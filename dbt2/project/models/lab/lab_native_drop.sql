{{ config(materialized='table', table_type='iceberg', native_drop=true) }}
select customer_id from {{ ref('stg_customers') }}
