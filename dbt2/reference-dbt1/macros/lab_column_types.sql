{% macro lab_column_types(names, database=none) %}
  {% for name in names %}
    {% set rel = adapter.get_relation(database=database or target.database, schema=target.schema, identifier=name) %}
    {% set cols = adapter.get_columns_in_relation(rel) %}
    {% for c in cols %}
      {{ log("COL " ~ name ~ " " ~ c.name ~ " dtype=" ~ c.dtype ~ " data_type=" ~ c.data_type ~ " is_string=" ~ c.is_string(), info=True) }}
    {% endfor %}
    {#- map<...> and struct<...> stay in Hive syntax in dbt-athena too, so their casts fail on both -#}
    {% set castable = [] %}{% for c in cols if not (c.data_type.startswith('map') or c.data_type.startswith('struct')) %}{% do castable.append(c) %}{% endfor %}
    {% set sql %}select {% for c in castable %}cast(null as {{ c.data_type }}) as {{ c.quoted }}{{ ", " if not loop.last }}{% endfor %}{% endset %}
    {% do run_query(sql) %}
    {{ log("CAST-OK " ~ name, info=True) }}
  {% endfor %}
{% endmacro %}

{#- Columns of a relation in a given data catalog, without a relation lookup first. -#}
{% macro lab_columns_in(database, name) %}
  {% set rel = api.Relation.create(database=database, schema=target.schema, identifier=name) %}
  {% for c in adapter.get_columns_in_relation(rel) %}
    {{ log("COL " ~ database ~ " " ~ name ~ " " ~ c.name ~ " dtype=" ~ c.dtype, info=True) }}
  {% endfor %}
{% endmacro %}
