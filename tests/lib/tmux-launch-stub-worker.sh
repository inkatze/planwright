#!/bin/sh
# tmux-launch-stub-worker.sh — the stub worker CLI (`claude`) of the launch
# fixture harness (tests/lib/tmux-launch-harness.sh installs a `claude` shim
# that execs this with the harness state directory and the plugin root first).
# Never run directly.
#
# On start it confirms its launch the way a real worker does: it fires the
# plugin's SessionStart liveness hook in its OWN environment (so the handle,
# scope, and launch token that hook reads are whatever the launch actually
# delivered to the worker process), with a SessionStart payload whose source
# is `resume` when its argv carries --continue/--resume and `startup`
# otherwise. Writing `<state>/knobs/worker-confirm` = off skips that.
#
# It then writes one record, <state>/workers/<seq>, atomically (temp name,
# then rename): tab-separated `pid`, `cwd` (physical), `argv` (one field per
# word), `confirm` (`off`, or the hook's exit status and the launch token it
# saw), and one `env` line per variable of its environment. Finally it keeps
# running like a worker, or exits with the status in
# `<state>/knobs/worker-exit` when that holds a number. Its pid is recorded as
# <state>/pids/<pid> for the harness's reaper.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

S=$1
P=$2
shift 2

# The hook event this stub fires to confirm its launch.
CONFIRM_EVENT=session-start

# claim_seq <kind> — as in tmux-launch-stub-tmux.sh, which this must match.
claim_seq() {
  [ -d "$S/seq" ] || return 1
  cs_kind=$1
  set -- "$S/seq/$cs_kind".*
  cs_n=$#
  [ -e "$1" ] || cs_n=0
  cs_n=$((cs_n + 1))
  while [ "$cs_n" -lt 1000000 ]; do
    cs_id=$(printf '%06d' "$cs_n")
    if mkdir "$S/seq/$cs_kind.$cs_id" 2>/dev/null; then
      printf '%s\n' "$cs_id"
      return 0
    fi
    cs_n=$((cs_n + 1))
  done
  return 1
}

knob() {
  if [ -r "$S/knobs/$1" ]; then
    IFS= read -r kv_val <"$S/knobs/$1" || true
    printf '%s\n' "${kv_val:-$2}"
  else
    printf '%s\n' "$2"
  fi
}

: >"$S/pids/$$"
id=$(claim_seq worker) || {
  echo "stub worker: cannot claim a record sequence number under $S" >&2
  exit 70
}

if [ "$(knob worker-confirm on)" = off ]; then
  confirm='off'
else
  source=startup
  for a; do
    case $a in --continue | --resume | --resume=*) source=resume ;; esac
  done
  printf '{"hook_event_name":"SessionStart","source":"%s"}\n' "$source" \
    | CLAUDE_PLUGIN_ROOT=$P "$P/scripts/fleet-liveness.sh" hook "$CONFIRM_EVENT" \
      >/dev/null 2>"$S/workers/$id.confirm.err"
  confirm="$?	${PLANWRIGHT_WORKER_LAUNCH_TOKEN-}"
fi

tmp="$S/workers/.tmp.$$"
{
  printf 'pid\t%s\n' "$$"
  printf 'cwd\t%s\n' "$(pwd -P)"
  printf 'argv'
  for a; do printf '\t%s' "$a"; done
  printf '\n'
  printf 'confirm\t%s\n' "$confirm"
  env | awk '{ print "env\t" $0 }'
} >"$tmp" && mv "$tmp" "$S/workers/$id"

case $(knob worker-exit run) in
  run) exec sleep 600 ;;
  *[!0-9]*) exec sleep 600 ;;
  *) exit "$(knob worker-exit run)" ;;
esac
