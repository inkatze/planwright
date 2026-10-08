#!/bin/sh
# orchestrate-meta-step.sh — the meta-tower's single-spec step, run in the
# meta-tower's own session.
#
# After orchestrate-meta-select.sh picks `<spec-dir> <id>`, the meta-tower
# calls this script. It carries the step's mechanical part, in the single-spec
# tower's order (skills/orchestrate/SKILL.md, *The dispatch record*):
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
#   5. launch the one worker through the rung's own primitive.
#
# The skill's resource-governance lines and its `orchestrate_dispatch` launch
# tier stay with the caller; this script runs neither.
#
# The gate checks what a script can: the entry parses, its command is a
# sanctioned form naming this bundle, its `Class:` is `meaning` or
# `expression-only`, and a meaning-class entry carries a `Lens-pass:`. The
# record names no writer beyond its class marking, so writer identity is read
# through that marking.
#
# The worker is /execute-task and nothing else: the prompt is copied into a
# private file before it is screened, its first non-blank line must invoke
# /execute-task, and only the screened copy reaches the launch, so this path
# cannot start a tower.
#
# Usage:
#   orchestrate-meta-step.sh dispatch <spec-dir> <id> --backend <rung>
#       --prompt-file <file> [--repo-root <dir>] [-- <extra launch args>...]
#     <spec-dir>   the spec bundle as orchestrate-meta-select.sh printed it,
#                  the primary checkout's own bundle under the default spec
#                  root (a relocated root is refused).
#     <id>         one task id; the meta step dispatches single units.
#     --backend    stream-json-persistent | headless-oneshot. Other rungs are
#                  refused (exit 2): the harness-native ones belong to the
#                  session itself, print hands the launch to a human, and the
#                  tmux primitive takes no prompt through its launch-arg
#                  allowlist.
#     --prompt-file  the worker's prompt; its first non-blank line invokes
#                  /execute-task (or /planwright:execute-task).
#     --repo-root  the primary checkout (default: resolve-root.sh repo
#                  --primary); <spec-dir> must sit at its `specs/<spec>`.
#     Everything after `--` reaches the rung's launch (the resolved tier).
#
# Report: `meta-step<TAB><key><TAB><value>` lines (lock, record, gate, anchor,
# ref, branch, worktree, backend, handle), or on a halt `halt<TAB><stage><TAB>
# <reason>`, plus `remedy<TAB><text>` on a park.
#
# Exit codes:
#   0  dispatched: the record written and the worker launched
#   1  a clean no-op: the per-spec lock is held by another tower, or the unit
#      is already in flight
#   2  usage, a refused input or rung, or a lock or fetch refusal; nothing
#      created
#   4  the freshness gate parked the unit (route to `## Awaiting input`);
#      nothing created, lock released
#   5  the dispatch record could not be written; lock released, and a marker
#      the primitive stamped is cleared
#   6  the worker launch failed after the record. The marker is cleared so the
#      unit derives Ready again, unless the rung may hold a worker for the
#      unit (see launch_failed), which keeps it. The placed worktree is left
#      for the next dispatch's reconcile.
#   129, 130, 141, 143  ended by a signal; the lock is released, and a marker
#      with no launch behind it is cleared
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

# relay <file> — a child's stderr with every control character dropped but TAB
# and newline: C0 and DEL bytes, standalone C1 bytes (invalid UTF-8, which
# iconv -c discards), and C1 characters encoded as UTF-8 (C2 80 to C2 9F).
# Valid UTF-8 text survives, so the children's messages stay readable. Where
# iconv is missing, every C1-range byte goes, at the cost of that text.
relay() {
  [ -s "$1" ] || return 0
  if command -v iconv >/dev/null 2>&1; then
    iconv -c -f UTF-8 -t UTF-8 <"$1" 2>/dev/null \
      | LC_ALL=C sed "s/$(printf '\302')[$(printf '\200')-$(printf '\237')]//g" \
      | tr -d '\000-\010\013-\037\177' >&2
  else
    tr -d '\000-\010\013-\037\177\200-\237' <"$1" >&2
  fi
}

usage() {
  die "usage: orchestrate-meta-step.sh dispatch <spec-dir> <id> --backend <stream-json-persistent|headless-oneshot> --prompt-file <file> [--repo-root <dir>] [-- <extra launch args>...]"
}

[ "$#" -ge 1 ] || usage
[ "$1" = dispatch ] || usage
shift

spec_dir=
task_id=
backend=
prompt_file=
repo_root=
repo_root_given=0
while [ "$#" -gt 0 ]; do
  case $1 in
    --backend | --prompt-file | --repo-root)
      [ "$#" -ge 2 ] || usage
      case $1 in
        --backend) backend=$2 ;;
        --prompt-file) prompt_file=$2 ;;
        --repo-root)
          repo_root=$2
          repo_root_given=1
          ;;
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
  stream-json-persistent | headless-oneshot) ;;
  *) die "rung '$(spec_parse_printable "$backend")' is not carried by the meta step (stream-json-persistent, headless-oneshot)" ;;
esac

# The byte screen comes first: grep matches line by line, so an id carrying a
# newline would otherwise pass on its first line alone.
case $task_id in
  '' | *[!0-9.]*) die "task id is not a single id (^[0-9]+(\\.[0-9]+)?\$)" ;;
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

[ "$repo_root_given" -eq 0 ] || [ -n "$repo_root" ] || die "--repo-root is empty"
if [ -z "$repo_root" ]; then
  repo_root=$(/bin/sh "$script_dir/resolve-root.sh" repo --primary 2>/dev/null) \
    || die "the primary checkout did not resolve; pass --repo-root"
fi
[ -d "$repo_root" ] || die "repo root is not a directory"

# The lock lives in the spec directory, while the gate and the record address
# the primary checkout's bundle. They must be one directory, or a
# single-spec tower locking the primary's copy would not exclude this step.
# dispatch-fetch.sh takes only the default root's repo-relative form, so a
# relocated root is refused here, before the lock, rather than by the fetch.
repo_phys=$(cd "$repo_root" && pwd -P) || die "the repo root cannot be entered"
primary_phys=$(cd "$repo_phys" && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$script_dir/resolve-root.sh" repo --primary 2>/dev/null) \
  || die "the primary checkout did not resolve from --repo-root"
primary_phys=$(cd "$primary_phys" && pwd -P) || die "the primary checkout cannot be entered"
[ "$repo_phys" = "$primary_phys" ] \
  || die "the repo root (--repo-root, else PLANWRIGHT_REPO_ROOT) is not the primary checkout; pass the primary checkout"
spec_root=$(cd "$repo_phys" && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$script_dir/resolve-root.sh" spec --primary 2>/dev/null) \
  || die "the primary checkout's spec root did not resolve"
spec_root_parent=$(cd "${spec_root%/*}" 2>/dev/null && pwd -P) || spec_root_parent=
root_base=${spec_root##*/}
[ "$spec_root_parent" = "$repo_phys" ] && [ "$root_base" = specs ] \
  || die "the spec root is relocated; the dispatch gate reads only the default root"
spec_rel=$root_base/$spec_name
spec_phys=$(cd "$spec_dir" && pwd -P) || die "the spec directory cannot be entered"
primary_spec=$(cd "$spec_root" 2>/dev/null && cd "$spec_name" 2>/dev/null && pwd -P) \
  || die "the primary checkout holds no bundle named $spec_name"
[ "$spec_phys" = "$primary_spec" ] \
  || die "the spec directory is not the primary checkout's bundle; run from the primary checkout"

wtmp=$(mktemp -d) || exit 2
lock_held=0
record_written=0
launch_started=0

clear_marker() {
  "$script_dir/orchestrate-marker.sh" clear "$spec_dir" "$task_id" >/dev/null 2>"$wtmp/marker.err" </dev/null && return 0
  relay "$wtmp/marker.err"
  printf '%s\n' "$me: the dispatch marker could not be cleared; the unit reads in flight until it ages out" >&2
}
release_lock() {
  if [ "$lock_held" -eq 1 ]; then
    "$script_dir/orchestrate-lock.sh" release "$spec_dir" >/dev/null 2>&1 </dev/null || true
    lock_held=0
  fi
}
# shellcheck disable=SC2329 # invoked through the EXIT trap
# A signal can land after the record primitive stamped the marker but before
# its exit status is read; the worktree line it prints only after stamping is
# the evidence then. Here the clear runs before the release; a clear after
# the release (a failed launch) is safe because the marker it removes is
# younger than the liveness window, so no other dispatcher wrote one.
on_exit() {
  if [ "$launch_started" -eq 0 ]; then
    if [ "$record_written" -eq 1 ] \
      || grep -q "^dispatch${TAB}worktree${TAB}" "$wtmp/record.out" 2>/dev/null; then
      clear_marker
    fi
  fi
  release_lock
  rm -rf "$wtmp"
}
trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 141' PIPE
trap 'exit 143' TERM

# The launch reads only this copy, so the file the caller named cannot be
# swapped between the screen and the launch.
prompt=$wtmp/prompt
cp -- "$prompt_file" "$prompt" 2>/dev/null || die "prompt file missing or unreadable"
[ -s "$prompt" ] || die "prompt file is empty"
first_line=$(awk 'NF { print; exit }' "$prompt")
printf '%s\n' "$first_line" | grep -Eq '^/(planwright:)?execute-task( |$)' \
  || die "the prompt's first line does not invoke /execute-task; the meta step launches workers only"

say() { printf 'meta-step\t%s\t%s\n' "$1" "$2"; }

halt() {
  printf 'halt\t%s\t%s\n' "$1" "$2"
}

park() {
  halt "$1" "$2"
  printf 'remedy\t%s\n' "$3"
  exit 4
}

# field <file> <tag> <key> — the value of a `<tag><TAB><key><TAB><value>` line.
field() {
  awk -F"$TAB" -v t="$2" -v k="$3" '$1 == t && $2 == k { print $3; exit }' "$1"
}

# --- 1. the per-spec lock -----------------------------------------------

lock_rc=0
"$script_dir/orchestrate-lock.sh" acquire "$spec_dir" >/dev/null 2>"$wtmp/lock.err" </dev/null || lock_rc=$?
relay "$wtmp/lock.err"
case $lock_rc in
  0) lock_held=1 ;;
  1)
    say lock busy
    exit 1
    ;;
  *) die "the per-spec lock refused this spec directory (exit $lock_rc)" ;;
esac
say lock held

# --- 2. the execution freshness gate ------------------------------------

fetch_rc=0
"$script_dir/dispatch-fetch.sh" --spec "$spec_rel" "$repo_root" >"$wtmp/fetch.out" 2>"$wtmp/fetch.err" </dev/null || fetch_rc=$?
[ "$fetch_rc" -eq 0 ] || relay "$wtmp/fetch.err"
case $fetch_rc in
  0 | 3) ;;
  2) die "dispatch-fetch refused the request (exit 2)" ;;
  4) park fetch stale-transient "retry once the remote answers; never gate against a stale main" ;;
  5) park fetch anchor-unresolved "the bundle could not be anchored at the fetched ref; check it exists on main" ;;
  *) park fetch "dispatch-fetch exit $fetch_rc" "inspect the fetch failure before dispatching" ;;
esac
fetched_anchor=$(awk -F"$TAB" '$1 == "anchor" { print $2; exit }' "$wtmp/fetch.out")
ref=$(awk -F"$TAB" '$1 == "anchor" { print $3; exit }' "$wtmp/fetch.out")
printf '%s' "$fetched_anchor" | grep -Eq '^[0-9a-f]{40}$' \
  || park fetch "no anchor reported" "inspect dispatch-fetch.sh output"
case $ref in
  '' | -* | *[!A-Za-z0-9._/-]*) park fetch "no usable ref reported" "inspect dispatch-fetch.sh output" ;;
esac

if ! git -C "$repo_root" cat-file -e "$ref:$spec_rel/kickoff-brief.md" 2>/dev/null; then
  park gate no-brief "run /spec-kickoff; the bundle has no kickoff brief at $ref"
fi
git -C "$repo_root" show "$ref:$spec_rel/kickoff-brief.md" >"$wtmp/brief" 2>"$wtmp/show.err" || {
  relay "$wtmp/show.err"
  park gate brief-unreadable "the kickoff brief at $ref could not be read; inspect the repository"
}

entry_rc=0
entry=$(spec_parse_latest_anchor_entry "$wtmp/brief" --record 2>"$wtmp/entry.err") || entry_rc=$?
case $entry_rc in
  0) ;;
  1) park gate no-entry "repair the sign-off record per the meta-spec's execution-validity rules" ;;
  2)
    relay "$wtmp/entry.err"
    park gate unparseable-entry "complete the brief's most recent anchor entry, one Class and one Lens-pass line at most (an older entry is never read in its place)"
    ;;
  *)
    relay "$wtmp/entry.err"
    park gate "entry parse exit $entry_rc" "inspect the brief parse failure"
    ;;
esac
recorded=$(printf '%s\n' "$entry" | cut -f1)
cmd=$(printf '%s\n' "$entry" | cut -f2)
class=$(printf '%s\n' "$entry" | cut -f3)
lens=$(printf '%s\n' "$entry" | cut -f4)

case $cmd in
  "scripts/spec-anchor.sh specs/$spec_name" | "spec-anchor.sh specs/$spec_name") ;;
  "git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin")
    park gate pre-change-entry "the entry uses the interim whole-file form; classify the delta since it, then take the one-time self-re-anchor the meta-spec describes"
    ;;
  *) park gate non-sanctioned-command "repair the sign-off record: its command must be a sanctioned form naming this bundle" ;;
esac
case $class in
  meaning)
    [ -n "$lens" ] || park gate no-lens-pass "a meaning-class entry needs its dispositioned Lens-pass; re-run the /spec-kickoff sign-off"
    ;;
  expression-only) ;;
  *) park gate non-sanctioned-writer "the entry carries no sanctioned Class: marking; repair the sign-off record" ;;
esac
if [ "$recorded" != "$fetched_anchor" ]; then
  park gate mismatch "anchored content changed since sign-off (recorded $recorded, $ref has $fetched_anchor); run a /spec-kickoff delta re-walkthrough"
fi
say gate match
say anchor "$fetched_anchor"
say ref "$ref"

# --- 3. the dispatch record ---------------------------------------------

record_rc=0
"$script_dir/fleet-dispatch-worktree.sh" dispatch "$spec_name" "$task_id" \
  --repo-root "$repo_root" --no-attach \
  >"$wtmp/record.out" 2>"$wtmp/record.err" </dev/null || record_rc=$?
relay "$wtmp/record.err"
case $record_rc in
  0) record_written=1 ;;
  3)
    say record in-flight
    exit 1
    ;;
  *)
    halt record "fleet-dispatch-worktree exit $record_rc"
    exit 5
    ;;
esac
branch=$(field "$wtmp/record.out" dispatch branch)
worktree=$(field "$wtmp/record.out" dispatch worktree)
if [ -z "$worktree" ] || [ ! -d "$worktree" ]; then
  halt record "no worktree reported"
  exit 5
fi
say branch "$branch"
say worktree "$worktree"

# --- 4. release, 5. launch ----------------------------------------------

release_lock
say backend "$backend"

# launch_failed <rc> <reason> [keep] — keep the marker when the rung may have
# a worker for the unit: exit 3 from either rung reports one in flight, and
# fleet-streamjson.sh's startup-timeout exit 2 follows a supervisor it already
# spawned. Every other failure launched nothing.
launch_failed() {
  relay "$wtmp/launch.err"
  if [ "$1" -eq 3 ] || [ "${3:-}" = keep ]; then
    halt launch "$2 (the rung may hold a worker for the unit; its marker is kept)"
  else
    clear_marker
    halt launch "$2"
  fi
  exit 6
}

[ "$#" -eq 0 ] || set -- -- "$@"
launch_rc=0
case $backend in
  headless-oneshot)
    launch_started=1
    "$script_dir/fleet-dispatch-headless.sh" launch "$spec_name" "$task_id" \
      --worktree "$worktree" --repo-root "$repo_root" "$@" \
      <"$prompt" >"$wtmp/launch.out" 2>"$wtmp/launch.err" || launch_rc=$?
    [ "$launch_rc" -eq 0 ] || launch_failed "$launch_rc" "fleet-dispatch-headless exit $launch_rc"
    handle=$(field "$wtmp/launch.out" headless handle)
    [ -n "$handle" ] || handle="headless-$spec_name-task-$task_id"
    ;;
  stream-json-persistent)
    handle="$spec_name-task-$task_id"
    launch_started=1
    "$script_dir/fleet-streamjson.sh" launch "$handle" "$spec_name:task-$task_id" \
      --prompt-file "$prompt" --cwd "$worktree" "$@" \
      </dev/null >"$wtmp/launch.out" 2>"$wtmp/launch.err" || launch_rc=$?
    if [ "$launch_rc" -eq 2 ] && grep -q 'did not start within' "$wtmp/launch.err" 2>/dev/null; then
      launch_failed 2 "fleet-streamjson exit 2" keep
    fi
    [ "$launch_rc" -eq 0 ] || launch_failed "$launch_rc" "fleet-streamjson exit $launch_rc"
    ;;
esac
relay "$wtmp/launch.err"
say handle "$handle"
exit 0
