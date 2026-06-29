#!/bin/sh
# orchestrate-select.sh — pick the next ready unit for /orchestrate,
# critical-path-first (Task 13, REQ-F1.2, D-7, D-8), and emit the critical path
# for the comprehension graph view (Task 7 of specs/spec-comprehension, D-6).
#
# A ready task is one in the `## Forward plan` section that the LIVE DERIVATION
# reports neither completed nor in-progress, and whose every dependency the
# derivation reports completed. Among ready tasks the selector prefers the head
# of the effort-weighted longest dependent chain — the unit that unblocks the
# most downstream remaining work — and breaks ties FIFO, by first appearance in
# tasks.md. This turns REQ-F1.2's critical-path-first rule into a deterministic,
# testable computation instead of a hand-asserted one (the 2026-06-10
# observation).
#
# Live truth, not the committed snapshot (orchestration-concurrency Task 5, D-3,
# REQ-B1.2). Completed / in-progress state is read from the derivation engine
# (scripts/orchestrate-state.sh — git + trailer + marker + gh evidence), NOT from
# tasks.md section placement, so a task that is already in-flight or completed
# (by evidence the committed snapshot has not yet been reconciled to) is never
# re-dispatched. The dependency GRAPH is still parsed from tasks.md here: the
# engine's dependency parser is stricter (it flags prose forms as malformed),
# whereas the selector keeps the prose-deps handling PR #78 added, so readiness
# is recomputed locally over the engine's completed-set. The Status annotation
# is advisory and is NOT consulted.
#
# Dependency-line parsing: the `**Dependencies:**` bullet is read in prose or
# bare-id form. The local dep ids are the numeric (or dotted) tokens BEFORE any
# parenthetical; a trailing period is tolerated ("Task 1." is dep 1), and a
# parenthetical qualifier together with any trailing cross-spec clause (which
# may itself name id-shaped tokens) is dropped, so only this bundle's deps are
# extracted. Only the first line of the bullet is read — a wrapped continuation
# line is not parsed (both limitations are pinned in the test suite).
#
# Usage:
#   orchestrate-select.sh <spec-dir>
#       prints the selected ready task id on stdout (the default; for
#       /orchestrate dispatch).
#   orchestrate-select.sh --critical-path <spec-dir>
#       prints the effort-weighted longest-dependent chain — the structural
#       critical path — as ordered task ids, one per line. This is the single
#       source of truth the comprehension dependency-graph view reuses rather
#       than recomputing (D-6): it shares the same weight()/crit() longest-chain
#       logic the selector uses. Unlike selection, the chain spans the FULL task
#       DAG (every section): the terminal-task exclusion is a remaining-work
#       filter specific to dispatch, deliberately not applied to the structural
#       visualization. On a bundle with nothing completed the two coincide.
#
# Exit: 0 a unit/path was produced (on stdout); 1 (selection only) no ready
# unit this step; 2 the tasks.md is missing, unreadable, or holds no task
# records, or (selection only) the derivation engine is missing / not executable
# or its derivation fails (no git work tree, invalid spec id) — fail closed: a
# malformed file or unavailable live truth must not silently report "nothing".
#
# Portable POSIX sh + awk (bash 3.2 / BSD awk compatible): no gawk-only
# constructs (3-arg match, gensub), no eval, input treated as data. The
# --critical-path mode stays git-free (purely structural); selection mode is
# NOT git-free — it reads git-derived evidence by shelling out to the derivation
# engine (orchestrate-state.sh), which needs a git work tree and git on PATH.
set -u

# Pin the C locale: range patterns in the awk grammar are collation-dependent
# under UTF-8 locales.
LC_ALL=C
export LC_ALL
unset CDPATH

TAB=$(printf '\t')

# Resolve this script's directory so the sibling derivation engine
# (orchestrate-state.sh) is found regardless of the caller's working directory.
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# Mode: the optional leading --critical-path flag selects the path-emitting mode
# (D-6); without it the script is the unchanged ready-unit selector.
mode=select
case "${1:-}" in
  --critical-path)
    mode=path
    shift
    ;;
esac

spec_dir="${1:-}"
if [ -z "$spec_dir" ]; then
  echo "usage: orchestrate-select.sh [--critical-path] <spec-dir>" >&2
  exit 2
fi
tasks_md="$spec_dir/tasks.md"
if [ ! -f "$tasks_md" ] || [ ! -r "$tasks_md" ]; then
  echo "orchestrate-select: missing or unreadable $tasks_md" >&2
  exit 2
fi

# Live-truth state (Task 5, D-3, REQ-B1.2). In selection mode the completed /
# in-progress sets come from the derivation engine, never from tasks.md section
# placement. --critical-path stays purely structural (full DAG,
# completion-independent, git-free) and never consults the derivation, so these
# sets remain empty there. The sets are space-padded id lists (" 1 6 ") for an
# unambiguous whole-token membership test in the awk below.
completed=" "
inprogress=" "
if [ "$mode" = select ]; then
  state_engine="$script_dir/orchestrate-state.sh"
  if [ ! -x "$state_engine" ]; then
    echo "orchestrate-select: derivation engine $state_engine missing or not executable" >&2
    exit 2
  fi
  # Fail closed when the derivation cannot run (no git work tree, missing or
  # taskless tasks.md, invalid spec id): selecting against absent truth would
  # risk the double-dispatch this rewire exists to prevent (REQ-B1.2). The
  # engine's no-remote / degraded-gh paths still exit 0, so only a hard failure
  # reaches here. Capture stderr into the same stream (2>&1) so the engine's
  # specific reason is surfaced on a fail-closed exit; the record parser below
  # keys on a `task` first column, so any diagnostic line is harmlessly ignored
  # on the success path.
  if ! state_out=$("$state_engine" "$spec_dir" 2>&1); then
    echo "orchestrate-select: derivation failed for $spec_dir (cannot select against live truth):" >&2
    printf '%s\n' "$state_out" >&2
    exit 2
  fi
  # Read only the evidence-based states (completed / in-progress); ready and
  # blocked are recomputed below from the locally-parsed dependency graph. Other
  # tagged records (contradiction / degraded / refused / malformed-deps) and any
  # engine diagnostic line are ignored here — they are the reconcile's and the
  # guards' concern.
  completed=" $(printf '%s\n' "$state_out" \
    | awk -F"$TAB" '$1=="task" && $3=="completed"{print $2}' | tr '\n' ' ')"
  inprogress=" $(printf '%s\n' "$state_out" \
    | awk -F"$TAB" '$1=="task" && $3=="in-progress"{print $2}' | tr '\n' ' ')"
  # Surface the evidence-quality diagnostics on the success path so an operator
  # running selection by hand sees the pick stood on degraded or conflicting
  # evidence: `degraded` (a configured gh query failed, so the completed set is
  # git-only) and `contradiction` (git attests completion but the PR is still
  # open). stdout stays clean — only the selected id is emitted there. Acting on
  # these stays the reconcile's (T4) and the guards' (T7) concern; the selector
  # only makes them visible. The noisier `refused` / `malformed-deps` records are
  # deliberately left to those owners and not forwarded here.
  printf '%s\n' "$state_out" \
    | awk -F"$TAB" '$1=="degraded" || $1=="contradiction"' >&2
fi

awk -v mode="$mode" -v completed="$completed" -v inprogress="$inprogress" '
  function weight(s) {
    # Effort string -> a numeric weight. "half day" is 0.5; otherwise the
    # leading number ("1", "1.5", "2", "3"); an unrecognized form is 1.
    if (s ~ /half/) return 0.5
    if (match(s, /[0-9]+(\.[0-9]+)?/)) return substr(s, RSTART, RLENGTH) + 0
    return 1
  }
  # crit(t): effort(t) + the longest dependent chain below t, memoized.
  # Only non-terminal dependents extend a chain (remaining work), so a
  # Completed/Out-of-scope task never lengthens the critical path.
  function crit(t,   best, n, i, arr, c) {
    if (t in memo) return memo[t]
    memo[t] = weight(effort[t])            # cycle guard (DAG expected)
    best = 0
    n = split(deps_of[t], arr, " ")
    for (i = 1; i <= n; i++) {
      if (arr[i] == "") continue
      c = crit(arr[i])
      if (c > best) best = c
    }
    memo[t] = weight(effort[t]) + best
    return memo[t]
  }
  # Section headings: track the current ## section. The H2 text is the
  # canonical state label for every task block that follows.
  /^## / { section = substr($0, 4); sub(/[[:space:]]+$/, "", section); next }
  # Task headings: "### Task <id> — ...". id is the third field; validate it
  # against the task-id grammar before recording the record.
  /^### Task / {
    id = $3
    if (id ~ /^[0-9]+(\.[0-9]+)?$/) {
      cur = id
      ntasks++
      sec[id] = section
      order[id] = NR
      effort[id] = ""
      raw_deps[id] = ""
    } else {
      cur = ""
    }
    next
  }
  # Definition bullets within the current task block.
  cur != "" && /\*\*Dependencies:\*\*/ {
    s = $0
    sub(/.*\*\*Dependencies:\*\*/, "", s)
    sub(/\(.*/, "", s)    # drop parenthetical qualifiers (and any cross-spec
                          # clause they introduce) before id extraction
    gsub(/[^0-9.]+/, " ", s)               # keep only id-shaped tokens
    raw_deps[cur] = s
    next
  }
  cur != "" && /\*\*Estimated effort:\*\*/ {
    e = $0
    sub(/.*\*\*Estimated effort:\*\*[[:space:]]*/, "", e)
    effort[cur] = e
    next
  }
  END {
    if (ntasks == 0) {
      # Fail closed with a diagnostic, matching the shell-level missing-file
      # message above (a present-but-taskless tasks.md is still malformed).
      print "orchestrate-select: no task records in " FILENAME > "/dev/stderr"
      exit 2
    }

    # Normalize dependency lists (drop bare "." or empty tokens, keep ids).
    for (t in sec) {
      m = split(raw_deps[t], a, " ")
      list = ""
      for (i = 1; i <= m; i++) {
        tok = a[i]
        sub(/\.$/, "", tok)    # tolerate prose trailing period: "Task 1." -> 1
        if (tok ~ /^[0-9]+(\.[0-9]+)?$/) list = list tok " "
      }
      deps[t] = list
    }

    # Reverse edges: a task t extends the chain of each dep it declares. In
    # selection mode only non-terminal tasks count (Completed / Out of scope are
    # not future work, so a done task never lengthens the remaining critical
    # path). In path mode every task counts: the structural critical path is a
    # property of the whole DAG, independent of how much is already done.
    for (t in sec) {
      if (mode != "path") {
        # A task the derivation reports completed (live truth) carries no
        # remaining work, so it never lengthens the remaining critical path.
        # Out of scope is a parked terminal section — a human decision that is
        # not git-derivable, so it stays section-based.
        terminal = (index(completed, " " t " ") > 0 || sec[t] == "Out of scope")
        if (terminal) continue
      }
      m = split(deps[t], a, " ")
      for (i = 1; i <= m; i++)
        if (a[i] != "") deps_of[a[i]] = deps_of[a[i]] t " "
    }

    # Path mode: emit the effort-weighted longest-dependent chain (D-6). The
    # head is the task with the greatest crit() (FIFO ties); from there follow
    # the highest-crit dependent at each step, which is the continuation of the
    # longest chain. A visited guard keeps a malformed cyclic graph from looping.
    if (mode == "path") {
      head = ""; hw = -1; ho = 0
      for (t in sec) {
        w = crit(t)
        if (w > hw || (w == hw && order[t] < ho)) { hw = w; head = t; ho = order[t] }
      }
      cur = head
      print cur
      visited[cur] = 1
      while (1) {
        n = split(deps_of[cur], arr, " ")
        nb = ""; nw = -1; nord = 0
        for (i = 1; i <= n; i++) {
          if (arr[i] == "") continue
          w = crit(arr[i])
          if (w > nw || (w == nw && order[arr[i]] < nord)) { nw = w; nb = arr[i]; nord = order[arr[i]] }
        }
        if (nb == "" || (nb in visited)) break
        print nb
        visited[nb] = 1
        cur = nb
      }
      exit 0
    }

    # Ready set + critical-path selection.
    best_id = ""
    best_w = -1
    best_order = 0
    for (t in sec) {
      # Only un-parked candidates: a task parked in Awaiting input / Deferred /
      # Out of scope (a human decision, not git-derivable) is never auto-picked.
      # Because dispatch no longer moves sections (Task 3, branch-as-record), an
      # in-flight task still sits in Forward plan here; live truth excludes it.
      if (sec[t] != "Forward plan") continue
      # Already done or already in flight by live truth — never re-dispatch, even
      # when the committed snapshot has not yet caught up (D-3, REQ-B1.2).
      if (index(completed, " " t " ") > 0) continue
      if (index(inprogress, " " t " ") > 0) continue
      ready = 1
      m = split(deps[t], a, " ")
      for (i = 1; i <= m; i++) {
        if (a[i] == "") continue
        # A dependency counts as satisfied only when the derivation reports it
        # completed — so a dep done by snapshot-stale evidence still unblocks.
        if (index(completed, " " a[i] " ") == 0) { ready = 0; break }
      }
      if (!ready) continue
      w = crit(t)
      if (w > best_w || (w == best_w && order[t] < best_order)) {
        best_w = w
        best_id = t
        best_order = order[t]
      }
    }
    if (best_id == "") exit 1
    print best_id
  }
' "$tasks_md"
