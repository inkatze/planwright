# Storage Classes

Everything planwright writes belongs to exactly one of three classes, and each
class has one canonical home:
**framework config**, **framework runtime state**, and **user work products**.
The rule exists because the failure is silent:
runtime state committed into a work repo churns every diff and leaks machine
paths; a work product parked in framework state is invisible to review and dies
with the laptop; configuration hidden in state is neither diffable nor
reviewable. Naming the class first makes the home obvious.

Citations: inception REQ-I1.5 · inception D-8 · custom-spec-location
REQ-G1.4 · custom-spec-location D-1, D-4, D-6, D-12, D-13, D-18, D-20.

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

One class-1 file lives outside the chain: the **spec-root marker**,
`planwright-spec-root.yml`, at the top of a spec root other than the default
(class 3 below). It is the root's identity (`project: <id>`, `layout: 1`),
read so that a mistyped `spec_root` pointer is refused rather than resolved to
an empty root. `scripts/resolve-root.sh spec --init` writes it once at the
human's request and never replaces it; it is committed wherever the root is
committed (custom-spec-location D-4).

### 2. Framework runtime state

Framework-authored, machine-local, derived or reconstructible. Registries,
telemetry, dispatch markers, locks, queues, and cross-repo drops.

**Home:** the machine-local plugin data directory, `CLAUDE_PLUGIN_DATA`.

Never committed, never inside a work repo's tree, and never the source of
truth for anything a human owns. State every worktree of one repository must
share, and no other clone may see (the flight lock, the dispatch markers),
lives under that repository's common git directory instead: outside every
working tree, never tracked, and gone with the clone. The load-bearing property
is that it must be **losable**: every consumer of runtime state carries a
rebuild path — the reconcile sweep rebuilds progress state from branches, PRs,
and commit trailers; a venture registry rebuilds by scanning the ventures
root. If losing a piece of state would lose information, it is not runtime
state, and it is in the wrong class.

### 3. User work products

What the human owns, and what they would keep if planwright disappeared
tomorrow. Spec bundles, inception bundles and their exports, observation
fragments, the artifacts a run produces.

**Home:** a location the human owns. Spec bundles and the observations
accumulator live under the **spec root**: `<root>/<name>/` for a bundle and
`<root>/_observations/` for the accumulator, where the root is `specs/` in the
work repository unless the `spec_root` option names another directory
(`scripts/resolve-root.sh spec` resolves it; `spec-format`, *Overview*). The
inception bundle lives in the venture repo.

Plain text and readable without the framework, in every posture below; a work
product that can only be read through planwright's own tooling has failed this
class. **Committed** in the two git postures: the commit is the review surface
and the history. In `plain` there is no git to commit to, and the files are the
whole record.

**The posture ladder.** A spec root's posture is its git relationship to the
work repository (the repository whose code the tasks change), derived by the
resolver from repository identity (`resolve-root.sh spec --posture`) and never
declared:

| Posture | Where the root lies | What authoring does there |
| --- | --- | --- |
| `same-repo` (recommended; the default root is always here) | in the work repository, any worktree of it included | commits bundles on the spec branch and opens the spec PR in the work repository |
| `separate-repo` (for a shared holder) | in a **holder**, a second git repository holding one root per project it serves | the spec branch and worktree, the bundle and consume commits, and the spec PR target the holder; task branches, task PRs, and commit trailers stay in the work repository |
| `plain` (supported) | in no git repository | writes the files and skips every commit, push, and PR step, naming each skipped step in the handoff; no guard runs |

Task state derives from the work repository's git in every posture, and a
root's posture never blocks a dispatch. In `separate-repo` and `plain`, a
halting execution skill's Awaiting-input and Deferred writes land as
uncommitted files in the store, each named in the handoff
(custom-spec-location D-6, D-12, D-13).

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
the class-3 home — not in `CLAUDE_PLUGIN_DATA`.

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
(inception D-8): it is the sanctioned cross-repo state home today. The
cross-repo routing effort D-8 waited on has revived as custom-spec-location,
whose named observation targets write a fragment into another project's
accumulator on the same machine (custom-spec-location D-18), and the interim
home re-anchors there. The three-class split itself is not interim; only the
current address of class 2 is.
