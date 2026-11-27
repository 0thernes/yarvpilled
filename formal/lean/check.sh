#!/usr/bin/env bash
# Build the Lean spec, audit every theorem's axioms via VerifyAxioms.lean
# (strictly within [propext, Classical.choice, Quot.sound]), and replay the
# compiled environment in leanchecker. Needs elan (https://github.com/leanprover/elan).
set -euo pipefail
cd "$(dirname "$0")"
lake build
report=$(lake env lean VerifyAxioms.lean 2>&1)
echo "$report"
if echo "$report" | grep -q sorryAx; then echo "FAIL: a theorem depends on sorry"; exit 1; fi
# Every `#print axioms` output line must either report no axioms or only standard axioms.
bad=$(echo "$report" | grep -E "depends on axioms:" | grep -Ev "depends on axioms: \[(propext|Classical\.choice|Quot\.sound)(, (propext|Classical\.choice|Quot\.sound))*\]$" || true)
if [ -n "$bad" ]; then
  echo "FAIL: non-standard axiom detected:"
  echo "$bad"
  exit 1
fi
thms=$(grep -ho '^theorem [A-Za-z0-9_]*' Yarvpilled/*.lean | awk '{print $2}')
audited=$(echo "$report" | grep -cE "depends on axioms:|does not depend on any axioms")
total=$(echo "$thms" | wc -l | tr -d ' ')
if [ "$audited" -ne "$total" ]; then
  echo "FAIL: VerifyAxioms.lean audited $audited theorems, expected $total"
  exit 1
fi
lake env leanchecker --fresh Yarvpilled
echo "OK: $total theorems proved, strictly standard axioms only, leanchecker passed"
