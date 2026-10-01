#!/usr/bin/env bash
# Fail when a plugin's version in .claude-plugin/marketplace.json differs from
# the version in its own .claude-plugin/plugin.json (they must be bumped together).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
marketplace="$root/.claude-plugin/marketplace.json"
status=0

while IFS=$'\t' read -r name source listed; do
  manifest="$root/$source/.claude-plugin/plugin.json"
  if [[ ! -f "$manifest" ]]; then
    printf 'FAIL %s: missing %s\n' "$name" "$manifest"
    status=1
    continue
  fi
  actual="$(jq -r '.version // empty' "$manifest")"
  if [[ "$listed" == "$actual" ]]; then
    printf 'ok   %s %s\n' "$name" "$actual"
  else
    printf 'FAIL %s: marketplace.json says %s, plugin.json says %s\n' "$name" "$listed" "${actual:-<none>}"
    status=1
  fi
done < <(jq -r '.plugins[] | [.name, .source, (.version // "")] | @tsv' "$marketplace")

exit "$status"
