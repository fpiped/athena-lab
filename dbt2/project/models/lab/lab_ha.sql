{{ config(materialized='table', table_type='hive', ha=true, partitioned_by=['status']) }}
select order_id, customer_id, order_date, status from {{ ref('stg_orders') }}
