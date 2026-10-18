{% snapshot snap_orders_check %}
{{ config(target_schema=target.schema, unique_key='order_id', strategy='check', check_cols=['status']) }}
select * from {{ ref('stg_orders') }}
{% endsnapshot %}

{% snapshot snap_orders_ts_iceberg %}
{{ config(target_schema=target.schema, unique_key='order_id', strategy='timestamp', updated_at='updated_at', table_type='iceberg') }}
select order_id, status, cast(order_date as timestamp) as updated_at from {{ ref('stg_orders') }}
{% endsnapshot %}
