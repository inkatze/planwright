#!/bin/sh
# config-get.sh — read one planwright config value with the defaults +
# local-override precedence the config model defines (D-33, REQ-K1.1).
#
# The tracked defaults (config/defaults.yml) supply the base; a per-repo
# gitignored override (<repo>/.claude/planwright.local.yml) wins when it
# sets the key. The planwright config model is intentionally flat one-level
# `key: value` YAML, so a line-oriented reader is sufficient and keeps the
# runtime dependency-free (REQ-K1.5). The raw value is printed verbatim with
# a trailing `# comment` and surrounding quotes stripped; type and range
# validation stay with the caller, since they are key-specific (the lock
# threshold normalizes `m`, a backend name is an enum, etc.).
#
# This is the shared reader the dispatch layer reads through, instead of a
# fourth ad-hoc `sed` of the flat config (the consolidation the 2026-06-12
# observation called for).
#
# Usage: config-get.sh <key>
#   <key> matches ^[a-z][a-z0-9_]*$ and is validated before it is ever
#   interpolated into a pattern (framework-script security, REQ-D1.6).
#
# Environment overrides (tests, adopters, worktree callers that know the
# primary checkout's paths):
#   PLANWRIGHT_CONFIG_DEFAULTS  explicit tracked-defaults file
#   PLANWRIGHT_LOCAL_CONFIG     explicit per-repo override file
#   PLANWRIGHT_ROOT             planwright root holding config/defaults.yml
#   CLAUDE_PLUGIN_ROOT          plugin-delivery root (set by Claude Code)
#
# Exit: 0 value printed (from the local override or the defaults); 3 key
# absent in both; 2 usage / invalid key. Never fails opaquely.
set -u

# Pin the C locale: the [a-z] range checks below are collation-dependent and
# would otherwise admit uppercase under a UTF-8 locale.
LC_ALL=C
export LC_ALL
# A CDPATH-resolved cd would echo the destination into the command
# substitution that derives the script dir (house pattern).
unset CDPATH

key="${1:-}"
if [ -z "$key" ]; then
  echo "usage: config-get.sh <key>" >&2
  exit 2
fi
case "$key" in
  [a-z]*) ;;
  *)
    echo "planwright: invalid config key '$key' (must match ^[a-z][a-z0-9_]*\$)" >&2
    exit 2
    ;;
esac
case "$key" in
  *[!a-z0-9_]*)
    echo "planwright: invalid config key '$key' (must match ^[a-z][a-z0-9_]*\$)" >&2
    exit 2
    ;;
esac

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# Resolve the tracked defaults file: an explicit override, then the
# planwright root chain (env-set in plugin/test delivery), then the
# script-relative layout (scripts/ sibling config/). First existing wins.
defaults=""
if [ -n "${PLANWRIGHT_CONFIG_DEFAULTS:-}" ]; then
  defaults="$PLANWRIGHT_CONFIG_DEFAULTS"
else
  for root in "${PLANWRIGHT_ROOT:-}" "${CLAUDE_PLUGIN_ROOT:-}" "$script_dir/.."; do
    [ -n "$root" ] || continue
    if [ -f "$root/config/defaults.yml" ]; then
      defaults="$root/config/defaults.yml"
      break
    fi
  done
fi

# Resolve the per-repo local override: an explicit path, else the
# cwd's git toplevel. A missing local file is normal (the defaults stand).
local_cfg=""
if [ -n "${PLANWRIGHT_LOCAL_CONFIG:-}" ]; then
  local_cfg="$PLANWRIGHT_LOCAL_CONFIG"
else
  top=$(git rev-parse --show-toplevel 2>/dev/null) || top=""
  [ -n "$top" ] && local_cfg="$top/.claude/planwright.local.yml"
fi

# extract <file> <key>: print the cleaned value and return 0 when the key is
# present; return 1 when the file is absent or the key is not set. The key is
# pre-validated to the flat-identifier charset, so it is regex-safe here.
extract() {
  ef="$1"
  ek="$2"
  [ -f "$ef" ] || return 1
  grep -q "^${ek}:" "$ef" 2>/dev/null || return 1
  sed -n "s/^${ek}:[[:space:]]*//p" "$ef" \
    | head -1 \
    | sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' \
      -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
  return 0
}

if [ -n "$local_cfg" ] && extract "$local_cfg" "$key"; then
  exit 0
fi
if [ -n "$defaults" ] && extract "$defaults" "$key"; then
  exit 0
fi
# Key not found. If the tracked defaults file itself could not be located or
# read, that is a broken install (mis-set PLANWRIGHT_ROOT, partial delivery),
# not a normal absent key — surface it rather than failing opaquely. The exit
# code stays 3 so callers still pick their own fallback.
if [ -z "$defaults" ] || [ ! -r "$defaults" ]; then
  echo "config-get: tracked defaults not found (looked via PLANWRIGHT_CONFIG_DEFAULTS / PLANWRIGHT_ROOT / CLAUDE_PLUGIN_ROOT / script dir); '$key' unresolved" >&2
fi
exit 3
