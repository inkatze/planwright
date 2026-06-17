#!/usr/bin/env bash
# check-plugin-schema.sh — schema-deep validation of the plugin + marketplace
# manifests via `claude plugin validate` (Task 19 follow-up). This is the
# schema layer beneath lint:json's jq syntax check.
#
# lint:json proves the manifests are valid JSON. This proves they satisfy the
# Claude Code plugin SCHEMA: required fields present, the marketplace `source`
# path resolving, marketplace<->plugin name consistency, and (under --strict)
# no unknown fields. A manifest that is valid JSON but schema-broken passes
# lint:json yet fails at install — exactly the class of bug that hid the
# missing marketplace.json until T19 polish. This closes that gap.
#
# The `claude` CLI is NOT part of the mise toolchain (planwright pins only its
# own quality tools, and its runtime stays plain portable bash — REQ-K1.5).
# When `claude` is absent — e.g. a CI runner without Claude Code installed —
# this DEGRADES: it prints a clear skip note and exits 0, the same shape
# lint:commits uses when origin/main is missing. Where `claude` is present
# (a contributor's machine, or a runner that installs it) it ENFORCES. Add the
# `claude` CLI to the runner to make this gate bite in CI.
#
# Usage: check-plugin-schema.sh [<repo-dir>]
#   <repo-dir> defaults to the repo this script ships in.
# Exit codes: 0 validated OR cleanly skipped (no claude / no manifests);
#   1 a manifest failed schema validation; 2 usage error.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
set -u
unset CDPATH

repo_arg="${1:-}"
if [ -n "$repo_arg" ]; then
  if [ ! -d "$repo_arg" ]; then
    echo "check-plugin-schema: no such directory: $repo_arg" >&2
    exit 2
  fi
  repo_root="$(cd "$repo_arg" && pwd -P)"
else
  repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "check-plugin-schema: 'claude' CLI not on PATH; skipping schema validation" \
    "(lint:json still verified JSON syntax). Install Claude Code to enforce the" \
    "manifest schema locally or in CI."
  exit 0
fi

manifest="$repo_root/.claude-plugin/plugin.json"
marketplace="$repo_root/.claude-plugin/marketplace.json"

rc=0
validated=0
# The marketplace manifest (and the plugin it sources). --strict treats
# unknown fields as errors, matching the documented `claude plugin validate
# --strict` invocation in docs/getting-started.md.
if [ -f "$marketplace" ]; then
  claude plugin validate "$repo_root" --strict || rc=1
  validated=1
fi
# The plugin manifest directly: `validate <dir>` reports on the marketplace
# when one is present, so the plugin manifest needs its own explicit pass.
if [ -f "$manifest" ]; then
  claude plugin validate "$manifest" --strict || rc=1
  validated=1
fi

if [ "$rc" -ne 0 ]; then
  echo "check-plugin-schema: manifest schema validation FAILED" >&2
  exit 1
fi
if [ "$validated" -eq 0 ]; then
  echo "check-plugin-schema: no .claude-plugin manifests under $repo_root; nothing to validate" >&2
  exit 0
fi
echo "check-plugin-schema: manifests passed schema validation (claude plugin validate --strict)"
exit 0
