# Captured kickoff-brief entries

A file here is an amendment-log or sign-off entry copied verbatim from the
commit that landed it in a real bundle's `kickoff-brief.md`: captured output,
never a hand-authored golden. The test that uses a file pins its landing
commit and heading, re-derives the entry from that commit on every run, and
fails on any divergence, so editing a fixture in place is caught; the remedy
is to re-capture.

To capture or re-capture an entry, extract it from the landing commit's brief
rather than from a checkout. The heading is matched as a literal prefix, never
as a pattern: real headings carry parentheses and dashes that a regular
expression reads as operators and then silently matches nothing. The prefix
ends in a space so that `Amendment 6 ` cannot match `Amendment 60`. The entry
runs to the next heading at its level or above, or to the end of the brief.
Write to a temporary file and move it into place only when it is non-empty,
so a mistyped prefix cannot overwrite a good fixture with an empty one:

```sh
tmp=$(mktemp) &&
  git show <commit>:specs/<bundle>/kickoff-brief.md |
  awk -v h='### <heading prefix> ' '
    index($0, h) == 1 { if (p) exit; p = 1; print; next }
    p && /^#(#|##)? / { exit }
    p
  ' >"$tmp" &&
  [ -s "$tmp" ] &&
  mv "$tmp" tests/fixtures/kickoff-entries/<bundle>-<entry>.md
```

Then point the test's pins (the landing commit, the bundle, and the heading
prefix it names near the top) at what was captured; the commit must stay
reachable from the default branch, since the test reads it on every run.

One more way a recompute section can go red without the fixture having been
edited: a change to what `scripts/spec-anchor.sh` hashes moves every bundle's
anchor, so an entry recorded before the change no longer recomputes clean.
The remedy there is capturing an entry recorded after the change, not editing
the fixture.

`invariant-tasks-amendment-6.md` is used by
`tests/test-kickoff-verification-homes.sh`.
