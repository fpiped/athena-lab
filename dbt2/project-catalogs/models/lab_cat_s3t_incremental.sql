{{ config(materialized='incremental', incremental_strategy='append', catalog_name='tables') }}
select id from unnest(sequence(1, 3)) as t(id)
