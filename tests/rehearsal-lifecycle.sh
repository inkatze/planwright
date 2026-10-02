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
#                 is still running. While the sweep refuses terminate
#                 everywhere, the terminate cycle observes, and the check
#                 requires the sweep to say it refused
#   5. stop       the rung's `stop`, then every class of its release set checked
#                 independently of what `stop` reported, and the repeat stop
#                 answering already-closed
#   6. post-close a sweep and an observing stop finding nothing held
#
# MODES
#   (default)  the same lifecycle against a scripted CLI, so the harness itself
#              is covered by `mise run check` at no model cost. It proves the
#              harness, not the floor: only --live does that.
#   --live     against the real `claude` CLI. Spends model tokens and a few
#              minutes, so it is opt-in (`mise run rehearsal:lifecycle`) and
#              never part of `check` or CI. One worker at a time.
#
# ISOLATION. Everything planwright writes is under one mktemp root: the fleet
# home (registry, presence, attention store), the headless state, the
# throwaway repository the worker runs in, and the adopter and machine-local
# overlay layers; the scripts and core defaults are read from this checkout.
# Under
# --live the CLI itself keeps the real HOME, where its login lives, so it
# records its own session state there as any session does. Ambient
# fleet and tower identity is stripped, CLAUDE_PLUGIN_DATA included, and the
# resolved fleet home is checked to be the temp one before anything launches.
# On exit every process naming the root in its argv or running inside it,
# with its descendants, and every process of the tree snapshotted at the
# wedge that is still the same process, is killed and the absence
# re-checked; anything still
# there at exit is a failure, because the close should already have ended it.
#
# EXIT  0 every check passed · 1 a check failed · 2 the harness could not run
#       · 3 skipped: --live could not establish a live session (never a pass)
#       · a signal is re-raised once the cleanup has run
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
WAIT=''
# The stream-json wedge: a command nothing pre-approves, so it pends on a
# permission request. The headless hold (HOLD_CMD, set once the temp root
# exists) is a read of a fifo nobody writes: it blocks until the close, and it
# is a read-only shape the worker command guard approves. A foreground `sleep`
# did not hold a live worker: it ended its turn instead.
WEDGE_CMD='mkdir rehearsal-wedge'
TAB=$(printf '\t')

usage() {
  cat >&2 <<'USAGE'
usage: tests/rehearsal-lifecycle.sh [--live] [--rung sj|hl] [--model <name>] [--wait <secs>]
  --live    rehearse against the real claude CLI (spends tokens; opt-in only)
  --rung    one rung only: sj (stream-json-persistent) or hl (headless-oneshot)
  --model   the worker model under --live (default: haiku)
  --wait    seconds to wait for the worker to wedge (default: 180 live, 30 scripted)
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

if [ -z "$WAIT" ]; then
  # The scripted CLI wedges at once; a long wait there only turns a broken
  # wedge into a blown test-time budget instead of a quick failure.
  if [ "$LIVE" = 1 ]; then WAIT=180; else WAIT=30; fi
fi

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
# one printable line: C0 and C1 controls both go, since a terminal acts on
# either.
clip() {
  printf '%s' "$1" | tr -d '\000-\037\177-\237' | cut -c1-200
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

# --- the process table --------------------------------------------------------

# proc_table — one `<pid> TAB <ppid> TAB <start> TAB <argv>` row per process.
# The start time is what tells a process from a later one reissued its pid.
proc_table() {
  ps -A -ww -o pid=,ppid=,lstart=,args= 2>/dev/null | awk '
    {
      a = $0
      for (i = 1; i <= 7; i++) sub(/^[ \t]*[^ \t]+/, "", a)
      sub(/^[ \t]+/, "", a)
      printf "%s\t%s\t%s%s%s%s%s\t%s\n", $1, $2, $3, $4, $5, $6, $7, a
    }'
}

# Every process assertion below rests on the table; an unreadable one would
# make "nothing is left running" pass for the wrong reason.
case $(proc_table | awk -F'\t' -v me="$$" '$1 == me { print "ok"; exit }') in
  ok) ;;
  *)
    echo "rehearsal: this host's ps cannot list pid, ppid, start time and argv" >&2
    exit 2
    ;;
esac

# descendants <table> <seeds> <self> — the seeds still in the table and every
# process under them, as table rows; <self> is never included.
descendants() {
  printf '%s\n' "$1" | awk -F'\t' -v seed="$2" -v self="$3" '
    BEGIN { n = split(seed, s, " "); for (i = 1; i <= n; i++) if (s[i] != "") keep[s[i]] = 1 }
    NF >= 4 { par[$1] = $2; row[$1] = $0; ids[++m] = $1 }
    END {
      grew = 1
      while (grew) {
        grew = 0
        for (i = 1; i <= m; i++) {
          p = ids[i]
          if (!(p in keep) && (par[p] in keep)) { keep[p] = 1; grew = 1 }
        }
      }
      for (p in keep) if ((p in row) && p != self) print row[p]
    }'
}

# pids_under <root> — every process naming <root> in its argv or, where /proc
# exists, running with its cwd inside it, plus all their descendants. The
# table is read before the filter runs, so a scan never finds its own argv.
pids_under() {
  # Only ever a path inside a rehearsal root: an empty or wider one would
  # match every process on the host.
  case $1 in
    */pw-rehearsal.?*) ;;
    *) return 1 ;;
  esac
  pu_table=$(proc_table)
  pu_seed=$(printf '%s\n' "$pu_table" | awk -F'\t' -v r="$1" -v me="$$" \
    '$1 != me && index($4, r) { printf "%s ", $1 }')
  # One `ls` for every cwd link: a readlink per process costs seconds. A cwd
  # removed under the process reads `-> <path> (deleted)`.
  if [ -d /proc/self ]; then
    # shellcheck disable=SC2012  # /proc entries are numeric; find has no portable -lname read
    pu_seed="$pu_seed $(ls -l /proc/[0-9]*/cwd 2>/dev/null | awk -v r="$1" '
      { t = $NF; l = $(NF - 2) }
      t == "(deleted)" { t = $(NF - 1); l = $(NF - 3) }
      t == r || index(t, r "/") == 1 { split(l, a, "/"); printf "%s ", a[3] }')"
  fi
  descendants "$pu_table" "$pu_seed" "$$" | cut -f1
}

# same_pids <rows> — the pids of `<pid> TAB <start> TAB <argv>` rows still
# running as the same process: same pid, start time and argv.
same_pids() {
  [ -n "$1" ] || return 0
  awk -F'\t' 'NR == FNR { id[$1] = $3 "\t" $4; next }
    NF >= 3 && ($1 in id) && id[$1] == $2 "\t" $3 { print $1 }' <(proc_table) - <<<"$1"
}

# rows_of <pids...> — the current table rows of <pids>, as same_pids reads.
# shellcheck disable=SC2329  # called from final_check, under the EXIT trap
rows_of() {
  proc_table | awk -F'\t' -v want=" $* " 'index(want, " " $1 " ") { print $1 "\t" $3 "\t" $4 }'
}

# final_check — kill what is left under the root. Prints the leftovers and
# returns 1 when anything was there at all, 2 when something would not die,
# 3 when it could not look.
# shellcheck disable=SC2329  # called from the EXIT trap's cleanup
final_check() {
  case $mk in
    */pw-rehearsal.?*) ;;
    *)
      echo "unexpected rehearsal root '$mk'"
      return 3
      ;;
  esac
  fc_seen=''
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if [ -z "$(proc_table)" ]; then
      echo "the process table could not be read"
      return 3
    fi
    # shellcheck disable=SC2046  # pid lists, one word each
    fc_rows=$(rows_of $({
      pids_under "$mk"
      same_pids "${tracked:-}"
    } | awk 'NF' | sort -u))
    if [ -z "$fc_rows" ]; then
      [ -z "$fc_seen" ] && return 0
      printf '%s\n' "$fc_seen"
      return 1
    fi
    fc_seen=$(printf '%s\n%s\n' "$fc_seen" "$(printf '%s\n' "$fc_rows" | cut -f1)" | awk 'NF' | sort -u)
    # Re-checked against a fresh table immediately before the kill, so a pid
    # reissued since the scan is spared.
    for fc_p in $(same_pids "$fc_rows"); do
      kill -9 "$fc_p" 2>/dev/null
    done
    sleep 0.5
  done
  printf '%s\n' "$fc_seen"
  return 2
}

sig=''
# shellcheck disable=SC2329  # invoked by the EXIT trap
cleanup() {
  cl_rc=$?
  trap - EXIT INT TERM HUP
  # A reader that went away (`| head`) must not stop the cleanup half way.
  trap '' PIPE
  rmdir "$mk/hold" 2>/dev/null
  fc_rc=0
  leftover=$(final_check) || fc_rc=$?
  case $fc_rc in
    0) say "no process remains under the rehearsal root" ;;
    1)
      flunk exit "processes outlived the close and had to be killed at exit: $(printf '%s' "$leftover" | tr '\n' ' ')"
      ;;
    2)
      flunk exit "processes under the rehearsal root survive SIGKILL: $(printf '%s' "$leftover" | tr '\n' ' ')"
      ;;
    *) flunk exit "could not check for leftover processes: $leftover" ;;
  esac
  case $mk in
    */pw-rehearsal.?*) rm -rf "$mk" ;;
  esac
  if [ -n "$sig" ]; then
    say "INTERRUPTED by SIG$sig — not a pass" >&2
    kill -s "$sig" "$$"
    exit 1
  fi
  if [ "$cl_rc" != 0 ]; then
    say "ABORTED (exit $cl_rc) — the harness could not finish; not a pass" >&2
    exit "$cl_rc"
  fi
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

# --- static checks: the bundle is inert and the live run is opt-in ----------

# The bundle sits outside the spec root, so /orchestrate and the status render
# never enumerate it, and it is a Draft, so /orchestrate would still refuse a
# copy that strayed in. The rungs' own launch verbs do not read the status.
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

# The live run is its own mise task, and nothing `check` reaches through its
# dependency graph, nor any workflow, runs it.
mise_toml="$REPO_ROOT/mise.toml"
task_body=$(awk '
  /^\[tasks\."rehearsal:lifecycle"\]/ { on = 1; next }
  /^\[/ { on = 0 }
  on' "$mise_toml" 2>/dev/null)
case $task_body in
  *'tests/rehearsal-lifecycle.sh --live'*) pass static "the live rehearsal is its own opt-in mise task" ;;
  *) flunk static "mise.toml has no rehearsal:lifecycle task running tests/rehearsal-lifecycle.sh --live" ;;
esac
# Walk `depends`, `depends_post`, `wait_for` and `mise run <task>` in a body
# from `check`; a reached task that is the live task, or whose body runs it,
# fails. A line inside a multi-line string is body, never a table header.
# `test` must be reached, so a parse that found nothing cannot pass.
reach=$(awk '
  {
    probe = $0
    flips = gsub(/\047\047\047|"""/, "", probe)
    was_in = inml
    if (flips % 2) inml = !inml
  }
  !was_in && /^\[tasks\./ {
    cur = $0
    sub(/^\[tasks\./, "", cur)
    sub(/\][ \t]*$/, "", cur)
    gsub(/"/, "", cur)
    indep = 0
    next
  }
  !was_in && /^\[/ { cur = ""; next }
  cur == "" { next }
  # Prose naming a task is not a call to it.
  !was_in && /^[ \t]*description[ \t]*=/ { next }
  /rehearsal:lifecycle|rehearsal-lifecycle\.sh.*--live/ { live[cur] = 1 }
  # Every word after `mise run` / `mise r` up to a shell separator, flags
  # dropped and quotes stripped, is an edge: arguments that are not tasks
  # only add edges to nothing.
  {
    k = split($0, w, /[ \t]+/)
    for (i = 1; i <= k; i++) gsub(/["\047]/, "", w[i])
    for (i = 1; i < k; i++) {
      if (w[i] != "mise" || (w[i + 1] != "run" && w[i + 1] != "r")) continue
      for (j = i + 2; j <= k; j++) {
        if (w[j] == "&&" || w[j] == "||" || w[j] == ";" || w[j] == "|") break
        if (w[j] != "" && substr(w[j], 1, 1) != "-") dep[cur] = dep[cur] " " w[j]
      }
    }
  }
  !was_in && /^[ \t]*(depends|depends_post|wait_for)[ \t]*=/ { indep = 1 }
  indep {
    line = $0
    while (match(line, /"[^"]*"/)) {
      dep[cur] = dep[cur] " " substr(line, RSTART + 1, RLENGTH - 2)
      line = substr(line, RSTART + RLENGTH)
    }
    if (index($0, "]")) indep = 0
  }
  END {
    q[1] = "check"; seen["check"] = 1; n = 1
    for (i = 1; i <= n; i++) {
      m = split(dep[q[i]], d, " ")
      for (j = 1; j <= m; j++) if (!(d[j] in seen)) { seen[d[j]] = 1; q[++n] = d[j] }
    }
    if (!("test" in seen)) { print "parse-failed"; exit }
    for (t in seen) if (t == "rehearsal:lifecycle" || (t in live)) print t
  }' "$mise_toml" 2>/dev/null)
case $reach in
  '') pass static "nothing the check aggregate reaches runs the live rehearsal" ;;
  parse-failed) flunk static "could not walk the check aggregate's dependencies in mise.toml" ;;
  *) flunk static "the check aggregate reaches the live rehearsal through: $(printf '%s' "$reach" | tr '\n' ' ')" ;;
esac
wfl_hits=''
for wfl in "$REPO_ROOT"/.github/workflows/*; do
  [ -f "$wfl" ] || continue
  grep -Eq 'rehearsal:lifecycle|rehearsal-lifecycle\.sh[^#]*--live' "$wfl" && wfl_hits="$wfl_hits ${wfl##*/}"
done
if [ -z "$wfl_hits" ]; then
  pass static "no workflow runs the live rehearsal"
else
  flunk static "a workflow runs the live rehearsal:$wfl_hits"
fi

# --- the isolated world ------------------------------------------------------

mk=$(mktemp -d "${TMPDIR:-/tmp}/pw-rehearsal.XXXXXX") || exit 2
trap cleanup EXIT
trap 'sig=INT; exit 1' INT
trap 'sig=TERM; exit 1' TERM
trap 'sig=HUP; exit 1' HUP
# Assigned only on success: a failed substitution would otherwise leave the
# root empty for the exit trap's process scan.
mk_phys=$(cd "$mk" && pwd -P) || exit 2
mk=$mk_phys
# The root reaches a worker's prompt, awk -v and the cwd scan as one plain
# word.
case $mk in
  *[!A-Za-z0-9._/+-]*)
    echo "rehearsal: the temp root '$mk' has characters outside [A-Za-z0-9._/+-]; set TMPDIR to a plain path" >&2
    exit 2
    ;;
esac
mkdir -p "$mk/home" "$mk/headless" "$mk/adopter" "$mk/userhome" "$mk/bin" "$mk/gh-stub"

# The tree a stop is expected to end, as `<pid> TAB <start> TAB <argv>` rows
# gathered while the run goes, so the exit trap can reach a process that
# outlived its parent and no longer names the root. Kept in the harness's own
# memory: a file under the root is somewhere a live worker could write.
tracked=''

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
# Both give up after ten minutes, so a harness killed outright leaves nothing
# running for good.
cat >"$mk/bin/claude" <<'SHIM'
#!/bin/sh
case " $* " in
  *" --input-format "*)
    IFS= read -r _line || :
    sid=5e55e55e-0000-4000-8000-000000000012
    printf '%s\n' '{"type":"system","subtype":"init","cwd":"/x","session_id":"'$sid'","tools":[]}'
    printf '%s\n' '{"type":"control_request","request_id":"5e55e55e-0000-4000-8000-0000000000aa","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"'"$REHEARSAL_WEDGE"'"},"tool_use_id":"t1"}}'
    ;;
  *)
    cat >/dev/null
    cat "$REHEARSAL_FIFO" >/dev/null &
    held=$!
    ;;
esac
i=0
while [ -d "$REHEARSAL_HOLD" ] && [ "$i" -lt 600 ]; do
  sleep 1
  i=$((i + 1))
done
[ -n "${held:-}" ] && kill "$held" 2>/dev/null
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
  REHEARSAL_WEDGE="$WEDGE_CMD"
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

# wait_for <secs> <cmd...> — poll <cmd> until it holds or <secs> pass.
wait_for() {
  wf_end=$((SECONDS + $1))
  shift
  while [ "$SECONDS" -lt "$wf_end" ]; do
    "$@" && return 0
    sleep 0.2
  done
  "$@"
}

# --- per-rung helpers ---------------------------------------------------------

# The stream-json handle is a variable so the scripted skip path can launch a
# worker of its own, under a different handle, before the main one.
SJ_HANDLE=rehearsal-sj

handle_of() {
  case $1 in
    sj) printf '%s' "$SJ_HANDLE" ;;
    hl) printf 'headless-%s-task-%s' "$SPEC" "$UNIT" ;;
  esac
}

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

# rung_stop <rung> [stop args...] — the rung's `stop`, pinned on the headless
# rung to the unit directory this run created.
rung_stop() {
  rs_r=$1
  shift
  if [ "$rs_r" = hl ]; then
    hrun "$(script_of hl)" stop "$(handle_of hl)" --expect-dir "$(dir_of hl)" "$@"
  else
    hrun "$(script_of sj)" stop "$(handle_of sj)" "$@"
  fi
}

model_args() {
  [ "$LIVE" = 1 ] && printf '%s\n' -- --model "$MODEL"
}

write_prompt() {
  printf 'Rehearsal. Use the Bash tool to run exactly this command and nothing else: %s\nDo not use any other tool and do not explain.\n' \
    "$2" >"$1"
}

launch() {
  la_prompt="$mk/prompt-$1"
  case $1 in
    sj)
      write_prompt "$la_prompt" "$WEDGE_CMD"
      # shellcheck disable=SC2046  # model_args prints one argv word per line
      lrun fleet-streamjson.sh launch "$(handle_of sj)" "$SPEC:$UNIT" \
        --prompt-file "$la_prompt" --cwd "$repo" $(model_args) >"$mk/launch-$1.out" 2>&1
      ;;
    hl)
      write_prompt "$la_prompt" "$HOLD_CMD"
      # shellcheck disable=SC2046
      lrun fleet-dispatch-headless.sh launch "$SPEC" "$UNIT" --worktree "$repo" \
        --repo-root "$repo" $(model_args) <"$la_prompt" >"$mk/launch-$1.out" 2>&1
      ;;
  esac
}

# seeds_of <rung> — the pids the rung's state records, space-separated.
seeds_of() {
  case $1 in
    sj) cat "$(dir_of sj)/supervisor.pid" "$(dir_of sj)/worker.pid" 2>/dev/null | tr '\n' ' ' ;;
    hl) cat "$(dir_of hl)/pid" 2>/dev/null | tr '\n' ' ' ;;
  esac
}

# wedged <rung> — the positive evidence the worker reached its wedge.
wedged() {
  case $1 in
    sj)
      awk -F'\t' '$2 == "permission" && $4 == "pending"' "$(dir_of sj)/journal" 2>/dev/null | grep -q .
      ;;
    hl)
      we_seed=$(seeds_of hl)
      [ -n "$we_seed" ] || return 1
      descendants "$(proc_table)" "$we_seed" "$$" | awk -F'\t' -v cmd="$HOLD_CMD" \
        'index($4, cmd) { f = 1 } END { exit f ? 0 : 1 }'
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

# session_started <rung> — positive evidence a session came up. Only the
# stream-json rung records one (the init event's session id).
session_started() {
  [ "$1" = sj ] && [ -s "$(dir_of sj)/session" ]
}

# A run that ended in an error before any session came up never had a working
# session (no login, no network, a refused model): that is the skip. One that
# ended any other way without wedging is a worker that was not held, and that
# is a failure.
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

# shellcheck disable=SC2329  # polled through wait_for
wedge_or_end() {
  wedged "$1" || ended "$1"
}

# wedge_verdict <rung> — after the wait: `wedged`, `skip <why>` when no live
# session was ever established, or `fail <why>`.
wedge_verdict() {
  if wedged "$1"; then
    echo wedged
  elif ended "$1" && ended_in_error "$1" && ! session_started "$1"; then
    echo "skip no live session could be established: $(ended_detail "$1")"
  elif ended "$1"; then
    echo "fail the worker finished without being wedged: $(ended_detail "$1")"
  elif session_started "$1"; then
    echo "fail the session started but the worker did not wedge within ${WAIT}s"
  else
    echo "skip no live session within ${WAIT}s: the worker neither wedged nor ended"
  fi
}

# snapshot_tree <rung> — `<pid> TAB <start> TAB <argv>` for the rung's tree,
# from one read of the process table. A recorded pid seeds it only while its
# argv names the root: a pid file outlives its process, and the pid may be
# someone else's by now.
snapshot_tree() {
  st_table=$(proc_table)
  st_seed=$(printf '%s\n' "$st_table" | awk -F'\t' -v want=" $(seeds_of "$1") " -v r="$mk" \
    'index(want, " " $1 " ") && index($4, r) { printf "%s ", $1 }')
  descendants "$st_table" "$st_seed" "$$" | cut -f1,3,4
}

# worker_alive <rung> — true while the worker itself, as snapshotted at the
# wedge, is still the same process: the stream-json worker pid, or the
# headless hold command.
worker_alive() {
  case $1 in
    sj) wa_key=$(cat "$(dir_of sj)/worker.pid" 2>/dev/null) ;;
    hl) wa_key='' ;;
  esac
  [ -n "$(same_pids "$(printf '%s\n' "$2" | awk -F'\t' -v k="$wa_key" -v cmd="$HOLD_CMD" \
    '(k != "" && $1 == k) || (k == "" && index($3, cmd))')")" ]
}

detector_state() {
  hrun fleet-stuck-detector.sh classify "$(handle_of "$1")" --tower-id "$TOWER_ID" 2>/dev/null \
    | awk -F'\t' '$1 == "worker" { print $3 "\t" $6; exit }'
}

# sweep — one cycle; sets sw_rc, sw_out, sw_err.
sweep() {
  sw_rc=0
  hrun fleet-sweep.sh --repo "$repo" --tower-id "$TOWER_ID" >"$mk/sweep.out" 2>"$mk/sweep.err" || sw_rc=$?
  sw_out=$(cat "$mk/sweep.out")
  sw_err=$(cat "$mk/sweep.err")
}

sweep_mode() {
  printf '%s\n' "$sw_out" | awk -F'\t' '$1 == "summary" { sub(/^mode=/, "", $2); print $2; exit }'
}

# sweep_scanned — the cycle read its stores and saw at least one worker; a
# degraded or empty scan would leave every "left alone" check vacuous.
sweep_scanned() {
  printf '%s\n' "$sw_out" | awk -F'\t' '$1 == "summary" {
      for (i = 2; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }
      ok = (v["status"] == "ok" && v["workers"] + 0 >= 1)
    }
    END { exit ok ? 0 : 1 }'
}

# sweep_reap <handle> — the reap outcome the cycle printed for the worker, if
# it made the worker a candidate at all.
sweep_reap() {
  printf '%s\n' "$sw_out" | awk -F'\t' -v w="$1" '$1 == "reap" && $2 == w { print $3; exit }'
}

# sweep_took <handle> — the reap outcome when the cycle closed the worker or
# would have.
sweep_took() {
  case $(sweep_reap "$1") in
    reaped | partial | observed | unrecorded) sweep_reap "$1" ;;
  esac
}

# held_classes <rung> <tree-rows> — the release-set classes still held.
held_classes() {
  hc_d=$(dir_of "$1")
  hc_w=$(handle_of "$1")
  hc_out=''
  if [ "$(pids_under "$hc_d")" != '' ] || [ -n "$(same_pids "$2")" ]; then
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

# worktree_state — what a close must leave as it found it: every tracked and
# untracked path's status, a checksum of the tracked changes, and each
# untracked file's checksum. Empty when git cannot read the tree, which the
# caller treats as a change.
worktree_state() {
  ws_status=$(git -C "$repo" status --porcelain --untracked-files=all 2>/dev/null) || return 0
  ws_diff=$(git -C "$repo" diff HEAD --binary 2>/dev/null | cksum) || return 0
  ws_untracked=$(cd "$repo" && git ls-files -oz --exclude-standard 2>/dev/null | xargs -0 cksum -- 2>/dev/null) || return 0
  printf 'status:\n%s\ndiff: %s\nuntracked:\n%s\n' "$ws_status" "$ws_diff" "$ws_untracked"
}

# --- the lifecycle, one rung at a time ----------------------------------------

rehearse() {
  r=$1
  w=$(handle_of "$r")

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
  verdict=$(wedge_verdict "$r")
  case $verdict in
    wedged) ;;
    skip\ *)
      skip "$r" "${verdict#skip }"
      rung_stop "$r" --grace 2 >/dev/null 2>&1
      return
      ;;
    *)
      flunk "$r" "${verdict#fail }"
      rung_stop "$r" --grace 2 >/dev/null 2>&1
      return
      ;;
  esac
  case $r in
    sj) pass "$r" "the worker is wedged on a pending permission request ($WEDGE_CMD)" ;;
    hl) pass "$r" "the worker is held mid-command ($HOLD_CMD)" ;;
  esac
  tree=$(snapshot_tree "$r")
  tracked=$(printf '%s\n%s\n' "$tracked" "$tree" | awk 'NF')

  # 3. classify the running worker
  cls=$(detector_state "$r")
  state=${cls%%"$TAB"*}
  reason=${cls#*"$TAB"}
  case $r:$state in
    sj:waiting-on-a-human) pass "$r" "the detector classifies the wedged worker waiting-on-a-human (reason: $reason)" ;;
    sj:*) flunk "$r" "the detector classifies the wedged worker '$state' (reason: $reason), not waiting-on-a-human" ;;
    hl:dead | hl:finished-but-unreaped | hl: | hl:unclassified)
      # An unclassified completion is a sweep candidate, so it is as wrong for
      # a held worker as finished is.
      case $state:$reason in
        unclassified:completion-*) flunk "$r" "the detector reads a held, live worker as a completion (reason: $reason)" ;;
        unclassified:*)
          pass "$r" "the detector does not read the held worker as dead or finished (state: $state, reason: $reason)"
          na "$r" "waiting-on-a-human: headless-oneshot has no pend path; an unapproved ask fails under --print instead of waiting"
          ;;
        *) flunk "$r" "the detector classifies a held, live worker '$state' (reason: $reason)" ;;
      esac
      ;;
    hl:*)
      pass "$r" "the detector does not read the held worker as dead or finished (state: $state, reason: $reason)"
      na "$r" "waiting-on-a-human: headless-oneshot has no pend path; an unapproved ask fails under --print instead of waiting"
      ;;
  esac
  if [ "$r" = hl ]; then
    st_out=$(hrun "$(script_of hl)" status "$SPEC" "$UNIT" 2>/dev/null)
  else
    st_out=$(hrun "$(script_of sj)" status "$w" 2>/dev/null)
  fi
  case $r:$st_out in
    sj:"status $w awaiting-input"*) pass "$r" "the rung's own status reads awaiting-input" ;;
    hl:"running "*) pass "$r" "the rung's own status reads running" ;;
    *) flunk "$r" "the rung's own status reads '$(clip "$st_out")'" ;;
  esac

  # 4. both sweep modes, while the worker is still held
  # A held worker must not even be a reap candidate.
  rm -f "$machine_local"
  sweep
  took=$(sweep_reap "$w")
  if [ "$sw_rc" = 0 ] && sweep_scanned && [ "$(sweep_mode)" = observe ] && [ -z "$took" ] \
    && worker_alive "$r" "$tree"; then
    pass "$r" "an observing sweep leaves the held worker alone"
  else
    flunk "$r" "observing sweep: exit $sw_rc, mode '$(sweep_mode)', outcome '$took', $(clip "$sw_out $sw_err")"
  fi
  mkdir -p "$repo/.claude"
  printf 'fleet_sweep_reap: terminate\n' >"$machine_local"
  sweep
  took=$(sweep_reap "$w")
  # The terminate knob must have been read: either honored, or refused with
  # the sweep saying so. A second silent observing cycle exercises nothing.
  case $sw_rc:$(sweep_mode):$sw_err in
    0:terminate:*) term_read='honored' ;;
    0:observe:*'terminate is refused'*) term_read='refused for now, so the cycle observed and said why' ;;
    *) term_read='' ;;
  esac
  if [ -n "$term_read" ] && sweep_scanned && [ -z "$took" ] && worker_alive "$r" "$tree"; then
    pass "$r" "a terminating sweep leaves the held worker alone (terminate $term_read)"
  else
    flunk "$r" "terminating sweep: exit $sw_rc, mode '$(sweep_mode)', outcome '$took', terminate read: ${term_read:-no}, $(clip "$sw_err")"
  fi
  rm -f "$machine_local"

  # 5. stop, then the release set, checked independently of what stop said.
  # Each class the rung should hold must be held first, or its emptiness after
  # the close proves nothing.
  before=$(held_classes "$r" "$tree")
  case $r in
    sj) want='process scratch attention' ;;
    hl) want='process' ;;
  esac
  missing=''
  for c in $want; do
    case " $before " in
      *" $c "* | *" $c:"*) ;;
      *) missing="$missing $c" ;;
    esac
  done
  if [ -z "$missing" ]; then
    pass "$r" "before the close the worker holds: $before"
  else
    flunk "$r" "before the close the worker does not hold:$missing (held: $before)"
  fi
  wt_before=$(worktree_state)
  stop_rc=0
  stop_out=$(rung_stop "$r" --grace 5 2>&1) || stop_rc=$?
  case $stop_rc:$stop_out in
    "0:stop $w stopped released="*) pass "$r" "stop closes the worker ($(clip "${stop_out#stop "$w" }"))" ;;
    *) flunk "$r" "stop exited $stop_rc: $(clip "$stop_out")" ;;
  esac
  held=''
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    held=$(held_classes "$r" "$tree")
    [ -z "$held" ] && break
    sleep 0.5
  done
  if [ -z "$held" ]; then
    pass "$r" "after the close every class of the release set is empty"
  else
    flunk "$r" "the release set still holds: $held"
  fi
  na "$r" "tmux window: this rung runs no window"
  wt_after=$(worktree_state)
  if [ -d "$repo/.git" ] && [ "$(git -C "$repo" rev-parse HEAD 2>/dev/null)" = "$head_before" ] \
    && [ "$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null)" = main ] \
    && [ -r "$repo/specs/$SPEC/tasks.md" ] \
    && [ -n "$wt_before" ] && [ "$wt_after" = "$wt_before" ]; then
    pass "$r" "the worktree, its branch and the bundle are untouched"
  else
    flunk "$r" "the worktree, branch or bundle changed under the close"
  fi
  again_rc=0
  again=$(rung_stop "$r" 2>&1) || again_rc=$?
  if [ "$again_rc" = 0 ] && [ "$again" = "stop $w already-closed" ]; then
    pass "$r" "a repeat stop answers already-closed"
  else
    flunk "$r" "a repeat stop exited $again_rc: $(clip "$again")"
  fi

  # 6. post-close: a sweep and an observing stop find nothing held
  sweep
  took=$(sweep_took "$w")
  obs=$(rung_stop "$r" --observe 2>&1)
  if [ "$sw_rc" = 0 ] && sweep_scanned && [ -z "$took" ] && [ "$obs" = "stop $w already-closed" ] \
    && [ -z "$(held_classes "$r" "$tree")" ]; then
    pass "$r" "a post-close sweep finds nothing held"
  else
    flunk "$r" "post-close: sweep exit $sw_rc outcome '$took', observe '$(clip "$obs")', held '$(held_classes "$r" "$tree")', $(clip "$sw_out")"
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
      # Removing the CLI's PATH entries also removed a tool the harness needs
      # (jq, or coreutils when the CLI sits in /usr/bin): this check cannot run.
      # Any other exit 2, a usage error included, is a broken entry point.
      2:*'jq is required'* | 2:*'missing or not executable'*) na skip-path "--live without a CLI: the CLI shares a PATH entry with a tool the harness needs: $(clip "$sp_out")" ;;
      *) flunk skip-path "--live without a CLI exited $sp_rc: $(clip "$sp_out")" ;;
    esac
  fi

  # One rung: a CLI that fails before its session starts. The verdict must be
  # the recognised no-session skip, not the timeout one a launch that never
  # happened would also produce.
  SJ_HANDLE=rehearsal-nosession
  sp_cli=(${cli[@]+"${cli[@]}"})
  cli=(PLANWRIGHT_STREAMJSON_CLI="$mk/bin/claude-nosession")
  sp_rc=0
  launch sj || sp_rc=$?
  if [ "$sp_rc" != 0 ]; then
    flunk skip-path "the no-session worker's launch exited $sp_rc: $(clip "$(cat "$mk/launch-sj.out")")"
  else
    sp_wait=$WAIT
    WAIT=30
    wait_for "$WAIT" wedge_or_end sj
    sp_verdict=$(wedge_verdict sj)
    WAIT=$sp_wait
    case $sp_verdict in
      'skip no live session could be established:'*)
        pass skip-path "a worker whose session never starts is reported as a skip, not a pass"
        ;;
      *) flunk skip-path "a worker whose session never starts read as: $(clip "$sp_verdict")" ;;
    esac
  fi
  rung_stop sj --grace 2 >/dev/null 2>&1
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
exit 0
