"""Generate the scale project's models: six layers (250 models), each model reading one to three
models of the layer before, mixing views, tables, Hive insert_overwrite and Iceberg merge, with a
not_null test on every model. Deterministic (seed 7). Usage: generate.py <models dir>"""
import os
import random
import sys

random.seed(7)
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
layers = [10, 40, 60, 60, 50, 30]
kinds = ["view"] * 4 + ["table"] * 3 + ["hive_inc"] * 1 + ["iceberg"] * 2
configs = {
    "view": "materialized='view'",
    "table": "materialized='table'",
    # Hive partition columns come last in the select
    "hive_inc": "materialized='incremental', incremental_strategy='insert_overwrite', partitioned_by=['p']",
    "iceberg": "materialized='incremental', table_type='iceberg', incremental_strategy='merge', unique_key='id'",
}
schema, previous = ["version: 2", "models:"], []
for layer, count in enumerate(layers):
    current = []
    for i in range(count):
        name = f"m{layer}_{i:03d}"
        kind = "table" if layer == 0 else random.choice(kinds)
        if layer == 0:
            body = f"select id, 'r{i}' as src, id % 7 as p from unnest(sequence(1, 1000)) as t(id)"
        else:
            parents = random.sample(previous, random.randint(1, 3))
            union = " union all ".join(
                f"select id, id % 7 as p, '{name}' as src from {{{{ ref('{parent}') }}}}" for parent in parents
            )
            body = f"select id, max(src) as src, max(p) as p from ({union}) group by id"
        with open(os.path.join(out, f"{name}.sql"), "w") as f:
            f.write(f"{{{{ config({configs[kind]}) }}}}\n{body}\n")
        schema += [f"  - name: {name}", "    columns:", "      - name: id", "        data_tests: [not_null]"]
        current.append(name)
    previous = current
with open(os.path.join(out, "schema.yml"), "w") as f:
    f.write("\n".join(schema) + "\n")
