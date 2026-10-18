{{ config(materialized='table', table_type='iceberg') }}
select customer_id, number_of_orders from {{ ref('customers') }}
