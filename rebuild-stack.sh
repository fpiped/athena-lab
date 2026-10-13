#!/usr/bin/env bash
# Assemble the stack: dbt's main plus every open Athena part, and the Athena driver's main plus its
# open PRs, each in a worktree of the clones named in env.sh (stack/ and driver/).
# The parts are fetched from their pull requests. LAB_REF_<number>=<local ref> takes a local branch
# instead, e.g. LAB_REF_16376=my-branch to test commits not pushed yet.
# Conflicts between parts are resolved the same way each time (resolve()).
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
BASE=${BASE:-origin/main}   # a pinned main commit keeps a comparison against an earlier run fair

DBT=https://github.com/dbt-labs/dbt.git
DRIVER=https://github.com/dbt-labs/athena.git
# In merge order: <number> <repository>.
PARTS=(
  "16274 $DBT"   # Part 1: profile schema
  "16365 $DBT"   # Part 0: ADBC driver wiring
  "16367 $DBT"   # Part 2: adapter core wiring
  "16368 $DBT"   # Part 3: model config keys
  "16369 $DBT"   # Part 4: dbt-athena macro package
  "16374 $DBT"   # Part 5: metadata adapter
  "16370 $DBT"   # Part 8: unit tests
  "16375 $DBT"   # Part 9: init wizard
  "16376 $DBT"   # Part 6: AthenaAdapter methods through the driver
  "16452 $DBT"   # Part 7: Hive quoting and case folding
)
# 15: timestamps as microseconds (main fills them with milliseconds). LAB_DRIVER_PRS="19 20" leaves one out.
DRIVER_PRS=(${LAB_DRIVER_PRS:-15 19 20})

# fetch_ref <repo dir> <number> <remote url>: prints the ref to merge
fetch_ref() {
  local override="LAB_REF_$2"
  if [[ -n ${!override:-} ]]; then echo "${!override}"; return; fi
  git -C "$1" fetch -q "$3" "pull/$2/head:lab/pr-$2" --force
  echo "lab/pr-$2"
}

# reset_worktree <repo dir> <worktree> <branch> <base>: keeps target/ and its incremental build
reset_worktree() {
  if [[ -d $2 ]]; then
    git -C "$2" merge --abort 2>/dev/null || true
    git -C "$2" checkout -q -f -B "$3" "$4"
    git -C "$2" clean -fdq -e target
  else
    git -C "$1" worktree add -q -B "$3" "$2" "$4"
  fi
}

resolve() {  # $1 = part number just merged
  python3 - "$1" <<'PY'
import re, subprocess, sys, pathlib
part = sys.argv[1]
files = subprocess.run(["git", "diff", "--name-only", "--diff-filter=U"], capture_output=True, text=True).stdout.split()
keep_theirs = r"<<<<<<< [^\n]*\n.*?=======\n(.*?)>>>>>>> [^\n]*\n"
keep_ours = r"<<<<<<< [^\n]*\n(.*?)=======\n.*?>>>>>>> [^\n]*\n"
for f in files:
    p = pathlib.Path(f); s = p.read_text()
    if f.endswith("relation/mod.rs"):
        # union of both export lists
        def union(m):
            names = set()
            for side in (m.group(1), m.group(2)):
                names |= {n.strip() for n in side.replace("\n", " ").split(",") if n.strip()}
            return "    " + ", ".join(sorted(names, key=str.lower)) + ",\n"
        s = re.sub(r"<<<<<<< [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n", union, s, flags=re.S)
    elif part == "16374":
        s = re.sub(keep_theirs, r"\1", s, flags=re.S)   # Part 5's metadata adapter over Part 2's stubs
    elif part == "16375":
        s = re.sub(keep_ours, r"\1", s, flags=re.S)     # Part 1's profile schema over Part 9's copy
    elif part == "16376" and f.endswith(("adapter/adapter_impl.rs", "metadata/get_relation.rs")):
        s = re.sub(keep_theirs, r"\1", s, flags=re.S)   # Part 6's Glue reads over Part 5's SQL
    else:
        sys.exit(f"unhandled conflict in {f} merging part {part}")
    p.write_text(s)
    subprocess.run(["git", "add", f], check=True)
PY
  git -c commit.gpgsign=false commit -q --no-edit
}

git -C "$DBT_REPO" fetch -q origin main
reset_worktree "$DBT_REPO" "$LAB/stack" lab-stack "$BASE"
for entry in "${PARTS[@]}"; do
  read -r n url <<< "$entry"
  ref=$(fetch_ref "$DBT_REPO" "$n" "$url")
  if ! git -C "$LAB/stack" -c commit.gpgsign=false merge -q --no-edit "$ref" >/dev/null 2>&1; then (cd "$LAB/stack" && resolve "$n"); fi
  echo "merged $n ($ref)"
done
# Bench patch for a part that no longer compiles against main; drop it once the part is rebased.
# 16374 (Part 5): main added `state: Option<&State>` to `list_relations`; the other adapters pass None.
sed -i.bak 's/adapter.list_relations(&query_ctx, conn, db_schema, token_clone.clone())/adapter.list_relations(None, \&query_ctx, conn, db_schema, token_clone.clone())/' \
  "$LAB/stack/crates/dbt-adapter/src/metadata/athena/mod.rs" && rm -f "$LAB/stack/crates/dbt-adapter/src/metadata/athena/mod.rs.bak"
git -C "$LAB/stack" -c commit.gpgsign=false commit -q -am "bench patch: 16374 list_relations takes state" || true
if grep -rn --include='*.rs' 'todo!("Athena")' "$LAB/stack/crates" >/dev/null; then echo "todo!(Athena) left"; exit 1; fi
if grep -rln '^<<<<<<< ' "$LAB/stack/crates" >/dev/null; then echo "conflict markers left"; exit 1; fi

git -C "$ATHENA_DRIVER_REPO" fetch -q origin main
reset_worktree "$ATHENA_DRIVER_REPO" "$LAB/driver" lab-driver origin/main
for n in "${DRIVER_PRS[@]}"; do
  ref=$(fetch_ref "$ATHENA_DRIVER_REPO" "$n" "$DRIVER")
  if ! git -C "$LAB/driver" -c commit.gpgsign=false merge -q --no-edit "$ref" >/dev/null 2>&1; then
    # Both PRs add AWS SDK modules; the side merged first already requires the newer versions.
    conflicts=$(git -C "$LAB/driver" diff --name-only --diff-filter=U | tr '\n' ' ')
    [[ $conflicts == "go/go.mod " || $conflicts == "go/go.mod go/go.sum " ]] || { echo "unhandled driver conflict: $conflicts"; exit 1; }
    git -C "$LAB/driver" checkout --ours -- $conflicts && git -C "$LAB/driver" add $conflicts
    git -C "$LAB/driver" -c commit.gpgsign=false commit -q --no-edit
  fi
  echo "merged driver $n ($ref)"
done
git -C "$LAB/stack" log --oneline -1
