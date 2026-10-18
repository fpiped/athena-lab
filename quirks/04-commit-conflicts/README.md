# 04 commit-conflicts

**Claim.** Concurrent INSERTs into one Iceberg table fail on commit instead of retrying, the error
names no table, and the Iceberg properties that raise the retries cannot be set.

**Documented.** Appends do not conflict in Iceberg; a commit that loses the race is retried
(`commit.retry.num-retries`, default 4:
[Iceberg table properties](https://iceberg.apache.org/docs/latest/configuration/#table-behavior-properties)).
Athena accepts only a fixed list of Iceberg table properties
([Create Iceberg tables](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-creating-tables.html#querying-iceberg-table-properties)),
which has no `commit.retry.*`.

**Script.** a: 3 rounds of 16 concurrent `INSERT INTO t VALUES (<i>, <round>)` into one Iceberg table
(`ROUNDS`, `N` override); counts failures, rows and distinct errors. b: `CREATE TABLE ... TBLPROPERTIES
('table_type'='ICEBERG', 'commit.retry.num-retries'='10')` and `ALTER TABLE ... SET TBLPROPERTIES`
with `commit.retry.*`.

**Result** (2026-10-18, Athena engine version 3, two runs): REPRODUCED.

- a: 12/48 and 16/48 INSERTs failed; the rows of the failed ones are absent. Error, table name empty:
  `ICEBERG_COMMIT_ERROR: Failed to commit Iceberg update to the table: . If a data manifest file was generated at '<result location>-manifest.csv', you may need to manually clean the data from locations specified in the manifest. Athena will not delete data in your account.`
  MERGE conflicts (quirk 03) name the table (`... to table: <db>.<table>`).
- b: both statements fail with `Unsupported table property key: commit.retry.num-retries`.
