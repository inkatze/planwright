#!/bin/sh
# check-launch-shape.sh — the launch-shape prose guard (fleet-hardening
# Task 14; REQ-H1.5, D-10).
#
# The tmux rung launches its worker in a detached session it creates itself
# (`tmux new-session -d ...` running the dispatch env wrapper). The native
# worktree launcher, with or without its classic-tmux flag, is no longer the
# rung's launch; it survives only as an operator's hand-launch. This guard
# fails on shipped prose that names that launcher without saying so, so the
# old shape cannot drift back in as the rung's documented launch.
#
# RULE. A segment naming the old shape (`claude`, whitespace, `--worktree`; or
# the `--tmux` flag set to `classic`) passes only when a label sits within
# WINDOW segments of it in the same paragraph: "hand-launch" (or "hand
# launch"), or "prior launcher" for the liveness probes that still match the
# sessions that launcher created. A segment is a line, further split after
# every ". ", so a one-line JSON `_about` is judged sentence by sentence rather
# than as one paragraph; a blank line (or a bare comment leader) ends a
# paragraph. Every mention has to be labeled, whatever it says about the
# launch: deciding whether prose "presents" a launch is a judgment, and a label
# is something a script can see.
#
# SCOPE. docs/, doctrine/, skills/, scripts/ and config/ in full, plus every
# README outside the spec home, tests/ and dot-directories. Out of scope: the
# spec home, wherever it is relocated (decision records quote the old shape), tests/ (fixtures quote it as negative
# cases), and any CHANGELOG.md (release history). The default run reads the
# tracked files there; a --root run reads the filesystem.
#
# Usage: check-launch-shape.sh [--root <dir>]
#   --root  the tree to scan; default the enclosing git work tree.
# Exit: 0 clean · 1 an unlabeled mention · 2 usage, environment, or nothing to
#   scan (a scan that reached no file, or failed partway, fails closed rather
#   than passing).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

WINDOW=2
NL='
'

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
if [ -r "$script_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$script_dir/echo-safety.sh"
else
  sanitize_printable() {
    _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237')
    if [ -z "$_sp" ] && [ $# -ge 2 ]; then
      _sp=$2
    fi
    printf '%s' "$_sp"
  }
fi

usage() {
  echo "usage: check-launch-shape.sh [--root <dir>]" >&2
  exit 2
}

root=""
root_given=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      [ "$#" -ge 2 ] && [ -n "$2" ] && [ "$root_given" -eq 0 ] || usage
      root="$2"
      root_given=1
      shift 2
      ;;
    *) usage ;;
  esac
done

if [ "$root_given" -eq 0 ]; then
  if ! root=$(git rev-parse --show-toplevel 2>/dev/null); then
    echo "check-launch-shape: not inside a git work tree and no --root given" >&2
    exit 2
  fi
fi
# A leading dash would reach cd as an option (`-` is even a directory change).
case $root in
  -*) root=./$root ;;
esac
cd "$root" >/dev/null 2>&1 || {
  echo "check-launch-shape: cannot enter the root to scan" >&2
  exit 2
}

# The patterns are spelled so this file's own code never matches them. A
# mention may use the worktree flag's short form, carry flags between the
# launcher and that flag, and quote or space the classic-tmux value; one
# wrapped across a single line break (behind a comment, quote, list, or code
# leader, or a shell continuation) counts at its first line. Known misses: a
# wrap spanning several lines, a positional argument before the flag, and an
# upper-cased launcher name.
# shellcheck disable=SC2016 # the $-fields below are awk's, not the shell's
scan_program='
function flush(   i, j, ok, wrapped) {
  for (i = 1; i <= n; i++) {
    wrapped = i < n && line[i + 1] == line[i] + 1 && seg[i] ~ /claude`?[ \t]*(\\[ \t]*)?$/ \
      && seg[i + 1] ~ /^[ \t]*([#>*\/`-]+[ \t]*)*(--?[A-Za-z][A-Za-z-]*([= \t]+[^- \t][^ \t]*)?[ \t]+)*(--worktree|-w([= \t`"\047]|$))/
    if (!wrapped && seg[i] !~ /claude([ \t]+--?[A-Za-z][A-Za-z-]*([= \t]+[^- \t][^ \t]*)?)*[ \t]+(--worktree|-w([= \t`"\047]|$))/ \
      && seg[i] !~ /--tmux[= \t]+["\047]?classic/) continue
    ok = 0
    for (j = i - window; j <= i + window; j++) {
      if (j < 1 || j > n) continue
      if (tolower(seg[j]) ~ /(^|[^a-z])(hand[- ]launch|prior launcher)/) { ok = 1; break }
    }
    if (!ok) printf "HIT\t%s:%d\n", name[i], line[i]
  }
  n = 0
}
FNR == 1 { flush(); scanned++ }
{ sub(/\r$/, "") }
/^[ \t]*(#[ \t]*)?$/ { flush(); next }
{
  rest = $0
  while ((k = index(rest, ". ")) > 0) {
    seg[++n] = substr(rest, 1, k); name[n] = FILENAME; line[n] = FNR
    rest = substr(rest, k + 2)
  }
  seg[++n] = rest; name[n] = FILENAME; line[n] = FNR
}
END { flush(); printf "SCANNED\t%d\n", scanned }
'

# Each awk batch reports its own SCANNED count; the sum is the whole scan. A
# batch that fails says so in-band, since only the last command's status would
# survive the substitution. The repository's own run reads the tracked tree, so
# a local scratch file can neither fail nor pass the gate; a --root tree (the
# test fixtures) is read from the filesystem.
#
# The spec home comes from its resolver, since it can be relocated. When it
# does not resolve, or lies outside the scanned tree, nothing is excluded for
# it: that only widens the scan, so it can fail the gate but never pass it.
here=$(pwd -P) || exit 2
spec_rel=""
if spec_abs=$("$script_dir/resolve-root.sh" spec 2>/dev/null); then
  case "$spec_abs" in
    "$here"/?*) spec_rel=${spec_abs#"$here"/} ;;
  esac
fi
if [ "$root_given" -eq 0 ]; then
  list=$(mktemp) || exit 2
  trap 'rm -f "$list"' EXIT
  set -- docs doctrine skills scripts config ':(glob)**/README*' \
    ':(exclude)tests' ':(exclude,glob)**/.*/**' ':(exclude,glob)**/CHANGELOG.md'
  [ -z "$spec_rel" ] || set -- "$@" ":(exclude)$spec_rel"
  git ls-files -z -- "$@" >"$list" || {
    echo "check-launch-shape: cannot list the tracked tree; failing closed" >&2
    exit 2
  }
  # A tracked path the checkout lacks (a deletion not yet committed) is
  # skipped: there is no prose there to ship.
  export SCAN_PROGRAM="$scan_program"
  # shellcheck disable=SC2016 # the inner shell expands these, not this one
  out=$(
    [ ! -s "$list" ] \
      || xargs -0 sh -c 'for f do shift; [ ! -e "$f" ] || set -- "$@" "$f"; done
        [ "$#" -eq 0 ] || exec awk -v window="$0" "$SCAN_PROGRAM" "$@"' "$WINDOW" <"$list" \
      || printf 'FAILED\n'
  )
else
  # A spec home relocated inside a scanned directory is pruned there too. With
  # no spec home to exclude, `/` and `.//` are paths these finds never produce.
  out=$(
    for d in docs doctrine skills scripts config; do
      [ -d "$d" ] || continue
      find -H "$d" \( -name '.?*' -o -path "${spec_rel:-/}" \) -prune \
        -o -type f ! -name CHANGELOG.md \
        -exec awk -v window="$WINDOW" "$scan_program" {} + || printf 'FAILED\n'
    done
    find . \( -path "./${spec_rel:-/}" -o -path ./tests -o -path ./docs -o -path ./doctrine \
      -o -path ./skills -o -path ./scripts -o -path ./config -o -name '.?*' \) -prune \
      -o -type f -name 'README*' ! -name CHANGELOG.md \
      -exec awk -v window="$WINDOW" "$scan_program" {} + || printf 'FAILED\n'
  )
fi
case "$NL$out$NL" in
  *"${NL}FAILED$NL"*)
    echo "check-launch-shape: the scan itself failed; failing closed" >&2
    exit 2
    ;;
esac

scanned=$(printf '%s\n' "$out" | awk -F '\t' '$1 == "SCANNED" { s += $2 } END { print s + 0 }')
case "$scanned" in
  '' | *[!0-9]* | 0)
    echo "check-launch-shape: no file in scope under the root; failing closed" >&2
    exit 2
    ;;
esac

hits=$(printf '%s\n' "$out" | awk '/^HIT\t/ { h = substr($0, 5); sub(/^\.\//, "", h); print h }') || {
  echo "check-launch-shape: cannot read the scan's findings; failing closed" >&2
  exit 2
}
if [ -n "$hits" ]; then
  printf '%s\n' "$hits" | while IFS= read -r h; do
    printf 'check-launch-shape: %s: names the native worktree launcher without a hand-launch label\n' \
      "$(sanitize_printable "$h" '<unprintable path>')" >&2
  done
  echo "  The tmux rung launches its worker in a detached session (fleet-hardening D-10)." >&2
  echo "  Describe that launch instead, or label the mention an operator's hand-launch." >&2
  exit 1
fi
printf 'check-launch-shape: %s file(s) scanned, no unlabeled launch-shape mention.\n' "$scanned"
exit 0
