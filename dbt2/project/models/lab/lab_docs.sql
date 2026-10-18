{{ config(materialized='table', persist_docs={'relation': true, 'columns': true}, meta={'owner': 'lab', 'tier': 2}) }}
select customer_id, first_name from {{ ref('stg_customers') }}
