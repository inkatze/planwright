# Where the fleet's tokens go (2026-11)

A fleet's spend is dominated by a few habits, not by its prompts. This note
measures one host's transcripts, ranks the cuts by what they save, and ships
the tools that rerun the measurement and attribute spend to a unit of work.
Dollars are Claude API list prices from
[`config/token-prices.tsv`](../../config/token-prices.tsv); on a
subscription they stand for usage-window share, not a bill.

## What was measured

Every Claude Code transcript on the operator's host (all projects, sub-agent
transcripts included; the CLI keeps about two weeks, so the history starts
2026-10-26), read with `scripts/token-spend.sh`. Two windows:

- **Full history**, 2026-10-26 to 2026-11-08 UTC: $14,420, of which cache
  reads $8,816 (44.4B tokens), cache writes $3,961 (604M), output $1,641
  (82M), input under $2. Opus 5.5 is over 98% of it.
- **Mission-control era**, 2026-11-05 UTC to the measurement early on
  2026-11-08, about 3.3 days: $3,478, about $1,050 a day. Mission-control
  hubs $1,153; sessions they launched $2,202, of which sub-agents $1,057;
  the other $123 is sessions mission control neither ran nor launched.

The script's dollars matched the CLI's own `costUSD` to the cent on the four
fleet workers checked.

## The cuts, ranked

Each figure is the mission-control era first, then the full history. A
cache-read token is the cheapest token class by far, so the token and dollar
rankings differ; the order below is by dollars, the binding limit.

### 1. Hand long-lived sessions over at 200k context

Cache reads above 200k context: 3.1B tokens, $607 (17%); 20.4B tokens,
$4,072 (28%). Every turn re-reads the whole context, so a 1M-context turn
costs ten times a 100k one in reads alone. Before mission control, seven
long-running hub, tower and orchestrator sessions ran for days at 1M context
and cost $5,593, 39% of the history. Launched hubs since late 2026-11-07
hand over near 200k and peak there.

A handover is cheap: a hub's cold start plus its first ten turns of writes
averages $0.45, so it pays for itself within a few turns at high context.
The restarts the fleet already does are not a cost driver.

**Core change:** lower the shipped `mission_control_handover_context` (a
context percent) to 20, a 200k trigger on a 1M window. It reaches only a
launched hub: an attended hub compacts instead of handing over (mission-control
REQ-L1.5, which holds for a launched holder only per REQ-L1.8; D-29 as
superseded by D-42), so covering
attended hubs means reopening D-42. The tower's `context_budget_threshold`
counts orchestration steps, not context (orchestration-fleet REQ-C1.1, D-4),
so towers and `/orchestrate --watch` need a context trigger of their own
rather than a lower step count. These change spec-covered behavior, so they
go as amendments through `specs/_pending/`, not in this change.

### 2. Run review and verification sub-agents on Sonnet, or fewer of them

Sub-agents: $1,106 (32%) and $2,920. Those whose prompt is a review, lens,
verification or audit: 501 agents, $795 (cache writes $362, output $219);
1,792 agents, $2,301. A sub-agent writes about 195k tokens of cache on
average as it reads the files under review, at the 5-minute rate.

**Core change, option A:** a shipped model default for read-only lens and
verification sub-agents, set to `claude-sonnet-5-5`. Its writes and output
cost half of Opus 5.5's and its reads the same, so it saves about $290 and
$800 with no change in tokens. This trades review quality for spend and
reverses the operator's choice of Opus for verification agents: it is the
operator's decision. It belongs to the model-allocation spec's per-step
tiers (an amendment).

**Option B, tokens:** hand each lens agent the diff and the excerpts it
needs instead of letting it re-read whole files. Not sized: the transcripts
do not separate the reads a lens needed from the ones it did not.

### 3. End a worker instead of letting it wait past an hour

Cache rebuilds after an idle gap over an hour (the 1-hour cache lifetime):
109 rebuilds, 23.7M tokens, $171; 428 rebuilds, 131M tokens, $1,093. Most
are launched workers resuming after a long CI, bot or review wait. The
average rebuild writes 217k tokens ($1.57); a fresh session with a handover
brief starts for about $0.42 (cold start plus warm-up).

**Core change:** a wait expected to outlast 55 minutes ends the worker: it
writes its handover brief and exits, and mission control launches a fresh
worker with that brief when the awaited event fires. The shipped wait
helpers and the worker brief carry the rule. It saves about 18M tokens and
$125, and 107M tokens and $895. Owner: mission-control and
fleet-lifecycle-closure, through `specs/_pending/`.

### Measured and not worth cutting

- **Cold starts and warm-up** (each session's first write and its next nine
  turns): $101 and $295 across all sessions. Restarting is cheap.
- **Launch briefs re-read every turn**: about $11 in the era, of which the
  standing-rules block is $8. A planwright worker brief is about 21 KB,
  most of it that block, but cached re-reads are the cheapest tokens there
  are. Trim them for clarity, not spend.
- **Idle registered sessions**: an idle session spends nothing until woken,
  and waking one is cut 3. All 43 launch records on the host read
  `launched`, none retired: clutter, not spend.
- **Repeat sessions on one branch**: $421 and $2,102 beyond each branch's
  first session, but a session's fixed overhead is the $0.42 start; the rest
  is the round's own work. The spend record below makes rounds per unit
  visible.
- **Output**: $559 and $1,641. No cut without quality data.

### Do not switch main sessions to the 5-minute cache

Main sessions write the 1-hour cache and sub-agents the 5-minute one, which
costs less per write (the multipliers are in the price table). Moving main
sessions to 5 minutes (`FORCE_PROMPT_CACHING_5M`) would cost $1,255 and
$6,536 more: the era has 1,617 gaps of 5 to 60 minutes (tool runs, CI
checks), and each would rewrite the whole context instead of reading it.

## The tools

**`scripts/token-spend.sh`** reruns this note. `rows` reads each transcript
alone (a grep, then jq) into one line per assistant message, sub-agents
included; `report` turns those lines into the totals, kinds, dearest
sessions and branches, and every driver above. Keep the rows outside the
repository: they carry prompt heads, paths and branch names.

```sh
scripts/token-spend.sh rows > "$TMPDIR/rows.tsv"
scripts/token-spend.sh report "$TMPDIR/rows.tsv"
scripts/token-spend.sh report --context-cap 400000 "$TMPDIR/rows.tsv"
```

The mission-control era above is the same rows cut by message time, the
session lines kept:

```sh
awk -F '\t' '$1 == "s" || $5 >= "2026-11-05"' "$TMPDIR/rows.tsv" > "$TMPDIR/era.tsv"
```

A full sweep of 4 GB of transcripts took under seven minutes at the lowest
CPU and I/O priority. `rows --since <date>` skips files last written at or
before local midnight of that date, so it shortens a sweep but keeps every
message of a file written since. Kinds come from each session's first prompt and are
approximate.

**`scripts/spend-record.sh`** is the per-unit spend record. `record` totals
one session with its sub-agents and appends a row, under a lock, to
`<fleet-home>/mission-control/<program>/spend.tsv`; `read` sums rows per
unit:

```sh
scripts/spend-record.sh record --program planwright --launch mc-planwright-worker-0123456789
scripts/spend-record.sh record --program planwright --session <id> --unit pr-901
scripts/spend-record.sh read --program planwright
```

`--launch` takes a mission-control launch record of that program and reads
the session id from its stream-json worker directory, the unit from its
scope and the kind from its kind. For a session recorded more than once,
`read` keeps the row covering the latest message. Nothing calls `record`
yet: recording each worker as mission control retires it (while it holds
the launch name, so a relaunch under the same name cannot swap the session),
and showing a unit's spend on the panel, change mission-control behavior and
go through `specs/_pending/` with cut 3. The harness-rebaseline measurement
kit can read its token fields from the same totals.
