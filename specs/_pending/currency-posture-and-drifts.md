# Seed: currency posture, fetch hang guards, and four skill/doctrine drifts

Captured 2026-10-04 from the operator's dotfiles instruction audit
(`specs/claude-instructions` in the dotfiles repository, Task 6, REQ-I1.1 and
REQ-I1.2). That audit decided what to keep in the operator's own instruction
files and routed every rule it found wanting that planwright owns here
instead of patching around it (its D-9: a general capability graduates
through planwright's own drafting, not a local overlay). Its evidence was a
rule-by-rule inventory taken against planwright 0.44.0; every item below was
re-checked against 0.51.0 for this note, and the "Now" line on each says what
that re-check found.

Suggested invocation, from a fresh session in the planwright repo:

    /spec-draft currency-posture-and-drifts

The items do not share one owner. Run fold-detection before assuming a new
bundle: items 1 and 2 belong to `merge-currency-guard` (which already has a
pending amendment, `merge-currency-guard-amendment.md`, touching the same
hook), items 4 to 6 are skill-text drifts in `/spec-kickoff` and
`/execute-task` and probably go to their owning bundles as expression-only
amendments, and item 8 looks closed. Splitting this note by owner is a fine
outcome.

## The items

Each item: what to change, one line of why, then the evidence.

### 1. A ready guard that accepts a mergeable branch that is behind, or a knob to opt out

**Why:** where CI runs on the PR's merge ref, a branch that is mergeable but
behind its base produces the same merge commit whether or not it is synced
first, so forcing the sync buys a CI re-run and changes nothing.

- **Evidence:** the audit's D-3 and REQ-A1.1 changed the operator's own
  ready condition to "no conflicts with the base" (`mergeable: MERGEABLE`),
  and REQ-A1.4 sends the stricter planwright mechanisms here. The inventory
  found the guard is plugin-global `PreToolUse` wiring with no config knob
  (only a `gh` timeout and a retry-delay environment variable), so it also denies the operator's own
  `gh pr ready` in every repository where the plugin is enabled.
- **Now (0.51.0):** `scripts/ready-guard.sh` still denies whenever
  `behind_by != 0`; `merge-currency-guard` REQ-A1.1 is the single home of
  the behind-by-zero rule, so this is a meaning-class amendment there.
- **Accepted gap the audit named:** a green result from before the base moved
  does not cover later base changes. The audit leaves that to the operator,
  who syncs when it matters.
- **Overlap:** see `review-pass-capabilities.md` item 7. That item is about
  what counts as full-suite evidence; both items are about how many CI
  cycles a PR has to pay for.

### 2. A way to skip the convergence merge of the base into a worker branch

**Why:** the merge runs on every convergence pass even with no conflict, so it
moves the head and pays a fresh CI cycle each time, and a conflict it cannot
resolve lands on a worker that is not allowed to run `git merge` itself.

- **Evidence:** the audit's D-3 and REQ-A1.4. The inventory found the step
  has no config knob, no environment override and no overlay. It also found
  that the script's own header records that the merged head is not re-run
  through `/execute-task`'s full-CI step, and that the worker deny list
  forbids the merge a conflict asks for.
- **Now (0.51.0):** `/execute-task`'s Convergence section still runs
  `scripts/converge-sync-main.sh` unconditionally, "an empty list included",
  and `config/defaults.yml` has no key for it. The owner is
  `merge-currency-guard` REQ-B1.1.
- **Shape to decide:** a default-preserving knob, for example sync always
  (today), sync only when GitHub reports a conflict, or never. Item 1
  decides whether "behind" alone should ever force a sync.

### 3. Hang guards on the dispatch fetch

**Why:** an unbounded fetch inside the per-spec lock window can wedge a tower
indefinitely when SSH authentication cannot complete.

- **Evidence:** dotfiles observation `4570a2c5` (2026-07-23). The
  freshness-gate fetch blocked for more than 120 seconds with the per-spec
  lock held, because the SSH agent was locked after a restart. It cleared
  only when the operator unlocked the agent. The observation suggests a
  git-level timeout or a non-blocking auth probe (`git ls-remote` with
  `ConnectTimeout` and `BatchMode`) so the gate parks to Awaiting input
  instead.
- **Now (0.51.0):** `scripts/dispatch-fetch.sh` sets no
  `GIT_TERMINAL_PROMPT`, no ssh `BatchMode` and no timeout around its
  `git fetch`. Its sibling `scripts/converge-sync-main.sh` exports
  `GIT_TERMINAL_PROMPT=0` and forces `BatchMode=yes`, so the pattern to copy
  already exists. The reconcile sweep's best-effort fetch uses the same
  script.

### 4. A home for a bundle-level pending ready flip under Awaiting input

**Why:** `/spec-kickoff` records a failed spec-PR ready flip under
`## Awaiting input`, but format-version 2 allows only `**Task <id>**`
reference bullets there, and a spec PR has no task id.

- **Evidence:** dotfiles observation `6e1b5fcc` (2026-08-05). The degrade
  arm fired for real on a kickoff when CI was not green, and the entry had
  to be written as a plain bullet. `spec-validate.sh` accepted it at Ready,
  so the constraint is documented but not enforced.
- **Now (0.51.0):** the arm the observation hit, `kickoff-verification`'s
  terminal ready-flip CI gate refusing on CI that is not green, still
  records the pending flip under Awaiting input. So do both of
  `/spec-kickoff`'s own degrade arms (the push/PR failure and the flip
  failure). And
  `spec-format` still says that section "holds reference bullets only". The
  newer `pending ready-flip:` payload segment rides inside a task's
  reference bullet, so it does not cover the bundle-level case.
- **Fork to decide:** let Awaiting input hold plain bullets for bundle-level
  blockers, or name a different home for the pending flip.

### 5. The duplicate halt-bullet clause in `/execute-task`

**Why:** the halt protocol reads as "each halt writes its own bullet", but a
task may carry at most one reference bullet, so a run that halts twice
writes a validator error after the content is already committed.

- **Evidence:** dotfiles observation `9eeec28e` (2026-08-06). One task hit
  the halt protocol twice in a single run: once for Done-when clauses it
  could not verify, and again for a hard-disqualifier finding during
  convergence. The second bullet failed `spec-validate` ("named by more
  than one reference bullet").
- **Now (0.51.0):** the Pre-flight halt protocol in
  `skills/execute-task/SKILL.md` is unchanged and does not restate the
  one-bullet limit. The fix is one clause: a task that already has a bullet
  gets that bullet extended, not a second one.

### 6. `/spec-kickoff` pre-flight order

**Why:** working-location resolution runs after the bundle check and the
validator, so from the main checkout a bundle that lives only on its spec
branch reads as a structural defect, and the pre-flight work is spent and
then re-run after the switch.

- **Evidence:** dotfiles observation `5d46a147` (2026-08-05), seen on a
  four-file Draft bundle that sat unmerged on its spec branch.
- **Now (0.51.0):** pre-flight still runs bundle verification (step 2), the
  validator (step 3) and config (step 4) before resolving the working
  location (step 5). Resolving the location first would make the stop free.

### 7. Doctrine that lags the scripts on where the freshness gate reads from

**Why:** two doctrine passages still describe the gate before
fetch-before-gate landed, so a reader auditing the gate against doctrine
gets the wrong ref and a `tasks.md` write that no longer happens.

- **Evidence:** the inventory found the skills and `scripts/dispatch-fetch.sh`
  gate against the freshly fetched `origin/main`, while the doctrine says
  otherwise.
- **Now (0.51.0):** both passages are still there.
  - `spec-format` *Execution validity* says `/orchestrate` recomputes
    "immediately before the `tasks.md` update" and that both skills "read
    from the primary checkout's main view". But `/orchestrate` now says it
    never writes `tasks.md` at dispatch.
  - `orchestration-concurrency`'s reconcile-sweep paragraph says "the
    freshness gate's local-main view ... intentionally tracks the
    operator's checked-out brief, not the remote tip".
- **Class:** expression-only, since the scripts are the behaviour.
  `spec-format` is a protected doc.

### 8. Should `review_sequence` accept nestable skills from outside planwright's root?

**Why it was raised:** at 0.44.0 the resolver accepted only skills under
planwright's own skills root. So the operator's review skills could never be
named, while the operator's instruction file claimed they could.

- **Evidence:** the inventory measured it. A machine-local `[panel-review]`
  degraded to `polish` with a warning, and a repo-tracked list naming
  another review skill exited 4, which `/execute-task` treats as a stop.
- **Now (0.51.0): probably closed.** `review_sequence` is retired in favour
  of custom-steps: `steps_<point>` lists plus catalog entries, where a skill
  target is `<name>` or `<plugin>:<name>`. The dotfiles `review-skills`
  bundle (its D-12) registers its review skills through an adopter catalog,
  and this note's own visual flight ran an operator review skill as its
  second convergence step.
- **Left to confirm:** close it, or record any target shape that still does
  not resolve. Related: `review-pass-capabilities.md` item 6, a structured
  result for such external steps.

## Data hygiene

The source observations name a credential product and a host. This note
keeps only the failure shape. Private repository names stay out, per
`security-posture` *Artifact data-hygiene*.

## References

- dotfiles `specs/claude-instructions`: REQ-A1.1, REQ-A1.4, REQ-I1.1,
  REQ-I1.2, D-3, D-9, Task 6.
- dotfiles observations `4570a2c5`, `6e1b5fcc`, `9eeec28e` (archived there
  as consumed by that bundle) and `5d46a147` (cited by it, still live in
  that repository's observations).
- `specs/merge-currency-guard/` REQ-A1.1, REQ-B1.1;
  `specs/_pending/merge-currency-guard-amendment.md`.
- `scripts/ready-guard.sh`, `scripts/converge-sync-main.sh`,
  `scripts/dispatch-fetch.sh`, `skills/spec-kickoff/SKILL.md`,
  `skills/execute-task/SKILL.md`, `doctrine/spec-format.md`,
  `doctrine/orchestration-concurrency.md`, `doctrine/custom-steps.md`.
- `specs/_pending/review-pass-capabilities.md`, the companion seed from the
  same operator's review-skills bundle.
