# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # shared with the sourcing suite, both ways
# Shared fixture for the scripts/mc-handover.sh suites: two configured
# programs (alpha and beta) over the mission-control fixture, a CLI shim the
# stream-json rung launches successors against, and the runners and readers
# the suites assert with. The sourcing suite sets `here`, `repo_root` and
# `suite` (its scratch prefix) and defines fail() and ok() first.

for t in jq git; do
  command -v "$t" >/dev/null 2>&1 || {
    echo "FAIL: $t is required to run this suite" >&2
    exit 1
  }
done
[ -f "$repo_root/scripts/mc-handover.sh" ] || {
  echo "FAIL: scripts/mc-handover.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/$suite.XXXXXX") || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
tmp=$(cd "$tmp" && pwd -P) || exit 1
fleet="$tmp/fleet"
cleanup() {
  for d in "$fleet"/streamjson/*/; do
    [ -d "$d" ] || continue
    env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-streamjson.sh" \
      stop "$(basename "$d")" --grace 1 >/dev/null 2>&1 || :
  done
  rm -rf "$tmp"
}
trap cleanup EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"
reset_mc_fixture
cp "$repo_root/config/defaults.yml" "$core/config/defaults.yml"
for p in worker tower mission-control; do
  cp "$repo_root/config/$p-settings.json" "$core/config/"
done
mkdir -p "$repo/specs" "$fleet" "$tmp/bin"
home="$tmp/mc-home/alpha"
bhome="$tmp/mc-home/beta"
cat >"$tracked" <<EOF
mission_control_programs: [alpha, beta]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo/specs
program_alpha_home: $home
program_alpha_duties: [alpha-duty]
program_beta_repositories: [$repo]
program_beta_spec_root: $repo/specs
program_beta_home: $bhome
program_beta_duties: [alpha-duty]
EOF
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
IFS= read -r line || line=''
exit 0
SHIM
chmod +x "$tmp/bin/claude"

# run <script> <args...>: against the fixture, the shim on PATH. Sets RC,
# OUT, ERR.
run() {
  r_script=$1
  shift
  OUT=$(cd "$repo" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_SKILLS_ROOT \
    -u PLANWRIGHT_CONFIG_DEFAULTS -u PLANWRIGHT_REPO_ROOT_CHECKED -u PLANWRIGHT_CONFIG_STRICT_OVERLAYS \
    -u XDG_CONFIG_HOME -u TMUX -u TMUX_PANE -u PLANWRIGHT_MC_CHECKED -u PLANWRIGHT_MC_PROGRAM \
    -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE -u PLANWRIGHT_TOWER_ID \
    PATH="$tmp/bin:$PATH" PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" PLANWRIGHT_LOCAL_CONFIG="$tmp/absent.yml" \
    CLAUDE_DIR="$tmp/claude" HOME="$fixhome" PLANWRIGHT_FLEET_STATE_DIR="$fleet" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT=off \
    /bin/bash "$repo_root/scripts/$r_script" "$@" 2>"${RUN_ERR:-$tmp/stderr}")
  RC=$?
  ERR=$(cat "${RUN_ERR:-$tmp/stderr}")
}
ho() { run mc-handover.sh "$@"; }
col() { printf '%s\n' "$OUT" | awk -F '\t' -v k="$1" -v c="$2" '$1 == k { print $c; exit }'; }
rowfile() { printf '%s\n' "$fleet/mission-control/sessions/$1"; }
# wait_done <name>: until the shim's supervisor has recorded the run's end.
wait_done() {
  n=0
  until [ -s "$fleet/streamjson/$1/result" ] || [ "$n" -ge 100 ]; do
    sleep 0.1
    n=$((n + 1))
  done
}
holder_is() { # holder_is <label> <handle> [<program>]
  ho holder --program "${3:-alpha}"
  if [ "$(col holder 2)" = "$2" ]; then ok "$1"; else fail "$1: the holder is '$(col holder 2)', not $2"; fi
}
events_of() { # events_of <kind> [<program>]: the program's events of that kind
  run mc-event.sh list --program "${2:-alpha}"
  printf '%s\n' "$OUT" | awk -F '\t' -v k="$1" '$3 == k'
}
count_of() { events_of "$@" | grep -c .; }
printf '%s\n' "# Mission control" "" "Run program alpha." >"$tmp/brief.md"
