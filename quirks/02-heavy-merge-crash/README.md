# 02 heavy-merge-crash

**Claim.** A snapshot-style MERGE whose source inlines window functions (`row_number`, `lag`) over a
few million history rows and a correlated `NOT EXISTS` fails with `INTERNAL_ERROR_QUERY_ENGINE`
(observed in production).

**Documented.** [MERGE INTO](https://docs.aws.amazon.com/athena/latest/ug/merge-into-statement.html)
accepts any query as the source; a resource limit should surface as a user error (for example
`Query exhausted resources at this scale factor`), not an internal one.

**Script.** Iceberg history table of 1M ids x 6 versions (6M rows, 10 columns), Iceberg snapshot
table of the latest version up to day 3 (1M rows, `scd_id`, `valid_from`, `valid_to`). Two MERGE
shapes on `ON t.scd_id = x.scd_id`, the snapshot restored between them:

1. source = latest version per id (`row_number`, `lag`, `count` over `PARTITION BY id`), inserts where
   `NOT EXISTS` a snapshot row as new, updates closing the open row;
2. as 1, plus hard deletes (a second correlated `NOT EXISTS`, from the snapshot to the source) and a
   `lead()` over the snapshot.

`KEYS` and `VERSIONS` override the size. Each MERGE scans 200 to 400 MB.

**Result** (2026-10-18, Athena engine version 3): NOT REPRODUCED. Both shapes succeed in about 12 s.
The production failure needs another ingredient (data shape, size, or concurrency); quirk 01 shows
`INTERNAL_ERROR_QUERY_ENGINE` for a MERGE past ~325 columns, a candidate cause if the production table
is wide.
