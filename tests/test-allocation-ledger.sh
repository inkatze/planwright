#!/bin/bash
# Tests for scripts/allocation-ladder.sh and scripts/allocation-ledger.sh — the
# per-unit allocation ledger and the tier-ladder math it replays
# (model-allocation Task 2; D-6, D-8; REQ-C1.1, REQ-F1.1, REQ-F1.3).
#
# The ledger is the authoritative, append-only allocation store, one file per
# unit under the fleet home. A unit's current tier is DERIVED from its own rows
# plus configuration — memoryless, so a relaunched resolver computes the same
# tier from the same inputs (REQ-C1.1). The engine's decisions
# (scripts/allocation-adapt.sh) are covered by tests/test-allocation-adapt.sh;
# this file covers the store and the math underneath it.
#
# What is covered:
#   - the ladder rules (D-8): the successor path's hinge (effort up to `high`,
#     then model up keeping `high`), the mirror path's hinge (effort down to
#     `low`, then model down keeping `low`), the ladder ends, and the
#     model-major cost order that is DELIBERATELY a different ordering from the
#     movement path;
#   - the pinned row schema (D-6, REQ-F1.1): field count, enum validation,
#     monotone sequence numbering, and refusal of hostile/oversize input;
#   - derivation (REQ-C1.1): convergence across repeated invocations, the
#     zero-history starting tier, config sensitivity, reversal ordering (a
#     de-escalation restores the pre-step tier, un-bumping the model before the
#     effort), the mirror fallback with no escalation to reverse, and net
#     displacement with refunds;
#   - the per-unit lock (D-6): concurrent same-unit appends serialize with no
#     lost row and no duplicate sequence number, and cross-unit appends never
#     contend;
#   - health and degraded mode (REQ-F1.1): a torn/corrupt/short row makes the
#     ledger unhealthy, and the last recorded tier stays readable;
#   - instrumentation (REQ-F1.3): `stats` surfaces unit count, row count, byte
#     size, and derivation latency, and a scale fixture bounds derivation.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-allocation-ledger.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
LADDER="$here/../scripts/allocation-ladder.sh"
LEDGER="$here/../scripts/allocation-ledger.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# `append` prints the new row's sequence number. The fixtures below care only
# about its exit status, so they go through this helper and leave stdout quiet.
led() {
  "$LEDGER" "$@" >/dev/null
}

[ -r "$LADDER" ] || fail "scripts/allocation-ladder.sh missing or not readable"
[ -x "$LEDGER" ] || fail "scripts/allocation-ledger.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Every ledger path resolves under an isolated fleet home, so the host's real
# fleet state is never read or written.
PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet"
export PLANWRIGHT_FLEET_STATE_DIR
mkdir -p "$PLANWRIGHT_FLEET_STATE_DIR"

# The ladder library is a sourced helper (the echo-safety.sh precedent), so the
# math is exercised in-process here and in the engine, never re-implemented.
# shellcheck source=scripts/allocation-ladder.sh
. "$LADDER"

# --- 1. the successor path and its hinge (D-8) -----------------------------

step_up() {
  alloc_successor "$1" "$2"
}

got=$(step_up sonnet low) || fail "1a: successor (sonnet, low) returned non-zero"
[ "$got" = "sonnet medium" ] || fail "1a: (sonnet, low) -> '$got', want 'sonnet medium'"

got=$(step_up sonnet medium) || fail "1b: successor (sonnet, medium) returned non-zero"
[ "$got" = "sonnet high" ] || fail "1b: (sonnet, medium) -> '$got', want 'sonnet high'"

# The hinge: at `high` the MODEL steps up and effort STAYS `high` — not the next
# model's lowest or configured effort. This is the rule a model-only reading of
# the ladder gets wrong, so it is pinned directly.
got=$(step_up sonnet high) || fail "1c: successor (sonnet, high) returned non-zero"
[ "$got" = "opus high" ] || fail "1c: (sonnet, high) -> '$got', want 'opus high'"

got=$(step_up opus high) || fail "1d: successor (opus, high) returned non-zero"
[ "$got" = "fable high" ] || fail "1d: (opus, high) -> '$got', want 'fable high'"

# The ladder top is a hard stop: a further escalation has nowhere to go.
if alloc_successor fable high >/dev/null 2>&1; then
  fail "1e: successor (fable, high) should refuse — the ladder top is a hard stop"
fi
alloc_is_top fable high || fail "1f: (fable, high) is not reported as the ladder top"
if alloc_is_top opus high; then fail "1f: (opus, high) wrongly reported as the ladder top"; fi

# --- 2. the mirror path and its hinge (D-8) --------------------------------

got=$(alloc_mirror opus high) || fail "2a: mirror (opus, high) returned non-zero"
[ "$got" = "opus medium" ] || fail "2a: (opus, high) -> '$got', want 'opus medium'"

got=$(alloc_mirror opus medium) || fail "2b: mirror (opus, medium) returned non-zero"
[ "$got" = "opus low" ] || fail "2b: (opus, medium) -> '$got', want 'opus low'"

# The mirror hinge: at `low` the MODEL steps down and effort STAYS `low`.
got=$(alloc_mirror opus low) || fail "2c: mirror (opus, low) returned non-zero"
[ "$got" = "sonnet low" ] || fail "2c: (opus, low) -> '$got', want 'sonnet low'"

if alloc_mirror haiku low >/dev/null 2>&1; then
  fail "2d: mirror (haiku, low) should refuse — the ladder floor is a hard stop"
fi
alloc_is_bottom haiku low || fail "2e: (haiku, low) is not reported as the ladder floor"

# --- 3. cost order is a DIFFERENT ordering from the movement path (D-8) ----

# Model-major, effort-minor: a cheaper model is cheaper at ANY effort, so
# (sonnet, high) is cheaper than (opus, low) even though the successor path
# from (sonnet, high) reaches (opus, high), skipping (opus, low) entirely.
got=$(alloc_cheaper sonnet high opus low) || fail "3a: alloc_cheaper returned non-zero"
[ "$got" = "sonnet high" ] || fail "3a: cheaper of (sonnet,high)/(opus,low) -> '$got'"

got=$(alloc_cheaper opus low sonnet high) || fail "3b: alloc_cheaper returned non-zero"
[ "$got" = "sonnet high" ] || fail "3b: alloc_cheaper is not symmetric: '$got'"

got=$(alloc_cheaper opus low opus high) || fail "3c: alloc_cheaper returned non-zero"
[ "$got" = "opus low" ] || fail "3c: within one model the lower effort is cheaper: '$got'"

got=$(alloc_cheaper haiku high haiku high) || fail "3d: alloc_cheaper returned non-zero"
[ "$got" = "haiku high" ] || fail "3d: equal tiers should return the tier: '$got'"

# --- 4. the pinned row schema (D-6, REQ-F1.1) ------------------------------

unit=model-allocation:2
led append "$unit" step-1 1 launch \
  sonnet medium sonnet medium sonnet medium unit resolved 'trigger=none;rung=normal' \
  || fail "4a: a well-formed append was refused"

file=$("$LEDGER" path "$unit") || fail "4b: path refused a valid unit key"
[ -f "$file" ] || fail "4b: append did not create the ledger file at $file"

rowcount=$(wc -l <"$file" | tr -d ' ')
[ "$rowcount" = 1 ] || fail "4c: expected exactly one row, got $rowcount"

row=$("$LEDGER" rows "$unit") || fail "4d: rows refused a healthy ledger"
fields=$(printf '%s' "$row" | awk -F "$TAB" '{ print NF }')
[ "$fields" = 15 ] || fail "4d: the pinned schema is 15 fields, row carries $fields"

# Field 1 is the sequence number, and it starts at 1.
seq1=$(printf '%s' "$row" | cut -f1)
[ "$seq1" = 1 ] || fail "4e: the first row's seq is '$seq1', want 1"

# The unit, event, scope and outcome land in their pinned columns.
[ "$(printf '%s' "$row" | cut -f3)" = "$unit" ] || fail "4f: column 3 is not the unit"
[ "$(printf '%s' "$row" | cut -f6)" = launch ] || fail "4f: column 6 is not the event class"
[ "$(printf '%s' "$row" | cut -f13)" = unit ] || fail "4f: column 13 is not the scope"
[ "$(printf '%s' "$row" | cut -f14)" = resolved ] || fail "4f: column 14 is not the outcome"

# Sequence numbers are monotone: the second append is 2, never a restart.
led append "$unit" step-1 1 step-failure \
  sonnet medium sonnet high sonnet high unit applied 'trigger=step-failure;dir=up' \
  || fail "4g: the second append was refused"
seq2=$("$LEDGER" rows "$unit" | sed -n 2p | cut -f1)
[ "$seq2" = 2 ] || fail "4g: the second row's seq is '$seq2', want 2"

# --- 5. hostile and out-of-grammar input is refused, never written ---------

before=$(wc -l <"$file" | tr -d ' ')

if led append "$unit" step-1 1 not-an-event \
  sonnet medium sonnet medium sonnet medium unit resolved 'x=1' >/dev/null 2>&1; then
  fail "5a: an out-of-enum event class was accepted"
fi
if led append "$unit" step-1 1 launch \
  gpt-4 medium sonnet medium sonnet medium unit resolved 'x=1' >/dev/null 2>&1; then
  fail "5b: an out-of-enum model was accepted"
fi
if led append "$unit" step-1 1 launch \
  sonnet medium sonnet medium sonnet medium sideways resolved 'x=1' >/dev/null 2>&1; then
  fail "5c: an out-of-enum scope was accepted"
fi
if led append "../../etc/passwd" step-1 1 launch \
  sonnet medium sonnet medium sonnet medium unit resolved 'x=1' >/dev/null 2>&1; then
  fail "5d: a traversal unit key was accepted"
fi
# A tab in a field would tear the row; a control byte would drive a terminal.
if led append "$unit" "step${TAB}1" 1 launch \
  sonnet medium sonnet medium sonnet medium unit resolved 'x=1' >/dev/null 2>&1; then
  fail "5e: an embedded tab in the step field was accepted"
fi
# The inputs field is bounded so one row stays a single small append.
big=$(awk 'BEGIN { s = ""; while (length(s) < 400) s = s "k=v;"; print s }')
if led append "$unit" step-1 1 launch \
  sonnet medium sonnet medium sonnet medium unit resolved "$big" >/dev/null 2>&1; then
  fail "5f: an oversize inputs field was accepted"
fi

after=$(wc -l <"$file" | tr -d ' ')
[ "$before" = "$after" ] || fail "5g: a refused append still wrote to the ledger"

# --- 6. derivation: convergence, zero history, config sensitivity ----------

d_unit=derive:unit
led append "$d_unit" step-1 1 launch \
  sonnet medium sonnet medium sonnet medium unit resolved 'trigger=none' || fail "6: seed append"

# Zero history is the starting tier; a rows-but-no-adjustment ledger is too.
got=$("$LEDGER" derive fresh:unit sonnet medium) || fail "6a: derive refused a zero-history unit"
[ "$(printf '%s' "$got" | cut -f1,2)" = "sonnet${TAB}medium" ] \
  || fail "6a: zero-history derivation is '$got', want the starting tier"
[ "$(printf '%s' "$got" | cut -f3)" = 0 ] || fail "6a: zero-history net displacement is not 0"

got=$("$LEDGER" derive "$d_unit" sonnet medium) || fail "6b: derive refused a healthy ledger"
[ "$(printf '%s' "$got" | cut -f1,2)" = "sonnet${TAB}medium" ] \
  || fail "6b: a launch-only ledger moved the tier: '$got'"

# Two applied escalations: (sonnet, medium) -> (sonnet, high) -> (opus, high).
led append "$d_unit" step-1 1 step-failure \
  sonnet medium sonnet high sonnet high unit applied 'dir=up' || fail "6: up 1"
led append "$d_unit" step-2 1 flailing \
  sonnet high opus high opus high unit applied 'dir=up' || fail "6: up 2"

got=$("$LEDGER" derive "$d_unit" sonnet medium) || fail "6c: derive failed"
[ "$(printf '%s' "$got" | cut -f1,2)" = "opus${TAB}high" ] \
  || fail "6c: two escalations should reach (opus, high), got '$got'"
[ "$(printf '%s' "$got" | cut -f3)" = 2 ] || fail "6c: net displacement is not 2"

# Convergence: repeated derivation over the same records and config is stable.
again=$("$LEDGER" derive "$d_unit" sonnet medium) || fail "6d: derive failed on replay"
[ "$again" = "$got" ] || fail "6d: derivation is not memoryless: '$again' != '$got'"

# Config sensitivity: records PLUS config is the pinned input set (REQ-C1.1), so
# a changed starting tier moves the whole replay. From (haiku, low) the SAME two
# rows land two effort levels up instead, never on the tier above.
other=$("$LEDGER" derive "$d_unit" haiku low) || fail "6e: derive failed"
[ "$(printf '%s' "$other" | cut -f1,2)" = "haiku${TAB}high" ] \
  || fail "6e: from (haiku, low) two steps should reach (haiku, high), got '$other'"
[ "$(printf '%s' "$other" | cut -f1,2)" != "$(printf '%s' "$got" | cut -f1,2)" ] \
  || fail "6e: the derived tier did not move with the configured starting tier"

# The rows are unchanged across both derivations — only the config differed.
[ "$(printf '%s' "$other" | cut -f5)" = "$(printf '%s' "$got" | cut -f5)" ] \
  || fail "6f: the two derivations scanned different row counts"

# --- 7. reversal ordering and the mirror fallback (D-8) --------------------

# A de-escalation reverses the MOST RECENT UNREVERSED escalation step, so the
# two-step fixture above un-bumps the MODEL before it touches the effort.
led append "$d_unit" step-3 1 petition-de-escalate \
  opus high sonnet high sonnet high unit applied 'dir=down' || fail "7: down 1"
got=$("$LEDGER" derive "$d_unit" sonnet medium) || fail "7a: derive failed"
[ "$(printf '%s' "$got" | cut -f1,2)" = "sonnet${TAB}high" ] \
  || fail "7a: the reversal should restore (sonnet, high), got '$got'"
[ "$(printf '%s' "$got" | cut -f3)" = 1 ] || fail "7a: a reversal should refund the net (want 1)"

led append "$d_unit" step-4 1 petition-de-escalate \
  sonnet high sonnet medium sonnet medium unit applied 'dir=down' || fail "7: down 2"
got=$("$LEDGER" derive "$d_unit" sonnet medium) || fail "7b: derive failed"
[ "$(printf '%s' "$got" | cut -f1,2)" = "sonnet${TAB}medium" ] \
  || fail "7b: the second reversal should restore the starting tier, got '$got'"
[ "$(printf '%s' "$got" | cut -f3)" = 0 ] || fail "7b: net should be back to 0"

# With no escalation left to reverse, a de-escalation steps BELOW the starting
# tier by the mirror rule.
led append "$d_unit" step-5 1 petition-de-escalate \
  sonnet medium sonnet low sonnet low unit applied 'dir=down' || fail "7: down 3"
got=$("$LEDGER" derive "$d_unit" sonnet medium) || fail "7c: derive failed"
[ "$(printf '%s' "$got" | cut -f1,2)" = "sonnet${TAB}low" ] \
  || fail "7c: the mirror step should reach (sonnet, low), got '$got'"
[ "$(printf '%s' "$got" | cut -f3)" = -1 ] || fail "7c: net below start should be -1"

# An escalation from below start RE-RAISES along the successor path.
led append "$d_unit" step-6 1 step-failure \
  sonnet low sonnet medium sonnet medium unit applied 'dir=up' || fail "7: up 3"
got=$("$LEDGER" derive "$d_unit" sonnet medium) || fail "7d: derive failed"
[ "$(printf '%s' "$got" | cut -f1,2)" = "sonnet${TAB}medium" ] \
  || fail "7d: re-raise should follow the successor path, got '$got'"

# Rows that were NOT applied never move the tier — a denial, a no-op, an
# ignore, and a step-scoped row are all inert to unit-tier derivation.
inert=inert:unit
led append "$inert" s 1 step-failure sonnet medium - - sonnet medium unit denied 'x=1'
led append "$inert" s 1 flailing fable high - - fable high unit no-op 'x=1'
led append "$inert" s 1 launch sonnet medium haiku low haiku low step applied 'x=1'
got=$("$LEDGER" derive "$inert" sonnet medium) || fail "7e: derive failed"
[ "$(printf '%s' "$got" | cut -f1,2)" = "sonnet${TAB}medium" ] \
  || fail "7e: non-applied and step-scoped rows moved the unit tier: '$got'"

# --- 8. the per-unit lock serializes same-unit appends (D-6) ---------------
#
# Twelve racers rather than two, deliberately. This assertion is a REGRESSION
# GUARD for a measured defect: the `mkdir`-based advisory-lock shape lost mutual
# exclusion here from three concurrent same-unit writers upward, so two launches
# could derive a tier from the same ledger state. Twelve is where it showed up
# reliably enough to fail a test rather than a production run.

c_unit=concurrent:unit
i=0
while [ "$i" -lt 12 ]; do
  led append "$c_unit" "step-$i" 1 launch \
    sonnet medium sonnet medium sonnet medium unit resolved "n=$i" &
  i=$((i + 1))
done
wait
lines=$("$LEDGER" rows "$c_unit" | wc -l | tr -d ' ')
[ "$lines" = 12 ] || fail "8a: concurrent appends lost rows: $lines of 12 landed"
uniq_seq=$("$LEDGER" rows "$c_unit" | cut -f1 | sort -n | uniq | wc -l | tr -d ' ')
[ "$uniq_seq" = 12 ] || fail "8b: concurrent appends produced duplicate sequence numbers"
"$LEDGER" health "$c_unit" || fail "8c: concurrent appends left the ledger unhealthy"

# The OWNER TOKEN is what makes release safe: a holder returning after its lock
# was broken must not delete the CURRENT holder's lock. `lock` prints the token
# and `unlock` only acts when the token still matches.
tok=$("$LEDGER" lock lockowner:unit) || fail "8d: lock failed"
[ -n "$tok" ] || fail "8d: lock printed no owner token"
lock_file="$("$LEDGER" home)/.lock.lockowner:unit"
[ -L "$lock_file" ] || fail "8d: the lock left no marker at $lock_file"
"$LEDGER" unlock lockowner:unit "not-the-token" || fail "8e: unlock with a foreign token errored"
[ -L "$lock_file" ] || fail "8e: a foreign token released someone else's lock"
[ "$(readlink "$lock_file")" = "$tok" ] || fail "8e: the owner token changed under a foreign unlock"
"$LEDGER" unlock lockowner:unit "$tok" || fail "8f: unlock with the real token failed"
[ -L "$lock_file" ] && fail "8f: the owner's unlock did not release the lock"
tok3=$("$LEDGER" lock lockowner:unit) || fail "8g: the lock could not be re-acquired after release"
"$LEDGER" unlock lockowner:unit "$tok3"

# A failure that is NOT contention must fail closed at once. The ~100s spin
# budget buys patience for a deep same-unit queue; spending it on a condition
# no amount of waiting can clear is a stall, and the caller reads the eventual
# refusal as contention that was never there.
lock_home=$("$LEDGER" home)
mkdir -p "$lock_home"

# The stale break only ever claims a SYMLINK, so a plain file squatting the
# lock path is unclearable by definition.
squat="$lock_home/.lock.squat:unit"
: >"$squat"
l_start=$(date +%s)
if "$LEDGER" lock squat:unit >/dev/null 2>&1; then
  fail "8h: a non-symlink squatting the lock path was accepted as a held lock"
fi
l_elapsed=$(($(date +%s) - l_start))
[ "$l_elapsed" -le 10 ] \
  || fail "8h: a squatted lock path spun ${l_elapsed}s before refusing; it must fail closed at once"
rm -f "$squat"

# A store that exists but cannot be written: every `ln -s` fails, and a check
# that only looks for a MISSING parent directory never fires, because the
# directory is right there.
chmod 555 "$lock_home"
if (: >"$lock_home/.probe") 2>/dev/null; then
  # A user who writes through mode 555 (root, or a permissive filesystem)
  # cannot exercise this case; skipping beats asserting something untrue.
  rm -f "$lock_home/.probe"
  chmod 755 "$lock_home"
  echo "ok: unwritable-store lock case skipped (this user writes through mode 555)"
else
  l_start=$(date +%s)
  l_held=0
  "$LEDGER" lock unwritable:unit >/dev/null 2>&1 && l_held=1
  l_elapsed=$(($(date +%s) - l_start))
  chmod 755 "$lock_home"
  [ "$l_held" = 0 ] || fail "8i: a lock was reported held on an unwritable store"
  [ "$l_elapsed" -le 10 ] \
    || fail "8i: an unwritable store spun ${l_elapsed}s before refusing; it must fail closed at once"
fi

# --- 9. health and degraded mode (REQ-F1.1) -------------------------------

h_unit=health:unit
led append "$h_unit" s 1 launch sonnet medium sonnet medium sonnet high unit resolved 'x=1'
"$LEDGER" health "$h_unit" || fail "9a: a well-formed ledger is reported unhealthy"

# The last recorded tier stays readable — it is what a degraded launch uses.
last=$("$LEDGER" last-tier "$h_unit") || fail "9b: last-tier failed on a healthy ledger"
[ "$last" = "sonnet${TAB}high" ] || fail "9b: last-tier is '$last', want the RESOLVED tier"

# A torn row (a short write) makes the ledger unhealthy without destroying the
# readable history before it.
h_file=$("$LEDGER" path "$h_unit")
printf '2\t%s\tbroken\n' "$(date +%s)" >>"$h_file"
if "$LEDGER" health "$h_unit" >/dev/null 2>&1; then
  fail "9c: a torn short row did not make the ledger unhealthy"
fi
last=$("$LEDGER" last-tier "$h_unit") || fail "9d: last-tier failed on an unhealthy ledger"
[ "$last" = "sonnet${TAB}high" ] || fail "9d: last-tier lost the pre-corruption tier: '$last'"

# A non-monotone sequence is corruption too: derivation order would be undefined.
h2=health2:unit
h2_file=$("$LEDGER" path "$h2")
mkdir -p "$(dirname "$h2_file")"
now=$(date +%s)
printf '2\t%s\t%s\ts\t1\tlaunch\tsonnet\tmedium\tsonnet\tmedium\tsonnet\tmedium\tunit\tresolved\tx=1\n' "$now" "$h2" >"$h2_file"
printf '1\t%s\t%s\ts\t1\tlaunch\tsonnet\tmedium\tsonnet\tmedium\tsonnet\tmedium\tunit\tresolved\tx=1\n' "$now" "$h2" >>"$h2_file"
if "$LEDGER" health "$h2" >/dev/null 2>&1; then
  fail "9e: a non-monotone sequence did not make the ledger unhealthy"
fi

# An unreadable ledger is unhealthy, not a crash.
h3=health3:unit
h3_file=$("$LEDGER" path "$h3")
printf 'x\n' >"$h3_file"
chmod 000 "$h3_file"
if [ "$(id -u)" != 0 ]; then
  if "$LEDGER" health "$h3" >/dev/null 2>&1; then
    fail "9f: an unreadable ledger was reported healthy"
  fi
fi
chmod 644 "$h3_file"

# An out-of-enum cell is corruption too, and replay is why it has to be: a row
# whose event class falls outside the closed set is SKIPPED by `alloc_replay`,
# so a single corrupted cell quietly changes the derived tier while `health`
# still calls the file trustworthy. The enums `append` refuses on the way in
# are the enums `health` has to refuse on the way back out.
h4=health4:unit
led append "$h4" step-1 1 step-failure \
  sonnet medium sonnet medium sonnet medium unit applied 'x=1' || fail "9g: seed append failed"
h4_file=$("$LEDGER" path "$h4")

corrupt_cell() {
  awk -F "$TAB" -v col="$1" -v val="$2" 'BEGIN { OFS = FS } { $col = val; print }' \
    "$h4_file" >"$h4_file.tmp" && mv "$h4_file.tmp" "$h4_file"
}

corrupt_cell 6 not-an-event
if "$LEDGER" health "$h4" >/dev/null 2>&1; then
  fail "9g: an out-of-enum event class was reported healthy"
fi
corrupt_cell 6 step-failure

corrupt_cell 11 gpt-4
if "$LEDGER" health "$h4" >/dev/null 2>&1; then
  fail "9h: an out-of-enum model cell was reported healthy"
fi
corrupt_cell 11 sonnet

corrupt_cell 12 turbo
if "$LEDGER" health "$h4" >/dev/null 2>&1; then
  fail "9i: an out-of-enum effort cell was reported healthy"
fi
corrupt_cell 12 medium

# The two widenings the schema DOES allow stay healthy, so the check does not
# condemn a legitimately inherited or tier-less row.
corrupt_cell 11 inherit
corrupt_cell 12 inherit
"$LEDGER" health "$h4" || fail "9j: an inherit tier cell was reported unhealthy"
corrupt_cell 11 -
corrupt_cell 12 -
"$LEDGER" health "$h4" || fail "9k: a tier-less '-' cell was reported unhealthy"

# An unhealthy ledger still takes appends — the engine records its DEGRADED
# launch onto exactly the file it just called untrustworthy — so the sequence
# that append derives must not deepen the corruption it is writing into.
# Deriving from the LAST well-formed row rather than the HIGHEST one hands back
# a number the file already carries.
h5=health5:unit
h5_file=$("$LEDGER" path "$h5")
mkdir -p "$(dirname "$h5_file")"
now=$(date +%s)
for s in 1 3 2; do
  printf '%s\t%s\t%s\ts\t1\tlaunch\tsonnet\tmedium\tsonnet\tmedium\tsonnet\tmedium\tunit\tresolved\tx=1\n' \
    "$s" "$now" "$h5" >>"$h5_file"
done
led append "$h5" s 1 launch sonnet medium sonnet medium sonnet medium unit degraded 'x=1' \
  || fail "9l: a degraded-mode append onto an unhealthy ledger failed"
h5_new=$(awk -F "$TAB" 'END { print $1 }' "$h5_file")
[ "$h5_new" = 4 ] \
  || fail "9l: the append took sequence $h5_new, want 4 — it must clear the HIGHEST row, not the last"
h5_dupes=$(awk -F "$TAB" 'NF == 15 { c[$1]++ } END { for (k in c) if (c[k] > 1) n++; print n + 0 }' "$h5_file")
[ "$h5_dupes" = 0 ] || fail "9l: the append reused a sequence number the ledger already carried"

# The attempt column carries `valid_count`'s grammar, not merely "some digits".
# `append` refuses a leading-zero spelling, so a `health` that accepts one
# passes rows the writer could never have produced: the ledger reads as healthy
# while carrying a row no append path explains. Built with printf rather than an
# awk field assignment, because awk's strnum handling would turn `01` back into
# `1` and test nothing.
h6=health6:unit
h6_file=$("$LEDGER" path "$h6")
mkdir -p "$(dirname "$h6_file")"
printf '1\t%s\t%s\ts\t01\tlaunch\tsonnet\tmedium\tsonnet\tmedium\tsonnet\tmedium\tunit\tresolved\tx=1\n' \
  "$now" "$h6" >"$h6_file"
if "$LEDGER" health "$h6" >/dev/null 2>&1; then
  fail "9m: a leading-zero attempt was reported healthy"
fi
# `0` is a legal count, so health must not tighten past what append accepts.
printf '1\t%s\t%s\ts\t0\tlaunch\tsonnet\tmedium\tsonnet\tmedium\tsonnet\tmedium\tunit\tresolved\tx=1\n' \
  "$now" "$h6" >"$h6_file"
"$LEDGER" health "$h6" || fail "9n: attempt 0 was reported unhealthy, but it is a legal count"

# --- 10. instrumentation and scale (REQ-F1.3) -----------------------------

stats=$("$LEDGER" stats) || fail "10a: stats failed"
for k in units rows bytes derivation_ms; do
  printf '%s\n' "$stats" | grep -q "^$k$TAB" || fail "10a: stats is missing the '$k' line"
done
units=$(printf '%s\n' "$stats" | awk -F "$TAB" '$1 == "units" { print $2 }')
[ "$units" -ge 4 ] || fail "10a: stats undercounts units ($units)"

# The scale fixture: a long multi-day unit history derives within the pinned
# budget, so a scan-cost regression fails here rather than in operation.
s_unit=scale:unit
s_file=$("$LEDGER" path "$s_unit")
mkdir -p "$(dirname "$s_file")"
awk -v unit="$s_unit" -v now="$now" 'BEGIN {
  for (i = 1; i <= 2000; i++) {
    ev = (i % 7 == 0) ? "step-failure" : "launch"
    oc = (i % 7 == 0) ? "applied" : "resolved"
    printf "%d\t%d\t%s\ts%d\t1\t%s\thaiku\tlow\thaiku\tlow\thaiku\tlow\tunit\t%s\tn=%d\n", \
      i, now - (2000 - i) * 300, unit, i, ev, oc, i
  }
}' >"$s_file"

# The budget is deliberately GENEROUS. This suite runs N-way parallel on a
# shared machine, so a tight wall-clock bound measures load, not scan cost — it
# fails on a busy CI box while a real regression walks past. The regression
# class it has to catch is a scan that stops being linear (a per-row re-scan, a
# fork per row): that is orders of magnitude on 2000 rows, not a few seconds.
# The fine-grained reading is `stats`' derivation_ms, asserted below and
# surfaced through `fleet-stats.sh render` for operation.
start=$(date +%s)
got=$("$LEDGER" derive "$s_unit" haiku low) || fail "10b: derive failed on the scale fixture"
elapsed=$(($(date +%s) - start))
[ "$elapsed" -le 60 ] || fail "10b: derivation over 2000 rows took ${elapsed}s (budget 60s)"
[ "$(printf '%s' "$got" | cut -f5)" = 2000 ] || fail "10b: the scale fixture did not scan 2000 rows"

s_stats=$("$LEDGER" stats "$s_unit") || fail "10c: per-unit stats failed"
s_rows=$(printf '%s\n' "$s_stats" | awk -F "$TAB" '$1 == "rows" { print $2 }')
[ "$s_rows" = 2000 ] || fail "10c: per-unit stats reports $s_rows rows, want 2000"
s_ms=$(printf '%s\n' "$s_stats" | awk -F "$TAB" '$1 == "derivation_ms" { print $2 }')
case $s_ms in
  '' | *[!0-9]*) fail "10c: derivation_ms is not a plain integer: '$s_ms'" ;;
esac

echo "PASS: allocation-ledger ($(basename "$0"))"
