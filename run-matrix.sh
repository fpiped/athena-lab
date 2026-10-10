#!/usr/bin/env bash
# End-to-end matrix for the dbt 2.0 Athena adapter, against the resources setup.sh creates.
# Each step checks its exit code against an expectation, and the checks read Glue / S3 / Athena /
# Lake Formation directly. Results go to logs/results.txt; one log per step in logs/.
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
python3 -c "import boto3" 2>/dev/null || { echo "census.py needs Python 3 with boto3" >&2; exit 1; }
BIN="$LAB/stack/target/debug/dbt"
# The static-keys target runs on the current credentials passed as keys.
if [[ -n ${AWS_PROFILE:-} ]]; then
  eval "$(aws configure export-credentials --profile "$AWS_PROFILE" --format env | sed 's/^export AWS_/export LAB_AWS_/')"
else
  export LAB_AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID LAB_AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY LAB_AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN:-}
fi
DB=$LAB_SCHEMA
DB_OPEN=$LAB_SCHEMA_OPEN
WG=$LAB_WORK_GROUP
on() { [[ ${!1} == 1 ]]; }   # on LAB_SPARK: is the optional section enabled
mkdir -p "$LAB/logs"; RES="$LAB/logs/results.txt"; : > "$RES"
MATRIX_START=$(date -u +%s)
cd "$LAB/project"

record() { printf '%-4s %-48s %s\n' "$1" "$2" "${3:-}" | tee -a "$RES"; }

# step NAME EXPECT -- dbt args...   EXPECT = ok | fail:<text the error must contain>
step() {
  local name=$1 expect=$2; shift 3
  "$BIN" "$@" --profiles-dir "${PROFILES_DIR:-.}" > "$LAB/logs/$name.log" 2>&1; local rc=$?
  local summary; summary=$(grep -E '^Summary:' "$LAB/logs/$name.log" | tail -1)
  if [[ $expect == ok ]]; then
    [[ $rc == 0 ]] && record PASS "$name" "$summary" || record FAIL "$name" "exit $rc; $(grep -m1 -E '\[error\]|panic' "$LAB/logs/$name.log" | cut -c1-160)"
  else
    local want=${expect#fail:}
    if [[ $rc != 0 ]] && grep -q -- "$want" "$LAB/logs/$name.log"; then record PASS "$name" "failed as expected: $want"; else record FAIL "$name" "exit $rc, expected failure containing '$want'"; fi
  fi
}

check() {  # check NAME CONDITION-DESCRIPTION ACTUAL EXPECTED
  [[ "$3" == "$4" ]] && record PASS "check: $1" "$2 = $3" || record FAIL "check: $1" "$2: got '$3', expected '$4'"
}

athena_scalar() {  # first cell of a query result
  local id; id=$(aws athena start-query-execution --work-group "$WG" --query-string "$1" --query QueryExecutionId --output text)
  for _ in $(seq 1 60); do
    case $(aws athena get-query-execution --query-execution-id "$id" --query QueryExecution.Status.State --output text) in
      SUCCEEDED) aws athena get-query-results --query-execution-id "$id" --query 'ResultSet.Rows[1].Data[0].VarCharValue' --output text; return;;
      FAILED|CANCELLED) echo "query-failed"; return;;
    esac; sleep 1; done; echo timeout
}
# without --query the CLI merges every page before printing; a --query runs once per page
partitions() { aws glue get-partitions --database-name "$1" --table-name "$2" --output json 2>/dev/null | jq '.Partitions | length'; }
versions()   { aws glue get-table-versions --database-name "$1" --table-name "$2" --query 'length(TableVersions)' --output text 2>/dev/null || echo 0; }
leftovers()  { aws glue get-tables --database-name "$1" --query 'TableList[?contains(Name, `__dbt_tmp`) || contains(Name, `__ha`) || contains(Name, `__bkp`) || contains(Name, `__tmp_not_partitioned`)].Name' --output text | wc -w | tr -d ' '; }

# --- connection and credentials
step debug_default_chain ok -- debug
[[ -n ${AWS_PROFILE:-} ]] && step debug_named_profile ok -- debug --target dev_profile
step debug_static_keys   ok -- debug --target dev_keys
step debug_assume_role   "fail:AssumeRole" -- debug --target assume_role
step debug_endpoint      ok -- debug --target endpoint
step debug_endpoint_bogus "fail:127.0.0.1:9" -- debug --target endpoint_bogus
step debug_bad_poll_interval "fail:poll_interval" -- debug --target bad_poll_interval

# --- project loading
step deps  ok -- deps
step parse ok -- parse
step ls    ok -- ls

# --- full build, then a second pass over every incremental / idempotent path
csvs() { aws s3 ls --recursive "$LAB_S3_ROOT/athena-results/tables/" | grep -c '__dbt_tmp.csv$'; }
CSV_BEFORE=$(csvs)
step seed_full_refresh ok -- seed --full-refresh
check seed_csv_cleanup "seed CSVs left in S3 by this run" "$(( $(csvs) - CSV_BEFORE ))" 0
check seed_column_types "lab_seed_types.amount type" "$(aws glue get-table --database-name $DB --name lab_seed_types --query 'Table.StorageDescriptor.Columns[?Name==`amount`].Type|[0]' --output text)" "decimal(10,2)"
NOT_HERE="lab_lf_tags lab_external lab_udf_view $(on LAB_UDF || echo lab_udf_table lab_udf_incremental)"
step build_1 ok -- build --full-refresh --exclude $NOT_HERE
# run_results: dbt-athena's adapter_response (code OK, rows written, bytes scanned) plus the query id
check adapter_response "orders adapter_response code / rows / scanned>0 / query id" "$(jq -r '.results[] | select(.unique_id=="model.jaffle_shop.orders") | .adapter_response | "\(.code) \(.rows_affected) \(.data_scanned_in_bytes > 0) \((.query_id // "") | length > 0)"' target/run_results.json)" "OK 99 true true"
step run_2   ok -- run --exclude $NOT_HERE
step schema_change_add_column ok -- run --select lab_schema_change --vars '{lab_extra_col: true}'
check schema_change "lab_schema_change has extra_col" "$(aws glue get-table --database-name $DB --name lab_schema_change --query 'length(Table.StorageDescriptor.Columns[?Name==`extra_col`])' --output text)" 1
# a struct column added by on_schema_change: the DDL needs Hive's struct<...>, not Trino's row(...)
step schema_change_struct_base ok -- run --full-refresh --select lab_schema_change_struct lab_schema_change_struct_ice
step schema_change_struct_add ok -- run --select lab_schema_change_struct lab_schema_change_struct_ice --vars '{lab_struct_col: true}'
for t in lab_schema_change_struct lab_schema_change_struct_ice; do
  check "struct_$t" "$t payload type in Glue" "$(aws glue get-table --database-name $DB --name $t --query 'Table.StorageDescriptor.Columns[?Name==`payload`].Type|[0]' --output text)" "struct<a:string,b:int>"
done
check parts_150 "lab_parts_150 Glue partitions" "$(partitions $DB lab_parts_150)" 150
check parts_150_rows "lab_parts_150 rows after two runs" "$(athena_scalar "select count(*) from $DB.lab_parts_150")" 150
check ha_partitions "lab_ha Glue partitions (distinct statuses)" "$(partitions $DB lab_ha)" "$(athena_scalar "select count(distinct status) from $DB.stg_orders")"
check ice_bucket_rows "lab_ice_bucket rows" "$(athena_scalar "select count(*) from $DB.lab_ice_bucket")" 40
check ice_bucket_type "lab_ice_bucket table_type" "$(aws glue get-table --database-name $DB --name lab_ice_bucket --query 'Table.Parameters.table_type' --output text)" ICEBERG
check microbatch_rows "lab_microbatch rows" "$(athena_scalar "select count(*) from $DB.lab_microbatch")" 30
check merge_rows "lab_merge_preds rows (no duplicates)" "$(athena_scalar "select count(*) - count(distinct order_id) from $DB.lab_merge_preds")" 0
check docs_table "lab_docs Glue description" "$(aws glue get-table --database-name $DB --name lab_docs --query 'Table.Description' --output text)" "Customers, persisted to Glue. Second line of the description."
check docs_column "lab_docs customer_id comment" "$(aws glue get-table --database-name $DB --name lab_docs --query 'Table.StorageDescriptor.Columns[?Name==`customer_id`].Comment|[0]' --output text)" "Primary key."
check docs_meta "lab_docs meta owner parameter" "$(aws glue get-table --database-name $DB --name lab_docs --query 'Table.Parameters.owner' --output text)" lab
check view_keep2 "lab_view_keep2 Glue versions" "$(versions $DB lab_view_keep2)" 2
check mixed_case "Lab_MixedCase exists lowercased" "$(aws glue get-table --database-name $DB --name lab_mixedcase --query 'Table.Name' --output text 2>/dev/null)" lab_mixedcase
check temp_leftovers "temporary tables left in Glue" "$(leftovers $DB)" 0

# --- snapshots, tests, freshness, docs
step snapshot_1 ok -- snapshot
step snapshot_2 ok -- snapshot
step test       ok -- test
step freshness  ok -- source freshness
step docs       ok -- docs generate
step catalog    ok -- compile --write-catalog

# --- Athena UDFs (Lambda $LAB_UDF_FUNCTION): tables and incremental work, views are an Athena limit
if on LAB_UDF; then
step udf_models ok -- run --select lab_udf_table lab_udf_incremental
check udf_values "lab_udf_table upper-cased and shifted" "$(athena_scalar "select count(*) from $DB.lab_udf_table where first_name_upper = upper(first_name_upper) and shifted_id > 1000")" 100
step udf_view_refused "fail:not registered" -- run --select lab_udf_view --vars '{lab_negative: true}'
fi

# --- Python models on the Spark work group: Spark and pandas DataFrames, Hive and Iceberg, incremental
if on LAB_SPARK; then
step python_models ok -- run --full-refresh --select lab_py_table lab_py_iceberg lab_py_incremental --vars '{lab_python: true}'
step python_incremental ok -- run --select lab_py_incremental --vars '{lab_python: true}'
check py_table "lab_py_table rows with given_name" "$(athena_scalar "select count(given_name) from $DB.lab_py_table")" 100
check py_iceberg "lab_py_iceberg rows / table_type" "$(athena_scalar "select count(*) from $DB.lab_py_iceberg")/$(aws glue get-table --database-name $DB --name lab_py_iceberg --query 'Table.Parameters.table_type' --output text)" "3/ICEBERG"
check py_incremental "lab_py_incremental rows after two runs" "$(athena_scalar "select count(*) from $DB.lab_py_incremental")" 104
fi

# --- Lake Formation: schema tags from the profile, then table / column tags and a data cell filter
#     that a second config (lab_lf_v2) must replace; read back from Lake Formation
if on LAB_LAKE_FORMATION; then
DB_LF=$LAB_SCHEMA_LF   # created by the run, so create_schema tags it
aws glue delete-database --name "$DB_LF" 2>/dev/null
# the profile's schema tag key, which dbt does not render from env_var()
LF_PROFILES="$LAB/logs/profiles-lf"; mkdir -p "$LF_PROFILES"
sed "s/LAB_LF_TAG_DOMAIN: lab/$LAB_LF_TAG_DOMAIN: lab/" profiles.yml > "$LF_PROFILES/profiles.yml"
LF_TABLE='{"Table":{"DatabaseName":"'$DB_LF'","Name":"lab_lf_tags"}}'
LF_FILTER='{"DataCellsFilter":{"TableCatalogId":"'$LAB_ACCOUNT_ID'","DatabaseName":"'$DB_LF'","TableName":"lab_lf_tags","Name":"'$LAB_LF_FILTER'"}}'
lf_table_tags()  { aws lakeformation get-resource-lf-tags --resource "$LF_TABLE" --output json | jq -r '[.LFTagsOnTable[] | "\(.TagKey)=\(.TagValues|join(","))"] | sort | join(" ")'; }
lf_column_tags() { aws lakeformation get-resource-lf-tags --resource "$LF_TABLE" --output json | jq -r '[.LFTagsOnColumns[]? | .Name as $c | .LFTags[] | select(.TagKey == "'$LAB_LF_TAG_PII'") | "\($c):\(.TagKey)=\(.TagValues|join(","))"] | join(" ")'; }
lf_filter()      { aws lakeformation list-data-cells-filter --table '{"CatalogId":"'$LAB_ACCOUNT_ID'","DatabaseName":"'$DB_LF'","Name":"lab_lf_tags"}' --output json | jq -r '[.DataCellsFilters[] | "\(.Name):\(.RowFilter.FilterExpression)"] | join(" ")'; }
lf_grantees()    { aws lakeformation list-permissions --resource "$LF_FILTER" --output json | jq -r '[.PrincipalResourcePermissions[] | .Principal.DataLakePrincipalIdentifier | split("/") | last] | join(" ")'; }
PROFILES_DIR=$LF_PROFILES step lf_database_tags ok -- run --select lab_default_naming --target dev_lf_db
check lf_database "schema LF-Tags" "$(aws lakeformation get-resource-lf-tags --resource '{"Database":{"Name":"'$DB_LF'"}}' --output json | jq -r '[.LFTagOnDatabase[] | "\(.TagKey)=\(.TagValues|join(","))"] | join(" ")')" "$LAB_LF_TAG_DOMAIN=lab"
PROFILES_DIR=$LF_PROFILES step lf_v1 ok -- run --select lab_lf_tags --target dev_lf_db --vars '{lab_lf: true}'
check lf_v1_table "lab_lf_tags table tags (domain inherited)" "$(lf_table_tags)" "$LAB_LF_TAG_DOMAIN=lab $LAB_LF_TAG_TIER=lab"
check lf_v1_columns "lab_lf_tags column tags" "$(lf_column_tags)" "email:$LAB_LF_TAG_PII=true"
check lf_v1_filter "lab_lf_tags data cell filter" "$(lf_filter)" "$LAB_LF_FILTER:id > 1"
check lf_v1_grant "$LAB_LF_FILTER SELECT grantees" "$(lf_grantees)" "$LAB_ASSUME_ROLE_NAME"
PROFILES_DIR=$LF_PROFILES step lf_v2 ok -- run --select lab_lf_tags --target dev_lf_db --vars '{lab_lf: true, lab_lf_v2: true}'
check lf_v2_table "lab_lf_tags table tags after v2" "$(lf_table_tags)" "$LAB_LF_TAG_DOMAIN=lab $LAB_LF_TAG_TIER=gold"
check lf_v2_columns "lab_lf_tags column tags after v2" "$(lf_column_tags)" ""
check lf_v2_filter "lab_lf_tags data cell filter after v2" "$(lf_filter)" "$LAB_LF_FILTER:id > 2"
check lf_v2_grant "$LAB_LF_FILTER SELECT grantees after v2" "$(lf_grantees)" "$LAB_ASSUME_ROLE_NAME"
fi

# --- catalogs.yml v2 (project-catalogs/): a Glue Iceberg catalog with external_volume, an S3 Tables catalog;
#     the second run rebuilds the S3 Tables table through Glue and appends to the incremental one
TB_ARN=arn:aws:s3tables:$AWS_REGION:$LAB_ACCOUNT_ID:bucket/$LAB_TABLE_BUCKET
S3T='"s3tablescatalog/'$LAB_TABLE_BUCKET'".'$DB
CATALOG_MODELS=$(on LAB_S3_TABLES && echo "lab_cat_glue lab_cat_s3t lab_cat_s3t_incremental" || echo lab_cat_glue)
on LAB_S3_TABLES && for t in lab_cat_s3t lab_cat_s3t_incremental; do aws s3tables delete-table --table-bucket-arn $TB_ARN --namespace $DB --name $t 2>/dev/null; done
( cd "$LAB/project-catalogs" && step catalogs_1 ok -- run --select $CATALOG_MODELS && step catalogs_2 ok -- run --select $CATALOG_MODELS )
check catalog_glue "lab_cat_glue table_type / location under external_volume" "$(aws glue get-table --database-name $DB --name lab_cat_glue --output json | jq -r '.Table | "\(.Parameters.table_type) \(.StorageDescriptor.Location | startswith("'$LAB_S3_ROOT'/lab-catalog-lake/'$DB'/lab_cat_glue/"))"')" "ICEBERG true"
if on LAB_S3_TABLES; then
check catalog_s3t_tables "S3 Tables tables in the namespace" "$(aws s3tables list-tables --table-bucket-arn $TB_ARN --namespace $DB --output json | jq -r '[.tables[].name] | sort | join(" ")')" "lab_cat_s3t lab_cat_s3t_incremental"
check catalog_s3t_rows "lab_cat_s3t rows after the rebuild" "$(athena_scalar "select count(*) from $S3T.lab_cat_s3t")" 3
check catalog_s3t_incremental "lab_cat_s3t_incremental rows after two appends" "$(athena_scalar "select count(*) from $S3T.lab_cat_s3t_incremental")" 6
fi

# --- Iceberg commit conflicts: six concurrent UPDATEs of one table conflict in Athena; the driver reruns
#     ICEBERG_COMMIT_ERROR (num_iceberg_retries 3 by default), the control target has no reruns
conflicts() {  # $1 target: prints "<failed runs> <ICEBERG_COMMIT_ERROR queries in the work group since the setup>"
  local since; since=$(date -u +%s)
  "$BIN" run-operation lab_iceberg_conflict_setup --target "$1" --profiles-dir . > "$LAB/logs/conflict_setup_$1.log" 2>&1
  local pids="" failed=0
  for n in 1 2 3 4 5 6; do "$BIN" run-operation lab_iceberg_conflict_update --args "{n: $n}" --target "$1" --profiles-dir . > "$LAB/logs/conflict_$1_$n.log" 2>&1 & pids="$pids $!"; done
  for pid in $pids; do wait $pid || failed=$((failed + 1)); done
  local ids; ids=$(aws athena list-query-executions --work-group "$WG" --max-results 50 --query 'QueryExecutionIds' --output text)
  # TZ=UTC: the CLI prints timestamps in the local offset
  local commit_errors; commit_errors=$(TZ=UTC aws athena batch-get-query-execution --query-execution-ids $ids --output json | jq --argjson since "$since" '[.QueryExecutions[] | select((.Status.SubmissionDateTime | .[0:19] | strptime("%Y-%m-%dT%H:%M:%S") | mktime) >= $since) | select((.Status.StateChangeReason // "") | contains("ICEBERG_COMMIT_ERROR"))] | length')
  echo "$failed $commit_errors"
}
# Six writers can still exhaust three reruns now and then (0-1 of 6 in practice, against 5 of 6 without
# reruns), so the check compares the two targets rather than expecting zero failures.
set -- $(conflicts dev); with_reruns=$1 conflicts_seen=$2
set -- $(conflicts no_iceberg_retries); without_reruns=$1
check iceberg_retries "failed runs with / without reruns (conflicts seen: $conflicts_seen)" "$([[ $conflicts_seen -gt 0 && $with_reruns -lt $without_reruns ]] && echo fewer || echo "$with_reruns/$without_reruns")" "fewer"

# --- Python models: the model timeout and Ctrl-C both stop the Spark calculation
if on LAB_SPARK; then
calc_state() {  # "<calculation state> <session state>" of the newest calculation whose code contains $1
  # list-sessions leaves terminated sessions out unless asked for them
  for sid in $(aws athena list-sessions --work-group "$LAB_WORK_GROUP_SPARK" --max-results 10 --query 'Sessions[].SessionId' --output text) \
             $(aws athena list-sessions --work-group "$LAB_WORK_GROUP_SPARK" --state-filter TERMINATED --max-results 10 --query 'Sessions[].SessionId' --output text); do
    for cid in $(aws athena list-calculation-executions --session-id "$sid" --max-results 10 --query 'Calculations[].CalculationExecutionId' --output text); do
      if aws athena get-calculation-execution-code --calculation-execution-id "$cid" --query CodeBlock --output text | grep -q "$1"; then
        printf '%s %s\n' "$(aws athena get-calculation-execution --calculation-execution-id "$cid" --query '[Status.SubmissionDateTime, Status.State]' --output text)" "$(aws athena get-session-status --session-id "$sid" --query Status.State --output text)"
      fi
    done
  done | sort | tail -1 | cut -f2-
}
calc_stopped() {  # waits up to a minute for the calculation and its session to settle
  local state
  for _ in 1 2 3 4 5 6; do state=$(calc_state "$1"); [[ $state == "CANCELED TERMINATED" ]] && break; sleep 10; done
  echo "$state"
}
step python_timeout "fail:did not complete within 20 seconds" -- run --select lab_py_timeout --vars '{lab_python: true}'
check python_timeout_stopped "lab_py_timeout calculation / session after the timeout" "$(calc_stopped 'lab_py_timeout: longer')" "CANCELED TERMINATED"
( "$BIN" run --select lab_py_sleep --vars '{lab_python: true}' --profiles-dir . > "$LAB/logs/python_ctrl_c.log" 2>&1 & pid=$!; sleep 45; kill -INT $pid; wait $pid ) 2>/dev/null
sleep 10
check python_ctrl_c "lab_py_sleep calculation / session after SIGINT" "$(calc_stopped 'lab_py_sleep: cancelled')" "CANCELED TERMINATED"
fi

# --- model and seed configs of real projects
CSV_BEFORE=$(csvs)
step seed_configs ok -- seed --select lab_seed_insert lab_seed_sse --full-refresh
check seed_by_insert "lab_seed_insert rows / no CSV staged" "$(athena_scalar "select count(*) from $DB.lab_seed_insert")/$(( $(csvs) - CSV_BEFORE ))" "3/0"
check seed_sse "lab_seed_sse rows (AES256 upload args)" "$(athena_scalar "select count(*) from $DB.lab_seed_sse")" 2
step seed_sse_bad_key "fail:KMS" -- seed --select lab_seed_sse_bad --vars '{lab_negative: true}'
step extra_configs_1 ok -- build --full-refresh --select lab_extra
step extra_configs_2 ok -- run --select lab_extra
check store_failures "stored failing rows of the accepted_values test" "$(athena_scalar "select count(*) > 0 from ${DB}_dbt_test__audit.accepted_values_lab_unique_tmp_id__false__1")" true
check unique_tmp "lab_unique_tmp rows after two merges" "$(athena_scalar "select count(*) from $DB.lab_unique_tmp")" 5
check temp_schema "lab_temp_schema rows / tables left in the temp schema" "$(athena_scalar "select count(*) from $DB.lab_temp_schema")/$(aws glue get-tables --database-name $LAB_SCHEMA_TMP --query 'length(TableList)' --output text 2>/dev/null || echo 0)" "10/0"
check partitions_limit "lab_parts_limit Glue partitions / rows" "$(partitions $DB lab_parts_limit)/$(athena_scalar "select count(*) from $DB.lab_parts_limit")" "30/300"

# --- retry of a failed node (dbt-labs/dbt#15667: retry does not restore --vars, so pass them)
step retry_setup "fail:KMS" -- seed --select lab_seed_sse_bad --vars '{lab_negative: true}'
step retry_reruns_failed "fail:KMS" -- retry --vars '{lab_negative: true}'

# --- the other two credential paths build something real
[[ -n ${AWS_PROFILE:-} ]] && step run_named_profile ok -- run --select stg_customers --target dev_profile
step run_static_keys   ok -- run --select stg_customers --target dev_keys
step run_endpoint      ok -- run --select stg_customers lab_default_naming --target endpoint
if on LAB_ASSUME_ROLE; then
step debug_assume_role_bad_ext "fail:AccessDenied" -- debug --target assume_role_bad_ext
step run_assume_role   ok -- run --select stg_customers stg_orders lab_default_naming --target assume_role_ok
fi

# --- skip_workgroup_check: the adapter takes the enforced work group for an open one
step skip_wg_check "fail:enforces a centralized output location" -- run --select lab_default_naming --target skip_wg_check

# --- Ctrl-C: the running Athena query is stopped, not left to finish
( "$BIN" run --select lab_slow --vars '{lab_negative: true}' --profiles-dir . > "$LAB/logs/ctrl_c.log" 2>&1 & pid=$!; sleep 25; kill -INT $pid; wait $pid ) 2>/dev/null
slow_state() {
  local ids; ids=$(aws athena list-query-executions --work-group "$WG" --max-results 25 --query 'QueryExecutionIds' --output text)
  aws athena batch-get-query-execution --query-execution-ids $ids --output json |
    jq -r '[.QueryExecutions[] | select(.Query | contains("sequence(1, 20000)"))] | sort_by(.Status.SubmissionDateTime) | last | .Status.State'
}
sleep 5
check ctrl_c "lab_slow query state after SIGINT" "$(slow_state)" CANCELLED

# --- work group without enforced output location: external_location and schema_table_unique naming
step open_seed ok -- seed --target open --full-refresh
step open_run  ok -- run --target open --select stg_customers stg_orders lab_external lab_ha
check external_location "lab_external Glue location" "$(aws glue get-table --database-name $DB_OPEN --name lab_external --query 'Table.StorageDescriptor.Location' --output text)" "$LAB_S3_ROOT/lab-open-data/lab_external_fixed"
check open_naming "lab_ha location has schema/table" "$(aws glue get-table --database-name $DB_OPEN --name lab_ha --query 'Table.StorageDescriptor.Location' --output text | grep -c "/lab-open-data/$DB_OPEN/lab_ha/")" 1
check open_leftovers "temporary tables left in the open schema" "$(leftovers $DB_OPEN)" 0
step open_default_naming ok -- run --target open_default_naming --select lab_default_naming
check default_naming "lab_default_naming location is schema/table/uuid" "$(aws glue get-table --database-name $DB_OPEN --name lab_default_naming --query 'Table.StorageDescriptor.Location' --output text | grep -cE "/lab-open-data/$DB_OPEN/lab_default_naming/[0-9a-f-]{36}$")" 1

# --- column metadata from Glue: types as dbt-athena 1.11 renders them (expected/column_types_dbt1.txt was
#     produced by dbt-core 1.11 + dbt-athena 1.11 on the same tables), dropped Iceberg columns, mixed case,
#     union_relations casts, a Glue catalog registered in Athena and a catalog outside Glue
step types_build ok -- run --select lab_types lab_types_ice
step types_probe ok -- run-operation lab_column_types --args '{names: [lab_types, lab_types_ice]}'
check column_types_as_dbt1 "lines differing from dbt-athena 1.11" "$(grep -oE '(COL [^ ]+ [^ ]+ dtype=.* is_string=[A-Za-z]+|CAST-OK [a-z_]+)' "$LAB/logs/types_probe.log" | sed 's/is_string=True/is_string=true/; s/is_string=False/is_string=false/' | diff - "$LAB/project/expected/column_types_dbt1.txt" | grep -c '^[<>]')" 0
step sync_ice_1 ok -- run --full-refresh --select lab_sync_ice
step sync_ice_2 ok -- run --select lab_sync_ice --vars '{lab_sync_step: 2}'
step sync_ice_3 ok -- run --select lab_sync_ice --vars '{lab_sync_step: 3}'
check sync_ice_glue "lab_sync_ice columns in Glue (name:current)" "$(aws glue get-table --database-name $DB --name lab_sync_ice --output json | jq -r '[.Table.StorageDescriptor.Columns[] | "\(.Name):\(.Parameters["iceberg.field.current"])"] | join(" ")')" "order_id:true status:true extra:false"
step sync_ice_probe ok -- run-operation lab_column_types --args '{names: [lab_sync_ice]}'
check sync_ice_columns "lab_sync_ice columns dbt reads" "$(grep -oE 'COL lab_sync_ice [a-z_]+' "$LAB/logs/sync_ice_probe.log" | cut -d' ' -f3 | xargs)" "order_id status"
step mixed_case_1 ok -- run --full-refresh --select lab_mixed_case
step mixed_case_2 ok -- run --select lab_mixed_case
check mixed_case_append "Lab_Mixed_Case rows after two appends" "$(athena_scalar "select count(*) from $DB.lab_mixed_case")" 198
step union ok -- run --select lab_types_subset lab_union
check union_relations "lab_union rows, nulls cast for the subset" "$(athena_scalar "select cast(count(*) as varchar) || '/' || cast(count_if(a is null) as varchar) from $DB.lab_union")" "2/1"
step glue_alias_catalog ok -- run-operation lab_columns_in --args "{database: $LAB_CATALOG_GLUE_ALIAS, name: lab_types_subset}"
check glue_alias_catalog "columns through a Glue catalog registered in Athena" "$(grep -oE "COL $LAB_CATALOG_GLUE_ALIAS lab_types_subset [a-z]+ dtype=[a-z]+" "$LAB/logs/glue_alias_catalog.log" | cut -d' ' -f4- | xargs)" "s dtype=string i dtype=int"
step non_glue_catalog "fail:LambdaFunction" -- run-operation lab_columns_in --args "{database: $LAB_CATALOG_NON_GLUE, name: anything}"

# --- metadata reads: relations, columns and schemas come from Glue; information_schema is read only
#     by the catalog query of `compile --write-catalog` (athena__get_catalog_relations)
check metadata_from_glue "information_schema queries since the start: tables columns schemata (catalog apart)" "$(CENSUS_SKIP_CATALOG=$LAB_CATALOG_NON_GLUE python3 "$LAB/census.py" "$WG" "$MATRIX_START" | cut -d' ' -f1-3)" "0 0 0"

echo; echo "PASS $(grep -c '^PASS' "$RES")  FAIL $(grep -c '^FAIL' "$RES")"
