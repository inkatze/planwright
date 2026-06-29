#!/bin/sh
# orchestrate-select.sh — pick the next ready unit for /orchestrate,
# critical-path-first (Task 13, REQ-F1.2, D-7, D-8), and emit the critical path
# for the comprehension graph view (Task 7 of specs/spec-comprehension, D-6).
#
# A ready task is one in the `## Forward plan` section whose every dependency
# sits in `## Completed` (a task that is In progress, Awaiting input, or in a
# terminal/parked section is not a candidate). Among ready tasks the selector
# prefers the head of the effort-weighted longest dependent chain — the unit
# that unblocks the most downstream remaining work — and breaks ties FIFO, by
# first appearance in tasks.md. This turns REQ-F1.2's critical-path-first rule
# into a deterministic, testable computation instead of a hand-asserted one
# (the 2026-06-10 observation).
#
# Section membership is the canonical orchestration state (tasks.md doubles as
# the state record); the per-block Status annotation is advisory and is NOT
# consulted here, so the selector agrees with the content anchor's view.
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
# records (fail closed — a malformed file must not silently report "nothing").
#
# Portable POSIX sh + awk + git-free (bash 3.2 / BSD awk compatible): no
# gawk-only constructs (3-arg match, gensub), no eval, input treated as data.
set -u

# Pin the C locale: range patterns in the awk grammar are collation-dependent
# under UTF-8 locales.
LC_ALL=C
export LC_ALL
unset CDPATH

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

awk -v mode="$mode" '
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
        terminal = (sec[t] == "Completed" || sec[t] == "Out of scope")
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
      if (sec[t] != "Forward plan") continue
      ready = 1
      m = split(deps[t], a, " ")
      for (i = 1; i <= m; i++) {
        if (a[i] == "") continue
        if (sec[a[i]] != "Completed") { ready = 0; break }
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
