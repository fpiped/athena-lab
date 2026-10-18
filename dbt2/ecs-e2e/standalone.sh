#!/usr/bin/env bash
# Airflow 3.1.8 standalone for the Cosmos WATCHER_AWS_ECS run (DAG athena_ecs, port 8793).
# Watcher consumers only run under a real scheduler: `airflow dags test` deadlocks on them.
source "$(cd "$(dirname "$0")/../.." && pwd)/lib.sh"
E="$DBT2/ecs-e2e"
: "${LAB_ECS_CLUSTER:?}" "${LAB_ECS_TASK_DEFINITION:?}" "${LAB_ECS_SUBNETS:?}" "${LAB_ECS_SECURITY_GROUPS:?}" "${LAB_ECS_LOG_GROUP:?}"
export LAB_ECS_CLUSTER LAB_ECS_TASK_DEFINITION LAB_ECS_SUBNETS LAB_ECS_SECURITY_GROUPS LAB_ECS_LOG_GROUP
export AIRFLOW_HOME=$E/airflow AIRFLOW__CORE__DAGS_FOLDER=$E/dags AIRFLOW__CORE__LOAD_EXAMPLES=False PATH=$E/venv/bin:$PATH
export AIRFLOW__API__PORT=8793 AIRFLOW__CORE__EXECUTION_API_SERVER_URL=http://localhost:8793/execution/ AIRFLOW__DAG_PROCESSOR__REFRESH_INTERVAL=10
# the DAG renders from the image project's manifest
[[ -f $E/manifest.json ]] || (cd "$DBT2/linux/image/project" && "$DBT2/stack/target/debug/dbt" parse --profiles-dir . >/dev/null && cp target/manifest.json "$E/manifest.json")
exec airflow standalone
