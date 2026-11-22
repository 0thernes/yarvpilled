#!/usr/bin/env bash
# Build and run the differential kernel fuzzer (libFuzzer + ASan + UBSan) for N seconds.
#   fuzz/run.sh [seconds=60]          needs clang (with libFuzzer) and cargo
set -euo pipefail
cd "$(dirname "$0")/.."
SECS="${1:-60}"
CC="${CC:-$(command -v clang-19 || command -v clang)}"
(cd ext/yarvpilled_rust && cargo build --release --quiet)
mkdir -p tmp/fuzz/corpus
SAN="-fsanitize=fuzzer,address,undefined,float-cast-overflow -fno-sanitize-recover=all"
"$CC" -O1 -g -ffp-contract=off $SAN -DYP_HAVE_RUST -Iext/yarvpilled_native \
  fuzz/kernel_fuzz.c ext/yarvpilled_native/kernel_c.c ext/yarvpilled_native/crowd_x86_64.S \
  ext/yarvpilled_rust/target/release/libyarvpilled_rust.a -lm -lpthread -ldl -o tmp/fuzz/kernel_fuzz
tmp/fuzz/kernel_fuzz -max_total_time="$SECS" -max_len=4096 -print_final_stats=1 -artifact_prefix=tmp/fuzz/ tmp/fuzz/corpus fuzz/regressions 2>&1 | tee tmp/fuzz/last_run.txt
