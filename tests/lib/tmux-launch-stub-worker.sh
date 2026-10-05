#!/bin/sh
# tmux-launch-stub-worker.sh — the stub worker CLI (`claude`) of the launch
# fixture harness (tests/lib/tmux-launch-harness.sh installs a `claude` shim
# that execs this with the stub state directory and the plugin root first).
# Never run directly.
#
# On start it snapshots its environment before changing anything (the shell
# running it may still add PWD), then confirms its launch the way a real
# worker does: it fires the plugin's liveness hook,
# `<plugin root>/scripts/fleet-liveness.sh hook session-start`, in its OWN
# environment (so the handle, scope, and launch token the hook reads are
# whatever the launch actually delivered), with a SessionStart payload whose
# source is `resume` when its flags (the words before any `--`) carry
# --continue, -c, --resume[=...], or -r[=...], and `startup` otherwise. Until that hook accepts the session-start event it
# refuses the push, and the record shows the hook's exit status. Writing
# `<state>/knobs/worker-confirm` = off skips the hook.
#
# It then writes one record, <state>/workers/<seq>, atomically (temp name,
# then rename): tab-separated `pid`, `cwd` (physical), `argv` (one field per
# word), `confirm` (`off`, or the hook's exit status and the launch token it
# saw), and one `env` line per line of its environment as `env` prints it (a
# value holding a newline spans several). Finally it keeps
# running like a worker, or exits with the status in
# `<state>/knobs/worker-exit` when that holds a number. Its pid is recorded
# under <state>/pids/ for the harness's reaper.
env_snapshot=$(env)

STUB_STATE=$1
PLUGIN_ROOT=$2
shift 2
# shellcheck source=tests/lib/tmux-launch-stub-common.sh
. "${0%/*}/tmux-launch-stub-common.sh"

stub_record_pid "$$"
stub_claim_seq worker || {
  echo "stub worker: cannot claim a record sequence number under $STUB_STATE" >&2
  exit 70
}
id=$STUB_SEQ

stub_knob worker-confirm on
if [ "$STUB_KNOB" = off ]; then
  confirm=off
else
  start_source=startup
  for a; do
    case $a in
      --) break ;;
      --continue | -c | --resume | --resume=* | -r | -r=*) start_source=resume ;;
    esac
  done
  printf '{"hook_event_name":"SessionStart","source":"%s"}\n' "$start_source" \
    | CLAUDE_PLUGIN_ROOT=$PLUGIN_ROOT "$PLUGIN_ROOT/scripts/fleet-liveness.sh" hook session-start \
      >/dev/null 2>"$STUB_STATE/workers/$id.confirm.err"
  hook_rc=$?
  confirm="$hook_rc${STUB_TAB}${PLANWRIGHT_WORKER_LAUNCH_TOKEN-}"
fi

argv_line='argv'
for a; do argv_line="$argv_line${STUB_TAB}$a"; done
stub_write_file "$STUB_STATE/workers/$id" "pid${STUB_TAB}$$
cwd${STUB_TAB}$(pwd -P)
$argv_line
confirm${STUB_TAB}$confirm
$(printf '%s\n' "$env_snapshot" | awk '{ print "env\t" $0 }')
"

stub_knob worker-exit run
case $STUB_KNOB in
  '' | *[!0-9]*) exec sleep 600 ;;
  *) exit "$STUB_KNOB" ;;
esac
