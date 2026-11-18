# shellcheck shell=bash
# shellcheck disable=SC2034,SC2329 # tab, H and mchome are read by the sourcing test
# Shared fixture for the mc-readiness tests: the failure counter, the scratch
# tree, the mission-control fixture with program alpha over the fixture
# repository, and the evidence helpers complete and walk_with. The sourcing
# test sets here and repo_root first.

: "${here:?set here before sourcing}" "${repo_root:?set repo_root before sourcing}"

# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-readiness.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
# A run stopped while a directory is mode-restricted must still clean up.
trap 'chmod -R u+rwX "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
trap 'exit 143' HUP INT TERM

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
{
  printf 'ready_flip_policy: unit-owner\n'
  grep '^steps_' "$repo_root/config/defaults.yml"
} | write_core_defaults
# The configured cadence the audit resolves: the core steps catalog, with a
# stand-in for the polish skill its default convergence names.
cp "$repo_root/config/steps.yaml" "$core/config/steps.yaml"
mkdir -p "$core/skills/polish"
printf -- '---\nname: polish\ndescription: fixture stand-in\n---\n' >"$core/skills/polish/SKILL.md"
mchome="$tmp/mchome"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_home: $mchome
program_alpha_sources: {code-state: forge:snapshot}
EOF
mkdir -p "$mchome"
printf '# format: 1\nready\tprogram\t*\tsteps\tpolish\nready\tlabel\tui\tevidence\tscreenshot\nready\tprogram\t*\tbody\t## Summary\n' >"$mchome/gates.tsv"

H=1111111111111111111111111111111111111111
complete() {
  cat <<EOF
# format: 1
head	$H
repo	acme/web
label	ui
path	src/app.c
check	build	SUCCESS
check	lint	NEUTRAL
thread	t1	resolved
finding	cubic-dev-ai[bot]	t2	answered
step	polish	applied	$H
cadence	audited	$H
evidence	screenshot	shots/home.png	$H	ok
guard	ready-guard	pass	-
bodyline	## Summary
bodyline	Adds the thing.
EOF
}
walk_with() { # walk_with <label> <sed expression or -> [extra line]
  complete >"$tmp/ev"
  [ "$2" = - ] || sed -i.bak "$2" "$tmp/ev"
  [ -z "${3:-}" ] || printf '%s\n' "$3" >>"$tmp/ev"
  mc_run mc-readiness.sh walk --program alpha --evidence "$tmp/ev"
}
