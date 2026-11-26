#!/bin/bash
# Tests for the purged-identifier guard's tree scan,
# scripts/check-purged-identifiers.sh (REQ-B1.1, REQ-H1.3).
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
#     reach by design, while tracked paths and symlink targets are in it;
#   - a tree with nothing scannable in it fails CLOSED per REQ-H1.3.
#
# The message screens and the seeds and wiring are the -hook and -seeds
# siblings of this file, all sharing tests/lib/purged-identifiers-harness.sh.
# The scan of this repository's own tree is `check:purged-identifiers`, not a
# test: it hashes every word window of every tracked file, the costliest run
# by far, and the check already requires it to pass.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
unset CDPATH
# shellcheck source=tests/lib/purged-identifiers-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/purged-identifiers-harness.sh" || exit 1

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

# in_scope <label> <slug> <line> — the line must be caught.
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

finish check-purged-identifiers
