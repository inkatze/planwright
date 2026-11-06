#!/bin/bash
# check-allow-path-globs.sh — flags a Bash allow rule whose command path holds a
# wildcard. Read-only: it reports settings and never edits them.
#
# Why it matters. Claude Code's `*` matches any text, `/` and `..` included, so
# `Bash(/abs/planwright/scripts/*)` also admits
# `/abs/planwright/scripts/../../../bin/rm -rf <dir>` with no prompt, and
# `Bash(<cache>/planwright/*/scripts/x.sh answer *)` admits a `..` walk out of
# the version directory the same way. docs/permission-matcher-model.md (M3) has
# the matcher semantics. The safe forms are the exact script path with no `*`
# in it (it fails closed on upgrade), or the planwright PreToolUse hooks
# (worker-command-guard.sh, tower-command-guard.sh), which canonicalize the path.
#
# Usage:
#   check-allow-path-globs.sh               user settings (~/.claude/settings*.json)
#                                           and the current checkout's
#                                           .claude/settings*.json; missing files
#                                           are skipped
#   check-allow-path-globs.sh <file>...     exactly these files; a missing or
#                                           unreadable one fails the check
#
# Exit codes: 0 clean, 1 a flagged allow rule, 2 usage or input error (fail
# closed: an unparsable settings file is never reported clean).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

SAFE_HINT='use the exact script path with no * in it, e.g. Bash(/abs/path/to/planwright/scripts/fleet-streamjson.sh answer *), or rely on the planwright PreToolUse hook (worker-command-guard.sh / tower-command-guard.sh), which canonicalizes the path'

status=0

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
    ..|../*|*/..|*/../*) return 0 ;;
  esac
  return 1
}

# check_file <file>: report each flagged allow rule; non-zero on a bad file.
check_file() {
  local f=$1 rules rule inner word
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
    word=${inner%% *}
    if flagged_word "$word"; then
      echo "check-allow-path-globs: $f: allow rule '$rule' puts a wildcard or ../ in its command path, so it admits paths outside that directory; $SAFE_HINT" >&2
      status=1
    fi
  done <<EOF
$rules
EOF
  return 0
}

default_files() {
  local top f
  for f in "${HOME:-/nonexistent}/.claude/settings.json" "${HOME:-/nonexistent}/.claude/settings.local.json"; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  for f in "$top/.claude/settings.json" "$top/.claude/settings.local.json"; do
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

if [ "$status" -eq 0 ]; then
  echo "check-allow-path-globs: clean"
fi
exit "$status"
