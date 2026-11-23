#!/usr/bin/env bash
# Build formal/cbmc/lattice.c with ASan + UBSan against the C, asm and Rust kernels and run it.
# RECORD=1 also writes docs/verification/lattice.json.
set -euo pipefail
cd "$(dirname "$0")/../.."
CC="${CC:-gcc}"
mkdir -p tmp/lattice
RUST=()
if command -v cargo >/dev/null && (cd ext/yarvpilled_rust && cargo build --release --quiet); then
  RUST=(-DYP_HAVE_RUST ext/yarvpilled_rust/target/release/libyarvpilled_rust.a)
fi
SAN="-fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all"
"$CC" -O1 -g -ffp-contract=off $SAN -Iext/yarvpilled_native formal/cbmc/lattice.c \
  ext/yarvpilled_native/kernel_c.c ext/yarvpilled_native/crowd_x86_64.S "${RUST[@]}" -lm -lpthread -ldl -o tmp/lattice/lattice
start=$(date +%s)
out=$(tmp/lattice/lattice)
secs=$(( $(date +%s) - start ))
echo "$out"
if [ "${RECORD:-0}" = "1" ]; then
  printf '%s\n' "$out" | ruby -rjson -e 'j = JSON.parse($stdin.read); j["seconds"] = ARGV[0].to_i; j["date_utc"] = Time.now.utc.strftime("%FT%TZ"); j["cc"] = `#{ARGV[1]} --version`.lines.first.strip; j["sanitizers"] = "address,undefined,float-cast-overflow"; puts JSON.pretty_generate(j)' "$secs" "$CC" > docs/verification/lattice.json
fi
