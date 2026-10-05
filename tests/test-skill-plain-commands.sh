#!/bin/bash
# Tests for the one-plain-command-per-Bash-call convention: the skills a
# dispatched worker or subordinate tower runs (/orchestrate, /execute-task,
# /polish, /self-review) direct one plain command per Bash call, and neither
# they nor the doctrine they cite for command shape show a compound line for a
# routine step.
#
# Why (obs:885bc3c9): under `/orchestrate --fleet --unattended`, workers
# composed lines such as `P=<root>; cd <worktree>; $P/scripts/x.sh; echo rc=$?`.
# The worker command guard defers most compound forms, and a standing decision
# matches only a literal command prefix with plain arguments, so every routine
# read reached the operator as a permission prompt. The fix is skill prose, so
# this is a structural guard over the instruction files, like its sibling
# tests/test-skill-literal-path.sh.
#
# Checks:
#   - doctrine/plugin-script-invocation.md states the convention and each of
#     its rules (no cd, no assignments, no chains, no display pipes, exit
#     status from the call's own result);
#   - each of the four skills states it and points at that doctrine doc;
#   - no inline code span or fenced line in the four skills, or in
#     doctrine/orchestration-modes.md (the meta step's command shapes), opens
#     with a command and carries a compound marker: `$(`, `&&`, `||`, `; `,
#     `cd `, a leading assignment, `echo rc`, `$?`, or a pipe into a display
#     filter;
#   - /orchestrate names the arguments the tower-marker `record` and the
#     presence `publish` usage lines require, and publishes presence before
#     the loop's first step can launch a subordinate.
#
# Runs standalone: ./tests/test-skill-plain-commands.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
doc="$REPO_ROOT/doctrine/plugin-script-invocation.md"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

ok() {
  echo "ok: $1"
}

flatten() {
  tr '\n' ' ' <"$1"
}

# compound_spans <file>: print each command-shaped inline code span (joined
# across wrapped lines) or fenced line that carries a compound marker. A span
# counts as command-shaped when it opens with a script path, a common verb, or
# an assignment, so prose spans holding a `;` are not mistaken for commands.
compound_spans() {
  awk '
    # In a fence a bare assignment is a command of its own; in an inline span
    # `name=value` is as likely a config value, so only a prefix counts there.
    function check(c, infence) {
      sub(/^[ \t]+/, "", c)
      if (c !~ /^(scripts\/|tests\/|\/|(git|gh|tmux|printf|echo|cd|sh|bash|mise|claude|jq|cat|cp|mv|rm|mkdir|ls|find|grep|sed|awk|python3|bats|test) |[A-Za-z_][A-Za-z0-9_]*=)/) return
      if (infence && c ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { print c; return }
      if (c ~ /\$\(|&&|\|\||; |(^| )cd |^[A-Za-z_][A-Za-z0-9_]*=[^ ]* |echo rc|\$\?|\| *(sed|awk|head|tail|grep|cut)( |$)/) print c
    }
    /^[ ]*```/ { fence = !fence; next }
    fence { check($0, 1); next }
    { buf = buf " " $0 }
    END {
      while (match(buf, /`[^`]+`/)) {
        check(substr(buf, RSTART + 1, RLENGTH - 2), 0)
        buf = substr(buf, RSTART + RLENGTH)
      }
    }' "$1"
}

if [ ! -f "$doc" ]; then
  fail "doctrine/plugin-script-invocation.md missing"
else
  flat="$(flatten "$doc")"
  # The backticks are literal markdown, matched as fixed strings.
  # shellcheck disable=SC2016
  for phrase in \
    'one plain command per Bash call' \
    'No `cd`' \
    'No variable assignments' \
    'No chains' \
    'No display pipes' \
    'Exit status from the result' \
    'exactly as the resolver prints it'; do
    if printf '%s' "$flat" | grep -qF "$phrase"; then
      ok "doctrine doc states: $phrase"
    else
      fail "doctrine doc missing: $phrase"
    fi
  done
fi

for name in orchestrate execute-task polish self-review; do
  skill="$REPO_ROOT/skills/$name/SKILL.md"
  if [ ! -f "$skill" ]; then
    fail "$name SKILL.md missing"
    continue
  fi
  if flatten "$skill" | grep -qF 'one plain command per Bash call' \
    && grep -qF 'doctrine/plugin-script-invocation.md' "$skill"; then
    ok "$name: directs one plain command per Bash call, citing the doctrine"
  else
    fail "$name: one-plain-command directive or its doctrine pointer missing"
  fi
  hits="$(compound_spans "$skill")"
  if [ -z "$hits" ]; then
    ok "$name: no compound command shape in its code"
  else
    fail "$name: compound command shape(s): $hits"
  fi
done

modes="$REPO_ROOT/doctrine/orchestration-modes.md"
if [ ! -f "$modes" ]; then
  fail "doctrine/orchestration-modes.md missing"
else
  hits="$(compound_spans "$modes")"
  if [ -z "$hits" ]; then
    ok "orchestration-modes: no compound command shape in its code"
  else
    fail "orchestration-modes: compound command shape(s): $hits"
  fi
fi

orch="$REPO_ROOT/skills/orchestrate/SKILL.md"
oflat="$(flatten "$orch")"
# Backticks below are literal markdown.
# shellcheck disable=SC2016
if printf '%s' "$oflat" | grep -qE 'fleet-tower-marker\.sh record <spec> --mode <mode> +--pid <pid> +--checkout <[a-z-]+>' \
  && printf '%s' "$oflat" | grep -qE '`interactive` plus `--session-id <uuid>`'; then
  ok "orchestrate: tower-marker record names its required arguments and the interactive session id"
else
  fail "orchestrate: tower-marker record lacks <spec> --mode --pid --checkout, or the interactive --session-id"
fi
# Backticks below are literal markdown.
# shellcheck disable=SC2016
if printf '%s' "$oflat" | grep -qE 'fleet-presence\.sh publish +--checkout <[a-z-]+> +--pid <pid>' \
  && printf '%s' "$oflat" | grep -qE 'death handle' \
  && printf '%s' "$oflat" | grep -qE '`--session-id <uuid>` when interactive' \
  && printf '%s' "$oflat" | grep -qE '`--specs`, `--fenced` and, under `--meta`, `--meta`'; then
  ok "orchestrate: presence publish names --checkout, --pid, the death handle and the record fields"
else
  fail "orchestrate: presence publish lacks --checkout, --pid, the interactive --session-id, the death handle, --specs, --fenced or --meta"
fi
# first_in_watch <pattern>: the line of the pattern's first match inside the
# `## --watch` section, so a mention elsewhere in the skill cannot satisfy the
# ordering checks below.
first_in_watch() {
  awk -v pat="$1" '
    /^## / { inw = ($0 == "## --watch") }
    inw && tolower($0) ~ pat { print NR; exit }' "$orch"
}
publish_line="$(first_in_watch 'fleet-presence[.]sh publish')"
loop_line="$(first_in_watch 'loop the full step')"
if [ -n "$publish_line" ] && [ -n "$loop_line" ] && [ "$publish_line" -lt "$loop_line" ]; then
  ok "orchestrate: presence is published before the loop's first step"
else
  fail "orchestrate: presence publish does not precede the loop's first step"
fi
marker_line="$(first_in_watch 'fleet-tower-marker[.]sh record')"
if [ -n "$marker_line" ] && [ -n "$loop_line" ] && [ "$marker_line" -lt "$loop_line" ]; then
  ok "orchestrate: the tower marker is recorded before the loop's first step"
else
  fail "orchestrate: tower marker record does not precede the loop's first step"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all skill plain-command tests passed"
