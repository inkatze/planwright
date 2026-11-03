#!/bin/bash
# Structural guard over mission control's doctrine and operator docs
# (mission-control D-1, D-19; REQ-A1.6).
#
# Each property is probed against a violating sample at the end:
#   - doctrine/mission-control.md holds a section per concept it owns;
#   - every mission-control glossary term in doctrine/spec-format.md links
#     to a section of that doc that exists;
#   - docs/mission-control.md walks a fresh installation end to end with no
#     word the register forbids: both jargon lists, identifier and file
#     shapes, configuration keys, and any command but the operator's own.
set -u
LC_ALL=C
export LC_ALL
set -f
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
doctrine="$REPO_ROOT/doctrine/mission-control.md"
glossary="$REPO_ROOT/doctrine/spec-format.md"
opdoc="$REPO_ROOT/docs/mission-control.md"
tower_list="$REPO_ROOT/scripts/tower-jargon.txt"
mc_list="$REPO_ROOT/scripts/mission-control-jargon.txt"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
ok() { printf 'ok: %s\n' "$1"; }

for f in "$doctrine" "$glossary" "$opdoc" "$tower_list" "$mc_list"; do
  [ -f "$f" ] || fail "${f#"$REPO_ROOT"/} is missing"
done
[ "$failures" -eq 0 ] || exit 1

# slugs <file>: the GitHub heading slug of every heading, one per line.
slugs() {
  awk '/^```/ { fence = !fence; next } !fence && /^#+ / { sub(/^#+ +/, ""); sub(/[ \t]+$/, ""); print }' "$1" \
    | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 _-]//g; s/ /-/g'
}

# The concepts the doctrine doc owns, each a section of its own.
doc_sections="the-session-kind launch-kinds the-program-and-its-home
the-state-source-map the-format-field the-reclaim-folder the-rule-store
the-duty-contract shadow-mode the-mechanism-inventory mechanization-proposals
cadence-steps the-register-delta autonomy-at-this-tier the-handover-file
the-floors-by-reference"

# check_sections <doc>: prints each owned section the doc lacks.
check_sections() {
  have=$(slugs "$1")
  for s in $doc_sections; do
    printf '%s\n' "$have" | grep -qx "$s" || printf '%s\n' "$s"
  done
}

# The glossary terms Task 13 names, matched against a `- **<term>**` bullet
# in the glossary (case-folded); each bullet must link a section of
# mission-control.md that exists.
terms="mission control|program|program home|duty|rule store|state-source map|mechanism inventory|mechanization proposal|shadow mode|reclaim folder|cadence step|format field|handover file|launch kinds"

# check_glossary <glossary> <doctrine>: prints each term whose bullet is
# missing, links no section, or links a section that does not exist.
check_glossary() {
  have=$(slugs "$2")
  section=$(awk '/^## Glossary$/ { f = 1; next } /^## / { f = 0 } f' "$1")
  bullets=$(printf '%s\n' "$section" | awk '
    /^- / { if (b != "") print b; b = $0; next }
    /^  / && b != "" { sub(/^ +/, " "); b = b $0; next }
    { if (b != "") print b; b = "" }
    END { if (b != "") print b }')
  old_ifs=$IFS
  IFS='|'
  for t in $terms; do
    IFS=$old_ifs
    line=$(printf '%s\n' "$bullets" | awk -v t="$t" '
      { head = $0; sub(/^- \*\*/, "", head); sub(/\*\*.*/, "", head)
        if (tolower(head) == t) { print; exit } }')
    if [ -z "$line" ]; then
      printf '%s: no glossary bullet\n' "$t"
      continue
    fi
    anchors=$(printf '%s\n' "$line" | grep -oE 'mission-control\.md#[a-z0-9_-]+' | sed 's/.*#//')
    if [ -z "$anchors" ]; then
      printf '%s: links no section of mission-control.md\n' "$t"
      continue
    fi
    for a in $anchors; do
      printf '%s\n' "$have" | grep -qx "$a" || printf '%s: links missing section #%s\n' "$t" "$a"
    done
  done
  IFS=$old_ifs
}

# norm: lowercase, every run of non-alphanumerics one space, padded, so a
# term matches on word boundaries and a hyphen reads as a space.
norm() { tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/ /g; s/^/ /; s/$/ /'; }

# visible <doc>: the doc's text with link targets dropped, so a link to a
# reference page is not read as a file name said to the operator.
visible() { sed 's/](\([^)]*\))/]/g' "$1"; }

# check_register <doc>: prints each forbidden word or shape the doc carries.
check_register() {
  text=$(visible "$1")
  flat=$(printf '%s\n' "$text" | tr '\n' ' ' | norm)
  grep -hvE '^(#|$)' "$tower_list" "$mc_list" | while IFS= read -r w; do
    n=$(printf '%s\n' "$w" | norm)
    case $flat in *"$n"*) printf 'word: %s\n' "$w" ;; esac
  done
  printf '%s\n' "$text" | grep -oE 'REQ-[A-Z][0-9.]*|(^|[^A-Za-z0-9-])D-[0-9]+|Task [0-9]+' | sed 's/^[^RDT]//' | sort -u | sed 's/^/identifier: /'
  printf '%s\n' "$text" | grep -oE '[A-Za-z0-9_./-]*\.(sh|yml|yaml|json|tsv|md|txt|toml)([^A-Za-z0-9]|$)|scripts/[A-Za-z0-9_.-]*' | sort -u | sed 's/^/file: /'
  printf '%s\n' "$text" | grep -oE '[a-z]+_[a-z_]+' | sort -u | sed 's/^/configuration key: /'
  printf '%s\n' "$text" | grep -oE '(^|[^A-Za-z0-9_./-])/[a-z][a-z0-9:-]*' | sed 's/^[^/]//' \
    | grep -vx '/mission-control' | sort -u | sed 's/^/command: /'
}

# The walk a fresh installation takes, each a section of the operator doc.
op_sections="first-run state-sources duties proposals preferences resume handover"

check_walk() {
  have=$(slugs "$1")
  for s in $op_sections; do
    printf '%s\n' "$have" | grep -q "^$s" || printf 'section: %s\n' "$s"
  done
  flat=$(tr '\n' ' ' <"$1" | norm)
  for step in "repositories" "where your specs live" "signed in" "where the state" "duties" "quiet hours"; do
    n=$(printf '%s\n' "$step" | norm)
    case $flat in *"$n"*) ;; *) printf 'first-run step: %s\n' "$step" ;; esac
  done
}

report() { # report <label> <output>
  if [ -z "$2" ]; then
    ok "$1"
  else
    printf '%s\n' "$2" | while IFS= read -r l; do printf 'FAIL: %s: %s\n' "$1" "$l" >&2; done
    failures=$((failures + 1))
  fi
}

# REQ-A1.6 (design-level): the doctrine doc, the glossary and the walk.
report "D-1: the doctrine doc holds a section per concept it owns" "$(check_sections "$doctrine")"
report "REQ-A1.6: each mission-control glossary term links a section of the doctrine doc" "$(check_glossary "$glossary" "$doctrine")"
report "REQ-A1.6: the operator doc walks a fresh installation end to end" "$(check_walk "$opdoc")"
report "D-19: the operator doc carries no word the register forbids" "$(check_register "$opdoc")"

# The indexes name both docs.
if grep -qF '](docs/mission-control.md)' "$REPO_ROOT/README.md"; then ok "README links the operator doc"; else fail "README does not link docs/mission-control.md"; fi
# shellcheck disable=SC2016 # backticks are literal markdown, never expanded
if grep -qE '^\|.*\| `/mission-control` \|' "$REPO_ROOT/README.md"; then ok "README's command table lists /mission-control"; else fail "README's command table lacks /mission-control"; fi
if grep -qF '| [mission-control.md](mission-control.md) |' "$REPO_ROOT/doctrine/README.md"; then ok "the doctrine index has a mission-control row"; else fail "the doctrine index lacks a mission-control row"; fi

# Probes: each check fails on a violating sample.
probe=$(mktemp -d "${TMPDIR:-/tmp}/mc-docs-probe.XXXXXX") || exit 2
trap 'rm -rf "$probe"' EXIT
printf '# X\n\n## The session kind\n' >"$probe/doctrine.md"
if [ -n "$(check_sections "$probe/doctrine.md")" ]; then ok "probe: a missing section is caught"; else fail "probe: a missing section passed"; fi
printf '## Glossary\n\n- **Duty** a thing, see\n  [x](mission-control.md#no-such-section).\n- **Program** no link.\n' >"$probe/glossary.md"
out=$(check_glossary "$probe/glossary.md" "$doctrine")
case $out in *"duty: links missing section"*) ok "probe: a dangling glossary anchor is caught" ;; *) fail "probe: a dangling glossary anchor passed" ;; esac
case $out in *"program: links no section"*) ok "probe: an unlinked glossary term is caught" ;; *) fail "probe: an unlinked glossary term passed" ;; esac
case $out in *"rule store: no glossary bullet"*) ok "probe: a missing glossary term is caught" ;; *) fail "probe: a missing glossary term passed" ;; esac
for bad in "The orchestrator starts." "A visual flight lands." "See Task 4." "Per D-19." "Run mc-config.sh." "Set mission_control_guidance." "Type /spec-kickoff." "Say \"/resume\"." "The kickoff brief." "Open handover.md."; do
  printf '%s\n' "$bad" >"$probe/op.md"
  if [ -n "$(check_register "$probe/op.md")" ]; then ok "probe: '$bad' is caught"; else fail "probe: '$bad' passed the register"; fi
done
# shellcheck disable=SC2016 # backticks are literal markdown, never expanded
printf 'Type `/mission-control`; see [the reference](options-reference.md).\n' >"$probe/op.md"
if [ -z "$(check_register "$probe/op.md")" ]; then ok "probe: the operator's own command and a link target pass"; else fail "probe: a clean line was refused"; fi
printf '## First run\n' >"$probe/op.md"
if [ -n "$(check_walk "$probe/op.md")" ]; then ok "probe: a short walk is caught"; else fail "probe: a short walk passed"; fi

if [ "$failures" -ne 0 ]; then
  printf '%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all mission-control docs checks passed\n'
