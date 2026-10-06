#!/bin/bash
# Tests for scripts/check-launch-shape.sh — the launch-shape prose guard
# (fleet-hardening Task 14; REQ-H1.5, D-10).
#
# The tmux rung launches its worker in a detached session it creates itself;
# the native `--worktree` launcher (with or without `--tmux=classic`) survives
# only as an operator's hand-launch. The guard fails on prose that names the
# old shape without labeling it so, and passes once it carries the label.
#
# shellcheck disable=SC2016 # fixture bodies are literal prose with backticks.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-launch-shape.sh"

failures=0
assert() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}

assert_contains() {
  case "$2" in
    *"$3"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (output did not mention '$3'): $2" >&2
      failures=$((failures + 1))
      ;;
  esac
}

if [ ! -f "$CHECKER" ]; then
  echo "FAIL: checker script missing at $CHECKER" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# fixture_root <name> — set r to a fresh root holding one clean file in every
# scanned directory, so a case adds only the line it is about. It sets r
# rather than printing it: inside a command substitution its exit would only
# empty r, and the case would then write under `/`.
fixture_root() {
  r="$tmp/$1"
  for d in docs doctrine skills/x scripts config; do
    mkdir -p "$r/$d" || exit 1
    printf '%s\n' 'Nothing about launches here.' >"$r/$d/clean.md" || exit 1
  done
  printf '%s\n' '# readme' >"$r/README.md" || exit 1
}

# write_file <path> <line>... — verbatim.
write_file() {
  wf_path="$1"
  shift
  mkdir -p "$(dirname "$wf_path")" || exit 1
  printf '%s\n' "$@" >"$wf_path"
}

run() {
  out=$(/bin/sh "$CHECKER" "$@" 2>&1)
  code=$?
}

# --- REQ-H1.5: either old form presented as the rung's launch fails ----------
fixture_root tmux-form
write_file "$r/docs/fleet.md" 'Intro.' '' \
  'The tmux rung launches its worker with' \
  '`claude --worktree <suffix> --tmux=classic`, switching your client.'
run --root "$r"
assert "the --tmux=classic form presented as the rung's launch fails" 1 "$code"
assert_contains "the failure names the file and line" "$out" "docs/fleet.md:4"

fixture_root bare-form
write_file "$r/skills/x/SKILL.md" \
  'Dispatch places the worktree and runs `claude --worktree <suffix>` in tmux.'
run --root "$r"
assert "the bare claude --worktree form presented as the rung's launch fails" 1 "$code"

fixture_root flag-alone
write_file "$r/doctrine/backend.md" 'The worker pane is opened with --tmux=classic.'
run --root "$r"
assert "--tmux=classic named alone fails" 1 "$code"

fixture_root spaced
write_file "$r/config/x.json" '{"_about": "launches claude   --worktree x"}'
run --root "$r"
assert "extra spacing between claude and --worktree is still caught" 1 "$code"

fixture_root wrapped
write_file "$r/skills/x/SKILL.md" '- **tmux**. An interactive worker in a named window via `claude' \
  '  --worktree`. Observe it with capture-pane.'
run --root "$r"
assert "a mention wrapped across a line break is still caught" 1 "$code"
assert_contains "the wrapped mention is reported at its first line" "$out" "skills/x/SKILL.md:1"

fixture_root wrapped-comment
write_file "$r/scripts/s.sh" '# the worker launches via claude' '#   --worktree x'
run --root "$r"
assert "a mention wrapped across comment lines is still caught" 1 "$code"

fixture_root wrapped-continuation
# shellcheck disable=SC1003 # a literal trailing backslash, not an escape
write_file "$r/scripts/s.sh" 'exec claude \' '  --worktree "$x"'
run --root "$r"
assert "a mention split by a shell continuation is still caught" 1 "$code"

fixture_root wrapped-quote
write_file "$r/docs/q.md" '> the rung runs `claude' '> --worktree x`'
run --root "$r"
assert "a mention wrapped inside a block quote is still caught" 1 "$code"

fixture_root flags-between
write_file "$r/docs/f.md" 'Workers start via `claude --model opus --effort high --worktree x`.'
run --root "$r"
assert "flags between the launcher and --worktree do not hide the mention" 1 "$code"

fixture_root short-flag
write_file "$r/docs/f.md" 'Workers start via `claude -w x`.'
run --root "$r"
assert "the worktree flag's short form is caught" 1 "$code"

fixture_root wrapped-backtick
write_file "$r/docs/w.md" 'Workers start via `claude`' '`--worktree x`.'
run --root "$r"
assert "a mention wrapped between two code spans is still caught" 1 "$code"

fixture_root wrapped-flags
write_file "$r/docs/w.md" 'Workers start via claude' '--model opus --worktree x.'
run --root "$r"
assert "a wrap whose next line leads with other flags is still caught" 1 "$code"

fixture_root tmux-single-quoted
write_file "$r/docs/t.md" "The pane is opened with --tmux='classic'."
run --root "$r"
assert "a single-quoted classic value is caught" 1 "$code"

fixture_root tmux-spaced
write_file "$r/docs/t.md" 'The pane is opened with --tmux classic.'
run --root "$r"
assert "--tmux classic with a space is caught" 1 "$code"

fixture_root tmux-quoted
write_file "$r/docs/t.md" 'The pane is opened with --tmux="classic".'
run --root "$r"
assert "a quoted classic value is caught" 1 "$code"

fixture_root crlf
printf 'Workers start via claude\r\n--worktree x.\r\n' >"$r/docs/c.md"
run --root "$r"
assert "a CRLF file's wrapped mention is still caught" 1 "$code"

fixture_root crlf-blank
printf 'This is a hand-launch.\r\n\r\nWorkers start via `claude --worktree x`.\r\n' >"$r/docs/c.md"
run --root "$r"
assert "a CRLF blank line still ends the label's reach" 1 "$code"

# --- the hand-launch label passes --------------------------------------------
fixture_root labeled
write_file "$r/docs/conventions.md" \
  'An operator can still re-enter a worktree by hand-launch:' \
  '`claude --worktree <suffix>` (with or without `--tmux=classic`).'
run --root "$r"
assert "an old-shape mention labeled a hand-launch passes" 0 "$code"

fixture_root labeled-script
write_file "$r/scripts/flight.sh" \
  '# The print rung prints an operator hand-launch command.' \
  'set -- claude --worktree "$suffix"'
run --root "$r"
assert "a script line under a hand-launch comment passes" 0 "$code"

fixture_root prior
write_file "$r/scripts/w.sh" \
  '# Probe the name the prior launcher (`claude --worktree`) gave its session.'
run --root "$r"
assert "a mention naming the prior launcher passes" 0 "$code"

# The label must sit near the mention: a blank line ends its reach, and so does
# distance inside one long paragraph.
fixture_root far-blank
write_file "$r/docs/a.md" 'This is a hand-launch.' '' 'Workers start via `claude --worktree x`.'
run --root "$r"
assert "a label across a blank line does not cover the mention" 1 "$code"

fixture_root far-lines
write_file "$r/docs/a.md" 'This is a hand-launch.' 'one' 'two' 'three' 'four' \
  'Workers start via `claude --worktree x`.'
run --root "$r"
assert "a label several lines away does not cover the mention" 1 "$code"

fixture_root window-edge
write_file "$r/docs/a.md" 'This is a hand-launch.' 'one' 'Workers start via `claude --worktree x`.'
write_file "$r/config/s.json" '{"_about": "A hand-launch exists. One. The rung runs claude --worktree x."}'
run --root "$r"
assert "a label two lines or two sentences away covers the mention" 0 "$code"

fixture_root window-past-edge
write_file "$r/docs/a.md" 'This is a hand-launch.' 'one' 'two' 'Workers start via `claude --worktree x`.'
run --root "$r"
assert "a label three lines away does not cover the mention" 1 "$code"

fixture_root window-past-edge-sentence
write_file "$r/config/s.json" '{"_about": "A hand-launch exists. One. Two. The rung runs claude --worktree x."}'
run --root "$r"
assert "a label three sentences away does not cover the mention" 1 "$code"

fixture_root label-forms
write_file "$r/docs/a.md" 'Hand-launch: `claude --worktree x`.' '' 'A hand launch: `claude --worktree y`.'
run --root "$r"
assert "a capitalized label and the spaced spelling both count" 0 "$code"

fixture_root label-substring
write_file "$r/docs/a.md" 'Set up beforehand launch the rung with `claude --worktree x`.'
run --root "$r"
assert "a label must be its own word, not the tail of another" 1 "$code"

fixture_root comment-break
write_file "$r/scripts/s.sh" '# This is a hand-launch.' '#' '# The rung runs claude --worktree x.'
run --root "$r"
assert "a bare comment leader ends the label's paragraph" 1 "$code"

fixture_root file-boundary
write_file "$r/docs/a.md" 'This is a hand-launch.'
write_file "$r/docs/b.md" 'Workers start via `claude --worktree x`.'
run --root "$r"
assert "a label in one file never covers a mention in the next" 1 "$code"

fixture_root far-sentence
write_file "$r/config/s.json" \
  '{"_about": "A hand-launch exists. One. Two. Three. Four. The rung runs claude --worktree x."}'
run --root "$r"
assert "a label several sentences away on one long line does not cover it" 1 "$code"

# --- scope: README files are in, specs/, tests/ and the changelog are out -----
fixture_root readme
write_file "$r/templates/t/README.md" 'Run `claude --worktree x --tmux=classic` to dispatch.'
run --root "$r"
assert "a nested README presenting the old shape fails" 1 "$code"

fixture_root excluded
write_file "$r/specs/s/design.md" 'The rung ran `claude --worktree x --tmux=classic`.'
write_file "$r/tests/test-x.sh" '# negative case: claude --worktree x --tmux=classic'
write_file "$r/CHANGELOG.md" '- launches via `claude --worktree x`'
write_file "$r/docs/CHANGELOG.md" '- launches via `claude --worktree x`'
write_file "$r/templates/t/notes.md" 'Run `claude --worktree x` to dispatch.'
write_file "$r/docs/.vuepress/notes.md" 'Run `claude --worktree x` to dispatch.'
run --root "$r"
assert "specs/, tests/, changelogs and non-README files elsewhere are out of scope" 0 "$code"

# --- fail closed ---------------------------------------------------------------
mkdir -p "$tmp/empty"
run --root "$tmp/empty"
assert "a root with nothing to scan fails closed" 2 "$code"

run --root
assert "a --root with no value is a usage error" 2 "$code"

run --root ''
assert "an empty --root is a usage error, not the default root" 2 "$code"

run --root "$tmp/empty" --root "$tmp/empty"
assert "a repeated --root is a usage error" 2 "$code"

run --root "$tmp/no-such-dir"
assert "a root that cannot be entered fails closed" 2 "$code"

run --bogus
assert "an unknown option is a usage error" 2 "$code"

out=$(cd "$tmp/empty" && /bin/sh "$CHECKER" 2>&1)
code=$?
assert "outside a git work tree with no --root fails closed" 2 "$code"

# A file the scan cannot read fails the scan, even beside one with a mention
# that would otherwise be reported. Skipped as root, which reads it anyway.
if [ "$(id -u)" -ne 0 ]; then
  fixture_root unreadable
  write_file "$r/docs/a.md" 'Workers start via `claude --worktree x`.'
  write_file "$r/docs/z.md" 'clean'
  chmod 000 "$r/docs/z.md"
  run --root "$r"
  chmod 600 "$r/docs/z.md"
  assert "an unreadable file in scope fails closed" 2 "$code"
fi

fixture_root c1-path
write_file "$r/docs/a$(printf '\302\233')31m.md" 'Workers start via `claude --worktree x`.'
run --root "$r"
assert "a mention in a file with a C1 control byte in its name is reported" 1 "$code"
case "$out" in
  *"$(printf '\302\233')"*)
    echo "FAIL: the reported path carries a raw C1 control byte" >&2
    failures=$((failures + 1))
    ;;
  *) echo "ok: the reported path has its C1 control byte stripped" ;;
esac
assert_contains "the stripped path is still reported" "$out" "31m.md:1"

fixture_root tab-path
write_file "$r/docs/a$(printf '\t')b.md" 'Workers start via `claude --worktree x`.'
run --root "$r"
assert "a mention in a file with a tab in its name is reported" 1 "$code"
assert_contains "the reported location keeps the whole path and line" "$out" "b.md:1"

fixture_root dash-root
mkdir -p "$tmp/dash-parent"
mv "$r" "$tmp/dash-parent/-r"
out=$(cd "$tmp/dash-parent" && /bin/sh "$CHECKER" --root -r 2>&1)
code=$?
assert "a --root beginning with a dash is a directory, not a cd option" 0 "$code"

# --- the default run reads the tracked tree ----------------------------------
# A throwaway repository: only what git tracks is in scope, so an untracked
# scratch file cannot fail the gate, and a tracked deletion is not a failure.
g="$tmp/git-mode"
mkdir -p "$g"
git -C "$g" init -q || {
  echo "FAIL: cannot create the throwaway repository" >&2
  exit 1
}
write_file "$g/docs/a.md" 'Clean prose.'
write_file "$g/docs/scratch.md" 'Workers start via `claude --worktree x`.'
write_file "$g/specs/s/design.md" 'Workers start via `claude --worktree x`.'
write_file "$g/specs/s/README.md" 'Workers start via `claude --worktree x`.'
write_file "$g/tests/t.sh" '# claude --worktree x'
write_file "$g/CHANGELOG.md" '- `claude --worktree x`'
write_file "$g/templates/.hidden/README.md" 'Run `claude --worktree x`.'
write_file "$g/docs/gone.md" 'Clean prose.'
git -C "$g" add docs/a.md docs/gone.md specs tests CHANGELOG.md templates || {
  echo "FAIL: cannot stage the throwaway repository's files" >&2
  exit 1
}
rm "$g/docs/gone.md"
out=$(cd "$g" && /bin/sh "$CHECKER" 2>&1)
code=$?
assert "the default run ignores untracked files, excluded paths, and tracked deletions" 0 "$code"
[ "$code" -eq 0 ] || printf '%s\n' "$out" >&2

write_file "$g/README.md" 'Run `claude --worktree x` to dispatch.'
git -C "$g" add README.md || {
  echo "FAIL: cannot stage the throwaway repository's README" >&2
  exit 1
}
out=$(cd "$g" && /bin/sh "$CHECKER" 2>&1)
code=$?
assert "the default run reports a tracked mention" 1 "$code"
assert_contains "the default run names the tracked file" "$out" "README.md:1"

# --- the repository itself passes --------------------------------------------
out=$(cd "$REPO_ROOT" && /bin/sh "$CHECKER" 2>&1)
code=$?
assert "the repository's tracked shipped prose passes" 0 "$code"
[ "$code" -eq 0 ] || printf '%s\n' "$out" >&2

run --root "$REPO_ROOT"
assert "the repository read as a --root tree passes" 0 "$code"
[ "$code" -eq 0 ] || printf '%s\n' "$out" >&2

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all launch-shape checks passed"
