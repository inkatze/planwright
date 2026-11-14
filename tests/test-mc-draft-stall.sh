#!/bin/bash
# Tests for scripts/mc-draft-stall.sh — the stalled-draft alarm: a draft pull
# request whose latest CI run on its current head ended cancelled, or sat
# unfinished past mission_control_stalled_draft_threshold, with no stated hold
# still applying, raises one draft-stalled event per head.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-draft-stall.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-draft-stall.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT
trap 'exit 143' HUP INT TERM

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
mchome="$tmp/mchome"
mkdir -p "$mchome"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_home: $mchome
program_alpha_sources: {code-state: forge:snapshot}
EOF

# A gh that answers from files in $tmp: a pull request read is a JSON file run
# through the program's own --jq filter, so the filter under test is the real one.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<EOF
#!/bin/bash
jqp=""
args=()
while [ \$# -gt 0 ]; do
  case \$1 in --jq) jqp=\$2; shift 2 ;; *) args+=("\$1"); shift ;; esac
done
case \${args[0]}:\${args[1]} in
  pr:view)
    f="$tmp/pr.\${args[2]}.json"
    [ -f "\$f" ] || { echo "gh: no such pull request" >&2; exit 1; }
    jq -r "\$jqp" <"\$f"
    ;;
  api:*)
    case \${args[1]} in
      repos/*/issues/*) f="$tmp/issue.\${args[1]##*/}.json" ;;
      repos/*/check-runs*) f="$tmp/window.json" ;;
      *) exit 1 ;;
    esac
    [ -f "\$f" ] || { echo "gh: not found" >&2; exit 1; }
    jq -r "\$jqp" <"\$f"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"

snapdir="$fleet/mission-control/alpha/snapshots"
mkdir -p "$snapdir"
runtime="$fleet/mission-control/alpha"
H=1111111111111111111111111111111111111111
H2=2222222222222222222222222222222222222222
T=1800000000
HOUR=3600
MIN=60
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>"$tmp/dateerr" || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; }

row() { # row <n> <head> <checks>
  printf 'pr\tacme/web\t%s\t%s\ttrue\tMERGEABLE\tNONE\t0\t%s\t0\t0\tp%s\n' "$1" "$2" "$3" "$1"
}
snapshot() { # snapshot <taken> then rows on stdin
  printf 'format\t1\nsource\tforge\ntaken\t%s\n' "$1"
  cat
}
put() { cat >"$tmp/rows"; snapshot "$1" <"$tmp/rows" >"$snapdir/forge"; }
run() { # run <now>: the snapshot is retaken each pass, as the runner keeps it fresh
  [ -n "${STALE:-}" ] || [ ! -f "$snapdir/forge" ] || snapshot "$1" <"$tmp/rows" >"$snapdir/forge"
  OUT=$(mc_env env PATH="$tmp/bin:$PATH" /bin/bash "$repo_root/scripts/mc-draft-stall.sh" watch --program alpha --now "$1" 2>"$tmp/stderr")
  RC=$?
  ERR=$(cat "$tmp/stderr")
}
events() { mc_env /bin/bash "$repo_root/scripts/mc-event.sh" list --program alpha 2>"$tmp/evtmp" | awk -F '\t' '$3 == "draft-stalled"'; }
nevents() { events | wc -l | tr -d ' '; }

# pr <n> <head> <body> <labels json> <runs json>: the forge's answer for a pull request.
pr() {
  jq -n --arg h "$2" --arg b "$3" --argjson l "$4" --argjson r "$5" \
    '{headRefOid: $h, baseRefName: "main", body: $b, labels: $l, statusCheckRollup: $r}' >"$tmp/pr.$1.json"
}
cancelled() { printf '[{"__typename":"CheckRun","name":"build","workflowName":"ci","status":"COMPLETED","conclusion":"CANCELLED","startedAt":"%s","completedAt":"%s"}]' "$(iso "$1")" "$(iso "$1")"; }
running() { printf '[{"__typename":"CheckRun","name":"build","workflowName":"ci","status":"IN_PROGRESS","conclusion":"","startedAt":"%s","completedAt":"0001-01-01T00:00:00Z"}]' "$(iso "$1")"; }
green() { printf '[{"__typename":"CheckRun","name":"build","workflowName":"ci","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"%s","completedAt":"%s"}]' "$(iso "$1")" "$(iso "$1")"; }

# --- a cancelled run with no hold raises once -------------------------------
pr 7 "$H" "A plain description." '[]' "$(cancelled $((T - HOUR)))"
row 7 "$H" FAILURE | put "$T"
run "$T"
expect_rc "a cancelled run" 0
expect_out "is raised" "raised${tab}draft-stalled${tab}1"
case $(events) in *"acme/web#7: the latest CI run was cancelled"*) ok "the event names the draft and why" ;; *) fail "no named event: $(events)" ;; esac
run $((T + 15 * MIN))
expect_eq "the same head is not raised again on the next pass" ""
run $((T + 10 * HOUR))
expect_eq "nor ever, while the head stands" ""
if [ "$(nevents)" = 1 ]; then ok "one event in all"; else fail "expected one event, got $(nevents)"; fi

# --- a new head resets it ---------------------------------------------------
pr 7 "$H2" "A plain description." '[]' "$(cancelled $((T + 11 * HOUR)))"
row 7 "$H2" FAILURE | put $((T + 12 * HOUR))
run $((T + 12 * HOUR))
expect_out "a new head that is cancelled too is raised afresh" "raised${tab}draft-stalled${tab}1"
if [ "$(nevents)" = 2 ]; then ok "two events in all"; else fail "expected two events, got $(nevents)"; fi

# --- a hold that still applies is not stalled -------------------------------
rm -f "$runtime"/draft-stall.tsv
pr 7 "$H" "Waiting on the release window." '[]' "$(cancelled "$T")"
printf '{"check_runs":[{"conclusion":"failure"}]}' >"$tmp/window.json"
row 7 "$H" FAILURE | put "$T"
run "$T"
expect_eq "a release window still open holds it" ""
printf '{"check_runs":[{"conclusion":"success"}]}' >"$tmp/window.json"
run $((T + 15 * MIN))
expect_out "the window closed: raised" "raised${tab}draft-stalled${tab}1"
case $(events) in *"hold cleared (the release window is closed)"*) ok "the event says the hold cleared" ;; *) fail "no cleared note: $(events)" ;; esac

rm -f "$runtime"/draft-stall.tsv
pr 7 "$H" "Plain." '[{"name":"on-hold"}]' "$(cancelled "$T")"
run $((T + HOUR))
expect_eq "a hold label still on it holds it" ""
pr 7 "$H" "Plain." '[{"name":"ci-macos"}]' "$(cancelled "$T")"
run $((T + HOUR + 15 * MIN))
expect_out "the hold label gone: raised" "raised${tab}draft-stalled${tab}1"

rm -f "$runtime"/draft-stall.tsv
pr 7 "$H" "Blocked by #50 until it lands." '[]' "$(cancelled "$T")"
printf '{"state":"open"}' >"$tmp/issue.50.json"
run $((T + 2 * HOUR))
expect_eq "a PR it waits on that is open holds it" ""
printf '{"state":"closed"}' >"$tmp/issue.50.json"
run $((T + 2 * HOUR + 15 * MIN))
expect_out "the PR it waits on merged: raised" "raised${tab}draft-stalled${tab}1"
case $(events) in *"acme/web#50 is closed or merged"*) ok "the cleared hold is named" ;; *) fail "hold not named: $(events)" ;; esac

rm -f "$runtime"/draft-stall.tsv "$tmp/issue.50.json"
run $((T + 3 * HOUR))
expect_eq "a hold that cannot be read still applies" ""
pr 7 "$H" "Hold: until I say so." '[]' "$(cancelled "$T")"
run $((T + 3 * HOUR + 15 * MIN))
expect_eq "a stated hold with nothing checkable still applies" ""

# --- unfinished and green runs ----------------------------------------------
rm -f "$runtime"/draft-stall.tsv
pr 8 "$H" "Plain." '[]' "$(running $((T - 10 * MIN)))"
row 8 "$H" PENDING | put "$T"
run "$T"
expect_eq "a run in progress under the threshold is not raised" ""
run $((T + 3 * HOUR - 11 * MIN))
expect_eq "still under the default 3h threshold" ""
run $((T + 3 * HOUR - 10 * MIN))
expect_out "a run unfinished for the threshold is raised" "raised${tab}draft-stalled${tab}1"
case $(events) in *"acme/web#8: a CI run has sat unfinished for 3h0m"*) ok "the unfinished age is named" ;; *) fail "no age: $(events)" ;; esac

rm -f "$runtime"/draft-stall.tsv
pr 8 "$H" "Plain." '[]' "$(green "$T")"
row 8 "$H" SUCCESS | put "$T"
run $((T + 20 * HOUR))
expect_eq "a green draft is never read, however old" ""
pr 8 "$H" "Plain." '[]' "$(green "$T")"
row 8 "$H" PENDING | put "$T"
run $((T + 20 * HOUR))
expect_eq "a finished green run is not an unfinished one" ""

echo 'mission_control_stalled_draft_threshold: 30m' >>"$tracked"
pr 8 "$H" "Plain." '[]' "$(running "$T")"
run $((T + 30 * MIN))
expect_out "the threshold knob is honored" "raised${tab}draft-stalled${tab}1"
sed -i.bak 's/^mission_control_stalled_draft_threshold:.*/mission_control_stalled_draft_threshold: soon/' "$tracked"
rm -f "$runtime"/draft-stall.tsv
run $((T + 31 * MIN))
expect_rc "a malformed repo-tracked threshold fails the pass" 1
sed -i.bak '/^mission_control_stalled_draft_threshold:/d' "$tracked"

# --- a failed read raises nothing and is retried ----------------------------
rm -f "$runtime"/draft-stall.tsv "$tmp/pr.9.json"
row 9 "$H" FAILURE | put "$T"
run "$T"
expect_rc "an unreadable pull request" 0
expect_eq "raises nothing" ""
pr 9 "$H" "Plain." '[]' "$(cancelled "$T")"
run $((T + 15 * MIN))
expect_out "and is raised once it reads" "raised${tab}draft-stalled${tab}1"

# --- a draft gone ready or away is forgotten ---------------------------------
{ printf 'pr\tacme/web\t9\t%s\tfalse\tMERGEABLE\tNONE\t0\tFAILURE\t0\t0\tp9\n' "$H"; } | put $((T + HOUR))
run $((T + HOUR))
if [ -f "$runtime/draft-stall.tsv" ] && ! grep -q "acme/web#9" "$runtime/draft-stall.tsv"; then ok "a pull request no longer a draft is dropped from the record"; else fail "kept a non-draft"; fi

# --- a raised head is not raised twice, whatever the checks do between ------
rm -f "$runtime"/draft-stall.tsv
pr 7 "$H" "Plain." '[]' "$(cancelled "$T")"
row 7 "$H" FAILURE | put "$T"
run "$T"
expect_out "raised once" "raised${tab}draft-stalled${tab}1"
before=$(nevents)
row 7 "$H" SUCCESS | put $((T + 15 * MIN))
run $((T + 15 * MIN))
row 7 "$H" FAILURE | put $((T + 30 * MIN))
run $((T + 30 * MIN))
expect_eq "green for a pass, then cancelled again at the same head, is not raised again" ""
if [ "$(nevents)" = "$before" ]; then ok "no second event for the head"; else fail "raised twice for one head"; fi

# --- a snapshot a cadence old names an older head than the forge's ----------
rm -f "$runtime"/draft-stall.tsv
pr 7 "$H2" "Plain." '[]' "$(cancelled "$T")"
row 7 "$H" FAILURE | put "$T"
run "$T"
expect_out "judged at the live head" "raised${tab}draft-stalled${tab}1"
run $((T + 15 * MIN))
expect_eq "the live head is remembered, so the next pass is quiet" ""

# --- a snapshot past twice its cadence raises nothing ----------------------
rm -f "$runtime"/draft-stall.tsv
pr 7 "$H" "Plain." '[]' "$(cancelled "$T")"
row 7 "$H" FAILURE | put "$T"
STALE=1 run $((T + 10 * HOUR))
expect_eq "an old snapshot raises nothing" ""

# --- a run with no start time is aged from the first pass that saw it -------
rm -f "$runtime"/draft-stall.tsv
printf '[{"__typename":"CheckRun","name":"build","workflowName":"ci","status":"QUEUED","conclusion":"","startedAt":"0001-01-01T00:00:00Z","completedAt":"0001-01-01T00:00:00Z"}]' >"$tmp/queued.json"
pr 8 "$H" "Plain." '[]' "$(cat "$tmp/queued.json")"
row 8 "$H" PENDING | put "$T"
run "$T"
expect_eq "a queued run is not raised at first sight" ""
run $((T + 3 * HOUR - MIN))
expect_eq "nor just under the threshold from first sight" ""
run $((T + 3 * HOUR))
expect_out "but at the threshold from first sight" "raised${tab}draft-stalled${tab}1"

# --- hold words are words: stakeholder is no hold ---------------------------
rm -f "$runtime"/draft-stall.tsv
pr 7 "$H" "Holding pattern, nothing is blocked." '[{"name":"stakeholder-review"}]' "$(cancelled "$T")"
row 7 "$H" FAILURE | put "$T"
run "$T"
expect_out "a label or line that only contains hold is no hold" "raised${tab}draft-stalled${tab}1"

# --- twenty stalled drafts fit the event cap, the rest wait a pass ----------
rm -f "$runtime"/draft-stall.tsv
for n in $(seq 200 219); do pr "$n" "$H" "Plain." '[]' "$(cancelled "$T")"; done
for n in $(seq 200 219); do row "$n" "$H" FAILURE; done | put "$T"
before=$(nevents)
run "$T"
run $((T + 15 * MIN))
run $((T + 30 * MIN))
named=$(events | awk -F '\t' '{ print $5 }' | grep -o 'acme/web#2[0-9][0-9]' | sort -u | wc -l | tr -d ' ')
if [ "$named" = 20 ]; then ok "every draft is named by some event"; else fail "named $named of 20 drafts"; fi
if [ "$(events | awk -F '\t' '{ if (length($5) > 500) bad = 1 } END { print bad + 0 }')" = 0 ]; then ok "no event passes the byte cap"; else fail "an event is over 500 bytes"; fi
run $((T + 45 * MIN))
expect_eq "once all are raised, nothing more" ""

# --- the event class wakes the owner ----------------------------------------
if awk -F '\t' '$1 == "draft-stalled" && $2 != "routine" { f = 1 } END { exit !f }' "$repo_root/config/mc-event-classes.tsv"; then
  ok "draft-stalled has a waking class"
else
  fail "draft-stalled is not a waking class"
fi

# --- a stale or absent snapshot raises nothing ------------------------------
rm -f "$runtime"/draft-stall.tsv "$snapdir/forge"
run $((T + 50 * HOUR))
expect_rc "with no snapshot taken" 0
expect_eq "it waits quietly" ""

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
