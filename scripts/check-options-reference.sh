#!/bin/bash
# check-options-reference.sh — D-43 drift check (REQ-K1.8).
#
# Every option in the tracked default config must have a row in the canonical
# options reference. An undocumented option is an error (exit 1). A reference
# row with no matching config option is a warning on stderr (stale docs
# surface without blocking). Task 2 wires this into planwright's CI.
#
# Usage: check-options-reference.sh [<config> [<reference>]]
#   Defaults: config/defaults.yml and docs/options-reference.md relative to
#   the repo root (the script's parent directory).
#
# Exit codes: 0 fully documented, 1 undocumented option found, 2 usage error.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
set -u

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
config="${1:-$repo_root/config/defaults.yml}"
reference="${2:-$repo_root/docs/options-reference.md}"

if [ ! -f "$config" ]; then
  echo "check-options-reference: config file not found: $config" >&2
  exit 2
fi
if [ ! -f "$reference" ]; then
  echo "check-options-reference: reference file not found: $reference" >&2
  exit 2
fi

# Option keys: top-level "key:" lines in the flat default config.
config_keys="$(sed -n 's/^\([a-z0-9_]*\):.*/\1/p' "$config")"

# Documented options: table rows whose first cell is the backticked name.
# Cell padding is tolerated: the check is coverage, not whitespace style.
# shellcheck disable=SC2016 # the backtick is literal markdown, not expansion
documented_keys="$(sed -n 's/^|[[:space:]]*`\([a-z0-9_]*\)`[[:space:]]*|.*/\1/p' "$reference")"

status=0

for key in $config_keys; do
  found=0
  for doc in $documented_keys; do
    if [ "$key" = "$doc" ]; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "check-options-reference: option '$key' in $config has no entry in $reference" >&2
    status=1
  fi
done

for doc in $documented_keys; do
  found=0
  for key in $config_keys; do
    if [ "$doc" = "$key" ]; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "check-options-reference: warning: '$doc' is documented but absent from $config" >&2
  fi
done

if [ "$status" -eq 0 ]; then
  echo "check-options-reference: all options documented"
fi
exit "$status"
