#!/bin/sh
# fleet-remote.sh — drive a stream-json worker on another host over SSH, or run
# a worktree's committed tests there: the remote host's own planwright and
# tools do the work, and this script is the near-side channel that reaches
# them. `fleet-remote.sh --help` prints the contract.
#
# The remote command is a fixed /bin/sh program plus positional arguments,
# each single-quoted, so the remote login shell (sh, bash, zsh or fish) only
# ever sees quoted words and never re-parses a caller's text. That is also why
# arguments holding a backslash or a control character are refused: fish
# treats a backslash inside single quotes as an escape, POSIX shells do not.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

prog=fleet-remote
ssh_opts='-T -o ConnectTimeout=15 -o BatchMode=yes -o ForwardAgent=no -o ForwardX11=no -o ClearAllForwardings=yes'

help_text() {
  cat <<'EOF'
usage: fleet-remote.sh --host <alias> <verb> [<args>...]

Verbs (each runs on the remote host, through its own planwright and tools):
  root                          print the remote planwright root
  launch <launch-args>...       mission-control-launch.sh launch on the remote,
                                the brief read from this script's stdin into a
                                remote temp file (--brief is supplied, never
                                accepted)
  pending [<worker>...]         fleet-streamjson.sh pending
  answer <worker> <request-id> (--allow | --deny [--message <text>])
  steer <worker>                fleet-streamjson.sh steer, the message read
                                from stdin
  status <worker>               fleet-streamjson.sh status
  retire <name-or-worker> [--force-parked]
                                mission-control-launch.sh retire
  load                          print the remote's one-minute load average
                                and core count, one line, for a placement check
  compute [--worktree <abs-dir>] (--check | --task <name> | --test <tests/test-x.sh>)
          [--timeout <secs>]    push the worktree's HEAD commit (never its
                                uncommitted changes; every object the remote
                                clone lacks) to the remote clone at
                                ~/dev/<origin repo name> under a per-run hidden
                                ref, run the one command in a scratch worktree
                                there (umask 022, its own TMPDIR, test
                                parallelism set to the remote's cores shared
                                among its live runs, killed with its process
                                group at the timeout, default 1800 for --check
                                and 540 otherwise, at most 86400), stream its
                                output back, exit with its status, and remove
                                the worktree and the ref. The command's own
                                standard input is /dev/null. --worktree defaults
                                to the worktree holding the current directory.
                                The run stops when this command is killed or
                                the connection drops

<alias> is an SSH host alias (letters, digits, . _ -; no leading dash),
resolved by the operator's ~/.ssh/config: a LAN host and a Coder workspace
take the same path. SSH runs with BatchMode, so a host that would ask for a
password fails instead of hanging, and with agent, X11 and port forwarding
off.

The remote first sources its optional ~/.config/planwright/remote-env.sh, the
place for PATH and CLAUDE_PLUGIN_DATA on that host; it holds no secrets,
since compute runs the caller's code in that environment. The remote root is
the first root the remote's installed-plugin record names (its
resolve-installed-roots.sh --current, which needs jq there); no caller can
point a verb at another copy. compute needs no root, only the clone, git,
perl, and mise (--check, --task) or /bin/bash (--test); load needs only
getconf, sysctl or nproc and a readable load average; it unsets
PLANWRIGHT_ROOT so the shipped commit tests itself. It runs that code as the
remote account, so whatever that account can read (a CLI login included),
the code can too.

A compute run warns on stderr when its worktree's branch is behind its
upstream, since the remote runs the worktree's own HEAD, not the upstream's.

Exit codes: 2 usage error or a refused argument; 3 the remote is not set up
(no planwright root, an env file that fails, or for compute no clone, no
perl, or no mise or /bin/bash for the chosen command); 4 compute could not
ship HEAD (no clone there, or SSH failed); 255 SSH could not connect;
otherwise the remote verb's own exit. compute exits with the command's own
status, 143 when the timeout stopped it, 129 when the caller went away (this
side was killed or the connection dropped) and the command was stopped, and says on stderr which happened; a
channel failure there prints a fleet-remote: line, and a "fleet-remote:
running" line marks that the command started. A run whose connection drops
before its own cleanup leaves its ref behind; the next compute run on that
clone deletes this channel's refs older than the longest timeout.
EOF
}

usage() {
  help_text >&2
  exit 2
}

die() {
  printf '%s: %s\n' "$prog" "$1" >&2
  exit "${2:-2}"
}

# safe_arg <arg>: 0 when the arg can travel single-quoted to any remote shell.
safe_arg() {
  case $1 in
    *\\*) return 1 ;;
  esac
  [ "$(printf '%s' "$1" | tr -d '\000-\037\177' | wc -c)" -eq "$(printf '%s' "$1" | wc -c)" ]
}

# q <arg>: the arg single-quoted, each embedded quote closed, escaped, reopened.
q() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# lgit <args>: git on the caller's worktree with its hooks, fsmonitor and
# transport helpers disabled, so pointing compute at a worktree never runs
# code from that worktree on this host.
lgit() {
  (
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CONFIG GIT_CONFIG_PARAMETERS \
      GIT_CONFIG_COUNT GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM \
      GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS \
      GIT_IMPLICIT_WORK_TREE GIT_PREFIX
    GIT_OPTIONAL_LOCKS=0 GIT_ALLOW_PROTOCOL=ssh GIT_SSH_COMMAND="ssh $ssh_opts"
    export GIT_OPTIONAL_LOCKS GIT_ALLOW_PROTOCOL GIT_SSH_COMMAND
    exec git -C "$wt" -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"
  )
}

host=''
while [ $# -gt 0 ]; do
  case $1 in
    --help | -h)
      help_text
      exit 0
      ;;
    --host)
      [ $# -ge 2 ] || usage
      host=$2
      shift 2
      ;;
    -*) usage ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || usage
[ -n "$host" ] || die "--host <alias> is required"
case $host in
  -* | *[!A-Za-z0-9._-]*) die "refusing host alias: letters, digits, . _ - only, no leading dash" ;;
esac

verb=$1
shift
# The supervisor's own field grammar, so every handle it accepts is reachable.
worker_ok() {
  case $1 in
    '' | -* | *[!A-Za-z0-9._=@:-]*) die "refusing worker name: letters, digits, . _ = @ : - only" ;;
  esac
}
stdin_verb=0
case $verb in
  root | load)
    [ $# -eq 0 ] || usage
    ;;
  launch)
    [ $# -ge 1 ] || usage
    for a in "$@"; do
      case $a in --brief | --brief=*) die "launch takes the brief on stdin, never --brief" ;; esac
    done
    stdin_verb=1
    ;;
  pending)
    for a in "$@"; do worker_ok "$a"; done
    ;;
  answer)
    [ $# -ge 3 ] || usage
    worker_ok "$1"
    case $2 in '' | -* | *[!A-Za-z0-9-]*) die "refusing request id: letters, digits, - only" ;; esac
    case $3 in
      --allow) [ $# -eq 3 ] || usage ;;
      --deny)
        case $# in
          3) ;;
          5) [ "$4" = --message ] || usage ;;
          *) usage ;;
        esac
        ;;
      *) usage ;;
    esac
    ;;
  steer)
    [ $# -eq 1 ] || usage
    worker_ok "$1"
    stdin_verb=1
    ;;
  status | retire)
    [ $# -eq 1 ] || usage
    worker_ok "$1"
    ;;
  compute)
    wt=''
    secs=''
    kind=''
    value=''
    while [ $# -gt 0 ]; do
      case $1 in
        --worktree | --timeout | --task | --test)
          [ $# -ge 2 ] || usage
          case $1 in
            --worktree) wt=$2 ;;
            --timeout) secs=$2 ;;
            *)
              [ -z "$kind" ] || usage
              kind=${1#--}
              value=$2
              ;;
          esac
          shift 2
          ;;
        --check)
          [ -z "$kind" ] || usage
          kind=check
          shift
          ;;
        *) usage ;;
      esac
    done
    [ -n "$kind" ] || die "compute needs one of --check, --task <name>, --test <tests/test-name.sh>"
    if [ -z "$secs" ]; then
      case $kind in check) secs=1800 ;; *) secs=540 ;; esac
    fi
    case $secs in '' | *[!0-9]*) die "--timeout takes a whole number of seconds" ;; esac
    while :; do
      case $secs in 0?*) secs=${secs#0} ;; *) break ;; esac
    done
    case $secs in 0 | ??????*) die "--timeout takes 1 to 86400 seconds" ;; esac
    [ "$secs" -le 86400 ] || die "--timeout takes 1 to 86400 seconds"
    case $kind:$value in
      task:[a-z]*) case $value in *[!a-z0-9:_-]*) die "refusing task name" ;; esac ;;
      test:tests/test-*.sh) case ${value#tests/} in *[!A-Za-z0-9._-]*) die "refusing test path" ;; esac ;;
      check:) ;;
      *) die "refusing $kind target: a task name, or a tests/test-<name>.sh path" ;;
    esac
    if [ -z "$wt" ]; then
      wt=$(cd "${PWD:-.}" && GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false rev-parse --show-toplevel 2>/dev/null) \
        || die "compute needs --worktree <absolute path>, and the current directory is in no git worktree"
    fi
    case $wt in /*) ;; *) die "compute needs --worktree <absolute path>" ;; esac
    safe_arg "$wt" || die "refusing an argument holding a backslash or a control character"
    sha=$(lgit rev-parse --verify -q 'HEAD^{commit}') || die "not a git worktree with a commit: $wt"
    behind=$(lgit rev-list --count 'HEAD..@{upstream}' 2>/dev/null) || behind=0
    case $behind in '' | *[!0-9]*) behind=0 ;; esac
    if [ "$behind" -gt 0 ]; then
      printf '%s: warning: the worktree is %s commit(s) behind its upstream; running its own HEAD %s\n' "$prog" "$behind" "$sha" >&2
    fi
    url=$(lgit remote get-url origin 2>/dev/null) || die "the worktree has no origin remote to name the repository by"
    name=${url%/}
    name=${name%.git}
    name=${name##*/}
    name=${name##*:}
    case $name in '' | [.-]* | *[!A-Za-z0-9._-]*) die "cannot derive a repository name from origin" ;; esac
    if [ -n "$(lgit status --porcelain --untracked-files=normal 2>/dev/null)" ]; then
      printf '%s\n' "$prog: warning: uncommitted changes are not shipped; running HEAD $sha" >&2
    fi
    ref="refs/planwright-compute/$sha-$$-$(date +%s)"
    lgit push -q "$host:dev/$name" "$sha:$ref" </dev/null \
      || die "could not ship HEAD to $host:dev/$name (is the repository cloned there?)" 4
    set -- "$name" "$sha" "$secs" "$kind" "$value" "$ref"
    ;;
  *) usage ;;
esac
for a in "$@"; do
  safe_arg "$a" || die "refusing an argument holding a backslash or a control character"
done

# The remote program. $1 root (may be empty), $2 verb, the rest the verb's
# arguments. A function rather than a $( ) heredoc, which bash 3.2 misparses.
remote_program() {
  cat <<'EOF'
set -u
# The cleanup state is set before the env file is sourced, so a setup failure
# still removes the shipped ref, and carries a prefix the file will not reuse;
# the arguments are read after it, from the positionals it cannot change.
if [ "$2" = compute ]; then
  fr_repo="$HOME/dev/$3"
  fr_ref=$8
  fr_run=''
  fr_cleanup() {
    cd "$HOME" || :
    if [ -n "$fr_run" ]; then
      # A process that left its process group (setsid, a daemonised helper)
      # still names the run directory in its command line.
      fr_pat=$(printf '%s/' "$fr_run" | sed 's/[][\.*^$+?(){}|]/\\&/g')
      pkill -KILL -f "$fr_pat" >/dev/null 2>&1 || :
      chmod -R u+rwX "$fr_run" >/dev/null 2>&1 || :
      git -C "$fr_repo" worktree remove --force "$fr_run/wt" >/dev/null 2>&1 || git -C "$fr_repo" worktree prune >/dev/null 2>&1
      rm -rf "$fr_run"
    fi
    git -C "$fr_repo" update-ref -d "$fr_ref" >/dev/null 2>&1
  }
  trap fr_cleanup EXIT
  trap "exit 129" HUP
  trap "exit 130" INT
  trap "exit 141" PIPE
  trap "exit 143" TERM
fi
envf="$HOME/.config/planwright/remote-env.sh"
if [ -r "$envf" ]; then
  . "$envf" || { echo "fleet-remote: ~/.config/planwright/remote-env.sh failed" >&2; exit 3; }
fi
root=$1
verb=$2
shift 2
if [ "$verb" = compute ]; then
  sha=$2
  secs=$3
  kind=$4
  target=$5
  [ -d "$fr_repo/.git" ] || { echo "fleet-remote: no clone at ~/dev/$1 on this host" >&2; exit 3; }
  fr_now=$(date +%s)
  git -C "$fr_repo" for-each-ref --format="%(refname)" refs/planwright-compute/ | while IFS= read -r fr_old; do
    fr_epoch=${fr_old##*-}
    case $fr_epoch in '' | *[!0-9]*) continue ;; esac
    [ $((fr_now - fr_epoch)) -le 90000 ] || git -C "$fr_repo" update-ref -d "$fr_old" >/dev/null 2>&1
  done
  command -v perl >/dev/null 2>&1 || { echo "fleet-remote: compute needs perl on this host" >&2; exit 3; }
  case $kind in
    test) [ -x /bin/bash ] || { echo "fleet-remote: compute --test needs /bin/bash on this host" >&2; exit 3; } ;;
    *) command -v mise >/dev/null 2>&1 || { echo "fleet-remote: compute --$kind needs mise on this host" >&2; exit 3; } ;;
  esac
  base="$HOME/dev/.planwright-compute"
  mkdir -p "$base" || exit 3
  # A run killed before its cleanup leaves its scratch worktree too; any run
  # directory untouched for longer than the longest timeout is one of those.
  find "$base" -mindepth 1 -maxdepth 1 -type d -name "run.*" -mmin +1500 | while IFS= read -r fr_stale; do
    chmod -R u+rwX "$fr_stale" >/dev/null 2>&1
    git -C "$fr_stale/wt" worktree remove --force "$fr_stale/wt" >/dev/null 2>&1
    rm -rf "$fr_stale"
  done
  git -C "$fr_repo" worktree prune >/dev/null 2>&1
  fr_run=$(mktemp -d "$base/run.XXXXXX") || exit 3
  run=$fr_run
  echo $$ >"$run/pid"
  # Test parallelism: the remote's cores shared among the runs live now (this
  # one included, counted after its own directory exists so runs starting
  # together mostly divide the cores between them; best effort); a run killed without cleanup
  # names a dead pid and stops counting.
  fr_cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null)
  case $fr_cores in '' | *[!0-9]* | 0) fr_cores=4 ;; esac
  fr_live=0
  for fr_d in "$base"/run.*; do
    fr_p=$(cat "$fr_d/pid" 2>/dev/null) || continue
    case $fr_p in '' | *[!0-9]*) continue ;; esac
    if kill -0 "$fr_p" 2>/dev/null; then fr_live=$((fr_live + 1)); fi
  done
  [ "$fr_live" -ge 1 ] || fr_live=1
  fr_jobs=$((fr_cores / fr_live))
  [ "$fr_jobs" -ge 1 ] || fr_jobs=1
  git -C "$fr_repo" -c core.hooksPath=/dev/null worktree add -q --detach "$run/wt" "$sha" || exit 3
  cd "$run/wt" || exit 3
  mkdir "$run/tmp" || exit 3
  TMPDIR="$run/tmp"
  export TMPDIR
  MISE_TRUSTED_CONFIG_PATHS="$base${MISE_TRUSTED_CONFIG_PATHS:+:$MISE_TRUSTED_CONFIG_PATHS}"
  export MISE_TRUSTED_CONFIG_PATHS
  unset PLANWRIGHT_ROOT CLAUDE_PLUGIN_ROOT
  umask 022
  PLANWRIGHT_TEST_JOBS=$fr_jobs
  PLANWRIGHT_TEST_SLOTS=$fr_jobs
  export PLANWRIGHT_TEST_JOBS PLANWRIGHT_TEST_SLOTS
  case $kind in
    check)
      [ ! -f scripts/wire-githooks.sh ] || /bin/sh scripts/wire-githooks.sh >/dev/null 2>&1 || :
      set -- mise run check
      ;;
    task) set -- mise run "$target" ;;
    test)
      [ -f "$target" ] || { echo "fleet-remote: no $target at $sha" >&2; exit 3; }
      set -- /bin/bash "$target"
      ;;
  esac
  start=$(date +%s)
  echo "fleet-remote: running $* at $sha, timeout ${secs}s" >&2
  # A perl supervisor rather than shell job control: dash's wait can miss a
  # fast child, and set -m grabs a terminal when the shell holds one. The
  # command leads its own process group so the timeout reaches every child.
  sup='use POSIX qw(WNOHANG);
my ($secs, $flag, @cmd) = @ARGV;
my %code = (HUP => 129, INT => 130, PIPE => 141, TERM => 143);
my $pid;
for my $s (keys %code) { $SIG{$s} = sub { kill "KILL", -$pid if $pid; exit $code{$s} } }
$pid = fork;
defined $pid or exit 125;
if (!$pid) { open(STDIN, "<", "/dev/null"); setpgrp(0, 0); exec { $cmd[0] } @cmd; print STDERR "fleet-remote: cannot run $cmd[0]: $!\n"; exit 127 }
setpgrp($pid, $pid);
$SIG{ALRM} = sub { open(my $m, ">", $flag); kill "TERM", -$pid; $SIG{ALRM} = sub { kill "KILL", -$pid }; alarm 10 };
alarm $secs;
# The channel holds this standard input open for the whole run, so an end of
# file means the caller was killed or the connection dropped.
my $rin = ""; vec($rin, fileno(STDIN), 1) = 1;
my $st; my $watch = 1;
while (1) {
  my $got = waitpid($pid, WNOHANG);
  if ($got == $pid) { $st = $?; last }
  next if $got == -1 && $!{EINTR};
  if ($got == -1) { print STDERR "fleet-remote: lost track of the command\n"; $st = 125 << 8; last }
  my $r = $rin;
  my $n = select($watch ? $r : undef, undef, undef, 0.2);
  if ($watch && $n > 0 && vec($r, fileno(STDIN), 1)) {
    my $buf;
    my $len = sysread(STDIN, $buf, 4096);
    if (defined $len && $len == 0) {
      print STDERR "fleet-remote: the caller went away; stopping the command\n";
      kill "KILL", -$pid; waitpid($pid, 0); exit 129
    }
    $watch = 0 unless defined $len || $!{EINTR};
  }
}
alarm 0;
kill "KILL", -$pid;
exit($st & 127 ? 128 + ($st & 127) : $st >> 8);'
  perl -e "$sup" "$secs" "$run/timed-out" "$@" 2>&1
  rc=$?
  if [ -e "$run/timed-out" ]; then
    echo "fleet-remote: timeout after ${secs}s (the command's own exit was $rc)" >&2
    rc=143
  fi
  echo "fleet-remote: exit $rc after $(( $(date +%s) - start ))s" >&2
  exit "$rc"
fi
if [ "$verb" = load ]; then
  fr_load=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null) || fr_load=''
  [ -n "$fr_load" ] || fr_load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{ print $2 }')
  fr_cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null)
  if [ -z "$fr_load" ] || [ -z "$fr_cores" ]; then
    echo "fleet-remote: cannot read this host's load or core count" >&2
    exit 3
  fi
  printf '%s %s\n' "$fr_load" "$fr_cores"
  exit 0
fi
if [ -z "$root" ]; then
  for r in "$HOME"/.claude/plugins/cache/*/planwright/*/scripts/resolve-installed-roots.sh; do
    [ -f "$r" ] || continue
    root=$(cd "$HOME" && /bin/sh "$r" --current | sed -n 1p)
    [ -z "$root" ] || break
  done
fi
if [ -z "$root" ] || [ ! -d "$root/scripts" ]; then
  echo "fleet-remote: no planwright root on this host: install planwright there (its record needs jq)" >&2
  exit 3
fi
sj="$root/scripts/fleet-streamjson.sh"
mcl="$root/scripts/mission-control-launch.sh"
case $verb in
  root) printf "%s\n" "$root" ;;
  pending | answer | status) exec /bin/sh "$sj" "$verb" "$@" ;;
  retire) exec /bin/sh "$mcl" retire "$@" ;;
  launch | steer)
    f=$(mktemp "${TMPDIR:-/tmp}/fleet-remote.XXXXXX") || exit 3
    trap "rm -f \"\$f\"" EXIT
    trap "exit 129" HUP
    trap "exit 130" INT
    trap "exit 141" PIPE
    trap "exit 143" TERM
    cat >"$f" || exit 3
    [ -s "$f" ] || { echo "fleet-remote: empty stdin: nothing to send" >&2; exit 2; }
    if [ "$verb" = launch ]; then
      /bin/sh "$mcl" launch "$@" --brief "$f"
    else
      /bin/sh "$sj" steer "$@" --message-file "$f"
    fi
    ;;
esac
EOF
}
remote=$(remote_program)

cmd="exec /bin/sh -c $(q "$remote") fleet-remote '' $(q "$verb")"
for a in "$@"; do
  cmd="$cmd $(q "$a")"
done

# shellcheck disable=SC2086 # ssh_opts is a fixed word list
if [ "$stdin_verb" = 1 ]; then
  exec ssh $ssh_opts "$host" "$cmd"
fi
if [ "$verb" = compute ]; then
  # The remote run watches its standard input and stops the command when it
  # closes, so this side holds a pipe open for exactly as long as it lives:
  # a kill of this script, its process group, or the connection ends the run.
  # An unreadable pipe directory is a plain failure, never a run without it.
  kd=$(mktemp -d "${TMPDIR:-/tmp}/fleet-remote-keep.XXXXXX") || die "cannot create a temporary directory" 4
  mkfifo "$kd/k" || {
    rm -rf "$kd"
    die "cannot create a FIFO" 4
  }
  sleep 90000 >"$kd/k" &
  keep=$!
  sshp=''
  stop_children() {
    [ -z "$sshp" ] || kill "$sshp" 2>/dev/null
    kill "$keep" 2>/dev/null
    rm -rf "$kd"
  }
  trap 'stop_children; exit 129' HUP
  trap 'stop_children; exit 130' INT
  trap 'stop_children; exit 143' TERM
  # shellcheck disable=SC2086 # ssh_opts is a fixed word list
  ssh $ssh_opts -o ServerAliveInterval=15 -o ServerAliveCountMax=4 "$host" "$cmd" <"$kd/k" &
  sshp=$!
  wait "$sshp"
  rc=$?
  sshp=''
  stop_children
  exit "$rc"
fi
# shellcheck disable=SC2086 # ssh_opts is a fixed word list
exec ssh $ssh_opts "$host" "$cmd" </dev/null
