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

## The adapter contract

An adapter is a set of flat entries, one per **part**, that share a `vendor:`
field. Each entry's id is `<vendor>.<name>`, so an overlay can supersede one
recognizer of a vendor without restating the rest. Ids, vendor ids, names,
and rule names follow the step-id grammar (`^[a-z][a-z0-9-]*$`, at most 64
bytes). Every value is a single-line scalar the catalog reader keeps; a
control byte, an empty declared field, an unknown field, or a block scalar is
malformed.

| Part | Fields | Rules |
| --- | --- | --- |
| `vendor` | `evidence`, `bot-login` (optional) | Exactly one per vendor. `evidence` is a core evidence kind: `claude-frames` or `none`. `bot-login` is the bot account's login as GitHub's REST API reports it, `[bot]` suffix included; a vendor with comment-body controls needs it. |
| `recognizer` | `match`, `reset-after` (optional) | `match` is a fixed, case-sensitive string of at most 256 bytes; output containing it is a limit refusal. `reset-after` is the fixed text after which the vendor states its reset time. |
| `control` | `comment-body` or `args` | Exactly one. A comment body (at most 1024 bytes) is what a PR-comment vendor is sent; it may mention only `@<bot-login without [bot]>` and carries no issue or URL reference, link, or HTML markup. CLI `args` are blank-separated words in the plain-word charset of custom-steps' command args, passed as separate arguments and never through a shell; an option-shaped word must be `-x`, `--name`, or `--name=value` with a value opening with neither `-` nor `@`, and no word opens with `@`. |
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
