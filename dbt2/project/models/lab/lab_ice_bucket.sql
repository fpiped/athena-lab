{{ config(materialized='table', table_type='iceberg', partitioned_by=['bucket(id, 4)'], force_batch=true) }}
select n as id, 'row_' || cast(n as varchar) as label from unnest(sequence(1, 40)) as t(n)
