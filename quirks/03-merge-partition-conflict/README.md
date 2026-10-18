# 03 merge-partition-conflict

**Claim.** Concurrent MERGEs into disjoint partitions of one Iceberg table fail on commit unless the
`ON` clause restricts the partition column. Production: 36/48 failed without, 0/48 with.

**Documented.** Iceberg checks a concurrent commit against the files the operation read
([Iceberg reliability](https://iceberg.apache.org/docs/latest/reliability/#concurrent-write-operations));
a MERGE that reads only its partition does not conflict with writes to other partitions. Athena
documents no MERGE concurrency limit
([MERGE INTO](https://docs.aws.amazon.com/athena/latest/ug/merge-into-statement.html)).

**Script.** Iceberg table partitioned by `part`, 8 partitions of 500 rows. Per round, 8 MERGEs start at
once, one per partition, each 1,000 source rows of its partition (500 matched, 500 new on the first
round). 6 rounds (48 statements) for each `ON` clause:

- `t.id = s.id AND t.part = s.part`
- `t.id = s.id AND t.part = '<literal>'`
- `t.id = s.id`

`PARTS` and `ROUNDS` override the counts.

**Result** (2026-10-18, Athena engine version 3, two runs): REPRODUCED.

- without a partition predicate: 42/48 failed in both runs (each round exactly one MERGE committed);
- `t.part = s.part`: 5/48 failed in both; `t.part = '<literal>'`: 6/48 and 7/48.

Every failure: `ICEBERG_COMMIT_ERROR: Failed to commit Iceberg update to table: <db>.target`. The
partition predicate cuts the failures but does not remove them, unlike the production measurement.
