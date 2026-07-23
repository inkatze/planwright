#!/usr/bin/env bash
# check-doctrine-manifest.sh — the REQ-A1.3 manifest-citation guard
# (operator-dialogue Task 6, REQ-A1.3, REQ-H1.2, D-11).
#
# REQ-A1.3: a skill SHALL cite the governing doctrine in its manifest for each
# attended human moment it instantiates, so the citation tracks the behavior it
# governs and never precedes it. The `interaction-style` doctrine governs every
# attended human surface (comprehension, approval, handoff, report); a surface
# that has been reworked to instantiate it must carry the citation on its
# machine-parseable manifest line (`Doctrine: <load> interaction-style`), not
# merely in incidental prose. This check is the CI backstop for that rule.
#
# The instantiated-surface list is deliberately partial and grows per pass: the
# kickoff surface is instantiated this pass (`/spec-kickoff`), and `/spec-draft`
# already cites the doctrine. The execution-side surfaces (/orchestrate,
# /execute-task, /resume, /drain) add the citation when their behavior is
# reworked on their deferred pass (see the operator-dialogue tasks.md Deferred
# entry); until then they are intentionally NOT in the list, so the check never
# demands a citation ahead of the behavior that honors it. To widen the list on
# a future instantiation pass, add the surface name to DEFAULT_SURFACES below.
#
# The "manifest" is the block of `Doctrine: <run-start|point-of-use> <doc>`
# lines an instruction-hygiene manifest emits (doctrine/instruction-hygiene.md).
# A prose sentence that merely names the doctrine does NOT satisfy the rule: the
# manifest line is the machine-parseable contract the loader and this guard read.
#
# Usage: check-doctrine-manifest.sh [--skills-root <dir>] [<surface>...]
#   --skills-root <dir>  the skills directory (default: <repo>/skills)
#   <surface>...         the attended surfaces to check (default: the built-in
#                        instantiated-surface list). Each names <root>/<surface>/
#                        SKILL.md.
#
# Exit codes: 0 every checked surface cites `interaction-style` in its manifest;
# 1 one or more instantiated surfaces omit the manifest citation; 2 usage or
# config error (a flag missing its value, or a surface whose SKILL.md is absent
# — fail-closed so a moved/renamed manifest never silently passes).
#
# Output carries no untrusted bytes into the terminal beyond the argument-derived
# skills-root path, which passes the canonical sanitize_printable first (echo
# discipline, doctrine/security-posture.md). SKILL.md content is matched with
# grep only, never executed. Portable bash 3.2 / BSD tooling; no external deps
# beyond grep.
set -u

# Pin the C locale so the regex bracket/word classes mean their ASCII range on
# every host (defensive; mirrors sibling checks).
LC_ALL=C
export LC_ALL

# A user CDPATH would make cd echo into the command substitution below.
unset CDPATH

# The canonical echo-discipline sanitizer, so an argument-supplied path carrying
# control bytes cannot drive the terminal when echoed on an error path.
# shellcheck source=scripts/echo-safety.sh
. "$(dirname "$0")/echo-safety.sh"

prog="check-doctrine-manifest"

# The governing doctrine this guard enforces the citation of. This spec's
# attended surfaces instantiate the interaction-style doctrine.
DOCTRINE="interaction-style"

# The instantiated attended surfaces (REQ-A1.3, kickoff-first this pass). Widen
# this list as each further surface's behavior is reworked to instantiate the
# doctrine — never ahead of it.
DEFAULT_SURFACES="spec-kickoff spec-draft"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
skills_root="$repo_root/skills"

# ---- argument parsing --------------------------------------------------------
surfaces=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skills-root)
      if [ $# -lt 2 ]; then
        echo "$prog: --skills-root needs a value" >&2
        exit 2
      fi
      skills_root="$2"
      shift 2
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        surfaces="$surfaces $1"
        shift
      done
      ;;
    -*)
      echo "$prog: unknown option: $(sanitize_printable "$1")" >&2
      exit 2
      ;;
    *)
      surfaces="$surfaces $1"
      shift
      ;;
  esac
done

[ -n "$surfaces" ] || surfaces="$DEFAULT_SURFACES"

# ---- the check ---------------------------------------------------------------
# A manifest citation is a `Doctrine:` line naming the doctrine at a sanctioned
# load phase. Anchored so a prose sentence that merely mentions the doctrine name
# does not match — only the machine-parseable manifest line does.
manifest_re="^Doctrine:[[:space:]]+(run-start|point-of-use)[[:space:]]+${DOCTRINE}([[:space:]]|\$)"

violations=0
checked=0
for surface in $surfaces; do
  skill_md="$skills_root/$surface/SKILL.md"
  if [ ! -f "$skill_md" ]; then
    echo "$prog: no SKILL.md for surface '$(sanitize_printable "$surface")' at $(sanitize_printable "$skill_md") (fail-closed)" >&2
    exit 2
  fi
  checked=$((checked + 1))
  if grep -Eq "$manifest_re" "$skill_md"; then
    continue
  fi
  echo "$prog: surface '$(sanitize_printable "$surface")' omits the '$DOCTRINE' manifest citation (expected a 'Doctrine: <run-start|point-of-use> $DOCTRINE' line in $(sanitize_printable "$skill_md"))" >&2
  violations=$((violations + 1))
done

if [ "$violations" -ne 0 ]; then
  echo "$prog: $violations instantiated surface(s) omit the '$DOCTRINE' manifest citation (REQ-A1.3)" >&2
  exit 1
fi

echo "$prog: all $checked instantiated surface(s) cite '$DOCTRINE' in their manifest"
exit 0
