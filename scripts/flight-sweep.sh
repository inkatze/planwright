#!/bin/sh
# flight-sweep.sh — the shared flight sweep and its derived index
# (tower-front-door D-9; REQ-E1.3, REQ-F1.3, REQ-F1.4, REQ-F1.6).
#
# One implementation reconstructs what is in flight for a checkout from
# durable evidence alone, so every surface that renders flights (the tower's
# session start, /resume's tower mode) reads the same derivation and the two
# cannot drift. The evidence, per flight id:
#   - its branch, `planwright/flight/<id>`, local or remote-tracking on origin;
#   - its worktree, registered and not prunable, known by its
#     `.claude/worktrees/flight-<id>` path or its branch;
#   - its landing: a PR for the branch in any state (the draft-PR arm), or the
#     record file `specs/_flights/<id>.md` committed on the branch (the
#     no-remote arm), whichever the home declared at dispatch put there;
#   - its worker's liveness: the dispatch registry's death handle judged by
#     the positive-evidence predicate (scripts/fleet-death-evidence.sh). Only
#     positive evidence of death reads `dead`; no record, a print-rung `none`,
#     or a query mechanism that cannot answer reads `unknown`. Silence is never
#     death;
#   - whether it waits on the operator: its worker's decision-queue row, read
#     from the attention store as the other fleet readers read it.
# A read that fails is named unknown in the render, never shown as empty: the
# forge, registry, and queue rows say which reads were made.
#
# THE INDEX is the render, written under the fleet home at
# `<fleet-home>/flight-index/<checkout-key>.tsv`: outside every checkout, so it
# is never tracked, and per checkout, so it is never a coordination surface. It
# is a cache, not an accumulator. No sweep reads it: each one rebuilds it from
# the evidence above, so deleting it loses nothing, and it owes no drain. Its
# serialization is stable (fixed row order, flights sorted by id, no
# timestamp), so a re-sweep over unchanged evidence reproduces it byte for
# byte; its mtime is when it was last swept.
#
# Subcommands:
#   sweep [--repo-root <dir>] [--no-forge] [--no-write]
#       Derive, write the index, and print it. --no-forge skips the PR reads
#       (landings then rest on record files, and the rest read unknown).
#       --no-write prints the same render and writes nothing, for a surface
#       whose contract forbids writes.
#   path [--repo-root <dir>]
#       Print the checkout's index path, whether or not it exists yet.
#   prune
#       Remove the index of every checkout that no longer exists, one
#       `pruned<TAB><checkout>` line each. The fleet cleanup sweep runs it.
#   hook session-start
#       The SessionStart arm: sweep the session's checkout so a fresh tower
#       reads a current index. Silent and exit 0 always. It stays out of a
#       worker's session (a worker identity in the environment, or a flight or
#       task worktree), and a checkout without flight evidence or an index is
#       left alone with nothing created. Each PR read is bounded by `timeout`
#       (or `gtimeout`) to at most 5 seconds, the reads together to about 15,
#       after which the rest read unknown; with neither binary the PR reads
#       are skipped. The wait a session start can see is that bound, not zero.
#
# Render (TAB-separated), in this order:
#   flight-index<TAB>1
#   checkout<TAB><repo-root>
#   root<TAB>tower|worker<TAB><path><TAB><version>, then root-skew<TAB>yes|no|unknown
#   forge<TAB>ok|partial|unavailable|skipped<TAB><reason or ->
#     reasons: no-flights, no-forge, no-origin (no PR can exist, so a flight
#     without a record file has no landing), no-gh, no-timeout, query-failed,
#     deadline; a fork's PR on a same-named branch is never a flight's landing
#   registry<TAB>ok|unavailable
#   queue<TAB>ok|unavailable
#   flight<TAB><id><TAB><state><TAB><landing><TAB><liveness><TAB><handle><TAB><worktree>
#     state     landed | awaiting-operator | in-air | dead | stranded | unknown
#               (in-air: a worktree and no landing, which includes a worker
#               paused behind a hard pause; stranded: a branch with neither a
#               worktree nor a landing, the residue surfaced rather than lost;
#               unknown: a landing or queue read that could not be made)
#     landing   pr:<url> | record:<path> | none | unknown
#     liveness  alive | dead | unknown, for a flight with a worktree; - otherwise
#     handle    the registered worker handle, or -
#     worktree  its path, or -
# The primary checkout is never a flight's worktree, even with a flight branch
# checked out, and a worktree path carrying a control byte is left out.
#
# Exit codes: 0 swept / printed / pruned; 2 usage or a refused input; 4 the
# fleet home, the worktree list, or the flight branches could not be read, or
# prune's directory is not private or cannot be listed; 5 the render was
# derived and printed but the index could not be written.
#
# PLANWRIGHT_FLIGHT_SWEEP_GH_TIMEOUT bounds each PR read in seconds (default
# 20). Outside the hook, a host with neither `timeout` nor `gtimeout` runs the
# reads unbounded, as the tower's own fallback reads do.
#
# Portable POSIX sh (the bash 3.2 floor); no eval; pathname expansion off.
set -uf
LC_ALL=C
export LC_ALL
unset CDPATH

prog=flight-sweep
TAB=$(printf '\t')
LF='
'

script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
root_dir=$(cd "$script_dir/.." && pwd -P) || exit 2

STATE="$script_dir/fleet-state.sh"
FDE="$script_dir/fleet-death-evidence.sh"
ROOTS="$script_dir/resolve-installed-roots.sh"
COMMON="$script_dir/flight-common.sh"

# A hook must never fail a session start, a broken install included.
in_hook=0
[ "${1:-}" != hook ] || in_hook=1

die() {
  printf '%s: %s\n' "$prog" "$2" >&2
  exit "$1"
}

usage() {
  cat >&2 <<'EOF'
usage: flight-sweep.sh sweep [--repo-root <dir>] [--no-forge] [--no-write]
       flight-sweep.sh path [--repo-root <dir>]
       flight-sweep.sh prune
       flight-sweep.sh hook session-start
EOF
  exit 2
}

for _h in "$STATE" "$FDE" "$ROOTS" "$COMMON"; do
  [ -r "$_h" ] || {
    [ "$in_hook" -eq 0 ] || exit 0
    die 2 "required helper missing: $_h"
  }
done
# shellcheck source=scripts/flight-common.sh
. "$COMMON"

GH_TIMEOUT=${PLANWRIGHT_FLIGHT_SWEEP_GH_TIMEOUT:-20}
case $GH_TIMEOUT in
  '' | *[!0-9]* | 0 | 0[0-9]*) GH_TIMEOUT=20 ;;
esac
[ "${#GH_TIMEOUT}" -le 4 ] || GH_TIMEOUT=20
# The session-start bounds: one PR read, and all of them together. The budget
# is overridable for tests.
HOOK_READ_MAX=5
HOOK_FORGE_BUDGET=${PLANWRIGHT_FLIGHT_SWEEP_HOOK_BUDGET:-15}
case $HOOK_FORGE_BUDGET in
  '' | *[!0-9]* | 0[0-9]*) HOOK_FORGE_BUDGET=15 ;;
esac
[ "${#HOOK_FORGE_BUDGET}" -le 3 ] || HOOK_FORGE_BUDGET=15

# Set only by the hook arm, never from the environment.
session_start=0

repo_root=''
resolve_repo() {
  if [ -z "$repo_root" ]; then
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) \
      || die 2 "not inside a git work tree and no --repo-root given"
  fi
  [ -d "$repo_root" ] || die 2 "--repo-root is not a directory"
  repo_root=$(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null) \
    || die 2 "--repo-root is not inside a git work tree"
  repo_root=$(cd "$repo_root" && pwd -P) || die 2 "cannot resolve --repo-root"
  ! has_ctl "$repo_root" || die 2 "refusing a repo root whose path carries a control character"
}

# resolve_home — set `fleet_home` to the fleet home as fleet-state.sh names
# it, creating nothing.
fleet_home=''
resolve_home() {
  fleet_home=$(/bin/sh "$STATE" root 2>/dev/null </dev/null) || die 4 "cannot resolve the fleet home"
  [ -n "$fleet_home" ] || die 4 "cannot resolve the fleet home"
  ! has_ctl "$fleet_home" || die 2 "refusing a fleet home whose path carries a control character"
}

# index_path — the checkout's index file: its key is the checksum of the
# canonical checkout path, and the file names its checkout on its own line.
index_path() {
  _key=$(printf '%s' "$repo_root" | cksum | awk '{ print $1 }')
  printf '%s/flight-index/%s.tsv\n' "$fleet_home" "$_key"
}

timeout_bin() {
  if command -v timeout >/dev/null 2>&1; then
    echo timeout
  elif command -v gtimeout >/dev/null 2>&1; then
    echo gtimeout
  fi
}

# ID_AWK — keep the lines that are grammar-valid flight ids: scripts/flight-id.sh's
# `<slug>-<uid>` (a kebab slug, an eight-hex uid, 64 characters at most),
# re-encoded so one pass checks every candidate.
# shellcheck disable=SC2016 # awk program text, not shell
ID_AWK='length($0) <= 64 && /^[a-z0-9][a-z0-9-]*-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$/'

# WT_AWK — for each registered, non-prunable flight worktree in a
# `git worktree list --porcelain` stream, print `<id><TAB><path>` for the id
# its path names and, when it differs, the one its branch names. The first
# block is the primary checkout, which a flight branch checked out there does
# not make a flight worktree. A path carrying a control byte is dropped.
# shellcheck disable=SC2016 # awk program text, not shell
WT_AWK='
  BEGIN {
    pfx = "/.claude/worktrees/flight-"
    bfx = "branch refs/heads/planwright/flight/"
  }
  function close_block() {
    if ((pid != "" || bid != "") && !prunable && path !~ /[[:cntrl:]]/) {
      if (pid != "") print pid "\t" path
      if (bid != "" && bid != pid) print bid "\t" path
    }
    pid = ""; bid = ""; prunable = 0; path = ""
  }
  /^worktree / {
    close_block()
    blocks++
    path = substr($0, 10)
    if (match($0, /\/\.claude\/worktrees\/flight-[^\/]+$/)) pid = substr($0, RSTART + length(pfx))
  }
  blocks > 1 && index($0, bfx) == 1 { bid = substr($0, length(bfx) + 1) }
  /^prunable/ { prunable = 1 }
  END { close_block() }'

# liveness <death-handle> — set LIVE to alive|dead|unknown from the positive-
# evidence predicate. The registry column is a hint, so an unrecognized class
# is never passed through; the predicate validates the tokens itself.
LIVE=unknown
liveness() {
  LIVE=unknown
  # shellcheck disable=SC2086 # split the handle into its class and tokens (globbing is off)
  set -- $1
  case ${1:-} in
    process) [ $# -eq 2 ] || return 0 ;;
    tmux-window) [ $# -eq 3 ] || return 0 ;;
    *) return 0 ;;
  esac
  /bin/sh "$FDE" "$@" >/dev/null 2>&1 </dev/null
  case $? in
    0) LIVE=dead ;;
    1) LIVE=alive ;;
  esac
}

# pr_landing <branch> — set PRL to `pr:<url>`, `none`, or `unknown` from the
# forge. `--head` matches the branch name on any fork, so only a PR from the
# repository itself counts; the newest such PR wins. A reply whose first row
# is not well-formed is unknown, never "no PR" (return 1); a query that fails
# outright or times out returns 2, and the caller stops asking.
PRL=unknown
pr_landing() {
  PRL=unknown
  set -- gh pr list --state all --head "$1" --limit 20 \
    --json state,isDraft,url,isCrossRepository \
    --jq '.[] | select(.isCrossRepository | not) | [.state, (.isDraft | tostring), .url] | @tsv'
  [ -z "$TO" ] || set -- "$TO" "$READ_MAX" "$@"
  _prl=$(cd "$repo_root" && GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 NO_COLOR=1 \
    "$@" 2>/dev/null </dev/null) || return 2
  if [ -z "$_prl" ]; then
    PRL=none
    return 0
  fi
  _url=$(printf '%s\n' "$_prl" | awk -F "$TAB" 'NR == 1 &&
    NF == 3 && ($1 == "OPEN" || $1 == "CLOSED" || $1 == "MERGED") \
      && ($2 == "true" || $2 == "false") \
      && $3 ~ /^https:\/\/[A-Za-z0-9.-]+\/[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+\/pull\/[0-9]+$/ { print $3 }')
  [ -n "$_url" ] || return 1
  PRL="pr:$_url"
}

render=''
emit() {
  render="$render$1$LF"
}

cmd_sweep() {
  forge=1
  write=1
  while [ $# -gt 0 ]; do
    case $1 in
      --repo-root)
        [ $# -ge 2 ] || usage
        repo_root=$2
        shift 2
        ;;
      --no-forge)
        forge=0
        shift
        ;;
      --no-write)
        write=0
        shift
        ;;
      *) usage ;;
    esac
  done
  resolve_repo
  resolve_home

  # Branches before worktrees: a placement racing this read then shows up
  # through its worktree rather than as a branch with none (stranded).
  _refs=$(git -C "$repo_root" for-each-ref --format='%(refname)' \
    refs/heads/planwright/flight/ refs/remotes/origin/planwright/flight/ 2>/dev/null </dev/null) \
    || die 4 "cannot list flight branches; nothing was swept"
  _wtl=$(git -C "$repo_root" worktree list --porcelain 2>/dev/null </dev/null) \
    || die 4 "cannot list worktrees; nothing was swept"
  wts=$(printf '%s\n' "$_wtl" | awk "$WT_AWK") || die 4 "cannot read the worktree list; nothing was swept"
  ids=$({
    printf '%s\n' "$_refs" | sed -n -e 's#^refs/heads/planwright/flight/##p' \
      -e 's#^refs/remotes/origin/planwright/flight/##p'
    printf '%s\n' "$wts" | cut -f1
  } | awk "$ID_AWK" | sort -u) || die 4 "cannot read the flight ids; nothing was swept"
  _old_ifs=$IFS

  # The registry and the decision queue are read once each; a failed read
  # leaves the rows it feeds unknown and is named in the render.
  registry_state=ok
  registry=$(/bin/sh "$STATE" registry 2>/dev/null </dev/null) || {
    registry=''
    registry_state=unavailable
  }
  queue_state=ok
  awaiting=''
  _store="$fleet_home/attention/state"
  if [ -e "$_store" ]; then
    awaiting=$(awk -F "$TAB" '$3 == "awaiting-input" { print $1 }' "$_store" 2>/dev/null) \
      || queue_state=unavailable
  fi

  forge_state=ok
  forge_reason=-
  TO=''
  READ_MAX=$GH_TIMEOUT
  if [ "$session_start" -eq 1 ] && [ "$READ_MAX" -gt "$HOOK_READ_MAX" ]; then
    READ_MAX=$HOOK_READ_MAX
  fi
  if [ -z "$ids" ]; then
    forge_state=skipped
    forge_reason=no-flights
  elif [ "$forge" -eq 0 ]; then
    forge_state=skipped
    forge_reason=no-forge
  elif ! git -C "$repo_root" remote get-url origin >/dev/null 2>&1 </dev/null; then
    forge_state=skipped
    forge_reason=no-origin
  elif ! command -v gh >/dev/null 2>&1; then
    forge_state=unavailable
    forge_reason=no-gh
  else
    TO=$(timeout_bin)
    if [ -z "$TO" ] && [ "$session_start" -eq 1 ]; then
      forge_state=skipped
      forge_reason=no-timeout
    fi
  fi

  forge_ok=0
  forge_bad=0
  forge_down=0
  forge_late=0
  forge_until=''
  if [ "$session_start" -eq 1 ]; then
    forge_until=$(($(date +%s) + HOOK_FORGE_BUDGET))
  fi
  flights=''
  IFS=$LF
  for id in $ids; do
    IFS=$_old_ifs
    branch=planwright/flight/$id
    ref=''
    if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch" </dev/null; then
      ref=refs/heads/$branch
    elif git -C "$repo_root" show-ref --verify --quiet "refs/remotes/origin/$branch" </dev/null; then
      ref=refs/remotes/origin/$branch
    fi
    landing=''
    if [ -n "$ref" ] && git -C "$repo_root" cat-file -e "$ref:specs/_flights/$id.md" 2>/dev/null </dev/null; then
      landing="record:specs/_flights/$id.md"
    fi
    if [ -z "$landing" ] && [ "$forge_reason" = no-origin ]; then
      landing=none
    elif [ -z "$landing" ]; then
      landing=unknown
      if [ -n "$forge_until" ] && [ "$forge_down" -eq 0 ] && [ "$(date +%s)" -ge "$forge_until" ]; then
        forge_down=1
        forge_late=1
      fi
      if [ "$forge_state" = ok ] && [ "$forge_down" -eq 0 ]; then
        pr_landing "$branch"
        case $? in
          0)
            landing=$PRL
            forge_ok=$((forge_ok + 1))
            ;;
          1) forge_bad=$((forge_bad + 1)) ;;
          *)
            forge_bad=$((forge_bad + 1))
            forge_down=1
            ;;
        esac
      fi
    fi

    wt=$(printf '%s\n' "$wts" | awk -F "$TAB" -v id="$id" '$1 == id { print $2; exit }')
    rec=$(printf '%s\n' "$registry" | awk -F "$TAB" -v id="$id" '
      ($2 == "tmux-flight-" id || $2 == "print-flight-" id) && $3 == "flight:" id { last = $2 "\t" $7 }
      END { if (last != "") print last }')
    handle=-
    death=''
    if [ -n "$rec" ]; then
      handle=${rec%%"$TAB"*}
      death=${rec#*"$TAB"}
    fi
    live=-
    if [ -n "$wt" ]; then
      liveness "$death"
      live=$LIVE
    fi
    waits=0
    if [ "$handle" != - ] && printf '%s\n' "$awaiting" | grep -Fqx -e "$handle"; then
      waits=1
    fi

    # A verdict short of landed needs every read behind it: an unread landing
    # or queue leaves a worktree flight unknown, unless its worker is
    # positively dead.
    case $landing in
      pr:* | record:*) state=landed ;;
      *)
        if [ -z "$wt" ]; then
          if [ "$landing" = none ]; then
            state=stranded
          else
            state=unknown
          fi
        elif [ "$waits" -eq 1 ]; then
          state='awaiting-operator'
        elif [ "$live" = dead ]; then
          state=dead
        elif [ "$landing" = unknown ] || [ "$queue_state" != ok ]; then
          state=unknown
        else
          state=in-air
        fi
        ;;
    esac
    flights="${flights}flight$TAB$id$TAB$state$TAB$landing$TAB$live$TAB$handle$TAB${wt:--}$LF"
    IFS=$LF
  done
  IFS=$_old_ifs

  if [ "$forge_bad" -gt 0 ] || [ "$forge_late" -eq 1 ]; then
    forge_reason=query-failed
    [ "$forge_late" -eq 0 ] || forge_reason=deadline
    if [ "$forge_ok" -gt 0 ]; then
      forge_state=partial
    else
      forge_state=unavailable
    fi
  fi

  emit "flight-index${TAB}1"
  emit "checkout$TAB$repo_root"
  emit "$(print_root_pair "$root_dir" "$(worker_root)")"
  emit "forge$TAB$forge_state$TAB$forge_reason"
  emit "registry$TAB$registry_state"
  emit "queue$TAB$queue_state"
  render="$render$flights"
  printf '%s' "$render"
  [ "$write" -eq 0 ] || write_index
}

# write_index — replace the checkout's index atomically, in a directory only
# the user can write; the fleet home is created private if absent.
write_index() {
  _idx=$(index_path)
  _dir=${_idx%/*}
  (umask 077 && mkdir -p "$_dir") 2>/dev/null || die 5 "cannot create $_dir; the index was not written"
  private_dir "$fleet_home" \
    || die 5 "the fleet home is not a directory owned by you that only you can write; the index was not written"
  private_dir "$_dir" \
    || die 5 "$_dir is not a directory owned by you that only you can write; the index was not written"
  _tmp=$(umask 077 && mktemp "$_dir/.index.XXXXXX") || die 5 "cannot write the index"
  trap 'rm -f "$_tmp"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  if printf '%s' "$render" >"$_tmp" && mv -f "$_tmp" "$_idx"; then
    trap - EXIT INT TERM HUP
    return 0
  fi
  die 5 "cannot write the index"
}

cmd_path() {
  while [ $# -gt 0 ]; do
    case $1 in
      --repo-root)
        [ $# -ge 2 ] || usage
        repo_root=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  resolve_repo
  resolve_home
  index_path
}

cmd_prune() {
  [ $# -eq 0 ] || usage
  resolve_home
  _dir="$fleet_home/flight-index"
  [ -e "$_dir" ] || [ -L "$_dir" ] || return 0
  private_dir "$_dir" || die 4 "$_dir is not a directory owned by you that only you can write; nothing was pruned"
  _files=$(find "$_dir" -mindepth 1 -maxdepth 1 -type f -name '*.tsv' 2>/dev/null </dev/null) \
    || die 4 "cannot list $_dir; nothing was pruned"
  _old_ifs=$IFS
  IFS=$LF
  for _f in $_files; do
    IFS=$_old_ifs
    _base=${_f##*/}
    case ${_base%.tsv} in
      '' | *[!0-9]*) continue ;;
    esac
    _co=$(awk -F "$TAB" 'NR == 2 && $1 == "checkout" { print $2 }' "$_f" 2>/dev/null)
    case $_co in
      /*) ;;
      *) continue ;;
    esac
    if [ ! -d "$_co" ] && rm -f "$_f"; then
      printf 'pruned\t%s\n' "$(printf '%s' "$_co" | tr -d '\000-\037\177')"
    fi
  done
  IFS=$_old_ifs
}

# cmd_hook session-start — sweep the session's checkout, silently. A worker's
# session is left alone: its checkout shares the tower's flight refs, and a
# sweep there would re-query the forge and cache a copy keyed to the worker.
cmd_hook() {
  [ "${1:-}" = session-start ] && [ $# -eq 1 ] || exit 0
  [ -t 0 ] || cat >/dev/null 2>&1
  [ -z "${PLANWRIGHT_WORKER_HANDLE:-}" ] && [ -z "${PLANWRIGHT_WORKER_SCOPE:-}" ] || exit 0
  _cwd=${CLAUDE_PROJECT_DIR:-$PWD}
  repo_root=$(git -C "$_cwd" rev-parse --show-toplevel 2>/dev/null </dev/null) || exit 0
  case $repo_root in
    */.claude/worktrees/flight-* | */.claude/worktrees/*-task-*) exit 0 ;;
  esac
  _evidence=$(git -C "$repo_root" for-each-ref --count=1 --format=x \
    refs/heads/planwright/flight/ refs/remotes/origin/planwright/flight/ 2>/dev/null </dev/null) || exit 0
  if [ -z "$_evidence" ]; then
    _evidence=$(git -C "$repo_root" worktree list --porcelain 2>/dev/null </dev/null \
      | awk "$WT_AWK" | head -n 1) || exit 0
  fi
  if [ -z "$_evidence" ]; then
    # No flights now: only an index left from earlier ones needs refreshing.
    (resolve_repo && resolve_home && [ -f "$(index_path)" ]) >/dev/null 2>&1 </dev/null || exit 0
  fi
  (
    session_start=1
    cmd_sweep --repo-root "$repo_root"
  ) >/dev/null 2>&1 </dev/null
  exit 0
}

[ $# -ge 1 ] || usage
cmd=$1
shift
case $cmd in
  sweep) cmd_sweep "$@" ;;
  path) cmd_path "$@" ;;
  prune) cmd_prune "$@" ;;
  hook) cmd_hook "$@" ;;
  *) usage ;;
esac
