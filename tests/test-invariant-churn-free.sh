#!/bin/bash
# The churn-free property test (invariant-tasks Task 4; D-9; REQ-A1.2,
# REQ-C1.6). Format-version 2 stores only what cannot be derived, so a FULL
# execution state transition — dispatch (task branch), in-progress evidence
# (commits on the branch), merged-PR evidence (merge with the Planwright-Task
# trailer plus the gh-stubbed PR batch) — exercised against a v2 fixture
# bundle must produce ZERO diff under the spec directory: the version-keyed
# writer (tasks-pr-sync.sh, both CLI arms and the hook) writes nothing, and
# the render (spec-status.sh) is read-only. The two human-payload writes the
# format does commit — a parking write (a reference bullet appearing in
# ## Awaiting input) and the matching unparking write — must leave the content
# anchor (scripts/spec-anchor.sh, canonical form) unchanged: bullets live
# outside task blocks, so the canonical tasks.md extraction never sees them.
#
# Oracles, per derived transition:
#   * the specs/ content digest is byte-identical before and after the writer
#     and the render run (no write, REQ-C1.1);
#   * the working tree stays clean under specs/ (no uncommitted churn);
# and across the parking/unparking commits:
#   * the content anchor recomputes to the baseline value (REQ-C1.6);
#   * at the end, the ONLY commits touching specs/ are the fixture and the
#     two human-payload writes — no derived transition produced a commit
#     (REQ-A1.2).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SYNC="$here/../scripts/tasks-pr-sync.sh"
RENDER="$here/../scripts/spec-status.sh"
ANCHOR="$here/../scripts/spec-anchor.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SYNC" ] || fail "scripts/tasks-pr-sync.sh missing or not executable"
[ -x "$RENDER" ] || fail "scripts/spec-status.sh missing or not executable"
[ -x "$ANCHOR" ] || fail "scripts/spec-anchor.sh missing or not executable"
command -v jq >/dev/null 2>&1 || fail "jq required to run this suite (hook form)"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# gh stub: deterministic, no network. Empty `pr list` by default; emits the
# canned TSV batch from GH_PRLIST when set (headRef, state, number, mergedAt —
# the merged-PR evidence the engine consumes). Mirrors test-tasks-pr-sync.sh.
stub=$tmp/bin
mkdir -p "$stub"
cat >"$stub/gh" <<'EOF'
#!/bin/sh
case "$*" in
  *"pr list"*)
    if [ -n "${GH_PRLIST:-}" ]; then printf '%s\n' "$GH_PRLIST"; fi
    exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$stub/gh"

# The v2 fixture bundle: restricted stored header + pointer line in all four
# files, a single ## Tasks section, human-payload sections. Two variants of
# tasks.md — unparked (the committed baseline) and parked (a reference bullet
# in ## Awaiting input) — identical in definition content, so the anchor must
# not move between them.
v2_heads() { # $1 = file title
  printf '%s\n' "# $1" '' '**Status:** Ready' '**Last reviewed:** 2026-07-15' \
    '**Format-version:** 2' '**Execution:** derived — see the status render' ''
}

write_v2_tasks() { # $1 = path, $2 = awaiting-input body
  {
    v2_heads "Demo — Tasks"
    printf '%s\n' '## Tasks' ''
    printf '%s\n' '### Task 1 — Alpha' '' \
      '- **Deliverables:** Alpha.' '- **Done when:** Alpha done.' \
      '- **Dependencies:** none' '- **Citations:** REQ-V2.1' \
      '- **Estimated effort:** 1 day' ''
    printf '%s\n' '### Task 2 — Beta' '' \
      '- **Deliverables:** Beta.' '- **Done when:** Beta done.' \
      '- **Dependencies:** 1' '- **Citations:** REQ-V2.2' \
      '- **Estimated effort:** 1 day' ''
    printf '%s\n' '## Awaiting input' '' "$2" ''
    printf '%s\n' '## Deferred' '' '(none yet)' ''
    printf '%s\n' '## Out of scope' '' '(none yet)'
  } >"$1"
}

repo=$tmp/repo
sd=$repo/specs/demo
mkdir -p "$sd"
git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
git -C "$repo" config commit.gpgsign false
git -C "$repo" remote add origin https://example.invalid/demo.git
v2_heads "Demo — Requirements" >"$sd/requirements.md"
v2_heads "Demo — Design" >"$sd/design.md"
v2_heads "Demo — Test Spec" >"$sd/test-spec.md"
write_v2_tasks "$sd/tasks.md" "(none yet)"
git -C "$repo" add -A
git -C "$repo" commit -qm "chore: fixture"

specs_digest() {
  (cd "$repo" && find specs -type f | LC_ALL=C sort | xargs git hash-object | git hash-object --stdin)
}

specs_clean() { # fail label if the working tree is dirty under specs/
  [ -z "$(git -C "$repo" status --porcelain -- specs)" ] \
    || fail "$1: working tree dirty under specs/ ($(git -C "$repo" status --porcelain -- specs))"
}

# run_writer <label>: both CLI arms; each must exit 0 (clean v2 no-op).
run_writer() {
  (cd "$repo" && PATH="$stub:$PATH" "$SYNC" reconcile specs/demo) >/dev/null 2>&1 \
    || fail "$1: CLI reconcile non-zero on the v2 bundle"
  (cd "$repo" && PATH="$stub:$PATH" "$SYNC" reconcile-status specs/demo) >/dev/null 2>&1 \
    || fail "$1: CLI reconcile-status non-zero on the v2 bundle"
}

# run_hook <label> <command> <stdout>: the PostToolUse hook form, cwd = repo.
run_hook() {
  (
    cd "$repo" \
      && printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"stdout":"%s","stderr":""}}' "$2" "$3" \
      | PATH="$stub:$PATH" "$SYNC"
  ) || fail "$1: hook exited non-zero"
}

# run_render <label>: the read-only render; must exit 0 and write nothing.
render_out=
run_render() {
  render_out=$(cd "$repo" && PATH="$stub:$PATH" "$RENDER" specs/demo 2>&1) \
    || fail "$1: render non-zero: $render_out"
}

anchor0=$(cd "$repo" && "$ANCHOR" specs/demo) || fail "baseline anchor failed"
d0=$(specs_digest)

# --- Stage 0: baseline — the render alone writes nothing ---------------------
run_render "stage 0"
[ "$(specs_digest)" = "$d0" ] || fail "stage 0: the render changed specs/ content"
specs_clean "stage 0"
echo "ok: stage 0 baseline — render is read-only"

# --- Stage 1: dispatch evidence (the task branch exists) ---------------------
git -C "$repo" branch planwright/demo/task-1
run_writer "stage 1"
run_render "stage 1"
[ "$(specs_digest)" = "$d0" ] || fail "stage 1 (dispatch): a derived transition changed specs/ content (REQ-A1.2)"
specs_clean "stage 1"
echo "ok: stage 1 dispatch — zero diff under specs/"

# --- Stage 2: in-progress evidence (commits ahead on the branch) -------------
git -C "$repo" checkout -q planwright/demo/task-1
git -C "$repo" commit -q --allow-empty -m "wip: task 1"
run_hook "stage 2" "gh pr create --draft" "https://github.com/x/demo/pull/41"
git -C "$repo" checkout -q main
run_writer "stage 2"
run_render "stage 2"
[ "$(specs_digest)" = "$d0" ] || fail "stage 2 (in-progress): a derived transition changed specs/ content (REQ-A1.2)"
specs_clean "stage 2"
echo "ok: stage 2 in-progress — zero diff under specs/ (hook + CLI + render)"

# --- Stage 3: merged-PR evidence (trailer merge + gh PR batch) ----------------
git -C "$repo" merge -q --no-ff -m "feat: task 1 done (#41)

Planwright-Task: demo/1" planwright/demo/task-1
export GH_PRLIST="planwright/demo/task-1${TAB}MERGED${TAB}41${TAB}2026-07-15T10:00:00Z"
run_hook "stage 3" "gh pr merge 41 --squash" "https://github.com/x/demo/pull/41"
run_writer "stage 3"
run_render "stage 3"
unset GH_PRLIST
[ "$(specs_digest)" = "$d0" ] || fail "stage 3 (merged): a derived transition changed specs/ content (REQ-A1.2)"
specs_clean "stage 3"
# Sanity: the evidence really derives completion (the no-op is not vacuous).
case "$render_out" in
  *"task 1 completed"*) ;;
  *) fail "stage 3: render does not derive task 1 completed — the churn-free run never exercised completion evidence: $render_out" ;;
esac
echo "ok: stage 3 merged-PR evidence — zero diff under specs/; completion derived, not stored"

# --- Stage 4: parking write (human payload) leaves the anchor unchanged ------
write_v2_tasks "$sd/tasks.md" "- **Task 2** — parked on a fixture question."
git -C "$repo" add -A
git -C "$repo" commit -qm "chore(spec): park task 2 awaiting input"
a_park=$(cd "$repo" && "$ANCHOR" specs/demo) || fail "stage 4: anchor failed on the parked bundle"
[ "$a_park" = "$anchor0" ] \
  || fail "stage 4 (parking): the parking commit moved the content anchor ($anchor0 -> $a_park; REQ-C1.6)"
run_render "stage 4"
case "$render_out" in
  *"task 2"*) ;;
  *) fail "stage 4: render lost task 2 after the parking write: $render_out" ;;
esac
echo "ok: stage 4 parking write — anchor unchanged (REQ-C1.6)"

# --- Stage 5: unparking write restores the baseline byte-for-byte ------------
write_v2_tasks "$sd/tasks.md" "(none yet)"
git -C "$repo" add -A
git -C "$repo" commit -qm "chore(spec): unpark task 2"
a_unpark=$(cd "$repo" && "$ANCHOR" specs/demo) || fail "stage 5: anchor failed after unparking"
[ "$a_unpark" = "$anchor0" ] \
  || fail "stage 5 (unparking): the unparking commit moved the content anchor (REQ-C1.6)"
[ "$(specs_digest)" = "$d0" ] || fail "stage 5: unparking did not restore the baseline specs/ content"
specs_clean "stage 5"
echo "ok: stage 5 unparking write — anchor and content back at baseline"

# --- Property: no derived transition ever produced a commit under specs/ -----
nspecs=$(git -C "$repo" log --oneline main -- specs | wc -l | tr -d ' ')
[ "$nspecs" -eq 3 ] \
  || fail "expected exactly 3 commits touching specs/ (fixture + park + unpark), got $nspecs — a derived transition committed spec content (REQ-A1.2)"
echo "ok: only human-payload writes commit spec content (REQ-A1.2)"

echo "PASS: test-invariant-churn-free.sh"
