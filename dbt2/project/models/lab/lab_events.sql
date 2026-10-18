{{ config(materialized='table', table_type='iceberg', event_time='ts') }}
select n as id, cast(date_add('day', -(n % 3), current_date) as timestamp) as ts
from unnest(sequence(1, 30)) as t(n)
