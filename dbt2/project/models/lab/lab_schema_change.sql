{{ config(materialized='incremental', incremental_strategy='append', table_type='hive', on_schema_change='append_new_columns') }}
select order_id, status{% if var('lab_extra_col') %}, 'added' as extra_col{% endif %}
from {{ ref('stg_orders') }}
{% if is_incremental() %} where order_id > (select max(order_id) from {{ this }}) {% endif %}
