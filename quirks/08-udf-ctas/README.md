# 08 udf-ctas

**Claim.** `USING EXTERNAL FUNCTION` must start the query: a CTE placed before it fails to parse, in
SELECT and CTAS alike. CTAS works, with or without `WITH (...)` properties, when `USING` comes right
after `AS`. Views cannot use UDFs.

**Documented.** Synopsis `USING EXTERNAL FUNCTION ... SELECT ...`
([UDF query syntax](https://docs.aws.amazon.com/athena/latest/ug/udf-query-syntax.html)); "You cannot
use views with UDFs" ([UDF considerations](https://docs.aws.amazon.com/athena/latest/ug/udf-considerations-limitations.html)).
Neither page mentions CTAS or WITH clauses.

**Script.** Uses the lab UDF Lambda (`$LAB_UDF_FUNCTION`, method `lab_upper`; `setup.sh` with
`LAB_UDF=1`). Runs a baseline SELECT, `CREATE TABLE t AS USING ...`, `CREATE TABLE t WITH (format) AS
USING ...`, the Iceberg CTAS, `USING ... WITH c AS (...) SELECT`, `WITH c AS (...) USING ... SELECT`
as a SELECT and in both CTAS forms, and `CREATE VIEW ... AS USING ...`. Last, the CTE-first query with
a nonexistent Lambda name: the parse error comes before any Lambda call. Without the lab function only
that last check runs meaningfully.

**Result** (2026-10-18, Athena engine version 3): REPRODUCED for the CTE order; the CTAS forms work.

- Succeed: baseline, CTAS without and with properties, Iceberg CTAS, CTE after `USING`.
- CTE before `USING` (SELECT and both CTAS forms), also with a nonexistent function:
  `InvalidRequestException: line 1:31: mismatched input 'USING'. Expecting: '(', 'SELECT', 'TABLE', 'VALUES'`.
- View: `line 1:126: Function 'lab_upper' not registered` (documented).
