#!/usr/bin/env bash
# Regenerate project/expected/column_types_dbt1.txt with dbt-core 1.11 + dbt-athena 1.11, on the
# lab_types / lab_types_ice tables the matrix builds (run the matrix, or their two models, first).
set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib.sh"
cd "$DBT2/reference-dbt1"
[[ -x venv/bin/dbt ]] || { uv venv -q --python 3.12 venv && uv pip install -q --python venv/bin/python "dbt-core~=1.11.0" "dbt-athena~=1.11.0"; }
venv/bin/dbt run-operation lab_column_types --args '{names: [lab_types, lab_types_ice]}' --profiles-dir . |
  grep -oE '(COL [^ ]+ [^ ]+ dtype=.* is_string=[A-Za-z]+|CAST-OK [a-z_]+)' |
  sed 's/is_string=True/is_string=true/; s/is_string=False/is_string=false/' > "$DBT2/project/expected/column_types_dbt1.txt"
wc -l < "$DBT2/project/expected/column_types_dbt1.txt"
