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
# Path contract: the writer MUST resolve the SAME marker path the reader does,
# so a marker dropped here is the marker the derivation engine reads. Both use
#   ${PLANWRIGHT_ORCH_STATE_DIR:-<spec-dir>/.orchestrate/markers}/<id>
# (the env override is a trusted operator/test knob, exactly as in the reader).
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
#   write   drop a fresh timestamped marker per id (mkdir -p the base dir).
#   clear   remove the marker per id (idempotent: a missing marker is fine; a
#           real removal failure is surfaced fail-closed, not swallowed).
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

# Runtime-marker base dir — the SAME resolution the reader uses. The env
# override is a trusted operator/test knob; the per-id hardening (symlink
# refusal + containment) is at the path, not here.
marker_dir="${PLANWRIGHT_ORCH_STATE_DIR:-$spec_dir/.orchestrate/markers}"

if [ "$cmd" = clear ]; then
  # Idempotent removal. rm -f on a missing path is a no-op (exit 0); on a symlink
  # it removes the link itself, never follows it. A real removal failure (e.g. an
  # unwritable marker dir) is surfaced fail-closed (exit 2) rather than swallowed,
  # so a clean exit always means the marker is gone — matching the script's
  # fail-closed contract everywhere else. Every id is attempted before exiting, so
  # one stuck marker never strands the rest of a bundle's cleanup.
  rc=0
  for id in "$@"; do
    if ! rm -f "$marker_dir/$id" 2>/dev/null; then
      echo "orchestrate-marker: cannot remove marker for task $id" >&2
      rc=2
    fi
  done
  exit "$rc"
fi

# write: create the base dir only now that every id has passed validation, so a
# refused write leaves no marker state behind.
if ! mkdir -p "$marker_dir" 2>/dev/null; then
  echo "orchestrate-marker: cannot create marker dir $marker_dir" >&2
  exit 2
fi
base_real=$(cd "$marker_dir" 2>/dev/null && pwd -P) || {
  echo "orchestrate-marker: cannot resolve marker dir $marker_dir" >&2
  exit 2
}

now=$(date +%s)
case "$now" in
  '' | *[!0-9]*)
    echo "orchestrate-marker: could not read a numeric timestamp" >&2
    exit 2
    ;;
esac

# Two-phase write so a multi-id (bundle) dispatch is all-or-nothing through the
# fragile part: phase 1 validates each marker path and stages a complete temp
# marker per id (nothing placed yet); phase 2 renames the staged temps into
# place. Any failure while staging rolls back every staged temp and exits 2 with
# no marker placed. Same-dir renames after staging do not fail under normal
# conditions; POSIX has no multi-file atomic rename, so the residual (a rename
# failing after a sibling already landed) is documented, not eliminated — and we
# never delete an already-placed (possibly pre-existing) marker to "undo" a
# partial batch, which would revert a legitimately in-progress task.
tab=$(printf '\t')
manifest=$(mktemp "$marker_dir/.manifest.XXXXXX") || {
  echo "orchestrate-marker: cannot create a staging manifest in $marker_dir" >&2
  exit 2
}
# Remove every still-staged temp recorded in the manifest, then the manifest
# itself. A temp already renamed into place no longer exists at its staged path,
# so its rm is a harmless no-op — rollback never touches a placed marker.
roll_back_staged() {
  while IFS="$tab" read -r _rb_id _rb_tmp; do
    [ -n "$_rb_tmp" ] && rm -f "$marker_dir/$_rb_tmp"
  done <"$manifest"
  rm -f "$manifest"
}

# Phase 1 — validate every marker path and stage a temp marker per id. The temp
# lives in the marker dir, so the phase-2 rename is same-filesystem.
for id in "$@"; do
  mfile="$marker_dir/$id"
  # A symlink at the marker path is never a legitimate marker (the writer emits
  # a regular file); refuse it rather than write through it (REQ-F1.1).
  if [ -L "$mfile" ]; then
    echo "orchestrate-marker: refusing symlink at marker path $mfile (REQ-F1.1)" >&2
    roll_back_staged
    exit 2
  fi
  # Likewise refuse any other non-regular file already at the path (e.g. a
  # directory): `mv -f` onto a directory moves the temp *inside* it and reports
  # success, leaving no marker. Only a regular file (re-dispatch) is overwritten.
  if [ -e "$mfile" ] && [ ! -f "$mfile" ]; then
    echo "orchestrate-marker: refusing non-regular file at marker path $mfile (REQ-F1.1)" >&2
    roll_back_staged
    exit 2
  fi
  # Containment: the marker must sit directly under its base dir after
  # canonicalization (defense in depth — the grammar already excludes slashes).
  file_dir=$(cd "$(dirname "$mfile")" 2>/dev/null && pwd -P) || file_dir=""
  if [ -z "$file_dir" ] || [ "$file_dir" != "$base_real" ]; then
    echo "orchestrate-marker: refusing out-of-base marker path $mfile (REQ-F1.1)" >&2
    roll_back_staged
    exit 2
  fi
  tmpf=$(mktemp "$marker_dir/.marker.XXXXXX") || {
    echo "orchestrate-marker: cannot create a temp marker in $marker_dir" >&2
    roll_back_staged
    exit 2
  }
  printf '%s\n' "$now" >"$tmpf" || {
    rm -f "$tmpf"
    echo "orchestrate-marker: cannot write marker for task $id" >&2
    roll_back_staged
    exit 2
  }
  printf '%s%s%s\n' "$id" "$tab" "${tmpf##*/}" >>"$manifest" || {
    rm -f "$tmpf"
    echo "orchestrate-marker: cannot record staged marker for task $id" >&2
    roll_back_staged
    exit 2
  }
done

# Phase 2 — place every staged temp via an atomic same-dir rename, so a
# concurrent reader never sees a torn marker. Read the manifest by redirection
# (not a pipe) so this loop runs in the current shell and a failure can exit.
while IFS="$tab" read -r id tmp; do
  [ -n "$tmp" ] || continue
  if ! mv -f "$marker_dir/$tmp" "$marker_dir/$id"; then
    echo "orchestrate-marker: cannot place marker for task $id" >&2
    roll_back_staged
    exit 2
  fi
done <"$manifest"
rm -f "$manifest"

exit 0
