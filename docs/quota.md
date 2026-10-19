# Vendor quotas

A unit's process depends on metered services planwright does not run: a
review bot that answers a PR comment, an external model CLI a step shells out
to, and Claude itself. When one of them refuses with a quota, usage, or rate
limit, planwright recognizes the refusal through that vendor's **adapter**:
data in the `vendors` catalog that names the vendor's refusal text, how to
tell the limit has cleared, and the controls the vendor offers.

This page is the reference for the adapter contract. Core ships one adapter,
for Claude; every other vendor is described in your own overlay. The
third-party examples below use invented placeholder vendors
(`sample-reviewer`, `sample-cli`); write your real vendors' strings in your
overlay.

## Where adapters live

The `vendors` catalog resolves through the same four layers as every data
catalog ([Overlays](overlays.md), *Data catalogs*):

| Layer | File |
| --- | --- |
| core | `config/vendors.yaml` (the `claude` adapter) |
| adopter | `<adopter-root>/catalogs/vendors.yaml` |
| repo-tracked | `<repo>/.claude/catalogs/vendors.yaml` |
| machine-local | `<repo>/.claude/catalogs.local/vendors.yaml` |

`scripts/resolve-vendors.sh` merges them (append, or `supersede: true` to
replace an entry by id), validates every entry, and prints the result grouped
by vendor; `--explain` names the layer each part came from, and `--vendor
<id>` limits the output to one vendor. Its header pins the output shape, the
exit codes, and every field's full grammar, bounds included.

A malformed entry follows the catalog by-layer policy: in core it is a broken
install, in a repo-tracked overlay it fails the resolution (a shared team
catalog never degrades silently), and in an adopter or machine-local overlay
it is dropped with a warning naming the reason. A part whose vendor entry, or
whose choice's control, was dropped goes with it.

Two entries that conflict, a second vendor entry for one vendor or two choice
pairs at the same position of one rule, are an override when they come from
different layers: the higher layer's entry wins and the resolver warns, naming
both entries and their layers. Only a conflict within a single layer is
malformed.

## The adapter contract

An adapter is a set of flat entries, one per **part**, that share a `vendor:`
field. Each entry's id is `<vendor>.<name>`, so an overlay can supersede one
recognizer of a vendor without restating the rest. Each half of an id (the
vendor id and the name), and rule names, follow the step-id grammar (`^[a-z][a-z0-9-]*$`, at most 64
bytes). Every value is a single-line scalar the catalog reader keeps; a
control byte, an empty declared field, an unknown field, or a block scalar is
malformed.

| Part | Fields | Rules |
| --- | --- | --- |
| `vendor` | `evidence`, `bot-login` (optional) | Exactly one per vendor. `evidence` is a core evidence kind: `claude-frames` or `none`. `bot-login` is the bot account's login as GitHub's REST API reports it, `[bot]` suffix included; a vendor with comment-body controls needs it. |
| `recognizer` | `match`, `reset-after` (optional) | `match` is a fixed, case-sensitive string of at most 256 bytes; output containing it is a limit refusal. `reset-after` is the fixed text after which the vendor states its reset time. |
| `control` | `comment-body` or `args` | Exactly one. A comment body (at most 1024 bytes) is what a PR-comment vendor is sent; it may mention only `@<bot-login without [bot]>` and carries no issue or URL reference, link, HTML markup, or HTML entity. CLI `args` are blank-separated words in the plain-word charset of custom-steps' command args, passed as separate arguments and never through a shell; an option-shaped word must be `-x`, `--name`, or `--name=value` with a value opening with neither `-` nor `@`, and no word opens with `@`. |
| `choice` | `rule`, `position`, `condition`, `control` | One ordered pair of a choice rule: the pairs of a rule are tried by `position`, and the first whose `condition` holds names the control. Conditions: `no-prior-review` (the vendor has answered no review request on this PR) and `prior-review`. `control` names a control of the same vendor. |

Controls are named in the vendor's own vocabulary and referenced as
`<vendor>:<control>`; planwright defines no shared control names and never
maps one vendor's control onto another's.

Nothing in an adapter is executed, evaluated, or used as a pattern:
recognizers match as literal text, comment bodies are posted from a file, and
CLI arguments are argv entries.

### Evidence kinds

- `claude-frames`: Claude's own rate-limit readings, which stream-json workers
  report as they run. Used by the core `claude` adapter only.
- `none`: no evidence source; a hold on this vendor waits for the operator.

Adding an evidence kind is a core change.

### Claude's readings

The stream-json supervisor keeps each worker's newest rate-limit reading beside
its other runtime state under the fleet home, and the reading outlives the
worker. `scripts/claude-frames.sh read` shows the session and weekly
utilization those readings give: for each window, a reading whose reset time
has passed, or lies beyond the throttle's hold ceiling, is ignored, and of the
rest the one with the furthest-future reset is taken, whichever worker sent
it. `scripts/fleet-stats.sh render` shows the
same as its `Claude usage` line. The header of `scripts/claude-frames.sh` pins
the stored frame, the output lines, and the exit codes.

These readings are **account-wide**: every session on the Claude account counts
toward them, not only the fleet's workers, so they are a ceiling to respect,
never the fleet's own spend, and every rendering says so. A fleet whose workers
run only on backends that emit no readings (headless or subagent workers), or
whose readings are all ignored, reads **unmeasured**, never as headroom.

A Claude hold counts as cleared only when each window has a reading received
after the hold began that is below the window's lowest restriction threshold,
its usage-gate `downshift` knob (`fleet_usage_session_downshift`,
`fleet_usage_weekly_downshift`; [Options reference](options-reference.md)). A
threshold set the usage gate refuses as malformed clears nothing either.
`scripts/claude-frames.sh clearance --since <epoch>` answers that for a hold
that began at `<epoch>`. A stated reset time passing is not evidence. The usage
gate's own signal is its `/usage` read; these readings never change it.

## Classifying a refusal

`scripts/classify-limit.sh --vendor <id> [--input <file>]` reads captured
output (a step's output, a bot's reply, a worker's event stream) and checks it
against the vendor's recognizers. A match prints the outcome `limited`, the
vendor, the matching recognizer's id, an excerpt screened and bounded as a
step-record excerpt is, and the stated reset time, in epoch seconds, when one
is accepted: the vendor stated it as epoch seconds or as an ISO-8601 UTC
timestamp in the `Z` form (`2026-01-31T09:30:00Z`, a fractional second
allowed; a numeric offset such as `+00:00` is not accepted), after now and
within the throttle's hold ceiling. No match exits 1 and prints nothing, so an unrecognized
failure keeps its ordinary outcome. The script's header pins the output
lines, the reset-time rules, and the exit codes.

## When a worker dies on a limit

A Claude worker killed by an API error still ends its run in good order: a
result frame reporting `success`, a zero exit. What says it died is the
result's `is_error` flag and the error text, so `scripts/worker-death.sh`
reads those, from a stream-json worker's event stream or a headless worker's
`result.json`. A rate-limit death is `limited` against `claude`: the unit is
held at step `worker`, and the fleet's dispatch throttle is engaged until the
reset time the error states, or, when it states none, until the time the
throttle reads from the error text (its default hold when it finds none). Any
other API error, a 529 overload say, is a failure naming its cause.

The completion readers report both, never a clean completion:

- `scripts/fleet-streamjson.sh status <worker>` prints `limited` or `ended`,
  the detail ending `/limited=claude` or `/cause=<cause>`;
- `scripts/fleet-dispatch-headless.sh status <spec> <id>` prints
  `limited <rc> claude` (exit 7) or `ended <rc> <cause>` (exit 6);
- `scripts/fleet-stuck-detector.sh` reports the worker `unclassified` with
  the same cause in its `completion-failed` reason.

Releasing the hold (`scripts/quota-hold.sh resume --vendor claude`) does not
clear the throttle; `scripts/fleet-throttle.sh clear` does.

## Holds and the usage ledger

A held vendor is held for the whole host: each unit holding it is recorded in
the vendor's hold store under the fleet home, never in `tasks.md`, and
recording a hold pushes one attention event naming the vendor, the reason, the
stated reset time (or that none was stated), and the resume command; a `claude`
hold's event also says its usage is account-wide.

To resume a held vendor yourself, at any time:

```sh
scripts/quota-hold.sh resume --vendor <id>
```

It releases every unit holding the vendor and prints each one it released.

Each vendor also keeps a usage ledger of requests sent, answers, refusals,
holds, and resumes, with the PR and head where the event has them. It lives
only under the fleet home, is never committed, and drops lines older than
`quota_ledger_retention_days` (90 days unless you set it;
[Options reference](options-reference.md)) when you run
`scripts/quota-hold.sh prune`; nothing runs it on a schedule, and until it
runs the period still bounds what the counts include. To see each vendor's hold state and its
counts over that period, run `scripts/fleet-stats.sh render`, or
`scripts/quota-hold.sh status` for the machine-readable form. The header of
`scripts/quota-hold.sh` pins the store layout, the field grammars, and the exit
codes.

## Examples

A PR-comment review bot, as an operator would declare it in
`<repo>/.claude/catalogs.local/vendors.yaml`:

```yaml
vendors:
  - id: sample-reviewer.vendor
    vendor: sample-reviewer
    part: vendor
    evidence: none
    bot-login: sample-reviewer-app[bot]
  - id: sample-reviewer.quota
    vendor: sample-reviewer
    part: recognizer
    match: review quota for this period is used up
    reset-after: "available again at "
  - id: sample-reviewer.full
    vendor: sample-reviewer
    part: control
    comment-body: "@sample-reviewer-app full review"
  - id: sample-reviewer.delta
    vendor: sample-reviewer
    part: control
    comment-body: "@sample-reviewer-app review the new commits"
  - id: sample-reviewer.first-full
    vendor: sample-reviewer
    part: choice
    rule: auto
    position: 1
    condition: no-prior-review
    control: full
  - id: sample-reviewer.then-delta
    vendor: sample-reviewer
    part: choice
    rule: auto
    position: 2
    condition: prior-review
    control: delta
```

An external model CLI with effort levels:

```yaml
vendors:
  - id: sample-cli.vendor
    vendor: sample-cli
    part: vendor
    evidence: none
  - id: sample-cli.monthly
    vendor: sample-cli
    part: recognizer
    match: monthly request allowance exhausted
  - id: sample-cli.deep
    vendor: sample-cli
    part: control
    args: --effort=high
  - id: sample-cli.quick
    vendor: sample-cli
    part: control
    args: --effort=low --no-tools
```

Replacing one of the core `claude` recognizers from an overlay, leaving the
others as shipped:

```yaml
vendors:
  - id: claude.usage-limit
    supersede: true
    vendor: claude
    part: recognizer
    match: usage limit reached
    reset-after: usage limit reached|
```

Check the merged result with `scripts/resolve-vendors.sh --explain`.
