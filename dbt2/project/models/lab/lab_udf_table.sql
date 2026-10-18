{{ config(materialized='table') }}
USING EXTERNAL FUNCTION lab_upper(s VARCHAR) RETURNS VARCHAR LAMBDA '{{ env_var('LAB_UDF_FUNCTION') }}',
      EXTERNAL FUNCTION lab_add(a INTEGER, b INTEGER) RETURNS INTEGER LAMBDA '{{ env_var('LAB_UDF_FUNCTION') }}'
SELECT customer_id, lab_upper(first_name) AS first_name_upper, lab_add(cast(customer_id as integer), 1000) AS shifted_id
FROM {{ ref('stg_customers') }}
