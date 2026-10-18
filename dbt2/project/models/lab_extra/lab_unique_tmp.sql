{{ config(materialized='incremental', incremental_strategy='merge', table_type='iceberg', unique_key='id', unique_tmp_table_suffix=true) }}
select id, current_timestamp as loaded_at from unnest(sequence(1, 5)) as t(id)
