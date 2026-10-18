#!/usr/bin/env bash
# An Iceberg timestamp column is timestamp(6) in Athena, against the documented millisecond precision,
# and the (6) breaks UNLOAD to Parquet, Hive CTAS and views that expose a timestamp(6).
set -uo pipefail
QUIRK=05-timestamp-precision
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
title "Iceberg timestamp precision"
T=ts_ice V=ts_ice_view
cleanup() { q "DROP VIEW IF EXISTS $V"; q "DROP VIEW IF EXISTS ${V}_cast"; drop "$T" "${T}_hive"; aws s3 rm --recursive --quiet "$QS3/"; }
cleanup

q_must "CREATE TABLE $T (id int, ts timestamp) LOCATION '$(loc $T)' TBLPROPERTIES ('table_type'='ICEBERG')"
q_must "INSERT INTO $T VALUES (1, TIMESTAMP '2024-01-02 03:04:05.123456')"
hits=0

section "1. type reported for the column"
expected "timestamp with millisecond precision, i.e. timestamp(3) (Athena data types: 'TIMESTAMP(3) is equivalent to TIMESTAMP')"
q_show "SELECT typeof(ts) FROM $T"; typeof=$(q_rows | sed -n 2p)
q_show "SELECT data_type FROM information_schema.columns WHERE table_schema = '$QDB' AND table_name = '$T' AND column_name = 'ts'"; info=$(q_rows | sed -n 2p)
q_show "DESCRIBE $T"; desc=$(q_rows | grep '^ts' | sed 's/\\t/ /g')
actual "typeof: $typeof; information_schema: $info; DESCRIBE: $desc"
[[ $typeof == "timestamp(6)" ]] && hits=$((hits + 1))

section "2. microseconds written are kept"
expected "the docs' millisecond precision would truncate .123456 to .123"
q_show "SELECT CAST(ts AS varchar) FROM $T"; value=$(q_rows | sed -n 2p)
actual "$value"

section "3. UNLOAD to Parquet"
expected "UNLOAD writes any SELECT result (UNLOAD docs)"
q_show "UNLOAD (SELECT * FROM $T) TO '$QS3/unload/' WITH (format = 'PARQUET')"; unload="$Q_STATE${Q_REASON:+: $Q_REASON}"
actual "$unload"
[[ $Q_STATE == FAILED ]] && hits=$((hits + 1))
q_show "UNLOAD (SELECT id, CAST(ts AS timestamp(3)) AS ts FROM $T) TO '$QS3/unload3/' WITH (format = 'PARQUET')"
actual "with CAST(ts AS timestamp(3)): $Q_STATE"

section "4. a view selecting the column"
expected "the view is created; its catalog type matches what a query through it returns"
q_show "CREATE VIEW $V AS SELECT id, ts FROM $T"; create="$Q_STATE${Q_REASON:+: $Q_REASON}"
q_show "DESCRIBE $V"; view_type=$(q_rows | grep '^ts' | sed 's/\\t/ /g')
q_show "SELECT typeof(ts) FROM $V"; view_typeof=$(q_rows | sed -n 2p)
actual "CREATE VIEW: $create; DESCRIBE: $view_type; typeof through the view: $view_typeof"
q_show "CREATE VIEW ${V}_cast AS SELECT id, CAST(ts AS timestamp(6)) AS ts FROM $T"; create_cast="$Q_STATE${Q_REASON:+: $Q_REASON}"
actual "view with an explicit timestamp(6): $create_cast"
[[ $create_cast == FAILED* ]] && hits=$((hits + 1))

section "5. CTAS to a Hive (non-Iceberg) Parquet table"
expected "CTAS writes any SELECT result"
# the enforcing work group rejects external_location in CTAS, so this one runs on the open work group
q_show "CREATE TABLE ${T}_hive WITH (external_location = '$(loc ${T}_hive)', format = 'PARQUET') AS SELECT * FROM $T" "$WG_OPEN"
ctas="$Q_STATE${Q_REASON:+: $Q_REASON}"
actual "$ctas"

cleanup
summary="typeof=$typeof, value kept=$value; UNLOAD: $unload; view DESCRIBE $view_type vs typeof $view_typeof; view with CAST to timestamp(6): $create_cast; Hive CTAS: $ctas"
if (( hits > 0 )); then verdict REPRODUCED "$summary"; else verdict "NOT REPRODUCED" "$summary"; fi
