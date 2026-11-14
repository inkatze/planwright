#!/bin/bash
# Tests for events whose subject is gone: the wake leaves them out and marks
# them submitted, and `mc-event.sh prune --gone` removes them from the store.
# The forge is a gh shim on PATH reading its answers from a file.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-event-gone.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC2034 # read by the sourced fixture
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')

mkdir -p "$tmp/fakebin"
cat >"$tmp/fakebin/gh" <<'GHEOF'
#!/bin/sh
# gh pr view <n> --repo <slug> --json state --jq .state
[ "$1 $2" = "pr view" ] || exit 2
[ "$4 $5" = "--repo acme/widgets" ] || exit 1
[ ! -f "$GH_FAIL" ] || exit 1
awk -v n="$3" '$1 == n { print $2; f = 1 } END { exit !f }' "$GH_STATES"
GHEOF
chmod +x "$tmp/fakebin/gh"
export GH_STATES="$tmp/gh-states" GH_FAIL="$tmp/gh-fail"
printf '%s\n' "11 OPEN" "12 MERGED" "13 CLOSED" >"$GH_STATES"
PATH="$tmp/fakebin:$PATH"

setup() {
  reset_mc_fixture
  rm -rf "$fleet"
  rm -f "$GH_FAIL"
  cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_sources: {work-items: specs:record}
EOF
  sess=$fleet/mission-control/sessions
  mkdir -p "$sess"
  printf 'format\t1\nprogram\talpha\nkind\tworker\nscope\ts\nbackend\tstream-json\nlaunched\t1\n' >"$sess/mc-live-1"
  mc_run fleet-state.sh register regw mission-control:alpha --backend stream-json
  mc_run fleet-state.sh register retw mission-control:alpha --backend stream-json
  mc_run fleet-state.sh retire retw mission-control:alpha --backend stream-json
  mkdir -p "$fleet/mission-control/alpha"
  printf 'format\t1\nsession\tmc-holder-2\nkind\tattended\nsince\t1\ngeneration\t2\n' >"$fleet/mission-control/alpha/holder"
  chmod 600 "$fleet/mission-control/alpha/holder"
  mc_run mc-wake.sh target add --program alpha tw
}

emit() { mc_run mc-event.sh emit --program alpha "$@"; }

# A backlog mixing gone and live subjects.
backlog() {
  emit pending-prompt mc-live-1 "live launched worker"
  live_a=$OUT
  emit pending-prompt-overdue regw "live registry worker"
  live_b=$OUT
  emit pending-prompt mc-retired-9 "retired worker"
  gone_a=$OUT
  emit merge-ready acme:widgets:11 "open pr"
  live_c=$OUT
  emit merge-ready acme:widgets:12 "merged pr"
  gone_b=$OUT
  emit readiness-due acme:widgets:13 "closed pr"
  gone_c=$OUT
  emit handover-requested mc-holder-2 "ask the live holder"
  live_d=$OUT
  emit mission-control-announce mc-old-holder-1 "a past generation"
  gone_d=$OUT
  emit merge-ready pr-123456 "subject outside the grammar, unresolvable"
  live_e=$OUT
  emit merge-ready acme:widgets:99 "the forge does not know it"
  live_f=$OUT
  emit decision-queued some-item "a kind the filter does not read"
  live_g=$OUT
  emit pr-merged acme:widgets:12 "the landing notice itself"
  live_h=$OUT
  emit pending-prompt retw "a retired registry worker"
  gone_e=$OUT
  live_ids="$live_a $live_b $live_c $live_d $live_e $live_f $live_g $live_h"
  gone_ids="$gone_a $gone_b $gone_c $gone_d $gone_e"
}

count_events() {
  mc_run mc-event.sh list --program alpha
  printf '%s\n' "$OUT" | awk 'NF { n++ } END { print n + 0 }'
}

# A backlog mixing gone and live subjects relays only the live ones.
setup
backlog
mc_run mc-wake.sh compose --program alpha tw
case $OUT in
  "wake${tab}8${tab}"*) ok "the wake carries the live events only" ;;
  *) fail "expected a wake of 8 events, got: $OUT" ;;
esac
for id in $live_ids; do
  case $OUT in *"$id"*) ;; *) fail "live event $id missing from the wake" ;; esac
done
for id in $gone_ids; do
  case $OUT in *"$id"*) fail "gone event $id reached the wake" ;; esac
done
mc_run mc-event.sh list --program alpha --target tw --pending
for id in $gone_ids; do
  case $OUT in *"$id"*) fail "gone event $id is still pending" ;; esac
done
ok "the gone events left the pending set"
if [ "$(count_events)" -eq 13 ]; then ok "and stay listable"; else fail "the wake deleted events"; fi

# The prune mode removes only the gone-subject events.
setup
backlog
mc_run mc-event.sh prune --program alpha --gone --dry-run
case $OUT in "would-prune${tab}5") ok "--gone --dry-run counts the gone events" ;; *) fail "dry run said '$OUT'" ;; esac
if [ "$(count_events)" -eq 13 ]; then ok "a dry run removes nothing"; else fail "a dry run removed events"; fi
mc_run mc-event.sh prune --program alpha --gone
case $OUT in "pruned${tab}5") ok "--gone prunes the gone events" ;; *) fail "prune said '$OUT'" ;; esac
mc_run mc-event.sh list --program alpha
for id in $gone_ids; do
  case $OUT in *"$id"*) fail "gone event $id survived the prune" ;; esac
done
for id in $live_ids; do
  case $OUT in *"$id"*) ;; *) fail "live event $id was pruned" ;; esac
done
ok "only the gone events were pruned"

# A forge read that fails keeps its event, in the prune and in the wake.
setup
backlog
: >"$GH_FAIL"
mc_run mc-event.sh prune --program alpha --gone --dry-run
case $OUT in "would-prune${tab}3") ok "a failing forge keeps every pull request event" ;; *) fail "prune with a failing forge said '$OUT'" ;; esac
mc_run mc-wake.sh compose --program alpha tw
case $OUT in
  *"$gone_b"*"$gone_c"* | *"$gone_c"*"$gone_b"*) ok "the unjudged pull request events still wake" ;;
  *) fail "a pull request event was dropped on a failed forge read: $OUT" ;;
esac

# No holder record keeps the handover and announce events.
setup
backlog
rm -f "$fleet/mission-control/alpha/holder"
mc_run mc-event.sh prune --program alpha --gone
case $OUT in "pruned${tab}4") ok "with no holder the handover and announce events are kept" ;; *) fail "prune with no holder said '$OUT'" ;; esac
mc_run mc-wake.sh compose --program alpha tw
case $OUT in *"$gone_d"*) ok "and still wake" ;; *) fail "an announce event was dropped with no holder" ;; esac

# An unreadable session list keeps the session events (a root user reads
# any directory, so the case is skipped there).
if [ "$(id -u)" -ne 0 ]; then
  setup
  backlog
  chmod 000 "$sess"
  mc_run mc-event.sh prune --program alpha --gone
  mc_run mc-event.sh list --program alpha
  case $OUT in *"$gone_a"*) ok "a session event is kept while the session list cannot be read" ;; *) fail "a session event was dropped" ;; esac
  chmod 755 "$sess"
fi

if [ "$failures" -ne 0 ]; then
  echo "test-mc-event-gone: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-event-gone: all passed"
