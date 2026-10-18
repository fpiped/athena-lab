{{ config(materialized='table', table_type='hive', enabled=(target.name == 'open'),
          external_location=env_var('LAB_S3_ROOT') ~ '/lab-open-data/lab_external_fixed') }}
select customer_id from {{ ref('stg_customers') }}
