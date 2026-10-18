{{ config(materialized='incremental', incremental_strategy='append', table_type='iceberg', on_schema_change='sync_all_columns') }}
{#- lab_sync_step 1: three columns; 2: `extra` dropped (Glue keeps it flagged iceberg.field.current=false); 3: same as 2 -#}
select order_id, status{% if var('lab_sync_step', 1) == 1 %}, 'x' as extra{% endif %}
from {{ ref('stg_orders') }}
{% if is_incremental() %} where order_id > (select max(order_id) from {{ this }}) - 1 {% endif %}
