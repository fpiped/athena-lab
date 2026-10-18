# Sourced by every script: loads env.sh (or the file LAB_ENV names), derives the resource names,
# checks the account. The LAB_* variables are exported because the dbt projects read them with env_var().

LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DBT2="$LAB/dbt2"
LAB_ENV=${LAB_ENV:-$LAB/env.sh}
if [[ ! -f $LAB_ENV ]]; then
  echo "$LAB_ENV is missing: copy env.example.sh to env.sh and fill it in" >&2
  exit 1
fi
# shellcheck source=env.example.sh
source "$LAB_ENV"

: "${AWS_REGION:?}" "${LAB_ACCOUNT_ID:?}" "${LAB_PREFIX:?}" "${LAB_BUCKET:?}"
export AWS_DEFAULT_REGION=$AWS_REGION
export DBT_ALLOW_EXPERIMENTAL_ADAPTERS=true DBT_SEND_ANONYMOUS_USAGE_STATS=false DISABLE_AUTO_DRIVER_REBUILD=1

u=${LAB_PREFIX//-/_}
export LAB_S3_ROOT="s3://$LAB_BUCKET${LAB_S3_PREFIX:+/$LAB_S3_PREFIX}"
export LAB_SCHEMA=${LAB_SCHEMA:-$u}
export LAB_SCHEMA_OPEN=${LAB_SCHEMA_OPEN:-${LAB_SCHEMA}_open}
export LAB_SCHEMA_LF=${LAB_SCHEMA_LF:-${LAB_SCHEMA}_lf}
export LAB_SCHEMA_TMP=${LAB_SCHEMA_TMP:-${LAB_SCHEMA}_tmp}
export LAB_SCHEMA_SCALE=${LAB_SCHEMA_SCALE:-${LAB_SCHEMA}_scale}
export LAB_WORK_GROUP=${LAB_WORK_GROUP:-$LAB_PREFIX}
export LAB_WORK_GROUP_OPEN=${LAB_WORK_GROUP_OPEN:-$LAB_PREFIX-open}
export LAB_WORK_GROUP_SPARK=${LAB_WORK_GROUP_SPARK:-$LAB_PREFIX-spark}
export LAB_ASSUME_ROLE_NAME=${LAB_ASSUME_ROLE_NAME:-$LAB_PREFIX-assume}
export LAB_ASSUME_ROLE_ARN="arn:aws:iam::$LAB_ACCOUNT_ID:role/$LAB_ASSUME_ROLE_NAME"
export LAB_EXTERNAL_ID=${LAB_EXTERNAL_ID:-$LAB_PREFIX}
export LAB_SPARK_ROLE_NAME=${LAB_SPARK_ROLE_NAME:-$LAB_PREFIX-spark-exec}
export LAB_UDF_FUNCTION=${LAB_UDF_FUNCTION:-$LAB_PREFIX-udf}
export LAB_UDF_ROLE_NAME=${LAB_UDF_ROLE_NAME:-$LAB_PREFIX-udf-exec}
export LAB_LF_TAG_PREFIX=${LAB_LF_TAG_PREFIX:-$u}
export LAB_LF_TAG_TIER=${LAB_LF_TAG_PREFIX}_tier LAB_LF_TAG_PII=${LAB_LF_TAG_PREFIX}_pii LAB_LF_TAG_DOMAIN=${LAB_LF_TAG_PREFIX}_domain
export LAB_LF_FILTER=${LAB_LF_FILTER:-${LAB_LF_TAG_PREFIX}_ids}
export LAB_TABLE_BUCKET=${LAB_TABLE_BUCKET:-$LAB_PREFIX-tables}
export LAB_CATALOG_GLUE_ALIAS=${LAB_CATALOG_GLUE_ALIAS:-${u}_glue_alias}
export LAB_CATALOG_NON_GLUE=${LAB_CATALOG_NON_GLUE:-${u}_non_glue}
export LAB_ACCOUNT_ID AWS_REGION
for flag in LAB_ASSUME_ROLE LAB_SPARK LAB_LAKE_FORMATION LAB_S3_TABLES LAB_UDF; do export "$flag=${!flag:-0}"; done

account=$(aws sts get-caller-identity --query Account --output text) || exit 1
if [[ $account != "$LAB_ACCOUNT_ID" ]]; then
  echo "the credentials are for account $account, env.sh names $LAB_ACCOUNT_ID: refusing to run" >&2
  exit 1
fi
