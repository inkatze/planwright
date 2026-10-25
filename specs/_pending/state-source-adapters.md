# Seed brief for `state-source-adapters` (a follow-on bundle of `mission-control`)

Suggested invocation (fresh Claude session in the planwright repo, this file is the seed):

    /spec-draft state-source-adapters

Read this whole brief before eliciting. Run fold-detection against `mission-control` (owner of the
snapshot seam and the shipped forge adapter) before assuming a new bundle; this brief does not
prejudge extend-vs-spin-new.

## Why this is a follow-on, not part of `mission-control`

At the mission-control kickoff (section 5) the operator doubted that tracker adapters are feasible
short term. The core therefore fixed the seam, shipped only the forge adapter, and made `cited` the
honest day-one mode for every other source; adapters for trackers, document stores and design
tools became this fifth follow-on (mission-control D-12, D-22, D-27; brief risk rows 3 and 4).

## The shape (from the mission-control kickoff)

One **adapter per source**, each implementing the snapshot adapter contract of D-12: refresh one
age-stamped snapshot per program per cadence, the cadence and tracked set as knobs per source,
backing off on rate-limit headroom. Snapshots are runtime state and live under the plugin data home,
not the program home (D-8). D-12's own text still says "into the program home"; D-8, amended later
at sign-off, names the source snapshots as runtime state, so read D-8 as governing. Every duty reads
the snapshot; none polls the source itself (REQ-M1.1). Once an adapter exists, a program's source
map can move a fact class from `cited` to `snapshot` (REQ-H1.4).

Named candidates: **Jira** and **Notion** (in use in the program that seeded mission control) and
**Figma** (by category, for the `designs` fact class). A calendar adapter is what deadline-watch's
calendar reads wait on (D-27).

Each adapter's own decisions belong to this bundle, per source:

- **Authentication and token storage**: the program home never holds a credential (mission-control
  D-8), so where the token lives and how an adapter reaches it is decided here.
- **Rate limits**: the source's limits, the cadence floor they impose, and how the adapter's polls
  count against the program budget's source polls per hour (D-17, REQ-L1.2).
- **Write policy**: whether an adapter ever writes back to its source, and under what gate; the
  core's `cited` mode writes nothing.
- **Feasibility**: per source, whether an adapter is buildable at all; a source that is not stays
  `cited`.

## Seams it consumes from `mission-control`

- **The snapshot seam** (D-12, REQ-M1.1): the contract each adapter implements, the forge adapter
  its reference.
- **The source map** (REQ-H1.4, D-8): fact classes, access modes, and the default map an adapter
  changes.
- **The budget** (D-17, REQ-L1.2): every snapshot-mode source counts toward source polls.
- **The duty catalog** (D-3): duties read snapshots; the refreshers run under the fleet daemon
  gate (D-4).

## Observations left live for this bundle

No live fragment concerns trackers, document stores or design tools; the shape comes from the
kickoff. Two live fragments bear on the refresher pattern:

- obs:77d57078: a sweep's cadence window measured from first observation never renews, so a
  "checked once per window" read becomes every-pass after the first window (also cited by
  `universal-binary`).
- obs:a597583f: names forge secondary rate-limit hits as the revisit signal for per-call
  derivation cost (also cited by `universal-binary`).

## Open questions for the drafter

1. Which adapter first, judged by the fact classes programs most often leave `cited`.
2. The per-source auth model and where tokens live, outside the program home.
3. Whether any adapter writes, and if so whether a write is a human gate.
4. Company data: snapshots of company systems stay local and in company systems (mission-control
   REQ-I1.6); how the plugin data home, where snapshots live (D-8), bounds them.
