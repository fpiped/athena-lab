import pandas as pd


def model(dbt, spark):
    dbt.config(materialized="table", table_type="iceberg")
    return pd.DataFrame({"id": [1, 2, 3], "label": ["a", "b", "c"]})
