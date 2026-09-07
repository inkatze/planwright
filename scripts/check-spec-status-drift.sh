#!/usr/bin/env bash
# check-spec-status-drift.sh — stored-vs-derived spec status drift guard.
#
# A bundle's `**Status:**` header is STORED text. On a Format-version 1 bundle
# that text is authoritative and `tasks-pr-sync.sh reconcile` keeps it current.
# On a version 2 bundle the lifecycle state is DERIVED from live task evidence
# and is deliberately never written back: run the reconcile against one and it
# prints "derived state is never stored (REQ-C1.1) — nothing to reconcile" and
# writes nothing. So a v2 bundle can stand at `**Status:** Ready` indefinitely
# while every one of its tasks has long since completed, and nothing in the
# repo notices.
#
# That gap is not theoretical. A reader trusting the stored headers took a set
# of finished bundles for outstanding backlog, because the header is the first
# thing anyone reads and it is the one thing that never moves.
#
# The obvious repair — making the header say it is derived — is closed off.
# doctrine/spec-format.md constrains the value to the enum
# `<Draft|Ready|Active|Done|Retired|Superseded>`; a value outside it is refused
# by every reader of the header (scripts/spec-status.sh exits 2 on an
# unrecognized stored status), and scripts/spec-anchor.sh aborts on a header
# block it cannot parse, so the bundle's anchor would break. The header has to
# keep an enum value; the drift gets CAUGHT, not annotated.
#
# WHAT IS ENFORCED. One rule: a bundle whose derived state is `Done` must not
# store anything else. Derivation is not reimplemented here — it is read from
# scripts/spec-status.sh, the canonical status render, which is the derivation
# engine (scripts/orchestrate-state.sh) surfaced as a command. One derivation,
# one place.
#
# WHAT IS DELIBERATELY NOT ENFORCED, and why each is a decision rather than a
# gap:
#
#   Derived Active against stored Ready. On v2 this is CORRECT storage, not
#   drift: Active is derived on demand and never stored (the restricted v2
#   stored vocabulary is Draft, Ready, Retired, Superseded). On v1 it is a
#   transient window that the level-triggered reconcile writer closes on its
#   own, so flagging it would fail the tree for a state that is mid-repair.
#
#   Retired and Superseded. Human-set terminal states; doctrine accepts no
#   skill-driven transition out of one. A retired bundle whose every task
#   derives completed carries evidence identical to the drift case above, and
#   flagging it would push a reader toward a transition nothing will accept.
#   The render makes no execution claim for them, so they never reach the
#   comparison.
#
#   Stored v1 Active or Done. The render computes no derived bundle status for
#   these — the reconcile owns those committed values, and a derived claim here
#   would be a second writer's opinion. Enforcing over them would mean
#   reimplementing the aggregation for a mode the canonical render declines to
#   compute, which is the one thing this guard must not do.
#
#   Open Deferred gates. They do not block Done, and the Done universe excludes
#   Deferred- and Out-of-scope-parked tasks rather than waiting on them. That
#   exclusion lives inside the derivation and is inherited, not restated here.
#
# Scope is every bundle directory under specs/. The `_`-prefixed accumulators
# (specs/_observations, specs/_pending) are not bundles and are not scanned; a
# directory carrying no requirements.md is not one either, and is reported as
# skipped rather than absorbed silently — the spec validator owns bundle
# structure (the line check-memory-links.sh takes). A dot-named directory is
# outside the scope by construction: the spec-id grammar forbids a leading dot,
# so no such directory can be a bundle. A SYMLINKED bundle directory is refused
# rather than followed: following it would read content from outside the root
# while reporting it under a path inside the root, and skipping it would cover
# less than the scan claims (the position check-cdpath.sh takes).
#
# Usage:
#   check-spec-status-drift.sh [<root>]   scan the bundles under <root>/specs
#                                         (default: the parent of this script's
#                                         directory)
#   check-spec-status-drift.sh --help | -h
#
# The render is always this install's scripts/spec-status.sh, never <root>'s:
# pointed at a different checkout, this guard reads that tree's bundles through
# this tree's derivation engine.
#
# Exit codes: 0 clean, 1 a bundle whose stored status contradicts its derived
# state, 2 usage or a broken scan. Anything that would make the scan cover less
# than it claims — an absent root or specs/ directory, an unreadable bundle, a
# symlinked bundle directory, a name that is not a spec id, a render that fails
# or that refuses malformed input, a transient evidence failure, a scan reaching
# no bundles at all — is exit 2, never a clean report. The first such condition
# ends the run rather than being collected: a scan that cannot trust one bundle
# reports that, and the drift report is only meaningful over a complete scan.
#
# The transient case earns its own mention. When a remote is configured and the
# gh query fails, the render exits 3 and presents no evidence-derived status. A
# guard that shrugged that off would report a clean tree from an outage, which
# is the exact vacuous green it exists to prevent. No remote configured is a
# different thing entirely: the engine skips the probe silently and derives
# from git alone, and the scan proceeds normally.
#
# COST. Every scanned bundle runs the derivation engine, which walks git
# history and probes gh once. Over a full spec tree that is on the order of a
# minute or two, which is why this is an on-demand guard rather than a member
# of the `check` aggregate. Note that the exclusion defers the cost of scanning
# THIS repo's tree, not the guard's own test suite: those tests derive over
# small fixture repos and do run in the gate, as ordinary test files.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible.
set -u

LC_ALL=C
export LC_ALL

unset CDPATH

fail_closed() {
  echo "check-spec-status-drift: $1" >&2
  exit 2
}

self_dir="$(cd "$(dirname "$0")" && pwd -P)" \
  || fail_closed "cannot resolve the directory this script lives in"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)" \
  || fail_closed "cannot resolve the repository root"

RENDER="$self_dir/spec-status.sh"

# Display sanitizer for untrusted content headed for the terminal (echo
# discipline, doctrine/security-posture.md). Bundle names and render output
# both reach the terminal, and on a fork PR both are attacker-authored. The
# inline fallback keeps diagnostics safe when the shared helper cannot be
# sourced.
sanitize_printable() {
  _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237' 2>/dev/null) || _sp=''
  if [ -z "$_sp" ] && [ $# -ge 2 ]; then
    _sp=$2
  fi
  printf '%s' "$_sp"
}
if [ -f "$self_dir/echo-safety.sh" ] && [ -r "$self_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$self_dir/echo-safety.sh" \
    || fail_closed "the echo sanitizer could not be sourced — broken install"
fi
# A partially-sourced helper can leave the sanitizer undefined, and `set -u`
# does not catch a missing command: every diagnostic would then silently lose
# the untrusted fragment it exists to carry.
command -v sanitize_printable >/dev/null 2>&1 \
  || fail_closed "the echo sanitizer is unavailable — broken install"

usage() {
  cat <<'EOF'
check-spec-status-drift.sh — flag a spec bundle whose stored **Status:** header
contradicts the state derived from its live task evidence.

Usage:
  check-spec-status-drift.sh [<root>]   scan the bundles under <root>/specs
                                        (default: the parent of this script's
                                        directory)
  check-spec-status-drift.sh --help | -h

The render is always this install's scripts/spec-status.sh, never <root>'s:
pointed at a different checkout, this guard reads that tree's bundles through
this tree's derivation engine.

Why it exists: on a Format-version 2 bundle the lifecycle state is derived and
never written back to the header, and the reconcile refuses to touch it. The
header can therefore read `Ready` forever while every task is complete, and a
reader who trusts it mistakes a finished bundle for outstanding backlog.

Flagged: a bundle whose derived state is Done while its header stores anything
else.

Not flagged, deliberately: derived Active against stored Ready (on v2 Active is
never stored, so that is correct storage; on v1 the reconcile is mid-repair);
Retired and Superseded, which are human-set terminal states no skill-driven
transition leaves; Draft, which makes no execution claim; and stored v1 Active
or Done, for which the canonical render computes no derived status at all.

Derivation is not computed here. It is read from scripts/spec-status.sh, the
canonical status render over the derivation engine, so this guard cannot drift
from the engine the orchestrator and the reconcile read.

Exit codes: 0 clean, 1 a drifted bundle, 2 usage or a broken scan.

The clean report names both how many bundles were scanned and how many were
actually JUDGED. The two differ: a bundle the render makes no derived claim
about (Draft, Retired, Superseded, a stored v1 Active/Done, a zero-task bundle)
is scanned but not judged, and counting it as coverage would overstate what the
run proved.

Fixing a flagged bundle: the header is human-owned payload and this guard never
edits it. Confirm the derived state with `scripts/spec-status.sh <spec-dir>`,
then flip the stored Status through the normal lifecycle route. Never hand-edit
a signed bundle without re-anchoring it.

Cost: each bundle runs the derivation engine over git history and one gh probe,
so a full tree takes appreciably longer than a text-scanning guard. This is an
on-demand check, not a member of the `check` aggregate.
EOF
}

case "${1:-}" in
  --help | -h)
    [ "$#" -eq 1 ] || fail_closed "--help takes no other arguments"
    usage
    exit 0
    ;;
  -*)
    fail_closed "unknown option: $(sanitize_printable "$1" "(unprintable)") (see --help)"
    ;;
esac

[ "$#" -le 1 ] || fail_closed "too many arguments (expected at most one root)"

# `${1:-default}` substitutes on an empty argument as well as an absent one,
# which would silently scan the default tree for a caller who named a root.
if [ "$#" -eq 1 ]; then
  root="$1"
  [ -n "$root" ] || fail_closed "empty root argument (expected a directory)"
else
  root="$repo_root"
fi
safe_root="$(sanitize_printable "$root" "(unprintable path)")"
[ -d "$root" ] || fail_closed "root not found or not a directory: $safe_root"

specs_dir="$root/specs"
if [ -L "$specs_dir" ]; then
  fail_closed "specs is a symlink under $safe_root, refusing to follow — the scan would leave the root while reporting paths inside it"
fi
[ -d "$specs_dir" ] \
  || fail_closed "no specs directory under $safe_root — the scan would cover less than it claims"
if [ ! -r "$specs_dir" ] || [ ! -x "$specs_dir" ]; then
  fail_closed "the specs directory under $safe_root cannot be listed — the scan would cover less than it claims"
fi

if [ ! -f "$RENDER" ] || [ ! -r "$RENDER" ] || [ ! -x "$RENDER" ]; then
  fail_closed "the status render is missing, unreadable, or not executable at $(sanitize_printable "$RENDER" "(unprintable path)") — broken install"
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/check-spec-status-drift.XXXXXX")" \
  || fail_closed "could not create a temporary directory"
trap 'rm -rf "$work"' EXIT

# render_detail <fallback-file> — the render's own diagnostic, flattened to one
# line. Newlines and tabs become spaces BEFORE sanitizing, because the
# sanitizer deletes control bytes outright and would otherwise run a multi-line
# refusal into a single unreadable word.
render_detail() {
  tr '\n\t' '  ' <"$1" 2>/dev/null
}

status=0
scanned=0
judged=0
drifted=0

for dir in "$specs_dir"/*/; do
  # An unexpanded glob (an empty specs/) is the literal pattern, not a path.
  [ -e "$dir" ] || continue
  dir="${dir%/}"
  name="${dir##*/}"

  # The accumulators are not bundles; skipping them silently is correct, since
  # they were never in scope to begin with.
  case "$name" in
    _*) continue ;;
  esac

  safe_name="$(sanitize_printable "$name" "(unprintable bundle name)")"

  if [ -L "$dir" ]; then
    fail_closed "symlinked bundle directory in the scan scope, refusing to follow: specs/$safe_name"
  fi
  [ -d "$dir" ] || continue
  if [ ! -r "$dir" ] || [ ! -x "$dir" ]; then
    fail_closed "cannot list specs/$safe_name — the scan would cover less than it claims"
  fi

  # The bundle name is the spec id the render will validate anyway. Checking it
  # here turns a generic "the render failed" into a diagnostic that names the
  # actual problem, and keeps this guard's own line-oriented reporting from
  # depending on a sibling's unpromised behavior.
  case "$name" in
    *[!a-z0-9-]* | [!a-z0-9]*)
      fail_closed "specs/$safe_name is not a spec id (lowercase letters, digits and dashes, starting alphanumeric)"
      ;;
  esac

  req="$dir/requirements.md"
  if [ ! -e "$req" ]; then
    echo "check-spec-status-drift: specs/$safe_name has no requirements.md — skipped (the validator owns bundle structure)" >&2
    continue
  fi
  # Absent and unreadable are different facts and must not share a diagnostic:
  # one is a structural defect, the other a permissions failure that hides
  # content the scan claims to have covered.
  for f in "$req" "$dir/tasks.md"; do
    base="${f##*/}"
    [ -e "$f" ] \
      || fail_closed "specs/$safe_name has requirements.md but no $base — an incomplete bundle the scan cannot judge"
    [ -r "$f" ] \
      || fail_closed "cannot read specs/$safe_name/$base — the scan would cover less than it claims"
  done

  scanned=$((scanned + 1))

  # The render is the single source of the derivation (D-6: one derivation, one
  # place). Its stderr is kept separate so a refusal can be quoted back intact
  # rather than corrupting the stdout parse.
  render_out="$("$RENDER" "$dir" 2>"$work/err")"
  render_rc=$?

  case "$render_rc" in
    0) ;;
    3)
      # The render reports its transient failure on STDOUT, not stderr (the
      # engine's own stderr is consumed upstream), so reading $work/err here
      # would reliably produce no diagnostic at all.
      detail="$(printf '%s\n' "$render_out" \
        | awk '/^spec-status: transient evidence failure/ { print; exit }')"
      [ -n "$detail" ] || detail="$(render_detail "$work/err")"
      fail_closed "specs/$safe_name: transient evidence failure — $(sanitize_printable "$detail" "(no diagnostic)"); partial evidence is not a clean status"
      ;;
    *)
      fail_closed "specs/$safe_name: the status render failed (exit $render_rc) — $(sanitize_printable "$(render_detail "$work/err")" "(no diagnostic)")"
      ;;
  esac

  stored="$(printf '%s\n' "$render_out" \
    | awk '/^stored status: [A-Za-z]+/ { print $3; exit }')"
  [ -n "$stored" ] \
    || fail_closed "specs/$safe_name: the status render reported no stored status — refusing to guess"

  # The derived claim is matched on the render's `(derived)` marker, never on
  # the word alone: the zero-task report prints a `bundle status:` line too,
  # and it is explicitly a STORED value that never derives Done. Both parses
  # are line-anchored so neither can match a fragment of rendered payload.
  derived="$(printf '%s\n' "$render_out" \
    | awk '/^bundle status: [A-Za-z]+ \(derived\)$/ { print $3; exit }')"

  if [ -z "$derived" ]; then
    # No derived claim is the normal, correct outcome for Draft, Retired,
    # Superseded, a stored v1 Active/Done, and a zero-task bundle. It is NOT
    # normal for a stored Ready bundle that reported tasks: that combination
    # means the render's output no longer carries the shape parsed above, and a
    # guard that cannot find the derived state must say so rather than pass the
    # bundle. The render's text carries no stability promise, so this is the
    # coupling's tripwire — without it, a reformatted render would turn this
    # guard silently green over everything.
    if [ "$stored" = Ready ] \
      && ! printf '%s\n' "$render_out" | grep -q '^no tasks:'; then
      fail_closed "specs/$safe_name: stored Ready but the render published no derived status — the render's output shape has changed and this scan can no longer read it"
    fi
    continue
  fi

  judged=$((judged + 1))

  # The rule. Derivation is gated to stored-Ready bundles upstream, so in
  # practice this is stored Ready against derived Done; it is written as the
  # general comparison so a future widening of the render's gating is caught
  # rather than quietly ignored.
  if [ "$derived" = Done ] && [ "$stored" != Done ]; then
    echo "check-spec-status-drift: specs/$safe_name: stored '$(sanitize_printable "$stored" "(unprintable)")' but every task derives complete — the derived state is 'Done'" >&2
    drifted=$((drifted + 1))
    status=1
  fi
done

[ "$scanned" -gt 0 ] \
  || fail_closed "no spec bundles found under $safe_root/specs — a broken enumeration, not a clean tree"

# The coverage numbers are reported on both paths. A failing run is the one an
# operator actually reads, and it needs the same answer to "over how much?" that
# the clean run gives.
if [ "$status" -eq 0 ]; then
  echo "check-spec-status-drift: clean ($scanned bundles scanned, $judged judged)"
else
  echo "check-spec-status-drift: $scanned bundles scanned, $judged judged, $drifted drifted" >&2
fi
exit "$status"
