#!/usr/bin/env bash
# check-script-modes.sh — every shipped scripts/*.sh carries the file mode its
# first line declares.
#
# A script committed at 100644 runs through `bash <path>` and nowhere else:
# called by path, the way a plugin cache and the skills call it, it fails with
# "Permission denied" (exit 126). The repo's own tests run scripts through an
# explicit interpreter, so they pass on a script that is broken for every real
# caller; ready-flip.sh shipped two releases that way.
#
# THE SHEBANG IS THE DECLARATION. A file whose first line starts `#!` is run,
# and must be 100755. A file without one is a sourced library (the
# echo-safety.sh precedent: `# shellcheck shell=` in place of a shebang), and
# must be 100644, since an executable bit on it invites an exec that gets
# ENOEXEC and whatever shell the caller happens to run. Any other mode (a
# symbolic link, a submodule) is reported, never skipped.
#
# THE INDEX IS THE TRUTH. Modes and first lines are read from the git index,
# not the working tree: the index is what a commit ships, and a worktree chmod
# that never reached it fixes nothing.
#
# Scope is scripts/*.sh at the top level, the set lint:shell reads.
#
# Usage:
#   check-script-modes.sh [--repo-root <dir>]   default: this script's parent
#   check-script-modes.sh --help | -h
#
# Exit codes: 0 clean, 1 a script with the wrong mode, 2 usage or a scan that
# could not cover what it claims (no repository, an unreadable index or blob,
# zero scripts found).
#
# Portable bash 3.2; no fish/mise/tmux.
set -u

LC_ALL=C
export LC_ALL

unset CDPATH

self_dir="$(cd "$(dirname "$0")" && pwd -P)"

# Paths come from the index, which a PR controls, and reach stderr; strip the
# bytes that could drive the terminal (doctrine/security-posture.md). The
# inline fallback keeps diagnostics safe when the shared helper is absent.
sanitize_printable() {
  _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237' 2>/dev/null) || _sp=''
  if [ -z "$_sp" ] && [ $# -ge 2 ]; then
    _sp=$2
  fi
  printf '%s' "$_sp"
}
if [ -r "$self_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$self_dir/echo-safety.sh"
fi

fail_closed() {
  printf 'check-script-modes: %s\n' "$1" >&2
  exit 2
}

usage() {
  cat <<'EOF'
check-script-modes.sh — every scripts/*.sh in the git index carries the mode
its first line declares.

Usage:
  check-script-modes.sh [--repo-root <dir>]   default: this script's parent
  check-script-modes.sh --help | -h

A file whose first line starts with `#!` must be 100755; a file without one is
a sourced library and must be 100644. Modes and first lines are read from the
index, not the working tree.

Fixing a flagged file:
  git update-index --chmod=+x <path>   a script missing its executable bit
  git update-index --chmod=-x <path>   a library carrying one

Exit codes: 0 clean, 1 a script with the wrong mode, 2 usage or a scan that
could not cover what it claims.
EOF
}

root="$self_dir/.."
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root)
      [ $# -ge 2 ] || {
        usage >&2
        exit 2
      }
      root="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

[ -d "$root" ] || fail_closed "root is not a directory: $(sanitize_printable "$root" '?')"
top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" \
  || fail_closed "not inside a git repository: $(sanitize_printable "$root" '?')"

# The index listing goes through a temp file rather than a pipe so a failing
# `git ls-files` is seen: a pipe would hand the loop a short list and exit 0.
listing="$(mktemp)" || fail_closed "cannot create a temporary file"
trap 'rm -f "$listing"' EXIT
git -C "$top" ls-files -s -z -- ':(glob)scripts/*.sh' >"$listing" \
  || fail_closed "cannot read the git index"

count=0
bad=0
while IFS= read -r -d '' entry; do
  # <mode> SP <object> SP <stage> TAB <path>
  meta="${entry%%	*}"
  path="${entry#*	}"
  mode="${meta%% *}"
  rest="${meta#* }"
  blob="${rest%% *}"
  shown="$(sanitize_printable "$path" '?')"
  count=$((count + 1))
  case "$mode" in
    100644 | 100755) ;;
    *)
      printf 'check-script-modes: %s: mode %s is neither a script nor a library\n' \
        "$shown" "$(sanitize_printable "$mode" '?')" >&2
      bad=$((bad + 1))
      continue
      ;;
  esac
  # Existence is checked on its own: a pipe into head reports head's status,
  # and pipefail would trip on the SIGPIPE head's early exit sends git.
  git -C "$top" cat-file -e "$blob" 2>/dev/null \
    || fail_closed "cannot read the indexed blob of $shown"
  first="$(git -C "$top" cat-file blob "$blob" 2>/dev/null | head -c 2)"
  if [ "$first" = '#!' ]; then
    if [ "$mode" != 100755 ]; then
      printf 'check-script-modes: %s: has a shebang but is %s in the index; fix: git update-index --chmod=+x %s\n' \
        "$shown" "$mode" "$shown" >&2
      bad=$((bad + 1))
    fi
  elif [ "$mode" != 100644 ]; then
    printf 'check-script-modes: %s: has no shebang (a sourced library) but is %s in the index; fix: git update-index --chmod=-x %s\n' \
      "$shown" "$mode" "$shown" >&2
    bad=$((bad + 1))
  fi
done <"$listing"

[ "$count" -gt 0 ] || fail_closed "no scripts/*.sh in the index under $(sanitize_printable "$top" '?')"

if [ "$bad" -gt 0 ]; then
  printf 'check-script-modes: %s of %s scripts carry the wrong mode\n' "$bad" "$count" >&2
  exit 1
fi
printf 'check-script-modes: clean (%s scripts)\n' "$count"
