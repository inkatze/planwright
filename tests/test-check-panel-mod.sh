#!/bin/bash
# Tests for scripts/check-panel-mod.sh, the panel mod's gate (mission-control
# Task 7; REQ-F1.1, REQ-F1.2; D-6): the mods floor, the engine surface held
# to config/panel-mod-surface.txt, an empty or red plugin-test run, and the
# seeded drawing defect the suite must fail on.
#
# A fake claude on PATH answers --version, `plugin validate --json` and
# `plugin test` from fixtures, so this runs where the real CLI is absent;
# CI's lint job runs the gate itself against the real one.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-check-panel-mod.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
check=$repo_root/scripts/check-panel-mod.sh

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$check" ] || {
  echo "FAIL: scripts/check-panel-mod.sh missing" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# A fixture plugin root: the shipped surface list and a copy of the mod's
# files, which the gate copies again to seed its defect.
plug=$tmp/plugin
mkdir -p "$plug/.claude-plugin" "$plug/hooks" "$plug/config"
cp "$repo_root/config/panel-mod-surface.txt" "$plug/config/"
cp "$repo_root/.claude-plugin/plugin.json" "$plug/.claude-plugin/"
cp "$repo_root/hooks/mods.json" "$plug/hooks/"
cp -R "$repo_root/hooks/mission-control" "$plug/hooks/"
cp -R "$repo_root/types" "$plug/"

# The fake CLI. FAKE_VERSION sets the version; FAKE_CALLS the calls the
# report lists; FAKE_PASS and FAKE_FAIL the summary of a clean run;
# FAKE_SEED_CAUGHT=0 lets a seeded copy pass.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/claude" <<'EOF'
#!/bin/sh
case "$1 ${2:-}" in
  "--version ") echo "${FAKE_VERSION:-2.1.310} (Claude Code)" ;;
  "plugin validate")
    m="./mission-control/register.tsx"
    printf '{"success": true, "contents": [{"type": "hooks", "notes": [%s, %s, %s, %s]}]}\n' \
      "\"$m hooks: session.start, ui.render{component=Pane, requestId=mission-control}\"" \
      "\"$m calls: ${FAKE_CALLS:-\$.process.run (via run), \$.ui.resolve}\"" \
      "\"$m env reads: PLANWRIGHT_MC_PROGRAM\"" \
      "\"$m env writes: nothing\""
    ;;
  "plugin test")
    if grep -q seededDefect "$3/hooks/mission-control/panel.tsx" && [ "${FAKE_SEED_CAUGHT:-1}" = 1 ]; then
      printf ' 19 pass\n 6 fail\n'
      exit 1
    fi
    printf ' %s pass\n %s fail\n' "${FAKE_PASS:-25}" "${FAKE_FAIL:-0}"
    [ "${FAKE_FAIL:-0}" = 0 ] || exit 1
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$tmp/bin/claude"

run() { # run [VAR=value...]: the gate under the fake CLI; sets RC, OUT, ERR
  OUT=$(env PATH="$tmp/bin:$PATH" "$@" /bin/bash "$check" --root "$plug" 2>"$tmp/err")
  RC=$?
  ERR=$(cat "$tmp/err")
}
rc_is() { # rc_is <label> <want>
  if [ "$RC" -eq "$2" ]; then
    ok "$1"
  else
    fail "$1: exit $RC, $ERR"
  fi
}
has() { # has <label> <text> <needle>
  case $2 in
    *"$3"*) ok "$1" ;;
    *) fail "$1: no '$3' in: $2" ;;
  esac
}

run
rc_is "a clean mod passes (exit 0)" 0
has "the clean run counts its tests" "$OUT" "25 plugin tests passed on claude 2.1.310"
has "the clean run proves the seed is caught" "$OUT" "the seeded drawing defect fails the suite"

run FAKE_VERSION=2.1.286
rc_is "below the floor fails" 1
has "the floor is named" "$ERR" "below the mods floor 2.1.287"

run FAKE_VERSION=2.2.0
rc_is "a later minor passes the floor" 0

run 'FAKE_CALLS=$.process.run (via run), $.ui.resolve, $.http.fetch'
rc_is "a call the design does not name fails" 1
has "the extra call is named" "$ERR" 'uses call $.http.fetch'

run FAKE_PASS=0
rc_is "a run that executed no test fails" 1
has "the empty run is named" "$ERR" "ran no test"

run FAKE_FAIL=2 FAKE_PASS=23
rc_is "a red suite fails" 1

run FAKE_SEED_CAUGHT=0
rc_is "a suite blind to the seeded defect fails" 1
has "the blind suite is named" "$ERR" "passed over a seeded drawing defect"

sed 's/<Box flexDirection="column"/<Box flexDirection="row"/g' "$repo_root/hooks/mission-control/panel.tsx" \
  >"$plug/hooks/mission-control/panel.tsx"
run
rc_is "a seed that cannot apply fails" 1
has "the unapplied seed is named" "$ERR" "seeded defect did not apply"
cp "$repo_root/hooks/mission-control/panel.tsx" "$plug/hooks/mission-control/panel.tsx"

OUT=$(env PATH="/usr/bin:/bin" /bin/bash "$check" --root "$plug" 2>&1)
RC=$?
rc_is "without the CLI the gate skips (exit 0)" 0
has "the skip is said" "$OUT" "not on PATH; skipping"

OUT=$(/bin/bash "$check" --root "$tmp/absent" 2>&1)
RC=$?
rc_is "a missing root is a usage error" 2

if [ "$failures" -ne 0 ]; then
  echo "test-check-panel-mod: $failures failure(s)" >&2
  exit 1
fi
echo "test-check-panel-mod: all passed"
