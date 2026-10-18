"""Print the Parquet physical schema of every file under an S3 prefix: parquet_schema.py s3://bucket/prefix/"""
import io
import sys

import boto3
import pyarrow.parquet as pq

bucket, _, prefix = sys.argv[1].removeprefix("s3://").partition("/")
s3 = boto3.client("s3")
for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix=prefix):
    for obj in page.get("Contents", []):
        body = s3.get_object(Bucket=bucket, Key=obj["Key"])["Body"].read()
        if body[:4] != b"PAR1":
            continue
        print(pq.ParquetFile(io.BytesIO(body)).schema)
        sys.exit(0)
sys.exit("no Parquet file under the prefix")
