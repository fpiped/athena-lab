{{ config(materialized='table', table_type='hive', partitioned_by=['p'], partitions_limit=10) }}
select id, cast(id % 30 as varchar) as p from unnest(sequence(1, 300)) as t(id)
