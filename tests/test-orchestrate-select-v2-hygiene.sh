#!/bin/bash
# Tests for scripts/orchestrate-select.sh — FORMAT-VERSION 2 header/parse
# hygiene and untrusted-content discipline (invariant-tasks Task 5; D-8, D-3;
# REQ-C1.9, REQ-B1.5).
#
# Split out of tests/test-orchestrate-select.sh (guard-coverage Task 6,
# REQ-E1.2, D-9); the base file's header carries the full selection contract and
# names the other three siblings. No assertion changed in the split.
#
# What this file covers (V11–V19, the numbering kept from the pre-split file):
# Format-version trailing-trim (CRLF, Markdown hard break), a hostile
# unparseable header value sanitized on stderr, rejected-bullet warnings
# surviving a transient evidence failure, fenced illustration in the selection
# GRAPH, NUL bytes failing closed, near-miss reference bullets rejected loudly
# rather than skipped as prose, literal backslash sequences never re-synthesized
# into terminal escapes, a missing echo-safety.sh helper failing closed, and
# --critical-path staying structural on v2. The parked-map and Format-version
# candidacy cases (F1–F2, V1–V10) live in
# tests/test-orchestrate-select-v2.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SEL="$here/../scripts/orchestrate-select.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SEL" ] || fail "scripts/orchestrate-select.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# git with a deterministic, signing-free identity (mirrors the engine's test:
# the framework never signs CI fixtures, and a stray global commit.gpgsign would
# otherwise break fixture commits).
gitc() {
  repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# new_spec <repo> <spec-id> — init a git repo with specs/<spec-id>/ and echo the
# spec dir. The bundle's tasks.md is then written by the caller and committed
# with seal_base. The spec id is the bundle dir basename and must satisfy the
# anchored identifier grammar the engine validates (lowercase letters, digits,
# and dashes; first character a letter or digit), so all fixture spec ids below
# are well-formed.
new_spec() {
  nr_repo="$1"
  nr_spec="$2"
  mkdir -p "$nr_repo/specs/$nr_spec"
  git -C "$nr_repo" -c init.defaultBranch=main init -q
  printf '%s/specs/%s' "$nr_repo" "$nr_spec"
}

# seal_base <repo> — commit whatever is staged-or-not as the base commit on main.
seal_base() {
  gitc "$1" add -A
  gitc "$1" commit -q -m "base: spec bundle"
}

# done_trailer <repo> <spec-id> <id> — mark task <id> COMPLETED by adding a
# reachable completion trailer on main (no branch needed; the trailer is the
# durable anchor, D-2 / REQ-C1.4).
done_trailer() {
  gitc "$1" commit -q --allow-empty -m "task $3 done" -m "Planwright-Task: $2/$3"
}

# inflight_marker <spec-dir> <id> — mark task <id> IN-PROGRESS via a fresh
# runtime dispatch marker (D-3), the branch-create → first-commit window.
inflight_marker() {
  im_dir="$1/.orchestrate/markers"
  mkdir -p "$im_dir"
  date +%s >"$im_dir/$2"
}

# make_failing_gh_stub <dir> — drop a `gh` on PATH that always errors (mirrors
# the engine test). With a remote configured, this drives the engine's
# configured-but-failing-gh path, which emits a `degraded` record.
make_failing_gh_stub() {
  mkdir -p "$1"
  printf '#!/bin/sh\necho "gh: simulated failure" >&2\nexit 1\n' >"$1/gh"
  chmod +x "$1/gh"
}

# v2_tasks_md <path> — the shared v2 fixture skeleton: five tasks under a
# single ## Tasks section (no placement sections), the three human-payload
# sections empty. Task 1 is the root; 2/3/4/5 depend on it. Efforts make any
# parked-task leak visible: 2/3/4 (3 days each) outweigh 5 (half day), so if a
# bullet fails to exclude its task the selection flips away from 5.
v2_tasks_md() {
  cat >"$1" <<'EOF'
# tasks

**Format-version:** 2

## Tasks

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 2 — parked awaiting input

- **Dependencies:** 1
- **Estimated effort:** 3 days

### Task 3 — parked deferred

- **Dependencies:** 1
- **Estimated effort:** 3 days

### Task 4 — parked out of scope

- **Dependencies:** 1
- **Estimated effort:** 3 days

### Task 5 — the only un-parked candidate

- **Dependencies:** 1
- **Estimated effort:** half day

## Awaiting input

- **Task 2** blocked on a human decision.

## Deferred

- **Task 3** deferred behind a gate.

## Out of scope

- **Task 4** excluded by decision.
EOF
}

# Two fixtures the pre-split file inherited from earlier sections: the parked v2
# bundle V1 builds (V18 and V19 read it back), and the always-failing `gh` stub
# §17 built (V13 drives it). Each file stands alone, so both are rebuilt here.
dv1="$tmp/v2park"
dv1spec=$(new_spec "$dv1" vtwo)
v2_tasks_md "$dv1spec/tasks.md"
seal_base "$dv1"
done_trailer "$dv1" vtwo 1

degstub="$tmp/bindeg"
make_failing_gh_stub "$degstub"

# V11. Format-version trailing-trim: a CRLF header line and a Markdown
#      hard-break (trailing spaces) both parse.
dv11="$tmp/v2fvtrim"
dv11spec=$(new_spec "$dv11" vtwofvtrim)
{
  printf '# tasks\r\n\r\n'
  printf '**Format-version:** 2  \r\n\r\n'
  printf '## Tasks\r\n\r\n'
  printf '### Task 1 — ready\r\n\r\n'
  printf -- '- **Dependencies:** none\r\n'
  printf -- '- **Estimated effort:** 1 day\r\n\r\n'
  printf '## Awaiting input\r\n\r\n(none yet)\r\n\r\n'
  printf '## Deferred\r\n\r\n(none yet)\r\n\r\n'
  printf '## Out of scope\r\n\r\n(none yet)\r\n'
} >"$dv11spec/tasks.md"
seal_base "$dv11"
got=$(/bin/bash "$SEL" "$dv11spec") || fail "v2-fv-trim fixture: non-zero exit ($?)"
[ "$got" = 1 ] || fail "v2-fv-trim: selected '$got', expected 1 (CRLF/hard-break FV line must parse)"
echo "ok: Format-version trailing trim handles CRLF and hard-break lines"

# V12. REQ-C1.9 — a hostile unparseable Format-version value (raw ESC byte) is
#      refused (exit 2) with a sanitized diagnostic: no non-printable bytes on
#      stderr.
dv12="$tmp/v2fvhostile"
mkdir -p "$dv12"
printf '# tasks\n\n**Format-version:** 3\033[31mx\n\n## Tasks\n\n### Task 1 — x\n\n- **Dependencies:** none\n' >"$dv12/tasks.md"
v12_err="$tmp/v2fvhostile.err"
rc=0
/bin/bash "$SEL" "$dv12" >/dev/null 2>"$v12_err" || rc=$?
[ "$rc" = 2 ] || fail "v2-fv-hostile: exit $rc, expected 2"
grep -q 'Format-version' "$v12_err" \
  || fail "v2-fv-hostile: diagnostic must name Format-version (got: $(cat "$v12_err"))"
LC_ALL=C grep '[^ -~]' "$v12_err" >/dev/null \
  && fail "v2-fv-hostile: stderr carries non-printable bytes (unsanitized header value)"
echo "ok: a hostile Format-version value is refused with a sanitized diagnostic (REQ-C1.9)"

# V13. The rejected-bullet warning is emitted before the evidence probe, so it
#      still reaches stderr when the run then fails closed on transient
#      evidence (REQ-B1.5's locally-determinable-facts clause at this surface).
dv13="$tmp/v2rejdeg"
dv13spec=$(new_spec "$dv13" vtworejdeg)
{
  printf '# tasks\n\n**Format-version:** 2\n\n## Tasks\n\n'
  printf '### Task 1 — ready\n\n'
  printf -- '- **Dependencies:** none\n'
  printf -- '- **Estimated effort:** 1 day\n\n'
  printf '## Awaiting input\n\n'
  printf -- '- **Task 9x** grammar-violating id.\n\n'
  printf '## Deferred\n\n(none yet)\n\n## Out of scope\n\n(none yet)\n'
} >"$dv13spec/tasks.md"
seal_base "$dv13"
gitc "$dv13" remote add origin https://example.invalid/demo.git
v13_err="$tmp/v2rejdeg.err"
rc=0
v13_out=$(PATH="$degstub:$PATH" /bin/bash "$SEL" "$dv13spec" 2>"$v13_err") || rc=$?
[ "$rc" = 3 ] || fail "v2-rej-deg: exit $rc, expected 3 (transient failure)"
[ -z "$v13_out" ] || fail "v2-rej-deg: stdout must be empty (got '$v13_out')"
grep -q 'violates the task-id grammar' "$v13_err" \
  || fail "v2-rej-deg: the rejected-bullet warning must still surface during a transient failure"
echo "ok: rejected-bullet warnings survive a transient evidence failure (REQ-B1.5)"

# V14. Fenced code blocks are illustration in the selection GRAPH too: a
#      fenced example task heading is never a graph node, so it can be neither
#      selected nor part of the critical path (its example effort must not
#      outweigh real work).
dv14="$tmp/v2graphfence"
dv14spec=$(new_spec "$dv14" vtwographfence)
cat >"$dv14spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 2

## Tasks

### Task 1 — the only real task

- **Dependencies:** none
- **Estimated effort:** half day

```markdown
### Task 9 — an illustration, heavier than any real work

- **Dependencies:** none
- **Estimated effort:** 5 days
```

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
seal_base "$dv14"
got=$(/bin/bash "$SEL" "$dv14spec") || fail "v2-graph-fence fixture: non-zero exit ($?)"
[ "$got" = 1 ] || fail "v2-graph-fence: selected '$got', expected 1 (a fenced task heading is not a graph node)"
cp14=$(/bin/bash "$SEL" --critical-path "$dv14spec") || fail "v2-graph-fence --critical-path: non-zero exit ($?)"
case "$cp14" in
  *9*) fail "v2-graph-fence --critical-path: fenced task 9 appeared on the path [$cp14]" ;;
esac
echo "ok: fenced task headings are illustration in selection and --critical-path"

# V15. NUL bytes in tasks.md fail closed (mirrors drain-gates): the snapshot
#      read strips NULs, which would splice flanking bytes and could silently
#      un-park a task; corruption is refused, never reinterpreted.
dv15="$tmp/v2nul"
dv15spec=$(new_spec "$dv15" vtwonul)
{
  printf '# tasks\n\n**Format-version:** 2\n\n## Tasks\n\n'
  printf '### Task 1 — ready\n\n'
  printf -- '- **Dependencies:** none\n'
  printf -- '- **Estimated effort:** 1 day\n\n'
  printf '## Awaiting input\n\n'
  printf -- 'corrupt\000- **Task 1** parked, NUL-spliced.\n\n'
  printf '## Deferred\n\n(none yet)\n\n## Out of scope\n\n(none yet)\n'
} >"$dv15spec/tasks.md"
seal_base "$dv15"
rc=0
/bin/bash "$SEL" "$dv15spec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "v2-nul: exit $rc, expected 2 (NUL-laden tasks.md fails closed)"
echo "ok: NUL bytes in tasks.md fail closed (no snapshot splice)"

# V16. A NEAR-MISS reference bullet — whitespace-trimmed lead is a valid id
#      ("Task 1 ", stray space), or the lead is only digits/dots/whitespace
#      ("Task 1 2") — is a failed park a human meant: rejected LOUDLY, never
#      silently skipped as prose (REQ-C1.9's never-silent posture). Genuine
#      prose (V9) stays silent.
dv16="$tmp/v2nearmiss"
dv16spec=$(new_spec "$dv16" vtwonearmiss)
{
  printf '# tasks\n\n**Format-version:** 2\n\n## Tasks\n\n'
  printf '### Task 1 — ready\n\n'
  printf -- '- **Dependencies:** none\n'
  printf -- '- **Estimated effort:** 1 day\n\n'
  printf '## Awaiting input\n\n'
  printf -- '- **Task 1 ** near-miss: stray space inside the bold lead.\n\n'
  printf '## Deferred\n\n(none yet)\n\n## Out of scope\n\n(none yet)\n'
} >"$dv16spec/tasks.md"
seal_base "$dv16"
v16_err="$tmp/v2nearmiss.err"
rc=0
v16_out=$(/bin/bash "$SEL" "$dv16spec" 2>"$v16_err") || rc=$?
[ "$rc" = 0 ] || fail "v2-near-miss: exit $rc, expected 0"
[ "$v16_out" = 1 ] || fail "v2-near-miss: selected '$v16_out', expected 1 (a rejected near-miss parks nothing)"
grep -q 'violates the task-id grammar' "$v16_err" \
  || fail "v2-near-miss: a stray-space reference bullet must be rejected loudly, not silently skipped as prose"
echo "ok: near-miss reference bullets warn; the failed park is never silent (REQ-C1.9)"

# V17. Echo discipline: untrusted content carrying a LITERAL backslash escape
#      (the four printable bytes \033) must not be re-synthesized into a live
#      ESC by the diagnostic path — sanitize_printable strips formed control
#      bytes, and the emitter must not manufacture new ones. Exercised under
#      /bin/sh (macOS xpg echo) and dash (the CI shell) where echo interprets
#      backslash sequences.
dv17="$tmp/v2echoesc"
dv17spec=$(new_spec "$dv17" vtwoechoesc)
{
  printf '# tasks\n\n**Format-version:** 2\n\n## Tasks\n\n'
  printf '### Task 1 — ready\n\n'
  printf -- '- **Dependencies:** none\n'
  printf -- '- **Estimated effort:** 1 day\n\n'
  printf '## Awaiting input\n\n'
  printf -- '- **Task 9\\033[31mX** literal backslash sequence in the id.\n\n'
  printf '## Deferred\n\n(none yet)\n\n## Out of scope\n\n(none yet)\n'
} >"$dv17spec/tasks.md"
seal_base "$dv17"
for v17_sh in /bin/sh dash; do
  command -v "$v17_sh" >/dev/null 2>&1 || continue
  v17_err="$tmp/v2echoesc.${v17_sh##*/}.err"
  rc=0
  v17_out=$("$v17_sh" "$SEL" "$dv17spec" 2>"$v17_err") || rc=$?
  [ "$rc" = 0 ] || fail "v2-echo-esc ($v17_sh): exit $rc, expected 0"
  [ "$v17_out" = 1 ] || fail "v2-echo-esc ($v17_sh): selected '$v17_out', expected 1"
  grep -q 'violates the task-id grammar' "$v17_err" \
    || fail "v2-echo-esc ($v17_sh): the rejection warning must still be emitted"
  LC_ALL=C grep '[^ -~]' "$v17_err" >/dev/null \
    && fail "v2-echo-esc ($v17_sh): a literal backslash sequence was re-synthesized into a control byte on stderr"
done
echo "ok: literal backslash sequences are never re-synthesized into terminal escapes"

# V18. A missing echo-safety.sh helper is a broken install: fail closed
#      (exit 2) with a diagnostic naming the helper, before any parse or
#      derivation — the sanitizer is what keeps every later untrusted-content
#      diagnostic safe, so running without it is refused (REQ-C1.9).
lonesel="$tmp/lonesel"
mkdir -p "$lonesel"
cp "$SEL" "$lonesel/orchestrate-select.sh"
chmod +x "$lonesel/orchestrate-select.sh"
rc=0
v18_err=$(/bin/bash "$lonesel/orchestrate-select.sh" "$dv1spec" 2>&1 >/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "v18 echo-safety missing: exit $rc, expected 2 (broken install fails closed)"
case "$v18_err" in
  *echo-safety.sh*) : ;;
  *) fail "v18: diagnostic must name the missing helper (got: $v18_err)" ;;
esac
echo "ok: a missing echo-safety.sh helper fails closed (broken install, REQ-C1.9)"

# V19. --critical-path on a v2 bundle ignores reference-bullet parking by
#      design (path mode is purely structural: full DAG, no engine, no parked
#      map) — a bullet-parked task still appears on the emitted path. Pins the
#      select-mode-only guard on the parked-map parse.
cp19=$(/bin/bash "$SEL" --critical-path "$dv1spec") \
  || fail "v19 --critical-path on the v2 parked fixture: non-zero exit ($?)"
printf '%s\n' "$cp19" | grep -qx 1 \
  || fail "v19: the structural path must start at the root [$cp19]"
printf '%s\n' "$cp19" | grep -qx 2 \
  || fail "v19: a bullet-parked task must still ride the structural path (path mode ignores parking) [$cp19]"
echo "ok: --critical-path stays structural on v2 (bullet parking not applied)"

echo "PASS: orchestrate-select (v2 header/parse hygiene)"
