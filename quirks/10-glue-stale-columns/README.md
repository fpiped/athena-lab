# 10 glue-stale-columns

**Claim.** After `ALTER TABLE DROP COLUMN` on an Iceberg table, the Glue table's
`StorageDescriptor.Columns` still lists the dropped column, so readers of the Glue schema see a column
Athena no longer has.

**Documented.** [ALTER TABLE DROP COLUMN](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-alter-table-drop-column.html)
says the column is removed; nothing about the Glue columns. The Iceberg Glue catalog keeps
historical columns with the parameter `iceberg.field.current=false`; readers that ignore the
parameter see them as current.

**Script.** Iceberg table `(a int, b string, c int)`; Glue columns before; `DROP COLUMN b`; then
`information_schema.columns`, `DESCRIBE` and `aws glue get-table` columns with their parameters.

**Result** (2026-10-18, Athena engine version 3): REPRODUCED.

- `information_schema` and `DESCRIBE`: `a, c`.
- Glue: `a, c, b`; `b` moved last with
  `iceberg.field.current=false, iceberg.field.id=2, iceberg.field.optional=true`.
