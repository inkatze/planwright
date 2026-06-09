# Panel-* underuse — investigation

**Spec task:** Task 1 (`specs/pair-flow/tasks.md`)
**Citations:** REQ-G1.1, D-6, D-12
**Window:** 2026-04-22 through 2026-05-21 (30 days, ending the day before the pair-flow spec was drafted)
**Data source:** JSONL transcripts under `~/.claude/projects/**/*.jsonl`, including subagent files per [[project_subagent_volume]]. Slash-command invocations identified by `<command-name>` tags in user-typed messages (the format Claude Code emits when a user runs a slash command interactively). Skill-listing mentions are excluded by relying on that tag rather than free-text matches.

## Headline finding

**`/panel-*` is not underused. It is newly available.** The 30-day window crosses the `/panel-*` skill release date (2026-05-15, PR #22) almost exactly two-thirds of the way through, so the raw 29-vs-14 framing collapses on inspection: `/copilot-*` and `/panel-*` did not co-exist as live alternatives for most of the window.

| Skill | Total invocations in window | Earliest | Latest |
|---|---|---|---|
| `/copilot-pairing` + `/copilot-review` | 42 | 2026-04-22 | 2026-05-14 |
| `/panel-pairing` + `/panel-review` | 14 | 2026-05-18 | 2026-05-20 |

(The 42 figure is what the JSONL grep yields today; the spec quotes 29 from an earlier draft. The qualitative shape — `/copilot-*` dominates the pre-panel period, `/panel-*` dominates the post-panel period — is what matters.)

After `/panel-*` shipped, `/copilot-*` was invoked **zero times**. There is no measured period in which the user picked `/copilot-*` over `/panel-*`. Underuse is the wrong lens.

## Timeline detail

```
Apr 22 ████████████████████ 13× /copilot-review   ← initial /copilot-review usage burst
Apr 24 █  1× /copilot-review
Apr 28 █  1× /copilot-review
Apr 29 ███  3× /copilot-review
May 03 ██████  6× /copilot-pairing                ← /copilot-pairing arrives in workflow
May 04 █  1× /copilot-pairing
May 05 ███  3× /copilot-pairing
May 07 ████  4× /copilot-pairing
May 08 ████  4× /copilot-pairing
May 11 ████  4× /copilot-pairing
May 13 █  1× /copilot-pairing
May 14 █  1× /copilot-pairing                     ← last /copilot-* invocation
─────────────────────────────────────────────────  /panel-* ships (PR #22, commit 467dcfb)
May 18 ███  1× /panel-pairing, 2× /panel-review
May 19 ████████  6× /panel-review, 2× /panel-pairing
May 20 ███  3× /panel-pairing
```

The clean handoff at 2026-05-15 (no overlap, no fallback, no re-invocation of `/copilot-*` after `/panel-*` shipped) is the strongest available evidence that the user actively prefers `/panel-*` when both exist. This contradicts the implicit assumption that underuse meant disuse.

## Friction signals during the 6-day `/panel-*` window

Even though `/panel-*` is the active choice, two friction signals show up in the small post-release sample. Both are addressable, and both **already have a paired design decision in this spec**, which suggests the spec author anticipated them.

### Signal 1 — Default backends are wrong

7 of 14 `/panel-*` invocations (50%) explicitly overrode the default backend set via `--backends`:

| Skill | Invocations | With `--backends` override | Override target |
|---|---|---|---|
| `/panel-review` | 8 | 6 (75%) | `qwen-coder,deepseek-r1` (six times) |
| `/panel-pairing` | 6 | 1 (17%) | `deepseek,qwen` (once, on a 70-second-later retry of a default-backends call) |

The personal-profile default at the time was `qwen-coder,gpt-oss` (per the user-global CLAUDE.md `/panel-review` description). Every override that swapped a model swapped out `gpt-oss`. The user never reached for the documented default on `/panel-review`.

The single `/panel-pairing` retry within 70 seconds is the strongest behavioural signal: the user invoked once with default backends, watched briefly, then re-invoked with `--backends=deepseek,qwen`. That is a default-rejection event, captured in real time.

**Pairing in spec:** D-6 (Codex-only default for `/panel-*`, provisional). The spec already proposes collapsing the default to a single backend — `codex` — on all profiles. This investigation provides the empirical grounding D-6 was provisionally waiting on.

### Signal 2 — Cross-host Ollama tripped the auto-mode classifier

One observed incident, 2026-05-19T21:30:10: the auto-mode classifier denied a tool call with reason *"Sending project source code (full git diff with internal module code) to an external Ollama server at 192.168.1.20 not listed as a trusted endpoint constitutes data..."*. The cross-host Ollama topology that lets non-`work` hosts route to the `work` daemon (commit 0a15800, 2026-05-19) is a documented and trusted part of this dotfiles repo (CLAUDE.md `Cross-host Ollama topology`), but the classifier does not know that. Auto-mode treated it as exfiltration.

This is a permission-allowlist gap, not a flaw in `/panel-*`. It would have blocked any tool sending diff bytes to `192.168.1.20`. But it materializes during `/panel-*` sessions and would surface again unless explicitly allowed.

**Pairing in spec:** none directly, but the existing `chore(claude): allow LAN ollama curl` branch history suggests an explicit allow-rule for `curl http://192.168.1.20:11434/*` is the right fix. Worth a follow-up issue, not a blocker.

## Other lenses ruled out

- **Reflex (typed `/copilot-*` from muscle memory).** Ruled out: zero `/copilot-*` invocations after `/panel-*` shipped, in 6 days of active use across at least three worktrees. If reflex were the cause we would see at least one slip.
- **Latency (panel too slow).** No transcript evidence of abandoned `/panel-*` runs in the sample. The four-times-per-hour `/panel-review` clump on 2026-05-19 (00:03, 00:12, 00:33, 01:04 — 21-minute median gap) is consistent with iterating between review and fix, not waiting on a hung backend.
- **Low yield (panel finds nothing).** Cannot rule out from invocation counts alone, but the user-side behaviour (continued use, override-and-retry, multiple iterations) is not the shape of "this tool wastes my time." Yield is what Task 13's end-to-end validation is for.
- **Quota.** Not applicable: panel backends are local (Ollama) or business-account (codex); no per-request paid quota that would cap usage.

## Recommendation

**Keep `/panel-*` as the default panel skill. Do not demote, do not retire.** The spec's existing decisions D-12 and D-6 already encode the right adjustments; this investigation supports them, it does not change them.

Concretely:

1. **Confirm D-6 (codex-only default).** Drop `/panel-*` to a single default backend = `codex` on all profiles. The transcript evidence is that the existing two-backend default is consistently rejected; making the default what the user keeps overriding to is a simpler fix than the override path. `--backends` remains available for variance opt-in. D-6's "provisional" qualifier can be removed.
2. **Confirm D-12 (`/panel-pairing` demoted to escalation; `/polish` is the default convergence loop).** The 52 `/self-review` + 20 `/polish` invocations in the same window dwarf both `/copilot-*` and `/panel-*`; the user already uses `/polish`-shape as the convergence default. D-12 codifies what is already happening.
3. **Add LAN Ollama curl to the allowlist.** Follow-up issue, not a blocker for the rest of pair-flow. Tracks the existing `chore/claude-allow-lan-ollama-curl` branch idea.
4. **Re-measure at 30 days post-pair-flow.** Once `/orchestrate` and `/execute-task` land and panel-* is opt-in escalation only, the invocation count will be lower by design. That is not underuse either; it is the intended shape.

## Methodology notes (so this is reproducible)

- Discovery counted `<command-name>` tags inside user-typed message content. The string `/panel-` also appears in skill-listings, in skill prompt body text that references `/panel-pairing`, and inside hook output; those are excluded by tag matching.
- The 30-day window was applied as a timestamp filter on the JSONL `timestamp` field, not on file mtime (mtime drifts when transcripts are re-edited by the harness).
- Subagent JSONLs were walked, per [[project_subagent_volume]], but contributed zero matches in this window. Slash-command invocations originate in main threads.
- `git log --all --format='%h %ai %s' -- 'roles/osx/files/claude/commands/panel-*'` was used to anchor the panel release date.

## Open follow-ups

- **D-6 finalization.** This investigation is the empirical input D-6 said it was waiting on. The D-6 line in `design.md` can drop "provisional" and the corresponding language in REQ-G3.1.
- **Yield measurement.** Task 13's retrospective should record whether `/panel-pairing` (when invoked as escalation) catches anything `/polish` did not. That is the only honest signal for the "low yield" hypothesis we cannot rule out from invocation counts.
- **LAN-Ollama permission allow.** Track as a separate small change against `roles/osx/files/claude/settings.json` (`Bash(curl:* http://192.168.1.20:11434/*)` or equivalent). Not in this spec's scope per D-26's adjacent file-path-hook scope.
