# Captured kickoff-brief entries

A file here is an amendment-log or sign-off entry copied verbatim from the
commit that landed it in a real bundle's `kickoff-brief.md`: captured output,
never a hand-authored golden. The test that uses a file pins its landing
commit and heading, re-derives the entry from that commit on every run, and
fails on any divergence, so editing a fixture in place is caught; the remedy
is to re-capture.

To capture or re-capture an entry, extract it from the landing commit's brief
rather than from a checkout, and let the test's pins name that commit:

```sh
git show <commit>:specs/<bundle>/kickoff-brief.md \
  | awk '/^### <entry heading> /{p=1; print; next} p && /^### /{exit} p' \
  > tests/fixtures/kickoff-entries/<bundle>-<entry>.md
```

`invariant-tasks-amendment-6.md` is used by
`tests/test-kickoff-verification-homes.sh`.
