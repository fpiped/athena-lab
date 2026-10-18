# dbt 2 with the Athena adapter (lab stack) and the Athena ADBC driver, linux/arm64.
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
# the driver is loaded from lib/ next to the binary
COPY dbt /opt/dbt/dbt
COPY libadbc_driver_athena.so /opt/dbt/lib/libadbc_driver_athena.so
RUN ln -s /opt/dbt/dbt /usr/local/bin/dbt
COPY project /app/project
# the profile reads these; linux/build-linux.sh passes the values of env.sh
ARG AWS_REGION LAB_S3_ROOT LAB_SCHEMA LAB_WORK_GROUP
ENV AWS_REGION=$AWS_REGION LAB_S3_ROOT=$LAB_S3_ROOT LAB_SCHEMA=$LAB_SCHEMA LAB_WORK_GROUP=$LAB_WORK_GROUP
ENV DBT_ALLOW_EXPERIMENTAL_ADAPTERS=true DISABLE_AUTO_DRIVER_REBUILD=1 DBT_SEND_ANONYMOUS_USAGE_STATS=false DBT_PROFILES_DIR=/app/project
WORKDIR /app/project
