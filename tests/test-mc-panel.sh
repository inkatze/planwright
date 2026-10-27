#!/bin/bash
# Tests for scripts/mc-panel.sh, the panel mod's data seam and the text form
# it falls back to, and for scripts/mc-wake.sh compose, the wake the mod
# submits (mission-control REQ-E1.3, REQ-F1.1, REQ-F1.2, REQ-H1.4, REQ-L1.4,
# REQ-L1.5, REQ-M1.8; D-6, D-29).
#
# The mod's own drawing, wake and tick are covered by the plugin tests beside
# it (hooks/mission-control/*.test.tsx, scripts/check-panel-mod.sh); this
# suite proves the digest they draw from reads the real stores.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-panel.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$repo_root/scripts/mc-panel.sh" ] || {
  echo "FAIL: scripts/mc-panel.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"
# shellcheck source=tests/lib/mc-snapshot-fixture.sh
. "$here/lib/mc-snapshot-fixture.sh"

record() { # record <label> <type> [<field>...]: stdout holds that record
  rc_label=$1
  shift
  rc_want=$(printf '%s\t' "$@")
  rc_want=${rc_want%"$tab"}
  if printf '%s\n' "$OUT" | grep -qxF -- "$rc_want"; then
    ok "$rc_label"
  else
    fail "$rc_label: no line '$rc_want'"
    printf '%s\n' "----- stdout -----" "$OUT" "----- stderr -----" "$ERR" "------------------" >&2
  fi
}

# ---------------------------------------------------------------------------
# compose: the wake the mod submits, its events never-sent first.
# ---------------------------------------------------------------------------
setup
mc_run mc-wake.sh compose --program alpha mc-alpha
expect_rc "compose with nothing pending" 0
expect_eq "REQ-E1.3: compose with nothing pending says idle" "idle"
mc_run mc-event.sh emit --program alpha --now 2000 pr-ready pr-7 "seven is ready"
e1=$OUT
mc_run mc-event.sh emit --program alpha --now 2001 unit-parked task-3 "parked on a fork"
e2=$OUT
mc_run mc-event.sh mark --program alpha --target mc-alpha staged "$e1"
mc_run mc-wake.sh compose --program alpha mc-alpha
expect_rc "compose with two pending" 0
first=$(printf '%s\n' "$OUT" | head -n 1)
if [ "$first" = "wake${tab}2${tab}$e2 $e1" ]; then
  ok "REQ-E1.3: compose names the count and the ids, a never-sent event first"
else
  fail "REQ-E1.3: compose's first line is '$first'"
fi
expect_out "the wake names each event's kind and subject" "- unit-parked task-3"
expect_out "the wake says how to read the events" "list --program alpha $e2 $e1"
expect_no_out "the wake carries no free text" "parked on a fork"
expect_no_out "a submitted wake asks for no acknowledgement" "acknowledge"
mc_run mc-event.sh mark --program alpha --target mc-alpha submitted "$e1" "$e2"
mc_run mc-wake.sh compose --program alpha mc-alpha
expect_eq "REQ-E1.3: submitted events leave the wake" "idle"
mc_run mc-wake.sh compose --program alpha 'bad;target'
expect_rc "compose refuses a target outside the grammar" 2

# ---------------------------------------------------------------------------
# digest: every store the panel draws, each source with its mode and age.
# ---------------------------------------------------------------------------
setup
mc_run mc-snapshot.sh refresh --program alpha --now 1000
mc_run mc-budget.sh report --program alpha --now 1000 --load 10
mc_run fleet-state.sh register w-one mission-control:alpha --backend stream-json --death-handle none
mc_run fleet-state.sh register w-gone mission-control:alpha --backend tmux --death-handle "tmux-window mc 4"
mc_run fleet-state.sh retire w-gone mission-control:alpha --backend tmux --death-handle "tmux-window mc 4"
mc_run mc-event.sh emit --program alpha --now 1000 pr-ready pr-7
# A live session whose observed name is `closed` (nine fields), and one
# known only by a legacy three-field record.
printf '900\tw-named\tflight:docs\t-\tstream-json\t-\tnone\tclosed\t-\n900\tw-legacy\tflight:old\n' >>"$fleet/registry"
home=$fixhome/.config/planwright/mission-control/alpha
mkdir -p "$home/kb"
printf '<!-- format: 1 -->\n- %s: an entry\n' "\`a.md\`" >"$home/kb/index.md"
TZ=UTC touch -t 197001010015.00 "$home/kb/index.md"
{
  printf '# format: 1\n'
  printf 'decisions-197001-1\t1970-01-01T00:10:00Z\tflip pr-7\tready-flip\tpr-7\tgreen\tnone\t-\n'
  printf 'decisions-197001-2\t1970-01-01T00:11:00Z\tmerge order\tretarget\tpr-9\tbase merged\tnone\t-\n'
} >"$home/kb/decisions-1970-01.log"
{
  printf '# format: 1\n'
  printf 'decisions-197002-1\t1970-02-01T00:10:00Z\tpark task-3\tpark\ttask-3\tfork\tnone\t-\n'
  printf 'decisions-197002-2\t1970-02-01T00:15:00Z\trelaunch w-one\trelaunch\tw-one\tstalled\tnone\tsession-keeper\n'
} >"$home/kb/decisions-1970-02.log"
runtime=$fleet/mission-control/alpha
printf 'format\t1\ntaken\t900\ninterruptions_per_hour\t2.5\nsettled_share\t80\n' >"$runtime/measures"
# A watcher record whose loop is gone, its last run at 600 on a 5m cadence.
mkdir -p "$runtime/watchers"
printf '999999\t500\talpha-duty\tscripts/alpha-watch.sh\t5m\tlow\n' >"$runtime/watchers/alpha-duty.alpha-watch.rec"
printf '600\t0\t0\n' >"$runtime/watchers/alpha-duty.alpha-watch.last"

mc_run mc-panel.sh digest --program alpha --target mc-alpha --knobs --now 1030
expect_rc "the digest" 0
record "the digest opens with its format" format 1
record "the digest names its program" program alpha
record "the digest is stamped" taken 1030
record "REQ-F1.1: a live session is in flight" flight w-one mission-control:alpha stream-json
expect_no_out "a retired session is not in flight" "w-gone"
record "a live session named closed stays in flight" flight w-named flight:docs stream-json
record "a legacy three-field record is in flight, its backend unknown" flight w-legacy flight:old -
record "REQ-F1.1: what waits on the operator" waiting 0
record "REQ-E1.3: the target's pending events" pending 1
got=$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "decision" { printf "%s|", $2 }')
if [ "$got" = "1970-02-01T00:15:00Z|1970-02-01T00:10:00Z|1970-01-01T00:11:00Z|" ]; then
  ok "REQ-F1.1: the three newest decisions, newest first, across segments"
else
  fail "REQ-F1.1: decisions read '$got'"
fi
record "a decision carries its subject and act" decision 1970-02-01T00:15:00Z "relaunch w-one" relaunch
record "REQ-L1.4: the budget rung" rung normal "every dimension under the throttle threshold"
expect_out "REQ-L1.4: headroom per dimension" "headroom${tab}polls_per_hour${tab}"
record "REQ-L1.4: a watcher's expiry, a next run already passed" watcher alpha-duty alpha-watch.sh stopped -130
record "REQ-H1.4: the forge source with its mode and age" source code-state forge snapshot 30
record "REQ-H1.4: a record source carries no age" source decisions specs record -
record "REQ-H1.4: a class with no source is cited" source designs - cited -
record "REQ-F1.1: knowledge-base freshness, the index's age" kb 130
record "REQ-M1.8: interruptions per hour, with their age" measure interruptions_per_hour 2.5 130
record "REQ-M1.8: the settled share" measure settled_share 80 130
record "REQ-L1.5: the context threshold knob" knob handover-context 70
record "REQ-L1.5: the wake ceiling knob" knob handover-wakes 150
record "REQ-L1.5: the compaction ceiling knob" knob handover-compactions 2
record "the redraw cadence knob, in seconds" knob refresh 10
record "the tick cadence knob, in seconds" knob tick 300
record "D-29: no handover verb yet" handover absent
record "REQ-F1.2: the text line" line "mission control alpha: 3 in flight, 0 waiting, 1 pending, rung normal, tracker snapshot 30s old"
mc_run mc-panel.sh digest --program alpha --now 1030
expect_no_out "knobs only with --knobs" "knob${tab}"

# The text form alone, as a session without the mod reads it.
mc_run mc-panel.sh line --program alpha --target mc-alpha --now 1030
expect_rc "the line" 0
expect_eq "REQ-F1.2: the line form, one line" "mission control alpha: 3 in flight, 0 waiting, 1 pending, rung normal, tracker snapshot 30s old"

# A store that cannot be read is said, never drawn as empty.
printf 'format\t9\n' >"$runtime/measures"
mc_run mc-panel.sh digest --program alpha --now 1030
record "a measures file of an unknown format is refused, named" measure - unreadable -
expect_no_out "no pending count without a target" "pending${tab}"
rm -f "$runtime/measures"
mc_run mc-panel.sh digest --program alpha --now 1030
record "REQ-M1.8: no measures yet" measure - none -

# Stored text never reaches a terminal raw.
printf 'decisions-197002-3\t1970-01-01T00:20:00Z\tbad \033[2Jsubject\tact\tx\ty\tnone\t-\n' >>"$home/kb/decisions-1970-02.log"
mc_run mc-panel.sh digest --program alpha --now 1030
case $OUT in
  *"$(printf '\033')"*) fail "a control byte reached the digest" ;;
  *) ok "control bytes are dropped from stored text" ;;
esac

# A segment of an unknown format, or a symlinked knowledge base, is
# unreadable, never drawn.
printf '# format: 9\n' >"$home/kb/decisions-1970-03.log"
mc_run mc-panel.sh digest --program alpha --now 1030
record "a segment of an unknown format is unreadable" unreadable "decisions log"
expect_no_out "and none of its decisions are drawn" "decision${tab}"
rm -f "$home/kb/decisions-1970-03.log"
mv "$home/kb" "$home/kb.real"
ln -s "$home/kb.real" "$home/kb"
mc_run mc-panel.sh digest --program alpha --now 1030
record "a symlinked knowledge base is unreadable" unreadable "decisions log"
record "and its freshness is unreadable, not unwritten" unreadable "knowledge base"
rm -f "$home/kb"
mc_run mc-panel.sh digest --program alpha --now 1030
record "no index yet reads as not written" kb -
mv "$home/kb.real" "$home/kb"

# A handover ceiling of 0 would fire at once: refused like any invalid value.
printf 'mission_control_handover_compactions: 0\n' >>"$tracked"
mc_run mc-panel.sh digest --program alpha --knobs --now 1030
record "a zero compaction ceiling is refused" unreadable "knob mission_control_handover_compactions"
setup_tracked=$(grep -v '^mission_control_handover_compactions' "$tracked")
printf '%s\n' "$setup_tracked" >"$tracked"

mc_run mc-panel.sh digest --program beta
expect_rc "an unconfigured program" 3
mc_run mc-panel.sh digest --program alpha --target 'bad;t'
expect_rc "a target outside the grammar" 2

# ---------------------------------------------------------------------------
# presence: the producer marker the operator queue reads.
# ---------------------------------------------------------------------------
mc_run mc-panel.sh presence --program alpha --prompt --now 4000
expect_rc "a prompt event is recorded" 0
pres=$runtime/presence
if [ "$(cat "$pres" 2>/dev/null)" = "$(printf 'format\t1\nproducer\tmission-control-panel\nwritten\t4000\nlast-prompt\t4000')" ]; then
  ok "REQ-F1.4 input: the prompt event lands in the presence marker"
else
  fail "unexpected presence marker: $(cat "$pres" 2>/dev/null)"
fi
mc_run mc-panel.sh presence --program alpha --refresh --now 4100
case $(cat "$pres") in
  *"written${tab}4100"*"last-prompt${tab}4000"*) ok "a refresh keeps the last prompt and restamps the producer" ;;
  *) fail "the refresh lost the prompt time: $(cat "$pres")" ;;
esac
rm -f "$pres"
mc_run mc-panel.sh presence --program alpha --refresh --now 4200
case $(cat "$pres") in
  *"last-prompt${tab}-"*) ok "a refresh before any prompt records none" ;;
  *) fail "unexpected first refresh: $(cat "$pres")" ;;
esac
mc_run mc-panel.sh presence --program alpha --now 4200
expect_rc "presence needs --prompt or --refresh" 2
mc_run mc-panel.sh presence --program alpha --refresh --target mc-alpha --now 4300
if [ "$(cat "$runtime/leases/mc-alpha" 2>/dev/null)" = 4300 ]; then
  ok "a target's lease is restamped with the marker"
else
  fail "the lease reads '$(cat "$runtime/leases/mc-alpha" 2>/dev/null)'"
fi

mv "$runtime/leases" "$runtime/leases.real"
ln -s "$runtime/leases.real" "$runtime/leases"
mc_run mc-panel.sh presence --program alpha --refresh --target mc-alpha --now 4400
expect_rc "a symlinked lease directory is refused" 1
if [ "$(cat "$runtime/leases.real/mc-alpha")" = 4300 ]; then ok "and nothing is written through it"; else fail "a lease was written through the symlink"; fi
rm -f "$runtime/leases"
mv "$runtime/leases.real" "$runtime/leases"

# A store that is a symlink is unreadable, never unwritten.
mv "$runtime/budget" "$runtime/budget.saved"
ln -s "$tmp/nowhere" "$runtime/budget"
ln -s "$tmp/nowhere" "$runtime/measures"
mc_run mc-panel.sh digest --program alpha --now 1030
record "a symlinked budget is unreadable" unreadable budget
record "symlinked measures are unreadable" measure - unreadable -
rm -f "$runtime/budget" "$runtime/measures"
mv "$runtime/budget.saved" "$runtime/budget"
printf 'format\t1\ntaken\t900\n' >"$runtime/measures"
mc_run mc-panel.sh digest --program alpha --now 1030
record "measures with no rows read as none" measure - none -
rm -f "$runtime/measures"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-panel: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-panel: all passed"
