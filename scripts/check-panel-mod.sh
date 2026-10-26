#!/usr/bin/env bash
# check-panel-mod.sh — the panel mod's gate: the CLI at or above the mods
# floor, the engine surface `claude plugin validate` reports held to
# config/panel-mod-surface.txt, the plugin tests run and green, and the
# suite shown to fail on a seeded drawing defect. Without the claude CLI it
# skips with a note (CI's lint job installs one); a CLI below the floor fails.
#
# Usage: check-panel-mod.sh [--root <dir>]   (default: this checkout)
# Exit codes: 0 clean or skipped; 1 a finding; 2 usage or an unreadable
# input. Portable bash 3.2 / BSD tooling.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

# The lowest Claude Code release whose mods API the panel mod runs on.
FLOOR=2.1.287
MOD=hooks/mission-control/register.tsx

prog=check-panel-mod
root=""
if [ $# -eq 2 ] && [ "$1" = --root ]; then
  root=$2
elif [ $# -ne 0 ]; then
  echo "usage: $prog [--root <dir>]" >&2
  exit 2
fi
[ -n "$root" ] || root=$(cd "$(dirname "$0")/.." && pwd -P) || exit 2
[ -d "$root" ] || {
  echo "$prog: no such directory: $root" >&2
  exit 2
}
root=$(cd "$root" && pwd -P) || exit 2
surface=$root/config/panel-mod-surface.txt
[ -r "$surface" ] || {
  echo "$prog: cannot read $surface" >&2
  exit 2
}

if ! command -v claude >/dev/null 2>&1; then
  echo "$prog: 'claude' CLI not on PATH; skipping the panel mod's plugin tests and surface check"
  exit 0
fi
command -v jq >/dev/null 2>&1 || {
  echo "$prog: jq is not on PATH, so the validate report cannot be read" >&2
  exit 2
}

scratch=$(mktemp -d) || exit 2
trap 'rm -rf "$scratch"' EXIT
findings=0
finding() {
  echo "$prog: $1" >&2
  findings=$((findings + 1))
}

# 1. The floor.
version=$(claude --version 2>/dev/null | awk 'NR == 1 { print $1 }')
if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  finding "cannot read the claude CLI's version ('$version')"
elif ! V=$version F=$FLOOR awk 'BEGIN {
    split(ENVIRON["V"], v, "."); split(ENVIRON["F"], f, ".")
    for (i = 1; i <= 3; i++) { if (v[i] + 0 > f[i] + 0) exit 0; if (v[i] + 0 < f[i] + 0) exit 1 }
    exit 0 }'; then
  finding "the claude CLI is $version, below the mods floor $FLOOR"
fi

# 2. The surface: every hook, call and environment read the report lists
# must be one config/panel-mod-surface.txt names.
if ! claude plugin validate "$root/.claude-plugin/plugin.json" --json >"$scratch/report.json" 2>"$scratch/validate.err"; then
  finding "claude plugin validate failed on the manifest"
  sed -n '1,20p' "$scratch/validate.err" >&2
fi
if ! jq -r --arg mod "./${MOD#hooks/}" '
    .contents[] | select(.type == "hooks") | .notes[]
    | select(startswith($mod + " "))
    | ltrimstr($mod + " ")' "$scratch/report.json" >"$scratch/notes" 2>/dev/null; then
  finding "the validate report could not be read"
fi
# hooks: a, b{x=1, y=2}, c   ->  one entry per line, commas inside braces kept.
awk '
  function emit(kind, list,   i, c, depth, cur) {
    depth = 0; cur = ""
    for (i = 1; i <= length(list); i++) {
      c = substr(list, i, 1)
      if (c == "{") depth++
      if (c == "}") depth--
      if (c == "," && depth == 0) { sub(/^ +/, "", cur); print kind " " cur; cur = ""; continue }
      cur = cur c
    }
    sub(/^ +/, "", cur); if (cur != "" && cur != "nothing") print kind " " cur
  }
  /^hooks: / { emit("hook", substr($0, 8)) }
  /^calls: / { l = substr($0, 8); gsub(/ \(via [^)]*\)/, "", l); emit("call", l) }
  /^env reads: / { emit("env", substr($0, 12)) }
  /^env writes: / { emit("envwrite", substr($0, 13)) }
' "$scratch/notes" | sort -u >"$scratch/reported"
grep -Ev '^[[:space:]]*(#|$)' "$surface" | sort -u >"$scratch/allowed"
if [ ! -s "$scratch/reported" ]; then
  finding "the validate report names no hook or call for $MOD (is the module still listed?)"
fi
comm -23 "$scratch/reported" "$scratch/allowed" >"$scratch/extras"
while IFS= read -r extra; do
  finding "$MOD uses $extra, which config/panel-mod-surface.txt does not name"
done <"$scratch/extras"
comm -13 "$scratch/reported" "$scratch/allowed" | while IFS= read -r stale; do
  echo "$prog: warning: config/panel-mod-surface.txt names $stale, which the module no longer uses" >&2
done

# run_tests <dir> <log>: the plugin tests; prints `<exit> <pass> <fail>`.
run_tests() {
  claude plugin test "$1" >"$2" 2>&1
  rt_rc=$?
  rt_pass=$(awk '$2 == "pass" && $1 ~ /^[0-9]+$/ { n = $1 } END { print n + 0 }' "$2")
  rt_fail=$(awk '$2 == "fail" && $1 ~ /^[0-9]+$/ { n = $1 } END { print n + 0 }' "$2")
  printf '%s %s %s\n' "$rt_rc" "$rt_pass" "$rt_fail"
}

# 3. The suite, green and not empty.
read -r t_rc t_pass t_fail <<EOF
$(run_tests "$root" "$scratch/tests.log")
EOF
if [ "$t_rc" -ne 0 ] || [ "$t_fail" -ne 0 ]; then
  finding "the plugin tests failed (exit $t_rc, $t_pass pass, $t_fail fail)"
  sed -n '1,80p' "$scratch/tests.log" >&2
elif [ "$t_pass" -eq 0 ]; then
  finding "the plugin tests ran no test (a green run that executed nothing)"
else
  echo "$prog: $t_pass plugin tests passed on claude $version"
fi

# 4. A seeded drawing defect: a prop no surface takes on the pane's boxes,
# run against the drawing tests alone.
seed=$scratch/seeded
mkdir -p "$seed/.claude-plugin" "$seed/hooks" "$seed/config"
if ! { cp "$root/.claude-plugin/plugin.json" "$seed/.claude-plugin/" \
  && cp "$root/hooks/mods.json" "$seed/hooks/" \
  && mkdir -p "$seed/hooks/mission-control" \
  && cp "$root/hooks/mission-control"/*.ts "$root/hooks/mission-control"/*.tsx "$seed/hooks/mission-control/" \
  && rm -f "$seed/hooks/mission-control/wake.test.tsx" "$seed/hooks/mission-control/compaction.test.tsx" \
  && cp -R "$root/types" "$seed/"; }; then
  echo "$prog: cannot copy the mod to seed a defect" >&2
  exit 2
fi
sed 's/<Box flexDirection="column"/<Box flexDirection="column" seededDefect="1"/' \
  "$root/hooks/mission-control/panel.tsx" >"$seed/hooks/mission-control/panel.tsx"
if cmp -s "$root/hooks/mission-control/panel.tsx" "$seed/hooks/mission-control/panel.tsx"; then
  finding "the seeded defect did not apply (panel.tsx has no column Box to seed)"
else
  read -r s_rc s_pass s_fail <<EOF
$(run_tests "$seed" "$scratch/seeded.log")
EOF
  if [ "$s_rc" -eq 0 ] && [ "$s_fail" -eq 0 ]; then
    finding "the plugin tests passed over a seeded drawing defect, so they would not catch one"
  elif [ "$s_fail" -eq 0 ] || [ "$s_pass" -eq 0 ]; then
    # Failing for another reason (nothing ran, or nothing loaded) proves
    # nothing about drawing defects.
    finding "the seeded run failed without failing a drawing test (exit $s_rc, $s_pass pass, $s_fail fail)"
    sed -n '1,40p' "$scratch/seeded.log" >&2
  else
    echo "$prog: the seeded drawing defect fails the suite ($s_fail of $((s_pass + s_fail)) tests)"
  fi
fi

if [ "$findings" -ne 0 ]; then
  echo "$prog: $findings finding(s)" >&2
  exit 1
fi
echo "$prog: the panel mod is clean"
