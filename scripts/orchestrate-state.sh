#!/bin/sh
# orchestrate-state.sh — the task-state derivation engine for a planwright spec
# (orchestration-concurrency Task 1; D-1, D-2, D-3; REQ-C1.1, REQ-C1.2,
# REQ-A1.3, REQ-F1.1).
#
# Progress state is a DERIVED PROJECTION (D-1): it is computed fresh from
# observable git + GitHub evidence, never read from tasks.md section placement
# (which is a discardable read-model snapshot the reconcile owns). This script
# is the shared backbone the reconcile (T4), selection (T5), and the
# structural-corruption guards (T7) all read through, so the derivation lives in
# exactly one place.
#
# For each task defined in <spec-dir>/tasks.md it derives one of four states
# from the authoritative evidence set, applying the REQ-C1.2 precedence (git
# ground truth wins):
#
#   completed   the task branch (planwright/<spec>/task-<id>) is merge-reachable
#               into the base ref, OR a `Planwright-Task: <spec>/<id>` trailer
#               (D-2) is reachable from base, OR gh reports its PR MERGED. The
#               trailer is the durable anchor that survives branch deletion and
#               covers solo direct-to-base commits and squash merges (R2).
#   in-progress the branch exists with commits beyond base (not yet merged), OR
#               gh reports its PR OPEN, OR a FRESH runtime dispatch marker (D-3)
#               holds it across the branch-create → first-commit window.
#   ready       no in-progress/completed evidence and every dependency is
#               completed. A STALE marker (older than the staleness threshold,
#               branch carrying no commits) no longer holds the task: a crashed
#               pre-first-commit dispatch reverts to ready, safe to re-dispatch
#               because dispatch writes no authoritative state (D-3).
#   blocked     no evidence and at least one dependency is not yet completed.
#
# Output — a tagged TSV record stream on stdout (consumers switch on column 1;
# unknown tags are ignored). The contradiction/degraded records are on this
# same stream so they are assertable without the Task 7 guard wired (REQ-C1.2):
#
#   task<TAB><id><TAB><state><TAB><evidence>
#   contradiction<TAB><id><TAB><message>   git-attested completion while gh
#                                          reports the PR still OPEN: the signals
#                                          disagree; git wins, the disagreement
#                                          is surfaced, not silently resolved.
#   degraded<TAB>gh<TAB><message>          a configured gh query failed; the run
#                                          continues git-only (REQ-A1.3).
#   refused<TAB>Planwright-Task<TAB><val>  a malformed/hostile trailer value,
#                                          refused and never used (REQ-F1.1).
#
# No remote is first-class (REQ-A1.3): with no remote configured (or no gh on
# PATH) the gh probe is skipped silently and state derives from git + trailer +
# marker alone. Only a configured-but-failing gh emits a `degraded` record.
#
# Framework-script safety (REQ-F1.1): the spec id, every parsed task id, and
# every Planwright-Task trailer value are validated against their grammar before
# use; a value that fails is refused and never interpolated into a ref, path, or
# pattern. The runtime-marker path is containment-checked under its base dir.
#
# Environment overrides (tests, worktree callers):
#   PLANWRIGHT_BASE_REF        the integration ref reachability is measured
#                              against (default: main → origin/main → HEAD).
#   PLANWRIGHT_ORCH_STATE_DIR  the dir holding per-task runtime markers
#                              (default: <spec-dir>/.orchestrate/markers). The
#                              dispatch writer (T3) and the unified lock (T6)
#                              MUST resolve the same path; D-3's plugin-data home
#                              is reconciled when T6 unifies the lock primitive.
#
# Usage: orchestrate-state.sh <spec-dir>
# Exit: 0 records emitted; 2 the spec dir / tasks.md is missing, unreadable, or
#   holds no task records, or the spec id fails its grammar (fail closed — a
#   malformed input must not silently report "nothing").
#
# Portable POSIX sh + awk; bash 3.2 / BSD tooling. No gawk-only constructs,
# no eval; all external input is treated as data.
set -u

# Pin the C locale: the bracket-range validations below are collation-dependent
# and would otherwise admit non-ASCII under a UTF-8 locale.
LC_ALL=C
export LC_ALL
unset CDPATH

TAB=$(printf '\t')

spec_dir="${1:-}"
if [ -z "$spec_dir" ]; then
  echo "usage: orchestrate-state.sh <spec-dir>" >&2
  exit 2
fi
if [ ! -d "$spec_dir" ]; then
  echo "orchestrate-state: no such spec dir: $spec_dir" >&2
  exit 2
fi
tasks_md="$spec_dir/tasks.md"
if [ ! -f "$tasks_md" ] || [ ! -r "$tasks_md" ]; then
  echo "orchestrate-state: missing or unreadable $tasks_md" >&2
  exit 2
fi

# The spec id is the bundle directory name; validate it against the anchored
# identifier grammar (REQ-A1.8 / D-36) before it appears in any ref or pattern.
spec_id=$(basename "$spec_dir")
case "$spec_id" in
  '' | *[!a-z0-9-]* | [!a-z0-9]*)
    echo "orchestrate-state: invalid spec id '$spec_id'" >&2
    exit 2
    ;;
esac

repo_root=$(cd "$spec_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || repo_root=""
if [ -z "$repo_root" ]; then
  echo "orchestrate-state: $spec_dir is not inside a git work tree" >&2
  exit 2
fi
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# Resolve the base ref reachability is measured against. Prefer a local main
# (the integration line), then a tracked origin/main, then HEAD as a last
# resort. A worktree sitting on a task branch still measures against main, not
# its own tip.
base="${PLANWRIGHT_BASE_REF:-}"
if [ -z "$base" ]; then
  if git -C "$repo_root" show-ref --verify --quiet refs/heads/main; then
    base=main
  elif git -C "$repo_root" show-ref --verify --quiet refs/remotes/origin/main; then
    base=origin/main
  else
    base=HEAD
  fi
fi

# Marker staleness threshold (minutes), via the config reader (defaults + the
# overlay chain). An absent key keeps the documented safe default; a malformed
# value warns and falls back, mirroring the advisory lock.
threshold_min=15
repo_local_cfg="$repo_root/.claude/planwright.local.yml"
tv=$(PLANWRIGHT_LOCAL_CONFIG="$repo_local_cfg" \
  "$script_dir/config-get.sh" stale_marker_threshold 2>/dev/null) || tv=""
tv=${tv%m}
case "$tv" in
  '') ;; # key absent everywhere: the tracked default (15) stands
  *[!0-9]*)
    echo "orchestrate-state: ignoring malformed stale_marker_threshold; using ${threshold_min}m" >&2
    ;;
  *) threshold_min=$tv ;;
esac
threshold_sec=$((threshold_min * 60))

# Runtime-marker base dir, containment-checked so a crafted override cannot
# point the read outside an expected tree (defense in depth; per-task ids are
# grammar-validated below, so a built path can never carry a traversal).
marker_dir="${PLANWRIGHT_ORCH_STATE_DIR:-$spec_dir/.orchestrate/markers}"

now=$(date +%s)

# Collect the Planwright-Task trailer values reachable from base (the completion
# anchors). Each value is validated before use; a malformed/hostile value is
# refused on the output stream and never matched against a task. Well-formed
# values for OTHER specs are simply ignored (not ours, not an error).
reachable_ours=" "
if git -C "$repo_root" rev-parse --verify --quiet "$base" >/dev/null 2>&1; then
  trailer_raw=$(git -C "$repo_root" log "$base" \
    --format='%(trailers:key=Planwright-Task,valueonly)' 2>/dev/null)
  # Iterate values line by line; blank lines (commits without the trailer) are
  # skipped. Read from a here-doc so the loop runs in this shell (no subshell).
  while IFS= read -r tval; do
    [ -n "$tval" ] || continue
    # Strip surrounding whitespace a trailer may carry.
    tval=$(printf '%s' "$tval" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$tval" ] || continue
    # Well-formed shape: <spec-id>/<task-id>, both against their grammars.
    spec_part=${tval%%/*}
    id_part=${tval#*/}
    well_formed=1
    case "$tval" in
      */*) ;;
      *) well_formed=0 ;;
    esac
    case "$spec_part" in
      '' | *[!a-z0-9-]* | [!a-z0-9]*) well_formed=0 ;;
    esac
    case "$id_part" in
      '' | *[!0-9.]*) well_formed=0 ;;
    esac
    if [ "$well_formed" -ne 1 ] || ! printf '%s' "$id_part" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
      printf 'refused%sPlanwright-Task%s%s\n' "$TAB" "$TAB" "$tval"
      continue
    fi
    [ "$spec_part" = "$spec_id" ] || continue # another spec's trailer
    case "$reachable_ours" in
      *" $id_part "*) ;;
      *) reachable_ours="$reachable_ours$id_part " ;;
    esac
  done <<EOF
$trailer_raw
EOF
fi

# Probe gh once for PR state, keyed by head ref. No-remote / no-gh is the
# first-class path: skip the probe silently. Only a configured-but-failing gh
# (remote present, gh on PATH, query errors) emits a degradation record.
gh_lines=""
have_remote=0
[ -n "$(git -C "$repo_root" remote 2>/dev/null)" ] && have_remote=1
if [ "$have_remote" -eq 1 ] && command -v gh >/dev/null 2>&1; then
  if gh_out=$(cd "$repo_root" && gh pr list --state all \
    --json state,headRefName --jq '.[] | [.headRefName, .state] | @tsv' 2>/dev/null); then
    gh_lines=$gh_out
  else
    printf 'degraded%sgh%sgh query failed; deriving git-only\n' "$TAB" "$TAB"
  fi
fi

gh_state_for() {
  # echo the gh state (OPEN|CLOSED|MERGED) for a head ref, empty if none.
  printf '%s\n' "$gh_lines" | awk -F"$TAB" -v b="$1" '$1==b {print $2; exit}'
}

# Pass 1: parse the task records (ids + dependency lists, in file order) and,
# for each, resolve the evidence-only verdict to a work file. Section placement
# is NOT consulted — state is derived, not read (D-1). The work file lines are
#   <id><TAB><evstate><TAB><evidence><TAB><contra><TAB><deps>
# where evstate is completed|in-progress|unresolved, contra is 0|1, and deps is
# a space-separated id list (kept last so embedded spaces are harmless).
work=$(mktemp) || exit 2
trap 'rm -f "$work"' EXIT

tasks=$(awk '
  /^### Task /{
    if (pid != "") print pid "\t" pdeps
    id = $3
    if (id ~ /^[0-9]+(\.[0-9]+)?$/) { pid = id; pdeps = "" } else { pid = "" }
    next
  }
  pid != "" && /\*\*Dependencies:\*\*/{
    s = $0
    sub(/.*\*\*Dependencies:\*\*/, "", s)
    gsub(/[^0-9.]+/, " ", s)
    gsub(/^ +| +$/, "", s)
    pdeps = s
    next
  }
  END { if (pid != "") print pid "\t" pdeps }
' "$tasks_md")

if [ -z "$tasks" ]; then
  echo "orchestrate-state: no task records in $tasks_md" >&2
  exit 2
fi

# Branch-reachability helpers.
branch_exists() { git -C "$repo_root" show-ref --verify --quiet "refs/heads/$1"; }
is_ancestor() { git -C "$repo_root" merge-base --is-ancestor "$1" "$2" 2>/dev/null; }
commits_beyond() { [ "$(git -C "$repo_root" rev-list --count "$2..$1" 2>/dev/null || echo 0)" -gt 0 ]; }

while IFS="$TAB" read -r id deps; do
  [ -n "$id" ] || continue
  branch="planwright/$spec_id/task-$id"

  br_merged=0
  br_commits=0
  if branch_exists "$branch"; then
    if is_ancestor "$branch" "$base"; then
      br_merged=1
    elif commits_beyond "$branch" "$base"; then
      br_commits=1
    fi
  fi

  trailer_done=0
  case "$reachable_ours" in
    *" $id "*) trailer_done=1 ;;
  esac

  gh_state=$(gh_state_for "$branch")
  pr_merged=0
  pr_open=0
  [ "$gh_state" = MERGED ] && pr_merged=1
  [ "$gh_state" = OPEN ] && pr_open=1

  # Fresh runtime marker: only consulted as in-progress evidence, and only
  # meaningful while the branch carries no commits (branch evidence supersedes
  # it). A stale or malformed marker holds nothing — the task reverts to ready.
  marker_fresh=0
  marker_file="$marker_dir/$id"
  if [ -f "$marker_file" ]; then
    # Containment: the resolved marker must sit under its base dir.
    base_real=$(cd "$marker_dir" 2>/dev/null && pwd -P) || base_real=""
    file_real=$(cd "$(dirname "$marker_file")" 2>/dev/null && pwd -P) || file_real=""
    if [ -n "$base_real" ] && [ "$file_real" = "$base_real" ]; then
      mts=$(cat "$marker_file" 2>/dev/null)
      case "$mts" in
        '' | *[!0-9]*) mts="" ;; # malformed timestamp → no hold (fail safe)
      esac
      if [ -n "$mts" ] && [ "$((now - mts))" -le "$threshold_sec" ]; then
        marker_fresh=1
      fi
    fi
  fi

  evstate=unresolved
  # Non-empty placeholder: tab is an IFS-whitespace char, so an empty interior
  # field would collapse on read and shift the columns. Pass 2 overwrites this
  # for unresolved tasks (deps-met / deps-unmet).
  evidence=pending
  contra=0
  if [ "$br_merged" -eq 1 ]; then
    evstate=completed
    evidence="branch-merged"
  elif [ "$trailer_done" -eq 1 ]; then
    evstate=completed
    evidence=trailer
  elif [ "$pr_merged" -eq 1 ]; then
    evstate=completed
    evidence="pr-merged"
  elif [ "$br_commits" -eq 1 ]; then
    evstate=in-progress
    evidence="branch-commits"
  elif [ "$pr_open" -eq 1 ]; then
    evstate=in-progress
    evidence="pr-open"
  elif [ "$marker_fresh" -eq 1 ]; then
    evstate=in-progress
    evidence="marker-fresh"
  fi

  # Contradiction: git ground truth says completed (a merged branch or a
  # reachable trailer) while gh still reports the PR OPEN. The two signals
  # disagree; git wins (state stays completed) but the disagreement is surfaced.
  if { [ "$br_merged" -eq 1 ] || [ "$trailer_done" -eq 1 ]; } && [ "$pr_open" -eq 1 ]; then
    contra=1
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$evstate" "$evidence" "$contra" "$deps" >>"$work"
done <<EOF
$tasks
EOF

# Build the completed set, then emit the final stream. Unresolved tasks resolve
# to ready (every dependency completed) or blocked (a dependency is not).
completed=$(awk -F"$TAB" '$2=="completed"{print $1}' "$work" | tr '\n' ' ')

while IFS="$TAB" read -r id evstate evidence contra deps; do
  [ -n "$id" ] || continue
  case "$evstate" in
    completed | in-progress)
      st=$evstate
      ev=$evidence
      ;;
    *)
      met=1
      for d in $deps; do
        case " $completed " in
          *" $d "*) ;;
          *)
            met=0
            break
            ;;
        esac
      done
      if [ "$met" -eq 1 ]; then
        st=ready
        ev="deps-met"
      else
        st=blocked
        ev="deps-unmet"
      fi
      ;;
  esac
  printf 'task%s%s%s%s%s%s\n' "$TAB" "$id" "$TAB" "$st" "$TAB" "$ev"
  if [ "$contra" = 1 ]; then
    printf 'contradiction%s%s%scompletion attested in git but the PR is still open\n' \
      "$TAB" "$id" "$TAB"
  fi
done <"$work"
