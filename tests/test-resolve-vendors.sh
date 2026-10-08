#!/bin/bash
# Tests for scripts/resolve-vendors.sh: the vendors catalog merged through
# scripts/resolve-catalog.sh, validated entry by entry under the by-layer
# malformed policy, and grouped by vendor (quota-handling REQ-C1.1,
# REQ-C1.5, REQ-C1.6). Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RV="$REPO_ROOT/scripts/resolve-vendors.sh"
TAB=$(printf '\t')

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
# verdict <ok> <fail>: judged on the exit status of the command before it.
verdict() {
  vr=$?
  if [ "$vr" -eq 0 ]; then ok "$1"; else fail "$2"; fi
}
assert_rc() {
  if [ "$2" -eq "$3" ]; then ok "$1"; else fail "$1 (expected exit $2, got $3)"; fi
}
assert_contains() {
  case "$3" in
    *"$2"*) ok "$1" ;;
    *) fail "$1 (expected to find '$2' in: $3)" ;;
  esac
}
assert_absent() {
  case "$3" in
    *"$2"*) fail "$1 (did not expect '$2' in: $3)" ;;
    *) ok "$1" ;;
  esac
}

[ -f "$RV" ] || {
  echo "FAIL: resolver script missing at $RV" >&2
  exit 1
}

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

base() {
  env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    -u PLANWRIGHT_ADOPTER_OVERLAY -u CLAUDE_PLUGIN_DATA \
    -u PLANWRIGHT_REPO_ROOT -u HOME "$@"
}

# rv <sandbox> <args...>: run the resolver with the four layer roots wired to
# the sandbox; stdout to $sb/out, stderr to $sb/err, exit status in RC.
rv() {
  sb="$1"
  shift
  mkdir -p "$sb/core/scripts" "$sb/repo"
  [ -d "$sb/repo/.git" ] || GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$sb/repo"
  RC=0
  base PLANWRIGHT_ROOT="$sb/core" PLANWRIGHT_ADOPTER_OVERLAY="$sb/adopter" \
    PLANWRIGHT_REPO_ROOT="$sb/repo" /bin/bash "$RV" "$@" >"$sb/out" 2>"$sb/err" || RC=$?
  OUT=$(cat "$sb/out")
  ERR=$(cat "$sb/err")
}

core_cat() { echo "$1/core/config/vendors.yaml"; }
adopter_cat() { echo "$1/adopter/catalogs/vendors.yaml"; }
repo_cat() { echo "$1/repo/.claude/catalogs/vendors.yaml"; }
local_cat() { echo "$1/repo/.claude/catalogs.local/vendors.yaml"; }

# put <path>: write stdin as a catalog file.
put() {
  mkdir -p "$(dirname "$1")"
  cat >"$1"
}

# A minimal valid core seed, used as the floor for overlay cases.
seed() {
  put "$(core_cat "$1")" <<'YAML'
vendors:
  - id: claude.vendor
    vendor: claude
    part: vendor
    evidence: claude-frames
  - id: claude.first
    vendor: claude
    part: recognizer
    match: first refusal text
  - id: claude.second
    vendor: claude
    part: recognizer
    match: second refusal text
    reset-after: "resets "
YAML
}

# ---------------------------------------------------------------------------
# REQ-C1.6: the shipped core layer holds exactly one vendor, claude.
# ---------------------------------------------------------------------------
sb="$tmp/shipped"
mkdir -p "$sb/repo"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$sb/repo"
RC=0
OUT=$(base PLANWRIGHT_ROOT="$REPO_ROOT" PLANWRIGHT_ADOPTER_OVERLAY="$sb/adopter" \
  PLANWRIGHT_REPO_ROOT="$sb/repo" /bin/bash "$RV" 2>"$sb/err") || RC=$?
assert_rc "shipped catalog resolves" 0 "$RC"
vendors=$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "vendor" { print $2 }')
[ "$vendors" = claude ]
verdict "the core layer ships exactly one vendor, claude" "core vendors are '$vendors', expected only claude"
printf '%s\n' "$OUT" | grep -q "^vendor${TAB}claude${TAB}claude-frames${TAB}-\$"
verdict "claude declares the claude-frames evidence kind" "claude vendor line: $OUT"
printf '%s\n' "$OUT" | grep -q "^recognizer${TAB}claude${TAB}"
verdict "claude ships at least one recognizer" "no claude recognizer: $OUT"
warned=$(cat "$sb/err")
[ -z "$warned" ]
verdict "the shipped catalog resolves without a warning" "shipped catalog warned: $warned"

# ---------------------------------------------------------------------------
# REQ-C1.1: an adapter resolves across all four layers, with provenance.
# ---------------------------------------------------------------------------
sb="$tmp/layers"
seed "$sb"
put "$(adopter_cat "$sb")" <<'YAML'
vendors:
  - id: sample-reviewer.vendor
    vendor: sample-reviewer
    part: vendor
    evidence: none
    bot-login: sample-reviewer-app[bot]
YAML
put "$(repo_cat "$sb")" <<'YAML'
vendors:
  - id: sample-reviewer.quota
    vendor: sample-reviewer
    part: recognizer
    match: review quota for this period is used up
    reset-after: "available again at "
YAML
put "$(local_cat "$sb")" <<'YAML'
vendors:
  - id: sample-reviewer.full
    vendor: sample-reviewer
    part: control
    comment-body: "@sample-reviewer-app full review please"
  - id: sample-reviewer.delta
    vendor: sample-reviewer
    part: control
    comment-body: "@sample-reviewer-app review the new commits"
  - id: sample-reviewer.first-full
    vendor: sample-reviewer
    part: choice
    rule: auto
    position: 1
    condition: no-prior-review
    control: full
  - id: sample-reviewer.then-delta
    vendor: sample-reviewer
    part: choice
    rule: auto
    position: 2
    condition: prior-review
    control: delta
YAML
rv "$sb" --explain
assert_rc "four-layer adapter resolves" 0 "$RC"
assert_contains "provenance names the core layer" "claude${TAB}vendor${TAB}claude.vendor${TAB}core" "$OUT"
assert_contains "provenance names the adopter layer" "sample-reviewer${TAB}vendor${TAB}sample-reviewer.vendor${TAB}adopter" "$OUT"
assert_contains "provenance names the repo-tracked layer" "sample-reviewer${TAB}recognizer${TAB}sample-reviewer.quota${TAB}repo-tracked" "$OUT"
assert_contains "provenance names the machine-local layer" "sample-reviewer${TAB}control${TAB}sample-reviewer.full${TAB}machine-local" "$OUT"
rv "$sb"
assert_rc "four-layer adapter resolves (plain)" 0 "$RC"
assert_contains "vendor line carries the bot login" "vendor${TAB}sample-reviewer${TAB}none${TAB}sample-reviewer-app[bot]" "$OUT"
assert_contains "recognizer line carries its match and locator" "recognizer${TAB}sample-reviewer${TAB}quota${TAB}review quota for this period is used up${TAB}available again at " "$OUT"
assert_contains "control line carries its comment body" "control${TAB}sample-reviewer${TAB}full${TAB}comment-body${TAB}@sample-reviewer-app full review please" "$OUT"
assert_contains "choice line carries rule, position, condition, control" "choice${TAB}sample-reviewer${TAB}auto${TAB}2${TAB}prior-review${TAB}delta" "$OUT"
# Grouped by vendor: every claude line precedes every sample-reviewer line.
grouped=$(printf '%s\n' "$OUT" | awk -F '\t' '{ v = $2; if (v != last) { if (v in seen) bad = 1; seen[v] = 1; last = v } } END { print bad + 0 }')
[ "$grouped" = 0 ]
verdict "output is grouped by vendor" "vendors interleave: $OUT"
first=$(printf '%s\n' "$OUT" | awk -F '\t' '$2 == "sample-reviewer" { print $1; exit }')
[ "$first" = vendor ]
verdict "a vendor's group opens with its vendor line" "group opens with '$first'"
rv "$sb" --vendor sample-reviewer
assert_rc "--vendor filters to one vendor" 0 "$RC"
assert_absent "--vendor drops other vendors" "claude" "$OUT"
rv "$sb" --vendor nobody-here
assert_rc "an undeclared vendor exits 3" 3 "$RC"
# Output that cannot be written is a runtime failure, never a catalog verdict.
if [ -w /dev/full ]; then
  RC=0
  base PLANWRIGHT_ROOT="$sb/core" PLANWRIGHT_ADOPTER_OVERLAY="$sb/adopter" \
    PLANWRIGHT_REPO_ROOT="$sb/repo" /bin/bash "$RV" >/dev/full 2>"$sb/err" || RC=$?
  assert_rc "an unwritable output exits 6" 6 "$RC"
else
  ok "an unwritable output exits 6 (skipped: no /dev/full on this host)"
fi

# ---------------------------------------------------------------------------
# REQ-C1.1: an overlay supersedes one recognizer without restating the rest.
# ---------------------------------------------------------------------------
sb="$tmp/supersede"
seed "$sb"
put "$(adopter_cat "$sb")" <<'YAML'
vendors:
  - id: claude.first
    supersede: true
    vendor: claude
    part: recognizer
    match: replaced refusal text
YAML
rv "$sb" --explain
assert_contains "the superseded recognizer comes from the adopter" "claude${TAB}recognizer${TAB}claude.first${TAB}adopter" "$OUT"
assert_contains "the sibling recognizer stays core" "claude${TAB}recognizer${TAB}claude.second${TAB}core" "$OUT"
rv "$sb"
assert_rc "supersede resolves" 0 "$RC"
assert_contains "supersede replaces the match" "recognizer${TAB}claude${TAB}first${TAB}replaced refusal text${TAB}-" "$OUT"
assert_absent "the old match is gone" "first refusal text" "$OUT"
assert_contains "the untouched recognizer survives" "recognizer${TAB}claude${TAB}second${TAB}second refusal text${TAB}resets " "$OUT"
assert_contains "the vendor entry survives" "vendor${TAB}claude${TAB}claude-frames${TAB}-" "$OUT"

# ---------------------------------------------------------------------------
# A part whose vendor has no vendor entry is malformed, by layer.
# ---------------------------------------------------------------------------
orphan() {
  cat <<'YAML'
vendors:
  - id: ghost.quota
    vendor: ghost
    part: recognizer
    match: out of quota
YAML
}
sb="$tmp/orphan-local"
seed "$sb"
orphan | put "$(local_cat "$sb")"
rv "$sb"
assert_rc "an orphan part in machine-local degrades" 0 "$RC"
assert_contains "the orphan warning names the reason" "ghost.quota is malformed (vendor 'ghost' has no vendor entry)" "$ERR"
assert_absent "the orphan part is dropped" "ghost" "$OUT"
sb="$tmp/orphan-repo"
seed "$sb"
orphan | put "$(repo_cat "$sb")"
rv "$sb"
assert_rc "an orphan part in repo-tracked hard-fails" 4 "$RC"
assert_contains "the repo-tracked failure names the reason" "vendor 'ghost' has no vendor entry" "$ERR"
sb="$tmp/orphan-core"
{ seed "$sb"; } && orphan | sed 1d >>"$(core_cat "$sb")"
rv "$sb"
assert_rc "an orphan part in core is a broken install" 5 "$RC"
# A part whose vendor entry was itself dropped as malformed degrades with it.
sb="$tmp/orphan-cascade"
seed "$sb"
put "$(local_cat "$sb")" <<'YAML'
vendors:
  - id: sample-cli.vendor
    vendor: sample-cli
    part: vendor
    evidence: telepathy
  - id: sample-cli.quota
    vendor: sample-cli
    part: recognizer
    match: monthly quota exhausted
YAML
put "$(repo_cat "$sb")" <<'YAML'
vendors:
  - id: sample-cli.limit
    vendor: sample-cli
    part: recognizer
    match: limit reached
YAML
rv "$sb"
assert_rc "parts of a dropped vendor entry degrade, any layer" 0 "$RC"
assert_contains "the vendor entry's own reason is named" "sample-cli.vendor is malformed (unknown evidence kind)" "$ERR"
assert_absent "every part of the dropped vendor is gone" "sample-cli" "$OUT"

# ---------------------------------------------------------------------------
# REQ-C1.1, REQ-C1.5: each malformed field is refused with a named reason.
# Each case is one machine-local entry beside a valid sample-reviewer vendor;
# the warning must carry the reason and the entry must not resolve.
# ---------------------------------------------------------------------------
# bad <label> <reason> <yaml-entry-lines...>
bad() {
  label="$1"
  reason="$2"
  shift 2
  sb="$tmp/bad-$(printf '%s' "$label" | tr -c 'a-z0-9' '-')"
  seed "$sb"
  {
    echo "vendors:"
    echo "  - id: sample-reviewer.vendor"
    echo "    vendor: sample-reviewer"
    echo "    part: vendor"
    echo "    evidence: none"
    echo "    bot-login: sample-reviewer-app[bot]"
    for l in "$@"; do printf '%s\n' "$l"; done
  } | put "$(local_cat "$sb")"
  rv "$sb"
  if [ "$RC" -eq 0 ]; then ok "$label: degrades in machine-local"; else fail "$label: exit $RC ($ERR)"; fi
  assert_contains "$label: reason named" "($reason)" "$ERR"
  assert_absent "$label: entry dropped" "bad-entry" "$OUT"
}
bad "id without a vendor prefix" "id is not <vendor>.<name>" \
  "  - id: bad-entry" "    vendor: sample-reviewer" "    part: recognizer" "    match: x"
bad "id prefix differs from vendor" "id prefix is not the entry's vendor" \
  "  - id: other.bad-entry" "    vendor: sample-reviewer" "    part: recognizer" "    match: x"
bad "name outside the step-id grammar" "id is not <vendor>.<name>" \
  "  - id: sample-reviewer.Bad-entry" "    vendor: sample-reviewer" "    part: recognizer" "    match: x"
bad "missing part" "missing required field 'part'" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    match: x"
bad "unknown part" "unknown part" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: gadget"
bad "unknown field" "unknown field 'pattern' for a recognizer" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: recognizer" "    match: x" "    pattern: y"
bad "missing match" "missing required field 'match'" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: recognizer"
long=$(printf 'q%.0s' $(seq 1 300))
bad "oversized match" "match exceeds 256 bytes" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: recognizer" "    match: $long"
bad "sentinel locator" "reset-after of exactly '-' (the empty-field sentinel)" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: recognizer" "    match: x" "    reset-after: -"
bad "block scalar" "a block scalar (the catalog reader takes single-line scalars only)" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: recognizer" "    match: |"
bad "control with no invocation" "a control declares exactly one of 'comment-body' and 'args'" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: control"
bad "control with both invocations" "a control declares exactly one of 'comment-body' and 'args'" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: control" \
  "    comment-body: \"@sample-reviewer-app go\"" "    args: --full"
bad "comment body mentioning a foreign handle" "comment-body mentions a handle other than the bot login" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: control" \
  "    comment-body: \"@sample-reviewer-app review, cc @someone\""
bad "comment body mentioning a team" "comment-body mentions a handle other than the bot login" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: control" \
  "    comment-body: \"@sample-reviewer-app/team review\""
bad "comment body with an issue reference" "comment-body carries an issue or URL reference" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: control" \
  "    comment-body: \"@sample-reviewer-app review, fixes #12\""
bad "comment body with a GH- reference" "comment-body carries an issue or URL reference" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: control" \
  "    comment-body: \"@sample-reviewer-app see gh-7\""
bad "comment body with a URL" "comment-body carries an issue or URL reference" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: control" \
  "    comment-body: \"@sample-reviewer-app see https://example.invalid/x\""
big=$(printf 'z%.0s' $(seq 1 1100))
bad "oversized comment body" "comment-body exceeds 1024 bytes" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: control" \
  "    comment-body: \"@sample-reviewer-app $big\""
# shellcheck disable=SC2016 # the unexpanded substitution is the fixture
bad "CLI argument with command substitution" "args outside the plain-word grammar" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: control" '    args: --effort $(id)'
bad "CLI argument with a shell operator" "args outside the plain-word grammar" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: control" "    args: --full;reboot"
bad "CLI argument with a pipe" "args outside the plain-word grammar" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: control" "    args: a|b"
bad "CLI argument with a malformed option" "args carry an option injection" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: control" "    args: ---exec"
bad "CLI option value opening another option" "args carry an option injection" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: control" "    args: --model=--exec"
bad "CLI response-file argument" "args carry an option injection" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: control" "    args: @payload"
bad "CLI bare dash" "args carry an option injection" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: control" "    args: --full -"
bad "missing evidence" "missing required field 'evidence'" \
  "  - id: other.vendor" "    vendor: other" "    part: vendor" \
  "  - id: other.bad-entry" "    vendor: other" "    part: recognizer" "    match: x"
bad "bot login without the bot suffix" "bot-login is not a GitHub bot login (<login>[bot])" \
  "  - id: other.vendor" "    vendor: other" "    part: vendor" "    evidence: none" "    bot-login: someone" \
  "  - id: other.bad-entry" "    vendor: other" "    part: recognizer" "    match: x"
bad "bot login with a leading dash" "bot-login is not a GitHub bot login (<login>[bot])" \
  "  - id: other.vendor" "    vendor: other" "    part: vendor" "    evidence: none" "    bot-login: -x[bot]" \
  "  - id: other.bad-entry" "    vendor: other" "    part: recognizer" "    match: x"
bad "second vendor entry" "a second vendor entry for vendor 'sample-reviewer'" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: vendor" "    evidence: none"
bad "comment-body control without a bot login" "a comment-body control on a vendor with no bot-login" \
  "  - id: other.vendor" "    vendor: other" "    part: vendor" "    evidence: none" \
  "  - id: other.bad-entry" "    vendor: other" "    part: control" "    comment-body: please review"
bad "choice with an unknown condition" "unknown condition" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: choice" "    rule: auto" \
  "    position: 1" "    condition: on-tuesdays" "    control: full"
bad "choice with a non-numeric position" "position is not a positive integer" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: choice" "    rule: auto" \
  "    position: first" "    condition: prior-review" "    control: full"
bad "choice naming an undeclared control" "choice names control 'full', which vendor 'sample-reviewer' does not declare" \
  "  - id: sample-reviewer.bad-entry" "    vendor: sample-reviewer" "    part: choice" "    rule: auto" \
  "    position: 1" "    condition: prior-review" "    control: full"
bad "hostile vendor field" "vendor outside the step-id grammar" \
  "  - id: sample-reviewer.bad-entry" "    vendor: ../../etc" "    part: recognizer" "    match: x"

# A malformed repo-tracked entry hard-fails rather than degrading.
sb="$tmp/bad-repo"
seed "$sb"
put "$(repo_cat "$sb")" <<'YAML'
vendors:
  - id: claude.bad-entry
    vendor: claude
    part: control
    args: --x;y
YAML
rv "$sb"
assert_rc "a malformed repo-tracked entry hard-fails" 4 "$RC"
assert_contains "the hard-fail names the reason" "args outside the plain-word grammar" "$ERR"

# Two choice pairs at one position of one rule: the later one is malformed.
sb="$tmp/dup-position"
seed "$sb"
put "$(local_cat "$sb")" <<'YAML'
vendors:
  - id: claude.go
    vendor: claude
    part: control
    args: --go
  - id: claude.one
    vendor: claude
    part: choice
    rule: auto
    position: 1
    condition: prior-review
    control: go
  - id: claude.two
    vendor: claude
    part: choice
    rule: auto
    position: 1
    condition: no-prior-review
    control: go
YAML
rv "$sb"
assert_contains "a repeated rule position is refused" "claude.two is malformed (rule 'auto' already has a pair at position 1)" "$ERR"
assert_contains "the first pair at the position stands" "choice${TAB}claude${TAB}auto${TAB}1${TAB}prior-review${TAB}go" "$OUT"

# An entry that lost an indented line to the catalog reader is malformed in
# its own layer only: a later layer's clean supersede of it stands.
lost_entry() {
  cat <<'YAML'
vendors:
  - id: claude.extra
    vendor: claude
    part: recognizer
    match: extra refusal text
      nested: junk
YAML
}
sb="$tmp/lost-line"
seed "$sb"
lost_entry | put "$(adopter_cat "$sb")"
rv "$sb"
assert_rc "an adopter entry that lost a line degrades" 0 "$RC"
assert_contains "the lost line is named as the reason" "claude.extra is malformed (an indented line the catalog reader skipped)" "$ERR"
assert_absent "the entry that lost a line is dropped" "extra refusal text" "$OUT"
sb="$tmp/lost-line-superseded"
seed "$sb"
lost_entry | put "$(adopter_cat "$sb")"
put "$(repo_cat "$sb")" <<'YAML'
vendors:
  - id: claude.extra
    supersede: true
    vendor: claude
    part: recognizer
    match: clean refusal text
YAML
rv "$sb"
assert_rc "a clean supersede of an entry that lost a line resolves" 0 "$RC"
assert_contains "the clean supersede stands" "recognizer${TAB}claude${TAB}extra${TAB}clean refusal text${TAB}-" "$OUT"

# ---------------------------------------------------------------------------
# REQ-C1.5: a hostile --vendor is refused before any use.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016 # the unexpanded substitution is the fixture
for hostile in "../../etc" "Claude" "a b" '$(id)' "-x"; do
  sb="$tmp/hostile"
  seed "$sb"
  rv "$sb" --vendor "$hostile"
  assert_rc "hostile --vendor '$hostile' is a usage error" 2 "$RC"
done

# ---------------------------------------------------------------------------
# REQ-C1.6: docs/quota.md names only invented placeholder vendors.
# ---------------------------------------------------------------------------
doc="$REPO_ROOT/docs/quota.md"
if [ -r "$doc" ]; then
  ok "docs/quota.md exists"
  named=$(sed -n 's/^ *vendor: *//p' "$doc" | sort -u | tr '\n' ' ')
  for v in $named; do
    case "$v" in
      claude | sample-reviewer | sample-cli) ;;
      *) fail "docs/quota.md example names vendor '$v', not a placeholder" ;;
    esac
  done
  [ -n "$named" ]
  verdict "docs/quota.md examples declare vendors ($named)" "docs/quota.md declares no example vendor"
  for v in sample-reviewer sample-cli; do
    case " $named " in *" $v "*) ok "docs/quota.md illustrates $v" ;; *) fail "docs/quota.md lacks the $v example" ;; esac
  done
  # Real review-bot and model-CLI product names never appear in the doc.
  for real in copilot coderabbit gemini codex cubic greptile sourcery openai qodo bugbot sonarqube; do
    if grep -qi "$real" "$doc"; then fail "docs/quota.md names the real product '$real'"; fi
  done
  ok "docs/quota.md names no real review-bot or model-CLI product"
  # Every example resolves, warning-free, over the shipped core seed.
  sb="$tmp/doc-examples"
  mkdir -p "$sb/repo/.claude/catalogs.local"
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$sb/repo"
  awk '/^```yaml$/ { inb = 1; next } /^```$/ { inb = 0; next } inb && !/^vendors:/ { print }' "$doc" \
    | {
      echo "vendors:"
      cat
    } >"$sb/repo/.claude/catalogs.local/vendors.yaml"
  RC=0
  OUT=$(base PLANWRIGHT_ROOT="$REPO_ROOT" PLANWRIGHT_ADOPTER_OVERLAY="$sb/adopter" \
    PLANWRIGHT_REPO_ROOT="$sb/repo" /bin/bash "$RV" 2>"$sb/err") || RC=$?
  assert_rc "the docs/quota.md examples resolve" 0 "$RC"
  warned=$(cat "$sb/err")
  [ -z "$warned" ]
  verdict "the docs/quota.md examples resolve without a warning" "docs examples warned: $warned"
  assert_contains "the example choice rule resolves" "choice${TAB}sample-reviewer${TAB}auto${TAB}1${TAB}no-prior-review${TAB}full" "$OUT"
  assert_contains "the example CLI control resolves" "control${TAB}sample-cli${TAB}quick${TAB}args${TAB}--effort=low --no-tools" "$OUT"
else
  fail "docs/quota.md is missing"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all resolve-vendors tests passed"
