#!/bin/bash
# rehearsal-lifecycle.sh — the deliberate-wedge lifecycle rehearsal.
#
# WHY. Every close and detector suite in tests/ runs against a shim that plays
# the CLI the way its author imagined it. The leak those suites guard against
# hides on the path a shim does not take: a real worker that stopped making
# progress and was never closed. So this dispatches a worker against a
# throwaway spec bundle, wedges it on purpose, and drives the whole lifecycle
# from there on each session-grade rung:
#
#   1. launch     the rung's own `launch`, against the bundle copied into a
#                 throwaway repository
#   2. wedge      stream-json: the worker asks permission for a command nothing
#                 pre-approves, and the request pends. headless-oneshot has no
#                 pend path (an unapproved ask fails under --print), so it is
#                 held mid-command instead, and its waiting-on-a-human check
#                 reports n/a with that reason rather than passing
#   3. classify   fleet-stuck-detector.sh against the running worker: the
#                 wedged stream-json worker must read waiting-on-a-human, never
#                 working; no held worker may read dead or finished
#   4. sweep      fleet-sweep.sh in both reap modes, observing (the default) and
#                 with a machine-local terminate; neither may take a worker that
#                 is still running
#   5. stop       the rung's `stop`, then every class of its release set checked
#                 independently of what `stop` reported, the repeat stop
#                 answering already-closed, and a post-close sweep finding
#                 nothing held
#
# MODES
#   (default)  the same lifecycle against a scripted CLI, so the harness itself
#              is covered by `mise run check` at no model cost. It proves the
#              harness, not the floor: only --live does that.
#   --live     against the real `claude` CLI. Spends model tokens and a few
#              minutes, so it is opt-in (`mise run rehearsal:lifecycle`) and
#              never part of `check` or CI. One worker at a time.
#
# ISOLATION. Every path the rehearsal touches is under one mktemp root: the
# fleet home (registry, presence, attention store), the headless state, the
# throwaway repository the worker runs in, and the overlay layers. Ambient
# fleet and tower identity is stripped, CLAUDE_PLUGIN_DATA included, and the
# resolved fleet home is checked to be the temp one before anything launches.
# On exit every process naming the root in its argv or running inside it,
# with its descendants, is killed and the absence re-checked.
#
# EXIT  0 every check passed · 1 a check failed · 2 the harness could not run
#       · 3 skipped: --live could not establish a live session (never a pass)
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
S="$REPO_ROOT/scripts"
BUNDLE_SRC="$REPO_ROOT/tests/fixtures/lifecycle-rehearsal/bundle"
SPEC=rehearsal-wedge
UNIT=1
TOWER_ID='feedface-0000-4000-8000-000000000012'
LIVE=0
RUNGS='sj hl'
MODEL=haiku
WAIT=180
# The stream-json wedge: a command nothing pre-approves, so it pends on a
# permission request. The headless hold (HOLD_CMD, set once the temp root
# exists) is a read of a fifo nobody writes: it blocks until the close, and it
# is a read-only shape the worker command guard approves. A foreground `sleep`
# did not hold a live worker: it ended its turn instead.
WEDGE_CMD='mkdir rehearsal-wedge'

usage() {
  cat >&2 <<'USAGE'
usage: tests/rehearsal-lifecycle.sh [--live] [--rung sj|hl] [--model <name>] [--wait <secs>]
  --live    rehearse against the real claude CLI (spends tokens; opt-in only)
  --rung    one rung only: sj (stream-json-persistent) or hl (headless-oneshot)
  --model   the worker model under --live (default: haiku)
  --wait    seconds to wait for the worker to wedge (default: 180)
USAGE
  exit 2
}

while [ $# -gt 0 ]; do
  case $1 in
    --live)
      LIVE=1
      shift
      ;;
    --rung)
      [ $# -ge 2 ] || usage
      case $2 in
        sj | hl) RUNGS=$2 ;;
        *) usage ;;
      esac
      shift 2
      ;;
    --model)
      [ $# -ge 2 ] || usage
      case $2 in
        '' | *[!A-Za-z0-9._-]*) usage ;;
      esac
      MODEL=$2
      shift 2
      ;;
    --wait)
      [ $# -ge 2 ] || usage
      case $2 in
        '' | *[!0-9]*) usage ;;
      esac
      WAIT=$2
      shift 2
      ;;
    -h | --help) usage ;;
    *)
      echo "rehearsal: unknown argument: $1" >&2
      usage
      ;;
  esac
done

failures=0
skips=0

say() {
  printf 'rehearsal: %s\n' "$*"
}
pass() {
  say "[$1] PASS $2"
}
flunk() {
  failures=$((failures + 1))
  say "[$1] FAIL $2" >&2
}
skip() {
  skips=$((skips + 1))
  say "[$1] SKIP $2"
}
na() {
  say "[$1] N/A  $2"
}

# Worker-authored text (stderr, a result record) reaches the terminal only as
# one printable line.
clip() {
  printf '%s' "$1" | tr -d '\000-\037\177' | cut -c1-200
}

command -v jq >/dev/null 2>&1 || {
  echo "rehearsal: jq is required: the stream-json launch preflight runs the auto-approve hook" >&2
  exit 2
}
for f in fleet-streamjson.sh fleet-dispatch-headless.sh fleet-stuck-detector.sh \
  fleet-sweep.sh fleet-state.sh; do
  [ -x "$S/$f" ] || {
    echo "rehearsal: $S/$f missing or not executable" >&2
    exit 2
  }
done
[ -r "$BUNDLE_SRC/requirements.md" ] || {
  echo "rehearsal: the throwaway bundle is missing at $BUNDLE_SRC" >&2
  exit 2
}

# The one way --live cannot run: no CLI to launch. A visible skip, never a pass.
if [ "$LIVE" = 1 ] && ! command -v claude >/dev/null 2>&1; then
  say "SKIP no live session: the claude CLI is not on PATH"
  exit 3
fi

# --- static checks: the bundle is inert and the live run is opt-in ----------

# The bundle sits outside the spec root, so /orchestrate and the status render
# never enumerate it, and it is a Draft, so a copy that strayed in would still
# be refused.
spec_root=$("$S/resolve-root.sh" spec 2>/dev/null) || spec_root="$REPO_ROOT/specs"
case $BUNDLE_SRC/ in
  "$spec_root"/*) flunk static "the throwaway bundle sits under the spec root $spec_root" ;;
  *) pass static "the throwaway bundle sits outside the spec root" ;;
esac
if [ -e "$spec_root/$SPEC" ]; then
  flunk static "a bundle named $SPEC exists under the spec root"
fi
drafts=0
for f in requirements.md design.md tasks.md test-spec.md; do
  grep -qx '\*\*Status:\*\* Draft' "$BUNDLE_SRC/$f" 2>/dev/null && drafts=$((drafts + 1))
done
if [ "$drafts" = 4 ]; then
  pass static "every file of the throwaway bundle is a Draft"
else
  flunk static "the throwaway bundle is not a Draft in every file ($drafts of 4)"
fi

# The live run is its own mise task and nothing CI or `check` runs reaches it.
mise_toml="$REPO_ROOT/mise.toml"
task_body=$(awk '
  /^\[tasks\."rehearsal:lifecycle"\]/ { on = 1; next }
  /^\[/ { on = 0 }
  on' "$mise_toml" 2>/dev/null)
case $task_body in
  *'tests/rehearsal-lifecycle.sh --live'*) pass static "the live rehearsal is its own opt-in mise task" ;;
  *) flunk static "mise.toml has no rehearsal:lifecycle task running tests/rehearsal-lifecycle.sh --live" ;;
esac
check_body=$(awk '
  /^\[tasks\.check\]/ { on = 1; next }
  /^\[/ { on = 0 }
  on' "$mise_toml" 2>/dev/null)
case $check_body in
  *rehearsal*) flunk static "the check aggregate reaches the rehearsal task" ;;
  *) pass static "the check aggregate does not reach the live rehearsal" ;;
esac
wf_hits=''
for wf in "$REPO_ROOT"/.github/workflows/*; do
  [ -f "$wf" ] || continue
  grep -Eq 'rehearsal:lifecycle|rehearsal-lifecycle\.sh[^#]*--live' "$wf" && wf_hits="$wf_hits ${wf##*/}"
done
if [ -z "$wf_hits" ]; then
  pass static "no workflow runs the live rehearsal"
else
  flunk static "a workflow runs the live rehearsal:$wf_hits"
fi

# --- the isolated world ------------------------------------------------------

mk=$(mktemp -d "${TMPDIR:-/tmp}/pw-rehearsal.XXXXXX") || exit 2
mk=$(cd "$mk" && pwd -P) || exit 2
mkdir -p "$mk/home" "$mk/headless" "$mk/adopter" "$mk/userhome" "$mk/bin" "$mk/gh-stub"

# pids_under <root> — every process naming <root> in its argv or, where /proc
# exists, running with its cwd inside it, plus all their descendants. The
# snapshot goes through a variable so a scan never finds its own argv.
pids_under() {
  pu_snap=$(ps -A -ww -o pid=,ppid=,args= 2>/dev/null) || pu_snap=''
  [ -n "$pu_snap" ] || pu_snap=$(ps -A -o pid=,ppid=,args= 2>/dev/null) || pu_snap=''
  pu_seed=''
  while read -r pu_p _ pu_a; do
    [ "$pu_p" = "$$" ] && continue
    case $pu_a in
      *"$1"*) pu_seed="$pu_seed $pu_p" ;;
    esac
  done <<EOF
$pu_snap
EOF
  # One `ls` for every cwd link: a readlink per process costs seconds.
  if [ -d /proc/self ]; then
    # shellcheck disable=SC2012  # /proc entries are numeric; find has no portable -lname read
    pu_seed="$pu_seed $(ls -l /proc/[0-9]*/cwd 2>/dev/null | awk -v r="$1" '
      { t = $NF; l = $(NF - 2) }
      t == r || index(t, r "/") == 1 { split(l, a, "/"); print a[3] }')"
  fi
  printf '%s\n' "$pu_snap" | awk -v seed="$pu_seed" -v self="$$" '
    BEGIN { n = split(seed, s, " "); for (i = 1; i <= n; i++) keep[s[i]] = 1 }
    { kid[$1] = $2; pids[NR] = $1 }
    END {
      grew = 1
      while (grew) {
        grew = 0
        for (i = 1; i <= NR; i++) {
          p = pids[i]
          if (!(p in keep) && (kid[p] in keep)) { keep[p] = 1; grew = 1 }
        }
      }
      for (p in keep) if (p != self && p != "") print p
    }'
}

# The tree a stop is expected to end, recorded as `<pid> TAB <argv>` while the
# run goes, so the exit trap can reach a process that outlived its parent and
# no longer names the root. A pid counts only while its argv still matches: a
# dead worker's pid can be reissued to anything.
tracked="$mk/tracked-pids"
: >"$tracked"

# same_pids <file> — the recorded pids still running the recorded argv.
same_pids() {
  while IFS="$(printf '\t')" read -r sp_p sp_a; do
    [ -n "$sp_p" ] || continue
    [ "$(ps -ww -p "$sp_p" -o args= 2>/dev/null)" = "$sp_a" ] && printf '%s\n' "$sp_p"
  done <"$1"
}

final_check() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    fc_left=$({
      pids_under "$mk"
      same_pids "$tracked"
    } | awk 'NF' | sort -u)
    [ -z "$fc_left" ] && return 0
    for fc_p in $fc_left; do
      kill -9 "$fc_p" 2>/dev/null
    done
    sleep 0.5
  done
  printf '%s\n' "$fc_left"
  return 1
}

cleanup() {
  trap - EXIT INT TERM HUP
  rmdir "$mk/hold" 2>/dev/null
  if leftover=$(final_check); then
    say "no process remains under the rehearsal root"
  else
    say "FAIL processes outlived the rehearsal root: $(printf '%s' "$leftover" | tr '\n' ' ')" >&2
    failures=$((failures + 1))
  fi
  rm -rf "$mk"
  if [ "$failures" -gt 0 ]; then
    say "FAIL ($failures)" >&2
    exit 1
  fi
  if [ "$skips" -gt 0 ]; then
    say "SKIPPED ($skips) — not a pass"
    exit 3
  fi
  if [ "$LIVE" = 1 ]; then
    say "PASS"
  else
    say "PASS (scripted CLI; the floor is proven only by --live: mise run rehearsal:lifecycle)"
  fi
  exit 0
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP

# A gh that answers nothing, for the sweep's reconcile pass: the throwaway
# repository has no forge, and no call may leave the host.
cat >"$mk/gh-stub/gh" <<'GH'
#!/bin/sh
echo "gh: disabled inside the lifecycle rehearsal" >&2
exit 1
GH
chmod +x "$mk/gh-stub/gh"

# The scripted CLI. It reads its opening input, then plays the rung's wedge:
# stream-json emits init and a pending permission request and holds the
# channel; headless runs the hold command as a child, as the Bash tool would.
cat >"$mk/bin/claude" <<'SHIM'
#!/bin/sh
case " $* " in
  *" --input-format "*)
    IFS= read -r _line || :
    sid=5e55e55e-0000-4000-8000-000000000012
    printf '%s\n' '{"type":"system","subtype":"init","cwd":"/x","session_id":"'$sid'","tools":[]}'
    printf '%s\n' '{"type":"control_request","request_id":"5e55e55e-0000-4000-8000-0000000000aa","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"mkdir rehearsal-wedge"},"tool_use_id":"t1"}}'
    while [ -d "$REHEARSAL_HOLD" ]; do
      sleep 1
    done
    ;;
  *)
    cat >/dev/null
    cat "$REHEARSAL_FIFO" >/dev/null
    ;;
esac
exit 0
SHIM
chmod +x "$mk/bin/claude"
mkdir "$mk/hold"
mkfifo "$mk/hold.fifo" || {
  echo "rehearsal: could not create the hold fifo" >&2
  exit 2
}
HOLD_CMD="cat $mk/hold.fifo"

git_env() {
  GIT_AUTHOR_NAME=rehearsal GIT_AUTHOR_EMAIL=rehearsal@invalid \
    GIT_COMMITTER_NAME=rehearsal GIT_COMMITTER_EMAIL=rehearsal@invalid \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$@"
}
repo="$mk/repo"
{
  git_env git init -q -b main "$repo" \
    && mkdir -p "$repo/specs" \
    && cp -R "$BUNDLE_SRC" "$repo/specs/$SPEC" \
    && git_env git -C "$repo" add -A \
    && git_env git -C "$repo" commit -qm "rehearsal: throwaway bundle" \
    && git_env git init -q --bare "$mk/origin.git" \
    && git_env git -C "$repo" remote add origin "$mk/origin.git" \
    && git_env git -C "$repo" push -q -u origin main \
    && printf '.claude/\n' >>"$repo/.git/info/exclude"
} || {
  echo "rehearsal: could not build the throwaway repository" >&2
  exit 2
}
head_before=$(git -C "$repo" rev-parse HEAD)

scrub=(
  -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR
  -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID -u PLANWRIGHT_TOWER_PID
  -u PLANWRIGHT_TOWER_CHECKOUT -u PLANWRIGHT_TOWER_LAUNCHER
  -u PLANWRIGHT_TOWER_READY_CHECK -u PLANWRIGHT_TOWER_EVIDENCE_CMD
  -u PLANWRIGHT_ORCH_STATE_DIR -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS
  -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE
  -u PLANWRIGHT_FLEET_LOCK_HELD -u PLANWRIGHT_ALLOC_LOCK_HELD
  -u PLANWRIGHT_STREAMJSON_PENDING_AGE -u PLANWRIGHT_STREAMJSON_ALARM_TICK
  -u PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT -u PLANWRIGHT_STREAMJSON_CLI
  -u PLANWRIGHT_HEADLESS_CLAUDE -u PLANWRIGHT_HEADLESS_ENVWRAP
  -u PLANWRIGHT_USAGE_SIGNAL_DIR -u PLANWRIGHT_ATTENTION_SURFACE_PROVIDED
  -u FLEET_PANE_PROMPT_ANCHORS -u FLEET_PANE_PROMPT_SIGNATURES
  -u TMUX -u TMUX_PANE
  -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR
)
pin=(
  PLANWRIGHT_FLEET_STATE_DIR="$mk/home"
  PLANWRIGHT_HEADLESS_STATE_DIR="$mk/headless"
  PLANWRIGHT_REPO_ROOT="$repo"
  PLANWRIGHT_ADOPTER_OVERLAY="$mk/adopter"
  PLANWRIGHT_ROOT="$REPO_ROOT"
  REHEARSAL_HOLD="$mk/hold"
  REHEARSAL_FIFO="$mk/hold.fifo"
)
cli=()
if [ "$LIVE" = 0 ]; then
  cli=(PLANWRIGHT_STREAMJSON_CLI="$mk/bin/claude" PLANWRIGHT_HEADLESS_CLAUDE="$mk/bin/claude")
fi

# hrun <script> <args...> — a fleet script as the harness runs it: hermetic
# HOME, no forge, the temp fleet home.
hrun() {
  hr_s=$1
  shift
  env "${scrub[@]}" "${pin[@]}" ${cli[@]+"${cli[@]}"} \
    HOME="$mk/userhome" PATH="$mk/gh-stub:$PATH" /bin/sh "$S/$hr_s" "$@"
}

# lrun <script> <args...> — a launch. Under --live the worker keeps the real
# HOME, which is where the CLI's own login lives; everything planwright
# resolves still lands under the temp root.
lrun() {
  lr_s=$1
  shift
  if [ "$LIVE" = 1 ]; then
    env "${scrub[@]}" "${pin[@]}" /bin/sh "$S/$lr_s" "$@"
  else
    hrun "$lr_s" "$@"
  fi
}

resolved_home=$(hrun fleet-state.sh root 2>/dev/null) || resolved_home=''
if [ "$resolved_home" != "$mk/home" ]; then
  echo "rehearsal: refusing to launch: the fleet home resolves to '$resolved_home', not the rehearsal's own" >&2
  exit 2
fi

wait_for() {
  wf_n=$1
  shift
  wf_end=$((SECONDS + wf_n))
  while [ "$SECONDS" -lt "$wf_end" ]; do
    "$@" && return 0
    sleep 1
  done
  "$@"
}

# --- per-rung helpers ---------------------------------------------------------

handle_of() {
  case $1 in
    sj) printf '%s' "$SJ_HANDLE" ;;
    hl) printf 'headless-%s-task-%s' "$SPEC" "$UNIT" ;;
  esac
}
SJ_HANDLE=rehearsal-sj

dir_of() {
  case $1 in
    sj) printf '%s/home/streamjson/%s' "$mk" "$(handle_of sj)" ;;
    hl) printf '%s/headless/%s' "$mk" "$UNIT" ;;
  esac
}

script_of() {
  case $1 in
    sj) printf 'fleet-streamjson.sh' ;;
    hl) printf 'fleet-dispatch-headless.sh' ;;
  esac
}

model_args() {
  [ "$LIVE" = 1 ] && printf '%s\n' -- --model "$MODEL"
}

launch() {
  la_prompt="$mk/prompt-$1"
  case $1 in
    sj)
      printf 'Rehearsal. Use the Bash tool to run exactly this command and nothing else: %s\nDo not use any other tool and do not explain.\n' \
        "$WEDGE_CMD" >"$la_prompt"
      # shellcheck disable=SC2046  # model_args prints one argv word per line
      lrun fleet-streamjson.sh launch "$(handle_of sj)" "$SPEC:$UNIT" \
        --prompt-file "$la_prompt" --cwd "$repo" $(model_args) >"$mk/launch-$1.out" 2>&1
      ;;
    hl)
      printf 'Rehearsal. Use the Bash tool to run exactly this command and nothing else: %s\nDo not use any other tool and do not explain.\n' \
        "$HOLD_CMD" >"$la_prompt"
      # shellcheck disable=SC2046
      lrun fleet-dispatch-headless.sh launch "$SPEC" "$UNIT" --worktree "$repo" \
        --repo-root "$repo" $(model_args) <"$la_prompt" >"$mk/launch-$1.out" 2>&1
      ;;
  esac
}

# wedged <rung> — the positive evidence the worker reached its wedge.
wedged() {
  case $1 in
    sj)
      awk -F'\t' '$2 == "permission" && $4 == "pending"' "$(dir_of sj)/journal" 2>/dev/null | grep -q .
      ;;
    hl)
      we_root=$(cat "$(dir_of hl)/pid" 2>/dev/null) || return 1
      we_snap=$(ps -A -ww -o pid=,ppid=,args= 2>/dev/null) || return 1
      printf '%s\n' "$we_snap" | awk -v root="$we_root" -v cmd="$HOLD_CMD" '
        { parent[$1] = $2; line[$1] = $0 }
        END {
          for (p in line) {
            if (index(line[p], cmd) == 0) continue
            q = p
            for (i = 0; i < 64 && q != "" && q != "0"; i++) {
              if (q == root) { found = 1; break }
              q = parent[q]
            }
          }
          exit found ? 0 : 1
        }'
      ;;
  esac
}

# ended <rung> — the run finished before (or instead of) wedging.
ended() {
  case $1 in
    sj) [ -s "$(dir_of sj)/result" ] ;;
    hl) [ -s "$(dir_of hl)/exit" ] ;;
  esac
}

ended_detail() {
  case $1 in
    sj)
      clip "$(cat "$(dir_of sj)/result" 2>/dev/null); result: $(grep '"type":"result"' "$(dir_of sj)/events.jsonl" 2>/dev/null | tail -n 1 | jq -r '.result // empty' 2>/dev/null | head -c 400) $(tail -n 3 "$(dir_of sj)/stderr.log" 2>/dev/null)"
      ;;
    hl)
      clip "exit $(cat "$(dir_of hl)/exit" 2>/dev/null); result: $(jq -r '.result // empty' "$(dir_of hl)/result.json" 2>/dev/null | head -c 400) $(tail -n 3 "$(dir_of hl)/stderr.log" 2>/dev/null)"
      ;;
  esac
}

# A run that ended in an error before ever wedging never had a working session
# (no login, no network, a refused model): that is the skip. One that ended
# cleanly without wedging is a worker that was not held, and that is a failure.
ended_in_error() {
  case $1 in
    sj)
      # `result <subtype> <epoch> [true|false]` or `exit <rc> <epoch>`.
      awk -F'\t' 'NR == 1 { ok = ($1 == "result" && $2 == "success" && $4 != "true") }
        END { exit ok ? 1 : 0 }' "$(dir_of sj)/result" 2>/dev/null
      ;;
    hl)
      case $(cat "$(dir_of hl)/exit" 2>/dev/null) in
        '0 '*) ;;
        *) return 0 ;;
      esac
      case $(head -c 4000 "$(dir_of hl)/result.json" 2>/dev/null) in
        *'"is_error":true'* | *'"is_error": true'* | '') return 0 ;;
      esac
      return 1
      ;;
  esac
}

wedge_or_end() {
  wedged "$1" || ended "$1"
}

# wedge_verdict <rung> — after the wait: `wedged`, `skip <why>` when no live
# session was ever established, or `fail <why>`.
wedge_verdict() {
  if wedged "$1"; then
    echo wedged
  elif ended "$1" && ended_in_error "$1"; then
    echo "skip no live session could be established: $(ended_detail "$1")"
  elif ended "$1"; then
    echo "fail the worker finished without being wedged: $(ended_detail "$1")"
  else
    echo "skip no live session within ${WAIT}s: the worker neither wedged nor ended"
  fi
}

# tree_of <rung> — the recorded pids and everything under them right now.
tree_of() {
  case $1 in
    sj) to_seed="$(cat "$(dir_of sj)/supervisor.pid" "$(dir_of sj)/worker.pid" 2>/dev/null)" ;;
    hl) to_seed="$(cat "$(dir_of hl)/pid" 2>/dev/null)" ;;
  esac
  to_snap=$(ps -A -o pid=,ppid= 2>/dev/null) || to_snap=''
  printf '%s\n' "$to_snap" | awk -v seed="$to_seed" '
    BEGIN { n = split(seed, s, /[ \n]+/); for (i = 1; i <= n; i++) if (s[i] != "") keep[s[i]] = 1 }
    { kid[$1] = $2; pids[NR] = $1 }
    END {
      grew = 1
      while (grew) {
        grew = 0
        for (i = 1; i <= NR; i++) {
          p = pids[i]
          if (!(p in keep) && (kid[p] in keep)) { keep[p] = 1; grew = 1 }
        }
      }
      for (p in keep) print p
    }'
}

# snapshot_tree <rung> — `<pid> TAB <argv>` for the rung's tree right now.
snapshot_tree() {
  for st_p in $(tree_of "$1"); do
    st_a=$(ps -ww -p "$st_p" -o args= 2>/dev/null) || continue
    printf '%s\t%s\n' "$st_p" "$st_a"
  done
}

# tree_alive <rung> — true while any process of the snapshot taken at the
# wedge is still the same process.
tree_alive() {
  [ -n "$(same_pids "$mk/tree-$1")" ]
}

detector_state() {
  hrun fleet-stuck-detector.sh classify "$(handle_of "$1")" --tower-id "$TOWER_ID" 2>/dev/null \
    | awk -F'\t' '$1 == "worker" { print $3 "\t" $6; exit }'
}

# sweep <rung> <label> — one cycle; sets sw_rc, sw_out, sw_err.
sweep() {
  sw_rc=0
  hrun fleet-sweep.sh --repo "$repo" --tower-id "$TOWER_ID" >"$mk/sweep.out" 2>"$mk/sweep.err" || sw_rc=$?
  sw_out=$(cat "$mk/sweep.out")
  sw_err=$(cat "$mk/sweep.err")
}

sweep_mode() {
  printf '%s\n' "$sw_out" | awk -F'\t' '$1 == "summary" { sub(/^mode=/, "", $2); print $2; exit }'
}

# sweep_took <handle> — the reap outcome for the worker, when the cycle acted
# on it or would have.
sweep_took() {
  printf '%s\n' "$sw_out" | awk -F'\t' -v w="$1" '
    $1 == "reap" && $2 == w && ($3 == "reaped" || $3 == "partial" || $3 == "observed" || $3 == "unrecorded") { print $3; exit }'
}

held_classes() {
  hc_d=$(dir_of "$1")
  hc_w=$(handle_of "$1")
  hc_out=''
  if [ "$(pids_under "$hc_d")" != '' ] || tree_alive "$1"; then
    hc_out="$hc_out process"
  fi
  if [ "$1" = sj ]; then
    for hc_l in journal.lock recover.lock launch.lock; do
      [ -e "$hc_d/$hc_l" ] && hc_out="$hc_out locks:$hc_l"
    done
    for hc_f in "$hc_d"/in.fifo "$hc_d"/out.fifo "$hc_d"/.init.* "$hc_d"/.frame.* \
      "$hc_d"/.journal.* "$hc_d"/.session.* "$hc_d"/.pid.* "$hc_d"/*.broken.*; do
      [ -e "$hc_f" ] || [ -p "$hc_f" ] && hc_out="$hc_out scratch:${hc_f##*/}"
    done
  else
    for hc_f in "$hc_d"/exit.tmp "$hc_d"/.exit.*; do
      [ -e "$hc_f" ] && hc_out="$hc_out scratch:${hc_f##*/}"
    done
  fi
  if [ -f "$mk/home/attention/state" ] \
    && awk -F'\t' -v w="$hc_w" '$1 == w { f = 1 } END { exit f ? 0 : 1 }' "$mk/home/attention/state"; then
    hc_out="$hc_out attention"
  fi
  printf '%s' "${hc_out# }"
}

machine_local="$repo/.claude/planwright.local.yml"

# --- the lifecycle, one rung at a time ----------------------------------------

rehearse() {
  r=$1
  w=$(handle_of "$r")
  d=$(dir_of "$r")
  sc=$(script_of "$r")

  # 1. launch
  la_rc=0
  launch "$r" || la_rc=$?
  if [ "$la_rc" != 0 ]; then
    flunk "$r" "launch exited $la_rc: $(clip "$(cat "$mk/launch-$r.out")")"
    return
  fi
  pass "$r" "launched $w"

  # 2. wedge, or the visible skip when no session could be established
  wait_for "$WAIT" wedge_or_end "$r"
  snapshot_tree "$r" >>"$tracked"
  verdict=$(wedge_verdict "$r")
  case $verdict in
    wedged) ;;
    skip\ *)
      skip "$r" "${verdict#skip }"
      hrun "$sc" stop "$w" --grace 2 >/dev/null 2>&1
      return
      ;;
    *)
      flunk "$r" "${verdict#fail }"
      hrun "$sc" stop "$w" --grace 2 >/dev/null 2>&1
      return
      ;;
  esac
  case $r in
    sj) pass "$r" "the worker is wedged on a pending permission request ($WEDGE_CMD)" ;;
    hl) pass "$r" "the worker is held mid-command ($HOLD_CMD)" ;;
  esac
  snapshot_tree "$r" >"$mk/tree-$r"
  cat "$mk/tree-$r" >>"$tracked"

  # 3. classify the running worker
  cls=$(detector_state "$r")
  state=${cls%%"$(printf '\t')"*}
  reason=${cls#*"$(printf '\t')"}
  case $r:$state in
    sj:waiting-on-a-human) pass "$r" "the detector classifies the wedged worker waiting-on-a-human (reason: $reason)" ;;
    sj:*) flunk "$r" "the detector classifies the wedged worker '$state' (reason: $reason), not waiting-on-a-human" ;;
    hl:dead | hl:finished-but-unreaped | hl:)
      flunk "$r" "the detector classifies a held, live worker '$state' (reason: $reason)"
      ;;
    hl:*)
      pass "$r" "the detector does not read the held worker as dead or finished (state: $state, reason: $reason)"
      na "$r" "waiting-on-a-human: headless-oneshot has no pend path; an unapproved ask fails under --print instead of waiting"
      ;;
  esac
  if [ "$r" = hl ]; then
    st_out=$(hrun "$sc" status "$SPEC" "$UNIT" 2>/dev/null)
  else
    st_out=$(hrun "$sc" status "$w" 2>/dev/null)
  fi
  case $r:$st_out in
    sj:"status $w awaiting-input"*) pass "$r" "the rung's own status reads awaiting-input" ;;
    hl:"running "*) pass "$r" "the rung's own status reads running" ;;
    *) flunk "$r" "the rung's own status reads '$(clip "$st_out")'" ;;
  esac

  # 4. both sweep modes, while the worker is still held
  rm -f "$machine_local"
  sweep
  took=$(sweep_took "$w")
  if [ "$sw_rc" = 0 ] && [ "$(sweep_mode)" = observe ] && [ -z "$took" ] \
    && tree_alive "$r"; then
    pass "$r" "an observing sweep leaves the held worker alone"
  else
    flunk "$r" "observing sweep: exit $sw_rc, mode '$(sweep_mode)', outcome '$took', $(clip "$sw_err")"
  fi
  mkdir -p "$repo/.claude"
  printf 'fleet_sweep_reap: terminate\n' >"$machine_local"
  sweep
  took=$(sweep_took "$w")
  if [ "$sw_rc" = 0 ] && [ -z "$took" ] && tree_alive "$r"; then
    case $sw_err in
      *'terminate is refused'*)
        pass "$r" "a terminating sweep leaves the held worker alone (terminate is refused for now, so the cycle observed and said why)"
        ;;
      *) pass "$r" "a terminating sweep (mode $(sweep_mode)) leaves the held worker alone" ;;
    esac
  else
    flunk "$r" "terminating sweep: exit $sw_rc, mode '$(sweep_mode)', outcome '$took', $(clip "$sw_err")"
  fi
  rm -f "$machine_local"

  # 5. stop, then the release set, checked independently of what stop said
  if [ "$r" = hl ]; then
    stop_out=$(hrun "$sc" stop "$w" --grace 5 --expect-dir "$d" 2>&1)
  else
    stop_out=$(hrun "$sc" stop "$w" --grace 5 2>&1)
  fi
  stop_rc=$?
  case $stop_rc:$stop_out in
    "0:stop $w stopped released="*) pass "$r" "stop closes the worker ($(clip "${stop_out#stop "$w" }"))" ;;
    *) flunk "$r" "stop exited $stop_rc: $(clip "$stop_out")" ;;
  esac
  held=''
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    held=$(held_classes "$r")
    [ -z "$held" ] && break
    sleep 0.5
  done
  if [ -z "$held" ]; then
    pass "$r" "every class of the release set is empty: process tree, locks, scratch temp, attention record"
  else
    flunk "$r" "the release set still holds: $held"
  fi
  na "$r" "tmux window: this rung runs no window"
  if [ -d "$repo/.git" ] && [ "$(git -C "$repo" rev-parse HEAD 2>/dev/null)" = "$head_before" ] \
    && [ "$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null)" = main ] \
    && [ -r "$repo/specs/$SPEC/tasks.md" ]; then
    pass "$r" "the worktree, its branch and the bundle are untouched"
  else
    flunk "$r" "the worktree, branch or bundle changed under the close"
  fi
  if [ "$r" = hl ]; then
    again=$(hrun "$sc" stop "$w" --expect-dir "$d" 2>&1)
  else
    again=$(hrun "$sc" stop "$w" 2>&1)
  fi
  again_rc=$?
  if [ "$again_rc" = 0 ] && [ "$again" = "stop $w already-closed" ]; then
    pass "$r" "a repeat stop answers already-closed"
  else
    flunk "$r" "a repeat stop exited $again_rc: $(clip "$again")"
  fi

  # 6. the post-close sweep finds nothing held
  sweep
  took=$(sweep_took "$w")
  if [ "$r" = hl ]; then
    obs=$(hrun "$sc" stop "$w" --observe --expect-dir "$d" 2>&1)
  else
    obs=$(hrun "$sc" stop "$w" --observe 2>&1)
  fi
  if [ "$sw_rc" = 0 ] && [ -z "$took" ] && [ "$obs" = "stop $w already-closed" ] \
    && [ -z "$(held_classes "$r")" ]; then
    pass "$r" "a post-close sweep finds nothing held"
  else
    flunk "$r" "post-close: sweep exit $sw_rc outcome '$took', observe '$(clip "$obs")', held '$(held_classes "$r")'"
  fi
}

# The skip path, scripted: a session that never comes up must read as a skip.
# Only without --live, where it costs nothing; under --live the real CLI
# decides which path runs.
skip_path() {
  # The whole run: --live with no CLI on PATH exits 3, never 0.
  sp_path=''
  sp_old_ifs=$IFS
  IFS=:
  for sp_p in $PATH; do
    [ -x "$sp_p/claude" ] || sp_path="$sp_path${sp_path:+:}$sp_p"
  done
  IFS=$sp_old_ifs
  # Never recurse into a run that could still find a CLI: that would be a real
  # live rehearsal started from inside `check`.
  if [ -n "$(PATH="$sp_path" /bin/sh -c 'command -v claude' 2>/dev/null)" ]; then
    na skip-path "--live without a CLI: a claude CLI stays reachable with every PATH entry holding one removed"
  else
    sp_rc=0
    sp_out=$(PATH="$sp_path" /bin/bash "$0" --live --rung sj 2>&1) || sp_rc=$?
    case $sp_rc:$sp_out in
      3:*'SKIP no live session'*) pass skip-path "--live without a CLI exits 3 with its reason, not 0" ;;
      2:*'jq is required'*) na skip-path "--live without a CLI: jq shares the CLI's directory on this host" ;;
      *) flunk skip-path "--live without a CLI exited $sp_rc: $(clip "$sp_out")" ;;
    esac
  fi

  # One rung: a CLI that fails before its session starts.
  SJ_HANDLE=rehearsal-nosession
  sp_cli=(${cli[@]+"${cli[@]}"})
  cli=(PLANWRIGHT_STREAMJSON_CLI="$mk/bin/claude-nosession")
  launch sj || :
  sp_wait=$WAIT
  WAIT=30
  wait_for "$WAIT" wedge_or_end sj
  case $(wedge_verdict sj) in
    skip\ *) pass skip-path "a worker whose session never starts is reported as a skip, not a pass" ;;
    *) flunk skip-path "a worker whose session never starts read as: $(clip "$(wedge_verdict sj)")" ;;
  esac
  hrun fleet-streamjson.sh stop "$SJ_HANDLE" --grace 2 >/dev/null 2>&1
  WAIT=$sp_wait
  cli=(${sp_cli[@]+"${sp_cli[@]}"})
  SJ_HANDLE=rehearsal-sj
}

if [ "$LIVE" = 0 ]; then
  cat >"$mk/bin/claude-nosession" <<'SHIM'
#!/bin/sh
IFS= read -r _line || :
echo "Invalid API key · Please run /login" >&2
printf '%s\n' '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"Invalid API key"}'
exit 1
SHIM
  chmod +x "$mk/bin/claude-nosession"
  skip_path
fi

for r in $RUNGS; do
  rehearse "$r"
done
