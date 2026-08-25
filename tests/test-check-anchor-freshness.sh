#!/bin/sh
# Unit test for scripts/check-anchor-freshness.sh — the standing anchor
# freshness guard (anchor-integrity Task 4; REQ-D1.1, REQ-D1.2, REQ-D1.3,
# REQ-D1.4, REQ-D1.5; D-6). It is the permanent successor to the one-shot
# landing proof (tests/test-anchor-landing-proof.sh): the recompute walk plus
# the changelog-pairing check, the brief-less error, and the lefthook mirror.
#
# Properties verified (numbered to match the body's check sections):
#   1. Green corpus (REQ-D1.1): a fixture whose brief anchors recompute equal
#      exits 0 and reports one `ok` record per bundle.
#   2. Stale anchor (REQ-D1.1): a recorded hash that no longer recomputes is an
#      error naming both hashes.
#   3. Non-sanctioned form and unparseable entry (REQ-D1.1, REQ-D1.5): a
#      command outside the sanctioned grammar, a shell-injected suffix, a
#      substitution, and an out-of-tree `<spec-dir>` are each refused with no
#      execution side effect; a brief whose entry carries no anchor line at all
#      is an error.
#   4. Most-recent-entry selection (REQ-D1.1): with an older fresh entry and a
#      newer stale one, the newer is the one checked (and vice versa) — including
#      when the entries sit on physically adjacent lines, where a parser that
#      reads ahead can swallow one and anchor on the older hash.
#   5. Every sanctioned form accepted (REQ-D1.1, REQ-F1.1): the canonical
#      repo-relative form, the resolution-aware logical form, and the interim
#      whole-file form each recompute; a sanctioned form that resolves to
#      nothing is the fail-closed absent-anchor-class error.
#   6. Skip semantics (REQ-D1.4): Draft, Retired, and Superseded bundles are
#      notices and keep the run green; a brief-less Ready bundle is an error
#      naming the repair remedy.
#   7. Known-parked notice (REQ-D1.1): a stale bundle carrying the live
#      `anchor re-review pending` marker in `## Awaiting input` reports as a
#      notice and exits 0; the same words outside that section do not exempt.
#   8. Changelog pairing (REQ-D1.2): an edit to anchored content since the
#      baseline is an error without a dated Changelog entry and green with one;
#      an edit confined to excluded content (a header Status flip, a tasks.md
#      annotation, a block move) stays green with no entry; and an edit made on
#      the baseline branch after the fork point is not this branch's unpaired
#      edit (the comparison is against the merge base, not the ref tip).
#   9. Baseline handling (REQ-D1.2, REQ-D1.5): an unresolvable DEFAULT baseline
#      degrades the pairing check to a skip-with-notice; an explicit
#      `--baseline` that cannot be used is fatal; a baseline value outside the
#      ref grammar is rejected before any git invocation.
#  10. Diagnostics are sanitized (REQ-D1.5): control bytes in parsed content do
#      not reach the output raw.
#  11. Wiring (REQ-D1.3): `mise.toml` runs the guard in the `check` aggregate,
#      and `lefthook.yml` mirrors it on pre-commit scoped to staged `specs/**`.
#
# Runs standalone under /bin/bash (the bash 3.2 floor) and /bin/sh.
set -eu

# Pin the C locale: range patterns are collation-dependent under UTF-8.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into command substitutions,
# corrupting derived paths (house pattern, see sibling tests).
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
GUARD="$repo/scripts/check-anchor-freshness.sh"
ANCHOR="$repo/scripts/spec-anchor.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$GUARD" ] || fail "scripts/check-anchor-freshness.sh missing or not executable"
[ -x "$ANCHOR" ] || fail "scripts/spec-anchor.sh missing or not executable"

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

# run_guard <specs-root> [args...] — run the guard, capturing combined output
# in $OUT and the exit code in $RC. The guard is invoked with the fixture's
# specs root so every case is a self-contained corpus.
OUT=
RC=0
run_guard() {
  rg_root=$1
  shift
  RC=0
  OUT=$("$GUARD" "$@" "$rg_root" 2>&1) || RC=$?
}

assert_rc() {
  [ "$RC" = "$2" ] || fail "$1: expected exit $2, got $RC. Output:
$OUT"
}

assert_has() {
  case $OUT in
    *"$2"*) ;;
    *) fail "$1: expected output to contain '$2'. Output:
$OUT" ;;
  esac
}

assert_lacks() {
  case $OUT in
    *"$2"*) fail "$1: expected output NOT to contain '$2'. Output:
$OUT" ;;
    *) ;;
  esac
}

# --- fixture builders ---------------------------------------------------

# make_bundle <specs-root> <name> <status> <body-marker>
make_bundle() {
  mb_dir="$1/$2"
  mkdir -p "$mb_dir"
  printf '%s\n' "# $2 — Requirements" '' "**Status:** $3" '' '## Goal' '' "$4" \
    '' '## Changelog' '' '- 2026-01-01 — Initial draft.' >"$mb_dir/requirements.md"
  printf '%s\n' "# $2 — Design" '' "**Status:** $3" '' '### D-1: A decision' '' 'A design body.' >"$mb_dir/design.md"
  printf '%s\n' "# $2 — Test Spec" '' "**Status:** $3" '' '## REQ-X' '' 'A test-spec body.' >"$mb_dir/test-spec.md"
  cat >"$mb_dir/tasks.md" <<EOF
# $2 — Tasks

**Status:** $3

## Tasks

### Task 1 — A task

- **Deliverables:** A thing.
- **Done when:** The thing exists.
- **Dependencies:** none
- **Citations:** REQ-X1.1
- **Estimated effort:** half day

## Awaiting input

(none yet)
EOF
}

# write_entry <specs-root> <name> <hash> [command] — a single-entry brief.
write_entry() {
  we_cmd=${4:-"scripts/spec-anchor.sh specs/$2"}
  cat >"$1/$2/kickoff-brief.md" <<EOF
# $2 — Kickoff Brief

## Amendment log

Class: expression-only
Anchor: \`$3\` — computed as
\`$we_cmd\`
EOF
}

# append_entry <specs-root> <name> <hash> [command] — a later entry, so the
# brief carries more than one and the most-recent selection is exercised.
append_entry() {
  ae_cmd=${4:-"scripts/spec-anchor.sh specs/$2"}
  cat >>"$1/$2/kickoff-brief.md" <<EOF

### A later amendment

Class: expression-only
Anchor: \`$3\` — computed as
\`$ae_cmd\`
EOF
}

# append_inline_entry <specs-root> <name> <hash> — a later entry in the
# single-line parenthesized layout, appended with no blank line, so two
# `Anchor:` lines land physically adjacent. That adjacency is what a parser
# reading the following line can silently swallow.
append_inline_entry() {
  # SC2016: the backticks are Markdown, not command substitution, and the
  # single quotes keep them literal in the printf format.
  # shellcheck disable=SC2016
  printf 'Anchor: `%s` (`scripts/spec-anchor.sh specs/%s`)\n' "$3" "$2" \
    >>"$1/$2/kickoff-brief.md"
}

# park <specs-root> <name> — write the live park marker into Awaiting input.
park() {
  awk '
    /^## Awaiting input/ { print; print ""; print "- **anchor re-review pending** — routed to its re-review ritual."; skip = 1; next }
    skip && /^\(none yet\)$/ { skip = 0; next }
    { print }
  ' "$1/$2/tasks.md" >"$1/$2/tasks.md.new"
  mv "$1/$2/tasks.md.new" "$1/$2/tasks.md"
}

stale=0000000000000000000000000000000000000000

########################################################################
# 1. Green corpus
########################################################################
f1="$tmp/f1/specs"
mkdir -p "$f1"
make_bundle "$f1" green Ready 'A requirement body.'
write_entry "$f1" green "$("$ANCHOR" "$f1/green")"

run_guard "$f1"
assert_rc "green corpus exits 0" 0
# Assert the record itself, not the bare word "ok": that substring also appears
# in the summary line, so a looser check would pass on a corpus that reported
# nothing at all.
assert_has "green corpus reports an ok record for the bundle" \
  "ok     green — anchor $("$ANCHOR" "$f1/green")"
assert_has "the summary counts exactly one ok and no errors" "1 ok, 0 notice(s), 0 error(s)"

########################################################################
# 2. Stale anchor
########################################################################
f2="$tmp/f2/specs"
mkdir -p "$f2"
make_bundle "$f2" drifted Ready 'A requirement body.'
write_entry "$f2" drifted "$stale"

run_guard "$f2"
assert_rc "a stale anchor fails the guard" 1
assert_has "the stale record names the recorded hash" "$stale"
assert_has "the stale record names the recomputed hash" "$("$ANCHOR" "$f2/drifted")"

########################################################################
# 3. Non-sanctioned forms, injection shapes, and an unparseable entry
########################################################################
f3="$tmp/f3/specs"
mkdir -p "$f3"
for name in nonsanctioned injected substituted outoftree; do
  make_bundle "$f3" "$name" Ready 'A requirement body.'
done
canary="$tmp/f3-canary"
write_entry "$f3" nonsanctioned "$("$ANCHOR" "$f3/nonsanctioned")" "sha1sum specs/nonsanctioned/*"
write_entry "$f3" injected "$("$ANCHOR" "$f3/injected")" "scripts/spec-anchor.sh specs/injected; touch $canary"
# SC2016: the single quotes are the point — the substitution must reach the
# guard as literal recorded bytes, never expanded by this test's own shell.
# shellcheck disable=SC2016
write_entry "$f3" substituted "$("$ANCHOR" "$f3/substituted")" 'scripts/spec-anchor.sh specs/$(id -un)'
write_entry "$f3" outoftree "$("$ANCHOR" "$f3/outoftree")" "scripts/spec-anchor.sh ../../etc"

run_guard "$f3"
assert_rc "non-sanctioned forms fail the guard" 1
for name in nonsanctioned injected substituted outoftree; do
  assert_has "$name is refused as non-sanctioned" "$name"
done
[ ! -e "$canary" ] || fail "the injected suffix executed: $canary exists"

# An entry with no anchor line at all is unparseable, not a silent pass.
f3b="$tmp/f3b/specs"
mkdir -p "$f3b"
make_bundle "$f3b" noentry Ready 'A requirement body.'
printf '%s\n' '# noentry — Kickoff Brief' '' 'Signed off: 2026-01-01' >"$f3b/noentry/kickoff-brief.md"
run_guard "$f3b"
assert_rc "a brief with no anchor entry fails the guard" 1
assert_has "the no-entry record says so" "no parseable anchor entry"

########################################################################
# 4. Most-recent-entry selection
########################################################################
f4="$tmp/f4/specs"
mkdir -p "$f4"
make_bundle "$f4" newerstale Ready 'A requirement body.'
write_entry "$f4" newerstale "$("$ANCHOR" "$f4/newerstale")"
append_entry "$f4" newerstale "$stale"
run_guard "$f4"
assert_rc "an older-fresh/newer-stale pair fails on the newer entry" 1
assert_has "the failure names the newer (stale) hash" "$stale"

f4b="$tmp/f4b/specs"
mkdir -p "$f4b"
make_bundle "$f4b" newerfresh Ready 'A requirement body.'
write_entry "$f4b" newerfresh "$stale"
append_entry "$f4b" newerfresh "$("$ANCHOR" "$f4b/newerfresh")"
run_guard "$f4b"
assert_rc "an older-stale/newer-fresh pair passes on the newer entry" 0

# Adjacency: two single-line entries on consecutive lines, the newer one stale.
# Nothing separates them, so a parser that reads ahead to find the command can
# consume the second entry as the first one's continuation and check the older
# hash — reporting green over a stale anchor, the one failure this guard exists
# to prevent.
f4c="$tmp/f4c/specs"
mkdir -p "$f4c"
make_bundle "$f4c" adjacent Ready 'A requirement body.'
write_entry "$f4c" adjacent "$("$ANCHOR" "$f4c/adjacent")"
append_inline_entry "$f4c" adjacent "$("$ANCHOR" "$f4c/adjacent")"
append_inline_entry "$f4c" adjacent "$stale"
run_guard "$f4c"
assert_rc "an entry adjacent to the previous one is still the one checked" 1
assert_has "the adjacent-entry failure names the newer (stale) hash" "$stale"

# The mirror image, and the reason an off-by-one here is not self-announcing:
# with the fresh entry last, skipping it lands on the older stale one and the
# guard goes red on a bundle that is in fact current.
f4d="$tmp/f4d/specs"
mkdir -p "$f4d"
make_bundle "$f4d" adjacentfresh Ready 'A requirement body.'
write_entry "$f4d" adjacentfresh "$stale"
append_inline_entry "$f4d" adjacentfresh "$stale"
append_inline_entry "$f4d" adjacentfresh "$("$ANCHOR" "$f4d/adjacentfresh")"
run_guard "$f4d"
assert_rc "an adjacent newer-fresh entry is honoured, not skipped" 0

########################################################################
# 5. Every sanctioned form; and a form that resolves to nothing
########################################################################
f5="$tmp/f5/specs"
mkdir -p "$f5"

make_bundle "$f5" canonical Ready 'A requirement body.'
write_entry "$f5" canonical "$("$ANCHOR" "$f5/canonical")" "scripts/spec-anchor.sh specs/canonical"

make_bundle "$f5" logical Ready 'A requirement body.'
write_entry "$f5" logical "$("$ANCHOR" "$f5/logical")" "spec-anchor.sh specs/logical"

make_bundle "$f5" interim Ready 'A requirement body.'
interim_hash=$(cd "$f5/interim" && git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin)
write_entry "$f5" interim "$interim_hash" \
  "git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin"

# The fixture tree has no scripts/ of its own, so the two script-based forms
# resolve through the root chain — pointed here at this repo.
PLANWRIGHT_ROOT="$repo" run_guard "$f5"
assert_rc "every sanctioned form recomputes" 0
assert_has "the canonical form is accepted" "canonical"
assert_has "the logical form is accepted" "logical"
assert_has "the interim whole-file form is accepted" "interim"

# A sanctioned form that resolves to nothing is the fail-closed
# absent-anchor-class error, never a silent match. The fixture is a tree that
# carries the guard and its grammar lib but no spec-anchor.sh, so the checked
# tree, the three env arms, and the self-location arm all miss.
f5b="$tmp/f5b"
mkdir -p "$f5b/scripts" "$f5b/specs"
cp "$GUARD" "$f5b/scripts/"
cp "$repo/scripts/spec-parse.sh" "$f5b/scripts/"
make_bundle "$f5b/specs" unresolvable Ready 'A requirement body.'
write_entry "$f5b/specs" unresolvable "$("$ANCHOR" "$f5b/specs/unresolvable")" \
  "spec-anchor.sh specs/unresolvable"
RC=0
OUT=$(PLANWRIGHT_ROOT="$tmp/nowhere" CLAUDE_PLUGIN_ROOT="$tmp/nowhere" CLAUDE_DIR="$tmp/nowhere" \
  "$f5b/scripts/check-anchor-freshness.sh" "$f5b/specs" 2>&1) || RC=$?
assert_rc "an unresolvable sanctioned form fails closed" 1
assert_has "the unresolvable record names the absent-anchor class" "absent-anchor"

########################################################################
# 6. Skip semantics and the brief-less error
########################################################################
f6="$tmp/f6/specs"
mkdir -p "$f6"
make_bundle "$f6" drafted Draft 'A requirement body.'
write_entry "$f6" drafted "$stale"
make_bundle "$f6" retired Retired 'A requirement body.'
write_entry "$f6" retired "$stale"
make_bundle "$f6" superseded Superseded 'A requirement body.'
write_entry "$f6" superseded "$stale"
run_guard "$f6"
assert_rc "Draft and terminal bundles are skipped, not failed" 0
assert_has "the Draft skip is a notice" "Draft"
assert_has "the Retired skip is a notice" "Retired"
assert_has "the Superseded skip is a notice" "Superseded"

f6b="$tmp/f6b/specs"
mkdir -p "$f6b"
make_bundle "$f6b" briefless Ready 'A requirement body.'
run_guard "$f6b"
assert_rc "a brief-less Ready bundle is an error" 1
assert_has "the brief-less error names the repair remedy" "/spec-kickoff"

########################################################################
# 7. Known-parked notice
########################################################################
f7="$tmp/f7/specs"
mkdir -p "$f7"
make_bundle "$f7" parked Ready 'A requirement body.'
write_entry "$f7" parked "$stale"
park "$f7" parked
run_guard "$f7"
assert_rc "a parked stale bundle keeps the guard green" 0
assert_has "the parked bundle reports as known-parked" "known-parked"

# The same words outside `## Awaiting input` are prose, not a park.
f7b="$tmp/f7b/specs"
mkdir -p "$f7b"
make_bundle "$f7b" mislabelled Ready 'Prose mentioning anchor re-review pending.'
write_entry "$f7b" mislabelled "$stale"
printf '\n## Deferred\n\n- anchor re-review pending (a note, in the wrong section)\n' \
  >>"$f7b/mislabelled/tasks.md"
run_guard "$f7b"
assert_rc "a park marker outside Awaiting input does not exempt" 1

########################################################################
# 8. Changelog pairing against a baseline ref
########################################################################
# A real git repo: the pairing check reads the bundle at the baseline ref.
mkrepo() {
  mr_root=$1
  mkdir -p "$mr_root"
  git -C "$mr_root" init -q
  git -C "$mr_root" config user.email t@example.com
  git -C "$mr_root" config user.name Test
  git -C "$mr_root" config commit.gpgsign false
}

commit_all() {
  git -C "$1" add -A
  git -C "$1" -c core.hooksPath=/dev/null commit -q -m "$2"
}

r8="$tmp/r8"
mkrepo "$r8"
mkdir -p "$r8/specs"
make_bundle "$r8/specs" paired Ready 'A requirement body.'
write_entry "$r8/specs" paired "$("$ANCHOR" "$r8/specs/paired")"
commit_all "$r8" "seed"
base=$(git -C "$r8" rev-parse HEAD)

# 8a. An anchored-content edit with no new Changelog entry is an error.
printf '\nAn out-of-flow meaning edit.\n' >>"$r8/specs/paired/design.md"
write_entry "$r8/specs" paired "$("$ANCHOR" "$r8/specs/paired")"
run_guard "$r8/specs" --baseline "$base"
assert_rc "an anchored edit with no Changelog entry fails" 1
assert_has "the pairing error says what is missing" "Changelog"

# 8b. The same edit with a dated Changelog entry is green.
printf '%s\n' '- 2026-02-02 — The out-of-flow edit, recorded.' >>"$r8/specs/paired/requirements.md"
write_entry "$r8/specs" paired "$("$ANCHOR" "$r8/specs/paired")"
run_guard "$r8/specs" --baseline "$base"
assert_rc "an anchored edit paired with a Changelog entry passes" 0

# 8b-ii. The Changelog may live in any of the bundle's four files, not only
#        requirements.md: design.md and test-spec.md carry one in this repo's
#        own corpus, so an edit paired there must count too.
r8e="$tmp/r8e"
mkrepo "$r8e"
mkdir -p "$r8e/specs"
make_bundle "$r8e/specs" designlog Ready 'A requirement body.'
printf '%s\n' '' '## Changelog' '' '- 2026-01-01 — Initial draft.' >>"$r8e/specs/designlog/design.md"
write_entry "$r8e/specs" designlog "$("$ANCHOR" "$r8e/specs/designlog")"
commit_all "$r8e" "seed"
basee=$(git -C "$r8e" rev-parse HEAD)

printf '\nAn out-of-flow meaning edit.\n' >>"$r8e/specs/designlog/test-spec.md"
write_entry "$r8e/specs" designlog "$("$ANCHOR" "$r8e/specs/designlog")"
run_guard "$r8e/specs" --baseline "$basee"
assert_rc "the unpaired edit is caught when no file gained an entry" 1

printf '%s\n' '- 2026-02-02 — The out-of-flow edit, recorded in design.md.' \
  >>"$r8e/specs/designlog/design.md"
write_entry "$r8e/specs" designlog "$("$ANCHOR" "$r8e/specs/designlog")"
run_guard "$r8e/specs" --baseline "$basee"
assert_rc "a Changelog entry in design.md pairs the edit just as one in requirements.md would" 0

# 8c. False-positive direction: edits confined to EXCLUDED content need no
#     entry — a header Status flip, a tasks.md annotation, and a block move.
r8c="$tmp/r8c"
mkrepo "$r8c"
mkdir -p "$r8c/specs"
make_bundle "$r8c/specs" excluded Ready 'A requirement body.'
write_entry "$r8c/specs" excluded "$("$ANCHOR" "$r8c/specs/excluded")"
commit_all "$r8c" "seed"
basec=$(git -C "$r8c" rev-parse HEAD)

for f in requirements design tasks test-spec; do
  sed 's/^\*\*Status:\*\* Ready$/**Status:** Active/' "$r8c/specs/excluded/$f.md" >"$r8c/specs/excluded/$f.md.new"
  mv "$r8c/specs/excluded/$f.md.new" "$r8c/specs/excluded/$f.md"
done
# A state annotation and a block move: both outside the canonical extraction.
awk '
  /^## Tasks$/ { print "## Forward plan"; next }
  /^### Task 1 / { print; print ""; print "- **Status:** implementing"; next }
  { print }
' "$r8c/specs/excluded/tasks.md" >"$r8c/specs/excluded/tasks.md.new"
mv "$r8c/specs/excluded/tasks.md.new" "$r8c/specs/excluded/tasks.md"

run_guard "$r8c/specs" --baseline "$basec"
assert_rc "edits confined to excluded content stay green with no Changelog entry" 0
assert_lacks "no pairing finding is reported for excluded-only edits" "Changelog entry"

# 8d. The baseline moves ahead. An edit made on the BASELINE branch, to a
#     bundle this branch never touched, is not this branch's unpaired edit:
#     the comparison is against the merge base, not the ref tip.
r8d="$tmp/r8d"
mkrepo "$r8d"
mkdir -p "$r8d/specs"
make_bundle "$r8d/specs" untouched Ready 'A requirement body.'
write_entry "$r8d/specs" untouched "$("$ANCHOR" "$r8d/specs/untouched")"
commit_all "$r8d" "seed"
git -C "$r8d" branch -q feature
printf '\nA meaning edit made on the baseline branch.\n' >>"$r8d/specs/untouched/design.md"
write_entry "$r8d/specs" untouched "$("$ANCHOR" "$r8d/specs/untouched")"
commit_all "$r8d" "baseline moves ahead"
mainref=$(git -C "$r8d" rev-parse HEAD)
git -C "$r8d" -c core.hooksPath=/dev/null checkout -q feature
run_guard "$r8d/specs" --baseline "$mainref"
assert_rc "a baseline branch that moved ahead is not an unpaired local edit" 0
assert_lacks "no pairing finding for a bundle this branch never touched" "Changelog entry"

########################################################################
# 9. Baseline handling
########################################################################
# 9a. An unresolvable DEFAULT baseline degrades the pairing check to a notice.
run_guard "$r8/specs"
assert_rc "an unresolvable default baseline degrades, not fails" 0
assert_has "the degradation is announced" "pairing check skipped"

# 9b. An explicit --baseline that cannot be used is fatal.
run_guard "$r8/specs" --baseline refs/heads/no-such-ref
assert_rc "an explicit baseline that does not resolve is fatal" 2
assert_has "the fatal baseline names the failure" "baseline"

# 9c. A baseline value outside the ref grammar is rejected before git runs.
run_guard "$r8/specs" --baseline '--upload-pack=touch /tmp/x'
assert_rc "an out-of-grammar baseline value is rejected" 2

# A bundle directory whose name is not a valid spec identifier cannot be
# checked at all: fail closed naming that cause, rather than blaming the
# brief's entry for the directory's fault.
f7c="$tmp/f7c/specs"
mkdir -p "$f7c"
make_bundle "$f7c" 'Bad_Name' Ready 'A requirement body.'
write_entry "$f7c" 'Bad_Name' "$("$ANCHOR" "$f7c/Bad_Name")" "scripts/spec-anchor.sh specs/Bad_Name"
run_guard "$f7c"
assert_rc "an off-grammar bundle directory fails closed" 1
assert_has "the off-grammar error names the identifier rule, not the brief" "not a valid spec identifier"
assert_has "the quoted rule is the real one, not a two-character pattern" '^[a-z0-9][a-z0-9-]*$'
assert_lacks "it does not misreport as a non-sanctioned form" "non-sanctioned command form"

########################################################################
# 10. Diagnostics are sanitized
########################################################################
f10="$tmp/f10/specs"
mkdir -p "$f10"
make_bundle "$f10" bytes Ready 'A requirement body.'
# A recorded command carrying an ESC byte: refused as non-sanctioned, and the
# diagnostic must not put the raw escape on the terminal.
esc=$(printf '\033')
write_entry "$f10" bytes "$("$ANCHOR" "$f10/bytes")" "scripts/spec-anchor.sh specs/${esc}[31mbytes"
run_guard "$f10"
assert_rc "a control-byte command is refused" 1
case $OUT in
  *"$esc"*) fail "the diagnostic echoed a raw ESC byte from the recorded command" ;;
  *) ;;
esac

# The other parsed value that reaches a diagnostic is the header Status: the
# grammar lib returns declaration values RAW, and an in-scope status (anything
# outside the Draft/Retired/Superseded literals) is echoed back in the
# brief-less error. It must go through the sanitizer too.
f10b="$tmp/f10b/specs"
mkdir -p "$f10b"
make_bundle "$f10b" statusbytes Ready 'A requirement body.'
sed "s/^\*\*Status:\*\* Ready$/**Status:** Ready${esc}[31mX/" "$f10b/statusbytes/requirements.md" \
  >"$f10b/statusbytes/requirements.md.new"
mv "$f10b/statusbytes/requirements.md.new" "$f10b/statusbytes/requirements.md"
rm -f "$f10b/statusbytes/kickoff-brief.md"
run_guard "$f10b"
assert_rc "a brief-less bundle with a control-byte status is an error" 1
case $OUT in
  *"$esc"*) fail "the diagnostic echoed a raw ESC byte from the parsed Status" ;;
  *) ;;
esac

########################################################################
# 11. Wiring: the CI aggregate and the lefthook pre-commit mirror
########################################################################
grep -q 'check:anchor-freshness' "$repo/mise.toml" \
  || fail "mise.toml has no check:anchor-freshness task"
grep -q '"check:anchor-freshness"' "$repo/mise.toml" \
  || fail "mise.toml's check aggregate does not depend on check:anchor-freshness"
grep -q '^lefthook = ' "$repo/mise.toml" \
  || fail "mise.toml pins no lefthook version for the pre-commit mirror"

[ -f "$repo/lefthook.yml" ] || fail "lefthook.yml missing (the pre-commit mirror)"
grep -q 'check-anchor-freshness.sh' "$repo/lefthook.yml" \
  || fail "lefthook.yml does not invoke the guard"
grep -q 'specs/\*\*' "$repo/lefthook.yml" \
  || fail "lefthook.yml does not scope the mirror to staged specs/** content"
grep -q 'no_auto_install: true' "$repo/lefthook.yml" \
  || fail "lefthook.yml must not let lefthook rewrite the tracked githooks/ dir"

[ -x "$repo/githooks/pre-commit" ] \
  || fail "githooks/pre-commit missing or not executable (the mirror's install path)"
grep -q 'lefthook' "$repo/githooks/pre-commit" \
  || fail "githooks/pre-commit does not dispatch to lefthook"

# The mirror is best-effort: with no lefthook on PATH the hook is a clean
# no-op, so a contributor without the toolchain can still commit.
mkdir -p "$tmp/emptypath"
RC=0
OUT=$(cd "$repo" && PATH="$tmp/emptypath" /bin/sh githooks/pre-commit 2>&1) || RC=$?
assert_rc "the pre-commit mirror no-ops when lefthook is absent" 0

# And when lefthook IS available, the config parses and the scoped job is real.
if command -v lefthook >/dev/null 2>&1; then
  RC=0
  OUT=$(cd "$repo" && lefthook validate 2>&1) || RC=$?
  assert_rc "lefthook.yml validates" 0
else
  echo "note: lefthook not on PATH; config asserted statically only"
fi

echo "all check-anchor-freshness tests passed"
