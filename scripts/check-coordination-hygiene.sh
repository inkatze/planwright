#!/bin/sh
# check-coordination-hygiene.sh — the conditional coordination-artifact hygiene
# guard (concurrent-orchestrator-coordination Task 5; D-9 · REQ-D1.4).
#
# Presence records, the `origin` fence namespace, and the strand sink are
# runtime, machine-local, uncommitted surfaces: normally nothing they hold ever
# reaches git, and this guard is a clean no-op. It exists for the case where a
# deployment DOES commit a coordination artifact — an audit or handover log, a
# summary of presence records, a PR body that quotes one — because those
# surfaces carry a peer tower's machine-local CHECKOUT PATH and its DEATH
# HANDLE (a pid, or a tmux session + window name), which are operational detail
# that must not leak into a committed artifact (REQ-D1.4). The guard is
# conditional in both directions: it screens what actually landed in git, and
# finding nothing to screen is a pass, never a failure.
#
# WHAT COUNTS AS A COMMITTED COORDINATION ARTIFACT. Detection is by RECORD
# SHAPE, not by a prose mention, so a design doc that describes the record
# format is not mistaken for one. A tracked file qualifies when it carries at
# least one line that IS a coordination record:
#   - a presence record: ten tab-separated fields whose first is the writer's
#     own schema tag `pw-presence-v1`, at column 1; or
#   - a fence-ref line: a bare `refs/planwright-fence/<...>` name at column 1.
# A deployment whose artifact is neither shape (a PR body, a prose handover
# log) names it: the path arguments screen those unconditionally.
#
# WHAT IT SCREENS FOR, in an artifact it did identify:
#   checkout-path      an absolute machine-local home path (a peer's checkout)
#   death-handle       either fleet-death-evidence.sh form
#   internal-hostname  a non-public host suffix or a private-IP literal
#   secret             delegated to scripts/inception-secret-screen.sh, which
#                      already owns the credential shapes and the gitleaks
#                      seam — consumed, never re-implemented
#
# A finding is reported as `<file>:<line>: <rule>` and NEVER carries the
# matched text: a guard that echoes what it caught has moved the leak out of
# the artifact and into the CI log, which is the failure it exists to prevent
# (doctrine/security-posture.md, echo discipline).
#
# Usage:
#   check-coordination-hygiene.sh [--repo <dir>]      scan the tracked tree
#   check-coordination-hygiene.sh [--] <path>...      screen declared artifacts
#
# Exit: 0 clean, or nothing to screen · 1 a leak was found · 2 usage or
#   environment error (including a path the screen could not read — this guard
#   never reports on what it has not read).
#
# Portable POSIX sh + grep -E + awk; bash 3.2 / BSD tooling floor.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

usage() {
  echo "usage: check-coordination-hygiene.sh [--repo <dir>]" >&2
  echo "       check-coordination-hygiene.sh [--] <path>..." >&2
  exit 2
}

repo=""
opts=1
npaths=0
nargs=$#
while [ "$nargs" -gt 0 ]; do
  arg=$1
  shift
  nargs=$((nargs - 1))
  if [ "$opts" -eq 1 ]; then
    case $arg in
      --repo)
        [ "$nargs" -ge 1 ] || usage
        [ -z "$repo" ] || usage
        repo=$1
        shift
        nargs=$((nargs - 1))
        continue
        ;;
      --)
        opts=0
        continue
        ;;
      -*) usage ;;
    esac
  fi
  # Paths stay IN "$@" and are never joined into one string: a name may carry
  # a newline, and splitting a joined list back apart would screen it zero
  # times while still reporting clean (the sibling screen's rule).
  set -- "$@" "$arg"
  npaths=$((npaths + 1))
done

[ "$npaths" -eq 0 ] || [ -z "$repo" ] || usage

TAB=$(printf '\t')

# --- the leak rules --------------------------------------------------------
#
# One `<rule><TAB><ERE>` line per class. grep -E is the engine because POSIX
# requires interval expressions there and not in awk, and because `grep -n`
# yields the line number without ever handing the matched text back.
#
# The two path roots are the shapes a peer tower's `--checkout` actually takes
# on the supported hosts; `/root` is included because an unattended tower may
# run as root. The death-handle patterns are the two forms
# fleet-death-evidence.sh declares and nothing else. The hostname rule requires
# the private suffix to be TERMINAL, so a filename like `planwright.local.yml`
# is not mistaken for a host.
rules=$(
  cat <<'RULES'
checkout-path	(/home/|/Users/)[A-Za-z0-9._-]+|/root(/|$)
death-handle	(^|[^A-Za-z0-9_-])process [1-9][0-9]{0,9}([^0-9]|$)
death-handle	(^|[^A-Za-z0-9_-])tmux-window [A-Za-z0-9_@%.-]{1,128} [A-Za-z0-9_@%.-]{1,128}
internal-hostname	[A-Za-z0-9-]+\.(internal|intranet|corp|lan|local)($|[^A-Za-z0-9.-])
internal-hostname	(^|[^0-9.])(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)[0-9]{1,3}\.[0-9]{1,3}
RULES
)

found=0
unreadable=0

# is_artifact <path> — true when the file carries at least one line that IS a
# coordination record (the shapes above), false for a prose mention of the
# format. Binary files never match: the shapes are anchored, tab-delimited
# text.
is_artifact() {
  # `hit` is a flag, not an early `exit 0`: an `exit` inside a rule still runs
  # END, whose own `exit` status would override it.
  awk -F'\t' '
    NF == 10 && $1 == "pw-presence-v1" { hit = 1; exit }
    $0 ~ /^refs\/planwright-fence\/[^ \t]+$/ { hit = 1; exit }
    END { exit !hit }
  ' "$1" 2>/dev/null
}

# screen_file <path> <name-to-report> — apply every rule, then delegate the
# credential class. A file this cannot READ is not a file it may call clean.
screen_file() {
  sf_path=$1
  sf_name=$2
  if [ ! -r "$sf_path" ]; then
    printf '%s\n' "check-coordination-hygiene: cannot read $(sanitize_printable "$sf_name" '(unprintable path)'); refusing to pass it unscreened" >&2
    unreadable=1
    return
  fi
  sf_oifs=$IFS
  IFS='
'
  for sf_rule in $rules; do
    [ -n "$sf_rule" ] || continue
    sf_rname=${sf_rule%%"$TAB"*}
    sf_rpat=${sf_rule#*"$TAB"}
    # Not a pipeline: piping into `cut` would hand back cut's status and throw
    # grep's away, and grep's status is the point — 1 is "no match", 2 is
    # "could not read this", and only one of those means clean. `-a` because
    # grep otherwise decides a file is binary and skips it while reporting
    # clean.
    sf_rc=0
    sf_hits=$(grep -a -n -E -e "$sf_rpat" -- "$sf_path" 2>/dev/null) || sf_rc=$?
    if [ "$sf_rc" -gt 1 ]; then
      printf '%s\n' "check-coordination-hygiene: could not read $(sanitize_printable "$sf_name" '(unprintable path)'); refusing to pass it unscreened" >&2
      unreadable=1
      IFS=$sf_oifs
      return
    fi
    for sf_hit in $sf_hits; do
      [ -n "$sf_hit" ] || continue
      printf '%s:%s: %s (value redacted)\n' \
        "$(sanitize_printable "$sf_name" '(unprintable path)')" \
        "${sf_hit%%:*}" "$sf_rname" >&2
      found=1
    done
  done
  IFS=$sf_oifs

  # The credential class is the sibling screen's, consumed as-is: it already
  # owns the shapes, the gitleaks seam, and the never-echo-the-match rule.
  sf_src=0
  "$script_dir/inception-secret-screen.sh" -- "$sf_path" || sf_src=$?
  case $sf_src in
    0) ;;
    1)
      printf '%s\n' "$(sanitize_printable "$sf_name" '(unprintable path)'): secret (reported above by the secret screen, value redacted)" >&2
      found=1
      ;;
    *)
      printf '%s\n' "check-coordination-hygiene: the secret screen could not read $(sanitize_printable "$sf_name" '(unprintable path)'); refusing to pass it unscreened" >&2
      unreadable=1
      ;;
  esac
}

if [ "$npaths" -gt 0 ]; then
  # Declared-artifact mode: the deployment named these, so shape detection is
  # not consulted — a PR body is a coordination artifact because it was handed
  # over, not because it looks like a record.
  for p in "$@"; do
    screen_file "$p" "$p"
  done
else
  [ -n "$repo" ] || repo=.
  if ! git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "check-coordination-hygiene: $repo is not a git work tree" >&2
    exit 2
  fi
  # Prefilter on the two literal tags before the per-file shape check, so the
  # scan is one grep over the tracked tree plus an awk on the few candidates,
  # never an awk per tracked file.
  cand_rc=0
  candidates=$(git -C "$repo" grep -I -l -F \
    -e 'pw-presence-v1' -e 'refs/planwright-fence/' -- 2>/dev/null) || cand_rc=$?
  if [ "$cand_rc" -gt 1 ]; then
    echo "check-coordination-hygiene: could not scan the tracked tree of $repo" >&2
    exit 2
  fi
  artifacts=0
  oifs=$IFS
  IFS='
'
  for rel in $candidates; do
    [ -n "$rel" ] || continue
    IFS=$oifs
    if is_artifact "$repo/$rel"; then
      artifacts=$((artifacts + 1))
      screen_file "$repo/$rel" "$rel"
    fi
    IFS='
'
  done
  IFS=$oifs
  if [ "$artifacts" -eq 0 ]; then
    echo "check-coordination-hygiene: no committed coordination artifact — nothing to screen" >&2
    exit 0
  fi
fi

[ "$unreadable" -eq 0 ] || exit 2
[ "$found" -eq 0 ] || exit 1
exit 0
