#!/usr/bin/env bash
# Build the Lean spec, list every theorem with the axioms it depends on, and
# fail if any proof uses sorry. Needs elan (https://github.com/leanprover/elan).
set -euo pipefail
cd "$(dirname "$0")"
lake build
thms=$(grep -ho '^theorem [A-Za-z0-9_]*' Yarvpilled/*.lean | awk '{print $2}')
{ echo "import Yarvpilled"; echo "open Yarvpilled"; for t in $thms; do echo "#print axioms $t"; done; } > .lake/axioms.lean
report=$(lake env lean .lake/axioms.lean 2>&1)
echo "$report"
if echo "$report" | grep -q sorryAx; then echo "FAIL: a theorem depends on sorry"; exit 1; fi
echo "OK: $(echo "$thms" | wc -l) theorems proved, none depend on sorry"
