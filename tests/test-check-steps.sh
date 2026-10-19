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

tmp=$(mktemp -d) || exit 1
# Checked before the cd: bash 3.2 treats `cd ""` as a no-op, which would
# point the cleanup trap at the caller's directory.
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

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
    -u PLANWRIGHT_REPO_ROOT_CHECKED -u PLANWRIGHT_CONFIG_STRICT_OVERLAYS \
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
if grep -qx 'steps_convergence: \[self-review\]' "$repo_root/.claude/planwright.yml"; then
  ok "REQ-F1.2: the repository's tracked config carries steps_convergence: [self-review], which the guard resolves"
else
  fail "REQ-F1.2: .claude/planwright.yml does not set steps_convergence: [self-review]"
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
reset_fixture() {
  write_core_defaults </dev/null
  printf 'steps_convergence: [self-review]\n' >"$tracked"
}
run_fixture() { run_guard --core "$core" --repo "$repo"; }

reset_fixture
run_fixture
expect_rc "a clean fixture passes" 0

# A git hook exports repository selectors; they must not redirect the
# toplevel check to another tree.
GIT_DIR="$tmp/nope" GIT_WORK_TREE="$tmp" run_fixture
expect_rc "inherited GIT_DIR and GIT_WORK_TREE do not reject a valid repository" 0

# REQ-H1.4: an unresolvable step fails, naming the step and the point.
reset_fixture
printf 'steps_pre_pr: [no-such-step]\n' >>"$tracked"
run_fixture
expect_fail "REQ-H1.4: an unresolvable step fails"
expect_out "REQ-H1.4: the failure names the step" "no-such-step"
expect_out "REQ-H1.4: the failure names the point" "pre-pr"

# REQ-A1.3: a non-empty list at an unwired point fails, naming the point.
reset_fixture
printf 'steps_post_merge: [self-review]\n' >>"$tracked"
run_fixture
expect_fail "REQ-A1.3: a non-empty list at an unwired point fails"
expect_out "REQ-A1.3: the failure names the unwired point" "post-merge"

# REQ-F1.1: the retired key fails in the repo-tracked config, naming the key
# and the file.
reset_fixture
printf 'review_sequence: [self-review]\n' >>"$tracked"
run_fixture
expect_fail "REQ-F1.1: review_sequence in the repo-tracked config fails"
expect_out "REQ-F1.1: the sweep names the file and the key" "check-steps: .claude/planwright.yml:2 sets review_sequence"

# REQ-F1.1: and in the core defaults, where no transitional line is allowed.
reset_fixture
printf '# Transitional, added 2026-09-28: kept until the release lands.\nreview_sequence: [polish]\n' | write_core_defaults
run_fixture
expect_fail "REQ-F1.1: review_sequence in the core defaults fails, dated comment or not"
expect_out "REQ-F1.1: the sweep names the defaults file and the key" "check-steps: config/defaults.yml:"

# REQ-F1.2: the documented transitional line, a dated comment directly above
# the key, passes in the repo-tracked config.
reset_fixture
printf '\n# Transitional, added 2026-09-28: this repository runs the installed\n# plugin until the release lands.\nreview_sequence: [self-review]\n' >>"$tracked"
run_fixture
expect_rc "REQ-F1.2: the dated transitional line in the repo-tracked config passes" 0
expect_out "REQ-F1.2: the pass notes the transitional line" "transitional review_sequence line at .claude/planwright.yml:5"
expect_out "REQ-F1.2: the pass does not claim no key is set" "outside a transitional line"

# A dated comment separated from the key by a blank line does not cover it.
reset_fixture
printf '\n# Transitional, added 2026-09-28\n\nreview_sequence: [self-review]\n' >>"$tracked"
run_fixture
expect_fail "REQ-F1.1: a transitional comment detached from the key does not cover it"
expect_out "REQ-F1.1: the sweep flags the detached line" "check-steps: .claude/planwright.yml:5 sets review_sequence"

# A marker without its date does not cover the key either.
reset_fixture
printf '\n# Transitional: kept for now\nreview_sequence: [self-review]\n' >>"$tracked"
run_fixture
expect_fail "REQ-F1.1: an undated transitional comment does not cover the key"
expect_out "REQ-F1.1: the sweep flags the undated line" "check-steps: .claude/planwright.yml:4 sets review_sequence"

# A blank before the colon is still the key.
reset_fixture
printf 'review_sequence : [self-review]\n' >>"$tracked"
run_fixture
expect_fail "REQ-F1.1: review_sequence with a blank before the colon fails"
expect_out "REQ-F1.1: the sweep flags the spaced key" "check-steps: .claude/planwright.yml:2 sets review_sequence"

# An indented key is still the key.
reset_fixture
printf '  review_sequence: [self-review]\n' >>"$tracked"
run_fixture
expect_fail "REQ-F1.1: an indented review_sequence still fails"
expect_out "REQ-F1.1: the sweep itself flags the indented key" "check-steps: .claude/planwright.yml:2 sets review_sequence"

# Usage errors exit 2.
run_guard --bogus
expect_rc "an unknown flag is a usage error" 2
expect_out "the unknown flag is named" "check-steps: unknown argument: --bogus"
run_guard --core
expect_rc "--core missing its value is a usage error" 2
expect_out "the flag missing its value is named" "check-steps: --core needs a value"
run_guard --repo
expect_rc "--repo missing its value is a usage error" 2
expect_out "the flag missing its value is named" "check-steps: --repo needs a value"
run_guard --core "$tmp/nope" --repo "$repo"
expect_rc "a core root without config/defaults.yml is a usage error" 2
expect_out "the missing defaults file is named" "check-steps: no readable config/defaults.yml under"
run_guard --core "$core" --repo "$tmp/nope"
expect_rc "a missing repository is a usage error" 2
expect_out "the missing repository is named" "check-steps: no repository at"
mkdir -p "$repo/sub"
run_guard --core "$core" --repo "$repo/sub"
expect_rc "a repository path that is not a git toplevel is a usage error" 2
expect_out "the non-toplevel repository is named" "check-steps: not a git toplevel:"

if [ "$failures" -ne 0 ]; then
  echo "test-check-steps: $failures failure(s)" >&2
  exit 1
fi
echo "test-check-steps: all passed"
