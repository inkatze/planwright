#!/bin/bash
# check-allow-path-globs.sh — flags a Bash allow rule whose command path holds a
# wildcard or `..`. Read-only. Claude Code's `*` also matches `/` and `..`, so
# `Bash(<dir>/*)` admits `<dir>/../../../bin/rm` (docs/permission-matcher-model.md
# M3; safe forms in docs/overlays.md).
#
# No argument: planwright's shipped profiles (config/*-settings.json beside this
# script), the checkout's settings and the user's home settings, missing files
# skipped. Arguments: exactly those files; a missing one fails the check.
# A finding in the user's home settings (~/.claude/settings*.json) only warns:
# those files are the user's, and the check never edits them.
# Exit: 0 clean or home warnings only, 1 flagged, 2 input error (never clean).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

SAFE_HINT='use the exact script path with no * in it, e.g. Bash(/abs/path/to/planwright/scripts/fleet-streamjson.sh answer *), or rely on the planwright PreToolUse hook (worker-command-guard.sh / tower-command-guard.sh), which canonicalizes the path'

status=0
warned=0
script_root=$(cd "$(dirname "$0")/.." && pwd -P)

if ! command -v jq >/dev/null 2>&1; then
  echo "check-allow-path-globs: jq is required to read settings" >&2
  exit 2
fi

# flagged_word <word>: 0 when the rule's command path carries a wildcard or a
# `..` segment. A trailing `:*` is the argument boundary, not part of the path.
flagged_word() {
  local w=$1
  w=${w%:\*}
  case $w in
    *'*'*) case $w in *'/'*) return 0 ;; esac ;;
  esac
  case $w in
    .. | ../* | */.. | */../*) return 0 ;;
  esac
  return 1
}

# rule_flagged <rule-inner>: 0 when the rule's first word is flagged, or, for a
# shell prefix such as `bash scripts/*`, the script word after its options.
rule_flagged() {
  set -f
  # shellcheck disable=SC2086 # split the rule into words, globbing off
  set -- $1
  set +f
  [ "$#" -gt 0 ] || return 1
  flagged_word "$1" && return 0
  case ${1##*/} in
    bash | sh | zsh | dash | ksh) shift ;;
    *) return 1 ;;
  esac
  while [ "$#" -gt 0 ]; do
    case $1 in
      -*) shift ;;
      *) break ;;
    esac
  done
  [ "$#" -gt 0 ] && flagged_word "$1"
}

# home_settings <file>: 0 when the file is one of the user's home settings.
home_settings() {
  [ -n "${HOME:-}" ] || return 1
  case $1 in
    "$HOME/.claude/settings.json" | "$HOME/.claude/settings.local.json") return 0 ;;
  esac
  return 1
}

# check_file <file>: report each flagged allow rule; non-zero on a bad file.
check_file() {
  local f=$1 rules rule inner level
  if [ ! -f "$f" ] || [ ! -r "$f" ]; then
    echo "check-allow-path-globs: settings file not found or unreadable: $f" >&2
    return 2
  fi
  if ! rules=$(jq -r '.permissions.allow[]? | strings' "$f" 2>/dev/null); then
    echo "check-allow-path-globs: $f is not valid JSON; cannot check it" >&2
    return 2
  fi
  printf 'check-allow-path-globs: checked %s\n' "$f"
  while IFS= read -r rule; do
    case $rule in
      Bash\(*\)) ;;
      *) continue ;;
    esac
    inner=${rule#Bash(}
    inner=${inner%)}
    rule_flagged "$inner" || continue
    if home_settings "$f"; then
      level='warning: '
      warned=1
    else
      level=
      status=1
    fi
    echo "check-allow-path-globs: $level$f: allow rule '$rule' puts a wildcard or ../ in its command path, so it admits paths outside that directory; $SAFE_HINT" >&2
  done <<EOF
$rules
EOF
  return 0
}

default_files() {
  local top f
  for f in "$script_root"/config/*-settings.json; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
  for f in "${HOME:-/nonexistent}/.claude/settings.json" "${HOME:-/nonexistent}/.claude/settings.local.json"; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  for f in "$top/.claude/settings.json" "$top/.claude/settings.local.json"; do
    home_settings "$f" && continue
    [ -f "$f" ] && printf '%s\n' "$f"
  done
  return 0
}

if [ "$#" -eq 0 ]; then
  files=$(default_files)
  if [ -z "$files" ]; then
    echo "check-allow-path-globs: no settings files found to check"
    exit 0
  fi
  while IFS= read -r f; do
    check_file "$f" || exit 2
  done <<EOF
$files
EOF
else
  for f in "$@"; do
    check_file "$f" || exit 2
  done
fi

if [ "$status" -eq 0 ] && [ "$warned" -eq 1 ]; then
  echo "check-allow-path-globs: clean apart from warnings on home settings"
elif [ "$status" -eq 0 ]; then
  echo "check-allow-path-globs: clean"
fi
exit "$status"
