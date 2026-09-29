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
#   - whether it waits on the operator: its worker's decision-queue row.
# A read that fails is named unknown in the render, never shown as empty.
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
#   sweep [--repo-root <dir>] [--no-forge]
#       Derive, write the index, and print it. --no-forge skips the PR reads
#       (landings then rest on record files, and the rest read unknown).
#   path [--repo-root <dir>]
#       Print the checkout's index path, whether or not it exists yet.
#   prune
#       Remove the index of every checkout that no longer exists, one
#       `pruned<TAB><checkout>` line each. The fleet cleanup sweep runs it.
#   hook session-start
#       The SessionStart arm: sweep the session's checkout so a fresh tower
#       reads a current index. Silent and exit 0 always; a checkout without
#       flight evidence or an index is left alone, and nothing is created. The
#       PR reads are bounded by `timeout` (or `gtimeout`) and skipped where
#       neither exists, so a session start never waits on the network.
#
# Render (TAB-separated), in this order:
#   flight-index<TAB>1
#   checkout<TAB><repo-root>
#   root<TAB>tower|worker<TAB><path><TAB><version>, then root-skew<TAB>yes|no|unknown
#   forge<TAB>ok|partial|unavailable|skipped<TAB><reason or ->
#   queue<TAB>ok|unavailable
#   flight<TAB><id><TAB><state><TAB><landing><TAB><liveness><TAB><handle><TAB><worktree>
#     state     landed | awaiting-operator | in-air | dead | stranded | unknown
#               (stranded: a branch with neither a worktree nor a landing, the
#               residue surfaced rather than lost; unknown: no worktree and a
#               forge that could not be read)
#     landing   pr:<url> | record:<path> | none | unknown
#     liveness  alive | dead | unknown, for a flight with a worktree; - otherwise
#     handle    the registered worker handle, or -
#     worktree  its path, or -
#
# Exit codes: 0 swept / printed / pruned; 2 usage or a refused input; 4 the
# fleet home or the worktree list could not be read, or the index could not be
# written (the render is still printed when it was derived).
#
# PLANWRIGHT_FLIGHT_SWEEP_GH_TIMEOUT bounds each PR read in seconds (default 20).
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
FLIGHT_ID="$script_dir/flight-id.sh"
FDE="$script_dir/fleet-death-evidence.sh"
ROOTS="$script_dir/resolve-installed-roots.sh"
ROOTPAIR="$script_dir/flight-roots.sh"

die() {
  printf '%s: %s\n' "$prog" "$2" >&2
  exit "$1"
}

usage() {
  cat >&2 <<'EOF'
usage: flight-sweep.sh sweep [--repo-root <dir>] [--no-forge]
       flight-sweep.sh path [--repo-root <dir>]
       flight-sweep.sh prune
       flight-sweep.sh hook session-start
EOF
  exit 2
}

for _h in "$STATE" "$FLIGHT_ID" "$FDE" "$ROOTS" "$ROOTPAIR"; do
  [ -r "$_h" ] || die 2 "required helper missing: $_h"
done
# shellcheck source=scripts/flight-roots.sh
. "$ROOTPAIR"

GH_TIMEOUT=${PLANWRIGHT_FLIGHT_SWEEP_GH_TIMEOUT:-20}
case $GH_TIMEOUT in
  '' | *[!0-9]* | 0 | 0[0-9]*) GH_TIMEOUT=20 ;;
esac
[ "${#GH_TIMEOUT}" -le 4 ] || GH_TIMEOUT=20

has_ctl() {
  [ "$(printf '%s' "$1" | tr -d '\000-\037\177')" != "$1" ]
}

# private_dir <dir> — a real directory the invoking user owns that neither
# group nor others can write.
private_dir() {
  [ ! -L "$1" ] && [ -d "$1" ] || return 1
  _pd_uid=$(id -u) || return 1
  [ -n "$(find "$1" -maxdepth 0 -user "$_pd_uid" ! -perm -0020 ! -perm -0002 2>/dev/null)" ]
}

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

# valid_id <id> — the flight-id grammar, judged by its reference check.
valid_id() {
  /bin/sh "$FLIGHT_ID" check "$1" 2>/dev/null </dev/null
}

# WT_AWK — for each registered, non-prunable flight worktree in a
# `git worktree list --porcelain` stream, print `<id><TAB><path>` for the id
# its path names and, when it differs, the one its branch names. The offsets
# are the lengths of `/.claude/worktrees/flight-` (26) and
# `branch refs/heads/planwright/flight/` (36), plus one.
# shellcheck disable=SC2016 # awk program text, not shell
WT_AWK='
  function close_block() {
    if ((pid != "" || bid != "") && !prunable) {
      if (pid != "") print pid "\t" path
      if (bid != "" && bid != pid) print bid "\t" path
    }
    pid = ""; bid = ""; prunable = 0; path = ""
  }
  /^worktree / {
    close_block()
    path = substr($0, 10)
    if (match($0, /\/\.claude\/worktrees\/flight-[^\/]+$/)) pid = substr($0, RSTART + 26)
  }
  index($0, "branch refs/heads/planwright/flight/") == 1 { bid = substr($0, 37) }
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
# forge. A reply that is not one well-formed row is unknown, never "no PR"
# (return 1); a query that fails outright returns 2, and the caller stops
# asking a forge that is not answering.
PRL=unknown
pr_landing() {
  PRL=unknown
  if [ -n "$TO" ]; then
    _prl=$(cd "$repo_root" && GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 NO_COLOR=1 \
      "$TO" "$GH_TIMEOUT" gh pr list --state all --head "$1" --limit 1 \
      --json state,isDraft,url --jq '.[] | [.state, (.isDraft | tostring), .url] | @tsv' \
      2>/dev/null </dev/null) || return 2
  else
    _prl=$(cd "$repo_root" && GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 NO_COLOR=1 \
      gh pr list --state all --head "$1" --limit 1 \
      --json state,isDraft,url --jq '.[] | [.state, (.isDraft | tostring), .url] | @tsv' \
      2>/dev/null </dev/null) || return 2
  fi
  if [ -z "$_prl" ]; then
    PRL=none
    return 0
  fi
  case $_prl in
    *"$LF"*) return 1 ;;
  esac
  _url=$(printf '%s\n' "$_prl" | awk -F "$TAB" '
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
      *) usage ;;
    esac
  done
  resolve_repo
  resolve_home

  _wtl=$(git -C "$repo_root" worktree list --porcelain 2>/dev/null </dev/null) \
    || die 4 "cannot list worktrees; nothing was swept"
  wts=$(printf '%s\n' "$_wtl" | awk "$WT_AWK" | tr -d '\000-\010\013-\037\177') \
    || die 4 "cannot read the worktree list; nothing was swept"
  _refs=$(git -C "$repo_root" for-each-ref --format='%(refname)' \
    refs/heads/planwright/flight/ refs/remotes/origin/planwright/flight/ 2>/dev/null </dev/null) \
    || die 4 "cannot list flight branches; nothing was swept"
  _cands=$({
    printf '%s\n' "$_refs" | sed -n -e 's#^refs/heads/planwright/flight/##p' \
      -e 's#^refs/remotes/origin/planwright/flight/##p'
    printf '%s\n' "$wts" | cut -f1
  } | awk 'NF' | sort -u)
  ids=''
  _old_ifs=$IFS
  IFS=$LF
  for _c in $_cands; do
    valid_id "$_c" && ids="$ids$_c$LF"
  done
  IFS=$_old_ifs

  # The registry and the decision queue are read once each. A registry that
  # cannot be read leaves every liveness unknown; a queue that cannot be read
  # is named in the render.
  registry=$(/bin/sh "$STATE" registry 2>/dev/null </dev/null) || registry=''
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
  if [ -z "$ids" ]; then
    forge_state=skipped
    forge_reason=no-flights
  elif [ "$forge" -eq 0 ]; then
    forge_state=skipped
    forge_reason=no-forge
  elif ! command -v gh >/dev/null 2>&1; then
    forge_state=unavailable
    forge_reason=no-gh
  elif ! git -C "$repo_root" remote get-url origin >/dev/null 2>&1 </dev/null; then
    forge_state=unavailable
    forge_reason=no-origin
  else
    TO=$(timeout_bin)
    if [ -z "$TO" ] && [ "${hook_mode:-0}" -eq 1 ]; then
      forge_state=skipped
      forge_reason=no-timeout
    fi
  fi

  forge_ok=0
  forge_bad=0
  forge_down=0
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
    if [ -z "$landing" ]; then
      landing=unknown
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

    case $landing in
      pr:* | record:*) state=landed ;;
      *)
        if [ -n "$wt" ]; then
          if [ "$waits" -eq 1 ]; then
            state='awaiting-operator'
          elif [ "$live" = dead ]; then
            state=dead
          else
            state=in-air
          fi
        elif [ "$landing" = none ]; then
          state=stranded
        else
          state=unknown
        fi
        ;;
    esac
    flights="${flights}flight$TAB$id$TAB$state$TAB$landing$TAB$live$TAB$handle$TAB${wt:--}$LF"
    IFS=$LF
  done
  IFS=$_old_ifs

  if [ "$forge_bad" -gt 0 ]; then
    forge_reason=query-failed
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
  emit "queue$TAB$queue_state"
  render="$render$flights"
  printf '%s' "$render"
  write_index
}

# write_index — replace the checkout's index atomically, in a directory only
# the user can write; the fleet home is created private if absent.
write_index() {
  _idx=$(index_path)
  _dir=${_idx%/*}
  (umask 077 && mkdir -p "$_dir") 2>/dev/null || die 4 "cannot create $_dir; the index was not written"
  private_dir "$fleet_home" \
    || die 4 "the fleet home is not a directory owned by you that only you can write; the index was not written"
  private_dir "$_dir" \
    || die 4 "$_dir is not a directory owned by you that only you can write; the index was not written"
  _tmp=$(umask 077 && mktemp "$_dir/.index.XXXXXX") || die 4 "cannot write the index"
  if printf '%s' "$render" >"$_tmp" && mv -f "$_tmp" "$_idx"; then
    return 0
  fi
  rm -f "$_tmp"
  die 4 "cannot write the index"
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

# cmd_hook session-start — sweep the session's checkout, silently.
cmd_hook() {
  [ "${1:-}" = session-start ] && [ $# -eq 1 ] || exit 0
  [ -t 0 ] || cat >/dev/null 2>&1
  _cwd=${CLAUDE_PROJECT_DIR:-$PWD}
  repo_root=$(git -C "$_cwd" rev-parse --show-toplevel 2>/dev/null </dev/null) || exit 0
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
    hook_mode=1
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
