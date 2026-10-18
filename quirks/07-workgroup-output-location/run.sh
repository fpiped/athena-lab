#!/usr/bin/env bash
# On a work group that enforces its settings, a ResultConfiguration.OutputLocation passed to
# StartQueryExecution is silently replaced by the work group's: the call succeeds and nothing says so,
# while a CTAS external_location on the same work group is rejected.
set -uo pipefail
QUIRK=07-workgroup-output-location
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
title "Work group output location override"
SQL="SELECT 1 AS one"
REQUESTED=$QS3/requested/
aws s3 rm --recursive --quiet "$QS3/"
silent=0

# run_with_location <work group>: start with an explicit output location, wait, show the full responses
run_with_location() {
  local wg=$1 start id state exec_json loc listed
  section "work group $(aws athena get-work-group --work-group "$wg" --query 'WorkGroup.Configuration.EnforceWorkGroupConfiguration' --output text | sed 's/True/enforcing/;s/False/not enforcing/')"
  echo "-- StartQueryExecution: QueryString=\"$SQL\", WorkGroup=<work group>, ResultConfiguration.OutputLocation=<requested>"
  start=$(aws athena start-query-execution --work-group "$wg" --query-string "$SQL" \
    --result-configuration "OutputLocation=$REQUESTED" --output json 2>&1)
  echo "StartQueryExecution response keys: $(jq -c 'keys' <<<"$start" 2>/dev/null || echo "$start")"
  id=$(jq -r .QueryExecutionId <<<"$start")
  while :; do
    state=$(aws athena get-query-execution --query-execution-id "$id" --query QueryExecution.Status.State --output text)
    case $state in SUCCEEDED|FAILED|CANCELLED) break;; esac; sleep 1
  done
  exec_json=$(aws athena get-query-execution --query-execution-id "$id" --output json)
  loc=$(jq -r .QueryExecution.ResultConfiguration.OutputLocation <<<"$exec_json")
  listed=$(aws s3 ls --recursive "$REQUESTED" | wc -l | tr -d ' ')
  echo "state: $state"
  echo "GetQueryExecution output location under the requested prefix: $([[ $loc == "$REQUESTED"* ]] && echo yes || echo "no, under the work group's location")"
  echo "objects written under the requested prefix: $listed"
  echo "GetQueryExecution fields (values elided): $(jq -c '.QueryExecution | del(.Query) | [paths(scalars)] | map(join(".")) ' <<<"$exec_json")"
  echo "fields mentioning override or enforce: $(jq -c '[.. | strings | select(test("overrid|enforc"; "i"))]' <<<"$exec_json")"
  LAST_STATE=$state LAST_HONOURED=$([[ $loc == "$REQUESTED"* ]] && echo yes || echo no)
  LAST_SIGNAL=$(jq -r '[.. | strings | select(test("overrid|enforc"; "i"))] | length' <<<"$exec_json")
}

expected "documented: with 'Override client-side settings' the work group's settings win over the client's (https://docs.aws.amazon.com/athena/latest/ug/workgroups-settings-override.html); a client that asked for a location has no signal that it was ignored"
run_with_location "$WG"
enforced="state $LAST_STATE, requested location honoured: $LAST_HONOURED, override signals: $LAST_SIGNAL"
actual "$enforced"
[[ $LAST_STATE == SUCCEEDED && $LAST_HONOURED == no && $LAST_SIGNAL == 0 ]] && silent=1
aws s3 rm --recursive --quiet "$QS3/"
run_with_location "$WG_OPEN"
open="state $LAST_STATE, requested location honoured: $LAST_HONOURED"
actual "$open"

section "contrast: CTAS with external_location on the enforcing work group"
expected "the same override, or the same silence"
q_show "CREATE TABLE ctas_loc WITH (external_location = '$QS3/ctas_loc/', format = 'PARQUET') AS SELECT 1 AS one"
ctas="$Q_STATE${Q_REASON:+: ${Q_REASON#*operation: }}"
actual "$ctas"
drop ctas_loc

aws s3 rm --recursive --quiet "$QS3/"
summary="enforcing: $enforced; open: $open; CTAS external_location on enforcing: $ctas"
if (( silent )); then verdict REPRODUCED "$summary"; else verdict "NOT REPRODUCED" "$summary"; fi
