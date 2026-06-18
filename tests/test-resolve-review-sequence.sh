#!/bin/bash
# Tests for scripts/resolve-review-sequence.sh — the review_sequence knob
# resolver (Task 6: D-6, REQ-C1.3, REQ-D1.3, REQ-E1.3, REQ-E1.4).
#
# review_sequence is the ordered list of nestable review-skill names
# /execute-task's convergence phase runs. This resolver reads it *through*
# config-get (the Task 3 four-layer overlay reader — no layer logic is
# re-implemented here, REQ-D1.1), parses the inline list, validates each name
# against the "nestable review skill" predicate (a skill whose SKILL.md
# argument-hint declares --nested, REQ-D1.3), and applies the REQ-E1.4 by-layer
# malformed policy to a bad name. Output is the validated names, one per line.
#
# What is covered:
#   - the default (no overlays) resolves to today's convergence behavior
#     (a single `polish`), so /execute-task is unchanged out of the box;
#   - review_sequence resolves across all four layers via config-get
#     (last-layer-wins), and an overlay-set ordering is emitted in order;
#   - a bare scalar and an inline flow list both parse; whitespace and a
#     trailing comment are tolerated (config-get strips the comment);
#   - the REQ-E1.4 by-layer policy on a bad name (unknown or non-nestable
#     skill, or an empty list): adopter/machine-local degrade+warn to the core
#     default, repo-tracked hard-fails (exit 4);
#   - a structurally malformed repo-tracked config file still hard-fails
#     (config-get's exit 4 propagates).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-resolve-review-sequence.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
RS="$here/../scripts/resolve-review-sequence.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$RS" ] || fail "scripts/resolve-review-sequence.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- Hermetic skills root: fixture SKILL.md files that declare (or omit) the
#     --nested argument-hint. polish / self-review are nestable; orchestrate
#     exists but is not nestable; anything without a dir is "unknown".
skills="$tmp/skills"
mkdir -p "$skills/polish" "$skills/self-review" "$skills/orchestrate"
printf 'argument-hint: "[--nested]"\n' >"$skills/polish/SKILL.md"
printf 'argument-hint: "[--nested]"\n' >"$skills/self-review/SKILL.md"
printf 'argument-hint: "[--watch]"\n' >"$skills/orchestrate/SKILL.md"

# --- Config layer fixtures, wired through config-get's env overrides exactly as
#     test-config-get.sh does (hermetic: no $HOME, no git toplevel).
core_cfg="$tmp/core-defaults.yml"
adopter_root="$tmp/adopter"
repo="$tmp/repo"
mkdir -p "$adopter_root" "$repo/.claude"
adopter_cfg="$adopter_root/planwright.yml"
tracked_cfg="$repo/.claude/planwright.yml"
mlocal_cfg="$repo/.claude/planwright.local.yml"

# The shipped-style core default: today's single-skill gauntlet.
printf 'review_sequence: [polish]\n' >"$core_cfg"

# The resolver takes no arguments (the key is fixed), so `run` passes none.
run() {
  PLANWRIGHT_SKILLS_ROOT="$skills" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$RS"
}

reset_layers() {
  rm -f "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg"
}

# 1. Default (no overlays) reproduces today's convergence behavior: one `polish`.
reset_layers
got=$(run)
[ "$got" = polish ] \
  || fail "default did not resolve to today's behavior (expected 'polish', got '$got')"
echo "ok: the default review_sequence reproduces today's convergence (single 'polish')"

# 2. Four-layer resolution via config-get: a machine-local ordering wins, and is
#    emitted in order (one name per line).
reset_layers
printf 'review_sequence: [self-review, polish]\n' >"$mlocal_cfg"
got=$(run)
[ "$got" = "$(printf 'self-review\npolish')" ] \
  || fail "machine-local ordering not honored in order (got: '$got')"
echo "ok: an overlay-set ordering resolves through the four layers and is emitted in order"

# 2b. Ordering is honored, not sorted: the reverse order yields the reverse output.
reset_layers
printf 'review_sequence: [polish, self-review]\n' >"$mlocal_cfg"
got=$(run)
[ "$got" = "$(printf 'polish\nself-review')" ] \
  || fail "ordering was reordered/sorted (got: '$got')"
echo "ok: the list order is preserved verbatim (not sorted)"

# 2c. Last-layer-wins across layers: repo-tracked overrides adopter overrides core.
reset_layers
printf 'review_sequence: [self-review]\n' >"$adopter_cfg"
printf 'review_sequence: [polish, self-review]\n' >"$tracked_cfg"
got=$(run)
[ "$got" = "$(printf 'polish\nself-review')" ] \
  || fail "repo-tracked did not win over adopter (got: '$got')"
rm -f "$tracked_cfg"
got=$(run)
[ "$got" = self-review ] \
  || fail "adopter did not win over core after repo-tracked removed (got: '$got')"
echo "ok: review_sequence obeys last-layer-wins (core < adopter < repo-tracked < machine-local)"

# 3. A bare scalar value (no brackets) parses as a single-element list.
reset_layers
printf 'review_sequence: polish\n' >"$mlocal_cfg"
got=$(run)
[ "$got" = polish ] \
  || fail "bare scalar value not parsed as a single element (got: '$got')"
echo "ok: a bare scalar review_sequence parses as one element"

# 3b. Whitespace inside the flow list and a trailing comment are tolerated.
reset_layers
printf 'review_sequence: [ self-review ,  polish ]   # the gauntlet\n' >"$tracked_cfg"
got=$(run)
[ "$got" = "$(printf 'self-review\npolish')" ] \
  || fail "whitespace/comment not tolerated (got: '$got')"
echo "ok: inner whitespace and a trailing comment are tolerated"

# 4. Bad name (unknown skill) in the adopter overlay: malformed value, degrade to
#    the core default with a loud warning, exit 0.
reset_layers
printf 'review_sequence: [polish, no-such-skill]\n' >"$adopter_cfg"
rc=0
err=$(run 2>&1 >/dev/null) || rc=$?
out=$(run 2>/dev/null)
[ "$rc" = 0 ] || fail "bad-name adopter: exit $rc, expected 0 (degrade)"
[ "$out" = polish ] || fail "bad-name adopter: did not degrade to core default (got '$out')"
case $err in
  *adopter*) ;;
  *) fail "bad-name adopter: warning does not name the layer (got: '$err')" ;;
esac
echo "ok: an unknown skill in the adopter overlay degrades to the core default with a warning"

# 4b. Non-nestable skill (exists, but no --nested argument-hint) is also malformed.
reset_layers
printf 'review_sequence: [polish, orchestrate]\n' >"$mlocal_cfg"
rc=0
err=$(run 2>&1 >/dev/null) || rc=$?
out=$(run 2>/dev/null)
[ "$rc" = 0 ] || fail "non-nestable machine-local: exit $rc, expected 0 (degrade)"
[ "$out" = polish ] || fail "non-nestable machine-local: did not degrade to core (got '$out')"
case $err in
  *machine-local*) ;;
  *) fail "non-nestable machine-local: warning does not name the layer (got: '$err')" ;;
esac
echo "ok: a non-nestable skill in machine-local degrades to the core default with a warning"

# 4c. An empty list is malformed (a gauntlet needs at least one skill).
reset_layers
printf 'review_sequence: []\n' >"$adopter_cfg"
rc=0
err=$(run 2>&1 >/dev/null) || rc=$?
out=$(run 2>/dev/null)
[ "$rc" = 0 ] || fail "empty-list adopter: exit $rc, expected 0 (degrade)"
[ "$out" = polish ] || fail "empty-list adopter: did not degrade to core (got '$out')"
echo "ok: an empty review_sequence list is treated as malformed and degrades"

# 5. Bad name in the repo-tracked (team-shared) overlay hard-fails (exit 4): a
#    broken shared gauntlet never silently degrades a team.
reset_layers
printf 'review_sequence: [polish, no-such-skill]\n' >"$tracked_cfg"
rc=0
err=$(run 2>&1 >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "bad-name repo-tracked: exit $rc, expected 4 (hard-fail)"
case $err in
  *repo-tracked*) ;;
  *) fail "bad-name repo-tracked: error does not name the layer (got: '$err')" ;;
esac
echo "ok: a bad name in the repo-tracked overlay hard-fails (exit 4)"

# 5b. A non-nestable name in repo-tracked also hard-fails.
reset_layers
printf 'review_sequence: [orchestrate]\n' >"$tracked_cfg"
rc=0
run >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "non-nestable repo-tracked: exit $rc, expected 4 (hard-fail)"
echo "ok: a non-nestable name in the repo-tracked overlay hard-fails (exit 4)"

# 6. A structurally malformed repo-tracked config FILE (a YAML block sequence,
#    which config-get rejects) propagates the hard-fail (exit 4).
reset_layers
printf 'review_sequence:\n  - polish\n  - self-review\n' >"$tracked_cfg"
rc=0
run >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] \
  || fail "structurally malformed repo-tracked file: exit $rc, expected 4 (propagated hard-fail)"
echo "ok: a structurally malformed repo-tracked config file hard-fails (exit 4 propagated)"

# 7. A malformed adopter FILE (block sequence) degrades to the core default
#    (config-get degrades adopter; the resolver still yields a usable gauntlet).
reset_layers
printf 'review_sequence:\n  - polish\n' >"$adopter_cfg"
rc=0
out=$(run 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "malformed adopter file: exit $rc, expected 0 (degrade)"
[ "$out" = polish ] || fail "malformed adopter file: did not degrade to core (got '$out')"
echo "ok: a malformed adopter config file degrades to the core default"

# 8. Determinism: identical inputs yield identical output across repeated runs.
reset_layers
printf 'review_sequence: [self-review, polish]\n' >"$tracked_cfg"
a=$(run)
b=$(run)
[ "$a" = "$b" ] || fail "resolution is not deterministic across runs"
echo "ok: resolution is deterministic across repeated runs"

echo "PASS: resolve-review-sequence"
