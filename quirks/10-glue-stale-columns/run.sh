#!/usr/bin/env bash
# After ALTER TABLE DROP COLUMN on an Iceberg table, the Glue table's StorageDescriptor.Columns still
# lists the dropped column, so Glue-based readers see a column Athena no longer has.
set -uo pipefail
QUIRK=10-glue-stale-columns
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
title "Glue columns after an Iceberg DROP COLUMN"
T=dropped
cleanup() { drop "$T"; }
cleanup
q_must "CREATE TABLE $T (a int, b string, c int) LOCATION '$(loc $T)' TBLPROPERTIES ('table_type'='ICEBERG')"
glue_columns() {
  aws glue get-table --database-name "$QDB" --name "$T" --output json \
    | jq -r '.Table.StorageDescriptor.Columns[] | "\(.Name) \(.Type) \(.Parameters // {} | to_entries | map("\(.key)=\(.value)") | join(","))"'
}
section "before"
glue_columns | sed 's/^/glue: /'

section "drop column b"
q_show "ALTER TABLE $T DROP COLUMN b"
expected "Glue lists what Athena lists: a, c (the Glue table is the catalog Athena and other engines read: https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-alter-table-drop-column.html)"
q_show "SELECT column_name FROM information_schema.columns WHERE table_schema = '$QDB' AND table_name = '$T' ORDER BY ordinal_position"
athena=$(q_rows | sed 1d | paste -sd, -)
q_show "DESCRIBE $T"; describe=$(q_rows | grep -v '^#' | cut -d'\' -f1 | grep -v '^$' | paste -sd, -)
glue=$(glue_columns)
echo "$glue" | sed 's/^/glue: /'
glue_names=$(cut -d' ' -f1 <<<"$glue" | paste -sd, -)
actual "information_schema: $athena; DESCRIBE: $describe; Glue StorageDescriptor.Columns: $glue_names"
b_param=$(grep '^b ' <<<"$glue" | cut -d' ' -f3)

cleanup
summary="after DROP COLUMN b: information_schema [$athena], Glue Columns [$glue_names]${b_param:+, b parameters: $b_param}"
if grep -q '^b ' <<<"$glue"; then verdict REPRODUCED "$summary"; else verdict "NOT REPRODUCED" "$summary"; fi
