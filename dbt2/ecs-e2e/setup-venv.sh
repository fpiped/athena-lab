#!/usr/bin/env bash
# Build venv/ from requirements.lock (Airflow 3.1.8, the Amazon provider, pinned) plus Cosmos from a
# checkout with ExecutionMode.WATCHER_AWS_ECS (astronomer/astronomer-cosmos#3000): LAB_COSMOS_REPO.
source "$(cd "$(dirname "$0")/../.." && pwd)/lib.sh"
E="$DBT2/ecs-e2e"
: "${LAB_COSMOS_REPO:?set LAB_COSMOS_REPO to a checkout of astronomer-cosmos with WATCHER_AWS_ECS}"
uv venv --no-config -q --python 3.12 "$E/venv"
uv pip install --no-config -q --index-url https://pypi.org/simple --python "$E/venv/bin/python" -r "$E/requirements.lock"
uv pip install --no-config -q --index-url https://pypi.org/simple --python "$E/venv/bin/python" --no-deps -e "$LAB_COSMOS_REPO"
