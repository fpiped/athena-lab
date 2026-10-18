#!/usr/bin/env bash
# A snapshot-style MERGE whose source inlines window functions over a few million history rows and a
# correlated NOT EXISTS has failed in production with INTERNAL_ERROR_QUERY_ENGINE.
set -uo pipefail
QUIRK=02-heavy-merge-crash
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
title "Heavy snapshot MERGE"
KEYS=${KEYS:-1000}   # history rows: KEYS * KEYS ids, VERSIONS versions each (default 6M)
VERSIONS=${VERSIONS:-6}
ATTRS="a1 varchar, a2 varchar, a3 bigint, a4 double, a5 varchar, a6 date, a7 decimal(18,2), a8 varchar"
COLS="id, a1, a2, a3, a4, a5, a6, a7, a8, updated_at"
cleanup() { drop hist snap; }
cleanup

section "setup: history of $((KEYS * KEYS)) ids x $VERSIONS versions, snapshot of the versions up to 3"
q_must "CREATE TABLE hist WITH (table_type = 'ICEBERG', is_external = false, location = '$(loc hist)') AS
SELECT x * $KEYS + y AS id, 'name-' || CAST(y * v AS varchar) AS a1, CAST(x % 97 AS varchar) AS a2, CAST(y * v AS bigint) AS a3,
  CAST(x * v AS double) / 3 AS a4, IF(v % 2 = 0, NULL, 'flag-' || CAST(v AS varchar)) AS a5, DATE '2024-01-01' + v * INTERVAL '1' DAY AS a6,
  CAST(x + y + v AS decimal(18,2)) AS a7, to_hex(md5(to_utf8(CAST(x * y * v AS varchar)))) AS a8,
  CAST(TIMESTAMP '2024-01-01 00:00:00' + v * INTERVAL '1' DAY + y * INTERVAL '1' SECOND AS timestamp(6)) AS updated_at
FROM UNNEST(sequence(0, $KEYS - 1)) AS a(x) CROSS JOIN UNNEST(sequence(0, $KEYS - 1)) AS b(y) CROSS JOIN UNNEST(sequence(1, $VERSIONS)) AS c(v)"
q_must "CREATE TABLE snap WITH (table_type = 'ICEBERG', is_external = false, location = '$(loc snap)') AS
SELECT to_hex(md5(to_utf8(CAST(id AS varchar) || '|' || CAST(updated_at AS varchar)))) AS scd_id, $COLS,
  updated_at AS valid_from, CAST(NULL AS timestamp(6)) AS valid_to
FROM (SELECT *, row_number() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn FROM hist WHERE updated_at < TIMESTAMP '2024-01-04') WHERE rn = 1"
echo "history rows: $(q_value "SELECT count(*) FROM hist"), snapshot rows: $(q_value "SELECT count(*) FROM snap")"

# The source a snapshot run inlines: the latest version per id with its predecessor (window functions),
# new versions (correlated NOT EXISTS) as inserts, and the open rows they close as updates.
SOURCE="WITH ranked AS (
  SELECT h.*, row_number() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn,
    lag(updated_at) OVER (PARTITION BY id ORDER BY updated_at) AS prev_updated_at,
    count(*) OVER (PARTITION BY id) AS versions
  FROM hist h
), latest AS (
  SELECT * FROM ranked WHERE rn = 1
), insertions AS (
  SELECT to_hex(md5(to_utf8(CAST(l.id AS varchar) || '|' || CAST(l.updated_at AS varchar)))) AS scd_id, l.*, 'insert' AS change_type
  FROM latest l
  WHERE NOT EXISTS (SELECT 1 FROM snap s WHERE s.id = l.id AND s.updated_at >= l.updated_at)
), updates AS (
  SELECT s.scd_id, l.*, 'update' AS change_type
  FROM latest l JOIN snap s ON s.id = l.id AND s.valid_to IS NULL AND s.updated_at < l.updated_at
)
SELECT scd_id, $COLS, prev_updated_at, change_type FROM insertions
UNION ALL
SELECT scd_id, $COLS, prev_updated_at, change_type FROM updates"
INSERT_COLS="scd_id, $COLS, valid_from, valid_to"
INSERT_VALUES="x.scd_id, x.id, x.a1, x.a2, x.a3, x.a4, x.a5, x.a6, x.a7, x.a8, x.updated_at, x.updated_at, NULL"
MERGE_TAIL="ON t.scd_id = x.scd_id
WHEN MATCHED AND t.valid_to IS NULL AND x.change_type = 'update' THEN UPDATE SET valid_to = x.updated_at
WHEN NOT MATCHED AND x.change_type = 'insert' THEN INSERT ($INSERT_COLS) VALUES ($INSERT_VALUES)"

expected "the MERGE succeeds, or fails with a user-facing error (memory, timeout); INTERNAL_ERROR_QUERY_ENGINE is an engine fault"
results=""
# shape <label> <sql>: run one MERGE shape; the snapshot is restored after a success so each shape sees the same input
shape() {
  section "$1"; q_show "$2"
  results+="$1: $Q_STATE${Q_REASON:+ (${Q_REASON:0:120})}; "
  [[ $Q_STATE == SUCCEEDED ]] && q_must "DELETE FROM snap WHERE valid_from >= TIMESTAMP '2024-01-04'" \
    && q_must "UPDATE snap SET valid_to = NULL WHERE valid_to IS NOT NULL"
}
shape "1. source inlined as a subquery" "MERGE INTO snap t USING ($SOURCE) x
$MERGE_TAIL"
# shape 2 adds what a hard-delete snapshot run inlines: open rows whose id left the source (a second
# correlated NOT EXISTS) and a lead() over the snapshot to close superseded rows
SOURCE2="WITH ranked AS (
  SELECT h.*, row_number() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn,
    lag(updated_at) OVER (PARTITION BY id ORDER BY updated_at) AS prev_updated_at
  FROM hist h WHERE id % 10 <> 0
), latest AS (
  SELECT * FROM ranked WHERE rn = 1
), current_snap AS (
  SELECT s.*, lead(valid_from) OVER (PARTITION BY id ORDER BY valid_from) AS next_valid_from FROM snap s
), insertions AS (
  SELECT to_hex(md5(to_utf8(CAST(l.id AS varchar) || '|' || CAST(l.updated_at AS varchar)))) AS scd_id, l.*, 'insert' AS change_type
  FROM latest l
  WHERE NOT EXISTS (SELECT 1 FROM current_snap s WHERE s.id = l.id AND s.updated_at >= l.updated_at)
), updates AS (
  SELECT s.scd_id, l.*, 'update' AS change_type
  FROM latest l JOIN current_snap s ON s.id = l.id AND s.valid_to IS NULL AND s.next_valid_from IS NULL AND s.updated_at < l.updated_at
), deletes AS (
  SELECT s.scd_id, s.id, s.a1, s.a2, s.a3, s.a4, s.a5, s.a6, s.a7, s.a8, TIMESTAMP '2024-02-01 00:00:00.000000' AS updated_at,
    s.updated_at AS prev_updated_at, 'delete' AS change_type
  FROM current_snap s
  WHERE s.valid_to IS NULL AND NOT EXISTS (SELECT 1 FROM latest l WHERE l.id = s.id)
)
SELECT scd_id, $COLS, prev_updated_at, change_type FROM insertions
UNION ALL
SELECT scd_id, $COLS, prev_updated_at, change_type FROM updates
UNION ALL
SELECT scd_id, $COLS, prev_updated_at, change_type FROM deletes"
shape "2. with hard deletes: second NOT EXISTS and a lead() over the snapshot" "MERGE INTO snap t USING ($SOURCE2) x
ON t.scd_id = x.scd_id
WHEN MATCHED AND t.valid_to IS NULL AND x.change_type IN ('update', 'delete') THEN UPDATE SET valid_to = x.updated_at
WHEN NOT MATCHED AND x.change_type = 'insert' THEN INSERT ($INSERT_COLS) VALUES ($INSERT_VALUES)"

cleanup
if grep -q INTERNAL_ERROR_QUERY_ENGINE <<<"$results"; then verdict REPRODUCED "$results"; else verdict "NOT REPRODUCED" "$results"; fi
