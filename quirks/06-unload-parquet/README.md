# 06 unload-parquet

**Claim.** UNLOAD to Parquet writes timestamps as INT96, at top level and nested, and lowercases row
field names even when the query's row type keeps their case.

**Documented.** The UNLOAD page documents no Parquet encoding
([UNLOAD](https://docs.aws.amazon.com/athena/latest/ug/unload.html)). INT96 is deprecated in Parquet
([PARQUET-323](https://issues.apache.org/jira/browse/PARQUET-323)) in favour of INT64 `TIMESTAMP`
logical types, which Trino's Iceberg writer uses. Trino row types keep delimited field names
(`typeof` shows `row(camelCase integer, ...)`).

**Script.** Iceberg table with a top-level timestamp, `array<timestamp>`, `struct<at:timestamp>` and
`struct<camelCase:string,otherField:int>`. UNLOAD to Parquet with every timestamp cast to
`timestamp(3)` (`timestamp(6)` fails, see quirk 05), plus a literal
`CAST(ROW(1, 'y') AS ROW("camelCase" integer, "otherField" varchar))`. `parquet_schema.py` (pyarrow,
in `quirks/venv`) prints the written file's Parquet schema.

**Result** (2026-10-18, Athena engine version 3): REPRODUCED.

- The top-level timestamp, the array element and the struct field are `int96`.
- Field names `camelcase`, `otherfield` in both rows; the Glue struct is already lowercased by DDL,
  the literal row type is not.
- Nested `timestamp(6)` left uncast fails as at top level:
  `Incorrect timestamp precision for timestamp(6); the configured precision is MILLISECONDS; column name: ts_arr`.
