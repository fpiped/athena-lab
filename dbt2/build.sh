#!/usr/bin/env bash
# Build the dbt binary from stack/ and the Athena driver from driver/ (see rebuild-stack.sh),
# and put the driver where the binary looks for it: lib/ next to the executable.
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
case "$(uname -s)" in Darwin) ext=dylib;; *) ext=so;; esac
# The shim's Makefile tracks only the shim sources, not the driver package: rebuild every time.
(cd "$DBT2/driver/go/pkg" && rm -f "libadbc_driver_athena.$ext" && make >/dev/null)
(cd "$DBT2/stack" && cargo build --bin dbt)
mkdir -p "$DBT2/stack/target/debug/lib"
cp "$DBT2/driver/go/pkg/libadbc_driver_athena.$ext" "$DBT2/stack/target/debug/lib/"
ls -la "$DBT2/stack/target/debug/dbt" "$DBT2/stack/target/debug/lib/libadbc_driver_athena.$ext"
