#!/bin/sh
# sign-off-checklist.sh — regenerate the pending-sign-off checklist from the
# `Planwright-Sign-Off` trailers in a PR's base..head range, and allocate the
# branch's next free `PS-<n>` (doctrine/gate-wiring.md, *The
# `Planwright-Sign-Off` trailer*).
#
# Usage:
#   sign-off-checklist.sh list <base> [<head>]
#       One line per pending item, ancestors first:
#       <id> TAB <full sha> TAB <subject>
#       A commit carrying several trailers yields one line per trailer.
#       Control characters in the subject print as spaces.
#   sign-off-checklist.sh next <base> [<head>]
#       The next free id, `PS-<max+1>` over every `PS-<n>` the range names.
#
# <head> defaults to HEAD.
#
# What counts:
#   - Trailers are read through git's own parser
#     (`%(trailers:key=Planwright-Sign-Off,valueonly)`), never from subjects.
#     `PS-<n>` has at most nine digits; a longer or otherwise malformed value
#     is ignored with a warning.
#   - A legacy commit, one whose subject ends in ` [pending-sign-off]` and
#     that carries no `Planwright-Sign-Off` trailer, renders as
#     `PS-legacy-<sha7>`: the first seven hex characters of its full hash
#     (never `%h`, which grows with the repository). Legacy ids sit outside the
#     `PS-<n>` sequence, so `next` ignores them.
#   - A commit whose body carries git's `This reverts commit <sha>` line is
#     never an item (a trailer it carries is dropped with a warning) and drops
#     the commit it reverts, unless a later revert undid it in turn (a revert
#     of a revert reinstates the item). The hash may be full or, as
#     `git revert --reference` writes it, abbreviated to at least seven hex
#     characters; an abbreviation matching no commit, or several, in the range
#     pairs with nothing.
#   - A revert commit carrying a `Planwright-Sign-Off-Rejected` trailer that
#     names an id of the commit it reverts is a partial revert: it drops only
#     the ids it names, so one finding of a shared commit can be rejected
#     without dropping the rest.
#   - A `Planwright-Sign-Off-Rejected: <id>` trailer drops the item it names,
#     matched exactly, where <id> is `PS-<n>` or `PS-legacy-<sha7>`.
#   - A reverted or rejected id stays allocated: `next` never reuses it. One
#     `PS-<n>` on two commits (two stamps allocated from the same head) is
#     listed twice with a warning.
#
# Exit: 0 success (an empty list prints nothing); 2 usage error; 3
# unresolvable range (not a repository, a base or head that does not resolve
# to a commit, e.g. an unfetched base, no common ancestor, or a log record that
# does not parse, which a separator character inside a commit message causes);
# 4 legacy id collision (two legacy commits in the range share a seven-hex
# prefix). On 3 and 4 nothing is printed to stdout, so a failed regeneration
# never reads as an empty checklist and allocation never restarts the
# sequence.
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

git rev-parse --git-dir >/dev/null 2>&1 \
  || unresolvable "not inside a git repository"
base_sha=$(git rev-parse --verify --quiet "$base^{commit}") \
  || unresolvable "the base does not resolve to a commit (unfetched?)"
head_sha=$(git rev-parse --verify --quiet "$head^{commit}") \
  || unresolvable "the head does not resolve to a commit"
git merge-base "$base_sha" "$head_sha" >/dev/null 2>&1 \
  || unresolvable "the base and head share no common ancestor"
expected=$(git rev-list --count "$base_sha..$head_sha") \
  || unresolvable "git rev-list failed over the range"

US=$(printf '\037')
RSEP=$(printf '\036')
GS=$(printf '\035')

# --topo-order: the revert pairing below walks descendants before ancestors,
# which committer-date order does not guarantee across a merge.
# log.showSignature would print verification lines between the records.
log=$(git -c log.showSignature=false log --topo-order --reverse \
  --format="%H%x1f%s%x1f%(trailers:key=Planwright-Sign-Off,valueonly,separator=%x1d)%x1f%(trailers:key=Planwright-Sign-Off-Rejected,valueonly,separator=%x1d)%x1f%b%x1e" \
  "$base_sha..$head_sha") \
  || unresolvable "git log failed over the range"

printf '%s' "$log" | awk -v FS="$US" -v RS="$RSEP" -v GS="$GS" -v mode="$mode" \
  -v prog="$prog" -v expected="$expected" '
function trim(s) {
  sub(/^[ \t\n]+/, "", s)
  sub(/[ \t\n]+$/, "", s)
  return s
}
function is_ps(v) { return v ~ /^PS-[1-9][0-9]*$/ && length(v) <= 12 }
function is_legacy(v) { return v ~ /^PS-legacy-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$/ }
function warn(msg) { printf "%s: %s\n", prog, msg > "/dev/stderr" }
function malformed() {
  warn("unresolvable range: a git log record does not parse (a separator character in a commit message?); no checklist emitted")
  bad = 1
  exit 3
}
# The leading hex run of s.
function hexrun(s,  i) {
  for (i = 1; i <= length(s) && index("0123456789abcdef", substr(s, i, 1)) > 0; i++) ;
  return substr(s, 1, i - 1)
}
# The in-range commit a revert names: exact for a full hash, else the unique
# commit the abbreviation prefixes; "" when none or several match.
function target(t,  j, hit) {
  if (t in seen) return t
  hit = ""
  for (j = 1; j <= n; j++) {
    if (substr(h[j], 1, length(t)) == t) {
      if (hit != "") return ""
      hit = h[j]
    }
  }
  return hit
}
{
  sha = $1
  sub(/^\n+/, "", sha)
  if (sha == "" && NF <= 1) next
  if (NF != 5 || (length(sha) != 40 && length(sha) != 64) || hexrun(sha) != sha || sha in seen) malformed()
  n++
  seen[sha] = n
  s = $2
  # C0 controls, DEL, and the UTF-8 encoding of the C1 controls (CSI among
  # them), which a terminal also acts on.
  gsub(/[[:cntrl:]]/, " ", s)
  gsub(/\302[\200-\237]/, " ", s)
  h[n] = sha; subj[n] = s; so[n] = $3; rej[n] = $4
  rv[n] = ""
  m = split($5, lines, "\n")
  for (i = 1; i <= m; i++) {
    if (substr(lines[i], 1, 20) == "This reverts commit ") {
      t = hexrun(substr(lines[i], 21))
      if (length(t) >= 7) rv[n] = rv[n] " " t
    }
  }
}
END {
  if (bad) exit 3
  if (n != expected) malformed()
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
  # A revert is partial when a rejected id it carries belongs to a commit it
  # reverts; a rejection of some other commit leaves it a full revert.
  for (k = 1; k <= n; k++) {
    partial[k] = 0
    if (rv[k] == "" || rej[k] == "") continue
    c = split(rv[k], ts, " ")
    for (i = 1; i <= c; i++) {
      t = target(ts[i])
      if (t == "") continue
      delete own
      own["PS-legacy-" substr(t, 1, 7)] = 1
      d = split(so[seen[t]], vals, GS)
      for (e = 1; e <= d; e++) own[trim(vals[e])] = 1
      d = split(rej[k], vals, GS)
      for (e = 1; e <= d; e++) {
        v = trim(vals[e])
        if (v in own) partial[k] = 1
      }
    }
  }
  # Descendants first: a revert that is itself live drops its target, so a
  # revert of a revert cancels the first and reinstates the original. A
  # partial revert drops nothing here; its rejected trailers do the dropping.
  for (k = n; k >= 1; k--) {
    if (h[k] in dead || rv[k] == "" || partial[k]) continue
    c = split(rv[k], ts, " ")
    for (i = 1; i <= c; i++) {
      t = target(ts[i])
      if (t != "") dead[t] = 1
    }
  }
  for (k = 1; k <= n; k++) {
    if (h[k] in dead) continue
    c = split(rej[k], vals, GS)
    for (i = 1; i <= c; i++) {
      v = trim(vals[i])
      if (is_ps(v) || is_legacy(v)) rejected[v] = 1
    }
  }
  nout = 0
  for (k = 1; k <= n; k++) {
    if (rv[k] != "") {
      if (trim(so[k]) != "") warn("commit " substr(h[k], 1, 12) " is a revert, so its sign-off trailers are not items")
      continue
    }
    if (trim(so[k]) != "") {
      c = split(so[k], vals, GS)
      for (i = 1; i <= c; i++) {
        v = trim(vals[i])
        if (!is_ps(v)) {
          warn("ignoring a malformed sign-off value on commit " substr(h[k], 1, 12))
          continue
        }
        if (v in owner && owner[v] != h[k]) warn(v " is stamped on two commits, " substr(owner[v], 1, 12) " and " substr(h[k], 1, 12) "; one rejected trailer drops both")
        owner[v] = h[k]
        if (h[k] in dead || v in rejected) continue
        out[++nout] = v "\t" h[k] "\t" subj[k]
      }
    } else if (length(subj[k]) > 19 && substr(subj[k], length(subj[k]) - 18) == " [pending-sign-off]") {
      id = "PS-legacy-" substr(h[k], 1, 7)
      if (id in legacy) {
        warn("legacy id collision: commits " legacy[id] " and " h[k] " both render as " id "; no checklist emitted")
        exit 4
      }
      legacy[id] = h[k]
      if (h[k] in dead || id in rejected) continue
      out[++nout] = id "\t" h[k] "\t" subj[k]
    }
  }
  for (i = 1; i <= nout; i++) print out[i]
}
'
