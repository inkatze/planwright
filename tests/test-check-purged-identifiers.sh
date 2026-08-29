#!/bin/bash
# Tests for the purged-identifier guard — scripts/check-purged-identifiers.sh,
# its provisioning path scripts/seed-purged-identifiers.sh, and the
# githooks/commit-msg screen that extends Task 2's backstop with it
# (guard-coverage Task 3; D-5; REQ-B1.1, REQ-B1.2, REQ-H1.3).
#
# Contract under test:
#   - a planted seeded token in a tracked file fails the tree scan and a clean
#     tree passes, with the match reported by LOCATION only: the guard must
#     never echo the identifier it exists to keep out of the tree;
#   - the normalization boundary is pinned in BOTH directions — every casing,
#     separator, embedded (URL / mailto: / slug / path) and joined variant is
#     caught, while a shape with no word boundary at the identifier's edge, a
#     fragment of it, and a line-split spelling deliberately pass;
#   - untracked files, ignored files and binaries are out of the tree scan's
#     reach by design;
#   - a commit message carrying a planted token is rejected by BOTH the
#     commit-msg hook (write time, wired clones) and the CI-side commit-range
#     scan (unwired clones, --no-verify commits, fork PRs), while text git will
#     strip from the message — comment lines, a --verbose scissors diff — is
#     screened out first so a remediation commit is not refused for the diff it
#     removes;
#   - every vacuous-input case fails CLOSED per REQ-H1.3: a missing, empty,
#     malformed, directive-less, zero-hash or below-floor seed file, an empty
#     commit range, an empty message, and a tree with nothing scannable in it;
#   - the provisioning path is non-logging: stdin only, never argv, and it
#     never prints what it read on any success or failure path (REQ-B1.2);
#   - the COMMITTED seed file is hash-only, meets its own declared floor, and
#     is not merely this suite's test tokens — the "vacuously green seed list"
#     failure mode (REQ-B1.2);
#   - the wiring is pinned decidably: the check is a member of the `check`
#     aggregate, ci.yml carries the commit-range step, and the hook calls the
#     scanner.
#
# Every seed file here is per-test and temporary, planted with test-only
# tokens: one shared test seed would race under the parallel runner, and the
# real identifiers are provisioned out of band and never available to a test.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

# Isolate fixtures from the host's global/system git config (a global
# core.hooksPath, commit signing, or autosetuprebase would all corrupt them).
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_SYSTEM=/dev/null
GIT_EDITOR=true
export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_EDITOR

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SCAN="$REPO_ROOT/scripts/check-purged-identifiers.sh"
SEEDER="$REPO_ROOT/scripts/seed-purged-identifiers.sh"
REAL_SEED="$REPO_ROOT/config/purged-identifiers.seed"

# Test-only planted tokens. They exist nowhere but this suite and its
# fixtures; the committed seed file is asserted at the end NOT to contain
# them, which is what makes a test-token-only seed list a failure.
TOKEN='zzq-planted-seedtoken'
TOKEN2='zzq-second-planted-token'
# The normalized spelling of TOKEN. The withholding assertions check BOTH: a
# report that echoed the normalized candidate instead of the source text would
# leak the identifier just as effectively.
NORM='zzqplantedseedtoken'

failures=0

assert_exit() {
  # assert_exit <label> <expected-exit> <actual-exit>
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  # assert_contains <label> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (missing '$2')" >&2
      echo "----- output -----" >&2
      printf '%s\n' "$3" >&2
      echo "------------------" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_absent() {
  # assert_absent <label> <needle> <haystack>
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (output leaked '$2')" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

# ---- fixture-setup assertions: the deliverables this suite exercises must
# ---- exist before any scenario runs (Done-when setup-succeeded floor).
for f in "$SCAN" "$SEEDER"; do
  if [ ! -x "$f" ]; then
    echo "FAIL: $f missing or not executable" >&2
    exit 1
  fi
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/purged-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

# new_repo <name> — a fresh fixture repo with a deterministic, signing-free
# identity, and no hooks unless a scenario wires them.
new_repo() {
  d="$TMP/$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email fixture@example.invalid
  git -C "$d" config user.name 'Fixture'
  git -C "$d" config commit.gpgsign false
  printf '%s' "$d"
}

# seed_into <repo> <token>... — provision a per-test seed file through the
# real seeding path, so the suite exercises the same normalization contract
# the scanner reads (never a hand-written hash).
seed_into() {
  repo="$1"
  shift
  mkdir -p "$repo/config"
  printf '%s\n' "$@" \
    | (cd "$repo" && "$SEEDER" >/dev/null 2>&1)
}

# ---------------------------------------------------------------------------
# Tree scan: detection, and the report withholding the match.
# ---------------------------------------------------------------------------

r="$(new_repo detect)"
seed_into "$r" "$TOKEN"
printf 'a clean line\nthis mentions %s in prose\n' "$TOKEN" >"$r/doc.md"
git -C "$r" add doc.md
out="$(cd "$r" && "$SCAN" 2>&1)"
rc=$?
assert_exit "a planted token in a tracked file fails the tree scan" 1 $rc
assert_contains "the report names the file and line" "doc.md:2" "$out"
assert_absent "the report withholds the matched text" "$TOKEN" "$out"
assert_absent "the report withholds the normalized form too" "$NORM" "$out"

r="$(new_repo clean)"
seed_into "$r" "$TOKEN"
printf 'nothing to see here\n' >"$r/doc.md"
git -C "$r" add doc.md
out="$(cd "$r" && "$SCAN" 2>&1)"
assert_exit "a clean tree passes" 0 $?
assert_contains "a clean run reports what it scanned" "tracked text file(s) scanned" "$out"

# ---------------------------------------------------------------------------
# The normalization boundary, pinned in both directions.
# ---------------------------------------------------------------------------

# in_scope <label> <line> — the line must be caught.
in_scope() {
  r="$(new_repo "in-$2")"
  seed_into "$r" "$TOKEN"
  printf '%s\n' "$3" >"$r/doc.md"
  git -C "$r" add doc.md
  (cd "$r" && "$SCAN" >/dev/null 2>&1)
  assert_exit "in scope: $1" 1 $?
}

# out_of_scope <label> <slug> <line> — the line must pass.
out_of_scope() {
  r="$(new_repo "out-$2")"
  seed_into "$r" "$TOKEN"
  printf '%s\n' "$3" >"$r/doc.md"
  git -C "$r" add doc.md
  (cd "$r" && "$SCAN" >/dev/null 2>&1)
  assert_exit "out of scope: $1" 0 $?
}

in_scope "exact spelling" exact "prefix $TOKEN suffix"
in_scope "mixed casing" case 'prefix ZZQ-Planted-SeedToken suffix'
in_scope "underscore separators" underscore 'prefix zzq_planted_seedtoken suffix'
in_scope "dot separators" dot 'prefix zzq.planted.seedtoken suffix'
in_scope "no separators at all" joined 'prefix zzqplantedseedtoken suffix'
in_scope "space separated" spaced 'prefix zzq planted seedtoken suffix'
in_scope "inside a URL" url "see https://example.com/$TOKEN/tree/main"
in_scope "inside a mailto:" mailto "write to mailto:someone@$TOKEN.example"
in_scope "inside a longer slug" slug "the my-$TOKEN-notes file"
in_scope "inside a path" path "../zzq_planted_seedtoken/README.md"

out_of_scope "no word boundary before the identifier" prefixed "prefix x$TOKEN suffix"
out_of_scope "no word boundary after the identifier" suffixed "prefix ${TOKEN}s suffix"
out_of_scope "a proper fragment of the identifier" fragment 'prefix zzq-planted suffix'
out_of_scope "an altered spelling" typo 'prefix zzq-planted-seedtokn suffix'

r="$(new_repo out-linesplit)"
seed_into "$r" "$TOKEN"
printf 'trailing zzq-planted-\nseedtoken leading\n' >"$r/doc.md"
git -C "$r" add doc.md
(cd "$r" && "$SCAN" >/dev/null 2>&1)
assert_exit "out of scope: split across a line break" 0 $?

# ---------------------------------------------------------------------------
# Tracked-tree scoping and binary exclusion.
# ---------------------------------------------------------------------------

r="$(new_repo untracked)"
seed_into "$r" "$TOKEN"
printf 'tracked and clean\n' >"$r/doc.md"
git -C "$r" add doc.md
printf 'untracked mentions %s\n' "$TOKEN" >"$r/scratch.md"
(cd "$r" && "$SCAN" >/dev/null 2>&1)
assert_exit "an untracked file is out of the tracked-tree scope" 0 $?

r="$(new_repo ignored)"
seed_into "$r" "$TOKEN"
printf 'tracked and clean\n' >"$r/doc.md"
printf 'build/\n' >"$r/.gitignore"
git -C "$r" add doc.md .gitignore
mkdir -p "$r/build"
printf 'ignored mentions %s\n' "$TOKEN" >"$r/build/out.txt"
(cd "$r" && "$SCAN" >/dev/null 2>&1)
assert_exit "an ignored file is out of the tracked-tree scope" 0 $?

r="$(new_repo binary)"
seed_into "$r" "$TOKEN"
printf 'tracked and clean\n' >"$r/doc.md"
printf 'header\000 %s\n' "$TOKEN" >"$r/blob.bin"
git -C "$r" add doc.md blob.bin
(cd "$r" && "$SCAN" >/dev/null 2>&1)
assert_exit "a binary file is excluded from the tree scan" 0 $?

# A tree whose only tracked content is binary scans nothing — and a guard
# that scanned nothing must not report success (REQ-H1.3).
r="$(new_repo binary-only)"
seed_into "$r" "$TOKEN"
printf 'header\000payload\n' >"$r/blob.bin"
git -C "$r" add blob.bin
out="$(cd "$r" && "$SCAN" 2>&1)"
assert_exit "a tree with zero scannable files fails closed" 2 $?
assert_contains "the zero-file failure says so" "0 scannable files" "$out"

# ---------------------------------------------------------------------------
# Hostile and awkward inputs. Tracked filenames and commit ranges are
# fork-PR-controllable, so they are data the guard must survive, not trust.
# ---------------------------------------------------------------------------

# `git ls-files` from a subdirectory lists only that subtree. A run from
# anywhere but the root must still scan the WHOLE tree, or it would report
# success over a fraction of it.
r="$(new_repo subdir)"
seed_into "$r" "$TOKEN"
mkdir -p "$r/sub/deeper"
printf 'top level names %s\n' "$TOKEN" >"$r/doc.md"
printf 'clean\n' >"$r/sub/deeper/other.md"
git -C "$r" add doc.md sub
(cd "$r/sub/deeper" && "$SCAN" >/dev/null 2>&1)
assert_exit "a run from a subdirectory still scans the whole tree" 1 $?

# A relative --seed-file must survive the move to the repo root.
r="$(new_repo relseed)"
seed_into "$r" "$TOKEN"
printf 'names %s\n' "$TOKEN" >"$r/doc.md"
git -C "$r" add doc.md
(cd "$r" && "$SCAN" --seed-file config/purged-identifiers.seed >/dev/null 2>&1)
assert_exit "a relative --seed-file resolves against the caller's directory" 1 $?

# A symlink tracks a target path, not the target's content. The link's own
# target STRING is scanned (below); the file behind it is still never opened.
r="$(new_repo symlink)"
seed_into "$r" "$TOKEN"
printf 'clean tracked content\n' >"$r/doc.md"
printf 'outside content naming %s\n' "$TOKEN" >"$TMP/outside-target.txt"
ln -s "$TMP/outside-target.txt" "$r/link.txt"
git -C "$r" add doc.md link.txt
(cd "$r" && "$SCAN" >/dev/null 2>&1)
assert_exit "a tracked symlink is not followed out of the repository" 0 $?

# ---------------------------------------------------------------------------
# The tracked tree is every tracked BYTE, not only file content: a path git
# records and a symlink's target blob publish an identifier exactly as
# permanently as a line of prose does (REQ-B1.1, "anywhere in the tracked
# tree"). Each of these carries the token ONLY outside file content.
# ---------------------------------------------------------------------------

r="$(new_repo pathname)"
seed_into "$r" "$TOKEN"
printf 'entirely clean content\n' >"$r/$TOKEN-notes.md"
git -C "$r" add -- "$TOKEN-notes.md"
out="$(cd "$r" && "$SCAN" 2>&1)"
assert_exit "a token in a tracked FILENAME fails the scan" 1 $?
assert_contains "the filename report says it matched the path" "tracked path" "$out"
assert_absent "the filename report withholds the matched text" "$TOKEN" "$out"

r="$(new_repo dirname)"
seed_into "$r" "$TOKEN"
mkdir -p "$r/$TOKEN/nested"
printf 'entirely clean content\n' >"$r/$TOKEN/nested/file.md"
git -C "$r" add -- "$TOKEN"
(cd "$r" && "$SCAN" >/dev/null 2>&1)
assert_exit "a token in a tracked DIRECTORY name fails the scan" 1 $?

# git stores a symlink's target path AS the blob's content, so the target
# string is tracked content the guard would otherwise never read.
r="$(new_repo symlink-target)"
seed_into "$r" "$TOKEN"
printf 'clean tracked content\n' >"$r/doc.md"
ln -s "$TOKEN" "$r/harmless-link"
git -C "$r" add doc.md harmless-link
out="$(cd "$r" && "$SCAN" 2>&1)"
assert_exit "a token in a tracked SYMLINK TARGET fails the scan" 1 $?
assert_contains "the symlink report says it matched the target" "symlink target" "$out"
assert_absent "the symlink report withholds the matched text" "$TOKEN" "$out"

# A binary file's CONTENT is out of scope, but the name it is tracked under
# is still text the guard reads.
r="$(new_repo binary-name)"
seed_into "$r" "$TOKEN"
printf 'tracked and clean\n' >"$r/doc.md"
printf 'header\000payload\n' >"$r/$TOKEN.bin"
git -C "$r" add -- doc.md "$TOKEN.bin"
(cd "$r" && "$SCAN" >/dev/null 2>&1)
assert_exit "a token in a BINARY file's name still fails the scan" 1 $?

# A filename is untrusted text: an embedded escape sequence must not reach
# the reader's terminal through the report (echo discipline).
r="$(new_repo escapefile)"
seed_into "$r" "$TOKEN"
esc="$(printf 'esc\033[31mred.md')"
printf 'names %s\n' "$TOKEN" >"$r/$esc"
git -C "$r" add -- "$esc"
out="$(cd "$r" && "$SCAN" 2>&1)"
assert_exit "a filename carrying an escape sequence still reports" 1 $?
assert_absent "the report strips the escape sequence from the filename" "$(printf '\033')" "$out"

# A range beginning with '-' would reach git as an option, not a revision.
r="$(new_repo dashrange)"
seed_into "$r" "$TOKEN"
printf 'clean\n' >"$r/doc.md"
git -C "$r" add doc.md config
git -C "$r" commit -qm 'chore: base commit'
out="$(cd "$r" && "$SCAN" --commit-range '--output=/dev/null' 2>&1)"
assert_exit "a commit range beginning with a dash is refused" 2 $?
assert_contains "the dash refusal says why" "may not begin with" "$out"

# ---------------------------------------------------------------------------
# Seed-file fail-closed posture (REQ-H1.3, REQ-B1.2). Each of these is a
# vacuous-input case that must exit non-zero rather than pass.
# ---------------------------------------------------------------------------

# bad_seed <label> <slug> <seed-file-content>
bad_seed() {
  r="$(new_repo "seed-$2")"
  printf 'clean tracked content\n' >"$r/doc.md"
  git -C "$r" add doc.md
  mkdir -p "$r/config"
  printf '%s' "$3" >"$r/config/purged-identifiers.seed"
  out="$(cd "$r" && "$SCAN" 2>&1)"
  assert_exit "fails closed: $1" 2 $?
  assert_contains "fails closed loudly: $1" "fails closed" "$out"
}

r="$(new_repo seed-missing)"
printf 'clean tracked content\n' >"$r/doc.md"
git -C "$r" add doc.md
out="$(cd "$r" && "$SCAN" 2>&1)"
assert_exit "fails closed: the seed file is missing" 2 $?
assert_contains "the missing-seed failure names the remedy" "seed-purged-identifiers.sh" "$out"

H1='1111111111111111111111111111111111111111111111111111111111111111'
H2='2222222222222222222222222222222222222222222222222222222222222222'

bad_seed "an empty seed file" empty ''
bad_seed "directives but zero hashes" zerohash 'min-seeds: 1
max-words: 2
'
bad_seed "a zero min-seeds floor" zerofloor "min-seeds: 0
max-words: 2
$H1
"
bad_seed "a hash count below the declared floor" belowfloor "min-seeds: 3
max-words: 2
$H1
$H2
"
bad_seed "a plaintext-shaped line" plaintext "min-seeds: 1
max-words: 2
$TOKEN
"
bad_seed "an uppercase hex hash" uppercase "min-seeds: 1
max-words: 2
1111111111111111111111111111111111111111111111111111111111111AAA
"
bad_seed "a truncated hash" short "min-seeds: 1
max-words: 2
1111
"
bad_seed "no min-seeds directive" nofloor "max-words: 2
$H1
"
bad_seed "no max-words directive" nowords "min-seeds: 1
$H1
"
bad_seed "a max-words above the window" wideword "min-seeds: 1
max-words: 9
$H1
"
bad_seed "a duplicated directive" dupe "min-seeds: 1
min-seeds: 2
max-words: 2
$H1
"

# ---------------------------------------------------------------------------
# The commit-msg hook screen (write time).
# ---------------------------------------------------------------------------

# wired_repo <name> — a fixture repo carrying this branch's githooks/ and the
# scanner beside them, wired the way scripts/wire-githooks.sh wires a clone.
wired_repo() {
  d="$(new_repo "$1")"
  mkdir -p "$d/scripts" "$d/config"
  cp -R "$REPO_ROOT/githooks" "$d/githooks"
  cp "$SCAN" "$d/scripts/"
  git -C "$d" config core.hooksPath githooks
  printf '%s' "$d"
}

r="$(wired_repo hook-reject)"
seed_into "$r" "$TOKEN"
printf 'content\n' >"$r/doc.md"
git -C "$r" add doc.md
out="$(git -C "$r" commit -m "chore: mention $TOKEN in the subject" 2>&1)"
rc=$?
assert_exit "the commit-msg hook rejects a message carrying a planted token" 1 $rc
assert_contains "the hook rejection carries its own marker" "planwright githooks" "$out"
assert_absent "the hook rejection withholds the matched text" "$TOKEN" "$out"
assert_absent "the hook rejection withholds the normalized form too" "$NORM" "$out"

r="$(wired_repo hook-body)"
seed_into "$r" "$TOKEN"
printf 'content\n' >"$r/doc.md"
git -C "$r" add doc.md
out="$(git -C "$r" commit -m 'chore: a clean subject' -m "but the body names $TOKEN" 2>&1)"
assert_exit "the hook screens the whole message, not just the subject" 1 $?

r="$(wired_repo hook-accept)"
seed_into "$r" "$TOKEN"
printf 'content\n' >"$r/doc.md"
git -C "$r" add doc.md
out="$(git -C "$r" commit -m 'chore: a clean subject and body' 2>&1)"
assert_exit "the hook lets a clean message through" 0 $?

# A comment line is NOT exempt. git strips comments only when the message goes
# through an editor; with -F or -m the cleanup mode is "whitespace", which
# keeps them, so a hash line in a -F commit is permanent history like any
# other. Screening it is what stops the guard from blanking the very text git
# is about to publish.
r="$(wired_repo hook-comment)"
seed_into "$r" "$TOKEN"
printf 'content\n' >"$r/doc.md"
git -C "$r" add doc.md
msg="$r/msg.txt"
printf 'chore: a clean subject\n\n# a comment naming %s\n' "$TOKEN" >"$msg"
out="$(git -C "$r" commit -F "$msg" 2>&1)"
assert_exit "a comment line naming the token is screened, since -F keeps it" 1 $?

# Proof of the premise the case above rests on: git really does keep it.
r="$(wired_repo hook-comment-kept)"
seed_into "$r" "$TOKEN2"
printf 'content\n' >"$r/doc.md"
git -C "$r" add doc.md
msg="$r/msg.txt"
printf 'chore: a clean subject\n\n# an ordinary comment\n' >"$msg"
git -C "$r" commit -q -F "$msg" >/dev/null 2>&1
assert_contains "git keeps a '#' line in a -F commit, so screening it is right" \
  "# an ordinary comment" "$(git -C "$r" log -1 --format=%B)"

r="$(wired_repo hook-scissors)"
seed_into "$r" "$TOKEN"
printf 'content\n' >"$r/doc.md"
git -C "$r" add doc.md
msg="$r/msg.txt"
{
  printf 'chore: a clean subject\n\n'
  printf '# ------------------------ >8 ------------------------\n'
  printf 'diff --git a/doc.md b/doc.md\n-old line naming %s\n' "$TOKEN"
} >"$msg"
out="$(git -C "$r" commit --cleanup=scissors -F "$msg" 2>&1)"
assert_exit "a --verbose scissors diff naming the token does not refuse the commit" 0 $?

# A comment line is screened whatever character opens it: none of them are
# exempt, because git keeps them all in a -F commit.
r="$(wired_repo hook-commentchar)"
seed_into "$r" "$TOKEN"
git -C "$r" config core.commentChar ';'
printf 'content\n' >"$r/doc.md"
git -C "$r" add doc.md
msg="$r/msg.txt"
printf 'chore: a clean subject\n\n; %s\n' "$TOKEN" >"$msg"
out="$(git -C "$r" commit -F "$msg" 2>&1)"
assert_exit "a comment line is screened whatever character opens it" 1 $?

# What core.commentChar DOES still govern is the scissors marker, since git
# writes it with the configured character. Miss that and a --verbose
# remediation commit gets refused for the diff it is removing.
r="$(wired_repo hook-scissors-char)"
seed_into "$r" "$TOKEN"
git -C "$r" config core.commentChar ';'
printf 'content\n' >"$r/doc.md"
git -C "$r" add doc.md
msg="$r/msg.txt"
{
  printf 'chore: a clean subject\n\n'
  printf '; ------------------------ >8 ------------------------\n'
  printf 'diff --git a/doc.md b/doc.md\n-old line naming %s\n' "$TOKEN"
} >"$msg"
out="$(git -C "$r" commit --cleanup=scissors -F "$msg" 2>&1)"
assert_exit "a scissors marker written with the configured character truncates" 0 $?

# A regex-metacharacter comment char must be matched literally, not compiled.
r="$(wired_repo hook-commentchar-meta)"
seed_into "$r" "$TOKEN"
git -C "$r" config core.commentChar '$'
printf 'content\n' >"$r/doc.md"
git -C "$r" add doc.md
msg="$r/msg.txt"
{
  printf 'chore: a clean subject\n\n'
  printf '$ ------------------------ >8 ------------------------\n'
  printf 'diff --git a/doc.md b/doc.md\n-old line naming %s\n' "$TOKEN"
} >"$msg"
out="$(git -C "$r" commit --cleanup=scissors -F "$msg" 2>&1)"
assert_exit "a regex-metacharacter comment character is matched literally" 0 $?

# A wired clone that can write history but cannot screen it is the hole the
# hook closes, so an unreachable scanner is a refusal, not a skip.
r="$(wired_repo hook-noscanner)"
seed_into "$r" "$TOKEN"
rm -f "$r/scripts/check-purged-identifiers.sh"
printf 'content\n' >"$r/doc.md"
git -C "$r" add doc.md
out="$(git -C "$r" commit -m 'chore: a clean subject' 2>&1)"
assert_exit "the hook fails closed when the scanner is unreachable" 1 $?
assert_contains "the unreachable-scanner refusal says why" "failing closed" "$out"

r="$(wired_repo hook-noseed)"
printf 'content\n' >"$r/doc.md"
git -C "$r" add doc.md
out="$(git -C "$r" commit -m 'chore: a clean subject' 2>&1)"
assert_exit "the hook fails closed when the seed file is unreachable" 1 $?
# The scanner separates a match (exit 1) from a guard that could not run
# (exit 2), and the hook has to keep them apart: telling an author to reword a
# perfectly clean message because the SEED file is missing sends them to fix
# the one thing that is not broken.
assert_contains "an unrunnable guard is reported as a setup problem" "setup problem" "$out"
assert_absent "an unrunnable guard does not tell the author to reword" "reword" "$out"

# The Task 2 screen this hook extends still fires, and still first.
r="$(wired_repo hook-squash)"
seed_into "$r" "$TOKEN"
printf 'content\n' >"$r/doc.md"
git -C "$r" add doc.md
out="$(git -C "$r" commit -m 'fixup! chore: something' 2>&1)"
assert_exit "the Task 2 autosquash-subject screen still rejects" 1 $?
assert_contains "the autosquash rejection is the one reported" "refusing 'fixup!' subject" "$out"

# ---------------------------------------------------------------------------
# The CI-side commit-range scan (unwired clones, --no-verify, fork PRs).
# ---------------------------------------------------------------------------

# An UNWIRED repo: this is precisely the clone the hook never runs in.
r="$(new_repo range)"
seed_into "$r" "$TOKEN"
printf 'base\n' >"$r/doc.md"
git -C "$r" add doc.md config
git -C "$r" commit -qm 'chore: base commit'
base="$(git -C "$r" rev-parse HEAD)"
printf 'more\n' >>"$r/doc.md"
git -C "$r" commit -qam 'chore: a clean subject'
printf 'more still\n' >>"$r/doc.md"
git -C "$r" commit -qam "chore: a clean subject" -m "body naming $TOKEN"
head="$(git -C "$r" rev-parse HEAD)"

out="$(cd "$r" && "$SCAN" --commit-range "$base..$head" 2>&1)"
rc=$?
assert_exit "the range scan catches a planted token in a commit body" 1 $rc
assert_contains "the range report names the commit" "commit ${head:0:12}" "$out"
assert_absent "the range report withholds the matched text" "$TOKEN" "$out"
assert_absent "the range report withholds the normalized form too" "$NORM" "$out"

out="$(cd "$r" && "$SCAN" --commit-range "$base..$base~0" 2>&1)"
assert_exit "an empty commit range fails closed" 2 $?
assert_contains "the empty-range failure says so" "0 commits" "$out"

out="$(cd "$r" && "$SCAN" --commit-range 'no-such-ref..HEAD' 2>&1)"
assert_exit "an unresolvable commit range is a usage error" 2 $?

r="$(new_repo range-clean)"
seed_into "$r" "$TOKEN"
printf 'base\n' >"$r/doc.md"
git -C "$r" add doc.md config
git -C "$r" commit -qm 'chore: base commit'
base="$(git -C "$r" rev-parse HEAD)"
printf 'more\n' >>"$r/doc.md"
git -C "$r" commit -qam 'chore: a clean subject'
out="$(cd "$r" && "$SCAN" --commit-range "$base..HEAD" 2>&1)"
assert_exit "a clean commit range passes" 0 $?
assert_contains "the clean range reports what it screened" "commit message(s) screened" "$out"

# ---------------------------------------------------------------------------
# --message-file mode directly, including its own vacuous input.
# ---------------------------------------------------------------------------

r="$(new_repo msgfile)"
seed_into "$r" "$TOKEN"
printf 'chore: subject naming %s\n' "$TOKEN" >"$TMP/msg-dirty"
printf 'chore: a clean subject\n' >"$TMP/msg-clean"
: >"$TMP/msg-empty"

(cd "$r" && "$SCAN" --message-file "$TMP/msg-dirty" >/dev/null 2>&1)
assert_exit "--message-file catches a planted token" 1 $?
(cd "$r" && "$SCAN" --message-file "$TMP/msg-clean" >/dev/null 2>&1)
assert_exit "--message-file passes a clean message" 0 $?
(cd "$r" && "$SCAN" --message-file "$TMP/msg-empty" >/dev/null 2>&1)
assert_exit "an empty message fails closed" 2 $?
(cd "$r" && "$SCAN" --message-file "$TMP/does-not-exist" >/dev/null 2>&1)
assert_exit "a missing message file fails closed" 2 $?

# ---------------------------------------------------------------------------
# Usage.
# ---------------------------------------------------------------------------

r="$(new_repo usage)"
seed_into "$r" "$TOKEN"
printf 'clean\n' >"$r/doc.md"
git -C "$r" add doc.md

(cd "$r" && "$SCAN" --nonsense >/dev/null 2>&1)
assert_exit "an unknown flag is a usage error" 2 $?
(cd "$r" && "$SCAN" --message-file "$TMP/msg-clean" --commit-range HEAD >/dev/null 2>&1)
assert_exit "combining the two message modes is a usage error" 2 $?
(cd "$r" && "$SCAN" --seed-file >/dev/null 2>&1)
assert_exit "a flag with no value is a usage error" 2 $?

# ---------------------------------------------------------------------------
# The provisioning path (REQ-B1.2): stdin only, never argv, never echoed.
# ---------------------------------------------------------------------------

r="$(new_repo seeder)"
mkdir -p "$r/config"
out="$(printf '%s\n%s\n' "$TOKEN" "$TOKEN2" | (cd "$r" && "$SEEDER" 2>&1))"
assert_exit "the seeder writes from stdin" 0 $?
assert_absent "the seeder never echoes the plaintext" "$TOKEN" "$out"
assert_absent "the seeder never echoes the normalized form" "$NORM" "$out"
assert_contains "the seeder reports the count it wrote" "2 seed hash(es)" "$out"
seedfile="$r/config/purged-identifiers.seed"
written="$(cat "$seedfile")"
assert_absent "the written seed file holds no plaintext" "$TOKEN" "$written"
assert_absent "the written seed file holds no normalized form" "$NORM" "$written"
assert_contains "the written seed file declares its floor" "min-seeds: 2" "$written"
assert_contains "the written seed file declares its window" "max-words: 4" "$written"
stray="$(grep -cv -e '^#' -e '^$' -e '^min-seeds: [0-9]\{1,4\}$' -e '^max-words: [0-9]\{1,2\}$' -e '^[0-9a-f]\{64\}$' "$seedfile")"
assert_exit "every written seed line is a comment, a directive, or a bare hash" 0 "$stray"

out="$(printf '%s\n' "$TOKEN" | (cd "$r" && "$SEEDER" "$TOKEN" 2>&1))"
assert_exit "the seeder refuses an identifier passed as an argument" 2 $?
assert_contains "the argv refusal explains the stdin-only rule" "never from arguments" "$out"

out="$(printf '' | (cd "$r" && "$SEEDER" --seed-file "$TMP/nope.seed" 2>&1))"
assert_exit "the seeder refuses to write an empty seed file" 2 $?
assert_absent "the empty-input refusal writes nothing" "nope.seed" "$(ls "$TMP")"

out="$(printf 'ab\n' | (cd "$r" && "$SEEDER" --seed-file "$TMP/short.seed" 2>&1))"
assert_exit "the seeder refuses a too-short identifier" 2 $?
assert_contains "the too-short refusal reports the POSITION, not the value" "stdin line 1" "$out"

out="$(printf '///\n' | (cd "$r" && "$SEEDER" --seed-file "$TMP/nonword.seed" 2>&1))"
assert_exit "the seeder refuses a line with nothing to normalize" 2 $?

# --add merges rather than replacing, and deduplicates.
r="$(new_repo seeder-add)"
mkdir -p "$r/config"
printf '%s\n' "$TOKEN" | (cd "$r" && "$SEEDER" >/dev/null 2>&1)
out="$(printf '%s\n%s\n' "$TOKEN" "$TOKEN2" | (cd "$r" && "$SEEDER" --add 2>&1))"
assert_exit "--add merges into the existing seeds" 0 $?
assert_contains "--add deduplicates the overlap" "2 seed hash(es)" "$out"
out="$(printf '%s\n' "$TOKEN" | (cd "$r" && "$SEEDER" --add --seed-file "$TMP/absent.seed" 2>&1))"
assert_exit "--add against a missing seed file is an error" 2 $?

# --add reads the existing file with EXACTLY the grammar the scanner enforces.
# A looser reader is how a guard goes quietly weak: carrying hashes forward
# under a narrower window than they were seeded with leaves them permanently
# unmatchable while the check still reports green.

# add_onto <slug> <existing-seed-body> — run --add over a planted seed file.
add_onto() {
  ar="$(new_repo "add-$1")"
  mkdir -p "$ar/config"
  printf '%s' "$2" >"$ar/config/purged-identifiers.seed"
  printf 'zzqsolo\n' | (cd "$ar" && "$SEEDER" --add 2>&1)
}

H3='3333333333333333333333333333333333333333333333333333333333333333'

out="$(add_onto nowords "min-seeds: 1
$H3
")"
assert_exit "--add refuses an existing file with no max-words directive" 2 $?
assert_contains "the no-max-words refusal says what is wrong" "max-words" "$out"

out="$(add_onto widewords "min-seeds: 1
max-words: 12
$H3
")"
assert_exit "--add refuses an out-of-range max-words rather than carrying it" 2 $?

out="$(add_onto dupewords "min-seeds: 1
max-words: 2
max-words: 1
$H3
")"
assert_exit "--add refuses a duplicated max-words directive" 2 $?

out="$(add_onto dupefloor "min-seeds: 1
min-seeds: 2
max-words: 2
$H3
")"
assert_exit "--add refuses a duplicated min-seeds directive" 2 $?

# The window must never narrow below what the carried hashes were seeded with.
r2="$(new_repo add-window)"
mkdir -p "$r2/config"
printf 'zzq alpha beta gamma\n' | (cd "$r2" && "$SEEDER" >/dev/null 2>&1)
printf 'zzqsolo\n' | (cd "$r2" && "$SEEDER" --add >/dev/null 2>&1)
assert_contains "--add never narrows the window below the carried seeds" "max-words: 4" \
  "$(cat "$r2/config/purged-identifiers.seed")"

# The seeder and the scanner must agree on normalization: a seed provisioned
# in one spelling is caught in every other. This is the contract that keeps
# the two sides from drifting apart.
r="$(new_repo roundtrip)"
mkdir -p "$r/config"
printf 'ZZQ Planted SeedToken\n' | (cd "$r" && "$SEEDER" >/dev/null 2>&1)
printf 'prose naming %s here\n' "$TOKEN" >"$r/doc.md"
git -C "$r" add doc.md config
(cd "$r" && "$SCAN" >/dev/null 2>&1)
assert_exit "a seed provisioned space-separated is caught hyphenated" 1 $?

# ---------------------------------------------------------------------------
# The committed seed file and the wiring (REQ-B1.2, and decidable wiring).
# ---------------------------------------------------------------------------

if [ ! -f "$REAL_SEED" ]; then
  echo "FAIL: the committed seed file $REAL_SEED is missing — the guard would fail closed on every run" >&2
  failures=$((failures + 1))
else
  real_min="$(sed -n 's/^min-seeds: \([0-9]\{1,4\}\)$/\1/p' "$REAL_SEED")"
  real_words="$(sed -n 's/^max-words: \([0-9]\{1,2\}\)$/\1/p' "$REAL_SEED")"
  real_count="$(grep -c '^[0-9a-f]\{64\}$' "$REAL_SEED")"
  stray="$(grep -cv -e '^#' -e '^$' -e '^min-seeds: [0-9]\{1,4\}$' -e '^max-words: [0-9]\{1,2\}$' -e '^[0-9a-f]\{64\}$' "$REAL_SEED")"

  if [ "$stray" -ne 0 ]; then
    echo "FAIL: the committed seed file has $stray line(s) that are neither a comment, a directive, nor a bare hash" >&2
    failures=$((failures + 1))
  else
    echo "ok: the committed seed file is hash-only (no line of plaintext shape)"
  fi
  if [ -z "$real_min" ] || [ "$real_min" -lt 1 ]; then
    echo "FAIL: the committed seed file declares no usable min-seeds floor" >&2
    failures=$((failures + 1))
  elif [ "$real_count" -lt "$real_min" ]; then
    echo "FAIL: the committed seed file holds $real_count hash(es), below its declared floor of $real_min" >&2
    failures=$((failures + 1))
  else
    echo "ok: the committed seed file meets its declared minimum-seed floor ($real_count >= $real_min)"
  fi
  if [ -z "$real_words" ] || [ "$real_words" -lt 1 ]; then
    echo "FAIL: the committed seed file declares no usable max-words window" >&2
    failures=$((failures + 1))
  else
    echo "ok: the committed seed file declares a candidate window"
  fi

  # The vacuously-green failure mode: a seed list made of this suite's own
  # test tokens would pass every scenario above and guard nothing real.
  planted="$(printf '%s\n%s\n' "$TOKEN" "$TOKEN2" \
    | perl -MDigest::SHA=sha256_hex -ne 'chomp; my @w = map { lc } (/([A-Za-z0-9]+)/g); print sha256_hex(join("", @w)), "\n"')"
  leaked=0
  for h in $planted; do
    if grep -qx "$h" "$REAL_SEED"; then leaked=1; fi
  done
  if [ "$leaked" -ne 0 ]; then
    echo "FAIL: the committed seed file contains this suite's test tokens — a test-only seed list guards nothing" >&2
    failures=$((failures + 1))
  else
    echo "ok: the committed seed file holds no test-only token"
  fi
fi

if grep -q '"check:purged-identifiers"' "$REPO_ROOT/mise.toml" \
  && grep -q '^  "check:purged-identifiers",$' "$REPO_ROOT/mise.toml"; then
  echo "ok: check:purged-identifiers is defined and a member of the check aggregate"
else
  echo "FAIL: check:purged-identifiers is not wired into the check aggregate in mise.toml" >&2
  failures=$((failures + 1))
fi

if grep -q 'check-purged-identifiers.sh --commit-range' "$REPO_ROOT/.github/workflows/ci.yml"; then
  echo "ok: ci.yml carries the commit-range scan"
else
  echo "FAIL: ci.yml does not run the commit-range scan — unwired clones and fork PRs stay uncovered" >&2
  failures=$((failures + 1))
fi

if grep -q 'check-purged-identifiers.sh' "$REPO_ROOT/githooks/commit-msg"; then
  echo "ok: githooks/commit-msg calls the scanner"
else
  echo "FAIL: githooks/commit-msg does not screen the message" >&2
  failures=$((failures + 1))
fi

# The repo's own tree must pass its own guard.
out="$(cd "$REPO_ROOT" && "$SCAN" 2>&1)"
assert_exit "the repo's own tracked tree passes the guard" 0 $?

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "all check-purged-identifiers tests passed"
