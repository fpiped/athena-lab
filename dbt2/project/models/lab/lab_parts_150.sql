{{ config(materialized='incremental', incremental_strategy='insert_overwrite', table_type='hive', partitioned_by=['d']) }}
select n as id, date_add('day', n, date '2024-01-01') as d
from unnest(sequence(1, 150)) as t(n)
