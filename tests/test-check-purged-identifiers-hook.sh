#!/bin/bash
# Tests for the purged-identifier guard's message screens (REQ-B1.1,
# REQ-H1.3): a commit message carrying a planted token is rejected by BOTH
# githooks/commit-msg (wired clones) and the CI-side --commit-range scan
# (unwired clones, --no-verify commits, fork PRs), the report withholding the
# match, while a --verbose scissors diff is screened out first so a
# remediation commit is not refused for the diff it removes. The hook fails
# closed without its scanner or seed, and an empty range or message fails
# closed. Sibling suites share tests/lib/purged-identifiers-harness.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
unset CDPATH
# shellcheck source=tests/lib/purged-identifiers-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/purged-identifiers-harness.sh" || exit 1

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

# A seed file predating min-max-words is fatal to the tree and range scans but
# NOT to the write-time screen. Making it fatal there too would wedge every
# commit in a wired clone -- including the commit that lands the re-seed --
# while protecting nothing, since token screening is hash comparison and the
# window floor does not enter into it. Hook best-effort, CI authoritative.
legacy_seed_repo() {
  lr="$(wired_repo "$1")"
  seed_into "$lr" "$TOKEN"
  grep -v '^min-max-words' "$lr/config/purged-identifiers.seed" >"$lr/config/tmp.seed"
  mv "$lr/config/tmp.seed" "$lr/config/purged-identifiers.seed"
  printf '%s' "$lr"
}

r="$(legacy_seed_repo hook-legacy-clean)"
printf 'content\n' >"$r/doc.md"
git -C "$r" add doc.md
out="$(git -C "$r" commit -m 'chore: a perfectly clean subject' 2>&1)"
assert_exit "a seed predating min-max-words does not wedge commits" 0 $?

r="$(legacy_seed_repo hook-legacy-token)"
printf 'content\n' >"$r/doc.md"
git -C "$r" add doc.md
out="$(git -C "$r" commit -m "chore: mentions $TOKEN here" 2>&1)"
assert_exit "screening is not weakened by the tolerated absence" 1 $?
assert_absent "the legacy-seed rejection still withholds the matched text" "$TOKEN" "$out"

# Present-but-violated is enforced everywhere, including the hook. Only the
# ABSENCE is tolerated, and only on this surface.
r="$(wired_repo hook-narrowed)"
seed_into "$r" "$TOKEN"
sed 's/^max-words: .*/max-words: 1/' "$r/config/purged-identifiers.seed" >"$r/config/tmp.seed"
mv "$r/config/tmp.seed" "$r/config/purged-identifiers.seed"
printf 'content\n' >"$r/doc.md"
git -C "$r" add doc.md
out="$(git -C "$r" commit -m 'chore: a perfectly clean subject' 2>&1)"
assert_exit "a narrowed window is refused at write time too" 1 $?

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

finish check-purged-identifiers-hook
