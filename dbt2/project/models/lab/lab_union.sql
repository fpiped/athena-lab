{#- dbt_utils.union_relations casts the columns one side lacks: cast(null as <column.data_type>).
    map and struct columns are left out, as dbt-athena cannot cast them either. -#}
{{ config(materialized='table', table_type='hive') }}
{{ dbt_utils.union_relations(relations=[ref('lab_types'), ref('lab_types_subset')], exclude=['m', 'st']) }}
