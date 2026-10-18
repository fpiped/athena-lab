{{ config(materialized='view', versions_to_keep=2) }}
select customer_id from {{ ref('stg_customers') }}
