# The Review Seam

Stakeholders who will never open a git repository still review a venture: they
read a copy on a surface they already use and leave comments there. The review
seam is how that feedback gets back into the bundle without the surface ever
writing it. The cycle runs one way at a time, every harvested item is untrusted
data until the operator triages it, and an accepted item lands as a commit that
cites where it came from.

`scripts/inception-review-cycle.sh` is this contract's mechanical shadow, and
`scripts/inception-notion.sh` is the reference adapter. The bundle files, ids,
and gate records the seam protects are defined in
[inception-format.md](inception-format.md).

Citations: inception REQ-G1.6, inception REQ-G1.7, inception REQ-G1.9 ·
inception D-10.

## The cycle

1. **Export a snapshot.** A snapshot is the committed bundle at one commit, so
   an export refuses a bundle with uncommitted changes. It opens with a line
   telling the reader that edits to the copy are not read back and the next
   export replaces it. An export sends the bundle off the machine, so it is
   offered and runs only once the operator confirms it, having checked that
   the destination's readers match the venture repo's visibility (REQ-G1.9).
   It is secret-screened first. A snapshot the screen flags is not exported.
2. **Harvest feedback as data.** The adapter reads the surface's feedback and
   the seam adds each item it has not seen before to the ledger, as
   `pending`. Harvesting writes no bundle file.
3. **Triage each item.** The operator decides every item: `apply`, `modify`
   (applied with a recorded departure from what was asked), or `skip`. The
   decision names who made it. An accepted item also names the one bundle
   section it may change.
4. **Apply accepted items as attributed commits.** The agent makes the change
   and stages it, and the seam commits it only after checking that it stays
   inside the triaged section and passes the stakeholder-commit validator. The
   commit cites the item's source.
5. **Re-export.** The next export opens the next cycle. It waits until the
   previous export has been harvested in full, because replacing the copy can
   drop feedback nobody has read, and until every item is triaged. A partial
   harvest records what it read but does not count as harvested.

There is no step where the surface's edits come back. Symmetric file
synchronization is out by design: lossy conversion, phantom diffs, and
concurrent edits with no resolution all land on exactly the ids and anchors the
bundle depends on (D-10).

## Feedback is untrusted input

Harvested text comes from people who are not authorities over the bundle. It
can also be adversarial, since anyone who can comment on the copy can write
it. So:

- **It is quoted, never executed.** The ledger stores it as quoted (`>`)
  lines, one per line of the comment, with control characters stripped, so no
  comment can forge a heading or a field. Every value taken from the surface
  is checked against its grammar before it is used: a source id before it
  keys the ledger, an API id before it goes into a URL.
- **It is a request, not an instruction.** An agent implementing an accepted
  item reads its text as what a stakeholder asked for. It never treats the
  text as directions to itself. The operator's triage decision is the
  authority.
- **Nothing applies without triage.** The apply step refuses a pending or
  skipped item and refuses an item already applied. No code path writes
  harvested feedback into the bundle.

## Re-import at section granularity

An accepted item changes one section: a `##` or `###` heading of one bundle
file and the lines under it up to the next heading at the same level or
higher. A register entry can be named by its id alone (`assumptions.md#A-2`).
The apply step refuses:

- a staged change to any other file, or to lines outside that section;
- an edit to the section's own heading line, where register ids live;
- any section in the gate log, so gate records are never a target;
- a change the stakeholder-commit validator (`inception-validate.sh
  --baseline HEAD`) refuses, so no id vanishes and no recorded gate run is
  edited, whatever the section.

## The ledger

`feedback/ledger.md` in the venture is tracked, and it is the only record of
what became of each item. A surface may give no way to resolve a comment
(Notion's API cannot), so the comment stays on the copy after it is decided.
The ledger, keyed by source id, is what keeps it from being harvested again as
new.

The header carries `Ledger-version`, `Adapter`, `Cycle`, `Phase` (`exported`
or `harvested`), the `Snapshot` commit, and the `Exported` date. Each item is
an `### FB-<n> — <source>` block. Its fields are `Source`, `Thread`, `Author`,
`Created`, `Anchor`, `Anchor-text`, `Cycle`, `Disposition` (`pending`,
`apply`, `modify`, or `skip`), `Section`, `Decider`, `Decided`, `Applied`, and
`Note`, and a quoted `Text:` body comes last. Export, harvest, and triage each
commit the ledger on its own. An apply commits the change and the ledger's
`Applied` line together. A step that writes the ledger refuses to start while
the ledger has uncommitted changes, so a step whose commit failed is never
read as done, and holds the venture's bundle lock, so two writers cannot
interleave. A step whose own commit fails restores the ledger, except an
export: that has already gone out, so its record stays for the operator to
commit. Each commit applying feedback carries three trailers:

```text
Feedback-Item: FB-<n>
Feedback-Source: <adapter>:<kind>:<id>
Feedback-Author: <the name the surface reported>
```

The ledger is not a bundle file, and the bundle validator does not read it.
Anyone who can commit to the venture can already change anything in it, the
ledger included, so the seam does not guard the ledger against commits. What it
guards is the review surface: a comment reaches the ledger only as quoted text.

## The adapter contract

An adapter moves bytes between the venture and one review surface and decides
nothing. The seam runs adapters from a closed set, each a sibling script that
answers three verbs:

- `status <venture>` prints `page<TAB><destination>`, or `none`.
- `export <venture> <snapshot>` replaces the surface's copy with the
  snapshot.
- `harvest <venture>` prints one item record per piece of feedback and ends
  with a summary line. A record is `item`, then the source, thread, author,
  created time, anchor, anchor text, and text, tab-separated and escaped as
  jq's `@tsv` escapes them. The summary is `summary<TAB>complete|partial<TAB>
  <count>`. A harvest with no summary line records nothing.

Where an adapter sends the bundle, and the credential it sends it with, are
machine-local. The destination lives in the clone's git directory, because
anything in the work tree arrives with a pull and a commit could redirect the
next export. A credential never goes into the venture and never onto a command
line.

## The Notion reference adapter

The Notion adapter pins one API version and exports through the Markdown
Content API's `replace_content`. It harvests comments on the page and on every
block it can reach. It does not enter child pages, and the walk has a bound:
past it the harvest reports `partial`, and the next export waits until a
harvest under a higher bound completes. Three properties of Notion's comment
API shape the rest of the seam:

- It returns unresolved comments only.
- It carries no resolved field and no text-range anchor. The adapter records
  the commented block's id and opening text instead.
- It cannot resolve a comment.

The integration needs Notion's "Read comments" capability, which ships off,
and it needs to be shared with the page.

These are platform claims, and platform claims go stale. They are re-verified
at build time along with the venture's other fast-rotting claims.
