#!/usr/bin/env bash
# ALTER TABLE CHANGE COLUMN cannot widen a field inside a struct or an array of structs of an Iceberg
# table with the full column type, although the Athena docs list int to bigint promotion for struct
# fields; the dotted field name works.
set -uo pipefail
QUIRK=09-nested-type-change
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
title "Iceberg nested type promotion"
T=nested
cleanup() { drop "$T"; }
cleanup
q_must "CREATE TABLE $T (id int, items array<struct<a:int,b:string>>, pt struct<x:int,y:string>, n int) LOCATION '$(loc $T)' TBLPROPERTIES ('table_type'='ICEBERG')"
q_must "INSERT INTO $T VALUES (1, ARRAY[CAST(ROW(1, 'b') AS ROW(a integer, b varchar))], CAST(ROW(1, 'y') AS ROW(x integer, y varchar)), 1)"

expected "documented: 'Type promotion: widens the type of a column, struct field, map key, map value, or list element ... integer to big integer' (https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-evolving-table-schema.html)"
fails=0 out=""
# try <label> <sql>: run an ALTER and record its outcome
try() {
  section "$1"; q_show "$2"
  out+="$1: $Q_STATE${Q_REASON:+ ($Q_REASON)}; "
}
try "widen a field of an array of structs" "ALTER TABLE $T CHANGE COLUMN items items array<struct<a:bigint,b:string>>"
[[ $Q_STATE == FAILED ]] && fails=$((fails + 1))
try "widen a struct field" "ALTER TABLE $T CHANGE COLUMN pt pt struct<x:bigint,y:string>"
[[ $Q_STATE == FAILED ]] && fails=$((fails + 1))
try "workaround: widen the struct field by its dotted name" "ALTER TABLE $T CHANGE COLUMN pt.x x bigint"
try "workaround: widen the array's struct field by its dotted name" "ALTER TABLE $T CHANGE COLUMN items.element.a a bigint"
try "contrast: add a struct field by its dotted name" "ALTER TABLE $T ADD COLUMNS (pt.z string)"
try "contrast: add a field to the array's struct" "ALTER TABLE $T ADD COLUMNS (items.element.c string)"
try "contrast: widen a top-level column" "ALTER TABLE $T CHANGE COLUMN n n bigint"
q_show "DESCRIBE $T"; q_rows | grep -E '^(items|pt|n)\\t' | sed 's/\\t/ /g'
q_show "SELECT * FROM $T"; actual "data still readable: $Q_STATE"

cleanup
if (( fails > 0 )); then verdict REPRODUCED "$out"; else verdict "NOT REPRODUCED" "$out"; fi
