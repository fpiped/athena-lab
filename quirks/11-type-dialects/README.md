# 11 type-dialects

**Claim.** DDL takes Hive type names and DML returns Trino names, so a type read from
`information_schema` cannot be written back into CREATE or ALTER, and Iceberg DDL rejects `integer`,
which the docs list for DDL.

**Documented.** "Athena uses Apache Hive data type names for DDL statements ... For DML queries ...
Athena uses Trino data type names"; `INT, INTEGER` share one row for DDL and DML; `STRING` (DDL) maps to
`VARCHAR` (DML), `STRUCT<...>` to `ROW(...)`
([Data types](https://docs.aws.amazon.com/athena/latest/ug/data-types.html)).

**Script.** Iceberg table with `string`, `struct`, `array`, `map`, `int`; its
`information_schema.columns`; then the reported names in DDL (Iceberg CREATE with `varchar`,
`varchar(10)`, `integer`, `row(...)`; Iceberg ALTER ADD COLUMNS with `row(...)`, `varchar`; Hive
CREATE with `varchar`, `integer`; Hive CREATE with `string` and `struct`), and Hive names in DML
(`CAST(... AS string)`, `CAST(... AS struct<...>)`).

**Result** (2026-10-18, Athena engine version 3): REPRODUCED.

- `information_schema`: `varchar`, `row(x integer, y varchar)`, `array(varchar)`, `map(varchar, integer)`, `integer`.
- Iceberg CREATE: `varchar` gives `varchar type is specified without length: varchar`; `varchar(10)`
  gives `Unsupported Hive type: VARCHAR, use string instead`; `integer` gives
  `Error: type expected at the position 0 of 'integer' but 'integer' is found.` (Hive CREATE accepts
  `integer`); `row(...)` gives `line 1:43: mismatched input 'LOCATION'. Expecting: 'COMMENT', 'WITH', <EOF>`.
- Iceberg ALTER: `row(...)` gives `line 1:23: mismatched input 'COLUMNS'. Expecting: '.', 'ADD'`;
  `varchar` gives `Error parsing column with name vvarchar`.
- Hive CREATE with `varchar`: `ParseException line 1:47 mismatched input ')' expecting ( near 'varchar' in primitive type specification`.
- DML: `CAST('a' AS string)` gives `TYPE_MISMATCH: line 1:8: Unknown type: string`; `CAST(... AS struct<x:int>)`
  gives `InvalidRequestException: Queries of this type are not supported`.
