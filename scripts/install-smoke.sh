#!/bin/sh
# install-smoke.sh — install planwright through both delivery modes and run an
# adopter-tier entry point through each with PATH narrowed to an allowlist, so
# the no-toolchain constraint holds on runner images that carry compilers,
# interpreters, and package managers by default.
#
# Usage: install-smoke.sh [--modes <list>] [--source <dir>] [--entry <path>]
#   --modes   comma-separated delivery modes, each at most once, default
#             `writer,marketplace`:
#               writer       scripts/install.sh into a scratch CLAUDE_DIR,
#                            itself run under the allowlist PATH
#               marketplace  `claude plugin marketplace add` of <source> and
#                            `claude plugin install planwright@planwright` into
#                            a scratch CLAUDE_CONFIG_DIR, on the caller's PATH
#                            (the CLI is the adopter's own installer); a
#                            missing `claude` fails the run.
#   --source  the planwright tree to install, default this script's repo.
#   --entry   a path relative to the installed root, run with no arguments in
#             place of the default scripts/step-record.sh exercise.
#
# Exit: 0 every mode installed and its entry point succeeded; 1 a failed
# install or entry point (named on stderr); 2 usage error.
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

die() {
  printf 'install-smoke: %s\n' "$2" >&2
  exit "$1"
}

modes=writer,marketplace
src=
entry=
while [ $# -gt 0 ]; do
  case $1 in
    --modes | --source | --entry)
      [ $# -ge 2 ] && [ -n "$2" ] || die 2 "$1 needs a value"
      case $1 in
        --modes) modes=$2 ;;
        --source) src=$2 ;;
        --entry) entry=$2 ;;
      esac
      shift 2
      ;;
    *) die 2 "unknown argument: $1" ;;
  esac
done

case ,$modes, in
  ,, | *,,*) die 2 "--modes is empty" ;;
esac
# A blank or space-separated list would split to fewer modes than it names,
# a blank one to none, and pass having installed nothing.
case $modes in
  *[!a-z,]*) die 2 "--modes takes comma-separated mode names" ;;
esac
mode_list=$(printf '%s\n' "$modes" | tr ',' ' ')
seen=' '
for m in $mode_list; do
  case $m in
    writer | marketplace) ;;
    *) die 2 "unknown delivery mode: $m" ;;
  esac
  case $seen in
    *" $m "*) die 2 "delivery mode named twice: $m" ;;
  esac
  seen="$seen$m "
done
case $entry in
  /*) die 2 "--entry must be a relative path inside the installed root" ;;
esac
case /$entry/ in
  */../*) die 2 "--entry must be a relative path inside the installed root" ;;
esac

if [ -z "$src" ]; then
  src=$(cd "$(dirname "$0")/.." && pwd -P) || die 2 "cannot locate the source tree"
fi
[ -f "$src/scripts/install.sh" ] || die 2 "no scripts/install.sh under $src"

work=$(mktemp -d "${TMPDIR:-/tmp}/install-smoke.XXXXXX") || die 1 "mktemp failed"
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

allow="$work/allow-bin"
mkdir -p "$allow" || die 1 "cannot create the allowlist directory"

# The runtime set: sh and bash with the utilities POSIX.1-2024 specifies,
# git, and gh. Left out: POSIX's development utilities (c17, make, lex, yacc,
# SCCS), the toolchain the constraint excludes; sets no adopter script uses
# (UUCP, message catalogs, vi, localedef); and cd, umask, unalias, which only
# a builtin can implement. mktemp is the one non-POSIX addition: every matrix
# platform ships it, it is no toolchain, and every scratch file comes from it.
tools='alias at awk basename batch bc bg cal cat chgrp chmod chown
cksum cmp comm command compress cp crontab csplit cut date dd df diff dirname
du echo ed env ex expand expr false fc fg file find fold fuser getconf getopts
grep hash head iconv id ipcrm ipcs jobs join kill link ln locale logger
logname lp ls mailx man mesg mkdir mkfifo more mv newgrp nice nl nohup od
paste patch pathchk pax pr printf ps pwd read readlink realpath renice rm
rmdir sed sleep sort split strings stty tabs tail talk tee test time timeout
touch tput tr true tsort tty type ulimit uname uncompress unexpand uniq
unlink uudecode uuencode wait wc who write xargs zcat
mktemp
sh bash git gh'

# Each name is found file by file and linked into a scratch directory, never
# by exposing its PATH directory (which may hold anything); a shell builtin
# (printf, test, kill) is still linked for xargs, env, and find -exec. A name
# the host lacks is simply absent.
set --
for t in $tools; do
  ifs=$IFS
  IFS=:
  for d in $PATH; do
    case $d in /*) ;; *) continue ;; esac
    if [ -f "$d/$t" ] && [ -x "$d/$t" ]; then
      set -- "$@" "$d/$t"
      break
    fi
  done
  IFS=$ifs
done
[ $# -gt 0 ] || die 1 "no allowlisted tool is on PATH"
ln -s -- "$@" "$allow/" || die 1 "cannot link the allowlist"
[ -e "$allow/sh" ] || die 1 "no sh on PATH to build the allowlist from"
[ -e "$allow/git" ] || die 1 "no git on PATH to build the allowlist from"

home="$work/home"
mkdir -p "$home" || die 1 "cannot create the scratch HOME"

# narrowed <command> [<arg>...]: run under the allowlist and nothing else;
# env -i keeps any variable from carrying a toolchain path.
narrowed() {
  env -i PATH="$allow" HOME="$home" LC_ALL=C TMPDIR="$work" "$@"
}

# exercise <mode> <root>: the default entry-point run against one installed
# copy, in a scratch repository of the mode's own. step-record.sh is the
# adopter-tier script with the largest coupling profile in `mise run
# substrate:partition` (a run, a record, a render, a fingerprint).
exercise() {
  sr="$2/scripts/step-record.sh"
  repo="$work/repo.$1"
  if ! {
    narrowed git init -q "$repo" \
      && printf 'smoke\n' >"$repo/README" \
      && narrowed git -C "$repo" add README \
      && narrowed git -C "$repo" -c user.name=smoke -c user.email=smoke@example.invalid \
        commit -q -m smoke
  }; then
    die 1 "$1 mode: cannot prepare the scratch repository under the allowlist PATH"
  fi

  run=$(narrowed "$sr" --worktree "$repo" new-run) || return 1
  narrowed "$sr" --worktree "$repo" write --run "$run" --point pre-pr \
    --step smoke --kind command --target smoke --hosting in-session \
    --backend terminal --start 2026-01-01T00:00:00Z --outcome passed \
    >/dev/null || return 1
  out=$(narrowed "$sr" --worktree "$repo" render --run "$run") || return 1
  case $out in
    *smoke*) ;;
    *)
      printf 'install-smoke: the rendered record names no smoke step\n' >&2
      return 1
      ;;
  esac
  fp=$(narrowed "$sr" --worktree "$repo" fingerprint --paths README) || return 1
  case $fp in
    *[!0-9a-f]* | '')
      printf 'install-smoke: the fingerprint is not a hex object id\n' >&2
      return 1
      ;;
  esac
}

# check <mode> <root>: run the entry point against one installed copy, by its
# literal path so a delivery mode that drops the execute bit fails here.
check() {
  if [ -n "$entry" ]; then
    (cd "$work" && narrowed "$2/$entry") || die 1 "$1 mode: $entry failed under the allowlist PATH"
  else
    exercise "$1" "$2" || die 1 "$1 mode: scripts/step-record.sh failed under the allowlist PATH"
  fi
  printf 'install-smoke: %s mode passed\n' "$1"
}

# claude_scratch <arg>...: the Claude CLI with every home it writes moved into
# the scratch directory, and no self-update.
claude_scratch() {
  CLAUDE_CONFIG_DIR="$work/claude-config" HOME="$home" \
    XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
    XDG_DATA_HOME="$home/.local/share" XDG_STATE_HOME="$home/.local/state" \
    DISABLE_AUTOUPDATER=1 claude "$@"
}

for m in $mode_list; do
  case $m in
    writer)
      cdir="$work/writer"
      narrowed CLAUDE_DIR="$cdir" "$src/scripts/install.sh" >/dev/null \
        || die 1 "writer mode: scripts/install.sh failed under the allowlist PATH"
      check writer "$cdir/planwright"
      ;;
    marketplace)
      command -v claude >/dev/null 2>&1 || die 1 "marketplace mode: no claude on PATH"
      claude_scratch plugin marketplace add "$src" >/dev/null \
        || die 1 "marketplace mode: claude plugin marketplace add failed"
      claude_scratch plugin install planwright@planwright >/dev/null \
        || die 1 "marketplace mode: claude plugin install failed"
      root=
      for d in "$work"/claude-config/plugins/cache/planwright/planwright/*/; do
        [ -d "$d" ] || continue
        [ -z "$root" ] || die 1 "marketplace mode: more than one installed version"
        root=${d%/}
      done
      [ -n "$root" ] || die 1 "marketplace mode: no installed copy under the scratch plugin cache"
      check marketplace "$root"
      ;;
  esac
done
