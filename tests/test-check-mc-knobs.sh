#!/bin/bash
# Tests for scripts/check-mc-knobs.sh — the mission-control knob inventory
# check: every mission_control_* key resolves with its default and carries an
# options-reference row naming its evidence, and no behaviour goes without a
# knob (mission-control REQ-J1.1, REQ-J1.2).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-check-mc-knobs.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
GUARD="$repo_root/scripts/check-mc-knobs.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$GUARD" ] || {
  echo "FAIL: scripts/check-mc-knobs.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

run_guard() {
  OUT=$(env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_ROOT \
    -u PLANWRIGHT_CONFIG_DEFAULTS -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_LOCAL_CONFIG \
    -u PLANWRIGHT_REPO_ROOT -u PLANWRIGHT_REPO_ROOT_CHECKED -u PLANWRIGHT_CONFIG_STRICT_OVERLAYS \
    /bin/bash "$GUARD" "$@" 2>&1)
  RC=$?
}
expect_rc() {
  if [ "$RC" -eq "$2" ]; then
    ok "$1 (exit $2)"
  else
    fail "$1: expected exit $2, got $RC"
    printf '%s\n' "----- output -----" "$OUT" "------------------" >&2
  fi
}
expect_out() {
  case "$OUT" in
    *"$2"*) ok "$1" ;;
    *)
      fail "$1: output lacks '$2'"
      printf '%s\n' "----- output -----" "$OUT" "------------------" >&2
      ;;
  esac
}

# ---------------------------------------------------------------------------
# REQ-J1.1, REQ-J1.2: the real repository passes, and the check runs in CI's
# lint job.
# ---------------------------------------------------------------------------
run_guard
expect_rc "REQ-J1.1: the real repository's knobs pass the inventory check" 0
if awk '/^\[/{c=0} /^\[tasks\."check:non-test"\]$/{c=1} c && /"check:mc-knobs"/{f=1} END{exit !f}' "$repo_root/mise.toml"; then
  ok "REQ-J1.1: check:mc-knobs is a dependency of check:non-test"
else
  fail "REQ-J1.1: check:mc-knobs is not wired into mise.toml's check:non-test task"
fi
if grep -q '^mission_control_' "$repo_root/config/defaults.yml"; then
  ok "REQ-J1.1: the shipped defaults carry mission_control_* knobs"
else
  fail "REQ-J1.1: the shipped defaults carry no mission_control_* knob"
fi

# ---------------------------------------------------------------------------
# Fixture: a core root carrying the shipped knobs, inventory, options
# reference and the scripts that read them.
# ---------------------------------------------------------------------------
core="$tmp/core"
reset_fixture() {
  rm -rf "$core"
  mkdir -p "$core/config" "$core/docs" "$core/scripts" "$core/doctrine"
  grep '^mission_control_' "$repo_root/config/defaults.yml" >"$core/config/defaults.yml"
  cp "$repo_root/config/mission-control-knobs.tsv" "$core/config/"
  cp "$repo_root/docs/options-reference.md" "$core/docs/"
  cp "$repo_root"/scripts/mc-*.sh "$core/scripts/"
}
run_fixture() { run_guard --core "$core"; }

reset_fixture
run_fixture
expect_rc "a fixture copy of the shipped knobs passes" 0

# REQ-J1.1: a seeded behaviour without a knob fails.
reset_fixture
printf 'seeded-behaviour\t-\tscripts/mc-program.sh\n' >>"$core/config/mission-control-knobs.tsv"
run_fixture
expect_rc "REQ-J1.1: an inventoried behaviour with no knob fails" 1
expect_out "REQ-J1.1: the knob-less behaviour is named" "seeded-behaviour"

reset_fixture
printf '#!/bin/sh\n# reads mission_control_unseeded_pref without a knob\n' >"$core/scripts/mc-seeded.sh"
run_fixture
expect_rc "REQ-J1.1: a script reading an undeclared mission_control_* key fails" 1
expect_out "REQ-J1.1: the undeclared key is named" "mission_control_unseeded_pref"
expect_out "REQ-J1.1: the reading script is named" "scripts/mc-seeded.sh"

reset_fixture
printf 'seeded-behaviour\tmission_control_not_in_defaults\tscripts/mc-program.sh\n' >>"$core/config/mission-control-knobs.tsv"
run_fixture
expect_rc "REQ-J1.1: a behaviour whose knob the defaults lack fails" 1
expect_out "REQ-J1.1: the missing knob is named" "mission_control_not_in_defaults"

reset_fixture
printf 'seeded-behaviour\tmission_control_programs\tscripts/no-such.sh\n' >>"$core/config/mission-control-knobs.tsv"
run_fixture
expect_rc "a behaviour whose consumer does not exist fails" 1
expect_out "the missing consumer is named" "scripts/no-such.sh"

for consumer in /etc/profile ../outside.sh scripts/../../outside.sh; do
  reset_fixture
  printf 'seeded-behaviour\tmission_control_programs\t%s\n' "$consumer" >>"$core/config/mission-control-knobs.tsv"
  run_fixture
  expect_rc "a consumer outside the core root fails: $consumer" 1
  expect_out "the out-of-root consumer is refused: $consumer" "names no consumer inside the core root"
done

reset_fixture
printf '#!/bin/sh\n' >"$core/scripts/reader.sh"
printf 'seeded-behaviour\tmission_control_programs\tscripts/reader.sh\n' >>"$core/config/mission-control-knobs.tsv"
run_fixture
expect_rc "a consumer that never names its knob fails" 1
expect_out "the consumer and knob are named" "scripts/reader.sh does not read mission_control_programs"

if [ "$(id -u)" -ne 0 ]; then
  reset_fixture
  chmod 000 "$core/scripts/mc-duties.sh"
  run_fixture
  expect_rc "an unreadable scanned file is an input the check cannot read" 2
  expect_out "the unreadable file is named" "scripts/mc-duties.sh"
  chmod 644 "$core/scripts/mc-duties.sh"
fi

# REQ-J1.1: every key resolves with its default and is claimed by a behaviour.
# row <knob>: an options-reference row naming its evidence, so a case fails
# only for the defect it plants.
row() {
  # shellcheck disable=SC2016 # the backticks are the row's literal text
  printf '| `%s` | `x` | A fixture knob. Evidence: a fixture. | `scripts/mc-program.sh` |\n' "$1" >>"$core/docs/options-reference.md"
}

reset_fixture
printf 'mission_control_orphan: 3\n' >>"$core/config/defaults.yml"
row mission_control_orphan
run_fixture
expect_rc "REQ-J1.1: a knob no behaviour claims fails" 1
expect_out "REQ-J1.1: the orphan knob is reported as unclaimed" "mission_control_orphan is claimed by no behaviour"

reset_fixture
printf 'mission_control_bare:\n' >>"$core/config/defaults.yml"
printf 'bare-behaviour\tmission_control_bare\tscripts/mc-program.sh\n' >>"$core/config/mission-control-knobs.tsv"
row mission_control_bare
run_fixture
expect_rc "REQ-J1.1: a knob with no default value fails" 1
expect_out "REQ-J1.1: the default-less knob is reported as unresolved" "mission_control_bare does not resolve to a default"

# The inventory's last row counts without a trailing newline, and an empty
# knob column is a missing knob, not a shifted row.
reset_fixture
printf 'last-behaviour\t-\tscripts/mc-program.sh' >>"$core/config/mission-control-knobs.tsv"
run_fixture
expect_rc "REQ-J1.1: a knob-less last row without a newline fails" 1
expect_out "REQ-J1.1: the unterminated row's behaviour is named" "behaviour 'last-behaviour' has no knob"

reset_fixture
printf 'empty-behaviour\t\tscripts/mc-program.sh\n' >>"$core/config/mission-control-knobs.tsv"
run_fixture
expect_rc "REQ-J1.1: an empty knob column fails" 1
expect_out "REQ-J1.1: the empty knob column reads as no knob" "behaviour 'empty-behaviour' has no knob"

# REQ-J1.2: every knob has an options-reference row naming its evidence.
reset_fixture
# shellcheck disable=SC2016 # the backticks are the row's literal text
grep -v '^| `mission_control_home_root`' "$repo_root/docs/options-reference.md" >"$core/docs/options-reference.md"
run_fixture
expect_rc "REQ-J1.2: a knob with no options-reference row fails" 1
expect_out "REQ-J1.2: the undocumented knob is named" "mission_control_home_root"

reset_fixture
awk '/^\| `mission_control_home_root`/ { gsub(/Evidence:/, "Source:") } { print }' \
  "$repo_root/docs/options-reference.md" >"$core/docs/options-reference.md"
run_fixture
expect_rc "REQ-J1.2: a row that names no evidence fails" 1
expect_out "REQ-J1.2: the row without evidence is named" "mission_control_home_root"

# Usage.
run_guard --bogus
expect_rc "an unknown flag is a usage error" 2
run_guard --core "$tmp/nope"
expect_rc "a core root without config/defaults.yml is a usage error" 2

if [ "$failures" -ne 0 ]; then
  echo "test-check-mc-knobs: $failures failure(s)" >&2
  exit 1
fi
echo "test-check-mc-knobs: all passed"
