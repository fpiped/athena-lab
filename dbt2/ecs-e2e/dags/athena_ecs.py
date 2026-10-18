"""dbt 2 on Athena from the Cosmos WATCHER_AWS_ECS producer (airflow DAG). Settings from env.sh (LAB_ECS_*)."""
import os
from datetime import datetime

from cosmos import DbtDag, ExecutionConfig, ProjectConfig, RenderConfig
from cosmos.constants import ExecutionMode, LoadMode

env = os.environ
athena_ecs = DbtDag(
    dag_id="athena_ecs",
    start_date=datetime(2026, 9, 1),
    schedule=None,
    catchup=False,
    # the image's project, parsed with `dbt parse` (standalone.sh extracts it)
    project_config=ProjectConfig(manifest_path=os.path.join(os.path.dirname(__file__), "..", "manifest.json"), project_name="jaffle_shop"),
    render_config=RenderConfig(load_method=LoadMode.DBT_MANIFEST),
    execution_config=ExecutionConfig(execution_mode=ExecutionMode.WATCHER_AWS_ECS, dbt_project_path="/app/project"),
    operator_args={
        "cluster": env["LAB_ECS_CLUSTER"],
        "task_definition": env["LAB_ECS_TASK_DEFINITION"],
        "container_name": "dbt",
        "launch_type": "FARGATE",
        "network_configuration": {
            "awsvpcConfiguration": {
                "subnets": env["LAB_ECS_SUBNETS"].split(","),
                "securityGroups": env["LAB_ECS_SECURITY_GROUPS"].split(","),
                "assignPublicIp": env.get("LAB_ECS_PUBLIC_IP", "DISABLED"),
            }
        },
        "awslogs_group": env["LAB_ECS_LOG_GROUP"],
        # the task definition's awslogs-stream-prefix, then the container name
        "awslogs_stream_prefix": env.get("LAB_ECS_STREAM_PREFIX", "ecs/dbt") + "/dbt",
        "awslogs_region": env["AWS_REGION"],
    },
)
