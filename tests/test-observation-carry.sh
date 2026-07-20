#!/bin/bash
# Tests for scripts/observation-carry.sh — the sanctioned tower-observation-to-
# `main` carry path (fleet-hardening Task 9; D-9; REQ-D1.3, REQ-E1.3).
#
# Contract under test:
#   - a tower branch carrying committed observation fragments, run through the
#     carry, produces a chore PR (or equivalent sanctioned carry) landing them
#     toward `main` (REQ-D1.3): the fragments are pushed onto ONE chore branch
#     and a draft PR is opened against `main`;
#   - a no-observation run is a clean no-op (no branch push, no PR, exit 0);
#   - nothing is stranded silently: a degrade (no remote / no gh) names the
#     stranded observations and exits non-zero rather than dropping them;
#   - the carry is IDEMPOTENT — reuse/update ONE open chore PR, dedupe already-
#     carried fragments — and safe under repeat/concurrent runs: a duplicate run
#     opens no second PR (REQ-D1.3);
#   - a new fragment appearing after the first carry is appended to the SAME
#     chore branch/PR as a new commit (never force-push, never a second PR);
#   - a fragment already on `origin/main` is not re-carried (dedupe);
#   - the path NEVER merges the PR and NEVER advances shared local `main`
#     (REQ-D1.3);
#   - no model/API call occurs anywhere in the decision path (REQ-E1.3);
#   - fail-closed on malformed input (non-git dir, bad --branch).
#
# Output stream is a tagged TSV on stdout, one record per line:
#   carry<TAB><created|updated|noop|degraded>
#   stranded<TAB><n>
#   pr<TAB><number-or-url>            (on created/updated when known)
# Exit: 0 created|updated|noop; 3 degraded (no remote / no gh / push-or-PR
#   failed — stranded named, never silent); 2 usage / invalid input (fail closed).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
CARRY="$here/../scripts/observation-carry.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$CARRY" ] || fail "scripts/observation-carry.sh missing or not executable"
# The gh stub faithfully emulates `gh ... --jq <expr>` by running the SAME
# expression through real jq, so this suite hard-depends on jq (as many sibling
# suites do). Preflight-check it so a missing jq fails clearly and early rather
# than as a confusing `command not found` inside the stub.
command -v jq >/dev/null 2>&1 || fail "jq required to run this suite (the gh stub runs jq)"

# git with a deterministic, signing-free identity (fixtures never sign).
gitc() {
  repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# Pull the value of a tagged record (col 1 == tag) out of the carry output.
tag_val() {
  printf '%s\n' "$1" | awk -F"$TAB" -v t="$2" '$1==t {print $2; exit}'
}

# --- gh stub -----------------------------------------------------------------
# A deterministic, no-network gh whose PR state lives in files under $GH_STATE:
#   $GH_STATE/open-prs   one head-branch per line for which an open PR exists
#   $GH_STATE/create-log one line per `gh pr create` invocation (the head)
#   $GH_STATE/merge-log  one line per `gh pr merge` invocation
# The script always calls `pr list --head X --state open --json number --jq
# '.[0].number'`, so the stub honors that extraction: it prints the PR NUMBER
# (or empty) — mirroring real gh, where an empty result set yields empty output.
# `pr create --head X` refuses (exit 1) if X already has an open PR (mirrors
# real gh), else logs + records the branch open and prints a URL.
make_gh_stub() {
  _dir="$1"
  mkdir -p "$_dir"
  cat >"$_dir/gh" <<'STUB'
#!/bin/sh
# Minimal deterministic gh; PR state in $GH_STATE (set by the test).
set -u
st="${GH_STATE:?GH_STATE unset}"
mkdir -p "$st" 2>/dev/null || true
open="$st/open-prs"
[ -f "$open" ] || : >"$open"
[ -f "$st/create-log" ] || : >"$st/create-log"
[ -f "$st/merge-log" ] || : >"$st/merge-log"
# gh accepts a leading -R <repo>; skip it so positional parsing is uniform.
if [ "${1:-}" = "-R" ]; then shift 2 2>/dev/null || shift; fi
sub="${1:-}"
act="${2:-}"
head=""
jqexpr=""
base=""
has_draft=0
prev=""
for a in "$@"; do
  case "$prev" in
    --head) head="$a" ;;
    --jq) jqexpr="$a" ;;
    --base) base="$a" ;;
  esac
  [ "$a" = "--draft" ] && has_draft=1
  prev="$a"
done
case "$sub $act" in
  "pr list")
    # Faithfully emulate `gh pr list --json number --jq <expr>` by running the
    # SAME jq expression the script passes over the synthesized result set: an
    # empty match is `[]`, a match is `[{"number":101}]`. This is what exposes a
    # bare `.[0].number` (which prints the literal "null" on []); the script must
    # use `.[0].number // empty` so an empty set yields empty output.
    if [ -n "$head" ] && grep -qxF "$head" "$open" 2>/dev/null; then
      json='[{"number":101,"url":"https://example.invalid/pr/101","headRefName":"'"$head"'"}]'
    else
      json='[]'
    fi
    if [ -n "$jqexpr" ]; then
      printf '%s' "$json" | jq -r "$jqexpr"
    else
      printf '%s\n' "$json"
    fi
    ;;
  "pr create")
    # Test hook: a `fail-create` marker makes `gh pr create` fail (to exercise
    # the PR-open-failure degrade). The log still records the attempt.
    if [ -f "$st/fail-create" ]; then
      printf '%s draft=%s base=%s FAILED\n' "${head:-?}" "$has_draft" "${base:-?}" >>"$st/create-log"
      echo "gh: simulated pr create failure" >&2
      exit 1
    fi
    if [ -n "$head" ] && grep -qxF "$head" "$open" 2>/dev/null; then
      echo "gh: a pull request for branch \"$head\" already exists" >&2
      exit 1
    fi
    [ -n "$head" ] && printf '%s\n' "$head" >>"$open"
    # Log head + whether --draft was passed + the --base value, so dropped-draft
    # and base-derivation regressions are detectable.
    printf '%s draft=%s base=%s\n' "${head:-?}" "$has_draft" "${base:-?}" >>"$st/create-log"
    printf 'https://example.invalid/pr/101\n'
    ;;
  "pr merge")
    printf '%s\n' "${head:-?}" >>"$st/merge-log"
    ;;
  *)
    : # pr edit / pr view / anything else: benign success
    ;;
esac
exit 0
STUB
  chmod +x "$_dir/gh"
}

# Build a repo with a bare origin, a seeded main carrying one pre-existing
# observation fragment, and a tower branch carrying `n` fresh fragments.
# Prints the repo path.
OBSREL="specs/_observations/entries"
frag_path() { printf '%s/%s' "$OBSREL" "$1"; }
frag_body() { printf -- '- 2026-07-20 [repo] observation %s\n' "$1"; }

seed_repo() {
  root="$1"
  mkdir -p "$root"
  gitc "$root" init -q -b main
  mkdir -p "$root/$OBSREL"
  # A pre-existing fragment already on main (must never be re-carried).
  frag_body "on-main-aaaa1111" >"$root/$(frag_path 2026-07-19-seed-aaaa1111.md)"
  gitc "$root" add -A
  gitc "$root" commit -qm "seed: main with a carried observation"
  gitc "$root" init -q --bare "$root.git"
  gitc "$root" remote add origin "$root.git"
  gitc "$root" push -q -u origin main
}

# Add `n` committed fragments on the current branch of <root>; the slugs are
# unique per call via the supplied tag.
add_frags() {
  root="$1"
  tag="$2"
  shift 2
  for uid in "$@"; do
    frag_body "$uid" >"$root/$(frag_path "2026-07-20-$tag-$uid.md")"
  done
  gitc "$root" add -A
  gitc "$root" commit -qm "obs($tag): record ${#} fragment(s)"
}

run_carry() {
  ghbin="$1"
  ghstate="$2"
  shift 2
  # Invoke the script through its own `#!/bin/sh` shebang (not a forced
  # /bin/bash), so the tests exercise the production interpreter — dash on Linux
  # CI — and surface any accidental bashism. Matches the sibling suites.
  PATH="$ghbin:$PATH" GH_STATE="$ghstate" \
    PLANWRIGHT_OBSERVATION_CARRY_STATE_DIR="$ghstate/carry-lock" \
    "$CARRY" "$@"
}

# origin/<ref> tree listing of the entries dir (basenames), sorted.
origin_entries() {
  root="$1"
  ref="$2"
  gitc "$root" ls-tree -r --name-only "$ref" -- "$OBSREL" 2>/dev/null \
    | sed 's#.*/##' | LC_ALL=C sort
}

# ---------------------------------------------------------------------------
# Case 1 — happy path: a tower branch with 2 stranded fragments produces a
# chore branch pushed to origin + a draft PR against main; local main is
# unchanged; the pre-existing on-main fragment is not re-carried (REQ-D1.3).
# ---------------------------------------------------------------------------
c1() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/obs-carry.c1.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  repo="$tmp/repo"
  seed_repo "$repo"
  gitc "$repo" checkout -q -b planwright/fleet-hardening/task-9
  add_frags "$repo" tower bbbb2222 cccc3333
  main_before=$(gitc "$repo" rev-parse main)
  gh="$tmp/bin"
  make_gh_stub "$gh"

  out=$(run_carry "$gh" "$tmp/ghstate" "$repo" 2>"$tmp/err") || fail "c1: carry exit $? — $(cat "$tmp/err")"
  [ "$(tag_val "$out" carry)" = created ] || fail "c1: expected carry=created, got: $out"
  [ "$(tag_val "$out" stranded)" = 2 ] || fail "c1: expected stranded=2, got: $out"

  # Exactly one PR created, and it was created as a DRAFT.
  [ "$(wc -l <"$tmp/ghstate/create-log" | tr -d ' ')" = 1 ] \
    || fail "c1: expected exactly one gh pr create"
  grep -q "draft=1" "$tmp/ghstate/create-log" \
    || fail "c1: PR must be created with --draft (got: $(cat "$tmp/ghstate/create-log"))"
  # Default base origin/main → PR base 'main' (the remote segment stripped).
  grep -q "base=main" "$tmp/ghstate/create-log" \
    || fail "c1: PR base should be 'main' for default origin/main (got: $(cat "$tmp/ghstate/create-log"))"
  # Never merged.
  [ ! -s "$tmp/ghstate/merge-log" ] || fail "c1: carry must never merge the PR"
  # Local main byte-for-byte unchanged.
  [ "$(gitc "$repo" rev-parse main)" = "$main_before" ] \
    || fail "c1: local main was advanced (must never touch shared local main)"

  # The chore branch on origin carries BOTH stranded fragments and NOT the
  # pre-existing on-main fragment beyond what main already has.
  chore_entries=$(origin_entries "$repo" "origin/planwright/chore/observations")
  printf '%s\n' "$chore_entries" | grep -qx "2026-07-20-tower-bbbb2222.md" \
    || fail "c1: chore branch missing fragment bbbb2222"
  printf '%s\n' "$chore_entries" | grep -qx "2026-07-20-tower-cccc3333.md" \
    || fail "c1: chore branch missing fragment cccc3333"
  echo "ok c1: stranded fragments carried onto a chore branch + draft PR; local main untouched"
}

# ---------------------------------------------------------------------------
# Case 2 — no observations: a tower branch with nothing stranded is a clean
# no-op (no push, no PR, exit 0) (REQ-D1.3).
# ---------------------------------------------------------------------------
c2() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/obs-carry.c2.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  repo="$tmp/repo"
  seed_repo "$repo"
  gitc "$repo" checkout -q -b planwright/fleet-hardening/task-9
  # No new fragments added — only the pre-existing on-main one exists.
  gh="$tmp/bin"
  make_gh_stub "$gh"

  out=$(run_carry "$gh" "$tmp/ghstate" "$repo" 2>"$tmp/err") || fail "c2: carry exit $? — $(cat "$tmp/err")"
  [ "$(tag_val "$out" carry)" = noop ] || fail "c2: expected carry=noop, got: $out"
  [ ! -s "$tmp/ghstate/create-log" ] || fail "c2: no-op must open no PR"
  gitc "$repo" ls-remote --heads origin "planwright/chore/observations" 2>/dev/null | grep -q . \
    && fail "c2: no-op must push no chore branch"
  echo "ok c2: no-observation run is a clean no-op"
}

# ---------------------------------------------------------------------------
# Case 3 — idempotent repeat: running the carry twice over the same stranded
# set opens exactly ONE PR; the second run is a no-op (dedupe) (REQ-D1.3).
# ---------------------------------------------------------------------------
c3() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/obs-carry.c3.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  repo="$tmp/repo"
  seed_repo "$repo"
  gitc "$repo" checkout -q -b planwright/fleet-hardening/task-9
  add_frags "$repo" tower dddd4444
  gh="$tmp/bin"
  make_gh_stub "$gh"

  out1=$(run_carry "$gh" "$tmp/ghstate" "$repo" 2>"$tmp/err") || fail "c3: run1 exit $? — $(cat "$tmp/err")"
  [ "$(tag_val "$out1" carry)" = created ] || fail "c3: run1 expected created, got: $out1"
  out2=$(run_carry "$gh" "$tmp/ghstate" "$repo" 2>"$tmp/err") || fail "c3: run2 exit $? — $(cat "$tmp/err")"
  [ "$(tag_val "$out2" carry)" = noop ] || fail "c3: run2 expected noop (dedupe), got: $out2"
  [ "$(wc -l <"$tmp/ghstate/create-log" | tr -d ' ')" = 1 ] \
    || fail "c3: duplicate run opened a second PR (must reuse one)"
  echo "ok c3: idempotent — duplicate run opens no second PR"
}

# ---------------------------------------------------------------------------
# Case 4 — incremental append: a new fragment after the first carry is appended
# to the SAME chore branch/PR as a new commit; still ONE PR (REQ-D1.3).
# ---------------------------------------------------------------------------
c4() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/obs-carry.c4.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  repo="$tmp/repo"
  seed_repo "$repo"
  gitc "$repo" checkout -q -b planwright/fleet-hardening/task-9
  add_frags "$repo" tower eeee5555
  gh="$tmp/bin"
  make_gh_stub "$gh"

  run_carry "$gh" "$tmp/ghstate" "$repo" >/dev/null 2>"$tmp/err" || fail "c4: run1 — $(cat "$tmp/err")"
  chore_before=$(gitc "$repo" rev-parse "origin/planwright/chore/observations")
  add_frags "$repo" tower ffff6666
  out=$(run_carry "$gh" "$tmp/ghstate" "$repo" 2>"$tmp/err") || fail "c4: run2 exit $? — $(cat "$tmp/err")"
  [ "$(tag_val "$out" carry)" = updated ] || fail "c4: run2 expected updated, got: $out"
  [ "$(wc -l <"$tmp/ghstate/create-log" | tr -d ' ')" = 1 ] \
    || fail "c4: incremental carry opened a second PR (must reuse one)"

  chore_after=$(gitc "$repo" rev-parse "origin/planwright/chore/observations")
  [ "$chore_after" != "$chore_before" ] || fail "c4: chore branch not advanced by the new fragment"
  # New commit is a fast-forward (chore_before is an ancestor — never force-push).
  gitc "$repo" merge-base --is-ancestor "$chore_before" "$chore_after" \
    || fail "c4: chore branch was not fast-forwarded (force-push forbidden)"
  entries=$(origin_entries "$repo" "$chore_after")
  printf '%s\n' "$entries" | grep -qx "2026-07-20-tower-eeee5555.md" || fail "c4: lost first fragment"
  printf '%s\n' "$entries" | grep -qx "2026-07-20-tower-ffff6666.md" || fail "c4: missing new fragment"
  echo "ok c4: new fragment appended to the same chore branch/PR (fast-forward, one PR)"
}

# ---------------------------------------------------------------------------
# Case 5 — dedupe against main: a fragment already present on origin/main is
# never re-carried (REQ-D1.3).
# ---------------------------------------------------------------------------
c5() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/obs-carry.c5.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  repo="$tmp/repo"
  seed_repo "$repo"
  gitc "$repo" checkout -q -b planwright/fleet-hardening/task-9
  # Re-add the SAME path that already exists on main, plus one genuinely new.
  frag_body "on-main-aaaa1111" >"$repo/$(frag_path 2026-07-19-seed-aaaa1111.md)"
  frag_body "new-gggg7777" >"$repo/$(frag_path 2026-07-20-tower-gggg7777.md)"
  gitc "$repo" add -A
  gitc "$repo" commit -qm "obs(tower): a new one alongside an already-carried one" || true
  gh="$tmp/bin"
  make_gh_stub "$gh"

  out=$(run_carry "$gh" "$tmp/ghstate" "$repo" 2>"$tmp/err") || fail "c5: carry exit $? — $(cat "$tmp/err")"
  [ "$(tag_val "$out" stranded)" = 1 ] || fail "c5: expected stranded=1 (dedupe the on-main one), got: $out"
  echo "ok c5: a fragment already on origin/main is not re-carried"
}

# ---------------------------------------------------------------------------
# Case 6 — degrade, not silent: no origin remote → the stranded observations
# are named and the carry exits 3, never a silent drop (REQ-D1.3, REQ-K1.7).
# ---------------------------------------------------------------------------
c6() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/obs-carry.c6.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  repo="$tmp/repo"
  mkdir -p "$repo"
  gitc "$repo" init -q -b main
  # Seed main (no fragment), then strand a fragment on a tower branch — with NO
  # origin remote, so the carry has nowhere to push.
  echo seed >"$repo/seed"
  gitc "$repo" add -A
  gitc "$repo" commit -qm "seed: main"
  gitc "$repo" checkout -q -b planwright/fleet-hardening/task-9
  mkdir -p "$repo/$OBSREL"
  frag_body "hhhh8888" >"$repo/$(frag_path 2026-07-20-tower-hhhh8888.md)"
  gitc "$repo" add -A
  gitc "$repo" commit -qm "obs(tower): stranded with no remote"
  gh="$tmp/bin"
  make_gh_stub "$gh"

  set +e
  out=$(run_carry "$gh" "$tmp/ghstate" "$repo" 2>"$tmp/err")
  rc=$?
  set -e
  [ "$rc" = 3 ] || fail "c6: expected exit 3 (degraded), got $rc — $out"
  [ "$(tag_val "$out" carry)" = degraded ] || fail "c6: expected carry=degraded, got: $out"
  # The stranded count is surfaced (not silently dropped).
  [ "$(tag_val "$out" stranded)" = 1 ] || fail "c6: degrade must name the stranded count, got: $out"
  echo "ok c6: no-remote degrades non-silently (exit 3, stranded named)"
}

# ---------------------------------------------------------------------------
# Case 7 — REQ-E1.3: no model/API call anywhere in the decision path. A source
# grep asserts the carry invokes no LLM/model endpoint (the sibling idiom).
# ---------------------------------------------------------------------------
c7() {
  src="$here/../scripts/observation-carry.sh"
  [ -f "$src" ] || fail "c7: expected decision-path script missing: $src"
  code=$(grep -vE '^[[:space:]]*#' "$src" || true)
  if printf '%s\n' "$code" | grep -nE '(^|[^A-Za-z_./])claude[[:space:]]' >/dev/null \
    || printf '%s\n' "$code" | grep -niE 'anthropic|/v1/messages|https?://' >/dev/null \
    || printf '%s\n' "$code" | grep -niwE '(curl|wget)' >/dev/null; then
    fail "c7: $src references a model/API/network surface in the decision path (REQ-E1.3)"
  fi
  echo "ok c7: no model/API call anywhere in the decision path (REQ-E1.3)"
}

# ---------------------------------------------------------------------------
# Case 8 — fail-closed: no repo-root arg exits 2; a non-git dir exits 2; a
# hostile --branch value exits 2 (framework-script safety).
# ---------------------------------------------------------------------------
c8() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/obs-carry.c8.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  gh="$tmp/bin"
  make_gh_stub "$gh"

  set +e
  run_carry "$gh" "$tmp/ghstate" >/dev/null 2>&1
  rc_noarg=$?
  run_carry "$gh" "$tmp/ghstate" "$tmp/not-a-repo" >/dev/null 2>&1
  rc_nongit=$?
  mkdir -p "$tmp/repo2"
  gitc "$tmp/repo2" init -q -b main
  run_carry "$gh" "$tmp/ghstate" --branch "../evil" "$tmp/repo2" >/dev/null 2>&1
  rc_badbranch=$?
  set -e
  [ "$rc_noarg" = 2 ] || fail "c8: no arg should exit 2, got $rc_noarg"
  [ "$rc_nongit" = 2 ] || fail "c8: non-git dir should exit 2, got $rc_nongit"
  [ "$rc_badbranch" = 2 ] || fail "c8: hostile --branch should exit 2, got $rc_badbranch"
  echo "ok c8: fail-closed on malformed input"
}

# ---------------------------------------------------------------------------
# Case 9 — never merges (source-level floor): the carry script contains no
# merge / auto-merge / ready-flip surface (REQ-D1.3, REQ-E1.4 spirit).
# ---------------------------------------------------------------------------
c9() {
  code=$(grep -vE '^[[:space:]]*#' "$CARRY" || true)
  # grep is already line-oriented, so `--force` / `force-with-lease` as bare
  # alternatives catch a force-push anywhere; no `[^\n]` bridge is needed (and
  # `[^\n]` inside a bracket wrongly excludes the literal letter n).
  if printf '%s\n' "$code" | grep -niE 'gh[[:space:]]+pr[[:space:]]+merge|--auto|merge_pull_request|pr[[:space:]]+ready|--force|force-with-lease' >/dev/null; then
    fail "c9: carry references a merge / ready-flip / force-push surface"
  fi
  echo "ok c9: no merge / ready-flip / force-push surface in the carry"
}

# ---------------------------------------------------------------------------
# Case 10 — --dry-run: computes + reports the stranded count but opens no PR and
# pushes no branch (the read-only surface).
# ---------------------------------------------------------------------------
c10() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/obs-carry.c10.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  repo="$tmp/repo"
  seed_repo "$repo"
  gitc "$repo" checkout -q -b planwright/fleet-hardening/task-9
  add_frags "$repo" tower iiii9999
  gh="$tmp/bin"
  make_gh_stub "$gh"

  out=$(run_carry "$gh" "$tmp/ghstate" --dry-run "$repo" 2>"$tmp/err") || fail "c10: carry exit $? — $(cat "$tmp/err")"
  [ "$(tag_val "$out" carry)" = noop ] || fail "c10: --dry-run expected carry=noop, got: $out"
  [ "$(tag_val "$out" stranded)" = 1 ] || fail "c10: --dry-run should report stranded=1, got: $out"
  [ ! -s "$tmp/ghstate/create-log" ] || fail "c10: --dry-run must open no PR"
  gitc "$repo" ls-remote --heads origin "planwright/chore/observations" 2>/dev/null | grep -q . \
    && fail "c10: --dry-run must push no chore branch"
  echo "ok c10: --dry-run reports stranded count without pushing or opening a PR"
}

# ---------------------------------------------------------------------------
# Case 11 — a REAL lock error (state dir unwritable / filesystem error) must
# degrade non-silently, not be misread as lock contention and reported as a
# clean no-op while observations are still stranded (REQ-D1.3 non-silent
# stranding; mirrors orchestrate-lock.sh's real-error-vs-contention split).
# ---------------------------------------------------------------------------
c11() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/obs-carry.c11.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  repo="$tmp/repo"
  seed_repo "$repo"
  gitc "$repo" checkout -q -b planwright/fleet-hardening/task-9
  add_frags "$repo" tower jjjjaaaa
  gh="$tmp/bin"
  make_gh_stub "$gh"
  # Force a real lock-dir creation error: point the state dir UNDER a regular
  # file, so both `mkdir -p <state-dir>` and `mkdir <state-dir>/...lock` fail and
  # the lock dir never comes into existence (a genuine error, not contention).
  printf 'x' >"$tmp/afile"

  set +e
  out=$(PATH="$gh:$PATH" GH_STATE="$tmp/ghstate" \
    PLANWRIGHT_OBSERVATION_CARRY_STATE_DIR="$tmp/afile/state" \
    "$CARRY" "$repo" 2>"$tmp/err")
  rc=$?
  set -e
  [ "$rc" = 3 ] || fail "c11: real lock error must degrade (exit 3), got $rc — out: $out; err: $(cat "$tmp/err")"
  [ "$(tag_val "$out" carry)" = degraded ] || fail "c11: expected carry=degraded, got: $out"
  [ "$(tag_val "$out" stranded)" = 1 ] || fail "c11: degrade must name the stranded count, got: $out"
  [ ! -s "$tmp/ghstate/create-log" ] || fail "c11: a lock-error degrade must open no PR"
  echo "ok c11: a real lock error degrades non-silently (not a silent no-op)"
}

# ---------------------------------------------------------------------------
# Case 12 — PR-base derivation is remote-aware: a local base branch that
# contains a slash (release/9.9) is used verbatim, NOT corrupted to its tail,
# because "release" is not a configured remote.
# ---------------------------------------------------------------------------
c12() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/obs-carry.c12.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  repo="$tmp/repo"
  seed_repo "$repo"
  # A local base branch whose name legitimately contains a slash.
  gitc "$repo" branch "release/9.9" main
  gitc "$repo" checkout -q -b planwright/fleet-hardening/task-9
  add_frags "$repo" tower kkkkbbbb
  gh="$tmp/bin"
  make_gh_stub "$gh"

  out=$(run_carry "$gh" "$tmp/ghstate" --base "release/9.9" "$repo" 2>"$tmp/err") \
    || fail "c12: carry exit $? — $(cat "$tmp/err")"
  [ "$(tag_val "$out" carry)" = created ] || fail "c12: expected created, got: $out"
  grep -q "base=release/9.9" "$tmp/ghstate/create-log" \
    || fail "c12: local slashed base must be preserved, not stripped (got: $(cat "$tmp/ghstate/create-log"))"
  echo "ok c12: PR-base derivation is remote-aware (local slashed base preserved)"
}

# ---------------------------------------------------------------------------
# Case 13 — a `gh pr create` failure degrades non-silently AND names the
# fragments now on the pushed chore branch awaiting a manual PR (REQ-D1.3).
# ---------------------------------------------------------------------------
c13() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/obs-carry.c13.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  repo="$tmp/repo"
  seed_repo "$repo"
  gitc "$repo" checkout -q -b planwright/fleet-hardening/task-9
  add_frags "$repo" tower llllcccc
  gh="$tmp/bin"
  make_gh_stub "$gh"
  mkdir -p "$tmp/ghstate"
  : >"$tmp/ghstate/fail-create" # make `gh pr create` fail

  set +e
  out=$(run_carry "$gh" "$tmp/ghstate" "$repo" 2>"$tmp/err")
  rc=$?
  set -e
  [ "$rc" = 3 ] || fail "c13: pr-create failure should degrade (exit 3), got $rc — $out"
  [ "$(tag_val "$out" carry)" = degraded ] || fail "c13: expected carry=degraded, got: $out"
  # The chore branch was still pushed (fragments reached the remote).
  gitc "$repo" ls-remote --heads origin "planwright/chore/observations" 2>/dev/null | grep -q . \
    || fail "c13: chore branch should have been pushed before the PR-create attempt"
  # The degrade names the specific fragment on the branch.
  grep -q "2026-07-20-tower-llllcccc.md" "$tmp/err" \
    || fail "c13: pr-create degrade must name the carried fragment (err: $(cat "$tmp/err"))"
  echo "ok c13: pr-create failure degrades non-silently and names the fragments"
}

# ---------------------------------------------------------------------------
# Case 14 — --branch must be a plain branch name: a remote-qualified value
# (origin/main) or a full-ref form (refs/heads/foo) is rejected (exit 2), so the
# carry never pushes to refs/heads/origin/main or discovers the wrong PR.
# ---------------------------------------------------------------------------
c14() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/obs-carry.c14.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  repo="$tmp/repo"
  seed_repo "$repo" # gives origin remote
  gitc "$repo" checkout -q -b planwright/fleet-hardening/task-9
  add_frags "$repo" tower mmmmdddd
  gh="$tmp/bin"
  make_gh_stub "$gh"

  set +e
  run_carry "$gh" "$tmp/ghstate" --branch "origin/main" "$repo" >/dev/null 2>&1
  rc_remote=$?
  run_carry "$gh" "$tmp/ghstate" --branch "refs/heads/foo" "$repo" >/dev/null 2>&1
  rc_refs=$?
  # A plain namespaced branch whose first segment is NOT a remote is still fine.
  run_carry "$gh" "$tmp/ghstate" --branch "planwright/chore/observations" "$repo" >/dev/null 2>"$tmp/err"
  rc_ok=$?
  set -e
  [ "$rc_remote" = 2 ] || fail "c14: remote-qualified --branch origin/main should exit 2, got $rc_remote"
  [ "$rc_refs" = 2 ] || fail "c14: refs/... --branch should exit 2, got $rc_refs"
  [ "$rc_ok" = 0 ] || fail "c14: a plain namespaced --branch should be accepted, got $rc_ok — $(cat "$tmp/err")"
  echo "ok c14: --branch rejects remote-qualified / full-ref forms"
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
c13
c14
echo "ALL PASS: observation-carry"
