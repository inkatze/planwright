#!/bin/sh
# spec-status.sh — the derived status render: the derivation engine
# (orchestrate-state.sh) surfaced as the canonical human execution-status read
# surface (invariant-tasks Task 3; D-3, D-4, D-6, D-12; REQ-B1.1–REQ-B1.6,
# REQ-C1.8, REQ-C1.9).
#
# For a named spec bundle it prints per-task execution status and the bundle's
# effective status (Active/Done), derived on demand from git/PR evidence via
# the engine — never committed, never mirrored to a remote (D-6). The render's
# text is a human-facing view with no stability promise; machine consumers read
# the engine's tagged stream directly.
#
# Behavior, by the bundle's stored header (requirements.md, the authoritative
# Status home) and declared Format-version (read from tasks.md, the file whose
# shape the version keys):
#
#   Draft / Retired / Superseded   the stored state is rendered with no
#                                  execution claim (REQ-B1.6) — the derivation
#                                  is not computed.
#   Ready                          per-task states plus the DERIVED bundle
#                                  status: Done when every task in the Done
#                                  universe derives completed and no live
#                                  Awaiting-input bullet remains; Active when
#                                  any progress exists with work remaining;
#                                  Ready otherwise. The determination is the
#                                  sync writer's STATUS_AWK semantics
#                                  (tasks-pr-sync.sh, kickoff-lifecycle Task 6)
#                                  ported here and re-sourced: parked-ness
#                                  comes from v2 reference bullets (or v1
#                                  section membership), not committed placement
#                                  (D-6). A zero-task bundle reports it has no
#                                  tasks and never derives Done (REQ-B1.6).
#   Active / Done (v1-only)        stored v1 values are rendered as stored,
#                                  with the per-task table; no derived bundle
#                                  claim (REQ-B1.6 computes derived bundle
#                                  status only for stored-Ready bundles). On a
#                                  v2 bundle these values violate the
#                                  restricted vocabulary and fail closed.
#
# Reference-bullet authority (REQ-B1.4, D-3): on a v2 bundle a live bullet
# whose bolded lead is `**Task <id>**` under ## Awaiting input / ## Deferred /
# ## Out of scope parks its task — the task renders awaiting-input / deferred /
# out-of-scope regardless of git evidence. A bullet on a task whose evidence
# derives completed is flagged as a stale-bullet anomaly. Awaiting-input-parked
# tasks block derived Done; Deferred / Out-of-scope-parked tasks are excluded
# from the Done universe rather than blocking it (D-4). Bullet task ids are
# validated against the task-id grammar before any use; a violating id is
# rejected with a sanitized warning (REQ-C1.9).
#
# Failure modes (REQ-B1.5, REQ-C1.8 — fail closed, distinct exits):
#   exit 0   rendered (including the stored-state-only and no-tasks reports)
#   exit 2   fail-closed input error: usage, missing/unreadable spec files, a
#            missing or unparseable Format-version: line (never falling open
#            to a version's rules), an unrecognized stored status, or an
#            engine failure
#   exit 3   transient evidence failure: the remote is configured but the gh
#            query failed (the engine's `degraded` record — its documented
#            failure signal). Partial evidence is NOT presented as status; the
#            locally-determinable facts (the stored header, reference-bullet
#            parked state) are reported, marked as the only facts available.
#            No remote configured is NOT this mode: it is the first-class
#            evidence-fallback path and renders fully with exit 0 (REQ-B1.2).
#
# Echo discipline (REQ-C1.9): every echoed value that originates in spec files
# or the evidence stream — header values, bullet text, engine-stream fields,
# remote-derived text — is routed through sanitize_printable before it reaches
# the terminal.
#
# Usage: spec-status.sh <spec-dir>
#
# Portable POSIX sh + awk; bash 3.2 / BSD tooling. No eval; all parsed content
# is treated as data. Pathname expansion is disabled (set -f): parsed spec text
# must never be filename-expanded against the run directory.
set -uf

# Pin the C locale: bracket-range validations are collation-dependent and would
# otherwise admit non-ASCII under a UTF-8 locale.
LC_ALL=C
export LC_ALL
unset CDPATH

TAB=$(printf '\t')

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

spec_dir="${1:-}"
if [ -z "$spec_dir" ]; then
  echo "usage: spec-status.sh <spec-dir>" >&2
  exit 2
fi
if [ ! -d "$spec_dir" ]; then
  echo "spec-status: no such spec dir: $spec_dir" >&2
  exit 2
fi
tasks_md="$spec_dir/tasks.md"
req_md="$spec_dir/requirements.md"
for f in "$tasks_md" "$req_md"; do
  if [ ! -f "$f" ] || [ ! -r "$f" ]; then
    echo "spec-status: missing or unreadable $f" >&2
    exit 2
  fi
done

# The spec id is the bundle directory name; validate it against the anchored
# identifier grammar before it is echoed or reaches the engine (REQ-C1.9).
spec_id=$(basename "$spec_dir")
case "$spec_id" in
  '' | *[!a-z0-9-]* | [!a-z0-9]*)
    echo "spec-status: invalid spec id '$(sanitize_printable "$spec_id")'" >&2
    exit 2
    ;;
esac

# --- Format-version (REQ-C1.8): missing or unparseable fails closed. -------
# The first header-block line wins; the value must be a known version. No
# fallback to either version's rules on a bad value.
# Trailing trim matters: a Markdown hard-break (two trailing spaces) or a CRLF
# checkout would otherwise make a valid value unrecognizable — and the
# sanitized diagnostic would misleadingly show the bare value as refused.
fv=$(awk '/^\*\*Format-version:\*\*/ { sub(/^\*\*Format-version:\*\*[ \t]*/, ""); sub(/[ \t\r]+$/, ""); print; exit }' "$tasks_md")
case "$fv" in
  1 | 2) ;;
  '')
    echo "spec-status: $tasks_md has no Format-version: line; refusing to guess the format (fail closed)" >&2
    exit 2
    ;;
  *)
    echo "spec-status: unparseable Format-version: '$(sanitize_printable "$fv")' in $tasks_md (fail closed)" >&2
    exit 2
    ;;
esac

# --- Stored status (requirements.md, the authoritative home). --------------
stored=$(awk '/^\*\*Status:\*\*/ { sub(/^\*\*Status:\*\*[ \t]*/, ""); sub(/[ \t\r]+$/, ""); print; exit }' "$req_md")
case "$stored" in
  Draft | Ready | Active | Done | Retired | Superseded) ;;
  '')
    echo "spec-status: $req_md has no Status: header" >&2
    exit 2
    ;;
  *)
    echo "spec-status: unrecognized stored status '$(sanitize_printable "$stored")' in $req_md" >&2
    exit 2
    ;;
esac
# v2 restricts the stored vocabulary to the human-gated states (REQ-A1.3);
# a stored Active/Done on a v2 bundle is malformed input, not a render mode.
if [ "$fv" = 2 ]; then
  case "$stored" in
    Active | Done)
      echo "spec-status: stored status '$stored' is not a v2 stored state (Active/Done are derived; REQ-A1.3)" >&2
      exit 2
      ;;
  esac
fi

printf 'spec: %s\n' "$spec_id"
printf 'format-version: %s\n' "$fv"

# --- Stored-status gating (REQ-B1.6). ---------------------------------------
# Draft / Retired / Superseded render their stored state with no execution
# claim; the derivation is not computed for them.
case "$stored" in
  Draft | Retired | Superseded)
    printf 'stored status: %s (no execution claim; the stored state is the whole report)\n' "$stored"
    exit 0
    ;;
esac
printf 'stored status: %s\n' "$stored"

# --- Task inventory. ---------------------------------------------------------
# Count the task blocks the derivation would read. A zero-task bundle has
# nothing to derive: report it and never derive Done (REQ-B1.6).
task_count=$(awk '/^### Task [0-9]/ && $3 ~ /^[0-9]+(\.[0-9]+)?$/ { n++ } END { print n + 0 }' "$tasks_md")
if [ "$task_count" -eq 0 ]; then
  echo 'no tasks: the bundle defines no task blocks'
  printf 'bundle status: %s (stored; no tasks — never derives Done)\n' "$stored"
  exit 0
fi

# --- Parked-state map (REQ-B1.4, D-3). ---------------------------------------
# v2: reference bullets under the three human-payload sections, bolded lead
# exactly `**Task <id>**`; the id is grammar-validated before use, a violating
# id is rejected (surfaced, never used), and the first bullet per task wins
# (cross-section exclusivity is the validator's error to raise). v1: a task
# BLOCK sitting in a human-payload section is classified by that section,
# matching the sync writer's STATUS_AWK. The map lines are
#   <id><TAB><class><TAB><payload>        class: awaiting-input|deferred|out-of-scope
#   rejected<TAB><raw>                    a bullet lead whose id fails the grammar
parked_map=$(awk -v fv="$fv" '
  function classof(sec) {
    if (sec == "Awaiting input") return "awaiting-input"
    if (sec == "Deferred") return "deferred"
    if (sec == "Out of scope") return "out-of-scope"
    return ""
  }
  /^## / { sec = substr($0, 4); next }
  fv == 2 && /^- \*\*Task / && classof(sec) != "" {
    line = $0
    sub(/^- \*\*Task /, "", line)
    i = index(line, "**")
    if (i == 0) next # no closing bold: not a reference bullet
    id = substr(line, 1, i - 1)
    payload = substr(line, i + 2)
    sub(/^[ \t]+/, "", payload)
    if (id !~ /^[0-9]+(\.[0-9]+)?$/) {
      # tabs would corrupt the record split; fold before emitting
      gsub(/\t/, " ", id)
      print "rejected\t" id
      next
    }
    if (id in seen) next
    seen[id] = 1
    gsub(/\t/, " ", payload)
    print id "\t" classof(sec) "\t" payload
    next
  }
  fv == 1 && /^### Task [0-9]/ && $3 ~ /^[0-9]+(\.[0-9]+)?$/ && classof(sec) != "" {
    if ($3 in seen) next
    seen[$3] = 1
    print $3 "\t" classof(sec) "\t"
  }
' "$tasks_md") || {
  # Fail closed: an unreadable parked map would silently drop an
  # Awaiting-input park and let the bundle derive Done (REQ-B1.6's inverse).
  echo "spec-status: could not derive the parked-state map from $tasks_md" >&2
  exit 2
}

parked_class_of() {
  printf '%s\n' "$parked_map" | awk -F"$TAB" -v i="$1" '$1 == i { print $2; exit }'
}
parked_payload_of() {
  printf '%s\n' "$parked_map" | awk -F"$TAB" -v i="$1" '$1 == i { print $3; exit }'
}

# Surface rejected bullet ids before any derivation output (REQ-C1.9).
printf '%s\n' "$parked_map" | while IFS="$TAB" read -r tag raw _; do
  [ "$tag" = rejected ] || continue
  printf 'warning: reference bullet rejected — task id %s violates the task-id grammar\n' \
    "'$(sanitize_printable "$raw")'"
done

# --- Run the derivation engine (D-6: one derivation, one place). -------------
engine_err=$(mktemp "${TMPDIR:-/tmp}/spec-status-err.XXXXXX") || exit 2
trap 'rm -f "$engine_err"' EXIT
engine_out=$("$script_dir/orchestrate-state.sh" "$spec_dir" 2>"$engine_err")
engine_rc=$?
if [ "$engine_rc" -ne 0 ]; then
  err=$(cat "$engine_err" 2>/dev/null)
  rm -f "$engine_err"
  echo "spec-status: derivation engine failed: $(sanitize_printable "$err" '(no diagnostic)')" >&2
  exit 2
fi
rm -f "$engine_err"

# --- Transient evidence failure (REQ-B1.5): fail closed, local facts only. ---
# The engine's `degraded` record is its documented transient-failure signal (a
# configured remote whose gh query failed). Evidence-derived states are NOT
# rendered; the locally-determinable facts — the stored header and the parked
# map, neither of which needs the remote — are reported as the only facts
# available. No remote configured never reaches here (the engine skips the
# probe silently in that first-class mode).
# Detect the record by its tag (the engine's documented consumption model:
# "consumers switch on column 1"), never by the message text — an empty
# message field must not fall open into a full render.
degraded=0
if printf '%s\n' "$engine_out" | awk -F"$TAB" '$1 == "degraded" { found = 1 } END { exit !found }'; then
  degraded=1
fi
if [ "$degraded" -eq 1 ]; then
  degraded_msg=$(printf '%s\n' "$engine_out" \
    | awk -F"$TAB" '$1 == "degraded" { print $3; exit }')
  printf 'spec-status: transient evidence failure — %s\n' \
    "$(sanitize_printable "$degraded_msg" '(no diagnostic from the engine)')"
  echo 'evidence-derived status is unavailable; the facts below are locally determinable and are the only facts available:'
  printf '%s\n' "$parked_map" | while IFS="$TAB" read -r id class payload; do
    case "$id" in
      '' | rejected) continue ;;
    esac
    printf 'parked: task %s %s — %s\n' "$id" "$class" \
      "$(sanitize_printable "$payload" '(no payload)')"
  done
  exit 3
fi

# --- Per-task render. ---------------------------------------------------------
# Engine task records, in file order, with reference-bullet authority applied
# (REQ-B1.4): a parked task renders its parked class regardless of evidence; a
# parked task whose evidence derives completed is flagged as a stale-bullet
# anomaly. The engine's completion records dress completed tasks with the PR
# number and merge date (REQ-B1.1). Classification tallies feed the bundle
# determination below (the STATUS_AWK port): awaiting-input-parked counts as
# pending, deferred/out-of-scope-parked leaves the Done universe, everything
# else counts by its derived state (D-4).
completion_for() {
  printf '%s\n' "$engine_out" \
    | awk -F"$TAB" -v i="$1" '$1 == "completion" && $2 == i { print $3 "\t" $4; exit }'
}

fwd=0
inp=0
comp=0
await=0
anomalies=""
tasks_seen=0
while IFS="$TAB" read -r tag id state ev; do
  [ "$tag" = task ] || continue
  tasks_seen=$((tasks_seen + 1))
  class=$(parked_class_of "$id")
  if [ -n "$class" ]; then
    case "$class" in
      awaiting-input) await=$((await + 1)) ;;
      *) : ;; # deferred / out-of-scope: excluded from the Done universe
    esac
    payload=$(parked_payload_of "$id")
    if [ -n "$payload" ]; then
      printf 'task %s %s (bullet: %s)\n' "$id" "$class" "$(sanitize_printable "$payload")"
    else
      printf 'task %s %s (parked)\n' "$id" "$class"
    fi
    if [ "$state" = completed ]; then
      anomalies="${anomalies}anomaly: task $id is parked by a live $class bullet but its evidence derives completed (stale bullet)
"
    fi
    continue
  fi
  case "$state" in
    completed) comp=$((comp + 1)) ;;
    in-progress) inp=$((inp + 1)) ;;
    *) fwd=$((fwd + 1)) ;;
  esac
  detail=$(sanitize_printable "$state")
  cinfo=$(completion_for "$id")
  if [ -n "$cinfo" ]; then
    c_pr=${cinfo%%"$TAB"*}
    c_date=${cinfo#*"$TAB"}
    if [ -n "$c_pr" ] && [ -n "$c_date" ]; then
      detail="$detail · PR #$(sanitize_printable "$c_pr") merged $(sanitize_printable "$c_date")"
    elif [ -n "$c_date" ]; then
      detail="$detail · merged $(sanitize_printable "$c_date")"
    fi
  fi
  printf 'task %s %s (%s)\n' "$id" "$detail" "$(sanitize_printable "$ev")"
done <<EOF
$engine_out
EOF

[ -n "$anomalies" ] && printf '%s' "$anomalies"

# A reference bullet naming no existing task parks nothing (the validator
# raises the error, REQ-C1.5); surface it so the bullet is not silently inert.
printf '%s\n' "$parked_map" | while IFS="$TAB" read -r id class _; do
  case "$id" in
    '' | rejected) continue ;;
  esac
  if ! printf '%s\n' "$engine_out" \
    | awk -F"$TAB" -v i="$id" '$1 == "task" && $2 == i { found = 1 } END { exit !found }'; then
    printf 'warning: a %s reference bullet names task %s, which does not exist\n' \
      "$class" "$id"
  fi
done

# Non-task engine records are surfaced as notes, every field treated as data
# (REQ-C1.9: a hostile trailer value or a malformed Dependencies line rides
# this stream).
printf '%s\n' "$engine_out" | while IFS="$TAB" read -r tag id msg _; do
  case "$tag" in
    contradiction)
      printf 'note: task %s — %s\n' "$(sanitize_printable "$id")" "$(sanitize_printable "$msg")"
      ;;
    refused)
      printf 'note: refused %s value %s\n' "$(sanitize_printable "$id")" \
        "'$(sanitize_printable "$msg" '(unprintable)')'"
      ;;
    malformed-deps)
      printf 'note: task %s has a malformed Dependencies line: %s\n' \
        "$(sanitize_printable "$id")" "'$(sanitize_printable "$msg" '(unprintable)')'"
      ;;
  esac
done

# --- Bundle effective status. -------------------------------------------------
# Derived only for stored-Ready bundles (REQ-B1.6). The determination is the
# STATUS_AWK port (tasks-pr-sync.sh): Done when nothing is pending (no
# forward/in-progress work and no awaiting-input-parked task — a live
# Awaiting-input bullet blocks Done, D-4), Active when any progress exists,
# Ready otherwise. Stored v1 Active/Done render as stored: the reconcile owns
# those committed values, and a second derived claim here would be a second
# writer's opinion.
if [ "$stored" = Ready ]; then
  pending=0
  if [ "$fwd" -gt 0 ] || [ "$inp" -gt 0 ] || [ "$await" -gt 0 ]; then
    pending=1
  fi
  progress=0
  if [ "$inp" -gt 0 ] || [ "$comp" -gt 0 ]; then
    progress=1
  fi
  if [ "$pending" -eq 0 ] && [ "$tasks_seen" -gt 0 ]; then
    bundle=Done
  elif [ "$progress" -eq 1 ]; then
    bundle=Active
  else
    bundle=Ready
  fi
  printf 'bundle status: %s (derived)\n' "$bundle"
fi

exit 0
