{# long enough to be cancelled; enabled only for the Ctrl-C step #}
{{ config(materialized='table', enabled=var('lab_negative')) }}
select count(*) as n
from unnest(sequence(1, 20000)) a(x) cross join unnest(sequence(1, 20000)) b(y) cross join unnest(sequence(1, 50)) c(z)
