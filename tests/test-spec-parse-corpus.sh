#!/bin/bash
# test-spec-parse-corpus.sh — the cross-consumer equivalence suite for the
# shared spec-parse grammar lib (format-grammar Task 2; REQ-B1.3, REQ-B1.4,
# REQ-B1.6, REQ-C1.1, REQ-C1.3, REQ-D1.9 · D-6, D-7, D-8).
#
# tests/test-spec-parse.sh pins what the LIB does. This file pins that the
# consumers actually consume it, over ONE shared fixture corpus, so the four v2
# parked-map parsers and the eight version-parse consumers cannot re-diverge
# (obs:5782486b, obs:22878c2c — the divergence this task exists to end).
#
# Properties verified:
#   1. All four v2 parked-map parsers (spec-status.sh, orchestrate-select.sh,
#      drain-gates.sh, spec-validate.sh) classify the SAME corpus identically
#      on the contested boundary each of them exposes: which reference-bullet
#      tokens are rejected, which prose bullets are tolerated, and that no
#      fenced line parses as a park (REQ-B1.4, REQ-C1.1).
#   2. The parked SET is observed where each consumer exposes it:
#      spec-status.sh renders the full map, orchestrate-select.sh refuses to
#      pick a parked task.
#   3. A CRLF checkout keeps a live Awaiting-input bullet blocking derived
#      Done — the spec-status.sh defect this task fixes (REQ-C1.3).
#   4. A column-0 BODY `**Format-version:**` literal no longer masks a MISSING
#      header declaration: every version-keyed consumer fails closed instead of
#      silently applying the body literal's rules (REQ-A1.3, REQ-B1.3).
#   5. A DUPLICATE in-header `Format-version:` or `Status:` declaration fails
#      closed in every consumer keyed on it (REQ-A1.2, REQ-D1.9, D-6).
#   6. The line-80 families — REQ bullets, D-ID headings, task headings, and
#      the `Dependencies:`/`Citations:` token extractions — produce agreeing
#      records from the three consumers that used to encode them privately
#      (spec-validate.sh, orchestrate-select.sh, spec-model.sh) over one shared
#      fixture, fenced illustration of any of them contributes nothing, and the
#      unified tokenizer invents no dependency edge from an unqualified
#      identifier in prose (REQ-B1.5, REQ-C1.2).
#   7. No consumer retains a private copy of a grammar the lib implements: a
#      grep sweep finds no remaining private `Format-version:`/`Status:`
#      header-declaration parse, no private reference-bullet parse, no private
#      fence lexer, and no private line-80 grammar (REQ-B1.1's no-private-copy
#      rule for the families landed so far), outside a named and reasoned
#      exemption table.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
scripts_dir="$here/../scripts"
STATUS="$scripts_dir/spec-status.sh"
SELECT="$scripts_dir/orchestrate-select.sh"
DRAIN="$scripts_dir/drain-gates.sh"
VALIDATE="$scripts_dir/spec-validate.sh"
MODEL="$scripts_dir/spec-model.sh"
LEDGER="$scripts_dir/check-ledger.sh"
MIGRATE="$scripts_dir/migrate-format-version.sh"
SYNC="$scripts_dir/tasks-pr-sync.sh"
LIB="$scripts_dir/spec-parse.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# refute <haystack> <needle> <label> — fail when the needle IS present. A `case`
# rather than `grep -q … && fail`: same semantics (POSIX exempts a non-final
# AND-OR list command from `set -e`, so both forms are safe), but this one names
# the assertion, spawns no process, and reads as an assertion rather than as
# control flow.
refute() {
  case "$1" in
    *"$2"*) fail "$3" ;;
  esac
}

# refute_line <haystack> <awk-condition> <label> — fail when any line of the
# haystack satisfies the awk condition (for negatives that need field or
# anchored matching rather than a substring).
refute_line() {
  if printf '%s\n' "$1" | awk "$2 { found = 1 } END { exit !found }"; then
    fail "$3"
  fi
}

for s in "$STATUS" "$SELECT" "$DRAIN" "$VALIDATE" "$MODEL" "$LEDGER" "$MIGRATE" "$SYNC"; do
  [ -x "$s" ] || fail "$(basename "$s") missing or not executable"
done
[ -r "$LIB" ] || fail "scripts/spec-parse.sh missing or unreadable"

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

gitc() {
  gc_repo="$1"
  shift
  git -C "$gc_repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# header_block <status> — the canonical v2 header block for a bundle file.
header_block() {
  printf '**Status:** %s\n' "$1"
  printf '**Last reviewed:** 2026-07-24\n'
  printf '**Format-version:** 2\n'
  printf '**Execution:** derived — see the status render\n'
}

# task_block <id> <deps> — one canonical v2 task definition block.
task_block() {
  printf '### Task %s — Thing %s\n\n' "$1" "$1"
  printf -- '- **Deliverables:** A thing.\n'
  printf -- '- **Done when:** The thing exists.\n'
  printf -- '- **Dependencies:** %s\n' "$2"
  printf -- '- **Citations:** D-1 · REQ-X1.1\n'
  printf -- '- **Estimated effort:** 1 day\n\n'
}

# write_corpus <spec-dir> — THE shared fixture corpus. Every case the four v2
# parsers used to disagree about sits in this one file:
#   * two live reference bullets (Task 2 awaiting-input, Task 3 deferred);
#   * a plain prose bullet with a `**Task ...**` lead whose token carries inner
#     whitespace ("**Task force assembled.**") — tolerated, never a park and
#     never a rejection;
#   * a bullet with no bold lead at all;
#   * a token violating the task-id grammar ("nine") — rejected;
#   * a NEAR-MISS lead ("**Task 4 **") whose trimmed remainder IS a valid id —
#     a park a human meant and failed to write, rejected loudly rather than
#     silently swallowed as prose;
#   * an unterminated bold lead — markdown lint's finding, not a park;
#   * a fenced mock payload section and reference bullet — illustration.
write_corpus() {
  wc_dir="$1"
  mkdir -p "$wc_dir"
  {
    printf '# Corpus — Requirements\n\n'
    header_block Ready
    printf '\n## Goal\n\nFixture.\n\n## REQ-X — Group\n\n'
    printf -- '- **REQ-X1.1** A requirement.\n'
  } >"$wc_dir/requirements.md"
  {
    printf '# Corpus — Design\n\n'
    header_block Ready
    printf '\n## Decision log\n\n### D-1: A decision\n\n'
    printf '**Decision:** Yes.\n\n**Alternatives considered:**\n\n- No.\n\n'
    printf '**Chosen because:** it is a fixture.\n'
  } >"$wc_dir/design.md"
  {
    printf '# Corpus — Test spec\n\n'
    header_block Ready
    printf '\n## REQ-X — Group\n\n### REQ-X1.1 — A requirement [test]\n\nFixture.\n'
  } >"$wc_dir/test-spec.md"
  {
    printf '# Corpus — Tasks\n\n'
    header_block Ready
    printf '\n## Tasks\n\n'
    task_block 1 none
    task_block 2 none
    task_block 3 none
    task_block 4 none
    printf '## Awaiting input\n\n'
    printf -- '- **Task 2** Blocked on a human decision.\n\n'
    printf '## Deferred\n\n'
    printf -- '- **Task force assembled.** Plain prose the format allows here.\n'
    printf -- '- A plain bullet with no bold lead at all.\n'
    printf -- '- **Task 3** Deferred with a reason.\n\n'
    printf '## Out of scope\n\n'
    printf -- '- **Task nine** A token violating the task-id grammar.\n'
    printf -- '- **Task 4 ** A near-miss lead: the trimmed remainder is a valid id.\n'
    printf -- '- **Task 5 An unterminated bold lead.\n\n'
    printf '## Notes\n\n'
    printf '```\n'
    printf '## Awaiting input\n\n'
    printf -- '- **Task 1** A fenced mock park that must parse as illustration.\n'
    printf '```\n'
  } >"$wc_dir/tasks.md"
}

# ---------------------------------------------------------------------------
# The corpus's expected classification, straight from the lib (the single
# implementation the consumers are asserted to agree with).
# ---------------------------------------------------------------------------
# shellcheck source=scripts/spec-parse.sh
. "$LIB" || fail "sourcing scripts/spec-parse.sh failed"

corpus_repo="$tmp/corpus-repo"
mkdir -p "$corpus_repo/specs"
write_corpus "$corpus_repo/specs/corpus"
gitc_dir="$corpus_repo"
git -C "$gitc_dir" -c init.defaultBranch=main init -q
gitc "$gitc_dir" add -A
gitc "$gitc_dir" commit -q -m "base: corpus bundle"

corpus_tasks="$corpus_repo/specs/corpus/tasks.md"
spec_parse_parked_map "$corpus_tasks" >"$tmp/lib.map" \
  || fail "the lib refused the shared corpus"

lib_refs=$(awk -F'\t' '$1 == "ref" { print $2 " " $3 }' "$tmp/lib.map")
lib_rejects=$(awk -F'\t' '$1 == "refbad" { print $2 }' "$tmp/lib.map")

[ "$lib_refs" = "2 awaiting-input
3 deferred" ] || fail "the lib's corpus parked map changed shape: $lib_refs"
[ "$lib_rejects" = "nine
4 " ] || fail "the lib's corpus rejected set changed shape: $(printf '%s' "$lib_rejects" | od -c | head -3)"
echo "ok: the shared corpus classifies as 2 parks, 2 rejected tokens, 1 tolerated prose bullet"

# ---------------------------------------------------------------------------
# Property 1 + 2: every v2 parser agrees on the corpus.
# ---------------------------------------------------------------------------

# spec-status.sh renders the full map: per-task class lines plus one rejection
# warning per rejected token. No remote is configured, so the engine takes its
# first-class evidence-fallback path and the render exits 0.
st_out=$("$STATUS" "$corpus_repo/specs/corpus" 2>"$tmp/status.err") \
  || fail "spec-status.sh failed on the corpus: $(cat "$tmp/status.err")"
printf '%s\n' "$st_out" | grep -q '^task 2 awaiting-input ' \
  || fail "spec-status.sh lost the Awaiting-input park: $st_out"
printf '%s\n' "$st_out" | grep -q '^task 3 deferred ' \
  || fail "spec-status.sh lost the Deferred park: $st_out"
printf '%s\n' "$st_out" | grep -q '^task 1 ' \
  || fail "spec-status.sh dropped task 1 entirely: $st_out"
# shellcheck disable=SC2016 # $1..$3 are awk fields, not shell expansions
refute_line "$st_out" '$1 == "task" && $2 == 1 && $3 == "awaiting-input"' \
  "spec-status.sh parked task 1 from a FENCED mock bullet: $st_out"
# shellcheck disable=SC2016 # $1..$3 are awk fields, not shell expansions
refute_line "$st_out" '$1 == "task" && $2 == 4 && $3 == "out-of-scope"' \
  "spec-status.sh parked task 4 from a near-miss lead: $st_out"
st_rejects=$(printf '%s\n' "$st_out" | sed -n "s/^warning: reference bullet rejected — task id '\(.*\)' violates.*/\1/p")
[ "$st_rejects" = "$lib_rejects" ] \
  || fail "spec-status.sh rejected set differs from the lib: got [$st_rejects], want [$lib_rejects]"
refute "$st_out" 'force assembled' \
  "spec-status.sh treated a plain prose bullet as a reference: $st_out"
echo "ok: spec-status.sh matches the lib's corpus classification (REQ-B1.4, REQ-C1.1)"

# orchestrate-select.sh exposes the parked set by refusing to pick a parked
# task, and echoes the same rejected tokens on stderr. Tasks 2 and 3 are
# parked, so the lowest-id unparked ready task (1) is picked.
sel_out=$("$SELECT" "$corpus_repo/specs/corpus" 2>"$tmp/select.err") \
  || fail "orchestrate-select.sh failed on the corpus: $(cat "$tmp/select.err")"
[ "$sel_out" = 1 ] || fail "orchestrate-select.sh picked '$sel_out', want '1' (2 and 3 are parked)"
sel_rejects=$(sed -n "s/^orchestrate-select: reference bullet rejected - task id '\(.*\)' violates.*/\1/p" "$tmp/select.err")
[ "$sel_rejects" = "$lib_rejects" ] \
  || fail "orchestrate-select.sh rejected set differs from the lib: got [$sel_rejects], want [$lib_rejects]"
refute "$(cat "$tmp/select.err")" 'force assembled' \
  "orchestrate-select.sh treated a plain prose bullet as a reference"
echo "ok: orchestrate-select.sh matches the lib's corpus classification (REQ-B1.4, REQ-C1.1)"

# drain-gates.sh echoes the same rejected tokens as report notes.
drain_out=$("$DRAIN" --today 2026-07-24 "$corpus_repo/specs" 2>"$tmp/drain.err") \
  || fail "drain-gates.sh failed on the corpus: $(cat "$tmp/drain.err")"
dr_rejects=$(printf '%s\n' "$drain_out" | sed -n "s/^note: reference bullet rejected - task id '\(.*\)' violates.*/\1/p")
[ "$dr_rejects" = "$lib_rejects" ] \
  || fail "drain-gates.sh rejected set differs from the lib: got [$dr_rejects], want [$lib_rejects]"
refute "$drain_out" 'force assembled' \
  "drain-gates.sh treated a plain prose bullet as a reference"
echo "ok: drain-gates.sh matches the lib's corpus classification (REQ-B1.4, REQ-C1.1)"

# spec-validate.sh reports one rejected-id finding per rejected token, and
# nothing for the tolerated prose bullet or the fenced mock park.
val_out=$("$VALIDATE" "$corpus_repo/specs/corpus" 2>&1) || :
va_rejects=$(printf '%s\n' "$val_out" | sed -n 's/.*fails the task-id grammar and is rejected: \(.*\)$/\1/p')
[ "$va_rejects" = "$lib_rejects" ] \
  || fail "spec-validate.sh rejected set differs from the lib: got [$va_rejects], want [$lib_rejects]"
refute "$val_out" 'force assembled' \
  "spec-validate.sh treated a plain prose bullet as a reference: $val_out"
refute "$val_out" 'names unknown task id' \
  "spec-validate.sh resolved a fenced or prose bullet into an unknown-id finding: $val_out"
echo "ok: spec-validate.sh matches the lib's corpus classification (REQ-B1.4, REQ-C1.1)"

# spec-validate.sh's reference-bullet integrity checks still fire over the
# lib's records: a bullet naming a non-existent task, and a task named twice.
# The zero-task variant is the regression fence for the empty-first-file gotcha
# — with no `### Task` block at all, the id side of the cross-check is empty and
# a naive FNR == NR discriminator would silently eat the first bullet.
mkdir -p "$tmp/refint/specs/refint" "$tmp/refzero/specs/refzero"
write_corpus "$tmp/refint/specs/refint"
{
  printf '# Refint — Tasks\n\n'
  header_block Ready
  printf '\n## Tasks\n\n'
  task_block 1 none
  printf '## Awaiting input\n\n'
  printf -- '- **Task 1** Parked here.\n\n'
  printf '## Deferred\n\n'
  printf -- '- **Task 1** And parked here too.\n'
  printf -- '- **Task 7** Names a task that does not exist.\n'
} >"$tmp/refint/specs/refint/tasks.md"
refint_out=$("$VALIDATE" "$tmp/refint/specs/refint" 2>&1) || :
printf '%s\n' "$refint_out" | grep -q 'names unknown task id 7' \
  || fail "spec-validate.sh lost the unknown-task-id reference check: $refint_out"
printf '%s\n' "$refint_out" | grep -q 'Task 1 is named by more than one reference bullet (Awaiting input and Deferred' \
  || fail "spec-validate.sh lost the twice-parked check or its section names: $refint_out"
echo "ok: spec-validate.sh reference-bullet integrity checks survive the re-point"

write_corpus "$tmp/refzero/specs/refzero"
{
  printf '# Refzero — Tasks\n\n'
  header_block Ready
  printf '\n## Tasks\n\n'
  printf '## Awaiting input\n\n'
  printf -- '- **Task 1** Names a task in a bundle that defines none.\n'
} >"$tmp/refzero/specs/refzero/tasks.md"
refzero_out=$("$VALIDATE" "$tmp/refzero/specs/refzero" 2>&1) || :
printf '%s\n' "$refzero_out" | grep -q 'names unknown task id 1' \
  || fail "a zero-task bundle ate its first reference bullet (empty-first-file gotcha): $refzero_out"
echo "ok: a zero-task v2 bundle still cross-checks its first reference bullet"

# An UNBALANCED column-0 fence is the newest fail-closed path the re-point
# introduces: the lib treats end-of-file inside an open fence as malformed
# (REQ-A1.1's lib half) rather than swallowing the rest of the file as
# illustration, and each consumer must surface that refusal instead of
# validating, rendering, or selecting against an empty parked map (REQ-B1.6f).
# The header block closes before the fence, so the version still parses — this
# isolates the parked-map path.
fence_repo="$tmp/fence-repo"
mkdir -p "$fence_repo/specs"
write_corpus "$fence_repo/specs/corpus"
{
  printf '# Corpus — Tasks\n\n'
  header_block Ready
  printf '\n## Tasks\n\n'
  task_block 1 none
  printf '## Awaiting input\n\n'
  printf -- '- **Task 1** A real park before the fence.\n\n'
  printf '## Notes\n\n'
  printf '```\n'
  printf 'An unterminated fence swallows everything below it.\n'
} >"$fence_repo/specs/corpus/tasks.md"
git -C "$fence_repo" -c init.defaultBranch=main init -q
gitc "$fence_repo" add -A
gitc "$fence_repo" commit -q -m "base: unbalanced-fence bundle"

if "$STATUS" "$fence_repo/specs/corpus" >/dev/null 2>&1; then
  fail "unbalanced fence: spec-status.sh did not fail closed"
fi
if "$SELECT" "$fence_repo/specs/corpus" >/dev/null 2>&1; then
  fail "unbalanced fence: orchestrate-select.sh did not fail closed"
fi
# --critical-path reaches the fence through the TASK GRAPH rather than the
# parked map: the map is a select-mode, v2-only read, so the mode above proves
# nothing about the graph parse. A truncated graph is the dangerous silence —
# a hidden dependency edge makes an unready task look ready — so it fails
# closed on 2 (the lib signals the imbalance with 3, which this script already
# spends on "transient evidence failure").
fence_path_rc=0
fence_path_out=$("$SELECT" --critical-path "$fence_repo/specs/corpus" 2>"$tmp/fence-path.err") \
  || fence_path_rc=$?
[ "$fence_path_rc" -eq 2 ] \
  || fail "unbalanced fence: --critical-path exited $fence_path_rc (want 2), printing [$fence_path_out]"
[ -z "$fence_path_out" ] \
  || fail "unbalanced fence: --critical-path emitted a truncated path: [$fence_path_out]"
grep -q 'open column-0 code fence' "$tmp/fence-path.err" \
  || fail "unbalanced fence: --critical-path does not name the fence: $(cat "$tmp/fence-path.err")"
if fence_val=$("$VALIDATE" "$fence_repo/specs/corpus" 2>&1); then
  fail "unbalanced fence: spec-validate.sh reported no error: $fence_val"
fi
printf '%s\n' "$fence_val" | grep -q 'spec-validate: ERROR' \
  || fail "unbalanced fence: spec-validate.sh finding is not ERROR severity: $fence_val"
printf '%s\n' "$fence_val" | grep -qi 'reference-bullet parse failed' \
  || fail "unbalanced fence: spec-validate.sh does not name the failed parse: $fence_val"
# drain-gates completes the sweep by contract; the refusal is a report error.
fence_drain=$("$DRAIN" --today 2026-07-24 "$fence_repo/specs" 2>/dev/null) \
  || fail "unbalanced fence: drain-gates.sh aborted instead of reporting"
printf '%s\n' "$fence_drain" | grep -q 'could not read the v2 parked map' \
  || fail "unbalanced fence: drain-gates.sh evaluated gates against an empty parked map: $fence_drain"
echo "ok: an unbalanced column-0 fence fails closed in every v2 parser (REQ-A1.1, REQ-B1.6f)"

# ---------------------------------------------------------------------------
# Property 3: a CRLF checkout keeps the Awaiting-input park blocking derived
# Done (REQ-C1.3 — the spec-status.sh defect this task fixes).
# ---------------------------------------------------------------------------
crlf_repo="$tmp/crlf-repo"
mkdir -p "$crlf_repo/specs"
write_corpus "$crlf_repo/specs/corpus"
# Only the two live parks and the definition blocks matter here; drop the
# rejected/prose/fenced cases so the bundle derives cleanly, then convert the
# whole file to CRLF.
{
  printf '# Corpus — Tasks\n\n'
  header_block Ready
  printf '\n## Tasks\n\n'
  task_block 1 none
  printf '## Awaiting input\n\n'
  printf -- '- **Task 1** Blocked on a human decision.\n'
} | awk '{ printf "%s\r\n", $0 }' >"$crlf_repo/specs/corpus/tasks.md"
git -C "$crlf_repo" -c init.defaultBranch=main init -q
gitc "$crlf_repo" add -A
gitc "$crlf_repo" commit -q -m "base: CRLF corpus"
# Task 1 has merged evidence, so ONLY the reference bullet can keep the bundle
# off Done: if the CRLF section heading were missed, the bundle would derive Done.
gitc "$crlf_repo" commit -q --allow-empty \
  -m "feat: task 1

Planwright-Task: corpus/1"
crlf_out=$("$STATUS" "$crlf_repo/specs/corpus" 2>"$tmp/crlf.err") \
  || fail "spec-status.sh failed on the CRLF corpus: $(cat "$tmp/crlf.err")"
printf '%s\n' "$crlf_out" | grep -q '^task 1 awaiting-input ' \
  || fail "CRLF checkout lost the Awaiting-input park (REQ-C1.3): $crlf_out"
refute "$crlf_out" 'bundle status: Done' \
  "a live Awaiting-input bullet failed to block derived Done on a CRLF checkout (REQ-C1.3): $crlf_out"
echo "ok: a CRLF checkout keeps a live Awaiting-input bullet blocking derived Done (REQ-C1.3)"

# ---------------------------------------------------------------------------
# Property 4: a column-0 BODY `**Format-version:**` literal is inert and no
# longer masks a MISSING header declaration (REQ-A1.3).
# ---------------------------------------------------------------------------
# write_bad_version <spec-dir> <mode> — a bundle whose version declaration is
# defective. mode=body: no header declaration, a column-0 body literal instead.
# mode=dup-fv / mode=dup-status: a duplicate in-header declaration.
write_bad_version() {
  wbv_dir="$1"
  wbv_mode="$2"
  mkdir -p "$wbv_dir"
  for wbv_f in requirements.md design.md test-spec.md tasks.md; do
    {
      printf '# Bad — %s\n\n' "$wbv_f"
      case $wbv_mode in
        body)
          printf '**Status:** Ready\n'
          printf '**Execution:** derived — see the status render\n\n'
          printf '## Body\n\n'
          printf '**Format-version:** 2\n'
          ;;
        dup-fv)
          printf '**Status:** Ready\n'
          printf '**Format-version:** 2\n'
          printf '**Format-version:** 1\n'
          printf '**Execution:** derived — see the status render\n'
          ;;
        dup-status)
          printf '**Status:** Ready\n'
          printf '**Status:** Draft\n'
          printf '**Format-version:** 2\n'
          printf '**Execution:** derived — see the status render\n'
          ;;
      esac
    } >"$wbv_dir/$wbv_f"
  done
  {
    printf '\n## Tasks\n\n'
    task_block 1 none
  } >>"$wbv_dir/tasks.md"
}

# assert_version_keyed_fail_closed <label> <spec-dir> — every version-keyed
# consumer must refuse the bundle rather than fall open to a version's rules.
# spec-graph.sh is deliberately absent: it keeps no private version parse, so
# it inherits the refusal through orchestrate-select.sh and spec-model.sh.
assert_version_keyed_fail_closed() {
  av_label="$1"
  av_dir="$2"
  av_root=$(dirname "$av_dir")

  if "$STATUS" "$av_dir" >/dev/null 2>&1; then
    fail "$av_label: spec-status.sh did not fail closed"
  fi
  if "$SELECT" "$av_dir" >/dev/null 2>&1; then
    fail "$av_label: orchestrate-select.sh did not fail closed"
  fi
  if "$LEDGER" "$av_dir/tasks.md" >/dev/null 2>&1; then
    fail "$av_label: check-ledger.sh did not fail closed"
  fi
  if "$SYNC" reconcile-status "$av_dir" >/dev/null 2>&1; then
    fail "$av_label: tasks-pr-sync.sh reconcile-status did not fail closed"
  fi
  if "$MIGRATE" "$av_dir" >/dev/null 2>&1; then
    fail "$av_label: migrate-format-version.sh did not fail closed"
  fi
  # drain-gates completes the sweep by contract; the refusal is a per-spec
  # report error, never a silent evaluation.
  av_drain=$("$DRAIN" --today 2026-07-24 "$av_root" 2>/dev/null) \
    || fail "$av_label: drain-gates.sh aborted instead of reporting"
  printf '%s\n' "$av_drain" | grep -qi 'error:.*not evaluated' \
    || fail "$av_label: drain-gates.sh evaluated gates under a guessed format: $av_drain"
  # spec-validate reports a hard finding (an error at every status).
  if av_val=$("$VALIDATE" "$av_dir" 2>&1); then
    fail "$av_label: spec-validate.sh reported no error"
  fi
  printf '%s\n' "$av_val" | grep -q 'spec-validate: ERROR' \
    || fail "$av_label: spec-validate.sh error is not an ERROR-severity finding: $av_val"
}

body_repo="$tmp/body-repo"
mkdir -p "$body_repo/specs"
write_bad_version "$body_repo/specs/bad" body
git -C "$body_repo" -c init.defaultBranch=main init -q
gitc "$body_repo" add -A
gitc "$body_repo" commit -q -m "base: body-literal bundle"
assert_version_keyed_fail_closed "body-literal version" "$body_repo/specs/bad"
echo "ok: a body-line Format-version: literal no longer masks a missing header declaration (REQ-A1.3)"

# ---------------------------------------------------------------------------
# Property 5: a duplicate in-header declaration of either load-bearing key
# fails closed in every consumer keyed on it (REQ-A1.2, REQ-D1.9, D-6).
# ---------------------------------------------------------------------------
dupfv_repo="$tmp/dupfv-repo"
mkdir -p "$dupfv_repo/specs"
write_bad_version "$dupfv_repo/specs/bad" dup-fv
git -C "$dupfv_repo" -c init.defaultBranch=main init -q
gitc "$dupfv_repo" add -A
gitc "$dupfv_repo" commit -q -m "base: duplicate Format-version bundle"
assert_version_keyed_fail_closed "duplicate Format-version" "$dupfv_repo/specs/bad"
echo "ok: a duplicate in-header Format-version: fails closed in every version-keyed consumer (REQ-D1.9)"

# A duplicate in-header `Status:` fails closed in every consumer keyed on the
# stored status. check-ledger.sh and migrate-format-version.sh key on the
# version, not the status, so they are not part of this set; spec-status.sh,
# spec-validate.sh, and tasks-pr-sync.sh are.
dupst_repo="$tmp/dupst-repo"
mkdir -p "$dupst_repo/specs"
write_bad_version "$dupst_repo/specs/bad" dup-status
git -C "$dupst_repo" -c init.defaultBranch=main init -q
gitc "$dupst_repo" add -A
gitc "$dupst_repo" commit -q -m "base: duplicate Status bundle"
if "$STATUS" "$dupst_repo/specs/bad" >/dev/null 2>&1; then
  fail "duplicate Status: spec-status.sh did not fail closed"
fi
if dupst_val=$("$VALIDATE" "$dupst_repo/specs/bad" 2>&1); then
  fail "duplicate Status: spec-validate.sh reported no error"
fi
printf '%s\n' "$dupst_val" | grep -q 'spec-validate: ERROR' \
  || fail "duplicate Status: spec-validate.sh error is not ERROR severity: $dupst_val"
dupst_drain=$("$DRAIN" --today 2026-07-24 "$dupst_repo/specs" 2>/dev/null) \
  || fail "duplicate Status: drain-gates.sh aborted instead of reporting"
printf '%s\n' "$dupst_drain" | grep -qi 'status' \
  || fail "duplicate Status: drain-gates.sh reported nothing about the status: $dupst_drain"
echo "ok: a duplicate in-header Status: fails closed in every status-keyed consumer (REQ-D1.9)"

# ---------------------------------------------------------------------------
# Property 6: the line-80 families agree across the three consumers that used
# to encode them privately (format-grammar Task 8; REQ-B1.5, REQ-C1.2 · D-4).
#
# One fixture bundle carries every shape the three copies had reason to differ
# on: a prose dependency list with a sentence-final period, a parenthetical
# cross-spec carry clause naming REQ and D ids, an unqualified identifier in
# prose OUTSIDE any parenthetical, and a fenced mock block whose task heading,
# REQ bullet, D heading, `Dependencies:` and `Citations:` bullets are all
# illustration.
#
# The assertions are on what each consumer EXPOSES of the parse: the validator
# through its findings, the bundle reader through its record stream, the
# selector through the critical path it computes from the same graph.
# ---------------------------------------------------------------------------
l80_repo="$tmp/l80-repo"
mkdir -p "$l80_repo/specs/line80"
{
  printf '# Line80 — Requirements\n\n'
  header_block Ready
  printf '\n## Goal\n\nFixture.\n\n## REQ-Y — Group\n\n'
  printf -- '- **REQ-Y1.1** A requirement. *(Cites: D-1.)*\n'
  printf -- '- **REQ-Y1.2** Another one. *(Cites: D-1, REQ-Y1.1.)*\n\n'
  printf '## Notes\n\nThe bullet form:\n\n'
  printf '```markdown\n'
  printf -- '- **REQ-Y1.1** A fenced example that must not duplicate the real id.\n'
  printf '```\n'
} >"$l80_repo/specs/line80/requirements.md"
{
  printf '# Line80 — Design\n\n'
  header_block Ready
  printf '\n## Decision log\n\n### D-1: A decision  (H)\n\n'
  printf '**Decision:** Yes.\n\n**Alternatives considered:**\n\n- No.\n\n'
  printf '**Chosen because:** it is a fixture.\n\n'
  printf '## Notes\n\nThe heading form:\n\n'
  printf '```markdown\n'
  printf '### D-1: A fenced example that must not duplicate the real id.\n'
  printf '```\n'
} >"$l80_repo/specs/line80/design.md"
{
  printf '# Line80 — Test spec\n\n'
  header_block Ready
  printf '\n## REQ-Y — Group\n\n'
  printf '### REQ-Y1.1 — A requirement [test]\n\nFixture.\n\n'
  printf '### REQ-Y1.2 — Another one [test]\n\nFixture.\n'
} >"$l80_repo/specs/line80/test-spec.md"
# l80_task <id> <title> <deps> <citations> — a definition block with the
# dependency and citation forms this property is about.
l80_task() {
  printf '### Task %s — %s\n\n' "$1" "$2"
  printf -- '- **Deliverables:** A thing.\n'
  printf -- '- **Done when:** The thing exists.\n'
  printf -- '- **Dependencies:** %s\n' "$3"
  printf -- '- **Citations:** %s\n' "$4"
  printf -- '- **Estimated effort:** 1 day\n\n'
}
{
  printf '# Line80 — Tasks\n\n'
  header_block Ready
  printf '\n## Tasks\n\n'
  l80_task 1 Root none 'D-1 · REQ-Y1.1'
  l80_task 2 Middle 'Task 1.' 'D-1'
  l80_task 3 Leaf 'Task 1; Task 2 (REQ-Y1.2 / D-1 — a carry clause naming ids)' 'REQ-Y1.2'
  l80_task 4 Tail 'Task 3; see D-9 for context' 'D-1'
  printf '## Notes\n\nThe block format:\n\n'
  printf '```markdown\n'
  l80_task 9 Illustration '7' 'D-9'
  printf '```\n'
} >"$l80_repo/specs/line80/tasks.md"
git -C "$l80_repo" -c init.defaultBranch=main init -q
gitc "$l80_repo" add -A
gitc "$l80_repo" commit -q -m "base: line-80 bundle"

# The validator: nothing fenced raises a finding, and nothing real is missed.
# A single clean run covers both directions — a fenced REQ bullet or D heading
# duplicating a real id would be a hard finding, and a fenced task block would
# report the definition fields it does not have.
l80_val=$("$VALIDATE" "$l80_repo/specs/line80" 2>&1) \
  || fail "spec-validate.sh reported findings on the line-80 fixture: $l80_val"
printf '%s\n' "$l80_val" | grep -q '0 error(s), 0 warning(s)' \
  || fail "spec-validate.sh on the line-80 fixture: $l80_val"
echo "ok: fenced REQ bullets, D headings, and task blocks raise no validator finding (REQ-C1.2)"

# The bundle reader: the record stream is the parse made visible.
l80_model=$("$MODEL" "$l80_repo/specs/line80") \
  || fail "spec-model.sh failed on the line-80 fixture"
m_field() { printf '%s\n' "$l80_model" | awk -F'\t' -v t="$1" '$1 == t { print }'; }

[ "$(m_field TASK | cut -f2 | tr '\n' ' ')" = "1 2 3 4 " ] \
  || fail "model task ids: $(m_field TASK)"
[ "$(m_field TASKDEP | cut -f2,3 | tr '\t' '>' | tr '\n' ' ')" = "2>1 3>1 3>2 4>3 " ] \
  || fail "model dependency edges: $(m_field TASKDEP)"
[ "$(m_field DEC | cut -f2 | tr '\n' ' ')" = "D-1 " ] \
  || fail "model decision ids (a fenced heading must not add one): $(m_field DEC)"
[ "$(m_field REQ | cut -f2 | tr '\n' ' ')" = "REQ-Y1.1 REQ-Y1.2 " ] \
  || fail "model requirement ids (a fenced bullet must not add one): $(m_field REQ)"
[ "$(m_field TEST | cut -f2 | tr '\n' ' ')" = "REQ-Y1.1 REQ-Y1.2 " ] \
  || fail "model test-spec coverage: $(m_field TEST)"
refute "$(m_field TASKCITE)" 'D-9' \
  "a fenced Citations bullet contributed a citation edge (REQ-B1.5): $(m_field TASKCITE)"
refute "$(m_field REQCITE)" 'REQ-Y1.2	REQ-Y1.2' \
  "a requirement cited itself: $(m_field REQCITE)"
echo "ok: the bundle reader emits the real records only, fenced illustration excluded (REQ-B1.5)"

# The selector: the critical path is computed from the same dependency graph,
# so it is the selector-side view of the edge set asserted above. Every effort
# is 1 day, so the chain is the graph: 1 -> 2 -> 3 -> 4.
l80_path=$("$SELECT" --critical-path "$l80_repo/specs/line80" 2>"$tmp/l80.err") \
  || fail "orchestrate-select.sh --critical-path failed: $(cat "$tmp/l80.err")"
[ "$l80_path" = "1
2
3
4" ] || fail "selector critical path: [$l80_path]"
echo "ok: the selector graph matches the bundle reader graph on the shared fixture (REQ-B1.5)"

# The unified tokenizer grammar-validates whole tokens instead of scraping
# digits out of the residue, so an unqualified identifier in prose contributes
# no edge. Exposed through SELECTION: a task whose only dependency-shaped token
# is "D-9" has no dependency at all, so it is ready, and its higher effort wins
# the critical-path-first pick. A phantom edge to a task 9 that does not exist
# would leave it permanently unready and the pick would fall to task 1.
scrape_repo="$tmp/scrape-repo"
mkdir -p "$scrape_repo/specs/scrape"
for f in requirements design test-spec; do
  cp "$l80_repo/specs/line80/$f.md" "$scrape_repo/specs/scrape/$f.md"
done
{
  printf '# Scrape — Tasks\n\n'
  header_block Ready
  printf '\n## Tasks\n\n'
  l80_task 1 Root none 'D-1'
  printf '### Task 2 — Prose-only dependency line\n\n'
  printf -- '- **Deliverables:** A thing.\n'
  printf -- '- **Done when:** The thing exists.\n'
  printf -- '- **Dependencies:** none; see D-9 for context\n'
  printf -- '- **Citations:** D-1\n'
  printf -- '- **Estimated effort:** 5 days\n'
} >"$scrape_repo/specs/scrape/tasks.md"
git -C "$scrape_repo" -c init.defaultBranch=main init -q
gitc "$scrape_repo" add -A
gitc "$scrape_repo" commit -q -m "base: digit-scrape bundle"
scrape_pick=$("$SELECT" "$scrape_repo/specs/scrape" 2>"$tmp/scrape.err") \
  || fail "orchestrate-select.sh failed on the digit-scrape fixture: $(cat "$tmp/scrape.err")"
[ "$scrape_pick" = 2 ] \
  || fail "an unqualified identifier in prose became a phantom dependency edge (picked '$scrape_pick', want '2')"
echo "ok: an unqualified identifier in a dependency line invents no edge (REQ-B1.5)"

# ---------------------------------------------------------------------------
# Property 7: no consumer retains a private copy of a landed grammar.
#
# The sweep is deliberately blunt about the two shapes the private copies took —
# an awk arm that EXTRACTS a value from the bolded header declaration, and an awk
# arm anchored on a `- **Task ` reference bullet — because a narrow signature is
# exactly what a future private copy would slip past. Bluntness costs an
# exemption table, which is the point: adding a name to it is a visible,
# reviewable act with a stated reason, whereas a silently-narrowed pattern is
# not. The lib is the one file allowed to carry either shape.
#
# The header signature is the line-anchored escaped declaration itself, not the
# awk `sub()` that one shape of private copy happened to use: anchored on `sub(`
# the sweep matched exactly ONE file in scripts/ — migrate-format-version.sh, the
# file on the exemption list — so `private_hdr` could never be non-empty and the
# sweep verified nothing. Anchoring on the declaration pattern catches the sed
# and bare-`/match/` shapes too, at the cost of the fuller exemption table below,
# which is the trade the bluntness argument above already asked for.
#
# Exempt, by name and reason:
#   migrate-format-version.sh  transform_header REWRITES the declaration (a
#                              writer, not a reader), and restructure_tasks
#                              probes the reference-bullet SHAPE to carry
#                              part-converted payload content verbatim through
#                              the v1 to v2 transform — it extracts no task id
#                              and classifies no section.
#   tasks-pr-sync.sh           write_status_header REWRITES the declaration (a
#                              writer, same class as above); the value it reads
#                              first comes from the lib.
#   check-memory-links.sh      bundle_status() reads the bundle `Status:` header
#                              with a private sed filter, and
#   migrate-status-lifecycle.sh  status_of() with a private awk `$2` read plus a
#                              grep presence probe. Both sit outside REQ-B1.3's
#                              named consumer set and neither is status-keyed for
#                              an execution decision, so leaving them was the
#                              scoped call recorded in specs/_observations
#                              (status-parse-stragglers, 2026-07-24). Named here
#                              so the gap is visible where the sweep is defined
#                              rather than only in the accumulator; a re-point
#                              removes the name and the stale-exemption guard
#                              below then demands it.
# ---------------------------------------------------------------------------
HDR_EXEMPT=" migrate-format-version.sh tasks-pr-sync.sh check-memory-links.sh migrate-status-lifecycle.sh "
REF_EXEMPT=" migrate-format-version.sh "

# The fence lexer became a lib family in Task 6 ($spec_parse_awk_fence), so the
# sweep grows a third arm: the whole point of a shared lexer is that a second
# copy cannot quietly reappear, and doctrine/spec-format.md states the fence
# rule universally, for ANY parser of spec bundles.
#
# Exempt, by name and reason:
#   check-instructions.sh    parses INSTRUCTION files (skills, doctrine), not
#                            spec bundles. A permanent exemption, not a
#                            straggler: it is a different document class, and
#                            it tracks a fence_char to handle tilde fences the
#                            spec grammar deliberately does not treat as
#                            toggles.
#   drain-gates.sh           its GATE-entry parse. Its reference-bullet parse
#                            already comes from the lib (Task 2); the gate
#                            grammar is not a lib family yet.
#
# (orchestrate-select.sh was the third name here until Task 8 put its task and
# dependency grammar on the lib; its fence guard is now the lib lexer.)
#
# The remaining spec-bundle exemption is sequenced, not permanent, and the
# stale-exemption guard below turns it into a prompt to drop the name once the
# parse it guards is re-pointed.
FENCE_EXEMPT=" check-instructions.sh drain-gates.sh "

# The line-80 families became lib families in Task 8 ($spec_parse_awk_grammar),
# so the sweep grows four more arms: the requirement bullet, the D-ID heading,
# the task heading, and the `Dependencies:` / `Citations:` token extractions.
# The REQ-bullet and Citations arms carry NO exemption — the lib is their only
# home anywhere in scripts/.
#
# The scoped set REQ-B1.5 names is the three consumers legacy line 80 recorded:
# spec-validate.sh, orchestrate-select.sh, spec-model.sh. The sweep is
# repo-wide anyway, on the same reasoning as the arms above (a NEW private copy
# in a new script is what a scoped sweep would miss), which makes every
# not-yet-migrated reader a named line rather than an invisible gap.
#
# Exempt, by name and reason:
#   spec-walkthrough.sh      grep presence probes for the `### D-<n>:` heading,
#                            driving the comprehension command scaffold slice
#                            selector rather than parsing a bundle. Outside the
#                            REQ-B1.5 consumer set; D-4 excludes the
#                            walkthrough scope grammar from the lib entirely.
#   orchestrate-state.sh     the derivation engine keeps its own, deliberately
#                            STRICTER dependency parser: it flags prose forms
#                            as malformed where the selector tolerates them
#                            (the divergence orchestrate-select.sh documents in
#                            its own header). A decided divergence, not drift —
#                            unifying it is a semantics change, not a re-point.
#   migrate-format-version.sh  restructure_tasks REWRITES task blocks (a writer,
#                            the same class as its header exemption above).
#   migrate-status-lifecycle.sh  a `grep -qE` presence probe for "does this file
#                            hold any task block at all", extracting nothing.
#   check-ledger.sh          the CANONICAL-FORM guard: it asserts the heading
#                            matches `### Task <id> — <title>` exactly, which
#                            is a stricter rule than "what is a task heading"
#                            and is the ledger guard concern by design.
#   spec-status.sh           its render-side task scan, and
#   drain-gates.sh           its per-spec task count and gate scan, and
#   tasks-pr-sync.sh         its section-reconcile scan. All three are readers
#                            outside the REQ-B1.5 consumer set, sequenced for a
#                            later vehicle and recorded in specs/_observations
#                            (line80-reader-stragglers). Named here so the gap
#                            is visible where the sweep is defined.
REQBULLET_EXEMPT=" "
DEC_EXEMPT=" spec-walkthrough.sh "
TASKHEAD_EXEMPT=" migrate-format-version.sh migrate-status-lifecycle.sh check-ledger.sh spec-status.sh drain-gates.sh tasks-pr-sync.sh orchestrate-state.sh "
DEPS_EXEMPT=" orchestrate-state.sh "
CITES_EXEMPT=" "

sweep_files=$(find "$scripts_dir" -name '*.sh' -type f | sort)
[ -n "$sweep_files" ] || fail "the grep sweep found no scripts to sweep"

exempt() {
  case "$1" in
    *" $2 "*) return 0 ;;
  esac
  return 1
}

# The sweep signatures, one per family: the shape a private copy takes in any
# of the tools these scripts use (awk match, awk sub(), sed s///, grep -qE).
HDR_SIG='\^\\\*\\\*\(Format-version\|Status\):\\\*\\\*'
REF_SIG='\^- \\\*\\\*Task '
FENCE_SIG='\^```'
REQBULLET_SIG='\^- \\\*\\\*REQ-'
DEC_SIG='\^### D-'
TASKHEAD_SIG='\^### Task '
DEPS_SIG='\\\*\\\*Dependencies:\\\*\\\*'
CITES_SIG='\\\*\\\*Citations:\\\*\\\*'

private_hdr=""
private_ref=""
private_fence=""
private_reqbullet=""
private_dec=""
private_taskhead=""
private_deps=""
private_cites=""
swept=0
for f in $sweep_files; do
  base=$(basename "$f")
  if [ "$base" = spec-parse.sh ]; then
    continue
  fi
  swept=$((swept + 1))
  # A private header-declaration parse: any line-anchored match on the bolded
  # `**Format-version:**` / `**Status:**` declaration, whichever tool carries it
  # (awk sub(), awk /match/, sed s///, grep -q).
  if grep -q "$HDR_SIG" "$f"; then
    exempt "$HDR_EXEMPT" "$base" || private_hdr="$private_hdr $base"
  fi
  # A private reference-bullet parse: an awk arm anchored on `^- \*\*Task `.
  if grep -q "$REF_SIG" "$f"; then
    exempt "$REF_EXEMPT" "$base" || private_ref="$private_ref $base"
  fi
  # A private fence lexer: any line-anchored column-0 fence match.
  if grep -q "$FENCE_SIG" "$f"; then
    exempt "$FENCE_EXEMPT" "$base" || private_fence="$private_fence $base"
  fi
  # The four line-80 signatures (Task 8; REQ-B1.5).
  if grep -q "$REQBULLET_SIG" "$f"; then
    exempt "$REQBULLET_EXEMPT" "$base" || private_reqbullet="$private_reqbullet $base"
  fi
  if grep -q "$DEC_SIG" "$f"; then
    exempt "$DEC_EXEMPT" "$base" || private_dec="$private_dec $base"
  fi
  if grep -q "$TASKHEAD_SIG" "$f"; then
    exempt "$TASKHEAD_EXEMPT" "$base" || private_taskhead="$private_taskhead $base"
  fi
  if grep -q "$DEPS_SIG" "$f"; then
    exempt "$DEPS_EXEMPT" "$base" || private_deps="$private_deps $base"
  fi
  if grep -q "$CITES_SIG" "$f"; then
    exempt "$CITES_EXEMPT" "$base" || private_cites="$private_cites $base"
  fi
done

[ "$swept" -gt 20 ] || fail "the grep sweep only swept $swept scripts; the glob looks broken"
[ -z "$private_hdr" ] \
  || fail "private header-declaration parse(s) remain outside the lib:$private_hdr"
[ -z "$private_ref" ] \
  || fail "private reference-bullet parse(s) remain outside the lib:$private_ref"
[ -z "$private_fence" ] \
  || fail "private fence lexer(s) remain outside the lib:$private_fence"
[ -z "$private_reqbullet" ] \
  || fail "private requirement-bullet parse(s) remain outside the lib:$private_reqbullet"
[ -z "$private_dec" ] \
  || fail "private decision-heading parse(s) remain outside the lib:$private_dec"
[ -z "$private_taskhead" ] \
  || fail "private task-heading parse(s) remain outside the lib:$private_taskhead"
[ -z "$private_deps" ] \
  || fail "private dependency-token parse(s) remain outside the lib:$private_deps"
[ -z "$private_cites" ] \
  || fail "private citation-token parse(s) remain outside the lib:$private_cites"
echo "ok: every private header / reference-bullet / fence / line-80 parse outside the lib is a named, reasoned exemption (REQ-B1.1)"

# The three consumers REQ-B1.5 names carry NO exemption on any line-80 arm:
# their migration is the deliverable, so a re-appearing private copy in one of
# them must go red rather than be exemptible.
for named in spec-validate.sh orchestrate-select.sh spec-model.sh; do
  for sig in "$REQBULLET_SIG" "$DEC_SIG" "$TASKHEAD_SIG" "$DEPS_SIG" "$CITES_SIG"; do
    if grep -q "$sig" "$scripts_dir/$named"; then
      fail "$named carries a private line-80 grammar copy again (REQ-B1.5): $sig"
    fi
  done
done
echo "ok: the three line-80 consumers keep no private copy of any migrated family (REQ-B1.5)"

# The exemptions are asserted to still MATCH, so a name whose reason has gone
# away (the writer was removed, the reader re-pointed) surfaces as a stale
# exemption instead of quietly weakening the sweep.
for hx in migrate-format-version.sh tasks-pr-sync.sh check-memory-links.sh migrate-status-lifecycle.sh; do
  if ! grep -q "$HDR_SIG" "$scripts_dir/$hx"; then
    fail "stale HDR exemption: $hx no longer carries the header parse it is exempted for"
  fi
done
if ! grep -q "$REF_SIG" "$scripts_dir/migrate-format-version.sh"; then
  fail "stale REF exemption: migrate-format-version.sh no longer carries the bullet-shape probe it is exempted for"
fi
for fx in check-instructions.sh drain-gates.sh; do
  if ! grep -q "$FENCE_SIG" "$scripts_dir/$fx"; then
    fail "stale FENCE exemption: $fx no longer carries the private fence lexer it is exempted for (drop the name from FENCE_EXEMPT)"
  fi
done
if ! grep -q "$DEC_SIG" "$scripts_dir/spec-walkthrough.sh"; then
  fail "stale DEC exemption: spec-walkthrough.sh no longer carries the decision-heading probe it is exempted for"
fi
for tx in migrate-format-version.sh migrate-status-lifecycle.sh check-ledger.sh spec-status.sh drain-gates.sh tasks-pr-sync.sh orchestrate-state.sh; do
  if ! grep -q "$TASKHEAD_SIG" "$scripts_dir/$tx"; then
    fail "stale TASKHEAD exemption: $tx no longer carries the task-heading parse it is exempted for (drop the name from TASKHEAD_EXEMPT)"
  fi
done
if ! grep -q "$DEPS_SIG" "$scripts_dir/orchestrate-state.sh"; then
  fail "stale DEPS exemption: orchestrate-state.sh no longer carries the stricter dependency parse it is exempted for"
fi
echo "ok: every sweep exemption still matches the shape it was granted for"

echo "PASS: test-spec-parse-corpus.sh"
