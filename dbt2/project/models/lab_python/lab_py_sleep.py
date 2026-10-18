import time


def model(dbt, spark):
    dbt.config(materialized="table")
    time.sleep(240)  # lab_py_sleep: cancelled by the Ctrl-C step
    return spark.createDataFrame([(1,)], ["id"])
