{{ config(materialized='table', table_type='hive') }}
select cast('x' as varchar) as s, cast('x' as varchar(10)) as s10, array['a'] as a, map(array['k'], array[1]) as m,
       cast(row('x', 1) as row(f varchar, g integer)) as st, cast(1.5 as decimal(10,2)) as d,  
       cast(current_timestamp as timestamp) as ts, cast('ab' as varbinary) as b, 1 as i, cast(1 as bigint) as bi,
       cast(1 as double) as db, true as bo, current_date as dt
