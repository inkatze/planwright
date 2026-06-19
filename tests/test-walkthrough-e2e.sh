#!/bin/bash
# End-to-end cross-cutting fixtures for /spec-walkthrough (Task 11 of
# specs/spec-comprehension; D-4 · REQ-E1.1, REQ-E1.2, REQ-E1.4, REQ-E1.5,
# REQ-E1.7).
#
# The per-view suites (test-spec-assemble.sh, test-spec-graph.sh, ...) exercise
# the rendering scripts in isolation, inspecting their stdout. This suite
# exercises the WHOLE command surface end to end: it runs scripts/spec-walkthrough.sh
# against a real four-file bundle from a separate workspace, then inspects the
# PERSISTED artifact the command actually writes to the gitignored
# .claude/walkthroughs/<spec>/ location — the integration path (scaffold load +
# scope resolution + atomic mktemp/rename write) that no single view test covers.
# The cross-cutting hygiene properties Task 11 owns are asserted against that
# real artifact:
#   - persisted to the gitignored location, and genuinely gitignored (REQ-E1.1);
#   - offline: no http(s) or external resource reference (REQ-E1.2);
#   - injection safety: a bundle bearing HTML/SVG markup renders escaped, with no
#     executable or structural markup from bundle content surviving (REQ-E1.7);
#   - provenance: the artifact records the bundle and the commit it was generated
#     from (REQ-E1.5);
#   - data hygiene: gitleaks finds no secret in the artifact (REQ-E1.4), when
#     gitleaks is installed (skipped with a note otherwise, matching the per-view
#     suite's discipline).
#
# Runs standalone: ./tests/test-walkthrough-e2e.sh
set -u
# Pin the C locale so grep ranges do not vary by host collation (REQ-K1.5).
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/spec-walkthrough.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() {
  echo "ok: $1"
}

if [ ! -x "$SCRIPT" ]; then
  echo "FAIL: scripts/spec-walkthrough.sh missing or not executable" >&2
  echo "1 failure(s)" >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  echo "ok: git unavailable — skipping end-to-end suite (no environment to run in)"
  echo "all walkthrough end-to-end checks passed"
  exit 0
fi

# Isolated workspace: a git repo (the command reads HEAD for the provenance
# stamp and the read-only contract is asserted against a clean tracked tree)
# holding a specs/<fixture> bundle whose text carries injection payloads. The
# command writes its artifact under the workspace's gitignored .claude/.
ws="$(mktemp -d)" || exit 1
trap 'chmod -R u+rwx "$ws" 2>/dev/null || true; rm -rf "$ws"' EXIT

spec=injectfix
d="$ws/specs/$spec"
mkdir -p "$d"

# requirements.md, design.md, tasks.md carry HTML/SVG metacharacters and markup
# in rendered fields (REQ titles, decision beats, task titles) so the escaping
# assertion below is meaningful: each payload must reach the artifact as inert
# text, never live markup.
cat >"$d/requirements.md" <<'EOF'
# Inject Fixture — Requirements
**Status:** Active
**Format-version:** 1

## REQ-A — payload group <i>tag</i>
- **REQ-A1.1** The widget SHALL escape <script>alert(1)</script> and
  <img src=x onerror="boom()"> safely. Placeholder <spec> & raw < and " too.
  *(Cites: D-1.)*
EOF
cat >"$d/design.md" <<'EOF'
# Inject Fixture — Design
**Status:** Active
**Format-version:** 1

### D-1: render escaped <script>evil()</script>
- **Context:** markup in <b>text</b> must not execute.
- **Decision:** escape all bundle content.
- **Alternatives considered:** raw passthrough <img onerror=x>.
- **Chosen because:** safety and clarity.
- **Consequence:** entities only.
EOF
cat >"$d/tasks.md" <<'EOF'
# Inject Fixture — Tasks
**Status:** Active
**Format-version:** 1

## Forward plan
### Task 1 — do <script>nope()</script>
- **Deliverables:** thing.
- **Done when:** done.
- **Dependencies:** none
- **Citations:** D-1
EOF
cat >"$d/test-spec.md" <<'EOF'
# Inject Fixture — Test Spec
**Status:** Active
**Format-version:** 1

## REQ-A — payload group
### REQ-A1.1 — escapes markup [test]
Assert escaping.
EOF

printf '%s\n' '.claude/walkthroughs/' >"$ws/.gitignore"
(
  cd "$ws" || exit 1
  git init -q
  git config user.email t@e.x
  git config user.name t
  git add -A
  # Disable signing so the suite does not depend on the host's commit-signing.
  git -c commit.gpgsign=false commit -qm init
)

short_commit="$(cd "$ws" && git rev-parse --short HEAD)"

# Run the real command from the workspace; capture its load report.
report="$(cd "$ws" && "$SCRIPT" "$spec" 2>&1)"
rc=$?
[ "$rc" -eq 0 ] || fail "command exited $rc for a valid bundle — report: $report"

art="$ws/.claude/walkthroughs/$spec/$spec.html"

# REQ-E1.1 — persisted to the gitignored location and genuinely gitignored.
if [ -f "$art" ]; then
  ok "artifact persisted to .claude/walkthroughs/$spec/$spec.html"
else
  fail "no artifact written at $art — report: $report"
fi
case $report in
  *"artifact: .claude/walkthroughs/$spec/$spec.html"*)
    ok "load report names the persisted artifact"
    ;;
  *)
    fail "load report does not name the artifact — report: $report"
    ;;
esac
if (cd "$ws" && git check-ignore -q ".claude/walkthroughs/$spec/$spec.html"); then
  ok "artifact path is gitignored"
else
  fail "artifact path is NOT gitignored (REQ-E1.1)"
fi
# The run left the tracked tree clean (no bundle mutation, no new tracked path).
tracked="$(cd "$ws" && git status --porcelain)"
[ -z "$tracked" ] || fail "run dirtied the tracked tree: $tracked"

# Nothing else below makes sense without the artifact.
if [ ! -f "$art" ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi

# REQ-E1.2 — offline: no network reference anywhere in the artifact.
netref="$(grep -Eo 'https?://[^"'"'"' )]*' "$art" || true)"
[ -z "$netref" ] || fail "artifact references a network resource (REQ-E1.2): $netref"
if grep -q 'src="http' "$art" || grep -q 'href="http' "$art"; then
  fail "artifact carries an external src/href (REQ-E1.2)"
else
  ok "artifact references no external network resource"
fi

# REQ-E1.7 — injection safety: bundle markup arrives escaped, never live. The
# assembler emits no <script> of its own (reveal is CSS-only), so any <script
# substring would have to originate from the bundle payload; assert there is
# none, that the live payload strings are absent, and that their escaped
# entities are present.
if [ "$(grep -c '<script' "$art")" -eq 0 ]; then
  ok "no live <script tag survives from bundle content (REQ-E1.7)"
else
  fail "a live <script tag survived into the artifact (REQ-E1.7 injection safety)"
fi
for live in "alert(1)</script>" 'onerror="boom()"' '<img src=x onerror'; do
  if grep -qF -- "$live" "$art"; then
    fail "live markup payload survived unescaped: $live (REQ-E1.7)"
  fi
done
for ent in '&lt;script&gt;' '&lt;spec&gt;'; do
  if grep -qF -- "$ent" "$art"; then
    ok "payload escaped to entity $ent"
  else
    fail "expected escaped entity $ent absent from artifact (REQ-E1.7)"
  fi
done

# REQ-E1.5 — provenance: the artifact records the bundle and the commit.
if grep -qF -- "$spec" "$art"; then
  ok "artifact records the bundle name (REQ-E1.5)"
else
  fail "artifact does not record the bundle name (REQ-E1.5)"
fi
if [ -z "$short_commit" ]; then
  # An empty commit id would make the grep below match any line (an empty -F
  # pattern matches everything), silently passing the provenance check for the
  # wrong reason. Guard it so REQ-E1.5 can only pass on a real commit stamp.
  fail "short_commit is empty; cannot assert provenance (REQ-E1.5)"
elif grep -qF -- "$short_commit" "$art"; then
  ok "artifact records the generating commit $short_commit (REQ-E1.5)"
else
  fail "artifact does not record the generating commit $short_commit (REQ-E1.5)"
fi

# REQ-E1.4 — data hygiene: the generated artifact is gitleaks-clean. Scanned
# with --no-git since the artifact is gitignored and so invisible to the
# repo-wide history scan.
if command -v gitleaks >/dev/null 2>&1; then
  if gitleaks detect --no-banner --no-git --source "$art" >/dev/null 2>&1; then
    ok "gitleaks found no secret in the artifact (REQ-E1.4)"
  else
    fail "gitleaks flagged the generated artifact (REQ-E1.4 data hygiene)"
  fi
else
  ok "gitleaks not installed — data-hygiene scan skipped (exercised in CI)"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all walkthrough end-to-end checks passed"
