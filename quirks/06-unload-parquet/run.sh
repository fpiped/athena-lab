#!/usr/bin/env bash
# UNLOAD to Parquet writes timestamps as INT96, top level and nested, and lowercases row field names
# even when the query's row type keeps their case.
set -uo pipefail
QUIRK=06-unload-parquet
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../lib.sh"
title "UNLOAD to Parquet: timestamp encoding and field-name case"
PY=$QUIRKS/venv/bin/python
if [[ ! -x $PY ]]; then
  uv venv --no-config -q "$QUIRKS/venv" &&
    VIRTUAL_ENV=$QUIRKS/venv uv pip install --no-config -q --index-url https://pypi.org/simple pyarrow boto3 || exit 1
fi
T=src
cleanup() { drop "$T"; aws s3 rm --recursive --quiet "$QS3/"; }
cleanup
TS="TIMESTAMP '2024-01-02 03:04:05.123456'"
q_must "CREATE TABLE $T (id int, ts timestamp, ts_arr array<timestamp>, ts_row struct<at:timestamp>, cc struct<camelCase:string,otherField:int>) LOCATION '$(loc $T)' TBLPROPERTIES ('table_type'='ICEBERG')"
q_must "INSERT INTO $T VALUES (1, $TS, ARRAY[$TS], CAST(ROW($TS) AS ROW(at timestamp(6))), CAST(ROW('x', 1) AS ROW(camelCase varchar, otherField integer)))"

section "1. nested timestamp(6) left as it is (top level cast to timestamp(3))"
q_show "UNLOAD (SELECT id, CAST(ts AS timestamp(3)) AS ts, ts_arr, ts_row FROM $T) TO '$QS3/nested6/' WITH (format = 'PARQUET')"
nested6="$Q_STATE${Q_REASON:+: $Q_REASON}"

section "2. every timestamp cast to timestamp(3), plus a row literal with camelCase field names"
SQL="UNLOAD (SELECT id, CAST(ts AS timestamp(3)) AS ts, CAST(ts_arr AS array(timestamp(3))) AS ts_arr, CAST(ts_row AS row(at timestamp(3))) AS ts_row, cc, CAST(ROW(1, 'y') AS ROW(\"camelCase\" integer, \"otherField\" varchar)) AS cc_lit FROM $T) TO '$QS3/out/' WITH (format = 'PARQUET')"
q_show "$SQL" || { cleanup; verdict "SKIPPED (UNLOAD failed: $Q_REASON)" "UNLOAD failed"; exit 0; }
q_show "SELECT typeof(CAST(ROW(1, 'y') AS ROW(\"camelCase\" integer, \"otherField\" varchar)))"
actual "row type in the query: $(q_rows | sed -n 2p)"
schema=$("$PY" -I "$HERE/parquet_schema.py" "$QS3/out/")
echo "Parquet schema of the unloaded file:"; echo "$schema" | sed 1d
expected "no encoding is documented for UNLOAD; Parquet deprecates INT96 (PARQUET-323) for INT64 TIMESTAMP(MILLIS|MICROS), which Trino's Iceberg writer uses; field names keep the case the query's row type carries"
int96=$(grep -c 'int96' <<<"$schema")
lower=$(grep -cE 'camelcase|otherfield' <<<"$schema")
actual "$int96 INT96 columns (top level, array element, row field); $lower lowercased field names (camelcase, otherfield in cc and cc_lit)"

cleanup
summary="INT96 timestamps: $int96 (top, array, row); lowercased field names: $lower; nested timestamp(6) UNLOAD: $nested6"
if (( int96 > 0 || lower > 0 )); then verdict REPRODUCED "$summary"; else verdict "NOT REPRODUCED" "$summary"; fi
