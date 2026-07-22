#!/bin/bash
# Tests for scripts/check-doctrine-manifest.sh — the REQ-A1.3 manifest-citation
# guard (operator-dialogue Task 6, REQ-A1.3, REQ-H1.2, D-11). A skill that
# instantiates an attended human moment SHALL cite the governing doctrine in its
# machine-parseable manifest (`Doctrine: <load> interaction-style`), so the
# citation tracks the behavior it governs. The check greps the manifests of the
# surfaces this spec has instantiated (`/spec-kickoff` this pass; `/spec-draft`
# already cites it) and fails if an instantiated attended surface omits it.
#
# The surface list is deliberately partial: the execution-side surfaces
# (/orchestrate, /execute-task, /resume, /drain) add the citation on their
# deferred instantiation pass (tasks.md Deferred), so the check's list widens
# per pass rather than demanding a citation ahead of the behavior. These tests
# pin: (a) the real repo's instantiated surfaces pass; (b) a manifest that omits
# the citation fails; (c) a prose-only mention (not on a `Doctrine:` manifest
# line) does NOT satisfy it — the manifest is the machine-parseable contract,
# not incidental prose; (d) a missing SKILL.md is a fail-closed config error.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-doctrine-manifest.sh"

failures=0
assert_exit() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (missing '$2')" >&2
      printf '%s\n' "----- output -----" "$3" "------------------" >&2
      failures=$((failures + 1))
      ;;
  esac
}

if [ ! -f "$CHECKER" ]; then
  echo "FAIL: checker missing at $CHECKER" >&2
  exit 1
fi

TMP="$(mktemp -d)" || {
  echo "FAIL: mktemp -d failed" >&2
  exit 1
}
[ -n "$TMP" ] && [ -d "$TMP" ] || {
  echo "FAIL: mktemp -d produced no usable directory ('$TMP')" >&2
  exit 1
}
trap 'rm -rf "$TMP"' EXIT

# ---- (a) the real repo's instantiated surfaces pass ----
echo "== real repo: instantiated attended surfaces cite the doctrine =="
out="$(/bin/bash "$CHECKER" 2>&1)"
assert_exit "default run over the real instantiated surfaces passes" 0 "$?"
assert_contains "the run names the doctrine it checked for" "interaction-style" "$out"

# ---- synthesize an isolated skills root for the negative cases ----
mk_skill() { # mk_skill <root> <name> <manifest-body-file-contents...>
  _mk_root="$1"
  _mk_name="$2"
  mkdir -p "$_mk_root/$_mk_name"
  shift 2
  printf '%s\n' "$@" >"$_mk_root/$_mk_name/SKILL.md"
}

# A passing skill: the citation is on a real `Doctrine:` manifest line.
GOOD="$TMP/good"
mk_skill "$GOOD" spec-kickoff \
  "---" "name: spec-kickoff" "---" "# /spec-kickoff" \
  "Doctrine: run-start security-posture" \
  "Doctrine: run-start interaction-style" \
  "Doctrine: point-of-use spec-format (pre-flight)"

echo "== a manifest carrying the Doctrine: interaction-style line passes =="
out="$(/bin/bash "$CHECKER" --skills-root "$GOOD" spec-kickoff 2>&1)"
assert_exit "a present manifest citation passes" 0 "$?"

# A failing skill: interaction-style appears only in PROSE, never on a
# `Doctrine:` manifest line — the manifest is the contract, not prose mentions.
PROSE="$TMP/prose"
mk_skill "$PROSE" spec-kickoff \
  "---" "name: spec-kickoff" "---" "# /spec-kickoff" \
  "Every exchange follows the interaction-style rules (see the doctrine)." \
  "Doctrine: run-start security-posture" \
  "Doctrine: point-of-use spec-format (pre-flight)"

echo "== a prose-only mention does NOT satisfy the manifest requirement =="
out="$(/bin/bash "$CHECKER" --skills-root "$PROSE" spec-kickoff 2>&1)"
assert_exit "a prose-only interaction-style mention fails" 1 "$?"
assert_contains "the omission is reported by surface name" "spec-kickoff" "$out"

# A failing skill: no mention at all.
OMIT="$TMP/omit"
mk_skill "$OMIT" spec-draft \
  "---" "name: spec-draft" "---" "# /spec-draft" \
  "Doctrine: run-start security-posture"

echo "== a manifest omitting the citation entirely fails =="
out="$(/bin/bash "$CHECKER" --skills-root "$OMIT" spec-draft 2>&1)"
assert_exit "an omitted citation fails" 1 "$?"
assert_contains "the missing doctrine is named" "interaction-style" "$out"

# Mixed: one surface cites, one omits — the run fails as a whole and names the
# offender, not the compliant surface.
MIX="$TMP/mix"
mk_skill "$MIX" spec-kickoff \
  "Doctrine: run-start interaction-style"
mk_skill "$MIX" spec-draft \
  "Doctrine: run-start security-posture"

echo "== one compliant + one omitting surface fails and names the offender =="
out="$(/bin/bash "$CHECKER" --skills-root "$MIX" spec-kickoff spec-draft 2>&1)"
assert_exit "a mixed run fails when any surface omits the citation" 1 "$?"
assert_contains "the offending surface is named" "spec-draft" "$out"

echo "== a missing SKILL.md is a fail-closed config error (exit 2) =="
out="$(/bin/bash "$CHECKER" --skills-root "$TMP/nonexistent" spec-kickoff 2>&1)"
assert_exit "a missing manifest fails closed as a config error" 2 "$?"

echo "== --skills-root without a value is a usage error =="
out="$(/bin/bash "$CHECKER" --skills-root 2>&1)"
assert_exit "a flag missing its value is a usage error" 2 "$?"

if [ "$failures" -eq 0 ]; then
  echo "PASS: all check-doctrine-manifest tests passed"
  exit 0
else
  echo "FAIL: $failures assertion(s) failed" >&2
  exit 1
fi
