# 01 wide-merge

**Claim.** Wide statements fail on the size of the code Trino generates: the changed-rows join of a
dbt `check` snapshot (an `OR` of per-column comparisons) and a MERGE that updates every column of a
wide Iceberg table.

**Documented.** No column limit is documented for joins or MERGE. Trino compiles each filter and
projection into one JVM method, capped at 64 KB of bytecode
([JVM spec 4.7.3](https://docs.oracle.com/javase/specs/jvms/se17/html/jvms-4.html#jvms-4.7.3));
past it Trino fails with `Compiler failed` or `Query exceeded maximum columns`
([trinodb/trino#15848](https://github.com/trinodb/trino/issues/15848), MERGE on Iceberg; closed,
[#17342](https://github.com/trinodb/trino/pull/17342) raised the column count MERGE reaches).

**Script.** Two Iceberg tables of 400 columns (seven types cycling) and 1,000 rows, `sql.py`
generates the statements:

- a: `SELECT count(*) FROM src s JOIN tgt t ON s.id = t.id AND (<test c1> OR ... OR <test cN>)`,
  each test the expression dbt's check strategy writes
  (`t.c <> s.c OR (t.c IS NULL AND NOT s.c IS NULL) OR (NOT t.c IS NULL AND s.c IS NULL)`), at 100, 200
  and 400 columns, then bisected to 10 columns; the same join with `IS DISTINCT FROM` at 400.
- b: `MERGE INTO <N-column table> USING src ... UPDATE SET <every column> ... INSERT <every column>`
  at 100, 200, 300, 400, bisected to 25.

`MAXC` and `ROWS` override the width and row count.

**Result** (2026-10-18, Athena engine version 3): REPRODUCED.

- a: works at 137 columns, fails at 143:
  `GENERIC_INTERNAL_ERROR: io.airlift.bytecode.CompilationException: Error compiling class: io/trino/$gen/JoinFilterFunction_<id>`.
  `IS DISTINCT FROM` works at 400 (shorter code per column).
- b: works at 325 columns, fails at 350 with
  `[ErrorCode: INTERNAL_ERROR_QUERY_ENGINE] Amazon Athena experienced an internal error while executing this query. Please contact AWS support for further assistance.`
  The error does not name the cause.
