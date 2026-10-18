"""Metadata queries a run sent to Athena: information_schema reads by kind, since a start time.

Usage: census.py WORK_GROUP SINCE_EPOCH_SECONDS [UNTIL_EPOCH_SECONDS]  ->  "<tables> <columns> <schemata> <catalog>"
`catalog` is the `compile --write-catalog` query (athena__get_catalog_relations), counted apart from
the per-relation reads. Queries on the catalog CENSUS_SKIP_CATALOG names (outside Glue, so on the
SQL path by design) are left out. Stops paging once it reaches queries older than SINCE.
"""
import datetime as dt
import os
import sys

import boto3

work_group, since = sys.argv[1], dt.datetime.fromtimestamp(int(sys.argv[2]), dt.timezone.utc)
until = dt.datetime.fromtimestamp(int(sys.argv[3]), dt.timezone.utc) if len(sys.argv) > 3 else None
skip = os.environ.get("CENSUS_SKIP_CATALOG")
athena = boto3.client("athena")
counts = {"tables": 0, "columns": 0, "schemata": 0, "catalog": 0}
token = None
while True:
    page = athena.list_query_executions(WorkGroup=work_group, MaxResults=50, **({"NextToken": token} if token else {}))
    ids = page.get("QueryExecutionIds", [])
    if not ids:
        break
    queries = athena.batch_get_query_execution(QueryExecutionIds=ids)["QueryExecutions"]
    for q in queries:
        submitted = q["Status"]["SubmissionDateTime"]
        if submitted < since or (until and submitted > until):
            continue
        sql = q["Query"].lower()
        if "information_schema" not in sql or (skip and f'"{skip.lower()}".information_schema' in sql):
            continue
        if "as table_database" in sql:
            counts["catalog"] += 1
        elif "information_schema.columns" in sql:
            counts["columns"] += 1
        elif "information_schema.tables" in sql:
            counts["tables"] += 1
        elif "information_schema.schemata" in sql:
            counts["schemata"] += 1
    token = page.get("NextToken")
    if not token or min(q["Status"]["SubmissionDateTime"] for q in queries) < since:
        break
print(" ".join(str(counts[k]) for k in ("tables", "columns", "schemata", "catalog")))
