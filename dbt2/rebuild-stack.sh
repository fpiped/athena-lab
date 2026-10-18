#!/usr/bin/env bash
# Assemble the stack: dbt's main plus every open Athena part, and the Athena driver's main plus its
# open PRs, each in a worktree of the clones named in env.sh (stack/ and driver/).
# The parts are fetched from their pull requests. LAB_REF_<number>=<local ref> takes a local branch
# instead, e.g. LAB_REF_16376=my-branch to test commits not pushed yet.
# Conflicts between parts are resolved the same way each time (resolve()).
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
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
# 15: timestamps as microseconds (main fills them with milliseconds); 21: cancellation during a status call;
# 22: query statistics. LAB_DRIVER_PRS="19 20" leaves the others out.
DRIVER_PRS=(${LAB_DRIVER_PRS:-15 19 20 21 22})

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
reset_worktree "$DBT_REPO" "$DBT2/stack" lab-stack "$BASE"
for entry in "${PARTS[@]}"; do
  read -r n url <<< "$entry"
  ref=$(fetch_ref "$DBT_REPO" "$n" "$url")
  if ! git -C "$DBT2/stack" -c commit.gpgsign=false merge -q --no-edit "$ref" >/dev/null 2>&1; then (cd "$DBT2/stack" && resolve "$n"); fi
  echo "merged $n ($ref)"
done
# Bench patch for a part that no longer compiles against main; drop it once the part is rebased.
# 16374 (Part 5): main added `state: Option<&State>` to `list_relations`; the other adapters pass None.
sed -i.bak 's/adapter.list_relations(&query_ctx, conn, db_schema, token_clone.clone())/adapter.list_relations(None, \&query_ctx, conn, db_schema, token_clone.clone())/' \
  "$DBT2/stack/crates/dbt-adapter/src/metadata/athena/mod.rs" && rm -f "$DBT2/stack/crates/dbt-adapter/src/metadata/athena/mod.rs.bak"
git -C "$DBT2/stack" -c commit.gpgsign=false commit -q -am "bench patch: 16374 list_relations takes state" || true
if grep -rn --include='*.rs' 'todo!("Athena")' "$DBT2/stack/crates" >/dev/null; then echo "todo!(Athena) left"; exit 1; fi
if grep -rln '^<<<<<<< ' "$DBT2/stack/crates" >/dev/null; then echo "conflict markers left"; exit 1; fi

resolve_driver() {  # conflicts between the driver PRs, resolved the same way each time
  python3 - <<'PY'
import re, subprocess, sys, pathlib
files = subprocess.run(["git", "diff", "--name-only", "--diff-filter=U"], capture_output=True, text=True).stdout.split()
block = re.compile(r"<<<<<<< [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n", re.S)
def statement(m):
    ours, theirs = m.group(1), m.group(2)
    # 21 moves the stop into stopQuery, 22 makes waitForQuery also return the execution
    if ours.strip() == "return s.stopQuery(ctx, execID)" and "StopQueryExecution" in theirs:
        return "\t\t\treturn nil, s.stopQuery(ctx, execID)\n"
    if "if ctx.Err() != nil" in ours and theirs.strip() == "return nil, adbc.Error{":
        return ours.replace("return s.stopQuery(ctx, execID)", "return nil, s.stopQuery(ctx, execID)").replace("\t\t\treturn adbc.Error{", "\t\t\treturn nil, adbc.Error{")
    # 20 adds the poll interval constant above waitForQuery, whose signature 22 changes
    if "const defaultPollInterval" in ours + theirs and "(*types.QueryExecution, error)" in ours + theirs:
        const = re.search(r"// defaultPollInterval.*?const defaultPollInterval = [^\n]*\n\n", ours + theirs, re.S).group(0)
        new = re.search(r"// waitForQuery polls.*?\(\*types.QueryExecution, error\) \{\n", ours + theirs, re.S).group(0)
        return const + new
    sys.exit("unhandled statement.go conflict")
for f in files:
    p = pathlib.Path(f)
    if f in ("go/go.mod", "go/go.sum", "README.md"):
        # go.mod: the side merged first already requires the newer SDK versions
        subprocess.run(["git", "checkout", "--ours", "--", f], check=True)
    elif f == "go/athena_database.go":
        p.write_text(block.sub(lambda m: m.group(1) + m.group(2), p.read_text()))  # both test hooks
    elif f == "go/driver_test.go":
        # 20 and 22 each add an integration test at the same place: keep both
        p.write_text(block.sub(lambda m: m.group(1) + "}\n\n" + m.group(2), p.read_text()))
    elif f == "go/statement.go":
        p.write_text(block.sub(statement, p.read_text()))
    else:
        sys.exit(f"unhandled driver conflict in {f}")
    subprocess.run(["git", "add", f], check=True)
PY
  git -c commit.gpgsign=false commit -q --no-edit
}

git -C "$ATHENA_DRIVER_REPO" fetch -q origin main
reset_worktree "$ATHENA_DRIVER_REPO" "$DBT2/driver" lab-driver origin/main
for n in "${DRIVER_PRS[@]}"; do
  ref=$(fetch_ref "$ATHENA_DRIVER_REPO" "$n" "$DRIVER")
  if ! git -C "$DBT2/driver" -c commit.gpgsign=false merge -q --no-edit "$ref" >/dev/null 2>&1; then
    (cd "$DBT2/driver" && resolve_driver)
  fi
  echo "merged driver $n ($ref)"
done
git -C "$DBT2/stack" log --oneline -1
