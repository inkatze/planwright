#!/bin/bash
# Asserts that the resolved `lint:md` target set covers templates/**/*.md
# (guard-coverage Task 10; REQ-G1.1, REQ-H1.3; D-11).
#
# The glob list lives in one string inside mise.toml, so narrowing it is a
# one-token edit nothing else would notice: the task stays green while linting
# less. This resolves the task's own globs and asserts a template path
# survives, then proves the assertion is sensitive by re-running it against
# copies of mise.toml whose scope has been narrowed.
#
# Resolution matches globby, the matcher markdownlint-cli2 actually uses: `*`
# does not cross a directory separator, `**` does. Resolving with `git ls-files`
# pathspecs instead would be wrong in the permissive direction, because git's
# `*` crosses `/` — `templates/*.md` would resolve to the two nested template
# READMEs that markdownlint does not lint, and the narrowing this file exists
# to catch would read as coverage. The tracked file list still comes from git;
# it is only the matching semantics that must be globby's.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

# git exports these during rebase --exec, filter-branch, and inside hooks, and
# either one silently repoints `git ls-files` at another index. This is the one
# test in the suite that resolves against the real repo index, so it clears
# them rather than inheriting whatever invoked it.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

failures=0
pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# lint_md_args <mise.toml> — the `lint:md` run line's arguments, one per line,
# with the markdownlint-cli2 invocation itself dropped. Exits 2 rather than
# printing a short list when the task, its run line, or its quoting cannot be
# read: an unresolvable glob set must never read as a covered one.
lint_md_args() {
  awk '
    /^\[/ { in_task = ($0 == "[tasks.\"lint:md\"]"); next }
    in_task && /^[ \t]*run[ \t]*=/ && !done {
      line = $0
      sub(/^[ \t]*run[ \t]*=[ \t]*/, "", line)
      sub(/[ \t]+$/, "", line)
      q = substr(line, 1, 1)
      if (q != "\"" && q != "'"'"'") { print "unquoted run value" > "/dev/stderr"; bad = 1; exit 2 }
      if (length(line) < 2 || substr(line, length(line), 1) != q) {
        print "unterminated run value" > "/dev/stderr"; bad = 1; exit 2
      }
      line = substr(line, 2, length(line) - 2)
      n = length(line); tok = ""; inq = 0; count = 0
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (inq) { if (c == "'"'"'") inq = 0; else tok = tok c }
        else if (c == "'"'"'") inq = 1
        else if (c == " " || c == "\t") { if (tok != "") { if (count++ > 0) print tok; tok = "" } }
        else tok = tok c
      }
      if (inq) { print "unterminated glob quote" > "/dev/stderr"; bad = 1; exit 2 }
      if (tok != "") { if (count++ > 0) print tok }
      if (count < 2) { print "lint:md run line takes no arguments" > "/dev/stderr"; bad = 1; exit 2 }
      done = 1
      exit 0
    }
    END { if (!done && !bad) { print "no lint:md run line" > "/dev/stderr"; exit 2 } }
  ' "$1"
}

# lint_md_targets <mise.toml> — the tracked files the argument globs resolve to
# under globby semantics, with the negated globs subtracted. Exit 2 when the
# set is empty or a glob cannot be honoured: either is a broken enumeration,
# not a clean scope.
lint_md_targets() {
  local args
  args="$(lint_md_args "$1")" || return 2
  printf '%s\n' "$args" >"$tmp/globs" || return 2
  # git pathspec magic (`:(glob)`, `:!`) is meaningful to git and meaningless
  # to markdownlint, so a glob carrying it lints nothing while resolving fine.
  # Refuse it rather than resolve it.
  if grep -q '^:' "$tmp/globs"; then
    echo "glob carries git pathspec magic, which markdownlint cannot honour" >&2
    return 2
  fi
  # Character classes and brace expansion are globby features this matcher does
  # not implement. Refusing is honest; translating them to literals would make
  # the resolver quietly disagree with markdownlint, which is the failure this
  # whole file exists to prevent.
  if grep -q '[][{}]' "$tmp/globs"; then
    echo "glob uses a character class or brace expansion, which this matcher does not implement" >&2
    return 2
  fi
  match_globs "$tmp/globs"
}

# match_globs <globfile> — the tracked paths the globs in <globfile> resolve to
# under globby semantics. Exit 2 on an unusable tracked list or an empty result.
match_globs() {
  local resolved
  # core.quotePath=false keeps git from C-quoting non-ASCII paths, which would
  # otherwise reach the matcher as an escaped string that no glob matches.
  (cd "$REPO_ROOT" && git -c core.quotePath=false ls-files) >"$tmp/tracked" || return 2
  [ -s "$tmp/tracked" ] || return 2
  resolved="$(awk -v globfile="$1" -v listfile="$tmp/tracked" '
    # Translate one globby pattern to an anchored ERE. `**/` spans directories,
    # `**` spans anything, a lone `*` stops at the separator.
    function glob2re(g,   out, i, n, c) {
      out = "^"; n = length(g); i = 1
      while (i <= n) {
        c = substr(g, i, 1)
        if (c == "*") {
          if (substr(g, i + 1, 1) == "*") {
            if (substr(g, i + 2, 1) == "/") { out = out "(.*/)?"; i += 3 }
            else { out = out ".*"; i += 2 }
          } else { out = out "[^/]*"; i += 1 }
        } else if (c == "?") { out = out "[^/]"; i += 1 }
        else if (index(".^$+(){}[]|\\", c) > 0) { out = out "\\" c; i += 1 }
        else { out = out c; i += 1 }
        }
      return out "$"
    }
    BEGIN {
      ni = 0; ne = 0
      while ((getline g < globfile) > 0) {
        if (g == "") continue
        if (substr(g, 1, 1) == "!") { exre[++ne] = glob2re(substr(g, 2)) }
        else { inre[++ni] = glob2re(g) }
      }
      if (ni == 0) exit 3
      while ((getline p < listfile) > 0) {
        keep = 0
        for (i = 1; i <= ni; i++) if (p ~ inre[i]) { keep = 1; break }
        if (!keep) continue
        for (i = 1; i <= ne; i++) if (p ~ exre[i]) { keep = 0; break }
        if (keep) print p
      }
    }
  ')" || return 2
  [ -n "$resolved" ] || return 2
  printf '%s\n' "$resolved"
}

# templates_covered <mise.toml> — 0 when the resolved set holds a markdown file
# under templates/, 1 when it does not, 2 when the set could not be resolved.
templates_covered() {
  local targets line
  targets="$(lint_md_targets "$1")" || return 2
  while IFS= read -r line; do
    case "$line" in
      templates/*.md) return 0 ;;
    esac
  done <<EOF
$targets
EOF
  return 1
}

# narrowed_copy <destination> <replacement-glob> — the shipped mise.toml with
# the templates glob dropped from the lint:md run line and an optional
# replacement in its place. Hard-fails when the edit changes nothing: a sed
# that silently no-ops would leave the sensitivity cases below asserting
# against an unmodified file and reporting a coverage regression that is really
# a stale fixture.
narrowed_copy() {
  sed "/^run = \"markdownlint-cli2 /{
    s|'templates/\*\*/\*\.md' ||
    s|markdownlint-cli2 |markdownlint-cli2 $2|
  }" "$REPO_ROOT/mise.toml" >"$1" || exit 1
  if cmp -s "$1" "$REPO_ROOT/mise.toml"; then
    echo "FAIL: narrowed_copy did not change mise.toml — the fixture no longer matches the run line" >&2
    failures=$((failures + 1))
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 1. The shipped glob reaches the template prose.
# ---------------------------------------------------------------------------
rc=0
templates_covered "$REPO_ROOT/mise.toml" || rc=$?
if [ "$rc" -eq 0 ]; then
  pass "lint:md's resolved target set includes templates/**/*.md"
else
  fail "lint:md's resolved target set does not reach templates/ (rc $rc)"
fi

# ---------------------------------------------------------------------------
# 2. The resolver agrees with markdownlint itself on how many files the shipped
#    globs reach. This is what keeps the assertion honest: a resolver that
#    drifts from the real matcher can be green about a scope that is not the
#    scope being linted.
# ---------------------------------------------------------------------------
cross_check() {
  cc_glob="$1"
  printf '%s\n' "$cc_glob" >"$tmp/one-glob"
  cc_ours="$(match_globs "$tmp/one-glob" | grep -c .)" || cc_ours=0
  # markdownlint's own count, from markdownlint. Its exit status reports rule
  # violations, which is not what is being compared here.
  cc_theirs="$(cd "$REPO_ROOT" && markdownlint-cli2 "$cc_glob" 2>&1 \
    | sed -n 's/^Linting: \([0-9]*\) file(s)$/\1/p')"
  if [ -z "$cc_theirs" ]; then
    fail "markdownlint-cli2 reported no file count for '$cc_glob'"
  elif [ "$cc_ours" = "$cc_theirs" ]; then
    pass "resolver and markdownlint agree on '$cc_glob' ($cc_ours files)"
  else
    fail "for '$cc_glob' the resolver says $cc_ours files, markdownlint lints $cc_theirs"
  fi
}

if command -v markdownlint-cli2 >/dev/null 2>&1; then
  # The two spellings whose difference is the whole point: `**` spans
  # directories and `*` does not. Cross-checking the full glob set instead
  # would lint every tracked markdown file on every test run, which is a cost
  # the suite carries forever for no extra signal.
  cross_check 'templates/**/*.md'
  cross_check 'templates/*.md'
else
  pass "markdownlint-cli2 not on PATH; the cross-check is skipped"
fi

# ---------------------------------------------------------------------------
# 3. Sensitivity: dropping the templates glob turns the assertion red.
# ---------------------------------------------------------------------------
if narrowed_copy "$tmp/dropped.toml" ""; then
  rc=0
  templates_covered "$tmp/dropped.toml" || rc=$?
  if [ "$rc" -eq 1 ]; then
    pass "dropping the templates glob fails the assertion"
  else
    fail "the assertion survived a lint:md glob with no templates pattern (rc $rc)"
  fi
fi

# ---------------------------------------------------------------------------
# 4. Sensitivity, the narrowing that matters most: `templates/*.md` still names
#    templates and still looks like coverage, but globby's `*` stops at the
#    separator, so markdownlint lints zero template files. Confirmed directly:
#    `markdownlint-cli2 'templates/*.md'` reports "Linting: 0 file(s)".
#    A git-pathspec resolver reads this as covered, which is the false green
#    this case exists to prevent.
# ---------------------------------------------------------------------------
if narrowed_copy "$tmp/shallow.toml" "'templates/*.md' "; then
  rc=0
  templates_covered "$tmp/shallow.toml" || rc=$?
  if [ "$rc" -eq 1 ]; then
    pass "narrowing templates/**/*.md to templates/*.md fails the assertion"
  else
    fail "a single-star templates glob was read as coverage (rc $rc)"
  fi
fi

# ---------------------------------------------------------------------------
# 5. Sensitivity: a templates glob present but matching no tracked file.
# ---------------------------------------------------------------------------
if narrowed_copy "$tmp/mismatched.toml" "'templates/**/*.markdown' "; then
  rc=0
  templates_covered "$tmp/mismatched.toml" || rc=$?
  if [ "$rc" -eq 1 ]; then
    pass "a templates glob matching no tracked file fails the assertion"
  else
    fail "a non-matching templates glob was read as coverage (rc $rc)"
  fi
fi

# ---------------------------------------------------------------------------
# 6. The negated globs are subtracted and the positives survive. The positive
#    control matters: a resolver that dropped everything would satisfy the
#    negation check on its own.
# ---------------------------------------------------------------------------
rc=0
targets="$(lint_md_targets "$REPO_ROOT/mise.toml")" || rc=$?
if [ "$rc" -ne 0 ]; then
  fail "could not resolve the shipped lint:md target set (rc $rc)"
else
  if printf '%s\n' "$targets" | grep -q '^specs/_observations/'; then
    fail "the resolved set kept a negated specs/_observations path"
  else
    pass "the resolved set honors the negated globs"
  fi
  if printf '%s\n' "$targets" | grep -qx 'README.md'; then
    pass "the resolved set keeps the root README the globs name"
  else
    fail "the resolved set lost README.md, so the subtraction is over-broad"
  fi
  if printf '%s\n' "$targets" | grep -q '^doctrine/'; then
    pass "the resolved set keeps the doctrine prose"
  else
    fail "the resolved set lost doctrine/*.md"
  fi
fi

# ---------------------------------------------------------------------------
# 7. Fail-closed (REQ-H1.3). Each case pins its own diagnostic, so a fixture
#    that fails for an unrelated reason cannot be mistaken for the case under
#    test — all of these would otherwise be indistinguishable exit 2s.
# ---------------------------------------------------------------------------
assert_closed() {
  ac_label="$1"
  ac_file="$2"
  ac_marker="$3"
  ac_err="$tmp/err.txt"
  ac_rc=0
  lint_md_targets "$ac_file" >/dev/null 2>"$ac_err" || ac_rc=$?
  if [ "$ac_rc" -ne 2 ]; then
    fail "$ac_label did not fail closed (rc $ac_rc)"
    return
  fi
  case "$(cat "$ac_err")" in
    *"$ac_marker"*) pass "$ac_label fails closed" ;;
    *) fail "$ac_label failed closed with the wrong diagnostic: $(cat "$ac_err")" ;;
  esac
}

grep -v '^\[tasks\."lint:md"\]' "$REPO_ROOT/mise.toml" >"$tmp/no-task.toml" || exit 1
assert_closed "a missing lint:md task" "$tmp/no-task.toml" "no lint:md run line"

sed "s|^run = \"markdownlint-cli2 .*\"$|run = \"markdownlint-cli2 'templates/**/*.md\"|" \
  "$REPO_ROOT/mise.toml" >"$tmp/unquoted.toml" || exit 1
assert_closed "an unterminated glob quote" "$tmp/unquoted.toml" "unterminated glob quote"

sed "s|^run = \"markdownlint-cli2 .*\"$|run = \"markdownlint-cli2\"|" \
  "$REPO_ROOT/mise.toml" >"$tmp/noargs.toml" || exit 1
assert_closed "a run line with no globs" "$tmp/noargs.toml" "takes no arguments"

sed "s|^run = \"markdownlint-cli2 .*\"$|run = \"markdownlint-cli2 ':(glob)templates/**/*.md'\"|" \
  "$REPO_ROOT/mise.toml" >"$tmp/magic.toml" || exit 1
assert_closed "a glob carrying git pathspec magic" "$tmp/magic.toml" "pathspec magic"

sed "s|^run = \"markdownlint-cli2 .*\"$|run = \"markdownlint-cli2 'templates/**/*.{md,markdown}'\"|" \
  "$REPO_ROOT/mise.toml" >"$tmp/braces.toml" || exit 1
assert_closed "a glob using brace expansion" "$tmp/braces.toml" "does not implement"

# A glob set that resolves to nothing has no diagnostic of its own; it is the
# emptiness itself that must be refused rather than reported as a clean scope.
sed "s|^run = \"markdownlint-cli2 .*\"$|run = \"markdownlint-cli2 'no-such-dir/**/*.md'\"|" \
  "$REPO_ROOT/mise.toml" >"$tmp/empty.toml" || exit 1
rc=0
lint_md_targets "$tmp/empty.toml" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "a glob set resolving to zero files fails closed"
else
  fail "a zero-file glob set did not fail closed (rc $rc)"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all lint-md-scope tests passed"
