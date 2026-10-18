#!/usr/bin/env bash
# Release build of the stack (dbt) and the driver for linux/arm64 (e.g. Fargate ARM64) into linux/out/:
# dbt in the manylinux_2_28 image dbt's release-v2 workflow uses, the driver shim with CGO in golang:1.26.
set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib.sh"
OUT="$DBT2/linux/out"; mkdir -p "$OUT/lib"
# Build from a snapshot of the stack commit (plus the Cargo.lock the Mac builds resolved), so that
# rebuild-stack.sh can reset stack/ while this runs.
SRC="$DBT2/linux/src"; rm -rf "$SRC"; mkdir -p "$SRC"
git -C "$DBT2/stack" archive HEAD | tar -x -C "$SRC"
cp "$DBT2/stack/Cargo.lock" "$SRC/"
git -C "$DBT2/stack" rev-parse HEAD > "$OUT/STACK_COMMIT"
docker build -q -t $LAB_PREFIX-dbt-build -f "$DBT2/linux/Dockerfile.build" "$DBT2/linux" >/dev/null
docker run --rm -v "$DBT2/driver:/driver" -v "$OUT/lib:/out" -v $LAB_PREFIX-go:/go/pkg/mod -w /driver/go/pkg golang:1.26-bookworm \
  bash -c 'rm -f libadbc_driver_athena.so && make >/dev/null && cp libadbc_driver_athena.so /out/'
# target dir and cargo registry live in docker volumes, not on the Mac disk
docker run --rm -v "$SRC:/src" -v "$OUT:/out" -v $LAB_PREFIX-dbt-target:/target -v $LAB_PREFIX-cargo:/root/.cargo/registry \
  -e CARGO_TARGET_DIR=/target -e CARGO_INCREMENTAL=0 -w /src \
  -e CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16 $LAB_PREFIX-dbt-build \
  bash -c 'cargo build --release --bin dbt -j 3 && cp /target/release/dbt /out/dbt'
# (-j 3 and 16 codegen units: 8 jobs with the profile's codegen-units=1 ran out of 12 GB of Docker memory)
file "$OUT/dbt" "$OUT/lib/libadbc_driver_athena.so"
# The ECS image: the release binary, the driver and the image project (ecs-e2e/ runs it).
cp "$OUT/dbt" "$OUT/lib/libadbc_driver_athena.so" "$DBT2/linux/image/"
docker build -q --platform linux/arm64 -t "$LAB_PREFIX-dbt:$(cut -c1-9 "$OUT/STACK_COMMIT")" \
  --build-arg AWS_REGION --build-arg LAB_S3_ROOT --build-arg LAB_SCHEMA --build-arg LAB_WORK_GROUP "$DBT2/linux/image"
rm -f "$DBT2/linux/image/dbt" "$DBT2/linux/image/libadbc_driver_athena.so"
