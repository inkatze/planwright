# shellcheck shell=bash
# Shared fixture for the autonomy tests (decisions, calibration, proposals,
# shadow mode, the self-audit): program alpha with its home under $tmp, the
# fixture core duties plus gamma-duty in shadow from the repo-tracked
# overlay, and an initialized knowledge base.
#
# Source after tests/lib/mission-control-fixture.sh. After sourcing:
#   $home, $kb      the program home and its knowledge base
#   seg_write <log> <YYYY-MM> [<entry line>...]
#                   a hand-written past segment, for entries whose time a
#                   test controls (readers check the format line only)
#   iso_epoch <ISO> the epoch of a UTC YYYY-MM-DDTHH:MM:SSZ time

: "${tmp:?}" "${repo:?}" "${tracked:?}"

home="$tmp/mc-home/alpha"
kb="$home/kb"

reset_mc_fixture
mkdir -p "$repo/specs"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo/specs
program_alpha_home: $home
program_alpha_duties: [alpha-duty, beta-duty, gamma-duty]
EOF
cat >"$repo/.claude/catalogs/duties.yaml" <<'EOF'
---
duties:
  - id: gamma-duty
    summary: "A custom duty earning trust in shadow"
    triggers: []
    watchers: []
    wake: none
    rules: []
    kinds: [gamma-item]
    files: gamma
    lifecycle: shadow
    never-propose: false
EOF
mc_run mc-kb.sh init --program alpha
if [ "$RC" -ne 0 ]; then
  printf '%s\n' "FAIL: the fixture knowledge base did not initialize" "$ERR" >&2
  exit 1
fi

seg_write() { # seg_write <log> <YYYY-MM> [<entry line>...]
  sw_f="$kb/$1-$2.log"
  shift 2
  {
    printf '# format: 1\n'
    for sw_l in "$@"; do printf '%s\n' "$sw_l"; done
  } >"$sw_f"
}

iso_epoch() {
  date -u -d "$1" '+%s' 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" '+%s'
}
