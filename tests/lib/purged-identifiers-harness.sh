# shellcheck shell=bash
# shellcheck disable=SC2034 # the suites that source this read the tokens and paths
# purged-identifiers-harness.sh — the fixture harness the
# tests/test-check-purged-identifiers*.sh suites share (sourced, never run).
# Every seed file is per-test and temporary, planted with test-only tokens:
# one shared test seed would race under the parallel runner, and the real
# identifiers are provisioned out of band and never available to a test.
# Sourcing runs setup and installs the only EXIT trap.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

# Isolate fixtures from the host's global/system git config (a global
# core.hooksPath, commit signing, or autosetuprebase would all corrupt them).
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_SYSTEM=/dev/null
GIT_EDITOR=true
export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_EDITOR

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SCAN="$REPO_ROOT/scripts/check-purged-identifiers.sh"
SEEDER="$REPO_ROOT/scripts/seed-purged-identifiers.sh"
REAL_SEED="$REPO_ROOT/config/purged-identifiers.seed"

# Test-only planted tokens. They exist nowhere but these suites and their
# fixtures; the committed seed file is asserted NOT to contain them, which is
# what makes a test-token-only seed list a failure.
TOKEN='zzq-planted-seedtoken'
TOKEN2='zzq-second-planted-token'
# The normalized spelling of TOKEN. The withholding assertions check BOTH: a
# report that echoed the normalized candidate instead of the source text would
# leak the identifier just as effectively.
NORM='zzqplantedseedtoken'

failures=0

assert_exit() {
  # assert_exit <label> <expected-exit> <actual-exit>
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  # assert_contains <label> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (missing '$2')" >&2
      echo "----- output -----" >&2
      printf '%s\n' "$3" >&2
      echo "------------------" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_absent() {
  # assert_absent <label> <needle> <haystack>
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (output leaked '$2')" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

# finish <suite> — report the tally and exit with it.
finish() {
  if [ "$failures" -ne 0 ]; then
    echo "$failures test(s) failed" >&2
    exit 1
  fi
  echo "all $1 tests passed"
}

# The deliverables these suites exercise must exist before any scenario runs.
for f in "$SCAN" "$SEEDER"; do
  if [ ! -x "$f" ]; then
    echo "FAIL: $f missing or not executable" >&2
    exit 1
  fi
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/purged-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

# new_repo <name> — a fresh fixture repo with a deterministic, signing-free
# identity, and no hooks unless a scenario wires them.
new_repo() {
  d="$TMP/$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email fixture@example.invalid
  git -C "$d" config user.name 'Fixture'
  git -C "$d" config commit.gpgsign false
  printf '%s' "$d"
}

# seed_into <repo> <token>... — provision a per-test seed file through the
# real seeding path, so the suites exercise the same normalization contract
# the scanner reads (never a hand-written hash).
seed_into() {
  repo="$1"
  shift
  mkdir -p "$repo/config"
  printf '%s\n' "$@" \
    | (cd "$repo" && "$SEEDER" >/dev/null 2>&1)
}
