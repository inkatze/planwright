#!/bin/bash
# Asserts that the resolved `lint:md` target set covers templates/**/*.md.
#
# The glob lives in one string inside mise.toml, so narrowing it is a
# one-token edit nothing else would notice: the task would still be green,
# just linting less. This resolves the task's own globs against the tracked
# tree and asserts a templates path survives, then proves the assertion is
# sensitive by running it against narrowed fixtures that must come back red.
#
# Resolution is `git ls-files` over the tracked tree rather than
# markdownlint's own globby pass. The two agree on which tracked prose the
# globs reach, which is the property under assertion; untracked files are out
# of scope for a repo guard either way.
set -u
unset CDPATH

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
# printing an empty list when the task, its run line, or its quoting cannot be
# read: an unresolvable glob set must not read as a covered one.
lint_md_args() {
  awk '
    /^\[tasks\./ { in_task = ($0 == "[tasks.\"lint:md\"]"); next }
    in_task && /^run *=/ {
      line = $0
      sub(/^run *= */, "", line)
      q = substr(line, 1, 1)
      if (q != "\"" && q != "'"'"'") { print "unquoted run value" > "/dev/stderr"; exit 2 }
      if (length(line) < 2 || substr(line, length(line), 1) != q) {
        print "unterminated run value" > "/dev/stderr"; exit 2
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
      if (inq) { print "unterminated glob quote" > "/dev/stderr"; exit 2 }
      if (tok != "") { if (count++ > 0) print tok }
      if (count < 2) { print "lint:md run line takes no arguments" > "/dev/stderr"; exit 2 }
      found = 1
      exit 0
    }
    END { if (!found) { print "no lint:md run line" > "/dev/stderr"; exit 2 } }
  ' "$1"
}

# lint_md_targets <mise.toml> — the tracked files the argument globs resolve
# to, with the negated globs subtracted. Exit 2 when the set is empty: a glob
# list that reaches nothing is a broken enumeration, not a clean scope.
lint_md_targets() {
  local args include exclude arg resolved
  args="$(lint_md_args "$1")" || return 2
  include=""
  exclude=""
  while IFS= read -r arg; do
    [ -n "$arg" ] || continue
    case "$arg" in
      !*) exclude="$exclude ${arg#!}" ;;
      *) include="$include $arg" ;;
    esac
  done <<EOF
$args
EOF
  [ -n "$include" ] || return 2
  # shellcheck disable=SC2086 # the globs are pathspecs, meant to word-split
  resolved="$(cd "$REPO_ROOT" && git ls-files -- $include | sort -u)" || return 2
  if [ -n "$exclude" ]; then
    # shellcheck disable=SC2086 # same: one pathspec per word
    resolved="$(comm -23 \
      <(printf '%s\n' "$resolved") \
      <(cd "$REPO_ROOT" && git ls-files -- $exclude | sort -u))" || return 2
  fi
  [ -n "$resolved" ] || return 2
  printf '%s\n' "$resolved"
}

# templates_covered <mise.toml> — 0 when the resolved set holds at least one
# markdown file under templates/, 1 when it does not, 2 when the set could not
# be resolved at all.
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
# the templates glob dropped from lint:md and an optional replacement put in
# its place, standing in for a future edit that narrows the scope.
narrowed_copy() {
  sed "/^run = \"markdownlint-cli2 /{
    s|'templates/\*\*/\*\.md' ||
    s|markdownlint-cli2 |markdownlint-cli2 $2|
  }" "$REPO_ROOT/mise.toml" >"$1"
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
# 2. Sensitivity: dropping the templates glob turns the assertion above red.
#    Without this the assertion could be green for reasons unrelated to the
#    scope it claims to pin.
# ---------------------------------------------------------------------------
narrowed_copy "$tmp/dropped.toml" ""
rc=0
templates_covered "$tmp/dropped.toml" || rc=$?
if [ "$rc" -eq 1 ]; then
  pass "dropping the templates glob fails the assertion"
else
  fail "the assertion survived a lint:md glob with no templates pattern (rc $rc)"
fi

# ---------------------------------------------------------------------------
# 3. Sensitivity, second shape: a templates glob still present in the command
#    but matching no tracked file. A pattern-text check would pass here.
# ---------------------------------------------------------------------------
narrowed_copy "$tmp/mismatched.toml" "'templates/**/*.markdown' "
rc=0
templates_covered "$tmp/mismatched.toml" || rc=$?
if [ "$rc" -eq 1 ]; then
  pass "a templates glob matching no tracked file fails the assertion"
else
  fail "a non-matching templates glob was read as coverage (rc $rc)"
fi

# ---------------------------------------------------------------------------
# 4. The negated globs are subtracted, so the resolved set is what
#    markdownlint actually lints rather than the union of the positives.
# ---------------------------------------------------------------------------
rc=0
targets="$(lint_md_targets "$REPO_ROOT/mise.toml")" || rc=$?
if [ "$rc" -ne 0 ]; then
  fail "could not resolve the shipped lint:md target set (rc $rc)"
elif printf '%s\n' "$targets" | grep -q '^specs/_observations/'; then
  fail "the resolved set kept a negated specs/_observations path"
else
  pass "the resolved set honors the negated globs"
fi

# ---------------------------------------------------------------------------
# 5. Fail closed: a mise.toml with no lint:md task is an error, not a set of
#    zero targets that vacuously excludes templates.
# ---------------------------------------------------------------------------
grep -v '^\[tasks\."lint:md"\]' "$REPO_ROOT/mise.toml" >"$tmp/no-task.toml"
rc=0
lint_md_targets "$tmp/no-task.toml" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "a missing lint:md task fails closed"
else
  fail "a missing lint:md task did not fail closed (rc $rc)"
fi

# ---------------------------------------------------------------------------
# 6. Fail closed: a lint:md whose globs resolve to nothing at all.
# ---------------------------------------------------------------------------
sed "s|^run = \"markdownlint-cli2 .*\"$|run = \"markdownlint-cli2 'no-such-dir/**/*.md'\"|" \
  "$REPO_ROOT/mise.toml" >"$tmp/empty.toml"
rc=0
lint_md_targets "$tmp/empty.toml" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "a glob set resolving to zero files fails closed"
else
  fail "a zero-file glob set did not fail closed (rc $rc)"
fi

# ---------------------------------------------------------------------------
# 7. Fail closed: an unparseable run line (unbalanced quoting) is an error
#    rather than a silently truncated argument list.
# ---------------------------------------------------------------------------
sed "s|^run = \"markdownlint-cli2 .*\"$|run = \"markdownlint-cli2 'templates/**/*.md\"|" \
  "$REPO_ROOT/mise.toml" >"$tmp/unquoted.toml"
rc=0
lint_md_targets "$tmp/unquoted.toml" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "an unterminated glob quote fails closed"
else
  fail "an unterminated glob quote did not fail closed (rc $rc)"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all lint-md-scope tests passed"
