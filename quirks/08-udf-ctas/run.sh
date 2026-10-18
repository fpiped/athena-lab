#!/usr/bin/env bash
# A Lambda UDF query cannot start with a WITH clause: USING EXTERNAL FUNCTION must come first, so a
# CTE placed before it (as SQL generators write it) fails to parse. Views cannot use UDFs at all.
set -uo pipefail
QUIRK=08-udf-ctas
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
title "Lambda UDF in CTAS, CTEs and views"
TABLES=(u_plain u_props u_iceberg u_cte_after u_cte_before u_props_cte_before)
cleanup() { q "DROP VIEW IF EXISTS u_view"; drop "${TABLES[@]}"; }
cleanup
if aws lambda get-function --function-name "$LAB_UDF_FUNCTION" >/dev/null 2>&1; then FN=$LAB_UDF_FUNCTION; have_fn=1
else FN=$LAB_PREFIX-no-such-udf; have_fn=0; echo "the lab UDF function does not exist (setup.sh with LAB_UDF=1 creates it): only the parser checks are meaningful"; fi
udf() { echo "USING EXTERNAL FUNCTION lab_upper(s VARCHAR) RETURNS VARCHAR LAMBDA '$1'"; }
U=$(udf "$FN")
CTE="WITH c AS (SELECT 'abc' AS s)"
expected "documented synopsis: USING EXTERNAL FUNCTION ... SELECT ... (https://docs.aws.amazon.com/athena/latest/ug/udf-query-syntax.html); a WITH clause is part of a query, so CTAS and a leading CTE should both compose with it. Views: 'You cannot use views with UDFs' (https://docs.aws.amazon.com/athena/latest/ug/udf-considerations-limitations.html)"
out=""
# try <label> <sql>: run and record; the Lambda name is shown as <fn>
MASK=$FN MASK_AS="<fn>"
try() { section "$1"; q_show "$2"; out+="$1: ${Q_STATE/START_FAILED/FAILED}; "; }
ok() { [[ $Q_STATE == SUCCEEDED ]]; }

try "SELECT (baseline)" "$U SELECT lab_upper('abc') AS v"
try "CTAS without properties" "CREATE TABLE u_plain AS $U SELECT lab_upper('abc') AS v"
try "CTAS WITH (format)" "CREATE TABLE u_props WITH (format = 'PARQUET') AS $U SELECT lab_upper('abc') AS v"
try "CTAS WITH (Iceberg)" "CREATE TABLE u_iceberg WITH (table_type = 'ICEBERG', is_external = false, location = '$(loc u_iceberg)') AS $U SELECT lab_upper('abc') AS v"
try "CTE after USING" "CREATE TABLE u_cte_after AS $U $CTE SELECT lab_upper(s) AS v FROM c"
try "CTE before USING (SELECT)" "$CTE $U SELECT lab_upper(s) AS v FROM c"; cte_reason=$Q_REASON
cte_failed=$([[ $Q_STATE == *FAILED && $Q_REASON == *"mismatched input 'USING'"* ]] && echo 1 || echo 0)
try "CTE before USING (CTAS)" "CREATE TABLE u_cte_before AS $CTE $U SELECT lab_upper(s) AS v FROM c"
try "CTE before USING (CTAS WITH (format))" "CREATE TABLE u_props_cte_before WITH (format = 'PARQUET') AS $CTE $U SELECT lab_upper(s) AS v FROM c"
try "view" "CREATE VIEW u_view AS $U SELECT lab_upper('abc') AS v"; view="$Q_STATE: $Q_REASON"

section "the parse error comes before any Lambda call"
MASK=$LAB_PREFIX-no-such-udf MASK_AS="<nonexistent function>"
q_show "$CTE $(udf "$MASK") SELECT lab_upper(s) AS v FROM c"
actual "with a nonexistent function: $Q_STATE${Q_REASON:+: $Q_REASON}"
unset MASK

cleanup
summary="${out}error: $cte_reason; view: $view"
if (( cte_failed )); then verdict REPRODUCED "$summary"
elif (( !have_fn )); then verdict "SKIPPED (lab UDF function missing)" "$summary"
else verdict "NOT REPRODUCED" "$summary"; fi
