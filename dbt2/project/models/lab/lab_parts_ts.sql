{#- Partitioned on a timestamp: the second run rewrites 2 of the 4 partitions and adds 2, so dbt-athena
    reads the partition values back to build the Glue filter that deletes the rewritten ones. -#}
{{ config(materialized='incremental', incremental_strategy='insert_overwrite', table_type='hive', partitioned_by=['ts']) }}
select n as id, cast(date_add('hour', n, timestamp '2026-01-01 00:00:00') as timestamp(3)) as ts  -- Hive stores milliseconds
from unnest(sequence({{ 3 if is_incremental() else 1 }}, {{ 6 if is_incremental() else 4 }})) as t(n)
