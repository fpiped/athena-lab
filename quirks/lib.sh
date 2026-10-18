# Sourced by every quirk: the lab's lib.sh, the quirks database, and helpers to run Athena queries.
# A quirk sets QUIRK=<nn-slug> before sourcing; its tables live under $LAB_S3_ROOT/quirks/<nn-slug>/<table>/.

QUIRKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$QUIRKS/../lib.sh"
: "${QUIRK:?set QUIRK before sourcing quirks/lib.sh}"

QDB=${LAB_SCHEMA}_quirks
QS3=$LAB_S3_ROOT/quirks/$QUIRK
WG=$LAB_WORK_GROUP
WG_OPEN=$LAB_WORK_GROUP_OPEN

aws glue get-database --name "$QDB" >/dev/null 2>&1 || aws glue create-database --database-input "Name=$QDB" >/dev/null

# --- output
title()   { printf '# %s\n# %s, work group engine: %s\n' "$1" "$(date -u +%Y-%m-%d)" \
              "$(aws athena get-work-group --work-group "$WG" --query WorkGroup.Configuration.EngineVersion.EffectiveEngineVersion --output text)"; }
section() { printf '\n== %s\n' "$*"; }
# show_sql <sql>: the statement, cut after 700 characters; MASK, when set, is shown as <MASK_AS>
show_sql() {
  local s=$1
  [[ -n ${MASK:-} ]] && s=${s//"$MASK"/${MASK_AS:-<masked>}}
  if (( ${#s} > 700 )); then printf -- '-- statement (%d characters, first 700):\n%s ...\n' "${#s}" "${s:0:700}"
  else printf -- '-- statement:\n%s\n' "$s"; fi
}
expected() { printf 'expected: %s\n' "$*"; }
actual()   { printf 'actual:   %s\n' "$*"; }
# verdict <REPRODUCED|NOT REPRODUCED|SKIPPED (reason)> <summary>: the summary line, then the verdict as the last line
verdict()  { printf '\nsummary: %s\n%s\n' "$2" "$1"; }

# loc <table>: the table's S3 location
loc() { echo "$QS3/$1/"; }

# --- queries
# trim_reason: drop the per-query cleanup hint (it names the result location) so equal errors compare equal
trim_reason() { sed -E 's/\. (If a data manifest file was generated|You may need to manually clean).*//'; }
# q <sql> [work group]: run and wait. Sets Q_ID, Q_STATE, Q_REASON (StateChangeReason); returns 0 on SUCCEEDED.
q() {
  local sql=$1 wg=${2:-$WG} err delay=0.5
  Q_REASON="" Q_STATE=""
  if ! Q_ID=$(aws athena start-query-execution --work-group "$wg" --query-execution-context "Database=$QDB" \
      --query-string "$sql" --query QueryExecutionId --output text 2>&1); then
    Q_STATE=START_FAILED
    Q_REASON=$(tr '\n' ' ' <<<"$Q_ID" | sed -E 's/^ *An error occurred \(([A-Za-z]+)\) when calling the [A-Za-z]+ operation: /\1: /; s/ *$//')
    Q_ID=""
    return 1
  fi
  while :; do
    read -r Q_STATE <<<"$(aws athena get-query-execution --query-execution-id "$Q_ID" --query QueryExecution.Status.State --output text)"
    case $Q_STATE in SUCCEEDED|FAILED|CANCELLED) break;; esac
    sleep "$delay"; [[ $delay == 0.5 ]] && delay=1 || delay=2
  done
  [[ $Q_STATE == SUCCEEDED ]] && return 0
  Q_REASON=$(aws athena get-query-execution --query-execution-id "$Q_ID" --query QueryExecution.Status.StateChangeReason --output text | trim_reason)
  return 1
}
# q_show <sql> [work group]: show the statement, run it, print state and reason
q_show() { show_sql "$1"; q "$@"; local rc=$?; printf 'state:    %s%s\n' "$Q_STATE" "${Q_REASON:+: $Q_REASON}"; return $rc; }
# q_must <sql>: a setup statement; exit when it fails
q_must() { q "$@" || { echo "setup statement failed: $Q_STATE: $Q_REASON" >&2; show_sql "$1" >&2; exit 1; }; }
# q_rows: the last query's result rows as TSV (header row included for SELECT)
q_rows() {
  aws athena get-query-results --query-execution-id "$Q_ID" --output json \
    | jq -r '.ResultSet.Rows[] | [.Data[] | .VarCharValue // "NULL"] | @tsv'
}
# q_value <sql>: the first cell of the first data row
q_value() { q_must "$1"; q_rows | sed -n 2p | cut -f1; }

# q_par <sql>...: start every statement at once, wait for all. Sets PAR_OK, PAR_FAIL and
# PAR_REASONS (distinct failure reasons with counts, one per line).
q_par() {
  local tmp i ids=() n=$#
  tmp=$(mktemp -d)
  i=0
  for sql in "$@"; do
    ( aws athena start-query-execution --work-group "$WG" --query-execution-context "Database=$QDB" \
        --query-string "$sql" --query QueryExecutionId --output text >"$tmp/$i" 2>"$tmp/$i.err" ) &
    i=$((i + 1))
  done
  wait
  for ((i = 0; i < n; i++)); do [[ -s $tmp/$i ]] && ids+=("$(cat "$tmp/$i")"); done
  local states
  while :; do
    states=$(aws athena batch-get-query-execution --query-execution-ids "${ids[@]}" \
      --query 'QueryExecutions[].[Status.State, Status.StateChangeReason]' --output json)
    jq -e 'all(.[]; .[0] == "SUCCEEDED" or .[0] == "FAILED" or .[0] == "CANCELLED")' <<<"$states" >/dev/null && break
    sleep 2
  done
  PAR_OK=$(jq '[.[] | select(.[0] == "SUCCEEDED")] | length' <<<"$states")
  PAR_FAIL=$(( n - PAR_OK ))
  PAR_REASONS=$( { jq -r '.[] | select(.[0] != "SUCCEEDED") | "\(.[0]): \(.[1])"' <<<"$states" | trim_reason
                   for ((i = 0; i < n; i++)); do [[ -s $tmp/$i.err ]] && echo "START_FAILED: $(tr '\n' ' ' <"$tmp/$i.err")"; done
                 } | sort | uniq -c | sed 's/^ *//')
  rm -rf "$tmp"
}

# sum_reasons: merge PAR_REASONS lines ("<count> <reason>") gathered over several rounds, most frequent first
sum_reasons() { awk 'NF { n = $1; sub(/^[0-9]+ /, ""); c[$0] += n } END { for (r in c) print c[r], r }' | sort -rn; }

# drop <table>...: drop each table and empty its S3 prefix
drop() {
  for t in "$@"; do
    q "DROP TABLE IF EXISTS \`$t\`" || echo "drop $t: $Q_STATE: $Q_REASON" >&2
    aws s3 rm --recursive --quiet "$(loc "$t")"
  done
}
