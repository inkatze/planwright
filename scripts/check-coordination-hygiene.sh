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
#   - a presence record: the tab-separated field count `fleet-presence.sh`'s
#     `pw-presence-v1` schema declares (see its record header), with that tag
#     at column 1; or
#   - a fence-ref line: a bare `refs/planwright-fence/<...>` name at column 1
#     (fleet-fence.sh's `list` form), or one of its verb-prefixed forms with the
#     ref in field 2 — `strand <ref> <owner> <liveness>` is the strand-sink
#     entry, and it carries a peer's owner identity a bare-ref match never sees.
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
# A finding is reported as `<file>:<line>: <rule> (value redacted)`, or as
# `<file>: secret (...)` for the delegated credential class, which carries no
# line number because the sibling screen owns its own reporting. Neither form
# ever carries the matched text: a guard that echoes what it caught has moved
# the leak out of the artifact and into the CI log, which is the failure it
# exists to prevent (doctrine/security-posture.md, echo discipline).
#
# Usage:
#   check-coordination-hygiene.sh [--repo <dir>]      scan the tracked tree
#   check-coordination-hygiene.sh [--] <path>...      screen declared artifacts
# The two modes are exclusive: `--repo` combined with path arguments is a usage
# error, as is an empty `--repo` value or a repeated one.
#
# Exit: 0 clean, or nothing to screen · 1 a leak was found · 2 usage or
#   environment error (including a path the screen could not read — this guard
#   never reports on what it has not read). 2 outranks 1 when both occur: a run
#   that could not read part of what it was asked to screen has no verdict to
#   give, and findings already printed stay on stderr.
#
# Portable POSIX sh + awk, with the GNU/BSD-common `grep -a`; bash 3.2 / BSD
# tooling floor. Pathname expansion is disabled (`set -f`), as on the two
# coordination scripts this screens for: the rule table and grep's output are
# both split on IFS-newline, and both carry bracket and star bytes drawn from
# record content, which globbing would expand against the working directory.
set -uf
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
# Tracked separately from `$repo`'s value: an empty string is a legitimate-
# looking argument but a useless directory, and using emptiness itself as the
# "unset" sentinel would let `--repo ''` slip past the duplicate check, past the
# repo/paths exclusion below, and then be rewritten to `.` — scanning the
# working directory in answer to a question about somewhere else.
repo_set=0
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
        [ "$repo_set" -eq 0 ] || usage
        repo=$1
        [ -n "$repo" ] || usage
        repo_set=1
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

[ "$npaths" -eq 0 ] || [ "$repo_set" -eq 0 ] || usage

TAB=$(printf '\t')

# --- the leak rules --------------------------------------------------------
#
# One or more `<rule><TAB><ERE>` lines per class; a class with several shapes
# gets one line each. grep -E is the engine because interval expressions are
# unreliable in the legacy awks inside this repo's tooling floor while every
# grep -E in it supports them, and because `grep -n` prefixes each hit with its
# line number — so the report can be built from that prefix alone and the
# matched text dropped, rather than printed.
#
# The path roots are the shapes a peer tower's `--checkout` takes on the
# supported hosts, plus `/root` for an unattended tower running as root. The
# writer's own grammar is wider than this (any absolute, control-free path), so
# an exotic root is a known miss — see the guard's entry in the PR audit.
#
# The death-handle patterns are the two forms fleet-death-evidence.sh declares
# and nothing else, matched at that owner's own bounds. The private-address
# rule requires a full dotted quad so an ordinary version string (`10.15.7`) is
# not reported as a host. The hostname rule requires
# the private suffix to end the label — not followed by another dot-label — so
# a filename like `planwright.local.yml` is not mistaken for a host.
rules=$(
  cat <<'RULES'
checkout-path	(/home/|/Users/)[A-Za-z0-9._-]+|/root(/|$)
death-handle	(^|[^A-Za-z0-9_-])process [1-9][0-9]{0,9}([^0-9]|$)
death-handle	(^|[^A-Za-z0-9_-])tmux-window [A-Za-z0-9_@%.-]{1,128} [A-Za-z0-9_@%.-]{1,128}
internal-hostname	[A-Za-z0-9-]+\.(internal|intranet|corp|lan|local)($|[^A-Za-z0-9.-])
internal-hostname	(^|[^0-9.])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3})([^0-9.]|$)
RULES
)

found=0
unreadable=0

# is_artifact <path> — 0 when the file carries at least one line that IS a
# coordination record (the shapes above), 1 for a prose mention of the format,
# and 2 when the file could not be READ. Binary files never match: the shapes
# are anchored, tab-delimited text.
#
# The three-way result is the point. Shape detection opens the file, so its
# read can fail for exactly the reasons screen_file's can; collapsing that into
# the same answer as "carries no record" would skip the file silently and let
# the caller report a clean tree. That is fail-OPEN in the one direction a leak
# guard must never fail, so the read error gets its own status and the caller
# routes it to the unscreened refusal.
is_artifact() {
  # `hit` is a flag, not an early `exit 0`: an `exit` inside a rule still runs
  # END, whose own `exit` status would override it. awk exits >1 by itself on a
  # file it cannot open, which is what makes the third status available.
  awk -F'\t' '
    NF == 10 && $1 == "pw-presence-v1" { hit = 1; exit }
    $0 ~ /^refs\/planwright-fence\/[^ \t]+$/ { hit = 1; exit }
    # fleet-fence.sh emits the sweep and fence verbs tab-prefixed, with the ref
    # in field 2 — `strand <ref> <owner> <liveness>` is the strand-sink entry
    # REQ-D1.4 names, and it carries a peer owner identity a bare-ref match
    # would never see. Keyed on the verb rather than on the ref alone so prose
    # quoting the namespace mid-sentence still does not qualify.
    NF >= 2 && $2 ~ /^refs\/planwright-fence\/[^ \t]+$/ &&
      $1 ~ /^(fenced|unfenced|taken|gc|gc-absent|gc-failed|honored|strand|tentative|suppressed|hold|anomaly)$/ {
        hit = 1; exit
      }
    END { exit !hit }
  ' "$1" 2>/dev/null
  ia_rc=$?
  [ "$ia_rc" -le 1 ] || return 2
  return "$ia_rc"
}

# screen_file <path> <name-to-report> — apply every rule, then delegate the
# credential class. A file this cannot READ is not a file it may call clean.
screen_file() {
  sf_path=$1
  sf_name=$2
  # Sanitized once per file, not once per hit: the value is constant for the
  # whole call and the sanitizer forks. Every line of a presence record trips
  # both the checkout-path and death-handle rules, so a large committed audit
  # log otherwise pays two forks per record to re-derive one string.
  sf_safe=$(sanitize_printable "$sf_name" '(unprintable path)')
  if [ ! -r "$sf_path" ]; then
    printf '%s\n' "check-coordination-hygiene: cannot read $sf_safe; refusing to pass it unscreened" >&2
    unreadable=1
    return
  fi
  sf_oifs=$IFS
  IFS='
'
  for sf_rule in $rules; do
    [ -n "$sf_rule" ] || continue
    # A rule line that lost its tab would split into a name equal to the whole
    # line and a pattern equal to the whole line, which matches nothing in any
    # file, forever, while still reporting clean. Refuse the malformed table
    # rather than screening with a rule that cannot fire.
    case $sf_rule in
      *"$TAB"*) ;;
      *)
        echo "check-coordination-hygiene: malformed rule table entry (no tab separator)" >&2
        IFS=$sf_oifs
        unreadable=1
        return
        ;;
    esac
    sf_rname=${sf_rule%%"$TAB"*}
    sf_rpat=${sf_rule#*"$TAB"}
    # Not a pipeline: piping into `cut` would hand back cut's status and throw
    # grep's away, and grep's status is the point — 1 is "no match", 2 is
    # "could not read this", and only one of those means clean. `-a` because
    # grep otherwise suppresses the matching lines for a file it judges binary,
    # reporting `Binary file … matches` with no usable line number; only the
    # declared-path mode can reach one, since the tree scan prefilters through
    # `git grep -I`.
    sf_rc=0
    sf_hits=$(grep -a -n -E -e "$sf_rpat" -- "$sf_path" 2>/dev/null) || sf_rc=$?
    if [ "$sf_rc" -gt 1 ]; then
      printf '%s\n' "check-coordination-hygiene: could not read $sf_safe; refusing to pass it unscreened" >&2
      unreadable=1
      IFS=$sf_oifs
      return
    fi
    for sf_hit in $sf_hits; do
      [ -n "$sf_hit" ] || continue
      printf '%s:%s: %s (value redacted)\n' "$sf_safe" "${sf_hit%%:*}" "$sf_rname" >&2
      found=1
    done
  done
  IFS=$sf_oifs

  # The credential class is the sibling screen's, consumed as-is: it already
  # owns the shapes, the gitleaks seam, and the never-echo-the-match rule.
  # Invoked through /bin/sh, not as a command, on that sibling's own documented
  # terms: the executable bit is not guaranteed to survive whatever copied the
  # plugin onto the host, and a lost bit would otherwise surface as 126 in the
  # arm below — blaming the artifact for a broken install.
  if [ ! -r "$script_dir/inception-secret-screen.sh" ]; then
    echo "check-coordination-hygiene: the secret screen is missing from $script_dir; refusing to pass $sf_safe unscreened" >&2
    unreadable=1
    return
  fi
  sf_src=0
  /bin/sh "$script_dir/inception-secret-screen.sh" -- "$sf_path" || sf_src=$?
  case $sf_src in
    0) ;;
    1)
      printf '%s\n' "$sf_safe: secret (reported above by the secret screen, value redacted)" >&2
      found=1
      ;;
    *)
      printf '%s\n' "check-coordination-hygiene: the secret screen could not screen $sf_safe; refusing to pass it unscreened" >&2
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
  [ "$repo_set" -eq 1 ] || repo=.
  if ! git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "check-coordination-hygiene: $repo is not a git work tree" >&2
    exit 2
  fi
  # Prefilter on the two literal tags before the per-file shape check, so the
  # scan is one grep over the tracked tree plus an awk on the few candidates,
  # never an awk per tracked file.
  #
  # git grep's STDERR is captured rather than discarded, because a tracked file
  # it cannot stat (mode 000, a permission-denied parent) is reported there and
  # then simply omitted from the candidate list — while the exit status stays 1,
  # the same 1 that means "no match". Discarding it would turn a file the scan
  # never read into a tree that commits nothing, which is the fail-open this
  # guard exists to avoid. Any stderr output means the enumeration is not
  # provably complete, so the scan refuses rather than certifying it.
  cand_err=$(mktemp "${TMPDIR:-/tmp}/check-coordination-hygiene.XXXXXX") || exit 2
  # Split, not a combined `EXIT INT TERM`: that shape removes the file and then
  # RESUMES, so a signal landing before the `-s` test below would drop the
  # enumeration evidence and let the scan certify a tree it never read. Exiting
  # non-zero keeps the EXIT trap's cleanup while making an interrupted scan a
  # refusal rather than a pass.
  trap 'rm -f "$cand_err"' EXIT
  trap 'exit 130' INT TERM
  cand_rc=0
  candidates=$(git -C "$repo" grep -I -l -F \
    -e 'pw-presence-v1' -e 'refs/planwright-fence/' -- 2>"$cand_err") || cand_rc=$?
  if [ "$cand_rc" -gt 1 ]; then
    echo "check-coordination-hygiene: could not scan the tracked tree of $repo" >&2
    exit 2
  fi
  if [ -s "$cand_err" ]; then
    # The paths git named are echoed back; they are tracked repository paths,
    # not record contents, so this leaks nothing the tree does not already hold.
    printf '%s\n' "check-coordination-hygiene: could not enumerate part of the tracked tree of $repo; refusing to pass it unscreened:" >&2
    sed 's/^/  /' "$cand_err" >&2
    unreadable=1
  fi
  artifacts=0
  oifs=$IFS
  IFS='
'
  for rel in $candidates; do
    [ -n "$rel" ] || continue
    IFS=$oifs
    scan_rc=0
    is_artifact "$repo/$rel" || scan_rc=$?
    case $scan_rc in
      0)
        artifacts=$((artifacts + 1))
        screen_file "$repo/$rel" "$rel"
        ;;
      1) ;; # read fine; mentions a tag but carries no record — not an artifact
      *)
        printf '%s\n' "check-coordination-hygiene: cannot read $(sanitize_printable "$rel" '(unprintable path)') to classify it; refusing to pass it unscreened" >&2
        unreadable=1
        ;;
    esac
    IFS='
'
  done
  IFS=$oifs
  # `unreadable` is checked first: a tree whose only candidate could not be read
  # has NOT been shown to commit nothing, and saying "nothing to screen" there
  # would report the absence of evidence as evidence of absence.
  if [ "$artifacts" -eq 0 ] && [ "$unreadable" -eq 0 ]; then
    echo "check-coordination-hygiene: no committed coordination artifact — nothing to screen" >&2
    exit 0
  fi
fi

[ "$unreadable" -eq 0 ] || exit 2
[ "$found" -eq 0 ] || exit 1
exit 0
