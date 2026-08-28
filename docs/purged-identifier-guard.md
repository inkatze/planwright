# The purged-identifier guard

Some identifiers — a former work-repository name, a personal handle — were
removed from this repository's history deliberately. `scan:secrets` cannot help
keep them out: a repository name is not a credential pattern, so gitleaks has
nothing to match on. Before this guard existed, a re-leak was caught only when a
reviewer happened to notice one, and at least once that is exactly what
happened.

This page is the reference for the guard that replaced that vigilance: what it
normalizes, which reintroduction shapes it catches, which it deliberately does
not, and how the plaintext gets provisioned without ever being written down.

## The three surfaces it covers

| Surface | Where it runs | Invocation |
| --- | --- | --- |
| The tracked tree | `mise run check`, and so every CI run | `check:purged-identifiers` |
| A commit message, at write time | `githooks/commit-msg`, on every commit in a wired clone | `check-purged-identifiers.sh --message-file` |
| Every commit message in a PR | GitHub Actions, on `pull_request` | `check-purged-identifiers.sh --commit-range` |

The tree scan is the primary guard. The message screens exist because a commit
message is not part of the tracked tree yet is published just as permanently;
the hook catches it at write time, and the CI range scan backs the hook up for
the clones it never runs in — an unwired clone, a `--no-verify` commit, or a
fork PR whose author never wired anything.

## What is committed

`config/purged-identifiers.seed` holds SHA-256 hashes and two directives, and
nothing else:

```text
min-seeds: <count>
max-words: <n>
<64 lowercase hex characters>
...
```

No plaintext is recorded anywhere in the repository. Anything in that file that
is not a comment, one of the two directives, or a bare 64-character lowercase
hex hash is a malformed seed file, which is how the format rules out a
plaintext line rather than merely discouraging one.

`min-seeds` is the non-vacuity floor: the scanner fails closed when the hash
count drops below it. Deleting seed lines therefore cannot quietly disarm the
guard — lowering the floor to match is possible, but it is a visible diff on a
tracked file, which is the honest limit of what a committed floor can promise.

`max-words` is the word count of the widest seeded identifier, and it bounds
the scanner's candidate window (below). The seeding path derives it from what
it ingested, so a generated file always spans its own seeds. Nothing re-derives
it at scan time, though: hand-lowering it would narrow the window past a
multi-word seed while the guard still reported green — the same honest limit
`min-seeds` has, and the same reason the seed file is generated rather than
edited.

**Accepted residual (D-5).** The purged identifiers are low-entropy names, so
their hashes are offline-guessable by anyone motivated to guess the names
themselves. The guard's threat model is accidental reintroduction, not
adversarial secrecy, and that residual is accepted rather than papered over.

## Normalization

Both sides — the seeding path and the scanner — apply exactly the same rule,
and that identity is the contract between them:

1. Split the text into **words**: maximal runs of `[A-Za-z0-9]`. Every other
   byte is a separator and carries no other meaning, so `-`, `_`, `.`, `/`,
   `@`, `:` and whitespace are all equivalent.
2. Lowercase each word.
3. Concatenate, with no separator between words.

A seed is normalized once, at provisioning time, into a single string. The
scanner builds **candidates** from scanned text by concatenating every run of
1 to `max-words` consecutive words on a line, and a candidate matches only on
full equality of the normalized forms — never on a substring.

## In scope

Given a purged identifier that normalizes to `acmeinternal`, all of these are
caught:

| Shape | Example |
| --- | --- |
| Exact | `acme-internal` |
| Any casing | `Acme-Internal`, `ACME-INTERNAL` |
| Any separator | `acme_internal`, `acme.internal`, `acme/internal` |
| No separator | `acmeinternal` |
| Space-separated | `acme internal` |
| Inside a URL | `https://example.com/acme-internal/tree/main` |
| Inside a `mailto:` | `mailto:someone@acme-internal.example` |
| Inside a longer slug | `my-acme-internal-notes` |
| Inside a path | `../acme_internal/README.md` |
| A tracked file or directory name | `docs/acme-internal/notes.md`, even with clean contents |
| A symlink target | `ln -s acme-internal link`, whose target string git stores as the link content |

The URL, `mailto:` and slug cases are not special-cased. They fall out of rule
1: those punctuation marks are word separators like any other, so the
identifier still appears as a complete run of consecutive words.

The last two rows are why the scan reads more than file contents. A path is
tracked data: git records it as permanently as any line of prose, and
REQ-B1.1 asks the guard to fire when an identifier reappears anywhere in the
tracked tree. A symlink is the same point in a sharper form, since git stores
the target path *as* the link content, so the string is tracked bytes even
though the file behind it is not the repository's to read. Names are therefore
screened for every tracked entry, including entries whose contents are skipped
as binary.

## Out of scope

These deliberately pass, and fixtures pin each one so the boundary cannot drift
in either direction:

| Shape | Example | Why |
| --- | --- | --- |
| No word boundary before the identifier | `xacme-internal` | Normalizes to `xacmeinternal`, a different string |
| No word boundary after it | `acme-internals` | Normalizes to `acmeinternals` |
| A proper part of the identifier | `acme` alone | The guard seeds whole identifiers, not their fragments |
| Split across a line break | `acme-`↵`internal` | Candidates are built per line |
| A typo or an altered spelling | `acme-internl` | Not a normalization variant; nothing short of fuzzy matching would catch it, and fuzzy matching overblocks |
| Non-ASCII lookalikes | `аcme-internal` (Cyrillic `а`) | Words are ASCII alphanumeric runs |
| A binary file's contents | a NUL byte in the first 8 KiB | No line-oriented text to normalize; the probe is bounded so a large file is never read whole. Its tracked *name* is still screened |
| Untracked or ignored files | a scratch file, `.gitignore`d output | `git ls-files` is the tracked-tree definition REQ-B1.1 names |
| The contents of a symlink's target | a tracked link pointing outside the repository | The link is never followed; reading the file behind it would scan content the repository does not own. The target *string* is screened |

The first three are the load-bearing ones: the guard trades a class of
near-miss reintroductions for never firing on unrelated text that merely
contains the identifier as a fragment. An overblocking guard gets disabled; a
guard that catches every casual reformatting and no innocent prose gets kept.

## Provisioning the plaintext

The identifiers are supplied by a human, out of band, and hashed on the way in:

```bash
scripts/seed-purged-identifiers.sh          # type one per line, then Ctrl-D
scripts/seed-purged-identifiers.sh --add    # merge into the existing seeds
```

The script reads **stdin only**. It never accepts an identifier as an argument
(argv is visible in `ps` and in shell history), never echoes what it read, and
reports a rejected line by its position rather than its content. It writes the
seed file through a temporary file and a rename, so an interrupted run cannot
leave behind a truncated list.

Two inputs are refused: a line that normalizes to fewer than four characters
(it would match common word runs everywhere and turn the guard into noise) and
one longer than eight words (beyond the scanner's candidate window).

Commit the resulting seed file. The plaintext stays with the operator.

## Failure modes

Every one of these exits non-zero rather than passing vacuously, per the
fail-closed posture REQ-H1.3 sets for every guard this repository ships:

- the seed file is missing, unreadable, empty, or holds zero hashes;
- either directive is missing or duplicated, `min-seeds` is `0`, or
  `max-words` is outside 1–8;
- the hash count is below the declared `min-seeds`;
- any line is neither a comment, a directive, nor a bare hash;
- the tracked tree enumerates zero scannable files, a commit range yields zero
  commits, or a screened commit message is empty;
- `perl` or `Digest::SHA` is unavailable, or the command runs outside a git
  work tree.

The hook adds one more: if the scanner or its seed file is unreachable, the
commit is refused. A wired clone that can write history but cannot screen it is
the hole the hook exists to close. `--no-verify` remains the human's deliberate
escape hatch, and the CI range scan is what makes using it visible.

## When a match fires

The report is a location and nothing else:

```text
check-purged-identifiers: docs/example.md:42: a purged identifier reappears (matched text withheld)
check-purged-identifiers: docs/[redacted]-[redacted]/notes.md: a purged identifier reappears in the tracked path (matched text withheld)
check-purged-identifiers: link.txt: a purged identifier reappears in the symlink target (matched text withheld)
```

The matched text is never printed. A guard that echoed its match would publish
the identifier into a CI log instead of into the tree, which is not an
improvement. Open the reported line to see what it found.

A path match is the one case where the location *is* the matched text, so the
path cannot be echoed raw. Every word run that took part in the match is
replaced with `[redacted]` and the rest of the path is left intact, which keeps
the report actionable — the surviving directory and extension are enough to
find the entry — without reproducing the identifier. Rename the entry rather
than opening it; for a symlink, the target string is what carries the match, so
the link itself is what needs repointing.

Filenames and commit ranges reaching this guard are contributor-controlled, so
they are treated as data: a filename is stripped of non-printable bytes before
it is echoed, and a commit range beginning with `-` is refused rather than
handed to git as an option.

The fix is to remove the reintroduction. Widening the normalization or
trimming the seed list to make the check pass defeats the guard; if a match is
genuinely a false positive, that is a finding about the normalization rules on
this page, and it belongs in review rather than in a local edit that turns the
check green.

## Related

- Design decision D-5 and requirements REQ-B1.1, REQ-B1.2, REQ-H1.3 in
  `specs/guard-coverage/`.
- The hook backstop this screen extends: [CONTRIBUTING.md](CONTRIBUTING.md).
- Fixtures pinning every shape table above:
  `tests/test-check-purged-identifiers.sh`.
