#!/bin/sh
# test-anchor-sweep.sh — unit tests for scripts/anchor-sweep.sh, the
# re-anchor sweep REQ-C1.4 requires of any parser change that moves a shipped
# bundle's content anchor (format-grammar Task 6 · D-9).
#
# Properties verified:
#   1. A bundle whose brief records the anchor the current tool computes is
#      reported `ok`, and a clean sweep exits 0.
#   2. The synthetic trip fixture: a bundle whose recorded anchor is the one
#      the FENCE-BLIND parser computed is reported `moved` with a non-zero
#      exit, and appending the paired expression-only re-anchor entry clears
#      it — the pairing REQ-C1.4 exists to force.
#   3. A bundle with no kickoff brief, or no anchor entry in one, is
#      `unanchored`: there is no recorded anchor for a freshness gate to trip
#      on, so it is reported without failing the sweep.
#   4. Both sanctioned command forms are honored, each recomputed with the
#      form the entry actually recorded (doctrine/spec-format.md, *Sanctioned
#      command forms*): the canonical `scripts/spec-anchor.sh <spec-dir>` and
#      the interim whole-file `git hash-object` pipeline.
#   5. The MOST RECENT entry is the one compared: an earlier entry's stale
#      anchor does not resurrect a bundle a later re-anchor already settled.
#   6. Fail-closed: an anchor-tool error and an unparseable anchor entry both
#      exit non-zero rather than reporting a bundle clean by omission.
#
# Runs standalone: ./tests/test-anchor-sweep.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
sweep="$here/../scripts/anchor-sweep.sh"
anchor="$here/../scripts/spec-anchor.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$sweep" ] || fail "scripts/anchor-sweep.sh missing or not executable"

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

# run_s <expected-exit> <args...> — run the sweep, capture combined output in
# $out, fail the suite if the exit code differs.
out=
run_s() {
  expect=$1
  shift
  rc=0
  out=$("$sweep" "$@" 2>&1) || rc=$?
  [ "$rc" -eq "$expect" ] \
    || fail "expected exit $expect, got $rc for: $* — output: $out"
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

# write_bundle <dir> [extra-tasks-content] — a minimal four-file bundle. The
# optional second argument is appended to tasks.md verbatim.
write_bundle() {
  wb_dir=$1
  mkdir -p "$wb_dir"
  printf '# Fixture — Requirements\n\n**Status:** Ready\n**Format-version:** 2\n' \
    >"$wb_dir/requirements.md"
  printf '# Fixture — Design\n\n**Status:** Ready\n**Format-version:** 2\n' \
    >"$wb_dir/design.md"
  printf '# Fixture — Test Spec\n\n**Status:** Ready\n**Format-version:** 2\n' \
    >"$wb_dir/test-spec.md"
  {
    printf '# Fixture — Tasks\n\n**Status:** Ready\n**Format-version:** 2\n\n'
    printf '## Tasks\n\n'
    printf '### Task 1 — Build the widget\n\n'
    printf -- '- **Deliverables:** A widget.\n'
    printf -- '- **Done when:** The widget exists.\n'
    printf -- '- **Dependencies:** none\n'
    printf -- '- **Citations:** D-1\n'
    printf -- '- **Estimated effort:** half day\n'
    [ $# -lt 2 ] || printf '%s' "$2"
  } >"$wb_dir/tasks.md"
}

# write_brief <dir> <hash> — a brief carrying one canonical-form anchor entry.
# shellcheck disable=SC2016 # literal anchor-entry lines, never expanded
write_brief() {
  {
    printf '# Fixture — Kickoff brief\n\n## 8. Sign-off\n\n'
    printf 'Class: meaning\nLens-pass: recorded above\n'
    printf 'Anchor: `%s` — computed as\n' "$2"
    printf '`scripts/spec-anchor.sh specs/%s`\n' "$(basename "$1")"
  } >"$1/kickoff-brief.md"
}

# ---------------------------------------------------------------------------
# 1. A bundle recording the current anchor sweeps clean.
# ---------------------------------------------------------------------------
root="$tmp/specs"
write_bundle "$root/clean"
write_brief "$root/clean" "$("$anchor" "$root/clean")"
run_s 0 "$root"
has "ok	clean"

# ---------------------------------------------------------------------------
# 2. The synthetic trip fixture (REQ-C1.4).
#
# The bundle carries fenced task-shaped lines. Its recorded anchor is the one
# the FENCE-BLIND parser computed for it — reproduced here without keeping a
# copy of that parser around, because the two are the same digest by
# construction: the fence-blind extraction of the fenced file keeps exactly the
# lines the fence-aware extraction of the same file WITHOUT its fence markers
# keeps (a bare ``` line is not a definition line, so neither parser ever
# emitted one). Deleting the markers therefore reproduces the old digest
# exactly, and the sweep sees precisely what landing this parser change did to
# a bundle that documents the task-block format in a fence.
# ---------------------------------------------------------------------------
fenced_tail='
## Notes

A task block is written like this:

```markdown
### Task 9 — A mock block that is documentation, not a task

- **Deliverables:** Nothing real.
- **Done when:** Never.
- **Dependencies:** none
- **Citations:** D-9
- **Estimated effort:** 1 day
```
'
write_bundle "$root/tripped" "$fenced_tail"

# The pre-change digest, via the marker-free twin described above.
write_bundle "$tmp/twin" "$fenced_tail"
awk '!/^```/' "$tmp/twin/tasks.md" >"$tmp/twin/tasks.new"
mv "$tmp/twin/tasks.new" "$tmp/twin/tasks.md"
old_anchor=$("$anchor" "$tmp/twin") || fail "computing the pre-change anchor failed"
new_anchor=$("$anchor" "$root/tripped") || fail "computing the current anchor failed"
[ "$old_anchor" != "$new_anchor" ] \
  || fail "the trip fixture does not actually move the anchor; it proves nothing"

write_brief "$root/tripped" "$old_anchor"
run_s 1 "$root"
has "moved	tripped"
has "$old_anchor"
has "$new_anchor"
has "ok	clean"

# Appending the paired expression-only re-anchor entry clears it — and the
# sweep is what proves the pairing happened.
# shellcheck disable=SC2016 # literal anchor-entry lines, never expanded
{
  printf '\n## 9. Amendment log\n\n### 2026-08-24 — Expression-only self-re-anchor\n\n'
  printf 'Class: expression-only\n'
  printf 'Anchor: `%s` — computed as\n' "$new_anchor"
  printf '`scripts/spec-anchor.sh specs/tripped`\n'
} >>"$root/tripped/kickoff-brief.md"
run_s 0 "$root"
has "ok	tripped"
lacks "moved"

# ---------------------------------------------------------------------------
# 3. No brief, and a brief with no anchor entry, are both `unanchored`.
# ---------------------------------------------------------------------------
write_bundle "$root/nobrief"
run_s 0 "$root"
has "unanchored	nobrief"

printf '# Fixture — Kickoff brief\n\nNo sign-off record yet.\n' \
  >"$root/nobrief/kickoff-brief.md"
run_s 0 "$root"
has "unanchored	nobrief"
rm -rf "$root/nobrief"

# ---------------------------------------------------------------------------
# 4. The interim whole-file form is recomputed with the interim form.
# ---------------------------------------------------------------------------
write_bundle "$root/interim"
interim=$(cd "$root/interim" \
  && git hash-object requirements.md design.md tasks.md test-spec.md \
  | git hash-object --stdin)
# shellcheck disable=SC2016 # literal anchor-entry lines, never expanded
{
  printf '# Fixture — Kickoff brief\n\n## 8. Sign-off\n\n'
  printf 'Class: meaning\n'
  printf 'Anchor: `%s` — computed as\n' "$interim"
  printf '`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`\n'
} >"$root/interim/kickoff-brief.md"
run_s 0 "$root"
has "ok	interim"

# It is genuinely the interim form being recomputed, not the canonical one
# coincidentally agreeing: the two forms differ for any bundle with tasks.
[ "$interim" != "$("$anchor" "$root/interim")" ] \
  || fail "the interim and canonical forms agree; the fixture proves nothing"
rm -rf "$root/interim"

# ---------------------------------------------------------------------------
# 5. The most recent entry wins.
# ---------------------------------------------------------------------------
write_bundle "$root/resettled"
write_brief "$root/resettled" "0000000000000000000000000000000000000000"
# shellcheck disable=SC2016 # literal anchor-entry lines, never expanded
{
  printf '\n### 2026-08-24 — Expression-only self-re-anchor\n\n'
  printf 'Class: expression-only\n'
  printf 'Anchor: `%s` — computed as\n' "$("$anchor" "$root/resettled")"
  printf '`scripts/spec-anchor.sh specs/resettled`\n'
} >>"$root/resettled/kickoff-brief.md"
run_s 0 "$root"
has "ok	resettled"
rm -rf "$root/resettled"

# ---------------------------------------------------------------------------
# 6. Fail-closed: an anchor-tool error and an unparseable entry.
# ---------------------------------------------------------------------------
# Duplicate task ids make the canonical extraction refuse. The sweep must not
# read that as "unchanged".
write_bundle "$root/broken"
cat >>"$root/broken/tasks.md" <<'EOF'

### Task 1 — A duplicate id

- **Deliverables:** A second widget.
- **Done when:** Never.
- **Dependencies:** none
- **Citations:** D-1
- **Estimated effort:** half day
EOF
write_brief "$root/broken" "0000000000000000000000000000000000000000"
run_s 3 "$root"
has "error	broken"
rm -rf "$root/broken"

# An entry whose anchor line carries no digest at all (the fail-closed shape a
# killed kickoff leaves behind) is not silently skipped.
write_bundle "$root/unparseable"
{
  printf '# Fixture — Kickoff brief\n\n## 8. Sign-off\n\n'
  printf 'Anchor: (none — fail closed)\n'
} >"$root/unparseable/kickoff-brief.md"
run_s 3 "$root"
has "unparseable	unparseable"
rm -rf "$root/unparseable"

# A clean root is still clean afterwards.
run_s 0 "$root"

# ---------------------------------------------------------------------------
# Usage errors.
# ---------------------------------------------------------------------------
run_s 2
run_s 2 "$tmp/does-not-exist"

echo "PASS: test-anchor-sweep"
