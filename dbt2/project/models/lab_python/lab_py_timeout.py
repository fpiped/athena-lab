import time


def model(dbt, spark):
    dbt.config(materialized="table", timeout=20)
    time.sleep(90)  # lab_py_timeout: longer than the timeout
    return spark.createDataFrame([(1,)], ["id"])
