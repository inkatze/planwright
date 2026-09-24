#!/bin/sh
# flight-id.sh — the flight-id grammar and the never-reuse rule
# (tower-front-door REQ-C1.1, D-11).
#
# A visual flight is a specless unit, so it cannot borrow the task-id grammar;
# it gets its own id: `<slug>-<uid>`, a kebab slug in the spec-identifier
# charset (`^[a-z0-9][a-z0-9-]*$`) plus an eight-character lowercase-hex uid,
# at most 64 characters in all. The derived names are the flight branch
# `planwright/flight/<flight-id>` and the worktree suffix `flight-<flight-id>`
# (the flattened single-segment form of the D-37 placement rule). This helper
# is the one place that mints, checks, and derives them, so every caller
# agrees on the grammar.
#
# Usage:
#   flight-id.sh new <slug> [--repo-root <dir>]
#   flight-id.sh check <flight-id>
#   flight-id.sh taken <flight-id> [--repo-root <dir>]
#   flight-id.sh branch <flight-id>
#   flight-id.sh suffix <flight-id>
#
# new     mints `<slug>-<uid>` and prints it. The uid is random, and a
#         candidate is skipped while durable evidence of that id exists
#         (never-reuse): a local branch `refs/heads/planwright/flight/<id>`, a
#         remote-tracking branch `refs/remotes/*/planwright/flight/<id>`, a
#         record file `specs/_flights/<id>.md` in the working tree or in the
#         `main` / `origin/main` tree, or a placed worktree
#         `.claude/worktrees/flight-<id>` under the primary checkout. The
#         slug is grammar-checked before anything is minted (REQ-F1.1).
# check   exits 0 when the argument is a grammar-valid flight id, 1 otherwise.
#         The candidate is never echoed back: a hostile value must not reach
#         an output a caller might interpolate.
# taken   prints one `evidence<TAB><class><TAB><what>` line per piece of
#         durable evidence (classes: branch, record, worktree) and exits 0;
#         exits 1 when there is none.
# branch / suffix
#         print the derived branch name / worktree suffix for a checked id.
#
# PLANWRIGHT_FLIGHT_UID_SOURCE=<file> replaces the random uid source with the
# file's lines, tried in order (a deterministic source for tests and replays).
#
# Exit: 0 success; 1 check failed / not taken; 2 usage error or a malformed
# argument (nothing minted, nothing echoed); 3 every uid candidate was taken;
# 4 no usable uid source; 5 the evidence probe failed (a git error, never
# read as "no evidence").
#
# Portable POSIX sh (the bash 3.2 / busybox floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

prog=flight-id
LF='
'

usage() {
  cat >&2 <<'USAGE'
usage: flight-id.sh new <slug> [--repo-root <dir>]
       flight-id.sh check <flight-id>
       flight-id.sh taken <flight-id> [--repo-root <dir>]
       flight-id.sh branch <flight-id>
       flight-id.sh suffix <flight-id>
USAGE
  exit 2
}

# The slug half: the spec-identifier charset, bounded so that `<slug>-<uid>`
# stays within the 64-character identifier ceiling.
valid_slug() {
  case $1 in
    '' | *"$LF"* | *[!a-z0-9-]* | [!a-z0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 55 ]
}

valid_uid() {
  case $1 in
    *"$LF"* | *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#1}" -eq 8 ]
}

valid_flight_id() {
  case $1 in
    *"$LF"* | *[!a-z0-9-]* | [!a-z0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ] || return 1
  [ "${#1}" -ge 10 ] || return 1
  _uid=${1##*-}
  _slug=${1%-*}
  valid_uid "$_uid" && valid_slug "$_slug"
}

# Resolve the repo root and the primary checkout (worktree dirs live under the
# primary, while refs and trees are shared).
resolve_repo() {
  if [ -z "$repo_root" ]; then
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
      echo "$prog: not inside a git work tree and no --repo-root given" >&2
      exit 2
    }
  fi
  repo_root=$(cd "$repo_root" 2>/dev/null && pwd -P) || {
    echo "$prog: --repo-root is not a directory" >&2
    exit 2
  }
  common=$(git -C "$repo_root" rev-parse --git-common-dir 2>/dev/null) || {
    echo "$prog: --repo-root is not a git work tree" >&2
    exit 2
  }
  case $common in
    /*) ;;
    *) common=$repo_root/$common ;;
  esac
  common=$(cd "$common" 2>/dev/null && pwd -P) || common=""
  case $common in
    */.git) primary=${common%/.git} ;;
    *) primary=$repo_root ;;
  esac
}

# A git failure while probing is not "no evidence": refuse to judge the id
# rather than mint it over a branch or record the probe could not read.
probe_failed() {
  echo "$prog: evidence probe failed ($1); refusing to judge the id" >&2
  exit 5
}

# evidence_for <id> — collect the durable evidence lines for a checked id
# into `found` (one `evidence<TAB><class><TAB><what>` per line). It runs in
# the calling shell, never a command substitution, so a probe failure exits
# the script instead of reading as an empty (free) result.
found=""
add_evidence() {
  _line=$(printf 'evidence\t%s\t%s' "$1" "$2")
  found="${found}${_line}${LF}"
}
evidence_for() {
  _id=$1
  found=""
  _ref=refs/heads/planwright/flight/$_id
  _rc=0
  git -C "$repo_root" show-ref --verify --quiet "$_ref" 2>/dev/null || _rc=$?
  case $_rc in
    0) add_evidence branch "$_ref" ;;
    1) ;;
    *) probe_failed "show-ref" ;;
  esac
  _remotes=$(git -C "$repo_root" for-each-ref --format='%(refname)' \
    "refs/remotes/*/planwright/flight/$_id" 2>/dev/null) || probe_failed "for-each-ref"
  # Ref names carry no whitespace, so splitting the list on it is exact.
  # shellcheck disable=SC2086
  for _r in $_remotes; do
    add_evidence branch "$_r"
  done
  _rec=specs/_flights/$_id.md
  if [ -e "$repo_root/$_rec" ]; then
    add_evidence record "$_rec"
  fi
  for _base in main origin/main; do
    git -C "$repo_root" rev-parse --verify --quiet "$_base^{commit}" >/dev/null 2>&1 || continue
    _hit=$(git -C "$repo_root" ls-tree --name-only "$_base" -- "$_rec" 2>/dev/null) \
      || probe_failed "ls-tree $_base"
    if [ -n "$_hit" ]; then
      add_evidence record "$_base:$_rec"
    fi
  done
  _wt=.claude/worktrees/flight-$_id
  if [ -e "$primary/$_wt" ]; then
    add_evidence worktree "$_wt"
  fi
}

# next_uid — set `uid` to the next candidate, or return 1 when the source is
# exhausted. It runs in the calling shell (not a command substitution) so the
# counter advances; the random source is bounded so a pathological evidence
# set ends in a clear exit 3 rather than a spin.
uid_n=0
uid=""
next_uid() {
  uid_n=$((uid_n + 1))
  if [ -n "${PLANWRIGHT_FLIGHT_UID_SOURCE:-}" ]; then
    uid=$(sed -n "${uid_n}p" "$PLANWRIGHT_FLIGHT_UID_SOURCE" 2>/dev/null) || uid=""
    [ -n "$uid" ] || return 1
    valid_uid "$uid" || {
      echo "$prog: malformed uid in PLANWRIGHT_FLIGHT_UID_SOURCE (line $uid_n)" >&2
      exit 2
    }
    return 0
  fi
  [ "$uid_n" -le 16 ] || return 1
  [ -r /dev/urandom ] || {
    echo "$prog: no usable uid source (/dev/urandom unreadable)" >&2
    exit 4
  }
  uid=$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n') || uid=""
  valid_uid "$uid" || {
    echo "$prog: no usable uid source (/dev/urandom read failed)" >&2
    exit 4
  }
}

[ $# -ge 1 ] || usage
cmd=$1
shift
repo_root=""

# The positional first, then options; every value is checked before use.
case $cmd in
  new | check | taken | branch | suffix)
    [ $# -ge 1 ] || usage
    arg=$1
    shift
    ;;
  *) usage ;;
esac
while [ $# -gt 0 ]; do
  case $1 in
    --repo-root)
      [ $# -ge 2 ] || usage
      case $cmd in new | taken) ;; *) usage ;; esac
      repo_root=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

case $cmd in
  check)
    valid_flight_id "$arg" && exit 0
    echo "$prog: not a flight id (expected <slug>-<uid>: slug ^[a-z0-9][a-z0-9-]*\$, uid eight lowercase hex characters, 64 characters at most)" >&2
    exit 1
    ;;
  branch)
    valid_flight_id "$arg" || {
      echo "$prog: refusing to derive a branch from a malformed flight id" >&2
      exit 1
    }
    printf 'planwright/flight/%s\n' "$arg"
    ;;
  suffix)
    valid_flight_id "$arg" || {
      echo "$prog: refusing to derive a worktree suffix from a malformed flight id" >&2
      exit 1
    }
    printf 'flight-%s\n' "$arg"
    ;;
  taken)
    valid_flight_id "$arg" || {
      echo "$prog: refusing to look up a malformed flight id" >&2
      exit 2
    }
    resolve_repo
    evidence_for "$arg"
    [ -n "$found" ] || exit 1
    printf '%s' "$found"
    ;;
  new)
    valid_slug "$arg" || {
      echo "$prog: refusing a malformed slug (expected ^[a-z0-9][a-z0-9-]*\$, 55 characters at most)" >&2
      exit 2
    }
    resolve_repo
    while next_uid; do
      candidate=$arg-$uid
      evidence_for "$candidate"
      if [ -z "$found" ]; then
        printf '%s\n' "$candidate"
        exit 0
      fi
    done
    echo "$prog: every uid candidate for slug '$arg' is already taken" >&2
    exit 3
    ;;
esac
