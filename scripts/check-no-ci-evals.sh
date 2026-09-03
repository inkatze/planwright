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
#   1. WORKFLOW-TEXT. Scan the workflow files for a wiring of an eval task:
#      a. Any mise task in the `eval:` namespace, in ANY invocation form:
#         `mise run eval:<x>`, the `run` alias `mise r eval:<x>`, the implicit
#         `mise eval:<x>`, a flag or quote between `run` and the task. The rule
#         is "a line that both invokes `mise` and carries an `eval:` token",
#         in either order — deliberately permissive, because a security control
#         should fail loud on a near-miss rather than let a novel invocation
#         form through. Matching the `eval:` namespace (not the bare substring
#         "eval") still spares a legitimately named task like
#         `evaluate-release` and prose that merely says "eval".
#      b. Invoking a kept-eval runner script directly, bypassing mise entirely
#         (`sh scripts/prompt-eval.sh …`, `./scripts/behavioral-eval.sh …`).
#         Both on-demand runners are covered — the guard must see EVERY eval
#         harness, not only `prompt-eval.sh`. The runner name is matched at a
#         leading TOKEN BOUNDARY (`(^|[^[:alnum:]_-])`), so a path or
#         whitespace before it triggers but a `-`/word-char prefix does not:
#         the test file `tests/test-behavioral-eval.sh` (which CI legitimately
#         runs via the `tests/*.sh` glob) is NOT mistaken for the runner it
#         exercises.
#      c. An `eval:` token on any line that is not a full-line comment, even
#         with no `mise` beside it. A parameterized invocation puts the task
#         name somewhere else entirely — a build matrix entry, a workflow input
#         default, an action's `with:` value — and `mise run ${{ matrix.task }}`
#         names nothing the other forms can see. Full-line comments are left to
#         form (a), so prose about the namespace does not fail a build while a
#         commented-out invocation still does.
#      This pass reads COMMENTS too, so a comment that looks like a wiring
#      over-blocks. That is the fail-loud direction and is kept deliberately.
#
#   2. TASK-GRAPH CLOSURE. Text alone misses the indirect wiring: an eval task
#      reached through a `depends` chain from a task CI does invoke. So the
#      mise task graph is parsed, the ROOT SET is every task (or task alias)
#      named on a mise-invoking workflow line, and the closure over `depends`,
#      `depends_post`, and `wait_for` is walked. Reaching a task in the `eval:`
#      namespace fails, and the offending chain is printed from the workflow
#      line that rooted it. A dependency naming the namespace — including by
#      wildcard, `depends = ["eval:*"]` or the catch-all `depends = ["*"]`,
#      both of which mise expands — fails on the name, so a wildcard cannot
#      launder the edge, and neither can a dependency on an eval task defined
#      outside this file. A wildcard is judged by the literal text before its
#      first wildcard character rather than by what it happens to match here,
#      because mise expands it over tasks this parse cannot see: `lint:*`
#      diverges from `eval:` immediately and is clear, while `eval*`,
#      `*:corpus` and a bare `*` can all name the namespace and fail.
#      Unlike pass 1, ROOT extraction skips full-line comments: a comment
#      cannot invoke anything, and counting one as a root would mask the
#      zero-roots fail-closed below.
#
#   3. RUN-BODY. A task's `run` body can invoke another task, so the graph is
#      not only its `depends` edges. Every run body in the closure is scanned
#      with pass 1's matching: invoking an eval task or a runner script there
#      fails, and a run-body `mise run <task>` feeds the closure as an edge, so
#      a run-body → depends → `eval:` chain is caught too. A wildcard operand
#      (`mise run all:*`) expands the same way a `depends` wildcard does,
#      except that a BARE `*` is ignored here — in a shell body it is far more
#      likely `rm -rf *` than a mise task selector. A run body is scanned whole,
#      so a SHELL comment inside one over-blocks exactly as a workflow comment
#      does in pass 1; a TOML comment after the value is not body text and is
#      stripped before matching. Only run bodies of CI-reachable tasks are
#      scanned; an eval task's own run body naturally invokes its runner, and
#      that is what being off the closure means.
#
# WHAT THE GRAPH PASSES DO NOT FOLLOW. Both are a backstop against ACCIDENTAL
# wiring, not a boundary against a committer who controls these files — who
# could delete the guard or rename the task out of the `eval:` namespace
# outright. Concretely, and by design:
#   * A run body is matched as TEXT and never followed. `run = "sh
#     scripts/foo.sh"` is not opened, so an eval invocation inside that script
#     is invisible. The same holds for a task declared with mise's `file =`
#     key, and for any workflow step that runs a script directly.
#   * Workflow `uses:` is not resolved: a local composite action or a reusable
#     workflow that wires an eval in is outside all three passes.
#   * An invocation split across physical lines (a backslash continuation, or
#     a YAML folded scalar) evades the line-based match, which also means the
#     task it names never becomes a root and its subtree goes unwalked.
# Closing any of these means executing or resolving PR-controlled content,
# which is a bigger hazard than the one being guarded.
#
# PARSE BOUNDARY (deliberate). `mise.toml` ONLY: the file passed as the second
# argument, or by default the first of `mise.toml`, `.mise.toml`,
# `mise/config.toml`, `.mise/config.toml`, `.config/mise.toml`,
# `.config/mise/config.toml` found at the repo root. File-based task
# definitions (`tasks/`, `.mise/tasks/`), imported or included task files, and
# `mise.local.toml` / `mise.<env>.toml` layering are outside the parse: a task
# defined there is invisible to passes 2 and 3, and a `depends` entry naming
# one reads as a dangling edge rather than a parse failure (its name is still
# checked against the `eval:` namespace). Within the file, a strict subset of
# TOML is modeled: `[tasks.<name>]` and `[tasks."<name>"]` tables, arrays
# (nested and multi-line), single-line strings, and `'''`/`"""` multi-line
# strings as a `run` body. These shapes are a PARSE FAILURE rather than
# half-read: an array-of-tables header, a bare `[tasks]` table, a nested task
# table, a dotted-key or inline-table task definition, a multi-line string used
# as a dependency or inside an array, an unterminated string, key or array, an
# unreadable value form. A repeated `[tasks.<name>]` header is the one shape
# read instead of refused: both blocks' edges merge under the one name, which
# over-blocks and never under-blocks, and mise rejects a file with a duplicate
# header before this guard's verdict could matter. Comments and quoting are
# tracked while parsing, so a `#` or a `]` inside a string is structure-neutral
# and one inside a comment cannot manufacture a dependency; basic-string
# escapes are decoded before matching, so a name mise resolves to the `eval:`
# namespace cannot hide behind its spelling. The decoder validates only what
# it needs to read the graph: a malformed `\u` escape is refused, but one TOML
# forbids for another reason (a surrogate, an unknown escape letter) is decoded
# rather than refused. Decoding only ever makes more text match, never less, so
# such a file over-blocks at worst, and mise rejects it before this guard's
# verdict could matter.
# `description` values are prose and are not scanned as run bodies. A `*` or
# `?` in a dependency is a wildcard; a bracket expression is read as literal
# text, so it resolves to no task and lands in the same accepted residual as
# any dependency pointing outside this file, while its `eval:`-reachability is
# still judged from the text before the bracket.
#
# FAIL-CLOSED. The guard fails, rather than passing, whenever it cannot prove
# the closure is clean: a `mise.toml` that is present but unparseable or that
# parses to zero tasks; zero roots against a non-empty graph (workflows exist
# and none of them names a task in the graph, which is indistinguishable from
# the root extraction having broken); a workflow directory or file that cannot
# be read; a grep or awk that fails rather than reporting; an argument that
# does not resolve. The one vacuous pass is a repo with no discoverable
# `mise.toml` at all: there is no task graph to close over, the symmetric case
# to an absent workflow directory. Pass `-` as the second argument to ask for
# that state explicitly (the workflow-text pass alone).
#
# Untrusted input: workflow files and `mise.toml` are PR-controllable. They are
# read as text and matched with grep and awk; no content is ever executed,
# sourced, or subjected to path expansion, and no content reaches an awk
# program-text or `-v` position. One exception worth naming: a `depends`
# wildcard is compiled into a regular expression, with every regex
# metacharacter other than the two wildcards escaped, so a crafted pattern can
# neither inject regex syntax nor build an expression that kills awk.
#
# Usage: check-no-ci-evals.sh [-h|--help] [<workflows-dir> [<mise-toml>|-]]
#   Defaults, both derived from this script's location so a bare invocation
#   works from any directory: <repo-root>/.github/workflows, and the first
#   mise config file listed under PARSE BOUNDARY. An explicitly passed
#   argument must resolve; `-` for <mise-toml> means "no task graph".
# Exit: 0 no eval task reachable from CI (or nothing to scan); 1 a violation
#   or a fail-closed condition, reported on stderr; 2 usage error.
#
# Portable POSIX sh + grep + sed + awk; bash 3.2 / BSD tooling. C locale pinned
# so the ERE character classes do not vary by host locale.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

say() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
usage_error() {
  warn "check-no-ci-evals: $1"
  warn "usage: check-no-ci-evals.sh [-h|--help] [<workflows-dir> [<mise-toml>|-]]"
  exit 2
}
fail_closed() {
  warn "check-no-ci-evals: $1"
  exit 1
}

repo_root="$(cd "$(dirname "$0")/.." && pwd)" || usage_error "cannot resolve this script's repository root"

dir=""
mise_toml=""
positional=0
for arg in "$@"; do
  case "$arg" in
    -h | --help)
      sed -e '1d' -e '/^[^#]/,$d' -e 's/^# \{0,1\}//' "$0"
      exit 0
      ;;
    --) break ;;
  esac
done
while [ $# -gt 0 ]; do
  case "$1" in
    --)
      shift
      break
      ;;
    -?*) usage_error "unknown option '$1'" ;;
    *) break ;;
  esac
done
for arg in "$@"; do
  positional=$((positional + 1))
  case "$positional" in
    1) dir="$arg" ;;
    2) mise_toml="$arg" ;;
    *) usage_error "too many arguments" ;;
  esac
  [ -n "$arg" ] || usage_error "argument $positional is empty"
done

if [ "$positional" -ge 1 ]; then
  [ -d "$dir" ] || usage_error "no workflow directory at '$dir'"
else
  dir="$repo_root/.github/workflows"
fi

if [ "$positional" -ge 2 ]; then
  if [ "$mise_toml" = "-" ]; then
    mise_toml=""
  elif [ ! -f "$mise_toml" ] || [ ! -r "$mise_toml" ]; then
    usage_error "no readable mise config at '$mise_toml'"
  fi
else
  for candidate in mise.toml .mise.toml mise/config.toml .mise/config.toml \
    .config/mise.toml .config/mise/config.toml; do
    if [ -f "$repo_root/$candidate" ]; then
      mise_toml="$repo_root/$candidate"
      break
    fi
  done
fi

# No workflow directory at all: nothing can wire an eval into CI. Vacuously
# clean (a repo may legitimately ship no workflows).
if [ ! -d "$dir" ]; then
  say "check-no-ci-evals: no workflow directory at '$dir'; nothing to scan."
  exit 0
fi
# A directory that exists but cannot be listed is not the same fact as one
# holding no workflows, and only the latter is a legitimate vacuous pass.
if [ ! -r "$dir" ] || [ ! -x "$dir" ]; then
  fail_closed "the workflow directory '$dir' cannot be listed, so its contents cannot be scanned."
fi

# Enumerate the workflow files into the positional parameters. A non-matching
# glob stays literal, so each candidate is existence-checked before use.
set --
for f in "$dir"/*.yml "$dir"/*.yaml; do
  [ -f "$f" ] || continue
  [ -r "$f" ] || fail_closed "the workflow file '$f' cannot be read, so it cannot be scanned."
  set -- "$@" "$f"
done

if [ "$#" -eq 0 ]; then
  say "check-no-ci-evals: no workflow files under '$dir'; nothing to scan."
  exit 0
fi

# ---- Pass 1: workflow text ----
#
# The mise-invocation alternative is matched in two stages so BOTH conditions
# hold on the line, in either order: the line invokes `mise` (at a TOKEN
# BOUNDARY, so a word merely ending in `mise` like `premise` does not trigger),
# and it carries an `eval:` at a TOKEN BOUNDARY (so the `eval` namespace
# triggers but a substring inside `retrieval:` / `medieval:` /
# `evaluate-release` does not).
#
# `-a` forces text handling: a NUL byte would otherwise make grep report the
# file as binary, print nothing, and exit 0 — a silent bypass of this pass.
# `--` ends the option list so a workflow directory whose name starts with `-`
# cannot turn a path into grep options. A grep exit above 1 is a read failure,
# never "no match", and fails closed.
# `-H` forces the filename prefix even for a single file (file:line:match).
mise_lines="$(grep -aHnE '(^|[^[:alnum:]_-])mise[[:space:]]' -- "$@")"
grep_rc=$?
[ "$grep_rc" -le 1 ] || fail_closed "grep failed (exit $grep_rc) while reading the workflow files under '$dir'."
mise_eval="$(printf '%s\n' "$mise_lines" | grep -aE '(^|[^[:alnum:]_-])eval:')"
grep_rc=$?
[ "$grep_rc" -le 1 ] || fail_closed "grep failed (exit $grep_rc) while matching the eval: namespace under '$dir'."
direct="$(grep -aHnE '(^|[^[:alnum:]_-])(prompt-eval|behavioral-eval)\.sh' -- "$@")"
grep_rc=$?
[ "$grep_rc" -le 1 ] || fail_closed "grep failed (exit $grep_rc) while matching the eval runners under '$dir'."
# A task name reaches CI without `mise` beside it whenever the invocation is
# parameterized: a matrix entry, a workflow input default, an action's `with:`
# value. Full-line comments are excluded here because prose about the
# namespace is common and the stage above already covers a commented-out
# invocation.
named_raw="$(grep -aHnE '(^|[^[:alnum:]_-])eval:' -- "$@")"
grep_rc=$?
[ "$grep_rc" -le 1 ] || fail_closed "grep failed (exit $grep_rc) while matching eval: task names under '$dir'."
named="$(printf '%s\n' "$named_raw" | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' || true)"
hits="$(printf '%s\n%s\n%s' "$mise_eval" "$direct" "$named" | grep -v '^[[:space:]]*$' | sort -u || true)"

if [ -n "$hits" ]; then
  warn "check-no-ci-evals: an eval task is wired into a CI workflow."
  warn "The kept eval harnesses (the eval: mise namespace — e.g. eval:skill, eval:behavioral)"
  warn "run on demand only, never in CI or 'mise run check'."
  warn "Offending references:"
  printf '%s\n' "$hits" | while IFS= read -r h; do
    [ -n "$h" ] && printf '  %s\n' "$h" >&2
  done
  exit 1
fi

# ---- Passes 2 and 3: task-graph closure and run bodies ----

if [ -z "$mise_toml" ]; then
  say "check-no-ci-evals: no eval task wired into any workflow under '$dir'."
  say "check-no-ci-evals: no mise config found under '$repo_root'; no task graph to close over."
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
  if (name == "" || index(line, name) == 0) return 0
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

# Every character outside a wildcard is escaped, so a crafted dependency
# pattern cannot inject regex syntax or a fatal expression.
function glob2ere(g,   i, c, out) {
  out = ""
  for (i = 1; i <= length(g); i++) {
    c = substr(g, i, 1)
    if (c == "*") out = out ".*"
    else if (c == "?") out = out "."
    else if (index("\\^$.|+()[]{}", c) > 0) out = out "\\" c
    else out = out c
  }
  return "^" out "$"
}
# A wildcard matches tasks this parse cannot see, so it is judged by what its
# pattern COULD name rather than by what it happens to match here: the literal
# text before its first wildcard. If that prefix and `eval:` still agree where
# the shorter of them ends, the pattern can name a task in the namespace and
# cannot be shown clear. `lint:*` diverges at the first character and is clear;
# `eval*`, `*:corpus` and the catch-all `*` are not.
function glob_reaches_eval(g,   i, c, p, ns, n) {
  p = ""
  for (i = 1; i <= length(g); i++) {
    c = substr(g, i, 1)
    if (c == "*" || c == "?" || c == "[") break
    p = p c
  }
  ns = "eval:"
  n = (length(p) < length(ns)) ? length(p) : length(ns)
  return (substr(p, 1, n) == substr(ns, 1, n))
}
function has_glob(g) { return (index(g, "*") > 0 || index(g, "?") > 0 || index(g, "[") > 0) }

# Walks one physical line of the config outside any multi-line string, tracking
# quote state so a `#`, `=` or bracket inside a string is not read as
# structure. Returns the line with any trailing comment removed, and reports
# the bracket-depth change, whether a string was left open, and where the
# first top-level `=` sits.
function scan(line,   i, c, q, esc, out, depth, eq) {
  q = ""; esc = 0; out = ""; depth = 0; eq = 0
  for (i = 1; i <= length(line); i++) {
    c = substr(line, i, 1)
    if (q == "\"") {
      if (esc) esc = 0
      else if (c == "\\") esc = 1
      else if (c == "\"") q = ""
    } else if (q == "'") {
      if (c == "'") q = ""
    } else if (c == "#") {
      break
    } else if (c == "\"" || c == "'") {
      q = c
    } else if (c == "[") {
      depth++
    } else if (c == "]") {
      depth--
    } else if (c == "=" && eq == 0 && depth == 0) {
      eq = i
    }
    out = out c
  }
  SCAN_TEXT = out
  SCAN_DELTA = depth
  SCAN_OPEN = (q != "")
  SCAN_EQ = eq
}

function addtask(name) {
  if (name == "") { bail("a [tasks...] header with no task name"); return }
  if (!(name in taskset)) { taskset[name] = 1; tasklist[++ntasks] = name }
  addname(name, name)
}
function addname(name, owner) {
  if (name == "" || (name in nameof)) return
  nameof[name] = owner
  namelist[++nnames] = name
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
function addflag(owner, why) {
  nflag[owner]++
  flagged[owner, nflag[owner]] = why
}

function unquote(s,   q) {
  q = substr(s, 1, 1)
  if ((q == "\"" || q == "'") && length(s) > 1 && substr(s, length(s), 1) == q)
    return substr(s, 2, length(s) - 2)
  return s
}
function trim(s) {
  sub(/^[[:space:]]+/, "", s)
  sub(/[[:space:]]+$/, "", s)
  return s
}

# Splits a dotted key into its segments, honoring quoted segments and the
# whitespace TOML allows around the dots, so `[tasks . build]` and
# `["tasks".build]` are read as the task definitions they are rather than
# skipped as unrecognized.
function key_seg(acc, qacc, qch) {
  if (qch == "") return trim(acc)
  # TOML has no way to write a key as part quoted and part bare, so reading
  # one would mean guessing which half names the task.
  if (trim(acc) != "") { bail("a table key mixing quoted and bare text is not modeled: " acc qacc); return "" }
  return (qch == "\"") ? decode_esc(qacc) : qacc
}
function split_key(s, parts,   i, c, q, acc, qacc, qch, esc, n) {
  n = 0; q = ""; acc = ""; qacc = ""; qch = ""; esc = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (q != "") {
      if (esc) { qacc = qacc c; esc = 0 }
      else if (q == "\"" && c == "\\") { qacc = qacc c; esc = 1 }
      else if (c == q) q = ""
      else qacc = qacc c
      continue
    }
    if (c == "\"" || c == "'") { q = c; qch = c; continue }
    if (c == ".") {
      parts[++n] = key_seg(acc, qacc, qch)
      acc = ""; qacc = ""; qch = ""
      continue
    }
    acc = acc c
  }
  if (q != "") { bail("unterminated quoted key segment: " s); return 0 }
  parts[++n] = key_seg(acc, qacc, qch)
  return n
}

function header(h,   inner, n) {
  cur = ""
  if (substr(h, 1, 2) == "[[") { bail("array-of-tables header not modeled: " h); return }
  if (substr(h, length(h), 1) != "]") { bail("unterminated table header: " h); return }
  inner = trim(substr(h, 2, length(h) - 2))
  n = split_key(inner, kparts)
  # kparts is reused across calls, so a refused split must not fall through to
  # the previous header's segments.
  if (n < 1 || kparts[1] != "tasks") return
  if (n == 1) { bail("inline [tasks] table not modeled"); return }
  if (n > 2) { bail("nested task table not modeled: " h); return }
  addtask(kparts[2])
  cur = kparts[2]
}

# The C locale makes awk byte-oriented, so a codepoint has to be spelled out
# as its UTF-8 bytes; emitting the raw number would produce a name that no
# longer matches the task the config names.
function utf8(n) {
  if (n < 128) return sprintf("%c", n)
  if (n < 2048) return sprintf("%c%c", 192 + int(n / 64), 128 + (n % 64))
  if (n < 65536)
    return sprintf("%c%c%c", 224 + int(n / 4096), 128 + int(n / 64) % 64, 128 + (n % 64))
  return sprintf("%c%c%c%c", 240 + int(n / 262144), 128 + int(n / 4096) % 64, \
    128 + int(n / 64) % 64, 128 + (n % 64))
}
function hex2dec(h,   i, v, d) {
  v = 0
  for (i = 1; i <= length(h); i++) {
    d = index("0123456789abcdef", tolower(substr(h, i, 1))) - 1
    if (d < 0) return -1
    v = v * 16 + d
  }
  return v
}
# TOML basic-string escapes are decoded before matching, so `eval:skill`
# cannot hide the namespace from a text match that mise itself would resolve.
# A single left-to-right walk, so a decoded backslash cannot be re-decoded.
function decode_esc(s,   i, c, n, out, h, w, v) {
  out = ""
  i = 1
  while (i <= length(s)) {
    c = substr(s, i, 1)
    if (c != "\\") { out = out c; i++; continue }
    n = substr(s, i + 1, 1)
    if (n == "u" || n == "U") {
      w = (n == "u") ? 4 : 8
      v = hex2dec(substr(s, i + 2, w))
      if (v < 1) { bail("an escape names no character: \\" n substr(s, i + 2, w)); return s }
      out = out utf8(v)
      i += 2 + w
    } else if (n == "n" || n == "t" || n == "r") {
      out = out " "
      i += 2
    } else if (n == "") {
      out = out c
      i++
    } else {
      out = out n
      i += 2
    }
  }
  return out
}

# Extracts every quoted string from a value buffer by walking it, so an escaped
# quote ends nothing: a regex that stopped at `\"` would take the next string's
# opening quote as its terminator and silently drop the rest of the array.
function each_string(buf, kind, owner,   i, c, q, esc, acc) {
  q = ""; esc = 0; acc = ""
  for (i = 1; i <= length(buf); i++) {
    c = substr(buf, i, 1)
    if (q == "") {
      # Only a delimiter opening at top level starts a multi-line string; the
      # same three characters inside a quoted literal are ordinary content.
      if ((c == "\"" || c == "'") && substr(buf, i, 3) == c c c) {
        bail("a multi-line string inside a " kind " value is not modeled")
        return
      }
      if (c == "\"" || c == "'") { q = c; acc = ""; esc = 0 }
      continue
    }
    if (esc) { acc = acc c; esc = 0; continue }
    if (q == "\"" && c == "\\") { acc = acc c; esc = 1; continue }
    if (c == q) {
      emit_string((q == "\"") ? decode_esc(acc) : acc, kind, owner)
      q = ""
      continue
    }
    acc = acc c
  }
  if (q != "") bail("unterminated string in a " kind " value")
}
function emit_string(s, kind, owner) {
  if (kind == "run") addrun(owner, s)
  else if (kind == "alias" || kind == "aliases") addname(s, owner)
  else adddep(owner, s, kind)
}
function finish_array() {
  each_string(arrbuf, arrkey, arrowner)
  arrkey = ""; arrbuf = ""; arrowner = ""; arrdepth = 0
}

FILENAME == misefile {
  raw = $0
  if (FNR == 1 && substr(raw, 1, 3) == sprintf("%c%c%c", 239, 187, 191))
    raw = substr(raw, 4)

  if (mldelim != "") {
    p = index(raw, mldelim)
    body = (p > 0) ? substr(raw, 1, p - 1) : raw
    if (mlkey == "run") addrun(mlowner, (mldelim == "\"\"\"") ? decode_esc(body) : body)
    if (p > 0) { mldelim = ""; mlkey = "" }
    next
  }

  scan(trim(raw))
  line = trim(SCAN_TEXT)

  if (arrkey != "") {
    arrbuf = arrbuf " " line
    arrdepth += SCAN_DELTA
    if (SCAN_OPEN) { bail("unterminated string inside a " arrkey " value"); next }
    if (arrdepth < 0) { bail("unbalanced brackets in a " arrkey " value"); next }
    if (arrdepth == 0) finish_array()
    next
  }

  if (line == "") next
  if (substr(line, 1, 1) == "[") { header(line); next }

  if (SCAN_EQ == 0) {
    bail(SCAN_OPEN ? "unterminated string: " line : "unrecognized line: " line)
    next
  }
  key = unquote(trim(substr(line, 1, SCAN_EQ - 1)))
  val = trim(substr(line, SCAN_EQ + 1))

  if (cur == "") {
    if (split_key(key, kparts) >= 1 && kparts[1] == "tasks")
      bail("a task defined outside a [tasks.<name>] table is not modeled: " line)
    next
  }

  d3 = substr(val, 1, 3)
  if (d3 == "'''" || d3 == "\"\"\"") {
    # A multi-line body under a key the closure reads would be silently
    # dropped, so refuse it; under any other key it is prose to skip past.
    if (key == "depends" || key == "depends_post" || key == "wait_for" \
      || key == "alias" || key == "aliases") {
      bail("a multi-line string is not modeled as a " key " value")
      next
    }
    rest = substr(val, 4)
    p = index(rest, d3)
    if (p > 0) rest = substr(rest, 1, p - 1)
    else { mldelim = d3; mlkey = key; mlowner = cur }
    if (key == "run") addrun(cur, (d3 == "\"\"\"") ? decode_esc(rest) : rest)
    next
  }
  if (SCAN_OPEN) { bail("unterminated string: " line); next }

  if (key != "depends" && key != "depends_post" && key != "wait_for" && key != "run" \
    && key != "alias" && key != "aliases") next

  if (substr(val, 1, 1) == "[") {
    arrkey = key; arrowner = cur; arrbuf = val; arrdepth = SCAN_DELTA
    if (arrdepth < 0) { bail("unbalanced brackets in a " key " value"); next }
    if (arrdepth == 0) finish_array()
    next
  }
  if (substr(val, 1, 1) == "\"" || substr(val, 1, 1) == "'") { each_string(val, key, cur); next }
  bail("unrecognized " key " value: " val)
  next
}

{
  wffiles[FILENAME] = 1
  l = $0
  sub(/^[[:space:]]+/, "", l)
  if (substr(l, 1, 1) == "#") next
  if (is_mise(l)) { wfline[++nwf] = $0; wfsrc[nwf] = FILENAME ":" FNR }
}

function chain(t,   path, u) {
  path = t
  u = parent[t]
  while (u != "") {
    path = u " -(" pkind[t] ")-> " path
    t = u
    u = parent[t]
  }
  return (rootsrc[t] == "" ? path : rootsrc[t] " invokes " path)
}
function push(v, from, kind) {
  if (v == "" || (v in seen)) return
  seen[v] = 1
  parent[v] = from
  pkind[v] = kind
  queue[++qn] = v
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
      if (has_glob(d)) {
        rx = glob2ere(d)
        for (k = 1; k <= nnames; k++)
          if (namelist[k] ~ rx) { addedge(u, nameof[namelist[k]], depkind[u, j]); matched = 1 }
        # A wildcard expands over every task mise knows, including the ones
        # defined outside this file, so what it CAN reach is the honest test.
        if (glob_reaches_eval(d))
          addflag(u, "has a wildcard dependency (" depkind[u, j] " = " d ") that can name the eval: namespace")
      } else if (d in nameof) {
        addedge(u, nameof[d], depkind[u, j])
        matched = 1
      }
      # A dependency resolving to no task in this file is outside the parse
      # boundary, so the closure will never walk it. Its name is then the only
      # thing left to read, and naming the eval: namespace is enough.
      if (!matched && !has_glob(d) && has_evalns(d))
        addflag(u, "depends on the eval: namespace (" depkind[u, j] " = " d ")")
    }
  }

  qn = 0
  nroots = 0
  for (i = 1; i <= nwf; i++)
    for (k = 1; k <= nnames; k++)
      if (!(nameof[namelist[k]] in seen) && tokmatch(wfline[i], namelist[k])) {
        nroots++
        rootsrc[nameof[namelist[k]]] = wfsrc[i]
        push(nameof[namelist[k]], "", "")
      }
  if (nroots == 0) {
    nfiles = 0
    for (f in wffiles) nfiles++
    print "no CI-invoked mise task found: none of the " nfiles " workflow file(s) scanned names a task from " misefile "."
    print "with zero roots the closure would pass vacuously over every task in the graph."
    exit 1
  }

  qi = 0
  while (qi < qn) {
    u = queue[++qi]
    if (u ~ /^eval:/)
      viol[++nviol] = "CI reaches eval task " u ": " chain(u)
    for (j = 1; j <= nflag[u]; j++)
      viol[++nviol] = "task " u " " flagged[u, j] ": " chain(u)
    for (j = 1; j <= nrun[u]; j++) {
      r = runbody[u, j]
      if ((is_mise(r) && has_evalns(r)) || is_runner(r))
        viol[++nviol] = "the run body of CI-invoked task " u " invokes an eval harness: " trim(r)
      if (!is_mise(r)) continue
      for (k = 1; k <= nnames; k++)
        if (tokmatch(r, namelist[k])) push(nameof[namelist[k]], u, "run body")
      # Shell operators end an operand as surely as whitespace does, so
      # `mise run lint:*;echo` must not read as one token `lint:*;echo`.
      nt = split(r, tok, /[[:space:];&|()<>]+/)
      for (k = 1; k <= nt; k++) {
        # The shell removes quoting and escapes before mise sees the operand,
        # so the guard must read what mise gets, not what the body spells.
        g = tok[k]
        gsub(/["'`\\]/, "", g)
        # A bracket expression matches one character, same as `?`, and reducing
        # it keeps the operand within the shape the filter below recognizes.
        gsub(/\[[^]]*\]/, "?", g)
        # A bare `*` is far more likely `rm -rf *` than a task selector, and
        # anything carrying other shell syntax is not a task name at all.
        if (g ~ /^[*?]+$/) continue
        # A wildcard with nothing before it and no namespace separator is a
        # shell glob argument — `mise run lint *.sh` — not a task selector.
        if (g ~ /^[*?]/ && index(g, ":") == 0) continue
        if (g !~ /^[[:alnum:]_.:*?-]*[*?][[:alnum:]_.:*?-]*$/) continue
        if (glob_reaches_eval(g))
          viol[++nviol] = "the run body of CI-invoked task " u " invokes the eval: namespace by wildcard (" g "): " chain(u)
        rx = glob2ere(g)
        for (k2 = 1; k2 <= nnames; k2++)
          if (namelist[k2] ~ rx) push(nameof[namelist[k2]], u, "run body")
      }
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

[ -n "$graph_awk" ] || fail_closed "the task-graph parser could not be assembled, so passes 2 and 3 could not run."

graph_out="$(awk -v misefile="$mise_toml" "$graph_awk" "$mise_toml" "$@")"
graph_rc=$?

if [ "$graph_rc" -gt 1 ]; then
  fail_closed "the task-graph parser failed (awk exit $graph_rc) on '$mise_toml'; passes 2 and 3 did not complete."
fi
if [ "$graph_rc" -eq 1 ]; then
  [ -n "$graph_out" ] || fail_closed "the task-graph parser reported a failure without a verdict on '$mise_toml'."
  warn "check-no-ci-evals: $(printf '%s' "$graph_out" | sed -n '1p')"
  printf '%s\n' "$graph_out" | sed -e '1d' | while IFS= read -r l; do
    [ -n "$l" ] && printf '%s\n' "$l" >&2
  done
  exit 1
fi

say "check-no-ci-evals: no eval task wired into any workflow under '$dir'."
say "check-no-ci-evals: no CI-invoked task in '$mise_toml' reaches the eval: namespace."
exit 0
