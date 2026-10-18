# quirks

One standalone reproduction per Athena quirk, for the Athena service team to rerun. Each `run.sh`
prints every statement, the expected behaviour (AWS docs or Trino) and the actual one, then a last line
`REPRODUCED`, `NOT REPRODUCED` or `SKIPPED (<reason>)`. A quirk that does not reproduce is reported as
such. Data is synthetic; each quirk drops its tables and S3 objects at the end.

| Quirk | Claim |
|---|---|
| [`01-wide-merge`](01-wide-merge/README.md) | wide check-snapshot joins and wide MERGEs fail |
| [`02-merge-partition-conflict`](02-merge-partition-conflict/README.md) | concurrent MERGEs into disjoint partitions conflict without a partition predicate in `ON` |
| [`03-commit-conflicts`](03-commit-conflicts/README.md) | concurrent INSERTs fail on commit; `commit.retry.*` cannot be set |
| [`04-timestamp-precision`](04-timestamp-precision/README.md) | Iceberg timestamps are `timestamp(6)`, which UNLOAD, Hive CTAS and views reject |
| [`05-unload-parquet`](05-unload-parquet/README.md) | UNLOAD writes INT96 timestamps and lowercases field names |
| [`06-workgroup-output-location`](06-workgroup-output-location/README.md) | an enforcing work group overrides a requested output location without a signal |
| [`07-udf-ctas`](07-udf-ctas/README.md) | a CTE cannot precede `USING EXTERNAL FUNCTION` |
| [`08-nested-type-change`](08-nested-type-change/README.md) | `CHANGE COLUMN` cannot widen a nested field with the full type |
| [`09-glue-stale-columns`](09-glue-stale-columns/README.md) | Glue keeps an Iceberg column after `DROP COLUMN` |
| [`10-type-dialects`](10-type-dialects/README.md) | DDL takes Hive type names, DML returns Trino names |

Every quirk reproduced on Athena engine version 3 in eu-west-1, in one run on 2026-10-18 and two on
2026-10-20, with the same outcome in each; the concurrency counts of 02 and 03 vary within the ranges
their READMEs give. Each README holds the exact errors.

## Running

Requirements: the root setup (`setup/setup.sh`: the work groups), `jq`, Python 3; `05` also needs `uv`
(it creates `quirks/venv/` with pyarrow and boto3); `07` needs the lab UDF function (`LAB_UDF=1`).

```sh
quirks/04-timestamp-precision/run.sh   # one quirk
quirks/run-all.sh                      # all; or run-all.sh 02 04
```

`run-all.sh` writes `results.txt` (one line per quirk: verdict and summary) and each quirk's output to
`logs/`; both are ignored. Tables live in the Glue database `<LAB_SCHEMA>_quirks` (created when
missing), under `$LAB_S3_ROOT/quirks/<quirk>/`; queries run on `$LAB_WORK_GROUP` (engine version 3,
enforced result location) unless a quirk says otherwise. `setup/teardown.sh` removes both.

`lib.sh` holds the helpers: `q` (run and wait, sets `Q_STATE` and `Q_REASON`, the
`StateChangeReason`), `q_par` (start N statements at once, count outcomes and distinct errors),
`drop` (table and S3 prefix).

Cost: each quirk scans kilobytes.
