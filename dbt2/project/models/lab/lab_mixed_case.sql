{#- An alias in mixed case: Glue stores it lowercased, so a second run has to find the table to append -#}
{{ config(materialized='incremental', incremental_strategy='append', table_type='hive', alias='Lab_Mixed_Case') }}
select order_id from {{ ref('stg_orders') }}
