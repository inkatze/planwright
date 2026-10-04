#!/bin/sh
# orchestrate-marker.sh — the runtime dispatch-marker WRITER, the dispatch-path
# counterpart to orchestrate-state.sh's marker READER (orchestration-concurrency
# Task 3; D-1, D-3; REQ-A1.1, REQ-A1.2, REQ-F1.1).
#
# A dispatch writes NO authoritative state (D-1): the task branch (the first
# durable act) plus this timestamped runtime marker ARE the dispatch record.
# The marker covers exactly the branch-create → first-commit window — a
# zero-commit branch is not yet In-progress evidence (REQ-C1.1), so the marker
# holds the task In progress until its branch carries a commit, after which
# branch evidence supersedes it (D-3). It is a discardable local artifact, never
# committed (gitignored alongside the advisory lock), so `main` carries no
# dispatch commit and a worker worktree cut from it inherits nothing foreign —
# contamination is impossible by construction (REQ-A1.2), not merely mitigated.
#
# Path contract: the writer MUST resolve the SAME marker dirs the readers do,
# so a marker dropped here is the marker the derivation engine reads from any
# worktree of the repository. Both ask orchestrate-marker-home.sh, which places
# the shared home under the common git dir and keeps the checkout-local
# <spec-dir>/.orchestrate/markers beside it; PLANWRIGHT_ORCH_STATE_DIR, a
# trusted operator/test knob, replaces both.
# The marker is one regular file per task id; its content is one integer (the
# epoch seconds at write). A cohesion bundle dispatches >1 task id, so `write`
# takes one or more ids and drops a marker per task.
#
# REQ-F1.1 (parsed input is data, never an executed path): every task id is
# validated against the per-task id grammar `^[0-9]+(\.[0-9]+)?$` BEFORE it is
# used to build a path. Markers are per individual task — the bundle-range form
# `5-6` is a branch suffix, never a marker filename — so a range, a traversal
# (`../x`), a glob, shell metacharacters, or any out-of-grammar token is a clean
# refusal (exit 2, nothing written), never an out-of-tree path. Validation is
# all-or-nothing across a batch: one hostile id refuses the whole write before
# any marker is dropped. A symlink — or any other non-regular file (e.g. a
# directory) — at the marker path is refused, not written through (the read-time
# symlink-swap guard's write-time counterpart), and the derived path is
# containment-checked under its base dir before the write.
#
# A single write is atomic (write-temp-then-rename within the marker dir), so a
# concurrent reader never sees a torn marker. A multi-id (bundle) write runs in
# two phases — validate-and-stage a temp per id, then rename them all — so a
# failure while staging places no marker at all (all-or-nothing through the
# fragile path); the unavoidable residual (POSIX has no multi-file atomic
# rename) never deletes an already-placed marker to undo a partial batch.
#
# Usage: orchestrate-marker.sh write|clear <spec-dir> <id> [<id>...]
#   write   drop a fresh timestamped marker per id in every write dir (mkdir -p
#           each).
#   clear   remove the marker per id from every read dir (idempotent: a missing
#           marker is fine; a real removal failure is surfaced fail-closed,
#           not swallowed).
# Exit: 0 success; 2 usage error, a missing spec dir, a refused (malformed/
#   hostile) id, a symlink/containment refusal, or a write/removal failure (fail
#   closed).
#
# Portable POSIX sh + `mktemp`/`date`; bash 3.2 / BSD tooling (the same floor as
# the reader). No eval; all input treated as data. Pathname expansion is disabled
# (set -f): the script does no intentional globbing, so an id like `*` is taken
# literally and refused by the grammar rather than expanded.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

cmd="${1:-}"
spec_dir="${2:-}"
if [ -z "$cmd" ] || [ -z "$spec_dir" ]; then
  echo "usage: orchestrate-marker.sh write|clear <spec-dir> <id> [<id>...]" >&2
  exit 2
fi
case "$cmd" in
  write | clear) ;;
  *)
    echo "orchestrate-marker: unknown command '$cmd' (write|clear)" >&2
    exit 2
    ;;
esac
if [ ! -d "$spec_dir" ]; then
  echo "orchestrate-marker: no such spec dir: $spec_dir" >&2
  exit 2
fi
shift 2
if [ "$#" -eq 0 ]; then
  echo "orchestrate-marker: $cmd needs at least one task id" >&2
  exit 2
fi

# Validate every id against the per-task id grammar BEFORE any path is built or
# any marker written (REQ-F1.1, all-or-nothing). The charset gate refuses any
# token carrying a character outside [0-9.] (so a slash, '-', glob, space, or
# shell metacharacter never reaches a path); the grammar then refuses the
# charset-valid-but-malformed residue (`..`, `1.`, `1.2.3`). The bundle-range
# form `5-6` fails the charset gate by design — markers are per individual task.
for id in "$@"; do
  case "$id" in
    '' | *[!0-9.]*)
      echo "orchestrate-marker: refusing malformed task id '$id' (REQ-F1.1: must match ^[0-9]+(\.[0-9]+)?\$)" >&2
      exit 2
      ;;
  esac
  if ! printf '%s' "$id" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
    echo "orchestrate-marker: refusing malformed task id '$id' (REQ-F1.1: must match ^[0-9]+(\.[0-9]+)?\$)" >&2
    exit 2
  fi
done

# Diagnostics carry paths, so they are stripped of control bytes and printed
# with printf, never echo (dash's echo turns a backslash sequence into a live
# escape).
say() {
  printf 'orchestrate-marker: %s\n' "$(printf '%s' "$1" | tr -d '\000-\037\177')" >&2
}

# The marker dirs come from orchestrate-marker-home.sh, which every reader asks
# too: `write` places a marker in each write dir, `clear` removes it from each
# read dir, so a marker an older writer left in the primary checkout is cleared
# along with this one. A copy an older writer left in another linked worktree
# is outside both lists and ages out at the staleness threshold. The per-id
# hardening (symlink refusal + containment) is at the path, below.
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
home_cmd="write"
[ "$cmd" = clear ] && home_cmd="read"
marker_dirs=$(/bin/sh "$script_dir/orchestrate-marker-home.sh" "$home_cmd" "$spec_dir") || {
  say "cannot resolve the marker dirs for $spec_dir"
  exit 2
}
[ -n "$marker_dirs" ] || {
  say "no marker dir resolved for $spec_dir"
  exit 2
}
nl='
'
tab=$(printf '\t')

# The helper prints canonical paths, so a dir whose own `pwd -P` differs was
# reached through a symlink and is refused rather than written or cleared
# through. The override is a trusted knob, printed as given, and not checked.
override=0
[ -n "${PLANWRIGHT_ORCH_STATE_DIR:-}" ] && override=1
canonical_ok() {
  [ "$override" -eq 1 ] && return 0
  [ "$(cd -P -- "$1" 2>/dev/null && pwd -P)" = "$1" ]
}
# The same check on the deepest part of a not-yet-created dir that exists, so
# `mkdir -p` never follows a planted symlink into creating dirs elsewhere.
ancestor_ok() {
  [ "$override" -eq 1 ] && return 0
  _a=$1
  while [ ! -e "$_a" ] && [ ! -L "$_a" ]; do
    _a=${_a%/*}
    [ -n "$_a" ] || _a=/
  done
  [ ! -L "$_a" ] && [ -d "$_a" ] && canonical_ok "$_a"
}

if [ "$cmd" = clear ]; then
  # Idempotent removal. rm -f on a missing path is a no-op (exit 0); on a symlink
  # it removes the link itself, never follows it. A real removal failure (e.g. an
  # unwritable marker dir) is surfaced fail-closed (exit 2) rather than swallowed,
  # so a clean exit always means the marker is gone — matching the script's
  # fail-closed contract everywhere else. Every id is attempted in every dir
  # before exiting, so one stuck marker never strands the rest of the cleanup.
  rc=0
  while IFS= read -r marker_dir; do
    [ -d "$marker_dir" ] || continue
    if ! canonical_ok "$marker_dir"; then
      say "skipping marker dir $marker_dir: reached through a symlink"
      continue
    fi
    for id in "$@"; do
      if ! rm -f "$marker_dir/$id" 2>/dev/null; then
        say "cannot remove marker for task $id in $marker_dir"
        rc=2
      fi
    done
  done <<EOF
$marker_dirs
EOF
  exit "$rc"
fi

# write: create the base dirs only now that every id has passed validation, so a
# refused write leaves no marker state behind. The checkout-local dir (or the
# override), always last, must be usable; a shared home that cannot be made or
# is reached through a symlink is dropped with a warning, so a dispatch never
# loses its marker for want of one.
last=${marker_dirs##*"$nl"}
kept=''
while IFS= read -r marker_dir; do
  why=''
  if ! ancestor_ok "$marker_dir"; then
    why="reached through a symlink"
  elif ! mkdir -p "$marker_dir" 2>/dev/null; then
    why="cannot create it"
  elif ! canonical_ok "$marker_dir"; then
    why="reached through a symlink"
  fi
  if [ -n "$why" ]; then
    if [ "$marker_dir" = "$last" ]; then
      say "cannot use marker dir $marker_dir: $why"
      exit 2
    fi
    say "skipping the shared marker dir $marker_dir ($why); other worktrees will not see this marker"
    continue
  fi
  kept="$kept$marker_dir$nl"
done <<EOF
$marker_dirs
EOF

now=$(date +%s)
case "$now" in
  '' | *[!0-9]*)
    say "could not read a numeric timestamp"
    exit 2
    ;;
esac

# Two-phase write so a multi-id (bundle) or multi-dir dispatch is all-or-nothing
# through the fragile part: phase 1 validates each marker path and stages a
# complete temp marker per id and dir (nothing placed yet); phase 2 renames the
# staged temps into place. Any failure while staging rolls back every staged
# temp and exits 2 with no marker placed. Same-dir renames after staging do not
# fail under normal conditions; POSIX has no multi-file atomic rename, so the
# residual (a rename failing after a sibling already landed) is documented, not
# eliminated — and we never delete an already-placed (possibly pre-existing)
# marker to "undo" a partial batch, which would revert a legitimately
# in-progress task.
#
# The manifest lives in the last dir, the one the write cannot do without, and
# names each temp's dir by its position in the kept list, so no path, whatever
# bytes it carries, is ever split out of a manifest line.
manifest=$(mktemp "$last/.manifest.XXXXXX") || {
  say "cannot create a staging manifest in $last"
  exit 2
}
dir_at() {
  printf '%s' "$kept" | sed -n "${1}p"
}
# Remove every still-staged temp recorded in the manifest, then the manifest
# itself. A temp already renamed into place no longer exists at its staged path,
# so its rm is a harmless no-op — rollback never touches a placed marker.
roll_back_staged() {
  while IFS="$tab" read -r _rb_n _rb_id _rb_tmp; do
    [ -n "$_rb_tmp" ] && rm -f "$(dir_at "$_rb_n")/$_rb_tmp"
  done <"$manifest"
  rm -f "$manifest"
}

# Phase 1 — validate every marker path and stage a temp marker per id and dir.
# The temp lives in its marker dir, so the phase-2 rename is same-filesystem.
n=0
while IFS= read -r marker_dir; do
  [ -n "$marker_dir" ] || continue
  n=$((n + 1))
  base_real=$(cd "$marker_dir" 2>/dev/null && pwd -P) || {
    say "cannot resolve marker dir $marker_dir"
    roll_back_staged
    exit 2
  }
  for id in "$@"; do
    mfile="$marker_dir/$id"
    # A symlink at the marker path is never a legitimate marker (the writer emits
    # a regular file); refuse it rather than write through it (REQ-F1.1).
    if [ -L "$mfile" ]; then
      say "refusing symlink at marker path $mfile (REQ-F1.1)"
      roll_back_staged
      exit 2
    fi
    # Likewise refuse any other non-regular file already at the path (e.g. a
    # directory): `mv -f` onto a directory moves the temp *inside* it and reports
    # success, leaving no marker. Only a regular file (re-dispatch) is overwritten.
    if [ -e "$mfile" ] && [ ! -f "$mfile" ]; then
      say "refusing non-regular file at marker path $mfile (REQ-F1.1)"
      roll_back_staged
      exit 2
    fi
    # Containment: the marker must sit directly under its base dir after
    # canonicalization (defense in depth — the grammar already excludes slashes).
    file_dir=$(cd "$(dirname "$mfile")" 2>/dev/null && pwd -P) || file_dir=""
    if [ -z "$file_dir" ] || [ "$file_dir" != "$base_real" ]; then
      say "refusing out-of-base marker path $mfile (REQ-F1.1)"
      roll_back_staged
      exit 2
    fi
    tmpf=$(mktemp "$marker_dir/.marker.XXXXXX") || {
      say "cannot create a temp marker in $marker_dir"
      roll_back_staged
      exit 2
    }
    printf '%s\n' "$now" >"$tmpf" || {
      rm -f "$tmpf"
      say "cannot write marker for task $id"
      roll_back_staged
      exit 2
    }
    printf '%s%s%s%s%s\n' "$n" "$tab" "$id" "$tab" "${tmpf##*/}" >>"$manifest" || {
      rm -f "$tmpf"
      say "cannot record staged marker for task $id"
      roll_back_staged
      exit 2
    }
  done
done <<EOF
$kept
EOF

# Phase 2 — place every staged temp via an atomic same-dir rename, so a
# concurrent reader never sees a torn marker. Read the manifest by redirection
# (not a pipe) so this loop runs in the current shell and a failure can exit.
while IFS="$tab" read -r n id tmp; do
  [ -n "$tmp" ] || continue
  marker_dir=$(dir_at "$n")
  if ! mv -f "$marker_dir/$tmp" "$marker_dir/$id"; then
    say "cannot place marker for task $id in $marker_dir"
    roll_back_staged
    exit 2
  fi
done <"$manifest"
rm -f "$manifest"

exit 0
