# Copy to env.sh (git-ignored) and fill in. Every script sources it through lib.sh.

# Credentials for the account below: a named profile, or leave AWS_PROFILE unset and export
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN.
export AWS_PROFILE=my-sandbox
export AWS_REGION=eu-west-1
# The scripts refuse to run against any other account.
export LAB_ACCOUNT_ID=123456789012

# Resources are named from the prefix: work groups and roles `<prefix>-...`, Glue databases
# `<prefix with underscores>_...`. setup.sh creates them; teardown.sh removes them.
export LAB_PREFIX=athena-lab
# An existing bucket; the lab writes under s3://$LAB_BUCKET/$LAB_S3_PREFIX/.
export LAB_BUCKET=my-bucket
export LAB_S3_PREFIX=athena-lab

# dbt2/: the clones used to assemble the stack (rebuild-stack.sh, build.sh).
export DBT_REPO=~/src/dbt              # github.com/dbt-labs/dbt
export ATHENA_DRIVER_REPO=~/src/athena # github.com/dbt-labs/athena

# Optional sections, 1 to run: an IAM role to assume, Python models on a Spark work group,
# Lake Formation (the caller must be a data lake administrator), S3 Tables (the account's
# S3 Tables integration with Glue must be enabled), Athena UDFs (needs Maven and a JDK).
export LAB_ASSUME_ROLE=1
export LAB_SPARK=1
export LAB_LAKE_FORMATION=0
export LAB_S3_TABLES=0
export LAB_UDF=0

# Any derived name can be overridden, e.g. to reuse resources that already exist:
# export LAB_WORK_GROUP=... LAB_ASSUME_ROLE_NAME=... LAB_LF_TAG_PREFIX=... (see lib.sh)

# Optional: the Cosmos WATCHER_AWS_ECS run (dbt2/ecs-e2e/), on your own Fargate cluster and a task
# definition running the image built from dbt2/linux/image/ (container name `dbt`).
# export LAB_COSMOS_REPO=~/src/astronomer-cosmos
# export LAB_ECS_CLUSTER=... LAB_ECS_TASK_DEFINITION=... LAB_ECS_LOG_GROUP=...
# export LAB_ECS_SUBNETS=subnet-a,subnet-b LAB_ECS_SECURITY_GROUPS=sg-x
