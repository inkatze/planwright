#!/bin/bash
# Tests for scripts/dispatch-fetch.sh — the deterministic bounded fetch
# primitive the /orchestrate and /execute-task freshness gate + merge detection
# run BEFORE dispatch (fleet-hardening Task 8; D-9; REQ-D1.1, REQ-D1.2,
# REQ-E1.3).
#
# Contract under test:
#   - the gate fetches `origin` and evaluates currency + the content anchor
#     against the fetched `origin/main`, WITHOUT advancing local `main`
#     (REQ-D1.1: the shared-checkout read-only-local-`main` invariant holds
#     byte-for-byte);
#   - the anchor check is RE-POINTED at the fetched ref by reusing the existing
#     scripts/spec-anchor.sh over `origin/main`'s spec content — it does not
#     re-implement anchor-hash comparison (D-9 scope boundary);
#   - merge detection evaluates against the freshly-fetched `origin/main`, so a
#     task whose PR merged on `origin` (trailer on `origin/main`) but whose
#     trailer has not reached local `main` is detected merged after the fetch
#     (REQ-D1.2), driving scripts/orchestrate-state.sh's existing union scan;
#   - a transient fetch failure against a PRESENT remote is handled distinctly
#     from a structural `no-remote` (retry, then block/flag — NEVER a silent
#     stale gate), for currency AND merge detection (REQ-D1.1);
#   - the per-gate fetch is BOUNDED (a TTL stamp coalesced with the reconcile
#     sweep) so an `/orchestrate --watch` idle loop does not fetch every cycle;
#   - no model/API call occurs anywhere in the decision path (REQ-E1.3).
#
# Output stream is a tagged TSV on stdout, one record per line:
#   fetch<TAB><fetched|fresh-within-ttl|no-remote|stale-transient>
#   anchor<TAB><hash><TAB><ref>     (only with --spec, when an anchor is computed)
# Exit: 0 remote current (fetched|fresh-within-ttl); 3 no-remote (degraded,
#   offline first-class); 4 stale-transient (fetch failed after retries, caller
#   must not silently proceed); 2 usage / invalid input (fail closed).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FETCH="$here/../scripts/dispatch-fetch.sh"
ANCHOR="$here/../scripts/spec-anchor.sh"
STATE="$here/../scripts/orchestrate-state.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FETCH" ] || fail "scripts/dispatch-fetch.sh missing or not executable"
[ -x "$ANCHOR" ] || fail "scripts/spec-anchor.sh missing or not executable"
[ -x "$STATE" ] || fail "scripts/orchestrate-state.sh missing or not executable"

# git with a deterministic, signing-free identity (the framework never signs in
# CI fixtures; a stray global commit.gpgsign would otherwise break fixtures).
gitc() {
  repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# Pull the value of a tagged record (col 1 == tag) out of the fetch output.
tag_val() {
  printf '%s\n' "$1" | awk -F"$TAB" -v t="$2" '$1==t {print $2; exit}'
}
# Pull the anchor record's ref (col 3).
anchor_ref() {
  printf '%s\n' "$1" | awk -F"$TAB" '$1=="anchor" {print $3; exit}'
}
# Pull a task's derived state out of orchestrate-state.sh's stream.
state_of() {
  printf '%s\n' "$1" | awk -F"$TAB" -v i="$2" '$1=="task" && $2==i {print $3; exit}'
}

# Write a minimal but valid four-file spec bundle under <repo>/specs/<name>,
# plus its kickoff-brief. spec-anchor.sh accepts it (four files present, one
# extractable task block). The <marker> text is embedded so an edit changes the
# content anchor deterministically.
write_spec() {
  repo="$1"
  name="$2"
  marker="$3"
  d="$repo/specs/$name"
  mkdir -p "$d"
  cat >"$d/requirements.md" <<EOF
# Demo — Requirements

**Status:** Ready
**Format-version:** 2

## Goal

Marker: $marker
EOF
  cat >"$d/design.md" <<EOF
# Demo — Design

Marker: $marker
EOF
  cat >"$d/test-spec.md" <<EOF
# Demo — Test spec

Marker: $marker
EOF
  cat >"$d/tasks.md" <<EOF
# Demo — Tasks

**Status:** Ready
**Format-version:** 2

## Tasks

### Task 1 — the unit
- **Deliverables:** a thing
- **Done when:** the thing exists
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** 1 day
EOF
  cat >"$d/kickoff-brief.md" <<EOF
# Demo — Kickoff brief

Marker: $marker
EOF
}

# ---------------------------------------------------------------------------
# Case 1 — fetched: currency + anchor re-pointed at origin/main; local main
# byte-for-byte unchanged (REQ-D1.1, D-9). The origin has a NEWER spec than the
# stale local main, so the re-pointed anchor is the newer one.
# ---------------------------------------------------------------------------
c1() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-fetch.c1.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  git init -q --bare "$tmp/origin.git"

  git clone -q "$tmp/origin.git" "$tmp/primary" 2>/dev/null
  write_spec "$tmp/primary" demo v1
  gitc "$tmp/primary" add -A
  gitc "$tmp/primary" commit -q -m "spec v1"
  gitc "$tmp/primary" branch -M main
  gitc "$tmp/primary" push -q origin main

  # A second worker advances origin/main with an edited spec (a re-anchor).
  git clone -q "$tmp/origin.git" "$tmp/dev2" 2>/dev/null
  write_spec "$tmp/dev2" demo v2
  gitc "$tmp/dev2" add -A
  gitc "$tmp/dev2" commit -q -m "spec v2 (re-anchor)"
  gitc "$tmp/dev2" push -q origin main

  # Independent expected anchors: v1 = primary's stale working tree; v2 = the
  # origin/main content (dev2's working tree).
  anchor_v1=$("$ANCHOR" "$tmp/primary/specs/demo")
  anchor_v2=$("$ANCHOR" "$tmp/dev2/specs/demo")
  [ "$anchor_v1" != "$anchor_v2" ] || fail "c1: fixture broken — v1 and v2 anchors are equal"

  main_before=$(gitc "$tmp/primary" rev-parse main)

  out=$(PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$tmp/state" \
    "$FETCH" --spec specs/demo "$tmp/primary") \
    || fail "c1: dispatch-fetch exited non-zero on a healthy fetch"

  [ "$(tag_val "$out" fetch)" = fetched ] \
    || fail "c1: expected fetch=fetched, got '$(tag_val "$out" fetch)'"
  [ "$(anchor_ref "$out")" = origin/main ] \
    || fail "c1: expected anchor ref origin/main, got '$(anchor_ref "$out")'"
  got_anchor=$(printf '%s\n' "$out" | awk -F"$TAB" '$1=="anchor"{print $2; exit}')
  [ "$got_anchor" = "$anchor_v2" ] \
    || fail "c1: re-pointed anchor '$got_anchor' != origin/main anchor '$anchor_v2'"
  [ "$got_anchor" != "$anchor_v1" ] \
    || fail "c1: gate returned the STALE local-main anchor, not the newer origin/main one"

  main_after=$(gitc "$tmp/primary" rev-parse main)
  [ "$main_before" = "$main_after" ] \
    || fail "c1: local main advanced ($main_before -> $main_after); read-only invariant broken"
  # And byte-for-byte: the working tree of the stale spec is untouched.
  [ "$("$ANCHOR" "$tmp/primary/specs/demo")" = "$anchor_v1" ] \
    || fail "c1: primary working-tree spec content changed after the gate"

  echo "ok c1: fetched, anchor re-pointed at origin/main, local main unchanged"
}

# ---------------------------------------------------------------------------
# Case 2 — no-remote: structural degrade (offline first-class). Exit 3, the
# anchor falls back to local main, dispatch may proceed degraded (REQ-D1.1).
# ---------------------------------------------------------------------------
c2() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-fetch.c2.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  git init -q "$tmp/repo"
  write_spec "$tmp/repo" demo v1
  gitc "$tmp/repo" add -A
  gitc "$tmp/repo" commit -q -m "spec v1"
  gitc "$tmp/repo" branch -M main
  anchor_local=$("$ANCHOR" "$tmp/repo/specs/demo")
  main_before=$(gitc "$tmp/repo" rev-parse main)

  set +e
  out=$(PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$tmp/state" \
    "$FETCH" --spec specs/demo "$tmp/repo")
  rc=$?
  set -e
  [ "$rc" -eq 3 ] || fail "c2: expected exit 3 (no-remote), got $rc"
  [ "$(tag_val "$out" fetch)" = no-remote ] \
    || fail "c2: expected fetch=no-remote, got '$(tag_val "$out" fetch)'"
  got_anchor=$(printf '%s\n' "$out" | awk -F"$TAB" '$1=="anchor"{print $2; exit}')
  [ "$got_anchor" = "$anchor_local" ] \
    || fail "c2: no-remote anchor '$got_anchor' != local-main anchor '$anchor_local'"
  [ "$(anchor_ref "$out")" = main ] \
    || fail "c2: expected degraded anchor ref main, got '$(anchor_ref "$out")'"
  [ "$(gitc "$tmp/repo" rev-parse main)" = "$main_before" ] \
    || fail "c2: local main moved on the no-remote path"
  echo "ok c2: no-remote degrades gracefully to local main (exit 3)"
}

# ---------------------------------------------------------------------------
# Case 3 — transient fetch failure against a PRESENT remote: retry, then block
# (exit 4, NO anchor line — never a silent stale gate). A counting git wrapper
# proves the retries actually happened (REQ-D1.1).
# ---------------------------------------------------------------------------
c3() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-fetch.c3.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  git init -q "$tmp/repo"
  write_spec "$tmp/repo" demo v1
  gitc "$tmp/repo" add -A
  gitc "$tmp/repo" commit -q -m "spec v1"
  gitc "$tmp/repo" branch -M main
  # A configured-but-unreachable origin: `git remote` is non-empty (present
  # remote → transient class, NOT no-remote), but the fetch cannot connect.
  gitc "$tmp/repo" remote add origin "$tmp/does-not-exist.git"
  main_before=$(gitc "$tmp/repo" rev-parse main)

  # A counting `git` shim on PATH: every real git call passes through, but a
  # `git ... fetch ...` invocation increments a counter so we can prove retry.
  shim="$tmp/bin"
  mkdir -p "$shim"
  realgit=$(command -v git)
  {
    echo '#!/bin/sh'
    echo "cnt=\"$tmp/fetch-count\""
    # shellcheck disable=SC2016 # $cnt/$@ are literal shim-script source, expanded at shim runtime, not here
    echo 'for a in "$@"; do if [ "$a" = fetch ]; then n=$(cat "$cnt" 2>/dev/null || echo 0); echo $((n+1)) >"$cnt"; break; fi; done'
    echo "exec \"$realgit\" \"\$@\""
  } >"$shim/git"
  chmod +x "$shim/git"

  set +e
  out=$(PATH="$shim:$PATH" \
    PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$tmp/state" \
    PLANWRIGHT_DISPATCH_FETCH_RETRIES=2 \
    PLANWRIGHT_DISPATCH_FETCH_RETRY_SLEEP=0 \
    "$FETCH" --spec specs/demo "$tmp/repo")
  rc=$?
  set -e
  [ "$rc" -eq 4 ] || fail "c3: expected exit 4 (stale-transient), got $rc"
  [ "$(tag_val "$out" fetch)" = stale-transient ] \
    || fail "c3: expected fetch=stale-transient, got '$(tag_val "$out" fetch)'"
  printf '%s\n' "$out" | awk -F"$TAB" '$1=="anchor"{exit 0} END{exit 1}' \
    && fail "c3: an anchor line was printed on a stale gate (silent-stale leak)"
  n=$(cat "$tmp/fetch-count" 2>/dev/null || echo 0)
  [ "$n" -ge 3 ] \
    || fail "c3: expected >=3 fetch attempts (1 + 2 retries), got $n — no retry"
  # The invariant must survive the path where a fetch actually RUNS and fails.
  [ "$(gitc "$tmp/repo" rev-parse main)" = "$main_before" ] \
    || fail "c3: local main moved on the transient-failure path"
  echo "ok c3: transient failure retries then blocks (exit 4, no anchor), $n attempts"
}

# ---------------------------------------------------------------------------
# Case 4 — TTL bound: a second run within the TTL reuses the stamp and does NOT
# hit the network, so an `--watch` idle loop does not fetch every cycle. Proven
# by advancing origin between runs and asserting the second run does NOT see it.
# Then expiring the stamp makes it fetch again (REQ-D1.1, D-9 bounded fetch).
# ---------------------------------------------------------------------------
c4() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-fetch.c4.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  git init -q --bare "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/primary" 2>/dev/null
  write_spec "$tmp/primary" demo v1
  gitc "$tmp/primary" add -A
  gitc "$tmp/primary" commit -q -m "spec v1"
  gitc "$tmp/primary" branch -M main
  gitc "$tmp/primary" push -q origin main

  state="$tmp/state"
  # First run: real fetch, writes the stamp.
  out1=$(PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$state" \
    PLANWRIGHT_DISPATCH_FETCH_TTL=3600 \
    "$FETCH" "$tmp/primary") || fail "c4: first run failed"
  [ "$(tag_val "$out1" fetch)" = fetched ] \
    || fail "c4: first run expected fetched, got '$(tag_val "$out1" fetch)'"
  origin_after_first=$(gitc "$tmp/primary" rev-parse origin/main)

  # A second worker advances origin/main AFTER the stamp is written.
  git clone -q "$tmp/origin.git" "$tmp/dev2" 2>/dev/null
  gitc "$tmp/dev2" commit -q --allow-empty -m "advance origin"
  gitc "$tmp/dev2" push -q origin main

  # Second run within the TTL: must NOT fetch — origin/main tracking is
  # unchanged from the first run.
  out2=$(PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$state" \
    PLANWRIGHT_DISPATCH_FETCH_TTL=3600 \
    "$FETCH" "$tmp/primary") || fail "c4: second run failed"
  [ "$(tag_val "$out2" fetch)" = fresh-within-ttl ] \
    || fail "c4: second run expected fresh-within-ttl, got '$(tag_val "$out2" fetch)'"
  [ "$(gitc "$tmp/primary" rev-parse origin/main)" = "$origin_after_first" ] \
    || fail "c4: within-TTL run hit the network (origin/main advanced)"

  # Expire the stamp (TTL=0): the next run fetches again and sees the advance.
  out3=$(PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$state" \
    PLANWRIGHT_DISPATCH_FETCH_TTL=0 \
    "$FETCH" "$tmp/primary") || fail "c4: third run failed"
  [ "$(tag_val "$out3" fetch)" = fetched ] \
    || fail "c4: expired-TTL run expected fetched, got '$(tag_val "$out3" fetch)'"
  [ "$(gitc "$tmp/primary" rev-parse origin/main)" != "$origin_after_first" ] \
    || fail "c4: expired-TTL run did not re-fetch (origin/main still stale)"
  echo "ok c4: fetch is TTL-bounded (fresh-within-ttl reuse, re-fetch on expiry)"
}

# ---------------------------------------------------------------------------
# Case 5 — merge detection against the fetched origin/main (REQ-D1.2): a task
# whose PR merged on origin (Planwright-Task trailer on origin/main) but whose
# trailer has not reached local main is detected merged only AFTER the fetch.
# Composes dispatch-fetch.sh (fetch) with orchestrate-state.sh (union scan).
# ---------------------------------------------------------------------------
c5() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-fetch.c5.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  git init -q --bare "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/primary" 2>/dev/null
  write_spec "$tmp/primary" demo v1
  gitc "$tmp/primary" add -A
  gitc "$tmp/primary" commit -q -m "spec v1"
  gitc "$tmp/primary" branch -M main
  gitc "$tmp/primary" push -q origin main

  # A merge lands on origin carrying Task 1's completion trailer, but primary
  # has not fetched, so its origin/main tracking ref is stale.
  git clone -q "$tmp/origin.git" "$tmp/dev2" 2>/dev/null
  gitc "$tmp/dev2" commit -q --allow-empty \
    -m "merge task 1" -m "Planwright-Task: demo/1"
  gitc "$tmp/dev2" push -q origin main

  # Before the fetch: the trailer is not on any ref primary can see → Task 1 is
  # not yet completed (deps none → ready).
  before=$("$STATE" "$tmp/primary/specs/demo")
  [ "$(state_of "$before" 1)" != completed ] \
    || fail "c5: Task 1 reported completed BEFORE the fetch — origin/main not stale in fixture"

  PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$tmp/state" \
    "$FETCH" "$tmp/primary" >/dev/null || fail "c5: fetch failed"

  # After the fetch: the union scan over the fresh origin/main sees the trailer.
  after=$("$STATE" "$tmp/primary/specs/demo")
  [ "$(state_of "$after" 1)" = completed ] \
    || fail "c5: Task 1 not detected merged after the fetch (got '$(state_of "$after" 1)')"
  echo "ok c5: merge detected against fetched origin/main (not re-dispatched)"
}

# ---------------------------------------------------------------------------
# Case 6 — merge-detection degradation under no-remote: with no remote, the
# fetch degrades AND orchestrate-state derives git-only without FALSELY marking
# an unmerged task completed (REQ-D1.1, the "for merge detection" arm).
# ---------------------------------------------------------------------------
c6() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-fetch.c6.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  git init -q "$tmp/repo"
  write_spec "$tmp/repo" demo v1
  gitc "$tmp/repo" add -A
  gitc "$tmp/repo" commit -q -m "spec v1"
  gitc "$tmp/repo" branch -M main

  set +e
  PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$tmp/state" \
    "$FETCH" "$tmp/repo" >/dev/null
  rc=$?
  set -e
  [ "$rc" -eq 3 ] || fail "c6: expected no-remote exit 3, got $rc"
  st=$("$STATE" "$tmp/repo/specs/demo")
  [ "$(state_of "$st" 1)" = ready ] \
    || fail "c6: unmerged Task 1 mis-derived as '$(state_of "$st" 1)' under no-remote"
  echo "ok c6: no-remote merge detection degrades without a false completion"
}

# ---------------------------------------------------------------------------
# Case 7 — REQ-E1.3: no model/API call anywhere in the decision path. A source
# grep asserts the script invokes no LLM/model endpoint (the same negative-
# assertion idiom sibling REQ-E1.3 mechanisms use).
# ---------------------------------------------------------------------------
c7() {
  # The whole decision path = dispatch-fetch.sh (the mechanism this bundle
  # introduces) AND the two helpers it invokes (spec-anchor.sh, config-get.sh),
  # so the "no model/API call anywhere in the decision path" claim covers what
  # actually runs. Patterns are command/endpoint-anchored: a `claude` CLI call is
  # lowercase followed by whitespace (so the `CLAUDE_PLUGIN_ROOT` path env var and
  # `.claude/` paths never trip it); the endpoint surfaces (anthropic, the
  # messages path, any URL) are matched case-insensitively as substrings; and the
  # `curl`/`wget` command words are matched with `-w` so one at column zero, one
  # indented, or one at end of line is caught alike (a plain `[^a-z]…[^a-z]`
  # bracket would miss a curl with no character on one side).
  for src in "$here/../scripts/dispatch-fetch.sh" \
    "$here/../scripts/spec-anchor.sh" "$here/../scripts/config-get.sh"; do
    [ -f "$src" ] || fail "c7: expected decision-path script missing: $src"
    # Strip comments so a word appearing only in prose never trips the guard.
    code=$(grep -vE '^[[:space:]]*#' "$src" || true)
    if printf '%s\n' "$code" | grep -nE '(^|[^A-Za-z_./])claude[[:space:]]' >/dev/null \
      || printf '%s\n' "$code" | grep -niE 'anthropic|/v1/messages|https?://' >/dev/null \
      || printf '%s\n' "$code" | grep -niwE '(curl|wget)' >/dev/null; then
      fail "c7: $src references a model/API/network surface in the decision path (REQ-E1.3)"
    fi
  done
  echo "ok c7: no model/API call anywhere in the decision path (REQ-E1.3)"
}

# ---------------------------------------------------------------------------
# Case 8 — usage / fail-closed: no repo-root arg, and a bad --spec path, both
# exit 2 (framework-script safety, fail closed on malformed input).
# ---------------------------------------------------------------------------
c8() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-fetch.c8.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  git init -q "$tmp/repo"

  set +e
  "$FETCH" >/dev/null 2>&1
  rc_noarg=$?
  "$FETCH" --spec '../evil' "$tmp/repo" >/dev/null 2>&1
  rc_badspec=$?
  "$FETCH" "$tmp/not-a-git-repo" >/dev/null 2>&1
  rc_nogit=$?
  set -e
  [ "$rc_noarg" -eq 2 ] || fail "c8: missing repo-root should exit 2, got $rc_noarg"
  [ "$rc_badspec" -eq 2 ] || fail "c8: traversal --spec should exit 2, got $rc_badspec"
  [ "$rc_nogit" -eq 2 ] || fail "c8: non-git repo-root should exit 2, got $rc_nogit"
  echo "ok c8: fails closed on missing/invalid input (exit 2)"
}

# ---------------------------------------------------------------------------
# Case 9 — the read-only-local-main invariant survives a HOSTILE
# `remote.origin.fetch` (F1.1). A checkout whose configured refspec maps into
# `refs/heads/*` would fast-forward local main on a bare `git fetch origin`; the
# script pins an explicit `+refs/heads/*:refs/remotes/origin/*` refspec, so local
# main must stay put while origin/main advances, independent of repo config.
# ---------------------------------------------------------------------------
c9() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-fetch.c9.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  git init -q --bare "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/primary" 2>/dev/null
  write_spec "$tmp/primary" demo v1
  gitc "$tmp/primary" add -A
  gitc "$tmp/primary" commit -q -m "spec v1"
  gitc "$tmp/primary" branch -M main
  gitc "$tmp/primary" push -q origin main
  # The hostile config: fetch maps remote heads straight onto LOCAL heads.
  gitc "$tmp/primary" config remote.origin.fetch '+refs/heads/*:refs/heads/*'

  git clone -q "$tmp/origin.git" "$tmp/dev2" 2>/dev/null
  gitc "$tmp/dev2" commit -q --allow-empty -m "advance origin"
  gitc "$tmp/dev2" push -q origin main
  advanced=$(gitc "$tmp/dev2" rev-parse main)

  main_before=$(gitc "$tmp/primary" rev-parse main)
  [ "$main_before" != "$advanced" ] || fail "c9: fixture broken — primary main already advanced"

  PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$tmp/state" \
    "$FETCH" "$tmp/primary" >/dev/null || fail "c9: fetch failed"

  [ "$(gitc "$tmp/primary" rev-parse main)" = "$main_before" ] \
    || fail "c9: local main advanced under a hostile refspec — invariant depends on config"
  [ "$(gitc "$tmp/primary" rev-parse origin/main)" = "$advanced" ] \
    || fail "c9: origin/main not updated — the pinned refspec did not fetch"
  echo "ok c9: read-only-local-main holds under a hostile remote.origin.fetch"
}

# ---------------------------------------------------------------------------
# Case 10 — --best-effort makes a single attempt (F4.1): a down remote must not
# cost the retry budget every reconcile-sweep cycle. Same unreachable-origin
# fixture as c3, but --best-effort defaults retries to 0 → exactly one attempt.
# ---------------------------------------------------------------------------
c10() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-fetch.c10.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  git init -q "$tmp/repo"
  write_spec "$tmp/repo" demo v1
  gitc "$tmp/repo" add -A
  gitc "$tmp/repo" commit -q -m "spec v1"
  gitc "$tmp/repo" branch -M main
  gitc "$tmp/repo" remote add origin "$tmp/does-not-exist.git"

  shim="$tmp/bin"
  mkdir -p "$shim"
  realgit=$(command -v git)
  {
    echo '#!/bin/sh'
    echo "cnt=\"$tmp/fetch-count\""
    # shellcheck disable=SC2016 # $cnt/$@ are literal shim-script source, expanded at shim runtime, not here
    echo 'for a in "$@"; do if [ "$a" = fetch ]; then n=$(cat "$cnt" 2>/dev/null || echo 0); echo $((n+1)) >"$cnt"; break; fi; done'
    echo "exec \"$realgit\" \"\$@\""
  } >"$shim/git"
  chmod +x "$shim/git"

  set +e
  out=$(PATH="$shim:$PATH" \
    PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$tmp/state" \
    PLANWRIGHT_DISPATCH_FETCH_RETRY_SLEEP=0 \
    "$FETCH" --best-effort "$tmp/repo")
  rc=$?
  set -e
  [ "$rc" -eq 4 ] || fail "c10: expected exit 4 (stale-transient), got $rc"
  [ "$(tag_val "$out" fetch)" = stale-transient ] \
    || fail "c10: expected fetch=stale-transient, got '$(tag_val "$out" fetch)'"
  n=$(cat "$tmp/fetch-count" 2>/dev/null || echo 0)
  [ "$n" -eq 1 ] \
    || fail "c10: --best-effort should make exactly 1 attempt, got $n"
  echo "ok c10: --best-effort is a single attempt (no retry budget)"
}

# ---------------------------------------------------------------------------
# Case 11 — echo discipline (security-posture, "Framework-script security"): an
# untrusted `--spec` carrying a terminal escape is rejected (exit 2) AND the
# rejection diagnostic is stripped of the raw control bytes before it reaches
# stderr, so a hostile spec name cannot drive the terminal via the error path.
# ---------------------------------------------------------------------------
c11() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-fetch.c11.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  git init -q "$tmp/repo"

  # An OSC set-window-title escape (ESC ] 0 ; ... BEL) embedded in the spec value.
  # It fails the identifier grammar, so it flows to the invalid-spec-name echo —
  # the exact place attacker-influenced bytes reach the terminal.
  # (a) Already-FORMED control bytes (raw ESC/BEL) must be stripped before echo.
  evil=$(printf 'specs/\033]0;PWNED\007x')
  set +e
  err=$("$FETCH" --spec "$evil" "$tmp/repo" 2>&1 >/dev/null)
  rc=$?
  set -e
  [ "$rc" -eq 2 ] || fail "c11: escape-bearing --spec should exit 2, got $rc"
  if printf '%s' "$err" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    fail "c11: a raw control byte reached stderr (escape-injection not sanitized)"
  fi

  # (b) A LITERAL backslash-escape (the four bytes \ 0 3 3): sanitize_printable
  # only strips FORMED control bytes, so these survive it — and a
  # backslash-interpreting echo (dash, macOS /bin/sh under xpg_echo) would
  # RE-SYNTHESIZE a live ESC from them AFTER sanitizing (the re-synthesis hole,
  # obs 2026-07-15). The diagnostic must use printf '%s', not echo, so no live ESC
  # is emitted even under such a shell. Exercised by running the script under any
  # available sh whose echo actually re-synthesizes.
  esc=$(printf '\033')
  set +e
  for _sh in dash sh /bin/sh; do
    command -v "$_sh" >/dev/null 2>&1 || continue
    [ "$("$_sh" -c 'echo "\033"' 2>/dev/null | od -An -tx1 | tr -d ' \n')" = 1b0a ] || continue
    out=$("$_sh" "$FETCH" --spec 'specs/\033]0;PWNEDx' "$tmp/repo" 2>&1 >/dev/null)
    case $out in
      *"$esc"*)
        set -e
        fail "c11: literal-backslash --spec re-synthesized a live ESC under $_sh (use printf '%s', not echo)"
        ;;
    esac
    break
  done
  set -e
  echo "ok c11: untrusted --spec escapes (formed and literal-backslash) are rejected and sanitized"
}

# ---------------------------------------------------------------------------
# Case 12 — fail CLOSED when the spec anchor is unresolvable at the fetched
# origin/main (D-9 "never a silent stale gate"). origin/main is current but has
# DROPPED the spec bundle upstream, while the stale local main still carries it.
# With --spec the gate has no current baseline: the script must exit 5 with NO
# anchor line, never exit 0 with a stale local-main anchor the caller would
# silently gate on. Local main must stay put on the fail path.
# ---------------------------------------------------------------------------
c12() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-fetch.c12.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  git init -q --bare "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/primary" 2>/dev/null
  write_spec "$tmp/primary" demo v1
  gitc "$tmp/primary" add -A
  gitc "$tmp/primary" commit -q -m "spec v1"
  gitc "$tmp/primary" branch -M main
  gitc "$tmp/primary" push -q origin main

  # An upstream change drops specs/demo from origin/main; primary has not fetched,
  # so its origin/main tracking (and its local main) still carry the stale spec.
  git clone -q "$tmp/origin.git" "$tmp/dev2" 2>/dev/null
  rm -rf "$tmp/dev2/specs/demo"
  gitc "$tmp/dev2" add -A
  gitc "$tmp/dev2" commit -q -m "drop spec"
  gitc "$tmp/dev2" push -q origin main

  main_before=$(gitc "$tmp/primary" rev-parse main)
  set +e
  out=$(PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$tmp/state" \
    "$FETCH" --spec specs/demo "$tmp/primary" 2>/dev/null)
  rc=$?
  set -e
  [ "$rc" -eq 5 ] \
    || fail "c12: expected exit 5 (fail closed; origin/main dropped the spec), got $rc"
  [ "$(tag_val "$out" fetch)" = fetched ] \
    || fail "c12: expected fetch=fetched (the fetch itself succeeded), got '$(tag_val "$out" fetch)'"
  printf '%s\n' "$out" | awk -F"$TAB" '$1=="anchor"{exit 0} END{exit 1}' \
    && fail "c12: emitted a STALE local-main anchor instead of failing closed"
  [ "$(gitc "$tmp/primary" rev-parse main)" = "$main_before" ] \
    || fail "c12: local main moved on the fail-closed path"
  echo "ok c12: fail closed (exit 5, no stale-main fallback) when origin/main drops the spec"
}

c1
c2
c3
c4
c5
c6
c7
c8
c9
c10
c11
c12

echo "PASS: test-dispatch-fetch.sh"
