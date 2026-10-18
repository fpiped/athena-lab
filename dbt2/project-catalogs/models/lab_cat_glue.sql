{{ config(materialized='table', catalog_name='lake') }}
select 1 as id, 'glue' as catalog
