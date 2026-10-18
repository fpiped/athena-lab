#!/usr/bin/env bash
# Create what the matrix needs, named from env.sh. Idempotent: what exists is left as it is.
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
IAM="$LAB/setup/iam"
on() { [[ ${!1} == 1 ]]; }
say() { echo "setup: $*"; }

# render <template>: the IAM document with the lab's names filled in
render() {
  python3 - "$1" <<'PY'
import os, sys
text = open(sys.argv[1]).read()
path = os.environ.get("LAB_S3_PREFIX", "")
values = {
    "ACCOUNT": os.environ["LAB_ACCOUNT_ID"], "REGION": os.environ["AWS_REGION"],
    "BUCKET": os.environ["LAB_BUCKET"], "S3_PATH": f"/{path}" if path else "",
    "SCHEMA": os.environ["LAB_SCHEMA"], "EXTERNAL_ID": os.environ["LAB_EXTERNAL_ID"],
    "WORK_GROUP": os.environ["LAB_WORK_GROUP"], "WORK_GROUP_OPEN": os.environ["LAB_WORK_GROUP_OPEN"],
    "WORK_GROUP_SPARK": os.environ["LAB_WORK_GROUP_SPARK"],
}
for key, value in values.items():
    text = text.replace(f"@{key}@", value)
print(text)
PY
}

# role <name> <trust template> [<inline policy template>]
role() {
  if aws iam get-role --role-name "$1" >/dev/null 2>&1; then say "role $1 exists"; return; fi
  aws iam create-role --role-name "$1" --assume-role-policy-document "$(render "$IAM/$2")" \
    --description "athena-lab ($LAB_PREFIX)" >/dev/null
  [[ -n ${3:-} ]] && aws iam put-role-policy --role-name "$1" --policy-name lab --policy-document "$(render "$IAM/$3")"
  say "role $1 created"
  NEW_ROLE=1
}

# work_group <name> <enforce> <output subpath> [<engine> <execution role arn>]
work_group() {
  if aws athena get-work-group --work-group "$1" >/dev/null 2>&1; then say "work group $1 exists"; return; fi
  local config="EnforceWorkGroupConfiguration=$2,PublishCloudWatchMetricsEnabled=false,ResultConfiguration={OutputLocation=$LAB_S3_ROOT/$3/}"
  [[ -n ${4:-} ]] && config="$config,EngineVersion={SelectedEngineVersion=$4}"
  [[ -n ${5:-} ]] && config="$config,ExecutionRole=$5"
  aws athena create-work-group --name "$1" --configuration "$config" --description "athena-lab ($LAB_PREFIX)"
  say "work group $1 created"
}

# data_catalog <name> <type> <parameters>
data_catalog() {
  if aws athena get-data-catalog --name "$1" >/dev/null 2>&1; then say "data catalog $1 exists"; return; fi
  aws athena create-data-catalog --name "$1" --type "$2" --parameters "$3" --description "athena-lab ($LAB_PREFIX)"
  say "data catalog $1 created"
}

if on LAB_LAKE_FORMATION && ! on LAB_ASSUME_ROLE; then
  echo "setup: the Lake Formation checks grant a data cell filter to the assume role: set LAB_ASSUME_ROLE=1" >&2
  exit 1
fi
NEW_ROLE=0
work_group "$LAB_WORK_GROUP" true athena-results "Athena engine version 3" ""
work_group "$LAB_WORK_GROUP_OPEN" false athena-results-open
# a Glue catalog registered in Athena (dbt-athena's cross-account path, here on the same account)
# and a catalog outside Glue (a connector that does not exist: the reads must take the SQL path)
data_catalog "$LAB_CATALOG_GLUE_ALIAS" GLUE "catalog-id=$LAB_ACCOUNT_ID"
data_catalog "$LAB_CATALOG_NON_GLUE" LAMBDA "function=arn:aws:lambda:$AWS_REGION:$LAB_ACCOUNT_ID:function:$LAB_PREFIX-does-not-exist"
# temp_schema must exist before the model that uses it runs
aws glue get-database --name "$LAB_SCHEMA_TMP" >/dev/null 2>&1 || { aws glue create-database --database-input "Name=$LAB_SCHEMA_TMP"; say "database $LAB_SCHEMA_TMP created"; }

on LAB_ASSUME_ROLE && role "$LAB_ASSUME_ROLE_NAME" assume-trust.json assume-policy.json
on LAB_SPARK && role "$LAB_SPARK_ROLE_NAME" spark-trust.json spark-policy.json
if on LAB_UDF; then
  role "$LAB_UDF_ROLE_NAME" lambda-trust.json
  aws iam attach-role-policy --role-name "$LAB_UDF_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
fi
# a new role takes a few seconds before Athena or Lambda accept it
[[ $NEW_ROLE == 1 ]] && { say "waiting for IAM"; sleep 15; }

on LAB_SPARK && work_group "$LAB_WORK_GROUP_SPARK" true spark-results "PySpark engine version 3" "arn:aws:iam::$LAB_ACCOUNT_ID:role/$LAB_SPARK_ROLE_NAME"

if on LAB_UDF && ! aws lambda get-function --function-name "$LAB_UDF_FUNCTION" >/dev/null 2>&1; then
  (cd "$LAB/udf" && mvn -q -s settings.xml package -DskipTests)
  # The jar is over Lambda's 50 MB limit for a direct upload, so it goes through S3. The Athena
  # federation SDK's Arrow needs java.nio opened on Java 17.
  aws s3 cp --quiet "$LAB/udf/target/lab-udf-1.0.jar" "$LAB_S3_ROOT/udf/lab-udf-1.0.jar"
  aws lambda create-function --function-name "$LAB_UDF_FUNCTION" --runtime java17 --architectures x86_64 \
    --handler lab.LabUdfHandler --memory-size 1024 --timeout 60 \
    --environment "Variables={JAVA_TOOL_OPTIONS=--add-opens=java.base/java.nio=ALL-UNNAMED}" \
    --role "arn:aws:iam::$LAB_ACCOUNT_ID:role/$LAB_UDF_ROLE_NAME" \
    --code "S3Bucket=$LAB_BUCKET,S3Key=${LAB_S3_PREFIX:+$LAB_S3_PREFIX/}udf/lab-udf-1.0.jar" >/dev/null
  say "function $LAB_UDF_FUNCTION created"
fi

if on LAB_LAKE_FORMATION; then
  # tag <key> <values...>: the values the lab_lf_tags model and the profile use
  tag() {
    local key=$1; shift
    if aws lakeformation get-lf-tag --tag-key "$key" >/dev/null 2>&1; then
      aws lakeformation update-lf-tag --tag-key "$key" --tag-values-to-add "$@" >/dev/null 2>&1 || true
    else
      aws lakeformation create-lf-tag --tag-key "$key" --tag-values "$@"
      say "LF-Tag $key created"
    fi
  }
  tag "$LAB_LF_TAG_TIER" lab gold
  tag "$LAB_LF_TAG_PII" true
  tag "$LAB_LF_TAG_DOMAIN" lab
fi

if on LAB_S3_TABLES; then
  if ! aws glue get-catalog --catalog-id s3tablescatalog >/dev/null 2>&1; then
    echo "setup: the account's S3 Tables integration with Glue (catalog s3tablescatalog) is not enabled;" >&2
    echo "       enable it in the S3 console (Table buckets > Integration with AWS analytics services) or set LAB_S3_TABLES=0" >&2
    exit 1
  fi
  arn=arn:aws:s3tables:$AWS_REGION:$LAB_ACCOUNT_ID:bucket/$LAB_TABLE_BUCKET
  aws s3tables get-table-bucket --table-bucket-arn "$arn" >/dev/null 2>&1 || { aws s3tables create-table-bucket --name "$LAB_TABLE_BUCKET" >/dev/null; say "table bucket $LAB_TABLE_BUCKET created"; }
  # dbt does not create S3 Tables namespaces
  aws s3tables get-namespace --table-bucket-arn "$arn" --namespace "$LAB_SCHEMA" >/dev/null 2>&1 || { aws s3tables create-namespace --table-bucket-arn "$arn" --namespace "$LAB_SCHEMA" >/dev/null; say "namespace $LAB_SCHEMA created"; }
fi
say "done"
