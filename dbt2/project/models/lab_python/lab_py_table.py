def model(dbt, spark):
    dbt.config(materialized="table")
    customers = dbt.ref("customers")
    return customers.withColumnRenamed("first_name", "given_name")
