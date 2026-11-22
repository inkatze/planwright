#!/bin/sh
# orchestrate-primary-ff.sh — /orchestrate's opt-in pre-flight fast-forward of
# a lagging primary checkout, so a step reads current specs rather than the
# ones the checkout last saw.
#
# Off unless the `orchestrate_fast_forward_primary` knob is true; off, it
# touches neither the checkout nor origin. On, it delegates to
# scripts/main-currency.sh ff-primary, the one sanctioned primary
# fast-forward: it fetches, then moves the primary checkout's default branch
# by `merge --ff-only` only when that branch is checked out, nothing tracked
# is uncommitted, no operation is in progress, and the branch is an ancestor
# of origin's. Anything else is refused and left exactly as it was; this
# never merges, resets or rebases. Every move is recorded with its old and
# new heads in <git-common-dir>/planwright/main-currency.log and logged on
# stderr.
#
# Usage: orchestrate-primary-ff.sh [--checkout <primary checkout>]
#   --checkout  the primary checkout's top level (default: the primary of the
#               repository holding the current directory); the knob is read
#               there.
#
# Output, one tab-separated line on stdout:
#   primary-ff	disabled
#   primary-ff	solo                      (no origin configured)
#   primary-ff	up-to-date	<branch>	<head>
#   primary-ff	fast-forward	<branch>	<old head>	<new head>
#   primary-ff	refused
#   primary-ff	stale-transient
#
# Exit: 0 disabled, solo, up-to-date or fast-forwarded; 2 usage or a broken
# install; 3 transient (fetch or git read failure; retry next step); 4 refused
# (a dirty tree, another branch or a detached HEAD, a diverged branch, or a
# checkout shape ff-primary refuses), its reason on stderr.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd -- "$(dirname -- "$0")" && pwd) || exit 2
if [ -r "$script_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$script_dir/echo-safety.sh"
else
  printf '%s\n' "orchestrate-primary-ff: broken install: echo-safety.sh is missing or unreadable" >&2
  exit 2
fi

err() {
  printf 'orchestrate-primary-ff: %s\n' "$1" >&2
}

checkout=''
while [ $# -gt 0 ]; do
  case "$1" in
    --checkout)
      [ $# -ge 2 ] && [ -n "$2" ] || {
        err "--checkout needs a value"
        exit 2
      }
      checkout=$2
      shift 2
      ;;
    *)
      err "unexpected argument '$(sanitize_printable "$1")'"
      printf '%s\n' "usage: orchestrate-primary-ff.sh [--checkout <primary checkout>]" >&2
      exit 2
      ;;
  esac
done

if [ -n "$checkout" ]; then
  cd -- "$checkout" 2>/dev/null || {
    err "cannot enter checkout directory '$(sanitize_printable "$checkout")'"
    exit 2
  }
fi

unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
top=$(/bin/sh "$script_dir/resolve-root.sh" repo --primary) && [ -n "$top" ] || {
  err "no primary checkout resolves from $(sanitize_printable "$(pwd)")"
  exit 2
}

knob=orchestrate_fast_forward_primary
kv=$(PLANWRIGHT_REPO_ROOT=$top "$script_dir/config-get.sh" "$knob")
krc=$?
case $krc:$kv in
  0:true) ;;
  0:false | 3:*)
    printf 'primary-ff\tdisabled\n'
    exit 0
    ;;
  0:*)
    err "$knob is '$(sanitize_printable "$kv")', not true or false; leaving the primary checkout as it is"
    printf 'primary-ff\tdisabled\n'
    exit 0
    ;;
  *)
    err "could not read $knob (config-get exit $krc); leaving the primary checkout as it is"
    printf 'primary-ff\tdisabled\n'
    exit 0
    ;;
esac

if [ -n "$checkout" ]; then
  res=$("$script_dir/main-currency.sh" ff-primary --checkout "$(pwd -P)")
else
  res=$("$script_dir/main-currency.sh" ff-primary)
fi
rc=$?

field() {
  printf '%s\n' "$res" | awk -F '\t' -v k="$1" '$1 == k { print $2; exit }'
}

case $rc in
  0) ;;
  3)
    printf 'primary-ff\tstale-transient\n'
    exit 3
    ;;
  4 | 6 | 7)
    err "the primary checkout was left exactly as it was"
    printf 'primary-ff\trefused\n'
    exit 4
    ;;
  *)
    err "main-currency.sh ff-primary failed (exit $rc); the primary checkout was left as it was"
    exit 2
    ;;
esac

sync=$(field sync)
branch=$(field branch)
head=$(field main)
case $sync in
  solo) printf 'primary-ff\tsolo\n' ;;
  up-to-date) printf 'primary-ff\tup-to-date\t%s\t%s\n' "$branch" "$head" ;;
  fast-forward)
    old=$(field before)
    err "fast-forwarded $(sanitize_printable "$branch") in $(sanitize_printable "$(field checkout)") from ${old:-(unborn)} to $head"
    printf 'primary-ff\tfast-forward\t%s\t%s\t%s\n' "$branch" "$old" "$head"
    ;;
  *)
    err "main-currency.sh ff-primary reported an unknown outcome '$(sanitize_printable "$sync")'"
    exit 2
    ;;
esac
exit 0
