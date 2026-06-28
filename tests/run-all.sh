#!/usr/bin/env bash
# Run every plugin's test suite. A plugin opts in to CI by providing
# tests/run-tests.sh that exits non-zero on failure. New plugins are picked up
# automatically. Exits non-zero if any suite fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

ran=0
failed=0
for runner in plugins/*/tests/run-tests.sh; do
  [ -e "$runner" ] || continue
  ran=$((ran + 1))
  plugin="$(basename "$(dirname "$(dirname "$runner")")")"
  printf '\n=== %s ===\n' "$plugin"
  if bash "$runner"; then
    printf '%s: PASS\n' "$plugin"
  else
    printf '%s: FAIL\n' "$plugin"
    failed=$((failed + 1))
  fi
done

printf '\n----\n'
if [ "$ran" -eq 0 ]; then
  echo "No plugin test suites found (plugins/*/tests/run-tests.sh)."
  exit 0
fi
printf '%d plugin suite(s) ran, %d failed\n' "$ran" "$failed"
[ "$failed" -eq 0 ]
