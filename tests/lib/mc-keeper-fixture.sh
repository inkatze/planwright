# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # the fixture reads `here` and `repo_root` and sets variables the sourcing suites read
# Shared fixture for the mc-keeper suites (scripts/mc-keeper.sh): the
# mission-control fixture with programs alpha and beta configured, the
# keeper's ledger path, a fake forge whose `pr view` answers come from
# $tmp/state7 and $tmp/state8, and the stream-json worker helpers the prompt
# suites share. The sourcing suite sets `here` to the tests directory and
# `repo_root` to the checkout before sourcing. Sourcing creates the scratch
# directory `tmp`, removed on exit, and exits 1 when jq is missing.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
# Fixture git calls must reach the fixture repositories, never one an
# inherited selector (a git hook's GIT_DIR, say) points at.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
ok() { printf 'ok: %s\n' "$1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-keeper.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

# The fake forge below runs the caller's own --jq.
command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required (the gh stub runs the caller's --jq)" >&2
  exit 1
}

tab=$(printf '\t')
reset_mc_fixture
cat >"$tracked" <<EOF
mission_control_programs: [alpha, beta]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo/specs
program_alpha_home: $tmp/mchome
program_alpha_budget: {host_load: 1000000}
EOF
ledger="$fleet/mission-control/alpha/keeper.tsv"

mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<EOF
#!/bin/sh
case "\$*" in
  *"pr view 7 "*) cat "$tmp/state7" ;;
  *"pr view 8 "*) cat "$tmp/state8" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
echo OPEN >"$tmp/state8"

own_worker() { # own_worker <worker> <owner>: the dispatch record's owner
  mkdir -p "$fleet/dispatch-markers"
  printf '%s\t%s\t%s\tstream-json-persistent\t%s\t-\n' "$1" "demo:task-9" "$2" "$fleet/streamjson/$1" >"$fleet/dispatch-markers/$1"
}
pp_req() { # pp_req <worker> [<owner>|-|none]: an overdue pending request under live pids, owned by alpha unless said; - a record naming no owner, none no record
  mkdir -p "$fleet/streamjson/$1"
  printf 'aaaa1111-bbbb-cccc-dddd-eeee00000001\tpermission\t1000\tpending\n' >"$fleet/streamjson/$1/journal"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/supervisor.pid"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/worker.pid"
  printf 'demo:task-9\n' >"$fleet/streamjson/$1/scope"
  [ "${2:-}" = none ] || own_worker "$1" "${2:-mission-control:alpha}"
}
pp_fresh() { # pp_fresh <worker> <request-suffix> <received> [none]: as pp_req, the request fresh; none leaves no record
  mkdir -p "$fleet/streamjson/$1"
  printf 'bbbb2222-bbbb-cccc-dddd-eeee0000000%s\tpermission\t%s\tpending\n' "$2" "$3" >"$fleet/streamjson/$1/journal"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/supervisor.pid"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/worker.pid"
  printf 'demo:task-9\n' >"$fleet/streamjson/$1/scope"
  [ "${4:-}" = none ] || own_worker "$1" mission-control:alpha
}
mc_row() { # mc_row <program> live|dead|none: the program's launched mission-control row, its stream-json pid alive or gone, or no row
  mr_n="mc-$1-mission-control-00000000aa"
  rm -rf "$fleet/mission-control/sessions/$mr_n" "$fleet/streamjson/$mr_n"
  [ "$2" != none ] || return 0
  mkdir -p "$fleet/mission-control/sessions" "$fleet/streamjson/$mr_n"
  printf 'format\t1\nname\t%s\nstate\tlaunched\nprogram\t%s\nkind\tmission-control\nscope\tx\nbackend\tstream-json\nhandle\t%s\nlaunched\t1\n' \
    "$mr_n" "$1" "$mr_n" >"$fleet/mission-control/sessions/$mr_n"
  if [ "$2" = live ]; then
    printf '%s\n' "$$" >"$fleet/streamjson/$mr_n/worker.pid"
  else
    printf '999999999\n' >"$fleet/streamjson/$mr_n/worker.pid"
  fi
}
keeper_as() { # keeper_as <program> <now>: one watch pass as that program
  OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM="$1" /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now "$2" 2>/dev/null)
}
