{#- Lake Formation: v1 then v2 (lab_lf_v2) must converge to each config; the database tag is inherited -#}
{%- set v2 = var('lab_lf_v2', false) -%}
{{ config(
    materialized='table',
    enabled=var('lab_lf', false),
    lf_tags_config={
        'enabled': true,
        'tags': {env_var('LAB_LF_TAG_TIER'): 'gold' if v2 else 'lab'},
        'tags_columns': {} if v2 else {env_var('LAB_LF_TAG_PII'): {'true': ['email']}},
        'inherited_tags': [env_var('LAB_LF_TAG_DOMAIN')],
    },
    lf_grants={'data_cell_filters': {'enabled': true, 'filters': {
        env_var('LAB_LF_FILTER'): {
            'row_filter': 'id > 2' if v2 else 'id > 1',
            'principals': [env_var('LAB_ASSUME_ROLE_ARN')],
        },
    }}},
) }}
select 1 as id, 'a@example.com' as email
union all select 2, 'b@example.com'
union all select 3, 'c@example.com'
