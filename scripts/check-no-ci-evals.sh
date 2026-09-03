#!/bin/sh
# check-no-ci-evals.sh — the standing CI-exclusion guard.
#
# The kept eval suites are deliberately on-demand: they cost tokens, gate
# nondeterministically, and need an API key that has no place in a public
# repo's CI. That "evals never run in CI" invariant is enforced here
# structurally — not by the eval tasks' mere absence from the `check`
# aggregate, which a future edit could silently undo.
#
# THREE PASSES.
#
#   1. WORKFLOW-TEXT. Scan the workflow files for a wiring of an eval task, in
#      two forms:
#      a. Any mise task in the `eval:` namespace (the sibling of `check:`,
#         `lint:`, `scan:`), in ANY invocation form: `mise run eval:<x>`, the
#         `run` alias `mise r eval:<x>`, the implicit `mise eval:<x>`, a flag or
#         quote between `run` and the task. The rule is "a `mise` invocation
#         whose line reaches an `eval:` task", matched by `mise` followed
#         anywhere on the line by `eval:` — deliberately permissive, because a
#         security control should fail loud on a near-miss rather than let a
#         novel invocation form through. Matching the `eval:` namespace (not the
#         bare substring "eval") still spares a legitimately named task like
#         `evaluate-release` and prose that merely says "eval".
#      b. Invoking a kept-eval runner script directly, bypassing mise entirely
#         (`sh scripts/prompt-eval.sh …`, `./scripts/behavioral-eval.sh …`).
#         Both on-demand runners are covered — the guard must see EVERY eval
#         harness, not only `prompt-eval.sh`. The runner name is matched at a
#         leading TOKEN BOUNDARY (`(^|[^[:alnum:]_-])`), so a path or whitespace
#         before it triggers but a `-`/word-char prefix does not: the test file
#         `tests/test-behavioral-eval.sh` (which CI legitimately runs via the
#         `tests/*.sh` glob) is NOT mistaken for the runner it exercises.
#
#   2. TASK-GRAPH CLOSURE. Text alone misses the indirect wiring: an eval task
#      reached through a `depends` chain from a task CI does invoke. So the
#      mise task graph is parsed, the ROOT SET is every task named on a
#      mise-invoking workflow line (pass 1's invocation-form matching, then a
#      token-boundary match against the parsed task names), and the closure over
#      `depends`, `depends_post`, and `wait_for` is walked. Reaching a task in
#      the `eval:` namespace fails, and the offending chain is printed from its
#      root. A dependency naming the namespace itself — `depends = ["eval:*"]`,
#      which mise expands — fails on the name, so a wildcard cannot launder the
#      edge.
#
#   3. RUN-BODY. A task's `run` body can invoke another task, so the graph is
#      not only its `depends` edges. Every run body in the closure is scanned
#      with pass 1's matching: invoking an eval task or a runner script there
#      fails, and a run-body `mise run <task>` feeds the closure as an edge, so
#      a run-body → depends → `eval:` chain is caught too. Only run bodies of
#      CI-reachable tasks are scanned; an eval task's own run body naturally
#      invokes its runner, and that is what being off the closure means.
#
# PARSE BOUNDARY (deliberate). `mise.toml` ONLY — the file passed as the second
# argument, defaulting to `mise.toml` then `.mise.toml` in the working
# directory. File-based task definitions (`tasks/`, `.mise/tasks/`), imported
# or included task files, and the `mise.local.toml` / config-path layering are
# outside the parse: a task defined there is invisible to passes 2 and 3, and a
# `depends` entry naming one reads as a dangling edge rather than a parse
# failure. Within the file, a strict subset of TOML is modeled: `[tasks.<name>]`
# and `[tasks."<name>"]` tables, single-line and multi-line arrays, single-line
# strings, and `'''`/`"""` multi-line strings. An array-of-tables header, a bare
# inline `[tasks]` table, and a nested task table are NOT modeled and are
# reported as parse failures rather than half-read. Run bodies are taken as raw
# text and matched, never executed, so an escape sequence inside one only ever
# affects matching. `description` values are prose, not run bodies, and are not
# scanned — otherwise this file's own documentation of the `eval:` namespace
# would trip the guard.
#
# FAIL-CLOSED. A `mise.toml` that is present but unparseable, or that parses to
# zero tasks, fails: an unreadable graph cannot show the closure is clean. So do
# zero roots against a non-empty graph — workflows exist and none of them names
# a task in the graph, which is indistinguishable from the root extraction
# having broken, and would otherwise pass vacuously over every task in the file.
# An ABSENT `mise.toml` is the one vacuous pass: there is no task graph to close
# over at all, the symmetric case to an absent workflow directory.
#
# Untrusted input: workflow files and `mise.toml` are PR-controllable. They are
# read as text and matched with grep and awk only; no content is ever executed
# or expanded. The scanned directory and the graph file are the only positional
# arguments; the only glob is the fixed `*.yml` / `*.yaml` pattern under that
# directory, so no file content is subject to expansion.
#
# Both graph passes are a backstop against ACCIDENTAL wiring, not a boundary
# against a committer who controls these files — who could delete the guard or
# rename the task out of the `eval:` namespace outright.
#
# Usage: check-no-ci-evals.sh [<workflows-dir> [<mise-toml>]]
#   Defaults: .github/workflows, then mise.toml or .mise.toml.
#   -h, --help  print this header.
# Exit: 0 no eval task reachable from CI (or nothing to scan); 1 a violation or
#   a fail-closed condition (offending file:line or task chain on stderr);
#   2 usage error.
#
# Portable POSIX sh + grep + awk; bash 3.2 / BSD tooling. C locale pinned so the
# ERE character classes do not vary by host locale.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

case "${1:-}" in
  -h | --help)
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
    exit 0
    ;;
esac

if [ $# -gt 2 ]; then
  echo "usage: check-no-ci-evals.sh [<workflows-dir> [<mise-toml>]]" >&2
  exit 2
fi

dir="${1:-.github/workflows}"
if [ $# -ge 2 ]; then
  mise_toml="$2"
elif [ -f mise.toml ]; then
  mise_toml="mise.toml"
else
  mise_toml=".mise.toml"
fi

# No workflow directory at all: nothing can wire an eval into CI. Vacuously
# clean (a repo may legitimately ship no workflows).
if [ ! -d "$dir" ]; then
  echo "check-no-ci-evals: no workflow directory at '$dir'; nothing to scan."
  exit 0
fi

# Enumerate the workflow files into the positional parameters. A non-matching
# glob stays literal, so each candidate is existence-checked before use.
set --
for f in "$dir"/*.yml "$dir"/*.yaml; do
  [ -f "$f" ] && set -- "$@" "$f"
done

if [ "$#" -eq 0 ]; then
  echo "check-no-ci-evals: no workflow files under '$dir'; nothing to scan."
  exit 0
fi

# ---- Pass 1: workflow text ----
#
# The mise-invocation alternative is matched in two stages so BOTH conditions
# hold on the line: the line invokes `mise` (at a TOKEN BOUNDARY, so a word
# merely ending in `mise` like `premise` does not trigger), and it carries an
# `eval:` at a TOKEN BOUNDARY (so the `eval` namespace triggers but a substring
# inside `retrieval:` / `medieval:` / `evaluate-release` does not).
#
# Two residuals, both accepted. A contrived line that invokes mise AND writes
# the literal `eval:` after a boundary elsewhere (a trailing `echo "eval: …"`)
# over-blocks — far rarer than a real `retrieval:` task, and it only causes a
# spurious CI failure, never a silent bypass. And a `run: |` block that splits
# the invocation across a backslash-newline continuation executes but evades the
# same-line match; an accidental multi-line split of `mise run eval:skill` does
# not happen in practice, so the line-based match is kept deliberately over a
# continuation-aware state machine.
#
# -H forces the filename prefix even for a single file (file:line:match report).
mise_eval="$(grep -HnE '(^|[^[:alnum:]_-])mise[[:space:]]' "$@" 2>/dev/null | grep -E '(^|[^[:alnum:]_-])eval:' || true)"
direct="$(grep -HnE '(^|[^[:alnum:]_-])(prompt-eval|behavioral-eval)\.sh' "$@" 2>/dev/null || true)"
hits="$(printf '%s\n%s' "$mise_eval" "$direct" | grep -v '^[[:space:]]*$' | sort -u || true)"

if [ -n "$hits" ]; then
  echo "check-no-ci-evals: an eval task is wired into a CI workflow." >&2
  echo "The kept eval harnesses (the eval: mise namespace — e.g. eval:skill, eval:behavioral)" >&2
  echo "run on demand only, never in CI or 'mise run check'." >&2
  echo "Offending references:" >&2
  printf '%s\n' "$hits" | while IFS= read -r h; do
    [ -n "$h" ] && echo "  $h" >&2
  done
  exit 1
fi

# ---- Passes 2 and 3: task-graph closure and run bodies ----

if [ ! -f "$mise_toml" ]; then
  echo "check-no-ci-evals: no eval task wired into any workflow under '$dir'."
  echo "check-no-ci-evals: no mise.toml at '$mise_toml'; no task graph to close over."
  exit 0
fi

graph_awk="$(
  cat <<'AWK'
function isnamechar(c) {
  return (c != "" && c ~ /[[:alnum:]_:.-]/)
}
# Does <name> appear in <line> as a whole task-name token? `:` and `-` count as
# name characters, so `check` does not match inside `check:specs`.
function tokmatch(line, name,   off, pos, before, after) {
  if (name == "") return 0
  off = 1
  while ((pos = index(substr(line, off), name)) > 0) {
    pos += off - 1
    before = (pos == 1) ? "" : substr(line, pos - 1, 1)
    after = substr(line, pos + length(name), 1)
    if (!isnamechar(before) && !isnamechar(after)) return 1
    off = pos + 1
  }
  return 0
}
function is_mise(s) { return s ~ /(^|[^[:alnum:]_-])mise[[:space:]]/ }
function has_evalns(s) { return s ~ /(^|[^[:alnum:]_-])eval:/ }
function is_runner(s) { return s ~ /(^|[^[:alnum:]_-])(prompt-eval|behavioral-eval)\.sh/ }
function bail(why) { if (parse_error == "") parse_error = why }

function addtask(name) {
  if (name == "") { bail("a [tasks...] header with no task name"); return }
  if (!(name in taskset)) { taskset[name] = 1; tasklist[++ntasks] = name }
}
function adddep(owner, dep, kind) {
  ndep[owner]++
  deps[owner, ndep[owner]] = dep
  depkind[owner, ndep[owner]] = kind
}
function addrun(owner, text) {
  if (owner == "" || text == "") return
  nrun[owner]++
  runbody[owner, nrun[owner]] = text
}
function addedge(from, to, kind) {
  nedge[from]++
  edge[from, nedge[from]] = to
  ekind[from, nedge[from]] = kind
}

function header(h,   inner, name, q) {
  sub(/[[:space:]]*#.*$/, "", h)
  cur = ""
  if (substr(h, 1, 2) == "[[") { bail("array-of-tables header not modeled: " h); return }
  if (substr(h, length(h), 1) != "]") { bail("unterminated table header: " h); return }
  inner = substr(h, 2, length(h) - 2)
  if (inner == "tasks") { bail("inline [tasks] table not modeled"); return }
  if (substr(inner, 1, 6) != "tasks.") return
  name = substr(inner, 7)
  q = substr(name, 1, 1)
  if ((q == "\"" || q == "'") && substr(name, length(name), 1) == q)
    name = substr(name, 2, length(name) - 2)
  else if (index(name, ".") > 0) { bail("nested task table not modeled: " h); return }
  addtask(name)
  cur = name
}

function collect_deps(buf, kind, owner,   rest, s) {
  rest = buf
  while (match(rest, /"[^"]*"|'[^']*'/)) {
    s = substr(rest, RSTART + 1, RLENGTH - 2)
    rest = substr(rest, RSTART + RLENGTH)
    adddep(owner, s, kind)
  }
}
function finish_array() {
  if (arrkey == "run") addrun(arrowner, arrbuf)
  else collect_deps(arrbuf, arrkey, arrowner)
  arrkey = ""; arrbuf = ""; arrowner = ""
}

function value_deps(key, val) {
  if (substr(val, 1, 1) == "[") {
    arrkey = key; arrbuf = val; arrowner = cur
    if (index(val, "]") > 0) finish_array()
  } else if (substr(val, 1, 1) == "\"" || substr(val, 1, 1) == "'") {
    collect_deps(val, key, cur)
  } else {
    bail("unrecognized " key " value: " val)
  }
}

# Run bodies are matched, never resolved, so the raw value text is kept
# verbatim — quotes and all — instead of being unescaped into a string.
function value_run(val,   d, rest, p) {
  d = substr(val, 1, 3)
  if (d == "'''" || d == "\"\"\"") {
    rest = substr(val, 4)
    p = index(rest, d)
    if (p > 0) { addrun(cur, substr(rest, 1, p - 1)); return }
    mldelim = d; mlowner = cur
    addrun(cur, rest)
    return
  }
  if (substr(val, 1, 1) == "[") {
    arrkey = "run"; arrbuf = val; arrowner = cur
    if (index(val, "]") > 0) finish_array()
    return
  }
  addrun(cur, val)
}

function chain(t,   path, u) {
  path = t
  u = parent[t]
  while (u != "") {
    path = u " -(" pkind[t] ")-> " path
    t = u
    u = parent[t]
  }
  return path
}
function push(v, from, kind) {
  if (v in seen) return
  seen[v] = 1
  parent[v] = from
  pkind[v] = kind
  queue[++qn] = v
}

FILENAME == misefile {
  raw = $0
  if (mldelim != "") {
    p = index(raw, mldelim)
    if (p > 0) { addrun(mlowner, substr(raw, 1, p - 1)); mldelim = "" }
    else addrun(mlowner, raw)
    next
  }
  if (arrkey != "") {
    arrbuf = arrbuf " " raw
    if (index(raw, "]") > 0) finish_array()
    next
  }
  line = raw
  sub(/^[[:space:]]+/, "", line)
  sub(/[[:space:]]+$/, "", line)
  if (line == "" || substr(line, 1, 1) == "#") next
  if (substr(line, 1, 1) == "[") { header(line); next }
  eq = index(line, "=")
  if (eq == 0 || cur == "") next
  key = substr(line, 1, eq - 1)
  gsub(/[[:space:]"']/, "", key)
  val = substr(line, eq + 1)
  sub(/^[[:space:]]+/, "", val)
  if (key == "depends" || key == "depends_post" || key == "wait_for") value_deps(key, val)
  else if (key == "run") value_run(val)
  next
}

{
  if (is_mise($0)) { wfline[++nwf] = $0; wfsrc[nwf] = FILENAME ":" FNR }
}

END {
  if (mldelim != "") bail("unterminated multi-line string")
  if (arrkey != "") bail("unterminated array")
  if (parse_error != "") {
    print "could not parse the mise task graph in " misefile ": " parse_error
    print "an unreadable graph cannot show the eval: namespace stays out of CI."
    exit 1
  }
  if (ntasks == 0) {
    print misefile " parsed to zero tasks, so the closure would prove nothing."
    exit 1
  }

  for (i = 1; i <= ntasks; i++) {
    u = tasklist[i]
    for (j = 1; j <= ndep[u]; j++) {
      d = deps[u, j]
      matched = 0
      if (index(d, "*") > 0) {
        rx = d
        gsub(/\*/, ".*", rx)
        rx = "^" rx "$"
        for (k = 1; k <= ntasks; k++)
          if (tasklist[k] ~ rx) { addedge(u, tasklist[k], depkind[u, j]); matched = 1 }
      } else if (d in taskset) {
        addedge(u, d, depkind[u, j])
        matched = 1
      }
      # A dependency that resolves to no task in this file is outside the parse
      # boundary, so the closure will never walk it. Its name is then the only
      # thing left to read, and naming the eval: namespace is enough.
      if (!matched && has_evalns(d)) evaldep[u] = depkind[u, j] " = " d
    }
  }

  qn = 0
  nroots = 0
  for (i = 1; i <= nwf; i++)
    for (k = 1; k <= ntasks; k++)
      if (!(tasklist[k] in seen) && tokmatch(wfline[i], tasklist[k])) {
        nroots++
        rootsrc[tasklist[k]] = wfsrc[i]
        push(tasklist[k], "", "")
      }
  if (nroots == 0) {
    print "no CI-invoked mise task found: no workflow line names a task from " misefile "."
    print "with zero roots the closure would pass vacuously over every task in the graph."
    exit 1
  }

  qi = 0
  while (qi < qn) {
    u = queue[++qi]
    if (u ~ /^eval:/)
      viol[++nviol] = "CI reaches eval task " u ": " chain(u)
    if (u in evaldep)
      viol[++nviol] = "task " u " depends on the eval: namespace (" evaldep[u] "): " chain(u)
    for (j = 1; j <= nrun[u]; j++) {
      r = runbody[u, j]
      if ((is_mise(r) && has_evalns(r)) || is_runner(r)) {
        body = r
        sub(/^[[:space:]]+/, "", body)
        viol[++nviol] = "the run body of CI-invoked task " u " invokes an eval harness: " body
      }
      if (is_mise(r))
        for (k = 1; k <= ntasks; k++)
          if (tokmatch(r, tasklist[k])) push(tasklist[k], u, "run body")
    }
    for (j = 1; j <= nedge[u]; j++) push(edge[u, j], u, ekind[u, j])
  }

  if (nviol == 0) exit 0
  print "an eval task is reachable from CI through the mise task graph."
  for (i = 1; i <= nviol; i++) print "  " viol[i]
  exit 1
}
AWK
)"

graph_out="$(awk -v misefile="$mise_toml" "$graph_awk" "$mise_toml" "$@")"
graph_rc=$?

if [ "$graph_rc" -ne 0 ]; then
  echo "check-no-ci-evals: $(printf '%s' "$graph_out" | head -n 1)" >&2
  printf '%s\n' "$graph_out" | tail -n +2 | while IFS= read -r l; do
    [ -n "$l" ] && echo "$l" >&2
  done
  exit 1
fi

echo "check-no-ci-evals: no eval task wired into any workflow under '$dir'."
echo "check-no-ci-evals: no CI-invoked task in '$mise_toml' reaches the eval: namespace."
exit 0
