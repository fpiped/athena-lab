{{ config(materialized='incremental', incremental_strategy='append', table_type='iceberg', on_schema_change='append_new_columns') }}
select order_id{% if var('lab_struct_col') %}, cast(row('x', 1) as row(a varchar, b integer)) as payload{% endif %}
from {{ ref('stg_orders') }}
{% if is_incremental() %} where order_id > (select max(order_id) from {{ this }}) {% endif %}
