{{ config(materialized='incremental', incremental_strategy='append', table_type='hive', temp_schema=env_var('LAB_SCHEMA_TMP')) }}
select id from unnest(sequence(1, 5)) as t(id)
