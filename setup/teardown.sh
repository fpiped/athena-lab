#!/usr/bin/env bash
# Remove what setup.sh and the matrix created, named from env.sh. The account's S3 Tables integration
# (catalog s3tablescatalog) is left alone: other table buckets may use it.
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
say() { echo "teardown: $*"; }
read -r -p "Delete the $LAB_PREFIX resources in account $LAB_ACCOUNT_ID? [y/N] " answer
[[ $answer == y ]] || exit 1

# the Glue databases the runs created, then the S3 prefixes they write under
for db in $(aws glue get-databases --query "DatabaseList[?starts_with(Name, '$LAB_SCHEMA')].Name" --output text); do
  aws glue delete-database --name "$db" && say "database $db deleted"
done
for sub in athena-results athena-results-open spark-results lab-open-data lab-catalog-lake udf quirks; do
  aws s3 rm --recursive --quiet "$LAB_S3_ROOT/$sub/" && say "$LAB_S3_ROOT/$sub/ emptied"
done

# a Spark work group is deleted only without open sessions; the Python models leave theirs idle
# for reuse until Athena's idle timeout
open_sessions() { aws athena list-sessions --work-group "$LAB_WORK_GROUP_SPARK" --query 'Sessions[].SessionId' --output text 2>/dev/null; }
for sid in $(open_sessions); do aws athena terminate-session --session-id "$sid" >/dev/null; done
for _ in $(seq 1 24); do [[ -z $(open_sessions) ]] && break; sleep 5; done
for wg in "$LAB_WORK_GROUP" "$LAB_WORK_GROUP_OPEN" "$LAB_WORK_GROUP_SPARK"; do
  aws athena delete-work-group --work-group "$wg" --recursive-delete-option 2>/dev/null && say "work group $wg deleted"
done
for catalog in "$LAB_CATALOG_GLUE_ALIAS" "$LAB_CATALOG_NON_GLUE"; do
  aws athena delete-data-catalog --name "$catalog" >/dev/null 2>&1 && say "data catalog $catalog deleted"
done
aws lambda delete-function --function-name "$LAB_UDF_FUNCTION" 2>/dev/null && say "function $LAB_UDF_FUNCTION deleted"
for role in "$LAB_ASSUME_ROLE_NAME" "$LAB_SPARK_ROLE_NAME" "$LAB_UDF_ROLE_NAME"; do
  aws iam get-role --role-name "$role" >/dev/null 2>&1 || continue
  for policy in $(aws iam list-role-policies --role-name "$role" --query PolicyNames --output text); do
    aws iam delete-role-policy --role-name "$role" --policy-name "$policy"
  done
  for arn in $(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "$role" --policy-arn "$arn"
  done
  aws iam delete-role --role-name "$role" && say "role $role deleted"
done
for key in "$LAB_LF_TAG_TIER" "$LAB_LF_TAG_PII" "$LAB_LF_TAG_DOMAIN"; do
  aws lakeformation delete-lf-tag --tag-key "$key" 2>/dev/null && say "LF-Tag $key deleted"
done
arn=arn:aws:s3tables:$AWS_REGION:$LAB_ACCOUNT_ID:bucket/$LAB_TABLE_BUCKET
if aws s3tables get-table-bucket --table-bucket-arn "$arn" >/dev/null 2>&1; then
  for ns in $(aws s3tables list-namespaces --table-bucket-arn "$arn" --query 'namespaces[].namespace[0]' --output text); do
    for t in $(aws s3tables list-tables --table-bucket-arn "$arn" --namespace "$ns" --query 'tables[].name' --output text); do
      aws s3tables delete-table --table-bucket-arn "$arn" --namespace "$ns" --name "$t"
    done
    aws s3tables delete-namespace --table-bucket-arn "$arn" --namespace "$ns"
  done
  aws s3tables delete-table-bucket --table-bucket-arn "$arn" && say "table bucket $LAB_TABLE_BUCKET deleted"
fi
say "done"
