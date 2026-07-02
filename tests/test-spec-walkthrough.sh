#!/bin/sh
# Unit tests for scripts/spec-walkthrough.sh — the /spec-walkthrough command
# scaffold (Task 1 of specs/spec-comprehension): the command surface,
# argument/flag parsing, identifier-charset + path-containment safety,
# read-only status-agnostic bundle loading, and graceful degradation.
#
# Properties verified, one numbered section per Task 1 behavior:
#   1.  A valid full bundle loads (exit 0) and the load report names the
#       detected status, the present files, the requested scope, and the
#       reveal state (REQ-A1.1).
#   2.  Status-agnostic: Draft, Ready, Active, Done, Retired, and Superseded
#       each load without a non-Active refusal (REQ-A1.4, REQ-B1.4).
#   3.  Strictly read-only apart from the gitignored artifact: a run leaves the
#       tracked tree clean, and the self-contained HTML walkthrough is written to
#       the gitignored .claude/walkthroughs/<spec>/ location (REQ-A1.3, REQ-E1.1).
#   4.  Argument and flag parsing: spec-path required; both `specs/<spec>`
#       and bare `<spec>` forms accepted; `--scope`/`--reveal` parse; an
#       unknown flag or a missing scope value is a usage refusal (REQ-A1.2).
#   5.  Reveal flag off by default; `--reveal` turns it on (REQ-A1.2).
#   6.  Graceful degradation: a missing bundle and a partial bundle each
#       yield a clear message naming what is absent, never an opaque halt;
#       a partial bundle still loads what is present (REQ-A1.5).
#   7.  Scope selectors parse and resolve on a full bundle (whole/file/reqs/
#       decisions/tasks/decision); a charset-valid scope that resolves to no
#       part of the bundle yields a clear message naming the available scopes
#       (REQ-A1.2, REQ-A1.5).
#   8.  Identifier and path safety: a hostile identifier (bad charset,
#       traversal, multi-component, over-length) is a clean refusal before
#       any read, never echoed back verbatim, never turned into a path; a
#       symlinked bundle escaping specs/ fails the containment check
#       (REQ-A1.6).
#
# Runs standalone: ./tests/test-spec-walkthrough.sh
set -eu

# Pin the C locale: charset checks and awk/grep ranges must not vary by host
# locale collation.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into command substitutions
# below, corrupting derived paths (house pattern, see sibling tests).
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/spec-walkthrough.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$script" ] || fail "scripts/spec-walkthrough.sh missing or not executable"

tmp="$(mktemp -d)" || exit 1
# Restore search/write permission before rm: section 11 deliberately chmod 000's
# a bundle dir, which would otherwise block cleanup if that test aborts early.
# The chmod is best-effort (`|| true`): its only job is to let `rm` proceed, and
# under `set -e` a non-zero chmod in this `;`-list would otherwise abort the trap
# before `rm` ever runs, leaking the temp tree.
trap 'chmod -R u+rwx "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

# run_w <expected-exit> <workspace> <args...> — run the scaffold with the
# workspace as CWD (the command resolves specs/ relative to the working
# directory, the repo-root invocation contract), capture combined output in
# $out, and fail the suite if the exit code differs.
out=
run_w() {
  rexp=$1
  rws=$2
  shift 2
  rc=0
  out=$(cd "$rws" && "$script" "$@" 2>&1) || rc=$?
  [ "$rc" -eq "$rexp" ] \
    || fail "expected exit $rexp, got $rc for: $* (cwd $rws) — output: $out"
}

has() {
  case $out in
    *"$1"*) ;;
    *) fail "output lacks \"$1\": $out" ;;
  esac
}

lacks() {
  case $out in
    *"$1"*) fail "output unexpectedly contains \"$1\": $out" ;;
  esac
}

# make_bundle <specs-root> <spec> <status> — a minimal four-file bundle with
# two requirement groups (A, B), two decisions (D-1, D-2), and two tasks.
make_bundle() {
  mr=$1
  ms=$2
  mst=$3
  d="$mr/$ms"
  mkdir -p "$d"
  cat >"$d/requirements.md" <<EOF
# Fixture — Requirements

**Status:** $mst
**Last reviewed:** 2026-06-16
**Format-version:** 1

## REQ-A — first group

- **REQ-A1.1** The thing SHALL exist. *(Cites: D-1.)*

## REQ-B — second group

- **REQ-B1.1** The other thing SHALL exist. *(Cites: D-2.)*
EOF
  cat >"$d/design.md" <<EOF
# Fixture — Design

**Status:** $mst
**Last reviewed:** 2026-06-16
**Format-version:** 1

### D-1: First decision  (N)

**Decision:** Do the first thing.

**Alternatives considered:**
- Nothing. Rejected because: nothing would exist.

**Chosen because:** the fixture needs it.

### D-2: Second decision  (N)

**Decision:** Do the second thing.

**Alternatives considered:**
- Nothing. Rejected because: nothing would exist.

**Chosen because:** the fixture needs it too.
EOF
  cat >"$d/tasks.md" <<EOF
# Fixture — Tasks

**Status:** $mst
**Last reviewed:** 2026-06-16
**Format-version:** 1

## Forward plan

### Task 1 — first

- **Deliverables:** a thing.
- **Done when:** the thing exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** 1 day
EOF
  cat >"$d/test-spec.md" <<EOF
# Fixture — Test Spec

**Status:** $mst
**Last reviewed:** 2026-06-16
**Format-version:** 1

### REQ-A1.1 — exists [test]

Assert the thing exists.
EOF
}

# ---------------------------------------------------------------------------
# 1. A valid full bundle loads and reports its shape.
# ---------------------------------------------------------------------------
ws="$tmp/ws1"
mkdir -p "$ws"
make_bundle "$ws/specs" demo Active

run_w 0 "$ws" demo
has "demo"
has "Active"
has "requirements.md"
has "design.md"
has "tasks.md"
has "test-spec.md"
has "reveal: off"

# The `specs/<spec>` invocation form is accepted identically.
run_w 0 "$ws" specs/demo
has "demo"

# ---------------------------------------------------------------------------
# 2. Status-agnostic: every status loads, no non-Active refusal.
# ---------------------------------------------------------------------------
for st in Draft Ready Active Done Retired Superseded; do
  wsx="$tmp/status-$st"
  mkdir -p "$wsx"
  make_bundle "$wsx/specs" demo "$st"
  run_w 0 "$wsx" demo
  has "$st"
done

# When requirements.md is absent, the status falls back to a sibling mirror
# that declares one.
fbws="$tmp/fallback"
mkdir -p "$fbws/specs/demo"
make_bundle "$fbws/specs" demo Done
rm "$fbws/specs/demo/requirements.md"
run_w 0 "$fbws" demo
has "Done"
has "missing"

# requirements.md present but its Status value is empty: reported as undeclared,
# not masked by a sibling mirror (requirements.md is authoritative).
emws="$tmp/emptystatus"
mkdir -p "$emws/specs/demo"
make_bundle "$emws/specs" demo Active
# Blank out only the requirements.md Status value; design.md still says Active.
{
  printf '# Fixture — Requirements\n\n'
  printf '**Status:**\n'
  printf '**Format-version:** 1\n\n'
  printf '## REQ-A — group\n\n- **REQ-A1.1** A thing SHALL exist. *(Cites: D-1.)*\n'
} >"$emws/specs/demo/requirements.md"
run_w 0 "$emws" demo
has "undeclared"
lacks "status: Active"

# ---------------------------------------------------------------------------
# 3. Strictly read-only apart from the gitignored artifact (REQ-A1.3, REQ-E1.1,
#    REQ-F1.3): the generated walkthrough is written under the gitignored
#    .claude/walkthroughs/<spec>/ location, so a run still leaves the *tracked*
#    work tree clean — no modified bundle file, no new tracked path, no commit.
#    The empty `git status --porcelain` below is also the REQ-F1.3 "no pipeline
#    mutation" assertion: a run changes no tasks.md state, no lock, no status,
#    and no other pipeline artifact — they are all tracked, so any mutation would
#    surface here as a dirty tree.
# ---------------------------------------------------------------------------
if command -v git >/dev/null 2>&1; then
  gws="$tmp/gitws"
  mkdir -p "$gws"
  make_bundle "$gws/specs" demo Draft
  # The real repo gitignores the artifact location (Task 6); mirror that so the
  # clean-tree assertion reflects the true contract.
  printf '%s\n' '.claude/walkthroughs/' >"$gws/.gitignore"
  (
    cd "$gws"
    git init -q
    git config user.email t@e.x
    git config user.name t
    git add -A
    # The baseline only needs to exist to diff against; disable signing so the
    # test does not depend on the host's commit-signing being configured.
    git -c commit.gpgsign=false commit -qm init
  )
  run_w 0 "$gws" demo
  status_after=$(cd "$gws" && git status --porcelain)
  [ -z "$status_after" ] \
    || fail "run was not read-only in the tracked tree; git status: $status_after"
  # The artifact was written to the gitignored location and is a self-contained
  # HTML document (REQ-E1.1) — the load report names it.
  has "artifact: .claude/walkthroughs/demo/demo.html"
  artifact="$gws/.claude/walkthroughs/demo/demo.html"
  [ -f "$artifact" ] || fail "no artifact written at $artifact"
  head1=$(head -1 "$artifact")
  case $head1 in
    '<!DOCTYPE html'*) ;;
    *) fail "artifact is not an HTML document (first line: $head1)" ;;
  esac
  # It is genuinely gitignored: git does not see it as an untracked path.
  ignored=$(cd "$gws" && git status --porcelain --ignored .claude/walkthroughs/ | awk '$1=="!!"{print; exit}')
  [ -n "$ignored" ] || fail "artifact location is not gitignored"
fi

# ---------------------------------------------------------------------------
# 4. Argument and flag parsing.
# ---------------------------------------------------------------------------
# Missing spec-path is a usage refusal.
run_w 2 "$ws"
# Unknown flag is a usage refusal.
run_w 2 "$ws" --bogus demo
# A scope flag with no value is a usage refusal.
run_w 2 "$ws" --scope
# A scope flag with a value but no spec-path is a usage refusal.
run_w 2 "$ws" --scope reqs:A
# Two positional spec-paths is a usage refusal.
run_w 2 "$ws" demo demo

# ---------------------------------------------------------------------------
# 5. Reveal flag: off by default, on with --reveal.
# ---------------------------------------------------------------------------
run_w 0 "$ws" demo
has "reveal: off"
run_w 0 "$ws" --reveal demo
has "reveal: on"

# ---------------------------------------------------------------------------
# 6. Graceful degradation on a missing or partial bundle.
# ---------------------------------------------------------------------------
# A bundle directory that does not exist: clear message, names the absence,
# no opaque halt.
run_w 1 "$ws" missingspec
has "missingspec"
lacks "Traceback"

# A partial bundle (two of four files) still loads what is present and names
# what is missing.
pws="$tmp/partial"
mkdir -p "$pws/specs/half"
cat >"$pws/specs/half/requirements.md" <<'EOF'
# Half — Requirements

**Status:** Draft
**Format-version:** 1

## REQ-A — group

- **REQ-A1.1** A thing SHALL exist. *(Cites: D-1.)*
EOF
cat >"$pws/specs/half/design.md" <<'EOF'
# Half — Design

**Status:** Draft
**Format-version:** 1

### D-1: A decision  (N)

**Decision:** Decide.

**Alternatives considered:**
- Nothing.

**Chosen because:** needed.
EOF
run_w 0 "$pws" half
has "partial"
# Structure-aware: the present files and the missing files land in their own
# labeled lists, not merely somewhere in the output.
has "files present: requirements.md, design.md"
has "files missing: tasks.md, test-spec.md"

# An empty bundle directory (present, but none of the four files) degrades with
# a clear message rather than rendering nothing.
ews="$tmp/empty"
mkdir -p "$ews/specs/hollow"
run_w 1 "$ews" hollow
has "hollow"
has "none of the four"

# ---------------------------------------------------------------------------
# 7. Scope selectors parse, resolve, and degrade with available scopes.
# ---------------------------------------------------------------------------
run_w 0 "$ws" --scope file:design demo
# The .md suffix on a file selector is accepted (normalized away).
run_w 0 "$ws" --scope file:requirements.md demo
run_w 0 "$ws" --scope reqs:A demo
run_w 0 "$ws" --scope decisions demo
run_w 0 "$ws" --scope tasks demo
run_w 0 "$ws" --scope decision:1 demo
run_w 0 "$ws" --scope decision:D-2 demo
# A lowercase d- prefix on a decision selector resolves the same as D-.
run_w 0 "$ws" --scope decision:d-1 demo

# A charset-valid scope that resolves to nothing names the available scopes.
run_w 1 "$ws" --scope file:nope demo
has "design.md"
run_w 1 "$ws" --scope reqs:Z demo
has "A"
run_w 1 "$ws" --scope decision:99 demo
has "D-1"
# An unknown scope kind names the valid scope kinds.
run_w 1 "$ws" --scope wat demo
has "whole"

# ---------------------------------------------------------------------------
# 8. Identifier and path safety: hostile input is refused before any read.
# ---------------------------------------------------------------------------
# Uppercase, traversal, multi-component, leading dash, and over-length all
# refuse with exit 2 and never echo the hostile token back verbatim.
run_w 2 "$ws" Demo
lacks "Demo"
run_w 2 "$ws" ../../etc/passwd
lacks "passwd"
run_w 2 "$ws" foo/bar
lacks "foo/bar"
run_w 2 "$ws" specs/foo/bar
lacks "foo/bar"
# A leading dash that reaches the charset check (via the specs/ form) is a clean
# refusal, not echoed back.
run_w 2 "$ws" specs/-leadingdash
lacks "leadingdash"
big=$(printf 'a%.0s' $(seq 1 65))
run_w 2 "$ws" "$big"

# A symlinked bundle whose target escapes specs/ fails the containment check.
if command -v ln >/dev/null 2>&1; then
  sws="$tmp/symws"
  mkdir -p "$sws/specs"
  make_bundle "$tmp/outside" escapee Active
  ln -s "$tmp/outside/escapee" "$sws/specs/escapee"
  run_w 2 "$sws" escapee
fi

# ---------------------------------------------------------------------------
# 9. Echo discipline: a hostile --scope value is sanitized before it is echoed
# back, so control characters cannot reach the terminal raw. Two ctrl bytes at
# the boundaries of the strip range — \001 (SOH, low end) and \177 (DEL, high
# end) — are stripped, so the sanitized "watxy" appears as a contiguous token
# only if sanitization covers the whole \000-\037\177 range.
# ---------------------------------------------------------------------------
ctrl=$(printf 'wat\001x\177y')
run_w 1 "$ws" --scope "$ctrl" demo
has "watxy"

# ---------------------------------------------------------------------------
# 10. CDPATH robustness: a user CDPATH must not corrupt the path-containment
# check. The check resolves the real specs/ and bundle paths via
# `$(cd <dir> && pwd -P)`; with CDPATH set, `cd` echoes the resolved
# destination into the command substitution, prepending a stray line that
# breaks the containment comparison and turns a valid bundle into a spurious
# "escapes the specs/ tree" refusal. The script must neutralize CDPATH (the
# house pattern every sibling script follows) so a valid bundle still loads.
# This test sets CDPATH in the child environment explicitly: the suite unsets
# it globally above, which would otherwise mask the regression.
# ---------------------------------------------------------------------------
cdrc=0
cdout=$(cd "$ws" && CDPATH="." "$script" demo 2>&1) || cdrc=$?
[ "$cdrc" -eq 0 ] \
  || fail "CDPATH=. broke a valid load (exit $cdrc) — output: $cdout"
case $cdout in
  *"loaded bundle 'demo'"*) ;;
  *) fail "CDPATH=. corrupted the load report: $cdout" ;;
esac

# ---------------------------------------------------------------------------
# 11. Path-containment fails closed (REQ-A1.6). When the bundle directory
# exists ([ -d ] true) but its real path cannot be resolved — `cd … && pwd -P`
# fails — the containment gate must refuse before any read, not fall through to
# the file reads with the gate silently bypassed. A directory with no search
# (execute) permission makes [ -d ] succeed (the parent is searchable) while
# `cd` into it fails. Skipped as root, where permission bits are ignored.
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  uws="$tmp/unresolvable"
  mkdir -p "$uws/specs"
  # Real files inside, so a fall-through past the gate would actually read them.
  make_bundle "$uws/specs" locked Active
  chmod 000 "$uws/specs/locked"
  run_w 2 "$uws" locked
  # Restore search permission immediately so the EXIT trap can clean up and the
  # captured $out is still asserted below.
  chmod 755 "$uws/specs/locked"
  has "could not resolve"
  has "before any read"
fi

# ---------------------------------------------------------------------------
# 12. Partial-bundle scope degradation names the absent source file, matching
# the `decisions`/`tasks`/`file:` branches (REQ-A1.5). Without this, a missing
# requirements.md or design.md degrades with an empty "available …:" list that
# never names what is absent.
# ---------------------------------------------------------------------------
# reqs:<group> with requirements.md absent names the missing file.
nrws="$tmp/noreqs"
mkdir -p "$nrws/specs"
make_bundle "$nrws/specs" demo Active
rm "$nrws/specs/demo/requirements.md"
run_w 1 "$nrws" --scope reqs:A demo
has "requirements.md"

# decision:<id> with design.md absent names the missing file.
ndws="$tmp/nodesign"
mkdir -p "$ndws/specs"
make_bundle "$ndws/specs" demo Active
rm "$ndws/specs/demo/design.md"
run_w 1 "$ndws" --scope decision:1 demo
has "design.md"

# ---------------------------------------------------------------------------
# 13. Decision-heading conformance (doctrine/spec-format.md: `### D-<n>:`, the
# colon is required; the validator flags a colon-less `### D-` as malformed).
# The decision lister and the `decisions` scope guard must match only the
# conforming form, the same form the `decision:<id>` resolver uses — otherwise
# a malformed heading is listed as an "available decision" the resolver can
# never resolve, and an all-malformed design.md reports a bogus decision set.
# ---------------------------------------------------------------------------
# A malformed `### D-<n>` (no colon) is not listed among available decisions.
mdws="$tmp/malformed-decisions"
mkdir -p "$mdws/specs"
make_bundle "$mdws/specs" demo Active
cat >>"$mdws/specs/demo/design.md" <<'EOF'

### D-9 Malformed heading with no colon  (N)

**Decision:** Should not be listed as an available decision.
EOF
run_w 1 "$mdws" --scope decision:99 demo
has "D-1"
lacks "D-9"

# A design.md whose only decision headings are malformed yields no decision
# set, degrading rather than reporting a bogus "decision set" scope.
omws="$tmp/only-malformed"
mkdir -p "$omws/specs/demo"
cat >"$omws/specs/demo/design.md" <<'EOF'
# Fixture — Design

**Status:** Active
**Format-version:** 1

### D-1 Malformed, no colon  (N)

**Decision:** Not a conforming decision heading.
EOF
run_w 1 "$omws" --scope decisions demo
has "no decisions"

# ---------------------------------------------------------------------------
# 14. Scope-probe grep noise discipline: the `decisions` scope guard redirects
# grep's stderr like the sibling probes (`reqs:`, `decision:`, and the two
# listers all use `2>/dev/null`), so an unreadable design.md degrades cleanly
# through the script's own message rather than leaking grep's "Permission
# denied" diagnostic into the output. Skipped as root (permission bits ignored).
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  grws="$tmp/grep-noise"
  mkdir -p "$grws/specs"
  make_bundle "$grws/specs" demo Active
  chmod 000 "$grws/specs/demo/design.md"
  run_w 1 "$grws" --scope decisions demo
  chmod 644 "$grws/specs/demo/design.md"
  lacks "Permission denied"
  has "no decision set"
fi

# ---------------------------------------------------------------------------
# 15. Artifact write is atomic: a failed assembly never creates, truncates, or
# leaves an empty/partial artifact behind, and a prior good artifact survives a
# later failed run (REQ-A1.5 — the bundle loaded, only the artifact is missing;
# the load must not corrupt a previously-written artifact). The scaffold resolves
# spec-assemble.sh as its sibling, so we run a copy of the scaffold beside a stub
# assembler that prints partial output then exits non-zero. The real assembler is
# fail-closed (no stdout on failure), so in practice the leftover would be an
# empty file; the stub's mid-stream partial write proves the temp-then-rename
# guard protects even a partially-writing assembler, the stronger property.
# ---------------------------------------------------------------------------
asws="$tmp/atomic"
mkdir -p "$asws/scripts"
cp "$script" "$asws/scripts/spec-walkthrough.sh"
# The scaffold sources scripts/echo-safety.sh as a sibling; stage it too.
cp "$here/../scripts/echo-safety.sh" "$asws/scripts/echo-safety.sh"
cat >"$asws/scripts/spec-assemble.sh" <<'EOF'
#!/bin/sh
# Stub assembler: emit a specific diagnostic on stderr and partial output on
# stdout, then fail — modeling an assembly that dies after writing some bytes,
# with a concrete reason the scaffold must surface rather than swallow.
printf 'STUB ASSEMBLER DIAGNOSTIC\n' >&2
printf 'PARTIAL BROKEN HTML'
exit 2
EOF
chmod +x "$asws/scripts/spec-assemble.sh"
scaffold="$asws/scripts/spec-walkthrough.sh"
make_bundle "$asws/specs" demo Active
printf '%s\n' '.claude/walkthroughs/' >"$asws/.gitignore"
afile="$asws/.claude/walkthroughs/demo/demo.html"

# 15a. No prior artifact: a failed assembly reports "not written" and leaves NO
# artifact file behind — the message must not be contradicted by a stray
# empty/partial file a confused reader could open.
arc=0
aout=$(cd "$asws" && "$scaffold" demo 2>&1) || arc=$?
[ "$arc" -eq 0 ] || fail "atomic: the load itself should still succeed (exit $arc): $aout"
case $aout in
  *"artifact: not written"*) ;;
  *) fail "atomic: expected 'artifact: not written' on assembly failure: $aout" ;;
esac
[ ! -e "$afile" ] \
  || fail "atomic: a failed assembly left a stray artifact at $afile: [$(cat "$afile" 2>/dev/null)]"
# The assembler's specific diagnostic must reach the user, not be swallowed by a
# stderr redirect — the degradation names the real reason (REQ-A1.5).
case $aout in
  *"STUB ASSEMBLER DIAGNOSTIC"*) ;;
  *) fail "atomic: the assembler's stderr diagnostic was swallowed, not surfaced: $aout" ;;
esac

# 15b. Prior good artifact: a later failed assembly preserves it intact rather
# than truncating it to empty/partial.
mkdir -p "$asws/.claude/walkthroughs/demo"
printf 'GOOD PRIOR ARTIFACT\n' >"$afile"
arc=0
aout=$(cd "$asws" && "$scaffold" demo 2>&1) || arc=$?
[ "$arc" -eq 0 ] || fail "atomic: the load should succeed with a prior artifact (exit $arc): $aout"
case $(cat "$afile") in
  'GOOD PRIOR ARTIFACT') ;;
  *) fail "atomic: a failed assembly corrupted the prior artifact: [$(cat "$afile")]" ;;
esac

echo "PASS: test-spec-walkthrough.sh"
