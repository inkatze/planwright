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
# than as one paragraph; a blank line ends a paragraph. Every mention has to be
# labeled, whatever it says about the launch: deciding whether prose "presents"
# a launch is a judgment, and a label is something a script can see.
#
# SCOPE. docs/, doctrine/, skills/, scripts/ and config/ in full, plus every
# README outside specs/, tests/ and dot-directories. Out of scope: specs/
# (decision records quote the old shape), tests/ (fixtures quote it as negative
# cases), and any CHANGELOG.md (release history).
#
# Usage: check-launch-shape.sh [--root <dir>]
#   --root  the tree to scan; default the enclosing git work tree.
# Exit: 0 clean · 1 an unlabeled mention · 2 usage, environment, or nothing to
#   scan (a scan that reached no file fails closed rather than passing).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

WINDOW=2

usage() {
  echo "usage: check-launch-shape.sh [--root <dir>]" >&2
  exit 2
}

root=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      [ "$#" -ge 2 ] || usage
      [ -z "$root" ] || usage
      root="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

if [ -z "$root" ]; then
  if ! root=$(git rev-parse --show-toplevel 2>/dev/null); then
    echo "check-launch-shape: not inside a git work tree and no --root given" >&2
    exit 2
  fi
fi
cd "$root" 2>/dev/null || {
  echo "check-launch-shape: cannot enter the root to scan" >&2
  exit 2
}

# The patterns are spelled so this file's own code never matches them.
# shellcheck disable=SC2016 # the $-fields below are awk's, not the shell's
scan_program='
function flush(   i, j, ok, wrapped) {
  for (i = 1; i <= n; i++) {
    # A mention wrapped across a line break (comment leader included) counts
    # at its first line.
    wrapped = i < n && line[i + 1] == line[i] + 1 && seg[i] ~ /claude[ \t]*$/ \
      && seg[i + 1] ~ /^[ \t]*(#[ \t]*)?--worktree/
    if (!wrapped && seg[i] !~ /claude[ \t]+--worktree/ && seg[i] !~ /--tmux[= ]classic/) continue
    ok = 0
    for (j = i - window; j <= i + window; j++) {
      if (j < 1 || j > n) continue
      if (tolower(seg[j]) ~ /hand[- ]launch|prior launcher/) { ok = 1; break }
    }
    if (!ok) printf "HIT\t%s:%d\n", name[i], line[i]
  }
  n = 0
}
FNR == 1 { flush(); scanned++ }
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

# Each find batch reports its own SCANNED count; the sum is the whole scan. A
# batch that fails says so in-band, since only the last command's status would
# survive the substitution.
out=$(
  for d in docs doctrine skills scripts config; do
    [ -d "$d" ] || continue
    find "$d" -type f ! -name CHANGELOG.md \
      -exec awk -v window="$WINDOW" "$scan_program" {} + || printf 'FAILED\n'
  done
  find . \( -path ./specs -o -path ./tests -o -path ./docs -o -path ./doctrine \
    -o -path ./skills -o -path ./scripts -o -path ./config -o -name '.?*' \) -prune \
    -o -type f -name 'README*' ! -name CHANGELOG.md \
    -exec awk -v window="$WINDOW" "$scan_program" {} + || printf 'FAILED\n'
)
if printf '%s\n' "$out" | grep -qx FAILED; then
  echo "check-launch-shape: the scan itself failed; failing closed" >&2
  exit 2
fi

scanned=$(printf '%s\n' "$out" | awk -F '\t' '$1 == "SCANNED" { s += $2 } END { print s + 0 }')
if [ "$scanned" -eq 0 ]; then
  echo "check-launch-shape: no file in scope under the root; failing closed" >&2
  exit 2
fi

hits=$(printf '%s\n' "$out" | awk -F '\t' '$1 == "HIT" { sub(/^\.\//, "", $2); print $2 }' \
  | tr -d '\000-\010\013-\037\177')
if [ -n "$hits" ]; then
  printf '%s\n' "$hits" | while IFS= read -r h; do
    printf 'check-launch-shape: %s: names the native worktree launcher without a hand-launch label\n' "$h" >&2
  done
  echo "  The tmux rung launches its worker in a detached session (fleet-hardening D-10)." >&2
  echo "  Describe that launch instead, or label the mention an operator's hand-launch." >&2
  exit 1
fi
printf 'check-launch-shape: %s file(s) scanned, no unlabeled launch-shape mention.\n' "$scanned"
exit 0
