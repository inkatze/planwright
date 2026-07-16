#!/bin/sh
# orchestrate-select.sh — pick the next ready unit for /orchestrate,
# critical-path-first (Task 13, REQ-F1.2, D-7, D-8), and emit the critical path
# for the comprehension graph view (Task 7 of specs/spec-comprehension, D-6).
#
# A ready task is one the LIVE DERIVATION reports neither completed nor
# in-progress, whose every dependency the derivation reports completed, and that
# is a candidate under the bundle's declared format version (invariant-tasks
# Task 5, D-8, REQ-C1.2): on a v1 bundle a candidate sits in `## Forward plan`;
# on a v2 bundle (no placement sections) a candidate is any task NOT parked by a
# live reference bullet (`- **Task <id>**` under ## Awaiting input / ## Deferred
# / ## Out of scope — bullet task ids are grammar-validated before use,
# REQ-C1.9). Among ready tasks the selector prefers the head of the
# effort-weighted longest dependent chain — the unit that unblocks the
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
# unit this step; 2 the tasks.md is missing, unreadable, NUL-laden, holds no
# task records, or has a missing/unparseable `Format-version:` line (REQ-C1.8 — the
# candidacy rules cannot be known without a parsed version; both modes refuse
# rather than guess), or the sourced echo-safety.sh helper is missing (broken
# install, both modes), or (selection only) the derivation engine is missing /
# not executable or its derivation fails (no git work tree, invalid spec id) —
# fail closed: a malformed file or unavailable live truth must not silently
# report "nothing"; 3 (selection only, v2) transient evidence failure — the
# remote is configured but the evidence fetch failed (the engine's `degraded`
# record), so nothing is dispatched rather than selecting against partial
# evidence (REQ-B1.5). v1 selection keeps its documented degraded-but-proceed
# behavior (the record is forwarded to stderr) — v1 behavior unchanged.
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

# echo-safety.sh is sourced (not executed): require it readable and fail closed
# when a broken install omits it. It sanitizes untrusted spec content (rejected
# bullet ids, engine diagnostics) before it reaches stderr (REQ-C1.9).
echo_safety="$script_dir/echo-safety.sh"
if [ ! -r "$echo_safety" ]; then
  printf '%s\n' "orchestrate-select: required helper $echo_safety missing or not readable" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$echo_safety"

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
  printf '%s\n' "usage: orchestrate-select.sh [--critical-path] <spec-dir>" >&2
  exit 2
fi
tasks_md="$spec_dir/tasks.md"
if [ ! -f "$tasks_md" ] || [ ! -r "$tasks_md" ]; then
  printf '%s\n' "orchestrate-select: missing or unreadable $tasks_md" >&2
  exit 2
fi

# NUL screen (mirrors drain-gates.sh): the snapshot read below strips NUL
# bytes, which would splice the flanking bytes into one line — corruption of
# the form `…\0- **Task 1**…` could silently un-park a task. Refuse the file
# instead of reinterpreting it.
if [ "$(wc -c <"$tasks_md")" -ne "$(tr -d '\000' <"$tasks_md" | wc -c)" ]; then
  printf '%s\n' "orchestrate-select: $tasks_md contains NUL bytes (fail closed)" >&2
  exit 2
fi

# Single-snapshot read: every parse below — the Format-version gate, the v2
# parked map, and the selection graph — reads ONE capture of tasks.md, so a
# concurrent rewrite cannot make the candidacy decision mix two file versions
# (a parked map from one, the graph from another) and a mid-run read failure
# fails closed instead of silently emptying a parse. The derivation engine
# still reads its own view of the file (the pre-existing sample-once
# tolerance); a divergence there is ordinary evidence lag, not a torn
# candidacy decision.
if ! tasks_content=$(cat "$tasks_md"); then
  printf '%s\n' "orchestrate-select: could not read $tasks_md (fail closed)" >&2
  exit 2
fi

# --- Format-version (REQ-C1.8): missing or unparseable fails closed. -------
# The candidacy rules are version-keyed (v1 section membership vs v2 bullet
# parking, D-8), so the version must parse before either rule is applied; no
# fallback to either version's rules on a bad value. --critical-path is
# structurally identical at both versions but refuses too rather than guessing.
# Trailing trim: a Markdown hard-break or CRLF checkout must not make a valid
# value unrecognizable. Column-0 fences are illustration: a fenced example
# header line must not shadow the real declaration into the wrong version's
# rules (the parse otherwise mirrors spec-status.sh, whose fence-awareness
# alignment is tracked as an observation).
fv=$(printf '%s\n' "$tasks_content" | awk '
  /^```/ { fence = !fence; next }
  fence { next }
  /^\*\*Format-version:\*\*/ { sub(/^\*\*Format-version:\*\*[ \t]*/, ""); sub(/[ \t\r]+$/, ""); print; exit }
')
case "$fv" in
  1 | 2) ;;
  '')
    printf '%s\n' "orchestrate-select: $tasks_md has no Format-version: line; refusing to guess the format (fail closed)" >&2
    exit 2
    ;;
  *)
    printf '%s\n' "orchestrate-select: unparseable Format-version: '$(sanitize_printable "$fv")' in $tasks_md (fail closed)" >&2
    exit 2
    ;;
esac

# Live-truth state (orchestration-concurrency Task 5, D-3, REQ-B1.2; the
# invariant-tasks Task 5 above is the format-version keying). In selection
# mode the completed /
# in-progress sets come from the derivation engine, never from tasks.md section
# placement. --critical-path stays purely structural (full DAG,
# completion-independent, git-free) and never consults the derivation, so these
# sets remain empty there. The sets are space-padded id lists (" 1 6 ") for an
# unambiguous whole-token membership test in the awk below.
completed=" "
inprogress=" "

# v2 parked map (select mode only; D-3, D-8, REQ-C1.2): a live reference bullet
# whose bolded lead is `**Task <id>**` under a human-payload section parks its
# task — never auto-picked (parked-ness is a human decision with no git-evidence
# proxy). Out-of-scope-parked tasks are additionally chain-terminal, mirroring
# the v1 `Out of scope` section semantics. Bullet task ids are validated against
# the task-id grammar before any use; a violating id is rejected with a
# sanitized stderr warning and never used (REQ-C1.9). A bullet naming a
# non-existent task parks nothing (the validator owns that error). The sets are
# space-padded id lists, same shape as completed/inprogress below.
#
# A sibling of the spec-status.sh (Task 3) parked-map parse and the
# drain-gates.sh copy, with the deliberate differences: column-0 fences are
# skipped (illustration, matching drain-gates; spec-status alignment is tracked
# as an observation); a lead with inner whitespace ("**Task force
# assembled.**") is a plain prose bullet the format allows in Deferred / Out of
# scope and is silently skipped, matching the validator's rule; no payload
# extraction (selection needs only ids and classes).
parked_any=" "
parked_oos=" "
if [ "$mode" = select ] && [ "$fv" = 2 ]; then
  parked_map=$(printf '%s\n' "$tasks_content" | awk '
    function classof(sec) {
      if (sec == "Awaiting input") return "awaiting-input"
      if (sec == "Deferred") return "deferred"
      if (sec == "Out of scope") return "out-of-scope"
      return ""
    }
    { sub(/\r$/, "") }
    /^```/ { fence = !fence; next }
    fence { next }
    /^## / { sec = substr($0, 4); sub(/[ \t]+$/, "", sec); next }
    /^- \*\*Task / && classof(sec) != "" {
      line = $0
      sub(/^- \*\*Task /, "", line)
      i = index(line, "**")
      if (i == 0) next # no closing bold: not a reference bullet
      id = substr(line, 1, i - 1)
      if (id ~ /[ \t]/) {
        # Inner whitespace is usually a plain prose bullet the format allows
        # in Deferred / Out of scope (validator parity) — but a NEAR-MISS
        # reference (whitespace-trimmed remainder is a valid id, or the lead
        # is only digits, dots, and whitespace: "1 ", "1 2") is a failed park
        # a human meant, rejected loudly below, never silently skipped.
        probe = id
        sub(/^[ \t]+/, "", probe)
        sub(/[ \t]+$/, "", probe)
        if (probe !~ /^[0-9]+(\.[0-9]+)?$/ && id !~ /^[0-9. \t]+$/) next
      }
      if (id !~ /^[0-9]+(\.[0-9]+)?$/) {
        # tabs would corrupt the record split; fold before emitting
        gsub(/\t/, " ", id)
        print "rejected\t" id
        next
      }
      if (id in seen) next
      seen[id] = 1
      print id "\t" classof(sec)
      next
    }
  ')
  while IFS="$TAB" read -r pm_id pm_rest; do
    [ -n "$pm_id" ] || continue
    if [ "$pm_id" = rejected ]; then
      # pm_rest carries the raw, grammar-violating id
      printf '%s\n' "orchestrate-select: reference bullet rejected - task id '$(sanitize_printable "$pm_rest" '(unprintable)')' violates the task-id grammar" >&2
      continue
    fi
    parked_any="$parked_any$pm_id "
    [ "$pm_rest" = out-of-scope ] && parked_oos="$parked_oos$pm_id "
  done <<EOF
$parked_map
EOF
fi

if [ "$mode" = select ]; then
  state_engine="$script_dir/orchestrate-state.sh"
  if [ ! -x "$state_engine" ]; then
    printf '%s\n' "orchestrate-select: derivation engine $state_engine missing or not executable" >&2
    exit 2
  fi
  # Fail closed when the derivation cannot run (no git work tree, missing or
  # taskless tasks.md, invalid spec id): selecting against absent truth would
  # risk the double-dispatch this rewire exists to prevent (REQ-B1.2). The
  # engine's no-remote / degraded-gh paths still exit 0, so only a hard failure
  # reaches here. Capture the engine's STDOUT (the tagged record stream the
  # parser below keys on) but let its STDERR pass straight through to ours: that
  # keeps both the fail-closed reason AND any success-path warning the engine
  # writes (e.g. a malformed stale_marker_threshold that warns and falls back)
  # visible to the operator, instead of the capture swallowing them.
  if ! state_out=$("$state_engine" "$spec_dir"); then
    printf '%s\n' "orchestrate-select: derivation failed for $spec_dir (cannot select against live truth)" >&2
    exit 2
  fi
  # Read only the evidence-based states (completed / in-progress); ready and
  # blocked are recomputed below from the locally-parsed dependency graph. The
  # other tagged stdout records (contradiction / degraded / refused /
  # malformed-deps) are handled just below or left to the reconcile's and the
  # guards' concern; the engine's free-form stderr already reached the operator.
  completed=" $(printf '%s\n' "$state_out" \
    | awk -F"$TAB" '$1=="task" && $3=="completed"{print $2}' | tr '\n' ' ')"
  inprogress=" $(printf '%s\n' "$state_out" \
    | awk -F"$TAB" '$1=="task" && $3=="in-progress"{print $2}' | tr '\n' ' ')"
  # Transient evidence failure on a v2 bundle (REQ-B1.5): the engine's
  # `degraded` record (a configured remote whose gh query failed — detected by
  # tag, never by message text) means the evidence is partial. A v2 bundle has
  # no committed placement to cross-check, so selecting here could re-dispatch
  # work whose only completion evidence sits behind the failed fetch: dispatch
  # nothing, distinct exit. v1 keeps its documented degraded-but-proceed
  # behavior (forwarded to stderr below) — v1 behavior unchanged.
  if [ "$fv" = 2 ] \
    && printf '%s\n' "$state_out" | awk -F"$TAB" '$1=="degraded" { f = 1 } END { exit !f }'; then
    dmsg=$(printf '%s\n' "$state_out" \
      | awk -F"$TAB" '$1=="degraded" { print $3; exit }')
    printf '%s\n' "orchestrate-select: transient evidence failure - $(sanitize_printable "$dmsg" '(no diagnostic from the engine)'); dispatching nothing (REQ-B1.5)" >&2
    exit 3
  fi
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

# The path travels via ENVIRON, not -v: awk -v performs C-escape processing,
# which would synthesize control bytes from a path carrying literal backslash
# sequences (the drain-gates statuses-whitelist rationale).
printf '%s\n' "$tasks_content" | ORCHESTRATE_SELECT_TASKS_MD="$tasks_md" \
  awk -v mode="$mode" -v fv="$fv" \
  -v completed="$completed" -v inprogress="$inprogress" \
  -v parked="$parked_any" -v parked_oos="$parked_oos" '
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
  # Column-0 fences are illustration (matching the FV and parked-map parses
  # above): a fenced example task heading is never a graph node, and a fenced
  # section heading never relabels the real section around it.
  /^```/ { fence = !fence; next }
  fence { next }
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
      print "orchestrate-select: no task records in " ENVIRON["ORCHESTRATE_SELECT_TASKS_MD"] > "/dev/stderr"
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
        # Out of scope is a parked terminal state — a human decision that is
        # not git-derivable: section-based on v1, bullet-based on v2 (D-3).
        terminal = (index(completed, " " t " ") > 0 \
          || (fv == 2 ? index(parked_oos, " " t " ") > 0 : sec[t] == "Out of scope"))
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
      # v1 reads parked-ness as section membership (because dispatch no longer
      # moves sections, an in-flight task still sits in Forward plan here; live
      # truth excludes it). v2 has no placement sections: every block sits in
      # ## Tasks and parked-ness is a live reference bullet (D-3, REQ-C1.2).
      if (fv == 2) {
        if (index(parked, " " t " ") > 0) continue
      } else if (sec[t] != "Forward plan") continue
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
'
