#!/usr/bin/env bash
# Run every CBMC harness in harness.c. Prints one line per harness and exits non-zero if any fails.
# Usage: formal/cbmc/check.sh [timeout-seconds-per-harness]   (default 600)
set -u
cd "$(dirname "$0")"
T="${1:-600}"
FLAGS=(--bounds-check --pointer-check --div-by-zero-check --signed-overflow-check
       --conversion-check --float-overflow-check --nan-check --unwind 12 --unwinding-assertions)
command -v cbmc >/dev/null || { echo "cbmc not installed (apt-get install cbmc)"; exit 3; }
echo "# $(cbmc --version) | flags: ${FLAGS[*]}"
fail=0
rows=()
for h in h_food_index_wrap h_food_index_default_world h_wrapd_into_torus h_tdelta_short_way h_crowd_bounded h_act_tick_safe; do
  start=$(date +%s)
  out=$(timeout "$T" cbmc harness.c --function "$h" "${FLAGS[@]}" 2>&1); rc=$?
  secs=$(( $(date +%s) - start ))
  summary=$(printf '%s\n' "$out" | grep -E '^\*\* [0-9]+ of [0-9]+ failed' | tail -1)
  if [ $rc -eq 0 ]; then verdict="VERIFIED"
  elif [ $rc -eq 124 ]; then verdict="TIMEOUT"; fail=1
  elif [ $rc -eq 137 ] || [ $rc -eq 143 ]; then verdict="KILLED"; fail=1   # OOM killer or external signal: no result
  else verdict="FAILED"; fail=1; printf '%s\n' "$out" | grep -E 'FAILURE|error' | head -20; fi
  echo "$h: $verdict (${secs}s) ${summary}"
  rows+=("{\"harness\": \"$h\", \"verdict\": \"$verdict\", \"seconds\": $secs, \"summary\": \"${summary#\*\* }\"}")
done
# Vacuity guard: weakened copies of two assertions must FAIL, or the assumptions are too strong.
vacfail=0
vac=$(mktemp --suffix=.c)
sed -e 's/k >= 0 \&\& k < w.fw \* w.fh, "food index in bounds"/k >= 0 \&\& k < 100, "vacuity"/' \
    -e 's/r >= 0.0 \&\& r < m,/r >= 0.0 \&\& r < m \/ 2,/' \
    -e "s#\"\.\./\.\./ext#\"$PWD/../../ext#" harness.c > "$vac"
for h in h_food_index_default_world h_wrapd_into_torus; do
  if timeout "$T" cbmc "$vac" --function "$h" >/dev/null 2>&1; then echo "vacuity $h: NOT CAUGHT"; fail=1; vacfail=1
  else echo "vacuity $h: weakened assertion fails as expected"; fi
done
rm -f "$vac"
# RECORD=1 writes docs/verification/cbmc.json (read by tools/claims.rb).
if [ "${RECORD:-0}" = "1" ]; then
  {
    echo "{"
    echo "  \"tool\": \"formal/cbmc/check.sh\","
    echo "  \"date_utc\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"cbmc\": \"$(cbmc --version)\","
    echo "  \"flags\": \"${FLAGS[*]}\","
    echo "  \"harnesses\": ["
    for k in "${!rows[@]}"; do sep=","; [ "$k" -eq $(( ${#rows[@]} - 1 )) ] && sep=""; echo "    ${rows[$k]}$sep"; done
    echo "  ],"
    echo "  \"vacuity_guard_passed\": $([ $vacfail -eq 0 ] && echo true || echo false),"
    echo "  \"passed\": $([ $fail -eq 0 ] && echo true || echo false)"
    echo "}"
  } > ../../docs/verification/cbmc.json
fi
exit $fail
