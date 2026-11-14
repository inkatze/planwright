#!/bin/bash
# Tests for `fleet-streamjson.sh recover` keeping a mission control worker's
# owner: the launcher's registry row and the dispatch record's owner survive
# a recover run by anyone, a missing row is rebuilt from the launch's own
# state, and a worker no program can place is raised once, to the hub.
#
#   o1: a recovered worker keeps its row, program and owner, whoever runs the
#       recover, and its dispatch record still names the owning program.
#   o2: its pending-prompt event reaches the owning program's keeper only.
#   o3: a missing row is rebuilt from the launch directory and the state the
#       worker kept, and the rebuilt row routes like the original.
#   o4: with neither row nor launch directory, the dispatch record's owner
#       stands and nothing is raised.
#   o5: a worker nothing places is raised once as unowned, to the hub.
#   o6: a worker no mission control launched recovers as before: no row
#       invented, nothing raised.
#
# Hermetic: fleet home, repository and CLI are case-local; the CLI is a shim.
# Runs under bash 3.2.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
SJ="$repo_root/scripts/fleet-streamjson.sh"
# shellcheck source=tests/lib/fixture-procs.sh
. "$here/lib/fixture-procs.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required" >&2
  exit 1
}

tmp=$(fixture_scratch) || {
  echo "FAIL: no scratch directory" >&2
  exit 1
}
tmp=$(cd -P -- "$tmp" && pwd -P) || exit 1
cleanup() {
  trap '' INT TERM
  trap - EXIT
  fixture_is_owner || return 0
  fixture_reap "$tmp/"
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
cat >"$tracked" <<EOF
mission_control_programs: [alpha, beta, hub]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo/specs
program_alpha_home: $tmp/mchome-alpha
program_alpha_budget: {host_load: 1000000}
program_beta_repositories: [$repo]
program_beta_spec_root: $repo/specs
program_beta_home: $tmp/mchome-beta
program_beta_budget: {host_load: 1000000}
program_hub_repositories: [$repo]
program_hub_spec_root: $repo/specs
program_hub_home: $tmp/mchome-hub
program_hub_budget: {host_load: 1000000}
mission_control_escalation_hub: hub
EOF

cp "$repo_root/config/worker-settings.json" "$core/config/worker-settings.json" || exit 1
sid='11111111-2222-3333-4444-555555555555'
rec="$tmp/rec"
mkdir -p "$tmp/bin" "$rec"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
printf '%s\n' "$*" >>"$SHIM_RECORD_DIR/argv"
printf '{"type":"system","subtype":"init","cwd":"/x","session_id":"%s","tools":[]}\n' "$SHIM_SID"
(sleep "${SHIM_WATCHDOG:-120}" && kill "$$" 2>/dev/null) &
while IFS= read -r line; do :; done
SHIM
chmod +x "$tmp/bin/claude"
printf 'begin\n' >"$tmp/prompt"

# sj <env assignment>... -- <args>: the supervisor under the fixture, with the
# given identity variables on top.
sj() {
  sj_extra=''
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
    sj_extra="$sj_extra $1"
    shift
  done
  shift
  # shellcheck disable=SC2086 # a word list of NAME=value pairs
  (
    mc_env env -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID -u PLANWRIGHT_TOWER_PID \
      $sj_extra \
      PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT=off \
      SHIM_RECORD_DIR="$rec" SHIM_SID="$sid" \
      /bin/sh "$SJ" "$@"
  )
}

rows="$fleet/mission-control/sessions"
launches="$fleet/mission-control/launch"

# nm <program> <kind> <scope>: the name the launcher derives, which restore
# checks a launch directory's provenance line against.
nm() { (mc_env /bin/sh "$repo_root/scripts/mission-control-launch.sh" name --program "$1" --kind "$2" --scope "$3"); }

# launched <name> <owner-or-empty> [<program> <kind> <scope>]: launch the worker as
# its mission control would, then stop it so a recover is what resumes it;
# with a program, the launcher's row and launch directory are written the way
# the launcher writes them.
launched() {
  l_name=$1
  l_owner=$2
  if [ -n "$l_owner" ]; then
    sj "PLANWRIGHT_TOWER_ID=$l_owner" -- launch "$l_name" demo:task-1 --prompt-file "$tmp/prompt" --cwd "$repo" >/dev/null \
      || fail "setup: the launch of $l_name exited non-zero"
  else
    sj -- launch "$l_name" demo:task-1 --prompt-file "$tmp/prompt" --cwd "$repo" >/dev/null \
      || fail "setup: the launch of $l_name exited non-zero"
  fi
  poll_until --what "the persisted session of $l_name" -- test -s "$fleet/streamjson/$l_name/session" \
    || fail "setup: $l_name never persisted its session"
  if [ -n "${3:-}" ]; then
    mkdir -p "$rows" "$launches/$l_name"
    printf 'format\t1\nname\t%s\nstate\tlaunched\ntoken\t1-abc\npid\t1\nprogram\t%s\nowner\tmission-control:%s\nkind\t%s\nscope\t%s\nbackend\tstream-json\nhandle\t%s\nprofile\tworker\ntier\t-\nreserved\t-\nbrief\t%s\ncwd\t%s\ntask\t-\nprimary\t-\nmarker\t-\nlaunched\t1\n' \
      "$l_name" "$3" "$3" "$4" "$5" "$l_name" "$launches/$l_name/brief.md" "$repo" >"$rows/$l_name"
    printf '<!-- mission-control launch: %s (kind %s, scope %s, program %s) -->\n' "$l_name" "$4" "$5" "$3" >"$launches/$l_name/brief.md"
  fi
  sj -- stop "$l_name" --grace 2 >/dev/null 2>&1
}

# owner_of <handle>: the owner column of the handle's last dispatch record.
owner_of() {
  mc_env /bin/sh "$repo_root/scripts/fleet-state.sh" registry \
    | awk -F '\t' -v h="$1" '$2 == h { o = $4 } END { print o }'
}

# recovered <name> [<env assignment>...]: recover the stopped worker.
recovered() {
  rc_name=$1
  shift
  RC=0
  ERR=$(sj "$@" -- recover "$rc_name" --cwd "$repo" 2>&1 >/dev/null) || RC=$?
  [ "$RC" -eq 0 ] || fail "recover $rc_name exited $RC: $ERR"
  sj -- stop "$rc_name" --grace 2 >/dev/null 2>&1
}

# pending <name> <received>: a request pending in the worker's journal.
pending() {
  printf 'cccc3333-bbbb-cccc-dddd-eeee00000001\tpermission\t%s\tpending\n' "$2" >"$fleet/streamjson/$1/journal"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/supervisor.pid"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/worker.pid"
}

# watch <program>: that program's keeper watch pass, stdout.
watch() {
  mc_env env PLANWRIGHT_MC_PROGRAM="$1" PLANWRIGHT_STREAMJSON_PENDING_AGE=900 \
    /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 5010 2>/dev/null
}

# ---------------------------------------------------------------------------
# o1, o2: the row, program and owner survive a recover run by another program's
# mission control, and the prompt reaches the owner's keeper only.
# ---------------------------------------------------------------------------
w1=$(nm alpha worker s1)
launched "$w1" mission-control:alpha alpha worker s1
before=$(cksum <"$rows/$w1")
recovered "$w1" PLANWRIGHT_TOWER_ID=mission-control:beta
[ "$(cksum <"$rows/$w1")" = "$before" ] && ok "o1: the recovered worker's registry row is untouched" \
  || fail "o1: the recover rewrote the registry row"
[ "$(awk -F '\t' '$1 == "program" { print $2 }' "$rows/$w1")" = alpha ] \
  && ok "o1: the row still names its program" || fail "o1: the row lost its program"
[ "$(owner_of "$w1")" = mission-control:alpha ] \
  && ok "o1: the dispatch record still names the launching mission control, not the caller" \
  || fail "o1: the dispatch record's owner is '$(owner_of "$w1")'"
recovered "$w1"
[ "$(owner_of "$w1")" = mission-control:alpha ] \
  && ok "o1: a recover from a shell with no identity keeps the owner too" \
  || fail "o1: an identity-less recover left owner '$(owner_of "$w1")'"
pending "$w1" 5000
a_out=$(watch alpha)
b_out=$(watch beta)
case $a_out in *"announced${tab}pending-prompt${tab}$w1"*) ok "o2: the owning program's keeper announces the recovered worker's prompt" ;; *) fail "o2: the owner heard nothing: $a_out" ;; esac
case $b_out in *"$w1"*) fail "o2: another program's keeper announced the prompt: $b_out" ;; *) ok "o2: no other program's keeper announces it" ;; esac

# ---------------------------------------------------------------------------
# o3: a missing row is rebuilt from the launch directory.
# ---------------------------------------------------------------------------
w3=$(nm alpha worker s3)
launched "$w3" mission-control:alpha alpha worker s3
rm -f "$rows/$w3"
recovered "$w3" PLANWRIGHT_TOWER_ID=mission-control:beta
if [ -f "$rows/$w3" ]; then
  ok "o3: the missing row is back"
else
  fail "o3: the recover left no registry row"
fi
for kv in 'program alpha' 'owner mission-control:alpha' 'kind worker' 'scope s3' 'backend stream-json' 'format 1' "name $w3"; do
  [ "$(awk -F '\t' -v k="${kv%% *}" '$1 == k { print $2 }' "$rows/$w3" 2>/dev/null)" = "${kv#* }" ] \
    || fail "o3: the rebuilt row's ${kv%% *} is not ${kv#* }"
done
[ "$(owner_of "$w3")" = mission-control:alpha ] && ok "o3: its dispatch record names the launching mission control" \
  || fail "o3: the dispatch record's owner is '$(owner_of "$w3")'"
list=$(mc_env /bin/sh "$repo_root/scripts/mission-control-launch.sh" list)
case $list in *"$w3${tab}alpha${tab}worker"*) ok "o3: the launcher lists the rebuilt row under its program" ;; *) fail "o3: the launcher's list: $list" ;; esac
for kv in 'state launched' "cwd $repo" "handle $w3" 'profile worker'; do
  [ "$(awk -F '\t' -v k="${kv%% *}" '$1 == k { print $2 }' "$rows/$w3")" = "${kv#* }" ] \
    || fail "o3: the rebuilt row's ${kv%% *} is not ${kv#* }"
done
pending "$w3" 5000
a_out=$(watch alpha)
case $a_out in *"announced${tab}pending-prompt${tab}$w3"*) ok "o3: the rebuilt row's program hears the prompt" ;; *) fail "o3: the owner heard nothing: $a_out" ;; esac
b_out=$(watch beta)
case $b_out in *"$w3"*) fail "o3: another program's keeper announced the rebuilt worker: $b_out" ;; *) ok "o3: the rebuilt row keeps the prompt from every other program" ;; esac

# ---------------------------------------------------------------------------
# o4: no row and no launch directory: the dispatch record's owner stands.
# ---------------------------------------------------------------------------
w4=mc-alpha-worker-0000000004
launched "$w4" mission-control:alpha
recovered "$w4" PLANWRIGHT_TOWER_ID=mission-control:beta
[ "$(owner_of "$w4")" = mission-control:alpha ] && ok "o4: the dispatch record's owner survives a recover that has no row to read" \
  || fail "o4: the dispatch record's owner is '$(owner_of "$w4")'"
hub_events=$(mc_env /bin/bash "$repo_root/scripts/mc-event.sh" list --program hub)
case $hub_events in *"$w4"*) fail "o4: a placed worker was raised as unowned: $hub_events" ;; *) ok "o4: nothing is raised for a worker the record places" ;; esac

# ---------------------------------------------------------------------------
# o5: nothing places the worker: raised once, to the hub.
# ---------------------------------------------------------------------------
w5=mc-alpha-worker-0000000005
launched "$w5" ''
recovered "$w5"
recovered "$w5"
hub_events=$(mc_env /bin/bash "$repo_root/scripts/mc-event.sh" list --program hub)
n=$(printf '%s\n' "$hub_events" | awk -F '\t' -v w="$w5" 'index($0, w) { n++ } END { print n + 0 }')
[ "$n" -eq 1 ] && ok "o5: a worker nothing places is raised to the hub exactly once across two recovers" \
  || fail "o5: the hub heard of $w5 $n times: $hub_events"
case $hub_events in *unowned*) ok "o5: the event says the worker is unowned" ;; *) fail "o5: the event does not say unowned: $hub_events" ;; esac
alpha_events=$(mc_env /bin/bash "$repo_root/scripts/mc-event.sh" list --program alpha)
case $alpha_events in *"$w5"*) fail "o5: the unowned worker was raised to a program: $alpha_events" ;; *) ok "o5: no other program is told" ;; esac
[ ! -e "$rows/$w5" ] && ok "o5: no row is invented for it" || fail "o5: a row was invented for the unowned worker"

# A caller's own identity is not an unplaced worker's owner.
w7=mc-alpha-worker-0000000007
launched "$w7" ''
recovered "$w7" PLANWRIGHT_TOWER_ID=mission-control:beta
[ "$(owner_of "$w7")" != mission-control:beta ] && ok "o5: an unplaced worker is not registered under the identity of whoever ran the recover" \
  || fail "o5: the unplaced worker was registered to the caller"

# restore, driven directly: what it refuses and what it leaves alone.
restore() { (mc_env /bin/sh "$repo_root/scripts/mission-control-launch.sh" restore "$@" 2>"$tmp/restore.err"); }
restore not-a-session >/dev/null
[ $? -eq 2 ] && ok "o7: restore refuses a name that is not a session name" || fail "o7: a bad name was not refused"
out=$(restore mc-alpha-worker-0000000099)
[ $? -eq 4 ] && [ ! -e "$rows/mc-alpha-worker-0000000099" ] && ok "o7: with no row and no launch directory restore exits 4 and writes nothing" \
  || fail "o7: restore of an unknown session: $out"
out=$(restore "$w1")
[ "$out" = "present${tab}alpha${tab}mission-control:alpha" ] && ok "o7: a row that is there is reported, not rewritten" || fail "o7: restore of a present row printed: $out"
w8=$(nm alpha worker s8)
w9=$(nm alpha worker s9)
mkdir -p "$launches/$w8"
printf '<!-- mission-control launch: %s (kind worker, scope s9, program alpha) -->\n' "$w9" >"$launches/$w8/brief.md"
restore "$w8" >/dev/null
[ $? -eq 4 ] && [ ! -e "$rows/$w8" ] && ok "o7: a launch directory whose provenance names another session is not trusted" || fail "o7: a mismatched provenance line was accepted"
printf '<!-- mission-control launch: %s (kind worker, scope s8, program beta) -->\n' "$w8" >"$launches/$w8/brief.md"
restore "$w8" >/dev/null
[ $? -eq 4 ] && [ ! -e "$rows/$w8" ] && ok "o7: a provenance line whose program does not derive the name is not trusted" || fail "o7: a forged program was accepted"

# ---------------------------------------------------------------------------
# o6: a worker no mission control launched recovers as before.
# ---------------------------------------------------------------------------
w6=sjr-plain-6
launched "$w6" ''
recovered "$w6"
[ ! -e "$rows/$w6" ] && ok "o6: no row is invented for a worker no mission control launched" || fail "o6: a row appeared for $w6"
hub_events=$(mc_env /bin/bash "$repo_root/scripts/mc-event.sh" list --program hub)
case $hub_events in *"$w6"*) fail "o6: a non-mission-control worker was raised: $hub_events" ;; *) ok "o6: and nothing is raised for it" ;; esac

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
