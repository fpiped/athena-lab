#!/usr/bin/env bash
# DDL takes Hive type names and DML returns Trino names: the type a query reports (varchar, row(...),
# integer) cannot be written back into CREATE or ALTER, so tools that round-trip types must translate.
set -uo pipefail
QUIRK=11-type-dialects
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
title "DDL (Hive) versus DML (Trino) type names"
TABLES=(t_ice t_ice_varchar t_ice_varchar10 t_ice_integer t_ice_row t_hive t_hive_varchar t_hive_integer)
cleanup() { drop "${TABLES[@]}"; }
cleanup
ice() { echo "LOCATION '$(loc "$1")' TBLPROPERTIES ('table_type'='ICEBERG')"; }
hive() { echo "STORED AS PARQUET LOCATION '$(loc "$1")'"; }
expected "documented: DDL uses Hive type names, DML uses Trino names (https://docs.aws.amazon.com/athena/latest/ug/data-types.html); the table lists INT and INTEGER for both"
out="" short=""
# try <label> <sql>: run a statement and record its outcome
try() { section "$1"; q_show "$2"; out+="$1: $Q_STATE${Q_REASON:+ ($Q_REASON)}; "; short+="$1: ${Q_STATE/START_FAILED/FAILED}; "; }

try "Iceberg CREATE with string, struct, array, map" "CREATE TABLE t_ice (s string, st struct<x:int,y:string>, arr array<string>, m map<string,int>, i int) $(ice t_ice)"
q_show "SELECT column_name, data_type FROM information_schema.columns WHERE table_schema = '$QDB' AND table_name = 't_ice' ORDER BY ordinal_position"
types=$(q_rows | sed 1d | tr '\t' ' ' | paste -sd, - | sed 's/,/, /g')
actual "information_schema.columns: $types"

section "the reported (Trino) names written back into DDL"
try "Iceberg CREATE with varchar" "CREATE TABLE t_ice_varchar (s varchar) $(ice t_ice_varchar)"
try "Iceberg CREATE with varchar(10)" "CREATE TABLE t_ice_varchar10 (s varchar(10)) $(ice t_ice_varchar10)"
try "Iceberg CREATE with integer" "CREATE TABLE t_ice_integer (i integer) $(ice t_ice_integer)"
try "Iceberg CREATE with row(...)" "CREATE TABLE t_ice_row (r row(x integer)) $(ice t_ice_row)"
try "Iceberg ALTER ADD COLUMNS with row(...)" "ALTER TABLE t_ice ADD COLUMNS (r row(x integer))"
try "Iceberg ALTER ADD COLUMNS with varchar" "ALTER TABLE t_ice ADD COLUMNS (v varchar)"
try "Hive CREATE with varchar" "CREATE EXTERNAL TABLE t_hive_varchar (s varchar) $(hive t_hive_varchar)"
try "Hive CREATE with integer" "CREATE EXTERNAL TABLE t_hive_integer (i integer) $(hive t_hive_integer)"
try "Hive CREATE with string and struct" "CREATE EXTERNAL TABLE t_hive (s string, st struct<x:int,y:string>) $(hive t_hive)"

section "the DDL (Hive) names written into DML"
try "CAST to string" "SELECT CAST('a' AS string)"
try "CAST to struct<...>" "SELECT CAST(ROW(1) AS struct<x:int>)"

cleanup
if grep -q 'FAILED' <<<"$out"; then verdict REPRODUCED "$short"; else verdict "NOT REPRODUCED" "$short"; fi
