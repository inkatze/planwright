#!/bin/sh
# fleet-remote.sh — drive a stream-json worker on another host over SSH: the
# remote host's own planwright launches and supervises it, and this script is
# the near-side channel that reaches those verbs. `fleet-remote.sh --help`
# prints the contract.
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

help_text() {
  cat <<'EOF'
usage: fleet-remote.sh --host <alias> [--root <abs-dir>] <verb> [<args>...]

Verbs (each runs the remote host's planwright, never this host's):
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
  retire <name-or-worker>       mission-control-launch.sh retire
  compute --worktree <abs-dir> (--check | --task <name> | --test <tests/test-x.sh>)
          [--timeout <secs>]    ship the worktree's HEAD commit (never its
                                uncommitted changes) to the remote clone at
                                ~/dev/<origin repo name> as a hidden ref, run
                                the one command in a scratch worktree there
                                (umask 022, its own TMPDIR, killed with its
                                process group at the timeout, default 540),
                                stream its output back, exit with its status,
                                and remove the worktree and the ref

<alias> is an SSH host alias (letters, digits, . _ -; no leading dash),
resolved by the operator's ~/.ssh/config: a LAN host and a Coder workspace
take the same path. SSH runs with BatchMode, so a host that would ask for a
password fails instead of hanging.

The remote root is --root, else PLANWRIGHT_ROOT as set by the remote's
optional ~/.config/planwright/remote-env.sh (sourced first, the place for
PATH and CLAUDE_PLUGIN_DATA on that host), else the first root the remote's
installed-plugin record names (its resolve-installed-roots.sh --current,
which needs jq there).

Exit codes: 2 usage error or a refused argument; 3 no planwright root (or,
for compute, no clone) on the remote; 4 compute could not ship HEAD; 255 SSH
could not connect; otherwise the remote verb's own exit (compute: 143 at the
timeout).
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

host=''
root=''
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
    --root)
      [ $# -ge 2 ] || usage
      root=$2
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
case $root in
  '' | /*) ;;
  *) die "--root must be an absolute path" ;;
esac

verb=$1
shift
worker_ok() {
  case $1 in
    '' | -* | *[!A-Za-z0-9_-]*) die "refusing worker name: letters, digits, _ - only" ;;
  esac
}
stdin_verb=0
case $verb in
  root)
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
    secs=540
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
    case $secs in '' | *[!0-9]* | 0) die "--timeout takes a whole number of seconds" ;; esac
    case $kind:$value in
      task:[a-z]*) case $value in *[!a-z0-9:_-]*) die "refusing task name" ;; esac ;;
      test:tests/test-*.sh) case ${value#tests/} in *[!A-Za-z0-9._-]*) die "refusing test path" ;; esac ;;
      check:) ;;
      *) die "refusing $kind target: a task name, or a tests/test-<name>.sh path" ;;
    esac
    case $wt in /*) ;; *) die "compute needs --worktree <absolute path>" ;; esac
    sha=$(git -C "$wt" rev-parse --verify -q 'HEAD^{commit}') || die "not a git worktree with a commit: $wt"
    url=$(git -C "$wt" remote get-url origin 2>/dev/null) || die "the worktree has no origin remote to name the repository by"
    name=${url%/}
    name=${name%.git}
    name=${name##*/}
    name=${name##*:}
    case $name in '' | -* | *[!A-Za-z0-9._-]*) die "cannot derive a repository name from origin" ;; esac
    if [ -n "$(git -C "$wt" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
      printf '%s\n' "$prog: warning: uncommitted changes are not shipped; running HEAD $sha" >&2
    fi
    GIT_SSH_COMMAND='ssh -T -o BatchMode=yes' git -C "$wt" push -q "$host:dev/$name" \
      "$sha:refs/planwright-compute/$sha" </dev/null || die "could not ship HEAD to $host:dev/$name (is the repository cloned there?)" 4
    set -- "$name" "$sha" "$secs" "$kind" "$value"
    ;;
  *) usage ;;
esac
for a in "$root" "$@"; do
  safe_arg "$a" || die "refusing an argument holding a backslash or a control character"
done

# The remote program. $1 root (may be empty), $2 verb, the rest the verb's
# arguments. A function rather than a $( ) heredoc, which bash 3.2 misparses.
remote_program() {
  cat <<'EOF'
set -u
envf="$HOME/.config/planwright/remote-env.sh"
if [ -r "$envf" ]; then . "$envf" || exit 3; fi
root=$1
verb=$2
shift 2
if [ "$verb" = compute ]; then
  repo="$HOME/dev/$1"
  sha=$2
  secs=$3
  kind=$4
  target=$5
  [ -d "$repo/.git" ] || { echo "fleet-remote: no clone at ~/dev/$1 on this host" >&2; exit 3; }
  base="$HOME/dev/.planwright-compute"
  mkdir -p "$base" || exit 2
  run=$(mktemp -d "$base/run.XXXXXX") || exit 2
  pid=''
  wd=''
  cleanup() {
    [ -z "$pid" ] || kill -KILL -- "-$pid" 2>/dev/null
    [ -z "$wd" ] || kill -KILL -- "-$wd" 2>/dev/null
    cd "$HOME" || :
    git -C "$repo" worktree remove --force "$run/wt" >/dev/null 2>&1
    git -C "$repo" update-ref -d "refs/planwright-compute/$sha" >/dev/null 2>&1
    rm -rf "$run"
  }
  trap cleanup EXIT
  trap "exit 129" HUP
  trap "exit 130" INT
  trap "exit 143" TERM
  git -C "$repo" worktree add -q --detach "$run/wt" "$sha" || exit 2
  cd "$run/wt" || exit 2
  mkdir "$run/tmp" || exit 2
  TMPDIR="$run/tmp"
  export TMPDIR
  umask 022
  case $kind in
    check)
      [ ! -f scripts/wire-githooks.sh ] || /bin/sh scripts/wire-githooks.sh >/dev/null 2>&1 || :
      set -- mise run check
      ;;
    task) set -- mise run "$target" ;;
    test)
      [ -f "$target" ] || { echo "fleet-remote: no $target at $sha" >&2; exit 2; }
      set -- /bin/bash "$target"
      ;;
  esac
  start=$(date +%s)
  echo "fleet-remote: running $* at $sha, timeout ${secs}s" >&2
  exec 3>&2 2>/dev/null
  set -m
  "$@" </dev/null 2>&1 &
  pid=$!
  ( sleep "$secs"; echo "fleet-remote: timeout after ${secs}s" >&3; kill -TERM -- "-$pid" 2>/dev/null; sleep 10; kill -KILL -- "-$pid" 2>/dev/null ) &
  wd=$!
  wait "$pid"
  rc=$?
  pid=''
  kill -KILL -- "-$wd" 2>/dev/null
  wait "$wd" 2>/dev/null
  wd=''
  set +m
  exec 2>&3 3>&-
  echo "fleet-remote: exit $rc after $(( $(date +%s) - start ))s" >&2
  exit "$rc"
fi
[ -n "$root" ] || root=${PLANWRIGHT_ROOT:-}
if [ -z "$root" ]; then
  for r in "$HOME"/.claude/plugins/cache/*/planwright/*/scripts/resolve-installed-roots.sh; do
    [ -f "$r" ] || continue
    root=$(cd "$HOME" && /bin/sh "$r" --current | sed -n 1p)
    break
  done
fi
if [ -z "$root" ] || [ ! -d "$root/scripts" ]; then
  echo "fleet-remote: no planwright root on this host: install planwright, or set PLANWRIGHT_ROOT in ~/.config/planwright/remote-env.sh" >&2
  exit 3
fi
sj="$root/scripts/fleet-streamjson.sh"
mcl="$root/scripts/mission-control-launch.sh"
case $verb in
  root) printf "%s\n" "$root" ;;
  pending | answer | status) exec /bin/sh "$sj" "$verb" "$@" ;;
  retire) exec /bin/sh "$mcl" retire "$@" ;;
  launch | steer)
    f=$(mktemp) || exit 2
    trap "rm -f \"\$f\"" EXIT
    cat >"$f" || exit 2
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

cmd="exec /bin/sh -c $(q "$remote") fleet-remote $(q "$root") $(q "$verb")"
for a in "$@"; do
  cmd="$cmd $(q "$a")"
done

if [ "$stdin_verb" = 1 ]; then
  exec ssh -T -o BatchMode=yes "$host" "$cmd"
fi
exec ssh -T -o BatchMode=yes "$host" "$cmd" </dev/null
