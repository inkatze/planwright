# Research Rigor

The model's memory of an ecosystem is a snapshot that ages; the code it
writes against that memory does not warn when the snapshot is stale.
Research Rigor defines when an agent must stop and consult current sources,
which sources count, and where the findings go. It is wired into
`/execute-task` (pre-implementation triggers) and `/spec-draft` (design-phase
research), and the resolution ladder in
[finding-categorization.md](finding-categorization.md) invokes it as its
second rung.

Citations: REQ-D1.5.

## Triggers

Research fires before implementation when any of these hold:

- **New dependency.** Adopting a library, service, or tool the project does
  not already use (pair with the engineering doctrine's dependency-adoption
  checklist).
- **Unfamiliar domain.** The task crosses into a domain the project has no
  established pattern for.
- **Security-touching pattern.** The change involves a pattern with known
  security pitfalls: input parsing, crypto, authn/z, subprocess construction,
  deserialization (see [security-posture.md](security-posture.md)).
- **Version-sensitive API use.** The correctness of the code depends on the
  specific version of a library, runtime, or external API.
- **Mature-project comparison.** No clean best practice is apparent and the
  question becomes "how do mature projects solve this".

## Source hierarchy

Consult in this order, descending in authority:

1. **Official documentation** for the exact version in use.
2. **The library's own source and tests.** What the code actually does
   outranks what secondary sources say it does; the library's tests are its
   most honest usage examples.
3. **Issue trackers and RFCs.** Known bugs, design intent, edge-case
   discussions.
4. **Community posts.** Blog posts and Q&A threads, last in the hierarchy:
   useful for leads, never authoritative alone.

## Recency discipline

Current documentation outranks model memory. When the model's recollection
of an API, default, or best practice conflicts with what the current docs
say, the docs win. Version-sensitive claims are verified against the version
the project actually pins, not the version the model remembers best.

## Antipattern check

Before adopting a pattern found during research, check for it being a known
antipattern: deprecation notices, "don't do this" sections in the official
docs, issues describing why the approach was abandoned, a replacement API
that exists specifically to supersede it. A pattern that was idiomatic when
the model's memory formed may be the documented mistake of the current
version.

## Recording

Research findings, including the tradeoffs weighed (performance, security,
system-wide implications) and the sources consulted, are recorded in the
kickoff brief's risk register, appended, never overwriting existing entries.
The record is what lets the next session, or the human at PR review, see why
the implementation went the way it did without re-running the research.

## Proportionality

Research depth scales with stake and reversibility (see
[proportionality.md](proportionality.md)). The triggers above are the floor,
not the ceiling: a high-stake or hard-to-reverse change deserves deeper
consultation down the source hierarchy even when only one trigger fires,
while a low-stake reversible change may stop at the official docs. A skill
that scopes research depth declares the scoping explicitly; skipping a fired
trigger silently is non-conforming.
