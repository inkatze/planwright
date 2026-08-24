# Storage Classes

Everything planwright writes belongs to exactly one of three classes, and each
class has one canonical home:
**framework config**, **framework runtime state**, and **user work products**.
The rule exists because the failure is silent:
runtime state committed into a work repo churns every diff and leaks machine
paths; a work product parked in framework state is invisible to review and dies
with the laptop; configuration hidden in state is neither diffable nor
reviewable. Naming the class first makes the home obvious.

Citations: inception REQ-I1.5 · inception D-8.

## The three classes

### 1. Framework config

Human-authored, declarative settings the framework reads and never writes.
Knob values, overlay doctrine, overlay catalogs.

**Home:** the four-layer overlay chain, highest precedence first —
`<repo>/.claude/planwright.local.yml` (machine-local, gitignored),
`<repo>/.claude/planwright.yml` (repo-tracked, committed), the adopter
overlay's `planwright.yml`, and the core defaults in
[`config/defaults.yml`](../config/defaults.yml). Doctrine and catalog overlays
follow the same layering under `doctrine/`, `doctrine.local/`, `catalogs/`,
and `catalogs.local/`.

Everything except the machine-local layer is committed and reviewed. Config
never holds derived values (that is class 2) and never holds secrets (see
below).

### 2. Framework runtime state

Framework-authored, machine-local, derived or reconstructible. Registries,
telemetry, dispatch markers, locks, queues, and cross-repo drops.

**Home:** the machine-local plugin data directory, `CLAUDE_PLUGIN_DATA`.

Never committed, never inside a work repo's tree, and never the source of
truth for anything a human owns. The load-bearing property is that it must be
**losable**: every consumer of runtime state carries a rebuild path — the
reconcile sweep rebuilds progress state from branches, PRs, and commit
trailers; a venture registry rebuilds by scanning the ventures root. If losing
a piece of state would lose information, it is not runtime state, and it is in
the wrong class.

### 3. User work products

What the human owns, and what they would keep if planwright disappeared
tomorrow. Spec bundles, inception bundles and their exports, observation
fragments, the artifacts a run produces.

**Home:** a git repository the human owns — `specs/<name>/` in the work repo,
the inception bundle in the venture repo, the accumulator under
`specs/_observations/`.

Committed, plain text, and readable without the framework. A work product that
can only be read through planwright's own tooling has failed this class.

## The rule

**One home per class; never mix.** When adding a file, ask three questions:

| Question | Answer | Class |
| --- | --- | --- |
| Who authored it? | A human, declaratively | 1 — config |
| Who authored it? | The framework, as a side effect | 2 or 3 |
| What if it is deleted? | Rebuilt from durable sources | 2 — runtime state |
| What if it is deleted? | Information is lost | 3 — work product |

A file that answers "the framework authored it *and* losing it loses
information" is a work product the framework happens to write, and belongs in
the repo — not in `CLAUDE_PLUGIN_DATA`.

## Secrets belong to none of them

Credentials, tokens, and keys are not a fourth class with a home here: they
are excluded from all three. Config references a secret by name; it never
carries the value. Runtime state does not cache one. A work product that
contains one is a data-hygiene finding
([security-posture.md](security-posture.md), and the secrets-and-configuration
domain in [decision-domains.md](decision-domains.md)).

## Minting a new home

A new storage location is a new mechanism, which means the existing-seam-reuse
domain fires ([decision-domains.md](decision-domains.md)): name which of these
three homes is nearest and why it does not fit, in the spec's design decision
or the kickoff brief's risk register, before minting one.

`CLAUDE_PLUGIN_DATA` as the runtime-state home is recorded as **interim**
(inception D-8): it is the sanctioned cross-repo state home today, and it
re-anchors on the cross-repo routing effort when that revives. The three-class
split itself is not interim; only the current address of class 2 is.
