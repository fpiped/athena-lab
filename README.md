# dbt2-athena-lab

A test bench for the AWS Athena adapter of dbt 2 (the Rust engine, [dbt-labs/dbt](https://github.com/dbt-labs/dbt)).
The adapter is being contributed as a series of pull requests that are not merged yet; this repository
assembles them on dbt's `main`, builds dbt with the Athena ADBC driver, and runs a matrix of checks
against a real AWS account. Each check reads the result back from Glue, S3, Lake Formation or Athena
rather than trusting an exit code.

Not an official dbt Labs project.

## What gets assembled

| | |
|---|---|
| dbt parts | [#16274](https://github.com/dbt-labs/dbt/pull/16274) profile schema, [#16365](https://github.com/dbt-labs/dbt/pull/16365) driver wiring, [#16367](https://github.com/dbt-labs/dbt/pull/16367) adapter core, [#16368](https://github.com/dbt-labs/dbt/pull/16368) model configs, [#16369](https://github.com/dbt-labs/dbt/pull/16369) dbt-athena macros, [#16374](https://github.com/dbt-labs/dbt/pull/16374) metadata adapter, [#16376](https://github.com/dbt-labs/dbt/pull/16376) adapter methods, [#16452](https://github.com/dbt-labs/dbt/pull/16452) Hive quoting, [#16370](https://github.com/dbt-labs/dbt/pull/16370) unit tests, [#16375](https://github.com/dbt-labs/dbt/pull/16375) init wizard |
| driver | [dbt-labs/athena#15](https://github.com/dbt-labs/athena/pull/15) more data types and correct timestamps, [#19](https://github.com/dbt-labs/athena/pull/19) AWS operations, [#20](https://github.com/dbt-labs/athena/pull/20) query statistics and connection options |

The tracking issue is [dbt-labs/dbt#16252](https://github.com/dbt-labs/dbt/issues/16252).

## Quick start

Requirements: git, a Rust toolchain (`rustup`; the dbt repository pins the version), Go, `protoc`,
the AWS CLI v2, `jq`, Python 3 with `boto3`, and an AWS account where you can create Athena work
groups and IAM roles.

```sh
git clone https://github.com/dbt-labs/dbt ~/src/dbt
git clone https://github.com/dbt-labs/athena ~/src/athena
cp env.example.sh env.sh      # account, region, prefix, bucket, clone paths, optional sections
setup/setup.sh                # work groups, roles and the rest, named from the prefix
./rebuild-stack.sh            # stack/ = dbt main + the parts, driver/ = athena main + its PRs
./build.sh                    # debug dbt binary with the driver next to it
./run-matrix.sh               # logs/results.txt, one log per step in logs/
setup/teardown.sh             # removes what setup.sh and the matrix created
```

The scripts refuse to run against an account other than `LAB_ACCOUNT_ID`. To test a branch of one of
the parts before pushing it, point that part at it: `LAB_REF_16376=my-branch ./rebuild-stack.sh`.

## What the matrix covers

- **Credentials**: default chain, named profile, static keys, assume role with an external ID (and its
  refusal), explicit endpoint, polling interval.
- **Materializations**: seeds (CSV upload, `seed_by_insert`, SSE upload arguments), views, tables
  (Hive and Iceberg, `ha` swaps), incremental (append, insert_overwrite with partitions, Iceberg merge,
  microbatch, 150-partition batching, `partitions_limit`), snapshots, `on_schema_change` including
  struct columns, `persist_docs` to Glue, view version expiry, temporary tables left behind.
- **Metadata**: relations, columns and schemas read from Glue as dbt-athena reads them; column types
  compared line by line with dbt-core 1.11 + dbt-athena 1.11 (`project/expected/`); dropped Iceberg
  columns; mixed-case names; `dbt_utils.union_relations`; a Glue catalog registered in Athena and a
  catalog outside Glue; no `information_schema` query outside the catalog query of `compile --write-catalog`.
- **Runtime**: the adapter response in `run_results.json`, Iceberg commit conflicts rerun, Ctrl-C
  stopping the running query, `dbt retry`, tests, source freshness, docs.
- **Optional sections** (`env.sh`): Python models on an Athena Spark work group (including timeout and
  Ctrl-C), Lake Formation tags and data cell filters, `catalogs.yml` v2 with S3 Tables, Athena UDFs.

## Other runs

- `run-scale.sh`: 250 generated models and 250 tests on 16 threads, twice.
- `reference-dbt1/`: dbt-core 1.11 + dbt-athena 1.11 on the same tables, to regenerate the reference.
- `linux/`: a linux/arm64 release build of the stack and the driver, and an image to run it on ECS.
- `ecs-e2e/`: an Airflow DAG running the image through Astronomer Cosmos `ExecutionMode.WATCHER_AWS_ECS`
  ([astronomer/astronomer-cosmos#3000](https://github.com/astronomer/astronomer-cosmos/pull/3000)), on
  a Fargate cluster of your own.

## Cost

Athena queries of the matrix scan kilobytes. The Spark section starts Athena Spark sessions, which are
billed by DPU-hour while they run; the S3 Tables and Lake Formation sections create no running resources.

## License

Apache-2.0.
