#!/bin/sh
# orchestrate-meta-step.sh — the meta-tower's single-spec step, run in the
# meta-tower's own session rather than in a subordinate tower session.
#
# After orchestrate-meta-select.sh picks `<spec-dir> <id>`, the meta-tower
# calls this script instead of launching a subordinate /orchestrate session.
# It carries the step's mechanical part, in the single-spec tower's order
# (skills/orchestrate/SKILL.md, *The dispatch record*):
#
#   1. take the per-spec lock (scripts/orchestrate-lock.sh); another holder is
#      a clean no-op, so a single-spec tower on the same spec excludes this
#      step and the reverse;
#   2. run the execution freshness gate inside the lock: fetch-before-gate
#      (scripts/dispatch-fetch.sh), then the brief's most recent anchor entry
#      as committed at the ref the fetch resolved, compared against the
#      fetch's recomputed anchor;
#   3. write the dispatch record: scripts/fleet-dispatch-worktree.sh creates
#      the task branch (the first durable act) and its worktree, then stamps
#      the runtime marker;
#   4. release the lock;
#   5. launch the one worker through the rung's own primitive. On the tmux
#      rung the primitive creates and launches in one call, so that launch
#      runs under the lock (it returns once the session exists, the
#      flight-dispatch precedent) and only its confirm runs after release.
#
# The gate checks what a script can: the entry parses, its command is a
# sanctioned form naming this bundle, its `Class:` is `meaning` or
# `expression-only`, and a meaning-class entry carries a `Lens-pass:`. The
# record names no writer beyond its class marking, so writer identity is read
# through that marking.
#
# The worker is /execute-task and nothing else: a prompt whose first
# non-blank line does not invoke it is refused before the lock, so this path
# cannot start a subordinate tower.
#
# Usage:
#   orchestrate-meta-step.sh dispatch <spec-dir> <id> --backend <rung>
#       --prompt-file <file> [--repo-root <dir>] [-- <extra launch args>...]
#     <spec-dir>   the spec bundle as orchestrate-meta-select.sh printed it.
#     <id>         one task id; the meta step dispatches single units.
#     --backend    stream-json-persistent | headless-oneshot | tmux. Other
#                  rungs are refused (exit 2): the harness-native ones belong
#                  to the session itself, and print hands the launch to a
#                  human.
#     --prompt-file  the worker's prompt; its first non-blank line invokes
#                  /execute-task (or /planwright:execute-task).
#     --repo-root  the primary checkout (default: resolve-root.sh repo
#                  --primary).
#     Everything after `--` reaches the rung's launch (the resolved tier).
#
# Report: `meta-step<TAB><key><TAB><value>` lines (lock, gate, anchor, ref,
# branch, worktree, backend, handle), or on a park `halt<TAB><stage><TAB>
# <reason>` plus `remedy<TAB><text>`.
#
# Exit codes:
#   0  dispatched: the record written and the worker launched
#   1  the per-spec lock is held by another tower: nothing done
#   2  usage, a refused input or rung, or a lock refusal; nothing done
#   4  the freshness gate parked the unit (route to `## Awaiting input`);
#      nothing created, lock released
#   5  the dispatch record could not be written (the worktree primitive
#      failed or found the unit already in flight); lock released
#   6  the worker launch failed after the record; the marker is cleared so
#      the unit derives Ready again, and the placed worktree is left for the
#      next dispatch's reconcile
#
# Portable POSIX sh (bash 3.2 / BSD tooling); no eval, every token
# grammar-checked before it reaches a path or a command.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH 2>/dev/null || true

me=orchestrate-meta-step
TAB=$(printf '\t')
script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2

spec_parse_sh="$script_dir/spec-parse.sh"
if [ ! -f "$spec_parse_sh" ] || [ ! -r "$spec_parse_sh" ]; then
  printf '%s\n' "$me: spec-parse.sh missing or unreadable: $spec_parse_sh" >&2
  exit 2
fi
# shellcheck source=scripts/spec-parse.sh
. "$spec_parse_sh" || exit 2

die() {
  printf '%s\n' "$me: $1" >&2
  exit "${2:-2}"
}

usage() {
  die "usage: orchestrate-meta-step.sh dispatch <spec-dir> <id> --backend <stream-json-persistent|headless-oneshot|tmux> --prompt-file <file> [--repo-root <dir>] [-- <extra launch args>...]"
}

[ "$#" -ge 1 ] || usage
[ "$1" = dispatch ] || usage
shift

spec_dir=
task_id=
backend=
prompt_file=
repo_root=
while [ "$#" -gt 0 ]; do
  case $1 in
    --backend | --prompt-file | --repo-root)
      [ "$#" -ge 2 ] || usage
      case $1 in
        --backend) backend=$2 ;;
        --prompt-file) prompt_file=$2 ;;
        --repo-root) repo_root=$2 ;;
      esac
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*) usage ;;
    *)
      if [ -z "$spec_dir" ]; then
        spec_dir=$1
      elif [ -z "$task_id" ]; then
        task_id=$1
      else
        usage
      fi
      shift
      ;;
  esac
done
[ -n "$spec_dir" ] && [ -n "$task_id" ] && [ -n "$backend" ] && [ -n "$prompt_file" ] || usage

# --- input screening (before any side effect) ---------------------------

case $backend in
  stream-json-persistent | headless-oneshot | tmux) ;;
  *) die "rung '$(spec_parse_printable "$backend")' is not carried by the meta step (stream-json-persistent, headless-oneshot, tmux)" ;;
esac

printf '%s' "$task_id" | grep -Eq '^[0-9]+(\.[0-9]+)?$' \
  || die "task id is not a single id (^[0-9]+(\\.[0-9]+)?\$)"

while [ "$spec_dir" != "${spec_dir%/}" ]; do spec_dir=${spec_dir%/}; done
spec_name=${spec_dir##*/}
case $spec_name in
  '' | flight | *[!a-z0-9-]* | [!a-z0-9]*) die "spec name fails the identifier grammar" ;;
esac
[ "${#spec_name}" -le 64 ] || die "spec name longer than 64"
[ -d "$spec_dir" ] || die "not a spec directory: $(spec_parse_printable "$spec_dir")"

[ -f "$prompt_file" ] && [ -r "$prompt_file" ] || die "prompt file missing or unreadable"
first_line=$(awk 'NF { print; exit }' "$prompt_file")
printf '%s\n' "$first_line" | grep -Eq '^/(planwright:)?execute-task( |$)' \
  || die "the prompt's first line does not invoke /execute-task; the meta step launches workers only"

if [ -z "$repo_root" ]; then
  repo_root=$(/bin/sh "$script_dir/resolve-root.sh" repo --primary 2>/dev/null) \
    || die "the primary checkout did not resolve; pass --repo-root"
fi
[ -d "$repo_root" ] || die "repo root is not a directory"

spec_rel=$(git -C "$spec_dir" rev-parse --show-prefix 2>/dev/null) \
  || die "the spec directory is not inside a git work tree"
while [ "$spec_rel" != "${spec_rel%/}" ]; do spec_rel=${spec_rel%/}; done
case $spec_rel in
  */"$spec_name" | "$spec_name") ;;
  *) die "the spec directory does not resolve to a repo-relative bundle path" ;;
esac

wtmp=$(mktemp -d) || exit 2
lock_held=0
release_lock() {
  if [ "$lock_held" -eq 1 ]; then
    "$script_dir/orchestrate-lock.sh" release "$spec_dir" >/dev/null 2>&1 </dev/null || true
    lock_held=0
  fi
}
trap 'release_lock; rm -rf "$wtmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

say() { printf 'meta-step\t%s\t%s\n' "$1" "$2"; }

park() {
  printf 'halt\t%s\t%s\n' "$1" "$2"
  printf 'remedy\t%s\n' "$3"
  exit 4
}

# --- 1. the per-spec lock -----------------------------------------------

lrc=0
"$script_dir/orchestrate-lock.sh" acquire "$spec_dir" >/dev/null 2>"$wtmp/lock.err" </dev/null || lrc=$?
case $lrc in
  0) lock_held=1 ;;
  1)
    say lock busy
    exit 1
    ;;
  *)
    cat "$wtmp/lock.err" >&2
    die "the per-spec lock refused this spec directory (exit $lrc)"
    ;;
esac
say lock held

# --- 2. the execution freshness gate ------------------------------------

frc=0
"$script_dir/dispatch-fetch.sh" --spec "$spec_rel" "$repo_root" >"$wtmp/fetch.out" 2>"$wtmp/fetch.err" </dev/null || frc=$?
case $frc in
  0 | 3) ;;
  4) park fetch stale-transient "retry once the remote answers; never gate against a stale main" ;;
  5) park fetch anchor-unresolved "the bundle could not be anchored at the fetched ref; check it exists on main" ;;
  *) park fetch "dispatch-fetch exit $frc" "inspect the fetch failure before dispatching" ;;
esac
anchor_line=$(awk -F"$TAB" '$1 == "anchor" { print; exit }' "$wtmp/fetch.out")
fetched=$(printf '%s' "$anchor_line" | cut -f2)
ref=$(printf '%s' "$anchor_line" | cut -f3)
printf '%s' "$fetched" | grep -Eq '^[0-9a-f]{40}$' \
  || park fetch "no anchor reported" "inspect dispatch-fetch.sh output"
case $ref in
  '' | -* | *[!A-Za-z0-9._/-]*) park fetch "no usable ref reported" "inspect dispatch-fetch.sh output" ;;
esac

git -C "$repo_root" show "$ref:$spec_rel/kickoff-brief.md" >"$wtmp/brief" 2>/dev/null \
  || park gate no-brief "run /spec-kickoff; the bundle has no kickoff brief at $ref"

erc=0
entry=$(spec_parse_latest_anchor_entry "$wtmp/brief" --record 2>/dev/null) || erc=$?
case $erc in
  0) ;;
  2) park gate unparseable-entry "complete the brief's most recent anchor entry (an older entry is never read in its place)" ;;
  *) park gate no-entry "repair the sign-off record per the meta-spec's execution-validity rules" ;;
esac
recorded=$(printf '%s\n' "$entry" | cut -f1)
cmd=$(printf '%s\n' "$entry" | cut -f2)
class=$(printf '%s\n' "$entry" | cut -f3)
lens=$(printf '%s\n' "$entry" | cut -f4)

case $cmd in
  "scripts/spec-anchor.sh specs/$spec_name" | "spec-anchor.sh specs/$spec_name") ;;
  "git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin") ;;
  *) park gate non-sanctioned-command "repair the sign-off record: its command must be a sanctioned form naming this bundle" ;;
esac
case $class in
  meaning)
    [ -n "$lens" ] || park gate no-lens-pass "a meaning-class entry needs its dispositioned Lens-pass; re-run the /spec-kickoff sign-off"
    ;;
  expression-only) ;;
  *) park gate non-sanctioned-writer "the entry carries no sanctioned Class: marking; repair the sign-off record" ;;
esac
if [ "$recorded" != "$fetched" ]; then
  park gate mismatch "anchored content changed since sign-off (recorded $recorded, $ref has $fetched); run a /spec-kickoff delta re-walkthrough"
fi
say gate match
say anchor "$fetched"
say ref "$ref"

# --- 3. the dispatch record ---------------------------------------------

if [ "$backend" = tmux ]; then
  prompt_text=$(cat "$prompt_file")
  drc=0
  "$script_dir/fleet-dispatch-worktree.sh" dispatch "$spec_name" "$task_id" \
    --repo-root "$repo_root" --launch-only -- "$@" "$prompt_text" \
    >"$wtmp/record.out" 2>"$wtmp/record.err" </dev/null || drc=$?
else
  drc=0
  "$script_dir/fleet-dispatch-worktree.sh" dispatch "$spec_name" "$task_id" \
    --repo-root "$repo_root" --no-attach \
    >"$wtmp/record.out" 2>"$wtmp/record.err" </dev/null || drc=$?
fi
if [ "$drc" -ne 0 ]; then
  cat "$wtmp/record.err" >&2
  printf 'halt\trecord\tfleet-dispatch-worktree exit %s\n' "$drc"
  exit 5
fi
rec_field() {
  awk -F"$TAB" -v t="$1" -v k="$2" '$1 == t && $2 == k { print $3; exit }' "$wtmp/record.out"
}
branch=$(rec_field dispatch branch)
worktree=$(rec_field dispatch worktree)
[ -n "$worktree" ] && [ -d "$worktree" ] || {
  printf 'halt\trecord\tno worktree reported\n'
  exit 5
}
say branch "$branch"
say worktree "$worktree"

# --- 4. release, 5. launch ----------------------------------------------

release_lock
say backend "$backend"

launch_failed() {
  cat "$wtmp/launch.err" >&2 2>/dev/null
  "$script_dir/orchestrate-marker.sh" clear "$spec_dir" "$task_id" >/dev/null 2>&1 </dev/null \
    || printf '%s\n' "$me: the dispatch marker could not be cleared; the unit reads in flight until it ages out" >&2
  printf 'halt\tlaunch\t%s\n' "$1"
  exit 6
}

: >"$wtmp/launch.err"
case $backend in
  tmux)
    handle=$(rec_field launch handle)
    session=$(rec_field launch session)
    since=$(rec_field launch since)
    [ -n "$handle" ] && [ -n "$session" ] || launch_failed "the tmux launch reported no session"
    crc=0
    "$script_dir/fleet-dispatch-worktree.sh" confirm --session "$session" --handle "$handle" \
      --since "${since:-unknown}" >/dev/null 2>"$wtmp/launch.err" </dev/null || crc=$?
    case $crc in
      0 | 14) ;;
      *) launch_failed "tmux confirm exit $crc" ;;
    esac
    ;;
  headless-oneshot)
    [ "$#" -eq 0 ] || set -- -- "$@"
    hrc=0
    "$script_dir/fleet-dispatch-headless.sh" launch "$spec_name" "$task_id" \
      --worktree "$worktree" --repo-root "$repo_root" "$@" \
      <"$prompt_file" >"$wtmp/launch.out" 2>"$wtmp/launch.err" || hrc=$?
    [ "$hrc" -eq 0 ] || launch_failed "fleet-dispatch-headless exit $hrc"
    handle=$(awk -F"$TAB" '$1 == "headless" && $2 == "handle" { print $3; exit }' "$wtmp/launch.out")
    ;;
  stream-json-persistent)
    handle="$spec_name-task-$task_id"
    [ "$#" -eq 0 ] || set -- -- "$@"
    src=0
    "$script_dir/fleet-streamjson.sh" launch "$handle" "$spec_name:task-$task_id" \
      --prompt-file "$prompt_file" --cwd "$worktree" "$@" \
      </dev/null >"$wtmp/launch.out" 2>"$wtmp/launch.err" || src=$?
    [ "$src" -eq 0 ] || launch_failed "fleet-streamjson exit $src"
    ;;
esac
say handle "$handle"
exit 0
