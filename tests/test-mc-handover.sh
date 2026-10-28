#!/bin/bash
# Tests for scripts/mc-handover.sh — mission control's succession, from the
# trigger to the resume (mission-control REQ-A1.1, REQ-A1.7, REQ-B1.7,
# REQ-L1.3, REQ-L1.5, REQ-L1.6). Successors launch on the stream-json rung
# against a CLI shim that reads its first message and exits, so each
# registry row is real and each retire goes through the launcher.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }
tab=$(printf '\t')

for t in jq git; do
  command -v "$t" >/dev/null 2>&1 || {
    echo "FAIL: $t is required to run this suite" >&2
    exit 1
  }
done
[ -f "$repo_root/scripts/mc-handover.sh" ] || {
  echo "FAIL: scripts/mc-handover.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-handover.XXXXXX") || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
tmp=$(cd "$tmp" && pwd -P) || exit 1
fleet="$tmp/fleet"
cleanup() {
  for d in "$fleet"/streamjson/*/; do
    [ -d "$d" ] || continue
    env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-streamjson.sh" \
      stop "$(basename "$d")" --grace 1 >/dev/null 2>&1 || :
  done
  rm -rf "$tmp"
}
trap cleanup EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"
reset_mc_fixture
cp "$repo_root/config/defaults.yml" "$core/config/defaults.yml"
for p in worker tower mission-control; do
  cp "$repo_root/config/$p-settings.json" "$core/config/"
done
mkdir -p "$repo/specs" "$fleet" "$tmp/bin"
home="$tmp/mc-home/alpha"
bhome="$tmp/mc-home/beta"
cat >"$tracked" <<EOF
mission_control_programs: [alpha, beta]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo/specs
program_alpha_home: $home
program_alpha_duties: [alpha-duty]
program_beta_repositories: [$repo]
program_beta_spec_root: $repo/specs
program_beta_home: $bhome
program_beta_duties: [alpha-duty]
EOF
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
IFS= read -r line || line=''
exit 0
SHIM
chmod +x "$tmp/bin/claude"

# run <script> <args...>: against the fixture, the shim on PATH. Sets RC,
# OUT, ERR.
run() {
  r_script=$1
  shift
  OUT=$(cd "$repo" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_SKILLS_ROOT \
    -u PLANWRIGHT_CONFIG_DEFAULTS -u PLANWRIGHT_REPO_ROOT_CHECKED -u PLANWRIGHT_CONFIG_STRICT_OVERLAYS \
    -u XDG_CONFIG_HOME -u TMUX -u TMUX_PANE -u PLANWRIGHT_MC_CHECKED -u PLANWRIGHT_MC_PROGRAM \
    -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE -u PLANWRIGHT_TOWER_ID \
    PATH="$tmp/bin:$PATH" PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" PLANWRIGHT_LOCAL_CONFIG="$tmp/absent.yml" \
    CLAUDE_DIR="$tmp/claude" HOME="$fixhome" PLANWRIGHT_FLEET_STATE_DIR="$fleet" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT=off \
    /bin/bash "$repo_root/scripts/$r_script" "$@" 2>"${RUN_ERR:-$tmp/stderr}")
  RC=$?
  ERR=$(cat "${RUN_ERR:-$tmp/stderr}")
}
ho() { run mc-handover.sh "$@"; }
col() { printf '%s\n' "$OUT" | awk -F '\t' -v k="$1" -v c="$2" '$1 == k { print $c; exit }'; }
rowfile() { printf '%s\n' "$fleet/mission-control/sessions/$1"; }
# wait_done <name>: until the shim's supervisor has recorded the run's end.
wait_done() {
  n=0
  until [ -s "$fleet/streamjson/$1/result" ] || [ "$n" -ge 100 ]; do
    sleep 0.1
    n=$((n + 1))
  done
}
holder_is() { # holder_is <label> <handle> [<program>]
  ho holder --program "${3:-alpha}"
  if [ "$(col holder 2)" = "$2" ]; then ok "$1"; else fail "$1: the holder is '$(col holder 2)', not $2"; fi
}
events_of() { # events_of <kind> [<program>]: the program's events of that kind
  run mc-event.sh list --program "${2:-alpha}"
  printf '%s\n' "$OUT" | awk -F '\t' -v k="$1" '$3 == k'
}
count_of() { events_of "$@" | grep -c .; }

run mc-rules.sh add alpha --text "Never hand the operator a pane" --subject panes --source "operator, fixture" --date 2026-10-26
[ "$RC" = 0 ] || fail "fixture: the rule was not added: $ERR"
run mc-kb.sh init --program alpha
[ "$RC" = 0 ] || fail "fixture: the knowledge base was not initialised: $ERR"
run mc-rules.sh load alpha
digest=$(printf '%s\n' "$OUT" | sed -n 's/.*, digest \([0-9a-f]*\) -->.*/\1/p' | head -n 1)
[ "${#digest}" = 64 ] || fail "fixture: no rules digest from the load: $OUT"
printf '%s\n' "# Mission control" "" "Run program alpha." >"$tmp/brief.md"
printf '%s\n' "item q-1" "session mc-worker-1" >"$tmp/picture"
printf '%s\n' "item q-1" >"$tmp/picture-short"
: >"$tmp/empty"

# ---------------------------------------------------------------------------
# REQ-L1.3, REQ-L1.5: each trigger source fires from its fixture; the
# compaction ceiling fires whatever the other two read.
# ---------------------------------------------------------------------------
ho due --program alpha --context 70 --wakes 0 --compactions 0
[ "$OUT" = "due${tab}context at 70%" ] && ok "context at the threshold triggers the handover" || fail "context at 70: $OUT $ERR"
ho due --program alpha --context 69 --wakes 999 --compactions 0
[ "$OUT" = not-due ] && ok "a context reading below the threshold is not due, whatever the wakes" || fail "context at 69: $OUT"
ho due --program alpha --context - --wakes 150 --compactions 0
[ "$OUT" = "due${tab}150 wakes" ] && ok "with no context reading the wake count triggers it" || fail "150 wakes: $OUT $ERR"
ho due --program alpha --context - --wakes 149 --compactions 1
[ "$OUT" = not-due ] && ok "below every threshold it is not due" || fail "149 wakes: $OUT"
ho due --program alpha --context 5 --wakes 0 --compactions 2
[ "$OUT" = "due${tab}2 compactions" ] && ok "the compaction ceiling fires regardless of the other two" || fail "2 compactions: $OUT"

# ---------------------------------------------------------------------------
# A first start: no holder, so a plain launch runs and takes the name.
# ---------------------------------------------------------------------------
ho launch --program alpha --brief "$tmp/brief.md"
[ "$RC" = 0 ] || fail "the first launch exited $RC: $ERR"
n1=$(col successor 2)
wait_done "$n1"
grep -qF 'Run program alpha.' "$fleet/mission-control/launch/$n1/brief.md" \
  && grep -qF 'no handover file' "$fleet/mission-control/launch/$n1/brief.md" \
  && ok "the successor's brief carries the brief and its succession note" \
  || fail "the composed brief lacks the brief or the note"
ho verify --program alpha --session "$n1" --picture "$tmp/picture" --digest "$digest" --ledger - --durable "$tmp/picture"
[ "$RC" = 0 ] && ok "a first start verifies against the durable picture" || fail "the first verify exited $RC: $OUT $ERR"
ho take --program alpha --session "$n1" --window 1s
[ "$(col took 2)" = "$n1" ] && [ "$(col took 3)" = - ] && ok "the first start takes the name from nobody" || fail "the first take: $RC $OUT $ERR"
holder_is "the name resolves to the first session" "$n1"

# ---------------------------------------------------------------------------
# REQ-A1.1: a launch with neither the ask nor a live handover refuses,
# naming the holder.
# ---------------------------------------------------------------------------
ho launch --program alpha --brief "$tmp/brief.md"
[ "$RC" = 3 ] && ok "a second unattended start is refused (exit 3)" || fail "a second start exited $RC: $OUT"
case $ERR in *"held by $n1"*) ok "the refusal names the holder" ;; *) fail "the refusal does not name $n1: $ERR" ;; esac
ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 3 ] && ok "a handover launch with no handover file is refused" || fail "a fileless handover exited $RC"
case $ERR in *"$n1"*) ok "that refusal names the holder too" ;; *) fail "the fileless refusal does not name $n1: $ERR" ;; esac
ho write --program alpha --session mc-not-holder --picture "$tmp/picture" --digest "$digest"
[ "$RC" = 1 ] && ok "only the holder writes the handover file" || fail "a non-holder's write exited $RC"

# ---------------------------------------------------------------------------
# REQ-L1.6: the handover file carries its format; a successor refuses one
# whose format it does not know; a failed self-check keeps the predecessor.
# ---------------------------------------------------------------------------
run mc-kb.sh append decisions --program alpha --subject fixture --act "merged nothing" --no-reversal
led1=$(printf '%s\n' "$OUT" | head -n 1)
ho write --program alpha --session "$n1" --picture "$tmp/picture" --digest "$digest"
[ "$RC" = 0 ] || fail "the holder's write exited $RC: $ERR"
hf="$home/handover.tsv"
[ "$(head -n 1 "$hf")" = "format${tab}1" ] && ok "the handover file opens with its format field" || fail "the file opens with '$(head -n 1 "$hf")'"
grep -qx "ledger${tab}$led1" "$hf" && grep -qx "predecessor${tab}$n1" "$hf" && grep -qx "item${tab}q-1" "$hf" \
  && grep -qx "session${tab}mc-worker-1" "$hf" \
  && ok "it records the last ledger sequence, the predecessor, the open items and the live sessions" || fail "the file is incomplete: $(cat "$hf")"
ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 0 ] || fail "the handover launch exited $RC: $ERR"
grep -qF "the handover file is $hf" "$fleet/mission-control/launch/$(col successor 2)/brief.md" \
  && ok "the successor's brief names the handover file" || fail "the successor's brief lacks the handover file's path"
n2=$(col successor 2)
wait_done "$n2"
[ "$n2" != "$n1" ] && ok "the successor has a name of its own" || fail "the successor reused $n1"
ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 3 ] && ok "a second successor is refused while one is pending" || fail "a second successor exited $RC"

cp "$hf" "$tmp/hf.keep"
{
  printf 'format\t9\n'
  tail -n +2 "$tmp/hf.keep"
} >"$hf"
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest" --ledger "$led1"
[ "$RC" = 1 ] && ok "a handover file of an unknown format is refused" || fail "the unknown format exited $RC"
case $OUT in *"format field is 9"*) ok "the refusal names the format field" ;; *) fail "the refusal does not name the format: $OUT" ;; esac
cp "$tmp/hf.keep" "$hf"

before=$(count_of handover-failed)
ho verify --program alpha --session "$n2" --picture "$tmp/picture-short" --digest "$digest" --ledger "$led1"
[ "$RC" = 1 ] && ok "a self-check missing a live session fails" || fail "the short picture exited $RC: $OUT"
case $OUT in "item${tab}"*mc-worker-1*) ok "it prints the item naming what is missing" ;; *) fail "no item line names the session: $OUT" ;; esac
[ "$(count_of handover-failed)" = $((before + 1)) ] && ok "the failed self-check raises one operator item" || fail "the self-check failure raised no item"
other=$(printf '%064d' 0)
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$other" --ledger "$led1"
[ "$RC" = 1 ] && ok "rules that are not the predecessor's fail the self-check" || fail "the digest mismatch exited $RC"
case $OUT in "item${tab}handover${tab}rules${tab}"*) ok "the item names the rules" ;; *) fail "no rules item: $OUT" ;; esac
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest" --ledger -
[ "$RC" = 1 ] && ok "a ledger position behind the predecessor's last entry fails" || fail "the stale ledger exited $RC"
case $OUT in "item${tab}handover${tab}ledger${tab}"*) ok "the item names the ledger" ;; *) fail "no ledger item: $OUT" ;; esac
ho take --program alpha --session "$n2" --window 1s
[ "$RC" = 1 ] && ok "an unverified successor cannot take the name" || fail "an unverified take exited $RC"
holder_is "after the failed self-check the predecessor keeps the name" "$n1"
[ -f "$(rowfile "$n1")" ] && ok "and its registry row stays" || fail "the predecessor's row went"

# ---------------------------------------------------------------------------
# REQ-L1.6, REQ-A1.1: the predecessor releases after the successor's pass;
# the name moves, the predecessor's row goes, the successor announces.
# ---------------------------------------------------------------------------
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest" --ledger "$led1"
[ "$RC" = 0 ] && ok "the successor's self-check matches the handover file" || fail "the matching verify exited $RC: $OUT $ERR"
ho release --program alpha --session "$n1"
[ "$RC" = 0 ] && [ "$(col released 3)" = "$n2" ] && ok "the predecessor releases the name to the verified successor" || fail "release: $RC $OUT $ERR"
ho take --program alpha --session "$n2" --window 5s
[ "$RC" = 0 ] || fail "the take exited $RC: $OUT $ERR"
[ "$(col took 4)" = released ] && ok "the successor takes the name on the release" || fail "the take did not see the release: $OUT"
[ "$(col retire 3)" = released ] && [ ! -f "$(rowfile "$n1")" ] && ok "the predecessor's registry row is gone" || fail "the predecessor was not retired: $OUT"
[ -n "$(col line 2)" ] && [ "$(printf '%s\n' "$OUT" | grep -c "^line$tab")" = 1 ] && ok "the operator sees one line" || fail "not one line: $OUT"
holder_is "the name resolves to the successor only" "$n2"
[ -n "$(events_of mission-control-announce)" ] && ok "the successor announces itself" || fail "no announce event"
[ ! -f "$hf" ] && ok "the consumed handover file is gone" || fail "the handover file outlived the take"

# A file naming a predecessor already retired authorises nothing.
cp "$tmp/hf.keep" "$hf"
ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 3 ] && ok "a handover file naming a retired predecessor is refused" || fail "the stale file exited $RC"
case $ERR in *"held by $n2"*) ok "that refusal names the holder" ;; *) fail "the stale-file refusal does not name $n2: $ERR" ;; esac
rm -f "$hf"

# ---------------------------------------------------------------------------
# REQ-A1.7: a predecessor that cannot release within the window is retired
# by the successor.
# ---------------------------------------------------------------------------
ho write --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest"
ho launch --program alpha --brief "$tmp/brief.md" --handover
n3=$(col successor 2)
wait_done "$n3"
ho verify --program alpha --session "$n3" --picture "$tmp/picture" --digest "$digest" --ledger "$led1"
[ "$RC" = 0 ] || fail "the third verify exited $RC: $OUT $ERR"
[ -f "$(rowfile "$n2")" ] || fail "fixture: the predecessor's row is missing before the hung take"
before=$(count_of handover-requested)
ho take --program alpha --session "$n3" --window 1s
[ "$RC" = 0 ] && [ "$(col took 4)" = retired ] && ok "a predecessor silent past the window is retired" || fail "the hung take: $RC $OUT $ERR"
[ "$(col retire 3)" = released ] && ok "the launcher retired it" || fail "the hung predecessor's retire line: $OUT"
[ "$(count_of handover-requested)" = $((before + 1)) ] && ok "the take asked the live predecessor to release" || fail "no handover-requested event for the take"
[ ! -f "$(rowfile "$n2")" ] && ok "the hung predecessor's row is gone" || fail "the hung predecessor's row stayed"
holder_is "the name resolves to the successor" "$n3"

# ---------------------------------------------------------------------------
# REQ-A1.7: resume by name in the operator's session: what changed since the
# last operator turn, an announcement to every live session, the holder
# releasing on request.
# ---------------------------------------------------------------------------
run mission-control-launch.sh launch --program alpha --kind worker --scope fixture-worker --brief "$tmp/brief.md"
[ "$RC" = 0 ] || fail "fixture: the worker did not launch: $ERR"
worker=$(printf '%s\n' "$OUT" | awk -F '\t' '$2 == "name" { print $3 }')
wait_done "$worker"
run mc-kb.sh append decisions --program alpha --subject "before the last turn" --act "held a branch" --no-reversal
sleep 1
run mc-panel.sh presence --program alpha --prompt --now "$(date +%s)"
[ "$RC" = 0 ] || fail "fixture: the presence marker was not written: $ERR"
sleep 1
run mc-kb.sh append decisions --program alpha --subject "after the last turn" --act "retargeted a branch" --no-reversal
ho resume --program alpha --session operator-term --picture "$tmp/picture-short" --digest "$digest" --durable "$tmp/picture"
[ "$RC" = 1 ] && ok "a resume whose self-check fails is refused" || fail "the failing resume exited $RC"
holder_is "and the name stays where it was" "$n3"
(
  n=0
  until [ -f "$fleet/mission-control/alpha/release-request" ] || [ "$n" -ge 100 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  RUN_ERR="$tmp/stderr-helper" run mc-handover.sh release --program alpha --session "$n3"
) &
helper=$!
ho resume --program alpha --session operator-term --picture "$tmp/picture" --digest "$digest" --durable "$tmp/picture" --window 10s
wait "$helper"
[ "$RC" = 0 ] || fail "the resume exited $RC: $OUT $ERR"
[ "$(col took 3)" = "$n3" ] && [ "$(col took 4)" = released ] && ok "the holder releases the name on the resume's request" || fail "the resume did not see the release: $OUT"
[ ! -f "$(rowfile "$n3")" ] && ok "the released holder's row is gone" || fail "the released holder's row stayed"
case $OUT in *"changed${tab}decision${tab}"*"after the last turn${tab}retargeted a branch"*) ok "the resume reports what changed since the last turn" ;; *) fail "no change reported: $OUT" ;; esac
case $OUT in *"held a branch"* | *"merged nothing"*) fail "a decision before the last turn was reported as changed" ;; *) ok "a decision before the last turn is not reported" ;; esac
case $OUT in *"announce${tab}$worker"*) ok "it announces itself to every live session" ;; *) fail "the worker was not announced to: $OUT" ;; esac
[ -n "$(events_of handover-requested)" ] && ok "the request reached the holder as an event" || fail "no handover-requested event"
holder_is "the name resolves to the operator's session" operator-term
# A session without the mod writes no lease, so nothing proves it gone.
ho holder --program alpha
[ "$(col holder 6)" = live ] && ok "an attended holder with no lease counts as live" || fail "the leaseless holder: $OUT"
ho launch --program alpha --brief "$tmp/brief.md"
[ "$RC" = 3 ] && ok "so a plain launch over it is refused" || fail "a launch over the leaseless holder exited $RC"
mkdir -p "$fleet/mission-control/alpha/leases"
printf "%s\n" "$(($(date +%s) - 600))" >"$fleet/mission-control/alpha/leases/operator-term"
ho holder --program alpha
[ "$(col holder 6)" = stale ] && ok "a lease older than the bound makes it stale" || fail "the old lease: $OUT"

# ---------------------------------------------------------------------------
# REQ-L1.6: where the holder is the operator's own session the
# harness cannot swap it, so the handover is one operator act on the panel.
# ---------------------------------------------------------------------------
printf "%s\n" "$(date +%s)" >"$fleet/mission-control/alpha/leases/operator-term"
ho path --program alpha
[ "$(col path 2)" = operator-act ] && ok "an attended holder's path is the operator's act" || fail "path: $OUT $ERR"
ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 4 ] && ok "no successor is launched over an attended holder" || fail "a launch over the attended holder exited $RC"
ho offer --program alpha
[ "$RC" = 0 ] && [ -n "$(events_of handover-act)" ] && ok "the act is offered as an operator item" || fail "offer: $RC $OUT $ERR"

# A record's handles reach paths and the launcher, so one outside the
# grammar is refused, never followed.
printf 'format\t1\nsession\tmc-x\npredecessor\t../../escape\npredecessor-kind\tregistry\nlaunched\t1\nmode\thandover\nverified\t1\n' \
  >"$fleet/mission-control/alpha/successor"
ho take --program alpha --session mc-x --window 1s
[ "$RC" = 1 ] && ok "a successor record naming a handle outside the grammar is refused" || fail "the tampered record's take exited $RC: $OUT"
holder_is "and the name stays put" operator-term

# ---------------------------------------------------------------------------
# A second program: recovery and edge paths.
# ---------------------------------------------------------------------------
run mc-kb.sh init --program beta
run mc-rules.sh load beta
bdigest=$(printf '%s\n' "$OUT" | sed -n 's/.*, digest \([0-9a-f]*\) -->.*/\1/p' | head -n 1)
[ "${#bdigest}" = 64 ] || fail "fixture: no rules digest for beta: $OUT"
printf '%s\n' "item b-1" >"$tmp/bpic"
bhf="$bhome/handover.tsv"
ho holder --program beta
[ "$OUT" = "holder${tab}-" ] && ok "a program nobody holds says so" || fail "the empty holder: $OUT"
ho launch --program beta --brief "$tmp/brief.md"
b1=$(col successor 2)
wait_done "$b1"
ho verify --program beta --session "$b1" --picture "$tmp/bpic" --digest "$bdigest" --ledger - --durable "$tmp/bpic"
ho take --program beta --session "$b1" --window 1s
holder_is "fixture: beta's first session holds its name" "$b1" beta
ho path --program beta
[ "$OUT" = "path${tab}unattended" ] && ok "a launched holder hands over unattended" || fail "path: $OUT"

run mc-kb.sh append decisions --program beta --subject fixture --act "noted" --no-reversal
bled=$(printf '%s\n' "$OUT" | head -n 1)
# A decisions log that cannot be read is never written down as no ledger.
if [ "$(id -u)" != 0 ]; then
  for seg in "$bhome"/kb/decisions-*.log; do chmod 000 "$seg"; done
  ho write --program beta --session "$b1" --picture "$tmp/bpic" --digest "$bdigest"
  [ "$RC" != 0 ] && [ ! -f "$bhf" ] && ok "an unreadable ledger fails the write" || fail "the write over an unreadable ledger exited $RC"
  for seg in "$bhome"/kb/decisions-*.log; do chmod 600 "$seg"; done
fi
# A relative picture shaped like an awk assignment is still read as a file.
printf '%s\n' "item b-1" >"$repo/item=a"
OUT=$(printf '%s\n' "item injected" | {
  ho write --program beta --session "$b1" --picture item=a --digest "$bdigest"
  printf '%s\n' "$RC"
})
grep -qx "item${tab}b-1" "$bhf" && ! grep -q injected "$bhf" && ok "the picture is read from its file, never stdin" || fail "the picture was not read from its file: $(cat "$bhf")"
rm -f "$repo/item=a"

# A predecessor that died after writing its handover file: the successor
# verifies against that file and takes the name without waiting.
run mission-control-launch.sh retire "$b1"
ho holder --program beta
[ "$(col holder 6)" = stale ] && ok "a holder whose row is gone is stale" || fail "the dead holder: $OUT"
ho launch --program beta --brief "$tmp/brief.md" --handover
b2=$(col successor 2)
wait_done "$b2"
ho verify --program beta --session "$b2" --picture "$tmp/bpic" --digest "$bdigest" --ledger "$bled"
[ "$RC" = 0 ] && ok "the successor of a dead predecessor verifies against its file" || fail "the dead predecessor's successor: $RC $OUT $ERR"
t0=$(date +%s)
ho take --program beta --session "$b2" --window 30s
[ "$RC" = 0 ] && [ "$(col took 4)" = retired ] && [ "$(col retire 3)" = gone ] && ok "it takes the name from the dead predecessor" || fail "the take from the dead predecessor: $RC $OUT"
[ $(($(date +%s) - t0)) -lt 10 ] && ok "without waiting out the window" || fail "the take waited for a predecessor already gone"

# A release made to one successor never lets another take the name.
ho write --program beta --session "$b2" --picture "$tmp/bpic" --digest "$bdigest"
ho launch --program beta --brief "$tmp/brief.md" --handover
b3=$(col successor 2)
wait_done "$b3"
ho verify --program beta --session "$b3" --picture "$tmp/bpic" --digest "$bdigest" --ledger "$bled"
ho release --program beta --session "$b2"
[ "$(col released 3)" = "$b3" ] || fail "fixture: the release did not name $b3: $OUT $ERR"
run mission-control-launch.sh retire "$b3"
ho launch --program beta --brief "$tmp/brief.md" --handover
b4=$(col successor 2)
wait_done "$b4"
ho verify --program beta --session "$b4" --picture "$tmp/bpic" --digest "$bdigest" --ledger "$bled"
ho take --program beta --session "$b4" --window 1s
[ "$RC" = 0 ] && [ "$(col took 4)" = retired ] && ok "a release to another successor does not count as this one's" || fail "the misdirected release: $RC $OUT"

# REQ-A1.1: the operator-asked launch against a live holder ends with one
# holder, the successor; with no handover file its ledger is checked
# against the log.
ho launch --program beta --brief "$tmp/brief.md" --asked
[ "$RC" = 0 ] && ok "the operator's ask launches over a live holder" || fail "the asked launch exited $RC: $ERR"
b5=$(col successor 2)
wait_done "$b5"
ho verify --program beta --session "$b5" --picture "$tmp/bpic" --digest "$bdigest" --ledger - --durable "$tmp/bpic"
[ "$RC" = 1 ] && ok "a ledger behind the log fails a durable self-check" || fail "the durable stale ledger exited $RC"
ho verify --program beta --session "$b5" --picture "$tmp/bpic" --digest "$bdigest" --ledger "$bled" --durable "$tmp/bpic"
[ "$RC" = 0 ] || fail "the asked successor's verify exited $RC: $OUT $ERR"
ho take --program beta --session "$b5" --window 1s
[ "$RC" = 0 ] && [ ! -f "$(rowfile "$b4")" ] && ok "the asked successor ends as the one holder" || fail "the asked take: $RC $OUT"
holder_is "the name resolves to the asked successor" "$b5" beta

# A resume while a successor is pending retires the stranded successor.
ho launch --program beta --brief "$tmp/brief.md" --asked
b6=$(col successor 2)
wait_done "$b6"
ho resume --program beta --session operator-b --picture "$tmp/bpic" --digest "$bdigest" --durable "$tmp/bpic" --window 1s
[ "$RC" = 0 ] || fail "the resume over a pending successor exited $RC: $OUT $ERR"
case $OUT in *"retire${tab}$b6${tab}released"*) ok "the stranded successor is retired" ;; *) fail "the stranded successor was not retired: $OUT" ;; esac
[ ! -f "$(rowfile "$b6")" ] && ok "and its row is gone" || fail "the stranded successor's row stayed"

ho release --program beta --session mc-nobody
[ "$RC" = 1 ] && ok "a session that does not hold the name cannot release it" || fail "a non-holder's release exited $RC"
ho release --program beta --session operator-b
[ "$RC" = 1 ] && ok "a release with no successor or request is refused" || fail "the orphan release exited $RC"
ho resume --program beta --session mc-unregistered --kind registry --picture "$tmp/bpic" --digest "$bdigest" --durable "$tmp/bpic"
[ "$RC" = 1 ] && ok "a registry resume needs the session's row" || fail "the rowless registry resume exited $RC"

for c in "take --program beta --session operator-b --window bogus" \
  "launch --program beta --brief $tmp/brief.md --backend nowhere" \
  "due --program beta --context x --wakes 0 --compactions 0" \
  "verify --program beta --session operator-b --picture $tmp/bpic --digest abc --ledger -" \
  "frobnicate --program beta"; do
  # shellcheck disable=SC2086 # each case is a word list on purpose
  ho $c
  [ "$RC" = 2 ] && ok "usage: $c (exit 2)" || fail "usage: $c exited $RC"
done
ho holder --program gamma
[ "$RC" = 3 ] && ok "a program that is not configured exits 3" || fail "the unconfigured program exited $RC"

cp "$tracked" "$tmp/tracked.keep"
printf '%s\n' "mission_control_handover_context: 50" >>"$tracked"
ho due --program beta --context 50 --wakes 0 --compactions 0
[ "$OUT" = "due${tab}context at 50%" ] && ok "the context threshold is the knob's" || fail "the knob was not read: $OUT $ERR"
cp "$tmp/tracked.keep" "$tracked"

echo
if [ "$failures" -gt 0 ]; then
  echo "test-mc-handover: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-handover: all passed"
