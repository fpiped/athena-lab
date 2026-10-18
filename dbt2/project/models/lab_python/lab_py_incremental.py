def model(dbt, spark):
    dbt.config(materialized="incremental", incremental_strategy="append")
    orders = dbt.ref("orders")
    if dbt.is_incremental:
        return orders.limit(5)
    return orders
