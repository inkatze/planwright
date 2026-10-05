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

# fixture_root <name> — a root holding one clean file in every scanned
# directory, so a case adds only the line it is about.
fixture_root() {
  fr="$tmp/$1"
  for d in docs doctrine skills/x scripts config; do
    mkdir -p "$fr/$d" || exit 1
    printf '%s\n' 'Nothing about launches here.' >"$fr/$d/clean.md"
  done
  printf '%s\n' '# readme' >"$fr/README.md"
  printf '%s\n' "$fr"
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
r=$(fixture_root tmux-form)
write_file "$r/docs/fleet.md" 'Intro.' '' \
  'The tmux rung launches its worker with' \
  '`claude --worktree <suffix> --tmux=classic`, switching your client.'
run --root "$r"
assert "the --tmux=classic form presented as the rung's launch fails" 1 "$code"
assert_contains "the failure names the file and line" "$out" "docs/fleet.md:4"

r=$(fixture_root bare-form)
write_file "$r/skills/x/SKILL.md" \
  'Dispatch places the worktree and runs `claude --worktree <suffix>` in tmux.'
run --root "$r"
assert "the bare claude --worktree form presented as the rung's launch fails" 1 "$code"

r=$(fixture_root flag-alone)
write_file "$r/doctrine/backend.md" 'The worker pane is opened with --tmux=classic.'
run --root "$r"
assert "--tmux=classic named alone fails" 1 "$code"

r=$(fixture_root spaced)
write_file "$r/config/x.json" '{"_about": "launches claude   --worktree x"}'
run --root "$r"
assert "extra spacing between claude and --worktree is still caught" 1 "$code"

r=$(fixture_root wrapped)
write_file "$r/skills/x/SKILL.md" '- **tmux**. An interactive worker in a named window via `claude' \
  '  --worktree`. Observe it with capture-pane.'
run --root "$r"
assert "a mention wrapped across a line break is still caught" 1 "$code"
assert_contains "the wrapped mention is reported at its first line" "$out" "skills/x/SKILL.md:1"

r=$(fixture_root wrapped-comment)
write_file "$r/scripts/s.sh" '# the worker launches via claude' '#   --worktree x'
run --root "$r"
assert "a mention wrapped across comment lines is still caught" 1 "$code"

# --- the hand-launch label passes --------------------------------------------
r=$(fixture_root labeled)
write_file "$r/docs/conventions.md" \
  'An operator can still re-enter a worktree by hand-launch:' \
  '`claude --worktree <suffix>` (with or without `--tmux=classic`).'
run --root "$r"
assert "an old-shape mention labeled a hand-launch passes" 0 "$code"

r=$(fixture_root labeled-script)
write_file "$r/scripts/flight.sh" \
  '# The print rung prints an operator hand-launch command.' \
  'set -- claude --worktree "$suffix"'
run --root "$r"
assert "a script line under a hand-launch comment passes" 0 "$code"

r=$(fixture_root prior)
write_file "$r/scripts/w.sh" \
  '# Probe the name the prior launcher (`claude --worktree`) gave its session.'
run --root "$r"
assert "a mention naming the prior launcher passes" 0 "$code"

# The label must sit near the mention: a blank line ends its reach, and so does
# distance inside one long paragraph.
r=$(fixture_root far-blank)
write_file "$r/docs/a.md" 'This is a hand-launch.' '' 'Workers start via `claude --worktree x`.'
run --root "$r"
assert "a label across a blank line does not cover the mention" 1 "$code"

r=$(fixture_root far-lines)
write_file "$r/docs/a.md" 'This is a hand-launch.' 'one' 'two' 'three' 'four' \
  'Workers start via `claude --worktree x`.'
run --root "$r"
assert "a label several lines away does not cover the mention" 1 "$code"

r=$(fixture_root far-sentence)
write_file "$r/config/s.json" \
  '{"_about": "A hand-launch exists. One. Two. Three. Four. The rung runs claude --worktree x."}'
run --root "$r"
assert "a label several sentences away on one long line does not cover it" 1 "$code"

# --- scope: README files are in, specs/, tests/ and the changelog are out -----
r=$(fixture_root readme)
write_file "$r/templates/t/README.md" 'Run `claude --worktree x --tmux=classic` to dispatch.'
run --root "$r"
assert "a nested README presenting the old shape fails" 1 "$code"

r=$(fixture_root excluded)
write_file "$r/specs/s/design.md" 'The rung ran `claude --worktree x --tmux=classic`.'
write_file "$r/tests/test-x.sh" '# negative case: claude --worktree x --tmux=classic'
write_file "$r/CHANGELOG.md" '- launches via `claude --worktree x`'
write_file "$r/docs/CHANGELOG.md" '- launches via `claude --worktree x`'
run --root "$r"
assert "specs/, tests/ and changelog mentions are out of scope" 0 "$code"

# --- fail closed ---------------------------------------------------------------
mkdir -p "$tmp/empty"
run --root "$tmp/empty"
assert "a root with nothing to scan fails closed" 2 "$code"

run --root
assert "a --root with no value is a usage error" 2 "$code"

run --bogus
assert "an unknown option is a usage error" 2 "$code"

# --- the repository itself passes --------------------------------------------
run --root "$REPO_ROOT"
assert "the repository's shipped prose passes" 0 "$code"
[ "$code" -eq 0 ] || printf '%s\n' "$out" >&2

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all launch-shape checks passed"
