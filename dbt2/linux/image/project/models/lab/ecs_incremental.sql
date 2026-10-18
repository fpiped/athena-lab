{{ config(materialized='incremental', incremental_strategy='append', table_type='hive') }}
select order_id, status, cast(current_timestamp as timestamp) as loaded_at from {{ ref('stg_orders') }}
{% if is_incremental() %} where false {% endif %}
