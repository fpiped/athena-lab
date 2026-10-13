{#- Timestamps read back through run_query, as macros read them (dbt-athena builds partition filters
    from these values): a literal and the same value as timestamp(6). -#}
{% macro lab_timestamp_probe() %}
  {% set t = run_query("select timestamp '2026-01-01 09:30:00.000' as ts, cast(timestamp '2026-01-01 09:30:00' as timestamp(6)) as ts6") %}
  {{ log("TS " ~ t.rows[0][0] ~ " | " ~ t.rows[0][1], info=True) }}
{% endmacro %}
