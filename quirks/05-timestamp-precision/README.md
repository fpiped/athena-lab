# 05 timestamp-precision

**Claim.** An Iceberg `timestamp` column is `timestamp(6)` in Athena, against the documented
millisecond precision, and the `(6)` makes UNLOAD to Parquet, Hive CTAS and views that expose it fail.

**Documented.** `TIMESTAMP`: "A calendar date and time of day with millisecond precision";
"`TIMESTAMP(3)` is equivalent to `TIMESTAMP`"
([Data types](https://docs.aws.amazon.com/athena/latest/ug/data-types.html)). The Iceberg types page
maps Iceberg `timestamp` to Athena `timestamp` with no precision note
([Iceberg data types](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-supported-data-types.html)).

**Script.** Iceberg table `(id int, ts timestamp)`, one row with `TIMESTAMP '2024-01-02 03:04:05.123456'`;
then `typeof`, `information_schema.columns`, `DESCRIBE`, the stored value, `UNLOAD ... (format =
'PARQUET')` with and without `CAST(ts AS timestamp(3))`, a view on the column (`DESCRIBE` and `typeof`
through it), a view with `CAST(ts AS timestamp(6))`, and a Parquet Hive CTAS (on the open work group:
the enforcing one rejects `external_location`).

**Result** (2026-10-18, Athena engine version 3): REPRODUCED.

- `typeof` and `information_schema`: `timestamp(6)`; `DESCRIBE`: `timestamp`. Microseconds kept:
  `2024-01-02 03:04:05.123456`.
- UNLOAD: `NOT_SUPPORTED: Incorrect timestamp precision for timestamp(6); the configured precision is MILLISECONDS; column name: ts`.
  With `CAST(ts AS timestamp(3))`: succeeds.
- Hive CTAS: the same `Incorrect timestamp precision` error.
- View on the column: created; `DESCRIBE` says `timestamp(3)`, `typeof` through it `timestamp(6)`.
  View with an explicit `timestamp(6)`: `Invalid column type for column ts: Unsupported Hive type: timestamp(6)`.
