#!/bin/bash
# Tests for scripts/check-steps.sh — the guard that resolves every named point
# in check mode against a repository's own configuration and sweeps the
# retired convergence knob's key (custom-steps REQ-A1.3, REQ-F1.1, REQ-F1.2,
# REQ-H1.4).
#
# The real-repository case runs the guard as `mise run check` does. Every
# other case runs it against a fixture core root and a fixture repository, so
# each failure is the one the fixture plants.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-check-steps.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
GUARD="$repo_root/scripts/check-steps.sh"
RS="$repo_root/scripts/resolve-steps.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$GUARD" ] || {
  echo "FAIL: scripts/check-steps.sh missing" >&2
  exit 1
}

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

WIRED=$(sed -n 's/^WIRED_POINTS="\(.*\)"$/\1/p' "$RS")
UNWIRED=$(sed -n 's/^UNWIRED_POINTS="\(.*\)"$/\1/p' "$RS")
[ -n "$WIRED" ] && [ -n "$UNWIRED" ] || {
  echo "FAIL: could not read the point vocabulary from scripts/resolve-steps.sh" >&2
  exit 1
}

# run_guard [args...]: the guard with the host's plugin and step context
# cleared, so a run inside a planwright step or an installed session sees
# only what the guard itself sets.
run_guard() {
  OUT=$(env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_SKILLS_ROOT \
    -u PLANWRIGHT_CONFIG_DEFAULTS -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_LOCAL_CONFIG \
    /bin/bash "$GUARD" "$@" 2>&1)
  RC=$?
}
expect_rc() { # expect_rc <label> <want>
  if [ "$RC" -eq "$2" ]; then
    ok "$1 (exit $2)"
  else
    fail "$1: expected exit $2, got $RC"
    printf '%s\n' "----- output -----" "$OUT" "------------------" >&2
  fi
}
expect_fail() { # expect_fail <label>
  if [ "$RC" -ne 0 ]; then
    ok "$1 (exit $RC)"
  else
    fail "$1: expected a non-zero exit"
    printf '%s\n' "----- output -----" "$OUT" "------------------" >&2
  fi
}
expect_out() { # expect_out <label> <needle>
  case "$OUT" in
    *"$2"*) ok "$1" ;;
    *)
      fail "$1: output lacks '$2'"
      printf '%s\n' "----- output -----" "$OUT" "------------------" >&2
      ;;
  esac
}

# =============================================================================
# REQ-H1.4: the guard passes on this repository's own configuration and
# resolves every named point, the non-empty wired ones and the unwired ones.
# =============================================================================
run_guard
expect_rc "REQ-H1.4: the real repository's configuration passes" 0
for p in $WIRED $UNWIRED; do
  expect_out "REQ-H1.4: the real run checks point '$p'" " $p"
done
if grep -Eq '^steps_[a-z_]+:[[:space:]]*\[[^]]' "$repo_root/.claude/planwright.yml"; then
  ok "REQ-F1.2: the repository's tracked config carries a non-empty point list the guard resolves"
else
  fail "REQ-F1.2: .claude/planwright.yml sets no non-empty point list"
fi

if awk '/^\[/{c=0} /^\[tasks\.check\]/{c=1} c && /"check:steps"/{f=1} END{exit !f}' "$repo_root/mise.toml"; then
  ok "REQ-H1.4: check:steps is a dependency of the check aggregate"
else
  fail "REQ-H1.4: check:steps is not wired into mise.toml's check task"
fi

# =============================================================================
# Fixtures: a core root carrying every point key, the shipped steps seed, and
# the core skills a list may name; a git repository carrying the repo-tracked
# layer.
# =============================================================================
core="$tmp/core"
repo="$tmp/repo"
mkdir -p "$core/config" "$core/doctrine" "$core/skills/polish" "$core/skills/self-review" "$repo/.claude"
git -C "$repo" init -q
printf 'argument-hint: "[--nested]"\n' >"$core/skills/polish/SKILL.md"
printf 'argument-hint: "[--nested]"\n' >"$core/skills/self-review/SKILL.md"
cp "$repo_root/config/steps.yaml" "$core/config/steps.yaml"

write_core_defaults() { # extra lines on stdin are appended
  {
    printf 'dispatch_isolation: per-step\n'
    for p in $WIRED $UNWIRED; do
      k="steps_$(printf '%s' "$p" | tr - _)"
      if [ "$p" = convergence ]; then
        printf '%s: [polish]\n' "$k"
      else
        printf '%s: []\n' "$k"
      fi
    done
    cat
  } >"$core/config/defaults.yml"
}
tracked="$repo/.claude/planwright.yml"
reset() {
  write_core_defaults </dev/null
  printf 'steps_convergence: [self-review]\n' >"$tracked"
}
fixture() { run_guard --core "$core" --repo "$repo"; }

reset
fixture
expect_rc "a clean fixture passes" 0

# REQ-H1.4: an unresolvable step fails, naming the step and the point.
reset
printf 'steps_pre_pr: [no-such-step]\n' >>"$tracked"
fixture
expect_fail "REQ-H1.4: an unresolvable step fails"
expect_out "REQ-H1.4: the failure names the step" "no-such-step"
expect_out "REQ-H1.4: the failure names the point" "pre-pr"

# REQ-A1.3: a non-empty list at an unwired point fails, naming the point.
reset
printf 'steps_post_merge: [self-review]\n' >>"$tracked"
fixture
expect_fail "REQ-A1.3: a non-empty list at an unwired point fails"
expect_out "REQ-A1.3: the failure names the unwired point" "post-merge"

# REQ-F1.1: the retired key fails in the repo-tracked config, naming the key
# and the file.
reset
printf 'review_sequence: [self-review]\n' >>"$tracked"
fixture
expect_fail "REQ-F1.1: review_sequence in the repo-tracked config fails"
expect_out "REQ-F1.1: the failure names the key" "review_sequence"
expect_out "REQ-F1.1: the failure names the file" ".claude/planwright.yml"

# REQ-F1.1: and in the core defaults, where no transitional line is allowed.
reset
printf '# Transitional, added 2026-09-28: kept until the release lands.\nreview_sequence: [polish]\n' | write_core_defaults
fixture
expect_fail "REQ-F1.1: review_sequence in the core defaults fails, dated comment or not"
expect_out "REQ-F1.1: the failure names the defaults file" "config/defaults.yml"

# REQ-F1.2: the documented transitional line, a dated comment directly above
# the key, passes in the repo-tracked config.
reset
printf '\n# Transitional, added 2026-09-28: this repository runs the installed\n# plugin until the release lands.\nreview_sequence: [self-review]\n' >>"$tracked"
fixture
expect_rc "REQ-F1.2: the dated transitional line in the repo-tracked config passes" 0

# A dated comment separated from the key by a blank line does not cover it.
reset
printf '\n# Transitional, added 2026-09-28\n\nreview_sequence: [self-review]\n' >>"$tracked"
fixture
expect_fail "REQ-F1.1: a transitional comment detached from the key does not cover it"

# A comment without the dated marker does not cover the key either.
reset
printf '\n# kept for now\nreview_sequence: [self-review]\n' >>"$tracked"
fixture
expect_fail "REQ-F1.1: an undated comment does not make the key transitional"

# An indented key is still the key.
reset
printf '  review_sequence: [self-review]\n' >>"$tracked"
fixture
expect_fail "REQ-F1.1: an indented review_sequence still fails"

# Usage errors exit 2.
run_guard --bogus
expect_rc "an unknown flag is a usage error" 2
run_guard --core
expect_rc "a flag missing its value is a usage error" 2
run_guard --core "$tmp/nope" --repo "$repo"
expect_rc "a core root without config/defaults.yml is a usage error" 2

if [ "$failures" -ne 0 ]; then
  echo "test-check-steps: $failures failure(s)" >&2
  exit 1
fi
echo "test-check-steps: all passed"
