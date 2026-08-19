# Seed brief: amend `worker-permission-ergonomics` (guard screens + profile delivery)

Captured 2026-08-18 during the `fleet-lifecycle-closure` drafting session,
which routed this work here rather than absorbing it (that bundle's D-9).

Suggested invocation, from a fresh session in the planwright repo:

    /spec-draft --extend worker-permission-ergonomics

The bundle derives **Done**, so extending it triggers the reopen cycle
(stored Ready → Draft on all four headers); the scoped kickoff of the delta
flips it back. Append new REQ/D-IDs, never renumber.

## Why this is an amendment and not a new bundle

obs:814c6ba9 states it outright: the guard was built by this bundle's Task 1
and wired by Task 2, all tasks are complete, "so this needs a spec
amendment". The ownership claim is written down, not inferred.

## Decisions already taken (operator sign-off, 2026-08-18)

These were the reserved security calls in the lifecycle-closure drafting
brief. They are **decided**; carry them in as the delta's starting point
rather than re-eliciting them.

1. **Narrow the guard screens to write-vectors, not parse difficulty.**
   Adopt all three of obs:814c6ba9's proposals:
   - **sed** — defer on the `w`/`r`/`e` commands and `-i`/`--in-place`,
     rather than on any `[` appearing in the script. Bracket expressions in
     `s///` and in addresses are read-only however they parse.
   - **awk** — defer on `system()`, `print`/`printf` redirection, `close()`,
     and `-f progfile`; allow the rest.
   - **plugin scripts** — have the guard resolve the planwright root itself
     (`PLANWRIGHT_ROOT`, then `CLAUDE_PLUGIN_ROOT`, then
     `<claude-dir>/planwright`) and allow `<root>/scripts/*.sh`, removing the
     per-machine version-pinned Bash allow entry that breaks on every plugin
     update.

   **Gating condition, non-negotiable:** an adversarial fixture table proving
   zero false-allows lands with the change. `guard-coverage` Task 1 already
   built a fixture table; extend it rather than starting one.

2. **Add `Bash(git push -u origin:*)` to the allow list.** obs:33812f90: the
   `-u` spelling puts the flag before the remote, so the existing
   `git push origin:*` rule never matches and the first push of every task
   branch prompts — the documented happy path is the one that prompts. This
   widens spelling coverage, not capability.

3. **The `git merge` deny stays as-is.** obs:5775c447 reports that the
   blanket deny blocks the sanctioned pre-ready main-sync and that deny
   precedence means no allow rule can carve out the legitimate direction.
   Resolution: `merge-currency-guard` Task 3 is already building
   `scripts/converge-sync-main.sh`, which performs exactly that fetch-then-
   merge. Allowlist **that script by literal path** and leave the merge deny
   untouched. This needs no widening and no branch-aware hook.
   *Sequencing:* depends on `merge-currency-guard` Task 3 landing.

## Also in the delta

- **Profile delivery at dispatch (obs:eea622de).** No bring-up step delivers
  `config/worker-settings.json` to dispatched workers, so the allowlist and
  the guard hook never reach worker sessions. Four workers ran ~8 hours
  overnight with zero commits because of it. Candidate shape recorded there:
  a `worker_settings` config knob the attach plan appends after a recorded
  one-time human sign-off, plus an explicit bring-up step in `docs/fleet.md`.
- **The dead hook on the `--settings` path (obs:a4a4fa59).** A profile
  delivered via `claude --settings` ships a **dead guard hook**:
  `${CLAUDE_PLUGIN_ROOT}` resolves only for hooks defined in a plugin's
  `hooks/hooks.json`, never for hooks in a settings file, and the profile is
  deliberately not plugin-registered. Needs a documented literal-path
  substitution step or a generator. Solving delivery (above) without this
  ships a profile whose guard silently does nothing.
- **REQ-A1.3 reword (obs:4dda9fe1).** The REQ leans on Claude Code's
  documented allow-vs-deny precedence, which the hooks doc does not actually
  confirm. Reword to assert the *outcome* — the hook never emits allow for a
  deny-listed command — rather than relying on platform precedence.
- **Pin the matcher's command-substitution behaviour (obs:aed9ca33).**
  Whether the Bash permission matcher reaches into `$(...)` is undocumented
  and unverified, and it is the one model-doc boundary that errs toward
  allow. Resolve by observing a real session against a scratch settings
  fragment, then pin the answer in a doc.

## Out of scope for this amendment

- The shared command-guard library extraction (obs:30159d5c, obs:92809aad).
  A tokenizer change must currently be applied to both guards; if the screen
  changes above prove unmaintainable across the duplicate engines, surface
  that as a prerequisite rather than absorbing the refactor here.
- The awk lexer that would allow the relational `$1 > 5` form
  (obs:026930ca). Considered and not taken: it is a parser rather than a
  character screen, and belongs with the shared-library extraction.

## Fold-detection note

Run it anyway, but the 2026-08-18 pass already checked: `guard-coverage`
(owns the fixture table this extends, Ready), `fleet-hardening` (owns the
*tower* guard, derives Done), and `fleet-lifecycle-closure` (Draft, routed
this work here). None is the right owner for the worker guard itself.
