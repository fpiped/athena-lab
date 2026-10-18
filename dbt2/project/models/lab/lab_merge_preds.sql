{{ config(materialized='incremental', incremental_strategy='merge', table_type='iceberg', unique_key='order_id',
          merge_update_columns=['status'], incremental_predicates=["src.order_id > 0"]) }}
select order_id, status, order_date from {{ ref('stg_orders') }}
