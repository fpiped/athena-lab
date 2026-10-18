{# begin three days back, so a run covers four daily batches #}
{{ config(materialized='incremental', incremental_strategy='microbatch', table_type='iceberg', unique_key='id',
          event_time='ts', batch_size='day', lookback=0,
          begin=(modules.datetime.date.today() - modules.datetime.timedelta(days=3)).isoformat()) }}
select id, ts from {{ ref('lab_events') }}
