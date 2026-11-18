#!/bin/bash
# Tests for scripts/mc-stall.sh's orphans verb: a stream-json supervisor or
# `claude -p` worker nothing can reach any more (its state directory gone or
# naming another supervisor, its working directory gone, or a worker with no
# supervisor and no fleet record) is listed, and never signalled.
#
# The processes are real: stand-in scripts named as the launcher and the CLI,
# so their command lines take the shape a real pair has. Each ends itself once
# this suite is gone.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/mc-stall-orphans.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
started=''
cleanup() {
  for p in $started; do kill "$p" 2>/dev/null; done
  rm -rf "$tmp"
}
trap cleanup EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"
reset_mc_fixture

fx="$tmp/fx"
mkdir -p "$fx/scripts" "$fx/bin"
# The supervisor stand-in: `_supervise <worker> <dir> <init> <claude argv...>`
# (or `launch <worker> <scope> --foreground <claude argv...>`) starts the
# worker as its child, as the real one does; FIXTURE_FORK also starts a fork
# that keeps the `_supervise` argv, as a real supervisor's subshells do.
cat >"$fx/scripts/fleet-streamjson.sh" <<'EOF'
#!/bin/sh
case $1 in
  _supervise | launch | status)
    [ -z "${FIXTURE_FORK:-}" ] || FIXTURE_FORK='' /bin/sh "$0" _supervise "$2" "$3" "$4" &
    shift 4
    ;;
esac
[ "$#" -eq 0 ] || "$@" &
while kill -0 "$FIXTURE_OWNER" 2>/dev/null; do sleep 1; done
EOF
cat >"$fx/bin/claude" <<'EOF'
#!/bin/sh
while kill -0 "$FIXTURE_OWNER" 2>/dev/null; do sleep 1; done
EOF
chmod +x "$fx/scripts/fleet-streamjson.sh" "$fx/bin/claude"
export FIXTURE_OWNER=$$

# start_pair <worker> <state dir> <cwd>: a supervisor and its worker, run
# from <cwd>; sets SUP to the supervisor's pid.
start_pair() {
  mkdir -p "$3"
  (cd "$3" && exec /bin/sh "$fx/scripts/fleet-streamjson.sh" _supervise "$1" "$2" "$2/.init" \
    "$fx/bin/claude" -p --input-format stream-json --output-format stream-json --name "$1" --resume fixture-session) &
  SUP=$!
  started="$started $SUP"
}
# start_bare <worker> <cwd> [<input format>]: a worker with no supervisor;
# sets BARE.
start_bare() {
  mkdir -p "$2"
  (cd "$2" && exec /bin/sh "$fx/bin/claude" -p --input-format "${3:-stream-json}" --output-format stream-json --name "$1") &
  BARE=$!
  started="$started $BARE"
}
# proc_args <pid>: the process's argv, read from procfs where there is one,
# since busybox's ps takes no -p and cuts argv short.
proc_args() {
  if [ -r "/proc/$1/cmdline" ]; then
    tr '\000' ' ' <"/proc/$1/cmdline"
  else
    ps -ww -o args= -p "$1"
  fi
}
# child_with <ppid> <needle>: a child of <ppid> whose argv holds <needle>.
child_with() {
  for cw in $(ps -A -o pid= -o ppid= | awk -v p="$1" '$2 == p { print $1 }'); do
    case $(proc_args "$cw" 2>&1) in *"$2"*)
      printf '%s\n' "$cw"
      return 0
      ;;
    esac
  done
  return 1
}
# wait_exec <pid> <needle>: wait until the process runs the command line the
# case started, so no check races its exec.
wait_exec() {
  we_i=0
  while [ "$we_i" -lt 100 ]; do
    case $(proc_args "$1" 2>&1) in *"$2"*) return 0 ;; esac
    sleep 0.1
    we_i=$((we_i + 1))
  done
  fail "pid $1 never ran $2"
}
# child_of <pid>: the worker the supervisor started, once it is up.
child_of() {
  co_i=0
  while [ "$co_i" -lt 50 ]; do
    # The stand-in's own sleep is a child too; the worker is the CLI one.
    if co=$(child_with "$1" bin/claude); then
      printf '%s\n' "$co"
      return 0
    fi
    sleep 0.1
    co_i=$((co_i + 1))
  done
  return 1
}
orphan_row() { # orphan_row <pid>: the listing's row for that pid
  printf '%s\n' "$OUT" | awk -F '\t' -v p="$1" '$1 == "orphan" && $2 == p'
}

# The incident's shape: a suite killed before its cleanup, its scratch tree
# then removed, the supervisor's state directory and working directory with it.
gone_dir="$tmp/gone/fleet/streamjson/mc-alpha-tower-orphan"
mkdir -p "$gone_dir"
start_pair mc-alpha-tower-orphan "$gone_dir" "$tmp/gone/repo"
gone_sup=$SUP
gone_worker=$(child_of "$gone_sup") || fail "the orphaned supervisor started no worker"
# A healthy pair: its directory records it and its working directory stands.
# Its fork, which keeps the supervisor's argv, belongs to it.
live_dir="$fleet/streamjson/mc-alpha-worker-live"
mkdir -p "$live_dir"
FIXTURE_FORK=1 start_pair mc-alpha-worker-live "$live_dir" "$tmp/live-cwd"
live_sup=$SUP
printf '%s\n' "$live_sup" >"$live_dir/supervisor.pid"
live_worker=$(child_with "$live_sup" bin/claude)
fe_i=0
while [ -z "$live_worker" ] && [ "$fe_i" -lt 50 ]; do
  sleep 0.1
  fe_i=$((fe_i + 1))
  live_worker=$(child_with "$live_sup" bin/claude)
done
[ -n "$live_worker" ] || fail "the healthy supervisor started no worker"
live_fork=$(child_with "$live_sup" _supervise)
[ -n "$live_fork" ] || fail "the healthy supervisor started no fork"
# A worker a foreground launch supervises from the launch process.
(cd "$tmp/live-cwd" && exec /bin/sh "$fx/scripts/fleet-streamjson.sh" launch mc-alpha-worker-fg fg-scope --foreground \
  "$fx/bin/claude" -p --input-format stream-json --output-format stream-json --name mc-alpha-worker-fg) &
fg_launch=$!
started="$started $fg_launch"
fg_worker=$(child_of "$fg_launch") || fail "the foreground launch started no worker"
# A worker under a process that only names the launcher supervises nothing.
(cd "$tmp/live-cwd" && exec /bin/sh "$fx/scripts/fleet-streamjson.sh" status mc-alpha-worker-st st-scope -- \
  "$fx/bin/claude" -p --input-format stream-json --output-format stream-json --name mc-alpha-worker-st) &
st_parent=$!
started="$started $st_parent"
st_worker=$(child_of "$st_parent") || fail "the status stand-in started no worker"
# A second supervisor over a directory that records another one.
dup_dir="$fleet/streamjson/mc-alpha-worker-dup"
mkdir -p "$dup_dir"
start_pair mc-alpha-worker-dup "$dup_dir" "$tmp/live-cwd"
dup_sup=$SUP
printf '%s\n' "$live_sup" >"$dup_dir/supervisor.pid"
# A worker whose supervisor is gone and that no fleet record names; one the
# fleet home still records; and a `claude -p` that is no stream-json worker.
start_bare mc-alpha-worker-bare "$tmp/live-cwd"
bare=$BARE
mkdir -p "$fleet/streamjson/mc-alpha-worker-known"
start_bare mc-alpha-worker-known "$tmp/live-cwd"
known=$BARE
start_bare mc-alpha-worker-text "$tmp/live-cwd" text
plain=$BARE
wait_exec "$dup_sup" mc-alpha-worker-dup
for p in "$bare" "$known" "$plain"; do wait_exec "$p" "bin/claude -p"; done
rm -rf "$tmp/gone"

# The fixture empties the process table; these processes are real.
OUT=$(mc_env env -u PLANWRIGHT_MC_PROC_ROOT /bin/bash "$repo_root/scripts/mc-stall.sh" orphans 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "orphans lists" 0
row=$(orphan_row "$gone_sup")
case $row in
  *"${tab}supervisor${tab}mc-alpha-tower-orphan${tab}"*) ok "a supervisor whose state directory is gone is listed, with its worker" ;;
  *) fail "the orphaned supervisor $gone_sup is not listed as one: $OUT" ;;
esac
case $row in *"state directory"*"is gone"*) ok "the reason names the state directory" ;; *) fail "the reason does not name the gone state directory: $row" ;; esac
case $row in *"working directory"*"is gone"*) ok "the reason names the working directory" ;; *) fail "the reason does not name the gone working directory: $row" ;; esac
case $row in *"worker pid $gone_worker"*) ok "the reason names the worker it holds" ;; *) fail "the reason does not name worker $gone_worker: $row" ;; esac
unlisted() { # unlisted <pid> <label>
  if [ -z "$(orphan_row "$1")" ]; then
    ok "$2"
  else
    fail "$2: $(orphan_row "$1")"
  fi
}
unlisted "$gone_worker" "a supervised worker is reported through its supervisor"
unlisted "$live_sup" "a supervisor its directory records is not listed"
unlisted "$live_worker" "a supervised worker of a healthy pair is not listed"
unlisted "$live_fork" "a supervisor's fork that keeps its argv is not listed"
unlisted "$fg_worker" "a worker a foreground launch supervises is not listed"
unlisted "$plain" "a claude -p that is no stream-json worker is not listed"
case $(orphan_row "$st_worker") in
  *"${tab}claude${tab}mc-alpha-worker-st${tab}"*"no supervisor"*) ok "a worker whose parent only names the launcher is listed" ;;
  *) fail "the worker $st_worker under a non-launching parent is not listed: $OUT" ;;
esac
case $(orphan_row "$known") in
  *"no supervisor"*"no fleet record"*) fail "a worker the fleet home records was said to have no record" ;;
  *"${tab}claude${tab}mc-alpha-worker-known${tab}"*"no supervisor"*) ok "a worker with no supervisor is listed, its fleet record noted" ;;
  *) fail "the unsupervised recorded worker $known is not listed: $OUT" ;;
esac
case $(orphan_row "$dup_sup") in
  *"records supervisor $live_sup"*) ok "a supervisor its directory does not record is listed" ;;
  *) fail "the unrecorded supervisor $dup_sup is not listed: $OUT" ;;
esac
case $(orphan_row "$bare") in
  *"${tab}claude${tab}mc-alpha-worker-bare${tab}"*"no supervisor"*"no fleet record"*) ok "a worker with no supervisor and no fleet record is listed" ;;
  *) fail "the bare worker $bare is not listed as one: $OUT" ;;
esac

for p in "$gone_sup" "$gone_worker" "$dup_sup" "$bare"; do
  if kill -0 "$p" 2>/dev/null; then
    ok "listing left pid $p running"
  else
    fail "listing signalled pid $p"
  fi
done

mc_run mc-stall.sh orphans
expect_rc "orphans over the fixture's empty process table" 0
if [ -z "$OUT" ]; then
  ok "a moved process table that is empty lists nothing"
else
  fail "the empty process table listed: $OUT"
fi

mc_run mc-stall.sh orphans --program
expect_rc "orphans takes no program" 2

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "ALL mc-stall orphans tests passed"
