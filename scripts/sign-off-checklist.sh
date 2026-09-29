#!/bin/sh
# sign-off-checklist.sh — regenerate the pending-sign-off checklist from the
# `Planwright-Sign-Off` trailers in a PR's base..head range, and allocate the
# branch's next free `PS-<n>` (doctrine/gate-wiring.md, *The
# `Planwright-Sign-Off` trailer*).
#
# Usage:
#   sign-off-checklist.sh list <base> [<head>]
#       One line per pending item, oldest commit first:
#       <id> TAB <full sha> TAB <subject>
#       A commit carrying several trailers yields one line per trailer.
#   sign-off-checklist.sh next <base> [<head>]
#       The next free id, `PS-<max+1>` over every `PS-<n>` the range names.
#
# <head> defaults to HEAD.
#
# What counts:
#   - Trailers are read through git's own parser
#     (`%(trailers:key=Planwright-Sign-Off,valueonly)`), never from subjects.
#   - A legacy commit, one whose subject ends in ` [pending-sign-off]` and
#     that carries no `Planwright-Sign-Off` trailer, renders as
#     `PS-legacy-<sha7>`: the first seven hex characters of its full hash
#     (never `%h`, which grows with the repository). Legacy ids sit outside the
#     `PS-<n>` sequence, so `next` ignores them.
#   - A commit whose body carries git's `This reverts commit <sha>` line is
#     never an item and drops the commit it reverts, unless a later revert
#     undid it in turn (a revert of a revert reinstates the item).
#   - A `Planwright-Sign-Off-Rejected: <id>` trailer drops the item it names,
#     matched exactly, where <id> is `PS-<n>` or `PS-legacy-<sha7>`.
#   - A reverted or rejected id stays allocated: `next` never reuses it.
#
# Exit: 0 success (an empty list prints nothing); 2 usage error; 3
# unresolvable range (a base or head that does not resolve to a commit, e.g.
# an unfetched base, or no common ancestor); 4 legacy id collision (two legacy
# commits in the range share a seven-hex prefix). On 3 and 4 nothing is
# printed to stdout, so a failed regeneration never reads as an empty
# checklist and allocation never restarts the sequence.
#
# Portable POSIX sh and awk (the bash 3.2 / BSD floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

prog=${0##*/}

usage() {
  echo "usage: $prog (list|next) <base> [<head>]" >&2
  exit 2
}

[ "$#" -ge 2 ] && [ "$#" -le 3 ] || usage
mode=$1
base=$2
head=${3:-HEAD}
case "$mode" in
  list | next) ;;
  *) usage ;;
esac
# An option-shaped ref would reach git as a flag.
for ref in "$base" "$head"; do
  case "$ref" in
    '' | -*) usage ;;
  esac
done

unresolvable() {
  echo "$prog: unresolvable range: $1; no checklist emitted" >&2
  exit 3
}

base_sha=$(git rev-parse --verify --quiet "$base^{commit}") \
  || unresolvable "the base does not resolve to a commit (unfetched?)"
head_sha=$(git rev-parse --verify --quiet "$head^{commit}") \
  || unresolvable "the head does not resolve to a commit"
git merge-base "$base_sha" "$head_sha" >/dev/null 2>&1 \
  || unresolvable "the base and head share no common ancestor"

US=$(printf '\037')
RSEP=$(printf '\036')
GS=$(printf '\035')

log=$(git log --reverse \
  --format="%H%x1f%s%x1f%(trailers:key=Planwright-Sign-Off,valueonly,separator=%x1d)%x1f%(trailers:key=Planwright-Sign-Off-Rejected,valueonly,separator=%x1d)%x1f%b%x1e" \
  "$base_sha..$head_sha") \
  || unresolvable "git log failed over the range"

printf '%s' "$log" | awk -v FS="$US" -v RS="$RSEP" -v GS="$GS" -v mode="$mode" -v prog="$prog" '
function trim(s) {
  sub(/^[ \t\n]+/, "", s)
  sub(/[ \t\n]+$/, "", s)
  return s
}
function is_ps(v) { return v ~ /^PS-[1-9][0-9]*$/ }
function is_legacy(v) { return v ~ /^PS-legacy-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$/ }
{
  sha = $1
  sub(/^\n+/, "", sha)
  if (sha == "") next
  n++
  s = $2
  gsub(/\t/, " ", s)
  h[n] = sha; subj[n] = s; so[n] = $3; rej[n] = $4
  rv[n] = ""
  m = split($5, lines, "\n")
  for (i = 1; i <= m; i++) {
    if (substr(lines[i], 1, 20) == "This reverts commit ") {
      t = substr(lines[i], 21, 40)
      if (length(t) == 40 && t ~ /^[0-9a-f]+$/) rv[n] = rv[n] " " t
    }
  }
}
END {
  if (mode == "next") {
    max = 0
    for (k = 1; k <= n; k++) {
      c = split(so[k] GS rej[k], vals, GS)
      for (i = 1; i <= c; i++) {
        v = trim(vals[i])
        if (is_ps(v) && substr(v, 4) + 0 > max) max = substr(v, 4) + 0
      }
    }
    print "PS-" (max + 1)
    exit 0
  }
  # Newest first: a revert that is itself live drops its target, so a revert
  # of a revert cancels the first and reinstates the original.
  for (k = n; k >= 1; k--) {
    if (h[k] in dead || rv[k] == "") continue
    c = split(rv[k], ts, " ")
    for (i = 1; i <= c; i++) dead[ts[i]] = 1
  }
  for (k = 1; k <= n; k++) {
    if (h[k] in dead) continue
    c = split(rej[k], vals, GS)
    for (i = 1; i <= c; i++) {
      v = trim(vals[i])
      if (is_ps(v) || is_legacy(v)) rejected[v] = 1
    }
  }
  out = ""
  for (k = 1; k <= n; k++) {
    if (rv[k] != "") continue
    if (trim(so[k]) != "") {
      c = split(so[k], vals, GS)
      for (i = 1; i <= c; i++) {
        v = trim(vals[i])
        if (!is_ps(v)) {
          printf "%s: ignoring a malformed sign-off value on commit %s\n", prog, substr(h[k], 1, 12) > "/dev/stderr"
          continue
        }
        if (h[k] in dead || v in rejected) continue
        out = out v "\t" h[k] "\t" subj[k] "\n"
      }
    } else if (length(subj[k]) > 19 && substr(subj[k], length(subj[k]) - 18) == " [pending-sign-off]") {
      id = "PS-legacy-" substr(h[k], 1, 7)
      if (id in legacy) {
        printf "%s: legacy id collision: commits %s and %s both render as %s; no checklist emitted\n", prog, legacy[id], h[k], id > "/dev/stderr"
        exit 4
      }
      legacy[id] = h[k]
      if (h[k] in dead || id in rejected) continue
      out = out id "\t" h[k] "\t" subj[k] "\n"
    }
  }
  printf "%s", out
}
'
