#!/bin/sh
# check-task-registration.sh — every `check:` / `lint:` / `scan:` task in
# mise.toml must be reachable from the `check` aggregate.
#
# A guard task the aggregate never reaches runs only for whoever remembers to
# invoke it by name, which in practice is CI logs and nobody. This is the
# standing form of the registration sweep:
# scripts/check-guard-wiring.sh asks whether every check-*.sh SCRIPT is run by
# something; this asks the complementary question one level up, whether every
# guard TASK is part of the gate. A task with an inline run body and no script
# is visible only here.
#
# WHAT COUNTS AS REGISTERED. The task's name is reached from the aggregate by
# walking `depends` and `depends_post` edges, wildcards expanded against the
# tasks this file defines. `wait_for` is not an edge: it waits for a task
# already scheduled and never schedules one, so a task named only there still
# runs for nobody. Text is not wiring: a name that appears in a description, a
# comment, or another task's run body registers nothing.
#
# PARSE BOUNDARY. The repo's own mise.toml, read as text — the same boundary
# scripts/check-no-ci-evals.sh documents. Tasks mise layers from
# mise.local.toml, file-based task directories, or an included config are
# outside it: a machine-local task is not wiring any other checkout has. A
# dependency naming no task in this file is reported as a dangling edge.
# Task headers are read in the `[tasks.name]` / `[tasks."ns:name"]` form, a
# sub-table header (`[tasks.name.env]`) belonging to the task it names. A
# dependency written as a multi-line string is not read as an edge.
#
# FAILS CLOSED on anything that would narrow the scan or hide a task: a
# missing or unreadable mise.toml, a file parsing to zero tasks, no aggregate
# task, zero namespaced tasks to check, or a tasks header outside the parsed
# form (a bare `[tasks]` table with dotted-key tasks under it, an array of
# tables, a header that never closes). Each of those would otherwise exit 0
# having proven nothing.
#
# Untrusted input: mise.toml is PR-controllable. It is read with awk as data;
# nothing from it is executed, sourced, or interpolated into program text.
#
# Usage: check-task-registration.sh [--repo-root <dir>] [--aggregate <task>]
# Exit codes: 0 every namespaced task is registered; 1 one or more are not;
# 2 usage error; 5 fail-closed (an input that would make the scan vacuous).
#
# POSIX sh on the macOS + Linux support bar.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=check-task-registration
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

repo_root=$(cd "$script_dir/.." && pwd) || exit 2
aggregate=check
while [ "$#" -gt 0 ]; do
  case $1 in
    --repo-root)
      [ "$#" -ge 2 ] || {
        echo "$me: --repo-root needs a directory" >&2
        exit 2
      }
      repo_root=$2
      shift 2
      ;;
    --aggregate)
      [ "$#" -ge 2 ] || {
        echo "$me: --aggregate needs a task name" >&2
        exit 2
      }
      aggregate=$2
      shift 2
      ;;
    -h | --help)
      echo "usage: check-task-registration.sh [--repo-root <dir>] [--aggregate <task>]" >&2
      exit 0
      ;;
    *)
      echo "$me: unknown argument" >&2
      exit 2
      ;;
  esac
done

# The aggregate name reaches the awk program through -v, so it is bound to the
# task-name grammar first; anything else is a usage error, never a pattern.
case $aggregate in
  '' | *[!A-Za-z0-9:_.-]*)
    echo "$me: --aggregate must be a task name (letters, digits, ':', '_', '.', '-')" >&2
    exit 2
    ;;
esac

repo_root=$(cd "$repo_root" 2>/dev/null && pwd) || {
  echo "$me: repo root is not a readable directory" >&2
  exit 5
}
misefile="$repo_root/mise.toml"
[ -r "$misefile" ] || {
  echo "$me: $misefile is missing or unreadable — there is no task graph to walk" >&2
  exit 5
}

# One awk pass: collect task headers and the two edge kinds, skipping
# comments and the inside of triple-quoted strings; then walk the closure from
# the aggregate and print a verdict block:
#   PARSE <why>       the scan would be vacuous (fail closed)
#   COUNT <n>         tasks parsed
#   DANGLING <name>   an edge naming no task in this file
#   UNREGISTERED <t>  a namespaced task the aggregate does not reach
report=$(awk -v agg="$aggregate" '
  function unquote(s) {
    sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
    if (s ~ /^"[^"]*"$/ || s ~ /^\x27[^\x27]*\x27$/) s = substr(s, 2, length(s) - 2)
    return s
  }
  # Record one dependency token: the first word of the quoted value (mise
  # accepts "task --arg" forms), from the current task.
  function add_edge(tok,   w) {
    tok = unquote(tok)
    split(tok, parts, /[ \t]+/); w = parts[1]
    if (w == "") return
    nedges++; efrom[nedges] = cur; eto[nedges] = w
  }
  # Pull every quoted token out of an array fragment.
  function harvest(s,   m) {
    while (match(s, /"[^"]*"|\x27[^\x27]*\x27/)) {
      m = substr(s, RSTART, RLENGTH)
      add_edge(m)
      s = substr(s, RSTART + RLENGTH)
    }
  }
  function glob_to_re(g,   re, i, c) {
    re = "^"
    for (i = 1; i <= length(g); i++) {
      c = substr(g, i, 1)
      if (c == "*") re = re ".*"
      else if (index(".^$+?()[]{}|\\", c)) re = re "\\" c
      else re = re c
    }
    return re "$"
  }
  # Reduce one physical line to its TOML structure: a comment is dropped (a
  # `#` starts one only outside quotes; inside a quoted name it is part of
  # the name), and the contents of a multi-line string are dropped, across
  # lines (`ml` holds the open delimiter between calls), so nothing inside
  # one can read as a header or an edge. Three quote characters open a
  # multi-line string only outside a single-line string and outside a
  # comment, as in TOML.
  function scan(s,   i, n, c, t, q, out) {
    out = ""; q = ""; n = length(s); i = 1
    while (i <= n) {
      c = substr(s, i, 1); t = substr(s, i, 3)
      if (ml != "") {
        if (t == ml) { ml = ""; i += 3 } else i++
        continue
      }
      if (q != "") {
        if (q == "\"" && c == "\\") { out = out c substr(s, i + 1, 1); i += 2; continue }
        if (c == q) q = ""
        out = out c; i++
        continue
      }
      if (t == "\"\"\"" || t == "\x27\x27\x27") { ml = t; i += 3; continue }
      if (c == "\"" || c == "\x27") q = c
      else if (c == "#") break
      out = out c; i++
    }
    return out
  }
  # Position of the first `]` outside quotes, or 0: a `]` inside a quoted
  # dependency ("task --only=[a]") does not close the array.
  function close_at(s,   i, c, q) {
    q = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (q != "") {
        if (q == "\"" && c == "\\") i++
        else if (c == q) q = ""
        continue
      }
      if (c == "\"" || c == "\x27") q = c
      else if (c == "]") return i
    }
    return 0
  }
  function parse_error(why) { perr = why " at line " NR; exit }
  {
    line = scan($0)
    if (inarr) {
      p = close_at(line)
      if (p) { frag = substr(line, 1, p - 1); inarr = 0 } else frag = line
      harvest(frag)
      next
    }
    if (line ~ /^[ \t]*\[/) {
      h = line; sub(/^[ \t]*\[/, "", h)
      if (h ~ /^\[?[ \t]*tasks[ \t]*(\]|\.)/) {
        # A tasks header. `[tasks.<name>]` declares a task and
        # `[tasks.<name>.<sub>]` a sub-table of one, whose lines belong to
        # it. A bare `[tasks]` (dotted-key tasks under it), an array of
        # tables, or a header this parser cannot read may declare a task it
        # would never see, so each fails closed.
        if (h ~ /^\[/) parse_error("an array-of-tables header ([[tasks...]])")
        sub(/^[ \t]*tasks[ \t]*/, "", h)
        if (h ~ /^\]/) parse_error("a bare [tasks] table (dotted-key tasks are outside the parse)")
        sub(/^\.[ \t]*/, "", h)
        if (h ~ /^["\x27]/) {
          q = substr(h, 1, 1); h = substr(h, 2)
          p = index(h, q)
          if (p == 0) parse_error("a task header this parser cannot read")
          name = substr(h, 1, p - 1); h = substr(h, p + 1)
        } else {
          match(h, /^[^].\x27" \t]+/)
          if (RLENGTH <= 0) parse_error("a task header this parser cannot read")
          name = substr(h, 1, RLENGTH); h = substr(h, RLENGTH + 1)
        }
        sub(/^[ \t]*/, "", h)
        if (!(h ~ /^\][ \t]*$/ || h ~ /^\./)) parse_error("a task header this parser cannot read")
        cur = name
        if (!(cur in tasks)) { tasks[cur] = 1; ntasks++; order[ntasks] = cur }
        next
      }
      cur = ""; next
    }
    if (cur == "") next
    if (line ~ /^[ \t]*(depends|depends_post)[ \t]*=/) {
      rhs = line; sub(/^[^=]*=[ \t]*/, "", rhs)
      if (rhs ~ /^\[/) {
        sub(/^\[/, "", rhs)
        p = close_at(rhs)
        if (p) rhs = substr(rhs, 1, p - 1); else inarr = 1
        harvest(rhs)
      } else {
        add_edge(rhs)
      }
    }
  }
  END {
    if (perr != "") { print "PARSE\t" FILENAME " has " perr ", which may declare a task this check would never see"; exit }
    if (ml != "") { print "PARSE\t" FILENAME " ends inside an unterminated triple-quoted string, which would hide every task after it"; exit }
    if (ntasks == 0) { print "PARSE\t" FILENAME " parsed to zero tasks"; exit }
    if (!(agg in tasks)) { print "PARSE\tno `" agg "` task in " FILENAME ", so there is no gate to walk"; exit }
    nscoped = 0
    for (i = 1; i <= ntasks; i++) if (order[i] ~ /^(check|lint|scan):/) nscoped++
    if (nscoped == 0) { print "PARSE\t" FILENAME " defines no check:/lint:/scan: task"; exit }
    print "COUNT\t" ntasks
    # Expand wildcard edges against the parsed task set; the literal edge
    # stays so a wildcard matching nothing is reported as dangling. The bound
    # is taken first: a task whose own name holds a `*` would otherwise
    # re-enter the expansion as fast as it is appended.
    ne = nedges
    for (e = 1; e <= ne; e++) {
      if (index(eto[e], "*") == 0) continue
      re = glob_to_re(eto[e])
      for (i = 1; i <= ntasks; i++) if (order[i] ~ re) { nedges++; efrom[nedges] = efrom[e]; eto[nedges] = order[i]; matched[e] = 1 }
    }
    reached[agg] = 1
    do {
      grew = 0
      for (e = 1; e <= nedges; e++) {
        if ((efrom[e] in reached) && (eto[e] in tasks) && !(eto[e] in reached)) { reached[eto[e]] = 1; grew = 1 }
      }
    } while (grew)
    for (e = 1; e <= nedges; e++) {
      if (!(efrom[e] in reached)) continue
      if (eto[e] in tasks) continue
      if (index(eto[e], "*") && (e in matched)) continue
      if (!(eto[e] in dangled)) { dangled[eto[e]] = 1; print "DANGLING\t" eto[e] }
    }
    for (i = 1; i <= ntasks; i++) {
      t = order[i]
      if (t ~ /^(check|lint|scan):/ && !(t in reached)) print "UNREGISTERED\t" t
    }
  }
' "$misefile") || {
  echo "$me: could not read $misefile — failing closed" >&2
  exit 5
}

case $report in
  PARSE*)
    echo "$me: ${report#PARSE?} — failing closed rather than reporting a clean scan" >&2
    exit 5
    ;;
  '')
    echo "$me: the parser reported nothing — failing closed" >&2
    exit 5
    ;;
esac

count=$(printf '%s\n' "$report" | awk -F'\t' '$1 == "COUNT" { print $2; exit }')
case ${count:-0} in
  '' | *[!0-9]* | 0)
    echo "$me: the parse reported no tasks — failing closed" >&2
    exit 5
    ;;
esac

# Task names are PR-controlled text that reaches the terminal: emit them
# through printf with control bytes stripped, never echo, which under dash
# expands backslash-escape text into live escape sequences.
say() { printf '%s\n' "$*" | tr -d '\000-\011\013-\037\177' >&2; }

printf '%s\n' "$report" | awk -F'\t' '$1 == "DANGLING" { print $2 }' | while IFS= read -r d; do
  say "$me: note: dependency on \`$d\` names no task in this repo's mise.toml — outside the parse boundary"
done

unregistered=$(printf '%s\n' "$report" | awk -F'\t' '$1 == "UNREGISTERED" { print $2 }')
if [ -n "$unregistered" ]; then
  printf '%s\n' "$unregistered" | while IFS= read -r t; do
    say "$me: task \`$t\` is not reached from the \`$aggregate\` aggregate"
  done
  say "$me: a guard task the gate never reaches runs for nobody. Add it to \`$aggregate\`'s depends (directly or through a task the aggregate already reaches)."
  exit 1
fi

echo "$me: ok, every check:/lint:/scan: task is reached from \`$aggregate\` ($count tasks parsed)"
exit 0
