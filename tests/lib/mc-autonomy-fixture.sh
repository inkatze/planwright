# shellcheck shell=bash
# Shared fixture for the autonomy tests, sourced after
# tests/lib/mission-control-fixture.sh: program alpha, its home ($home) and
# initialized knowledge base ($kb), and gamma-duty in shadow from the
# repo-tracked overlay. seg_write hand-writes a past segment for entries
# whose time a test controls (readers check only its format line).

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
  # GNU, busybox (which rejects the trailing Z without -D), then BSD.
  date -u -d "$1" '+%s' 2>/dev/null \
    || date -u -D '%Y-%m-%dT%H:%M:%SZ' -d "$1" '+%s' 2>/dev/null \
    || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" '+%s'
}
