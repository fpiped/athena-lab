{{ config(materialized='table', contract={'enforced': true}) }}
select cast(customer_id as integer) as customer_id, cast(first_name as varchar) as first_name from {{ ref('stg_customers') }}
