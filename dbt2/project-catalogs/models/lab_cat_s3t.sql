{{ config(materialized='table', catalog_name='tables') }}
select id, 'tables' as catalog from unnest(sequence(1, 3)) as t(id)
