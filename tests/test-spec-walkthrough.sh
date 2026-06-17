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
#   2.  Status-agnostic: Draft, Active, Done, Retired, and Superseded each
#       load without a non-Active refusal (REQ-A1.4, REQ-B1.4).
#   3.  Strictly read-only: a run in a git work tree leaves the tree clean —
#       no modified bundle file, no new path, no commit (REQ-A1.3).
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

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

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
has "reveal"

# The `specs/<spec>` invocation form is accepted identically.
run_w 0 "$ws" specs/demo
has "demo"

# ---------------------------------------------------------------------------
# 2. Status-agnostic: every status loads, no non-Active refusal.
# ---------------------------------------------------------------------------
for st in Draft Active Done Retired Superseded; do
  wsx="$tmp/status-$st"
  mkdir -p "$wsx"
  make_bundle "$wsx/specs" demo "$st"
  run_w 0 "$wsx" demo
  has "$st"
done

# ---------------------------------------------------------------------------
# 3. Strictly read-only: the git work tree stays clean after a run.
# ---------------------------------------------------------------------------
if command -v git >/dev/null 2>&1; then
  gws="$tmp/gitws"
  mkdir -p "$gws"
  make_bundle "$gws/specs" demo Draft
  (
    cd "$gws"
    git init -q
    git config user.email t@e.x
    git config user.name t
    git add -A
    git commit -qm init
  )
  run_w 0 "$gws" demo
  status_after=$(cd "$gws" && git status --porcelain)
  [ -z "$status_after" ] \
    || fail "run was not read-only; git status: $status_after"
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
has "requirements.md"
has "design.md"
# tasks.md and test-spec.md are named as missing.
has "tasks.md"
has "test-spec.md"
has "missing"

# ---------------------------------------------------------------------------
# 7. Scope selectors parse, resolve, and degrade with available scopes.
# ---------------------------------------------------------------------------
run_w 0 "$ws" --scope file:design demo
run_w 0 "$ws" --scope reqs:A demo
run_w 0 "$ws" --scope decisions demo
run_w 0 "$ws" --scope tasks demo
run_w 0 "$ws" --scope decision:1 demo
run_w 0 "$ws" --scope decision:D-2 demo

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

echo "PASS: test-spec-walkthrough.sh"
