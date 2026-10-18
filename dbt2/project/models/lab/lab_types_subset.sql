{{ config(materialized='table', table_type='hive') }}
select s, i from {{ ref('lab_types') }}
