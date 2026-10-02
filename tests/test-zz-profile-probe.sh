#!/bin/bash
# Temporary profiling probe for the slow-test profile; removed before merge.
#
# A no-op (one ok line) everywhere except the opt-in test-timing workflow on a
# Linux GitHub runner, where measure-test-time.sh runs every file serially and
# so leaves the runner otherwise idle while this file runs. There it measures
# launch costs, then runs each candidate file under a process-table sampler
# that charges wall-clock to production scripts, sleeps, waits, and test-side
# work, and counts forks from /proc/stat. A passing file's output is
# discarded by the measuring script, so the report goes to that script's
# stderr, which is the job log.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

if [ "${GITHUB_WORKFLOW:-}" != test-timing ] || [ "$(uname -s)" != Linux ]; then
  echo "ok: profile probe is a no-op outside the test-timing workflow"
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

out=/dev/null
p=$PPID
while [ "$p" -gt 1 ] 2>/dev/null; do
  if tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null | grep -q 'measure-test-time\.sh'; then
    out="/proc/$p/fd/2"
    break
  fi
  p=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null) || break
done
emit() { printf 'PROFILE-PROBE %s\n' "$*" >>"$out"; }

work="$(mktemp -d "${TMPDIR:-/tmp}/profile-probe.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT

cat >"$work/prof.sh" <<'PROF'
#!/usr/bin/env bash
# Sampling attribution profiler for one test file (bash 4+ harness; the test
# itself runs under /bin/bash like run-tests.sh). Every ~interval it snapshots
# the process table, keeps the test's descendants, and charges the elapsed
# slice to one class:
#   prod_run   a production script (scripts/, hooks/, githooks/) alive, some descendant runnable
#   prod_wait  a production script alive, nothing runnable
#   prod_sleep a production script alive, nothing runnable, a `sleep` alive
#   t_sleep    no production script, nothing runnable, a `sleep` alive
#   t_wait     no production script, nothing runnable, no sleep (waits, exec stalls)
#   t_run      no production script; test-side work runnable (fixture setup, assertions, launches)
# It also charges each slice to the top-level production scripts alive in it,
# split evenly, and on Linux counts forks per class from /proc/stat's
# `processes` counter, net of the sampler's own (SAMPLER_FORKS per tick).
# Usage: prof.sh <test-file> [interval-seconds]   (run from the repo root)
# Output: one key=value line on stdout.
set -u
LC_ALL=C
export LC_ALL
t=$1
iv=${2:-0.1}
name=${t##*/}
if [ "$(uname -s)" = Darwin ]; then
  ps_cmd=(ps -A -o pid=,ppid=,stat=,command=)
else
  ps_cmd=(ps -e -o pid=,ppid=,stat=,args=)
fi
per_tick=${SAMPLER_FORKS:-4}
prod_names=$(cd scripts 2>/dev/null && ls *.sh | tr '\n' ' ')
FK=0
forks() {
  FK=0
  [ -r /proc/stat ] || return 0
  local k v
  while read -r k v _; do
    if [ "$k" = processes ]; then FK=$v; return 0; fi
  done </proc/stat
}
US=0
us() { local v=${EPOCHREALTIME/./}; US=$((10#$v)); }
sec() { printf '%d.%02d' $(($1 / 1000000)) $((($1 % 1000000) / 10000)); }

declare -A cls_t cls_f script_t
for c in prod_run prod_wait prod_sleep t_sleep t_wait t_run; do cls_t[$c]=0; cls_f[$c]=0; done
ticks=0

forks; f0=$FK
us; start=$US
SPEC_WALKTHROUGH_DOT_TIMEOUT="${SPEC_WALKTHROUGH_DOT_TIMEOUT:-60}" /bin/bash "$t" >/dev/null 2>&1 &
tp=$!
prev=$start
pf=$f0
while kill -0 "$tp" 2>/dev/null; do
  res=$("${ps_cmd[@]}" 2>/dev/null | awk -v root="$tp" -v names="$prod_names" '
    BEGIN { nn=split(names, nm, " "); for (i=1;i<=nn;i++) NAMES[nm[i]]=1 }
    {
      pid=$1; ppid=$2; st=$3; $1=$2=$3=""; cmd=substr($0,4)
      P[pid]=ppid; S[pid]=st; C[pid]=cmd; n++; ids[n]=pid
    }
    function isprod(c,   a, k, j, b) {
      # A production script is the interpreter-run or directly-run file: one of
      # the first two words, under scripts/ hooks/ githooks/, or a copy whose
      # basename is a repository script (tests copy scripts/*.sh into stub dirs).
      k=split(c, a, " ")
      for (j=1; j<=k && j<=2; j++) {
        if (a[j] ~ /(^|\/)(scripts|hooks|githooks)\/[A-Za-z0-9._-]+$/) return 1
        b=a[j]; sub(/.*\//, "", b); if (b in NAMES) return 1
      }
      return 0
    }
    function desc(p,   q, k) { q=p; for (k=0; k<64 && q!="" && q>1; k++) { if (q==root) return 1; q=P[q] } return 0 }
    END {
      prod=0; run=0; slp=0; tops=""
      for (i=1;i<=n;i++) { p=ids[i]; if (p==root || !desc(p)) continue
        c=C[p]
        if (S[p] ~ /^R/) run=1
        split(c, a, " "); b=a[1]; sub(/.*\//, "", b); if (b=="sleep") slp=1
        if (isprod(c)) { prod=1
          q=P[p]; top=1; while (q!="" && q!=root && q>1) { if (isprod(C[q])) { top=0; break } q=P[q] }
          if (top) { m=c; k2=split(c, w, " "); for (j=1;j<=k2 && j<=2;j++) { bb=w[j]; sub(/.*\//, "", bb); if (bb in NAMES || w[j] ~ /(scripts|hooks|githooks)\/[A-Za-z0-9._-]+$/) { m=bb; break } } if (!(m in seen)) { seen[m]=1; tops=tops " " m } }
        }
      }
      if (prod) cl=(run?"prod_run":(slp?"prod_sleep":"prod_wait")); else if (run) cl="t_run"; else if (slp) cl="t_sleep"; else cl="t_wait"
      print cl tops
    }')
  us; now=$US
  forks; nf=$FK
  read -r cl tops <<<"$res"
  [ -n "$cl" ] || cl=t_wait
  dt=$((now - prev))
  cls_t[$cl]=$((cls_t[$cl] + dt))
  df=$((nf - pf - per_tick)); [ "$df" -lt 0 ] && df=0
  cls_f[$cl]=$((cls_f[$cl] + df))
  if [ -n "$tops" ]; then
    read -r -a arr <<<"$tops"
    k=${#arr[@]}
    for s in "${arr[@]}"; do script_t[$s]=$((${script_t[$s]:-0} + dt / k)); done
  fi
  prev=$now
  pf=$nf
  ticks=$((ticks + 1))
  sleep "$iv"
done
wait "$tp"
rc=$?
us; end=$US
forks; f1=$FK
if [ "$f0" -gt 0 ]; then fk=$((f1 - f0 - ticks * per_tick)); else fk=na; fi
out="file=$name rc=$rc wall=$(sec $((end - start))) ticks=$ticks forks=$fk"
for c in prod_run prod_wait prod_sleep t_sleep t_wait t_run; do
  out="$out $c=$(sec "${cls_t[$c]}") f_$c=${cls_f[$c]}"
done
sc=""
for s in "${!script_t[@]}"; do sc="$sc${script_t[$s]} $s"$'\n'; done
sc=$(printf '%s' "$sc" | sort -rn | head -8 | while read -r v s; do printf '%s:%s;' "$s" "$(sec "$v")"; done)
echo "$out scripts=$sc"
PROF

cat >"$work/launch.sh" <<'LAUNCH'
#!/bin/bash
# Mean wall-clock per launch over n launches, per kind, in microseconds.
set -u
n=${1:-300}
us() { local v=${EPOCHREALTIME/./}; US=$((10#$v)); }
run() {
  local kind=$1 i a b
  shift
  us; a=$US
  for ((i = 0; i < n; i++)); do "$@" >/dev/null 2>&1; done
  us; b=$US
  echo "launch kind=$kind n=$n us_per=$(((b - a) / n))"
}
sub() { local i a b; us; a=$US; for ((i = 0; i < n; i++)); do (:); done; us; b=$US; echo "launch kind=subshell n=$n us_per=$(((b - a) / n))"; }
sub
run true /bin/true
run sh /bin/sh -c :
run bash /bin/bash -c :
run bash-script /bin/bash "$0" --noop
run git git --version
run jq jq -n 1
run awk awk 'BEGIN{}'
LAUNCH
sed -i 's/^set -u$/set -u\n[ "${1:-}" = --noop ] \&\& exit 0/' "$work/launch.sh"

emit "host nproc=$(nproc) model=$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo | tr ' ' '_') kernel=$(uname -r) bash=${BASH_VERSION}"
/bin/bash "$work/launch.sh" 300 2>&1 | while IFS= read -r l; do emit "$l"; done

printf '#!/bin/bash\nsleep 3\n' >"$work/idle.sh"
emit "calib $(/bin/bash "$work/prof.sh" "$work/idle.sh" 0.1)"

for f in \
  tests/test-flight-dispatch.sh \
  tests/test-fleet-streamjson.sh \
  tests/test-resolve-steps.sh \
  tests/test-worker-command-guard.sh \
  tests/test-lock-lib.sh \
  tests/test-allocation-adapt.sh \
  tests/test-fleet-liveness.sh \
  tests/test-allocation-feedback-callsites.sh \
  tests/test-spec-validate.sh \
  tests/test-tower-queue-settle.sh \
  tests/test-tower-queue-away.sh \
  tests/test-allocation-feedback.sh \
  tests/test-tower-reply-hook.sh \
  tests/test-fleet-sweep-reap.sh \
  tests/test-tasks-pr-sync.sh \
  tests/test-tower-queue-merge.sh \
  tests/test-allocation-clamps.sh \
  tests/test-reserved-control-spellings.sh \
  tests/test-policy-guard.sh \
  tests/test-orchestrate-meta-select.sh \
  tests/test-tower-queue-store-lock.sh \
  tests/test-tower-loop-relay.sh \
  tests/test-tower-queue-standing.sh \
  tests/test-fleet-attention.sh \
  tests/test-fleet-stop-sj.sh \
  tests/test-tower-queue-lease.sh \
  tests/test-fleet-stop-hl.sh \
  tests/test-fleet-dispatch-reconcile.sh \
  tests/test-tower-loop-comms.sh \
  tests/test-release-publish.sh \
  tests/test-turn-shape-eval.sh \
  tests/test-flight-record.sh \
  tests/test-run-tests.sh; do
  if [ -f "$f" ]; then
    emit "prof $(/bin/bash "$work/prof.sh" "$f" 0.1)"
  else
    emit "missing $f"
  fi
done
emit "done"
echo "ok: profile probe ran"
