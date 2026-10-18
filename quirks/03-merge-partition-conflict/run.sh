#!/usr/bin/env bash
# Concurrent MERGEs into disjoint partitions of one Iceberg table conflict unless the ON clause
# names the partition column.
set -uo pipefail
QUIRK=03-merge-partition-conflict
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
title "Concurrent MERGE into disjoint partitions"
T=target
PARTS=${PARTS:-8} ROUNDS=${ROUNDS:-6}
cleanup() { drop "$T"; }
cleanup
q_must "CREATE TABLE $T (id bigint, value int, part string) PARTITIONED BY (part) LOCATION '$(loc $T)' TBLPROPERTIES ('table_type'='ICEBERG')"
q_must "INSERT INTO $T SELECT p * 100000 + n, 0, 'p' || CAST(p AS varchar) FROM UNNEST(sequence(1, $PARTS)) AS a(p) CROSS JOIN UNNEST(sequence(1, 500)) AS b(n)"

# merge <partition> <round> <on>: 1000 source rows of one partition, 500 matching, 500 new on the first round
merge() {
  echo "MERGE INTO $T t USING (SELECT $1 * 100000 + n AS id, $2 AS value, 'p$1' AS part FROM UNNEST(sequence(1, 1000)) AS s(n)) s
ON $3
WHEN MATCHED THEN UPDATE SET value = s.value
WHEN NOT MATCHED THEN INSERT (id, value, part) VALUES (s.id, s.value, s.part)"
}
expected "MERGEs whose rows lie in disjoint partitions do not conflict (Iceberg validates conflicts against the files the operation read; Trino's Iceberg MERGE scans only the partitions its predicates select)"
round=0
for variant in with literal without; do
  case $variant in
    with) on="t.id = s.id AND t.part = s.part" label="t.part = s.part";;
    literal) on="t.id = s.id AND t.part = 'p@P@'" label="t.part = <literal>";;
    without) on="t.id = s.id" label="none";;
  esac
  section "partition predicate in ON: $label; $PARTS concurrent MERGEs (one per partition), $ROUNDS rounds"
  show_sql "$(merge '<p>' '<round>' "${on//@P@/<p>}")"
  failed=0 reasons=""
  for r in $(seq 1 "$ROUNDS"); do
    round=$((round + 1)); stmts=()
    for p in $(seq 1 "$PARTS"); do stmts+=("$(merge "$p" "$round" "${on//@P@/$p}")"); done
    q_par "${stmts[@]}"
    echo "round $r: $PAR_OK succeeded, $PAR_FAIL failed"
    failed=$((failed + PAR_FAIL)) reasons+="$PAR_REASONS"$'\n'
  done
  actual "$failed/$((PARTS * ROUNDS)) failed"
  sum_reasons <<<"$reasons" | sed 's/^/  /'
  eval "failed_$variant=\$failed reasons_$variant=\$reasons"
done

cleanup
total=$((PARTS * ROUNDS))
first=$(sum_reasons <<<"$reasons_without" | head -1 | sed 's/^[0-9]* //')
summary="without partition column in ON: $failed_without/$total failed${first:+ ($first)}; with t.part = s.part: $failed_with/$total; with t.part = literal: $failed_literal/$total"
if (( $failed_without > 0 && $failed_without > $failed_with )); then verdict REPRODUCED "$summary"; else verdict "NOT REPRODUCED" "$summary"; fi
