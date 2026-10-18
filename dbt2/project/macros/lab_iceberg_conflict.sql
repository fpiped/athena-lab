{# Iceberg commit conflicts: concurrent UPDATEs of one table; the driver reruns ICEBERG_COMMIT_ERROR #}
{% macro lab_iceberg_conflict_setup() %}
  {% do run_query("drop table if exists " ~ target.schema ~ ".lab_iceberg_conflict") %}
  {% do run_query("create table " ~ target.schema ~ ".lab_iceberg_conflict with (table_type = 'ICEBERG', is_external = false, location = '" ~ target.s3_staging_dir ~ "lab-iceberg-conflict/" ~ modules.datetime.datetime.now().strftime('%Y%m%d%H%M%S') ~ "/') as select id, 0 as v from unnest(sequence(1, 1000)) as t(id)") %}
{% endmacro %}

{% macro lab_iceberg_conflict_update(n) %}
  {% do run_query("update " ~ target.schema ~ ".lab_iceberg_conflict set v = " ~ n ~ " where id % 6 = " ~ (n - 1)) %}
{% endmacro %}
