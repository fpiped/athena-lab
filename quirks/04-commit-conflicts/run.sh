#!/usr/bin/env bash
# Concurrent INSERTs into one Iceberg table fail on commit conflicts instead of retrying, and the
# Iceberg commit.retry.* properties that would raise the retries cannot be set.
set -uo pipefail
QUIRK=04-commit-conflicts
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
title "Iceberg commit conflicts on concurrent INSERTs"
T=inserts T2=retries
ROUNDS=${ROUNDS:-3} N=${N:-16}
cleanup() { drop "$T" "$T2"; }
cleanup
q_must "CREATE TABLE $T (id int, round int) LOCATION '$(loc $T)' TBLPROPERTIES ('table_type'='ICEBERG')"

section "a. $N concurrent single-row INSERTs, $ROUNDS rounds"
expected "appends do not conflict logically; Iceberg retries a commit that loses the race (commit.retry.num-retries, default 4: https://iceberg.apache.org/docs/latest/configuration/#table-behavior-properties)"
show_sql "INSERT INTO $T VALUES (<i>, <round>)"
failed=0 total=0 reasons=""
for r in $(seq 1 "$ROUNDS"); do
  stmts=(); for i in $(seq 1 "$N"); do stmts+=("INSERT INTO $T VALUES ($i, $r)"); done
  q_par "${stmts[@]}"
  echo "round $r: $PAR_OK succeeded, $PAR_FAIL failed"
  failed=$((failed + PAR_FAIL)) total=$((total + N)); reasons+="$PAR_REASONS"$'\n'
done
rows=$(q_value "SELECT count(*) FROM $T")
actual "$failed/$total failed; $rows rows in the table"
sum_reasons <<<"$reasons" | sed 's/^/  /'
error=$(sum_reasons <<<"$reasons" | head -1 | sed 's/^[0-9]* //')
name_empty=$(grep -q 'to the table: *$' <<<"$error" && echo yes || echo no)
[[ -n $error ]] && echo "table name empty in the most frequent error: $name_empty"

section "b. commit.retry.* table properties"
expected "documented: only a predefined list of TBLPROPERTIES is allowed for Iceberg (https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-creating-tables.html#querying-iceberg-table-properties); commit.retry.* is not on it, so there is no way to raise the retries"
q_show "CREATE TABLE $T2 (id int) LOCATION '$(loc $T2)' TBLPROPERTIES ('table_type'='ICEBERG', 'commit.retry.num-retries'='10')"
create="$Q_STATE${Q_REASON:+: $Q_REASON}"
q_show "ALTER TABLE $T SET TBLPROPERTIES ('commit.retry.num-retries'='10', 'commit.retry.min-wait-ms'='500')"
alter="$Q_STATE${Q_REASON:+: $Q_REASON}"
actual "CREATE: $create"
actual "ALTER: $alter"

cleanup
summary="$failed/$total concurrent INSERTs failed${error:+ (\"$error\", table name empty: $name_empty)}; CREATE with commit.retry: $create; ALTER: $alter"
if (( failed > 0 )) || [[ $create == FAILED* && $alter == FAILED* ]]; then verdict REPRODUCED "$summary"; else verdict "NOT REPRODUCED" "$summary"; fi
