# 09 nested-type-change

**Claim.** `ALTER TABLE CHANGE COLUMN` with the full column type cannot widen a field inside a struct
or an array of structs of an Iceberg table; the dotted field name can.

**Documented.** "Type promotion: Widens the type of a column, `struct` field, `map` key, `map` value,
or `list` element ... integer to big integer"
([Evolve Iceberg table schema](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-evolving-table-schema.html)).
The [CHANGE COLUMN](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-alter-table-change-column.html)
page has no nested example.

**Script.** Iceberg table `(id int, items array<struct<a:int,b:string>>, pt struct<x:int,y:string>, n int)`
with one row, then:

- `CHANGE COLUMN items items array<struct<a:bigint,b:string>>`
- `CHANGE COLUMN pt pt struct<x:bigint,y:string>`
- `CHANGE COLUMN pt.x x bigint`, `CHANGE COLUMN items.element.a a bigint`
- `ADD COLUMNS (pt.z string)`, `ADD COLUMNS (items.element.c string)`
- `CHANGE COLUMN n n bigint`

then `DESCRIBE` and a SELECT.

**Result** (2026-10-18, Athena engine version 3): REPRODUCED.

- Full-type widening of `items` and `pt`: `Cannot update type for nested type`.
- Dotted names widen both (`pt.x`, `items.element.a`) and add nested fields; top-level `n` widens.
  `DESCRIBE` then shows `bigint`; the row stays readable.
