# Anchor integrity — Design

**Status:** Draft
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision minted in this bundle.

## Decision log

### D-1: Mixed-altitude deliverable — policy as doctrine, enforcement as mechanism  (N)

**Decision:** Anchor integrity is a framework-level doctrine concern (who
may write anchor entries, when re-anchors happen, what authors may claim in
anchored prose, what frame the gate compares against) instantiated by repo
mechanisms (the hash-scope change, the re-anchor sweep, the CI guard, the
command form). The policy half lands as amendments to
`doctrine/spec-format.md` (the anchor's existing normative home); the
enforcement half lands as scripts, CI wiring, and skill-prose changes that
cite the doctrine.

**Alternatives considered:**
- Pure mechanism fix (patch `spec-anchor.sh`, move on). Rejected because:
  the process-side gap recurred three times across different skill families;
  it is a writer-policy gap no script change closes.
- A new standalone doctrine doc for anchor integrity. Rejected because:
  the meta-spec already owns anchors, sign-off records, and the amendment
  ritual; a second home would split one contract across two docs.

**Chosen because:** the pinned altitude claims (the mission's "gaps on both
the write side and the process side"; line 61's "systemic across every
skill that edits a spec bundle post-activation") name a cross-skill
contract problem, and cross-skill contracts live in doctrine, with
mechanisms citing them. This is the trigger-scoped altitude record
resolving those claims before mechanism design.

### D-2: Exclude exactly the header-block Status line from the per-file digests  (N)

**Decision:** The v1 per-file digest for `requirements.md`, `design.md`,
and `test-spec.md` is computed over the file content minus the header-block
`**Status:**` line, with the exclusion bounded to the header block as the
meta-spec defines it. The exclusion is universal: the digest is defined
once, in the meta-spec's version-1 body, and inherited unchanged by later
format versions, so the tool parses no format-version; v1's lifecycle
Status writes are the motivating failure. The exclusion is anchored to
the single leading header block and fails closed on a malformed,
duplicated, or unterminated header rather than silently hashing the
whole file. The `tasks.md` definition-content extraction is
unchanged (its header and annotations are already excluded). The anchor
tool's header comment is corrected to describe what the code does.

**Alternatives considered:**
- Migrate every v1 bundle to format-version 2 instead (v2 stores no flip,
  removing the cause). Rejected because: the meta-spec promises v1 bundles
  stay valid indefinitely, forced migration cannot reach adopter repos, and
  invariant-tasks deliberately made migration opt-in.
- Exclude the whole header block from the digest. Rejected because:
  `Format-version:` and `Superseded-by:` are meaning-bearing; excluding
  them would let a format migration or a supersession slip past the gate.
- Leave v1 as is and document the false-halt workaround. Rejected because:
  the failure fired live and recurs on every later-task dispatch of every
  multi-task v1 spec; a documented false halt is still a false halt.

**Chosen because:** the minimal exclusion makes both the stored Draft→Ready
flip and the derived Ready↔Active flip (and its file mirrors)
anchor-invariant — the contract the tool's header has claimed all along —
with the smallest possible change to what "meaning" hashes to.

### D-3: The hash-scope change lands with a coordinated expression-only re-anchor sweep  (N)

**Decision:** The digest change and a classify-and-route re-anchor sweep
land together in one PR: every briefed non-Draft, non-terminal bundle
whose latest anchor fails to recompute under the amended semantics —
pre-existing staleness included (a kickoff dry run 2026-07-17 found the
Done bundles' anchors stale from post-sign-off Status flips), and
interim whole-file-form entries included (converted to a current form) —
gets a marked `Class: expression-only` re-anchor entry, with a one-shot
landing proof that every in-scope bundle recomputes equal afterwards.
Each bundle's anchored-content delta since its recorded entry (diffed
from the commit that introduced the entry's anchor line) is classified
first: lifecycle-only or expression-only deltas get the machine entry
citing the delta that actually moved the anchor; a meaning-class or
unresolvable delta routes to the re-review ritual the bundle's status
admits (delta re-walkthrough for Ready/Active, the reopen cycle for
Done), parking that bundle — its gate stays failed closed — rather than
blocking the sweep. A park is visible: the sweep writes a live
`anchor re-review pending` bullet into that bundle's `## Awaiting input`,
the guard and the landing proof report the marked bundle as a
known-parked notice rather than an error (so one routed bundle cannot
red the merge gate repo-wide), and the re-review's sign-off removes the
bullet. Classifications and the proof are re-verified at the
sweep PR's merge SHA, so no unreviewed meaning edit is laundered. Adopter v1 bundles cannot be swept
from here, so the remedy (the same one-time self-re-anchor entry) is named
in adopter docs and in the freshness gate's v1 halt guidance.

**Alternatives considered:**
- Lazy re-anchor at each bundle's next dispatch. Rejected because: the next
  dispatch is exactly where the false halt fires; lazy repair is the
  failure mode, not a fix.
- Grandfather pre-change anchors (gate accepts either hash semantics).
  Rejected because: two live anchor semantics forever, and the gate could
  no longer prove which content a recorded anchor covers.

**Chosen because:** format-grammar REQ-C1.4 already establishes the
discipline — any parser change that moves a shipped bundle's anchor lands
with the paired sweep — and an atomic landing keeps the REQ-D guard green
from its first run.

### D-4: State the committed-main frame for the v1 gate arm  (N)

**Decision:** The meta-spec's execution-validity prose states: for a v1
bundle, both reads are taken against a single pinned commit of the main
view; when the recompute's only divergence from that pinned view within
anchored content is confined to header `**Status:**` lines carrying
sanctioned status values, across any subset of the four files — the
shape the single-writer derived mirror produces, accepted by shape
because the gate cannot attribute a divergence to a writer — the gate
compares against the pinned committed view; any other divergence
(committed or not) halts exactly as today.

**Alternatives considered:**
- Leave the frame implicit now that D-2 removes the known trigger.
  Rejected because: two live dispatches had to re-derive the frame under
  pressure from first principles; recording an exercised resolution is
  cheap, and transient sibling-writer states can still exist mid-reconcile.
- Reframe all recomputes to committed main. Rejected because: an
  uncommitted meaning edit in the working tree must keep halting the gate;
  "committed or not" is correct for meaning deltas.

**Chosen because:** it records the resolution actually used (invariant-tasks
Tasks 2 and 3) as doctrine, scoped narrowly to the one sanctioned derived
write, so the two gate framings can no longer diverge for v1 bundles.

### D-5: Re-anchor pathway — pre-flight detection, expression-only self-ritual, meaning-class routing  (N)

**Decision:** Every planwright-shipped skill that edits signed bundles
(`/self-review`, `/polish`, and `/execute-task`'s convergence step) gains
three behaviors: (1) a stale-anchor pre-flight before any bundle edit,
surfacing a mismatch rather than editing on top of it; (2) for
expression-only edits, the full sanctioned ritual in the same change — the
dated Changelog entry plus the marked `Class: expression-only`
self-re-anchor entry citing it; (3) refusal of meaning-class edits, routed
to `/spec-kickoff`. `/spec-kickoff` additionally recomputes the anchor as
the terminal pre-push step whenever anchored content changed after the
sign-off record was written. Failure ordering: the pre-flight blocks on
absent or unparseable entries and on recompute failures exactly as on
mismatches; the expression-only ritual's edit, Changelog entry, and
anchor entry land in one commit; the terminal recompute covers
expression-only edits only (a meaning-class post-sign-off edit re-enters
the sign-off flow) and halts the push if it fails. The doctrine statement of this contract binds
any act-on-findings skill, including external ones (the panel and copilot
families live outside this repo); those follow via their own repos.

**Alternatives considered:**
- Refuse all signed-bundle edits and route everything to `/spec-kickoff`.
  Rejected because: doctrine already sanctions machine-written
  expression-only self-re-anchors; a kickoff round-trip for a typo adds
  ceremony without adding safety.
- Detect-and-surface only (no skill ever writes the ritual). Rejected
  because: the recurring failure is precisely "edit applied, ritual
  skipped"; detection without a sanctioned completion path leaves the gap
  open by design.

**Chosen because:** fork decision, drafting session 2026-07-17. It closes
the recurrence while keeping meaning-class anchor writership exactly where
the meta-spec put it: `/spec-kickoff` alone.

### D-6: One guard script, two wirings — normative CI check, best-effort pre-commit mirror  (N)

**Decision:** One shared guard script asserts, for every non-Draft bundle
with a kickoff brief: the brief's most recent anchor entry parses, uses a
sanctioned command form, and recomputes equal against the checked tree;
and an edit to anchored content since the baseline ref without a dated
Changelog entry in that bundle is an error. Draft and terminal-state
(Retired, Superseded) bundles are skipped with a notice: terminal
bundles are frozen history whose briefs never grow machine entries. A
non-Draft, non-terminal bundle without a brief is an error naming the
repair remedy — brief removal must not disable the check. A bundle
carrying the live `anchor re-review pending` park marker (D-3) is a
known-parked notice, not an error. The script
wires into `mise run check` (the normative, merge-gating form that runs
in CI, whole-corpus) and into a best-effort lefthook pre-commit mirror
scoped to commits that stage `specs/**` content (repo-local convenience,
fails at commit time; lefthook is net-new hook infrastructure this spec
introduces — the repo has none today, obs line 113 — and an unscoped
mirror would tax every commit with the measured ~1.5–2.5s full-corpus
cost). The guard executes recorded commands per REQ-D1.5
(parse-validate-then-invoke, sanitized echo, validated baseline).
Residual risk, accepted: writership of a machine expression-only entry
is auditable, not mechanically verifiable — the guard checks form and
recompute, and a forged-but-well-formed entry is caught by human review
of the PR that carries it (the meta-spec's
misclassification-is-one-revert-away rule).

**Alternatives considered:**
- Pre-commit only. Rejected because: invisible to CI, to adopters without
  lefthook, and to any commit path that bypasses hooks; enforcement would
  be advisory.
- CI only. Rejected because: the author hears about drift one push later
  than a commit hook would tell them, and the staged-path-scoped mirror
  is cheap on the common case (it runs only when spec content is
  staged).
- Fold into `spec-validate.sh`. Rejected because: the validator is
  bundle-scoped; this guard is a cross-artifact brief↔bundle comparison
  with different skip semantics. They can run side by side in the same
  check task.

**Chosen because:** fork decision, drafting session 2026-07-17. The merge
gate is where drift must fail closed; the commit hook is where the author
wants to hear about it first.

### D-7: A third sanctioned command form — logical name resolved through the root chain  (N)

**Decision:** The meta-spec's sanctioned-command list gains a third form:
the logical `spec-anchor.sh <spec-dir>`, resolved through the documented
core root chain (explicit `PLANWRIGHT_ROOT` override → `CLAUDE_PLUGIN_ROOT`
plugin delivery → writer delivery under the Claude dir → self-location
beside the resolving script). Gate consumers accept all sanctioned forms.
New entries written in repos without a repo-root `scripts/` record the
logical form; the repo-relative canonical form stays sanctioned and
preferred where `scripts/spec-anchor.sh` exists, so no existing entry ever
invalidates.

**Alternatives considered:**
- Record an env-literal form such as
  `"$PLANWRIGHT_ROOT/scripts/spec-anchor.sh" <spec-dir>`. Rejected because:
  a stale or unset env var makes the recorded command silently resolve to
  the wrong version or nothing — a live failure mode observed with a stale
  `PLANWRIGHT_ROOT` during this very drafting session.
- Writer-install `spec-anchor.sh` into adopter repos so the repo-relative
  form always resolves. Rejected because: it grows the writer/packaging
  surface and creates per-repo copies that drift from the plugin version.

**Chosen because:** fork decision, drafting session 2026-07-17. It reuses
the proven rule-doc resolution convention with zero new infrastructure, and
recomputability becomes a property of the delivery mode, not of one repo
layout. Gate consumers resolve the tool from the checked tree's canonical
script where present, falling back to the chain only where absent; a
sanctioned form that resolves to nothing halts the gate as
absent-anchor-class (fail closed). A stale explicit override remains an
operator-owned risk (kickoff risk register row 2).

### D-8: Decided-rule statements over enumerated counts in anchored prose  (N)

**Decision:** The meta-spec's authoring guidance (a guidance refinement, no
format-version bump) directs anchored deliverable prose to state decided
rules ("every doctrine-relative link of this class is a violation") rather
than enumerated counts or corpus lists ("the sole real violation is X";
"the frozen corpus is these N fixtures") whose truth depends on surfaces
outside the bundle. Where an enumeration is unavoidable it follows the
existing cite-don't-copy convention or carries its own cross-check.
`/spec-draft` (at drafting) and `/spec-kickoff` (at sign-off) gain an
enumeration cross-check step: flag enumerations in the bundle and verify
each against the surface it enumerates, or convert it to a decided rule.

**Alternatives considered:**
- Validator-enforced enumeration detection. Rejected because: recognizing
  an enumerated claim is semantic, not structural; a grep-shaped rule would
  be a false-positive machine.
- Kickoff-only cross-check. Rejected because: the drafting session is where
  the count is born; catching it at sign-off wastes an authoring round-trip.

**Chosen because:** the class fired twice (output-hygiene Task 5's stale
"sole violation" premise; the frozen-corpus enumeration that omitted real
fixtures), both as anchored prose that rotted when a surface outside the
bundle changed. Decided rules age with the decision, not with the corpus.

## Cross-cutting concerns

- **Dependency on format-grammar (Ready).** format-grammar owns the shared
  extraction library, fence-awareness, and the meta-spec header-block scope
  definition; its REQ-C1.4 owns the sweep discipline. This bundle's Task 2
  implements the D-2 exclusion inside whatever extraction home has landed
  at execution time (the shared lib if the re-point has shipped, else
  `spec-anchor.sh` directly, with a reconcile note), and Task 1's
  header-block bound defers to format-grammar's definition where it has
  landed, defining the bound inline otherwise. Neither bundle edits the
  other's deliverables.
- **Other anchor-entry writers.** `scripts/migrate-format-version.sh`
  writes anchor entries and recomputes via `spec-anchor.sh`, so it inherits
  D-2 and D-7 automatically; Task 2 verifies its written command form stays
  sanctioned.
- **Sequencing.** Doctrine first (Task 1), then mechanism (Tasks 2–4) in
  dependency order, with the guard (Task 4) dispatched as early as its
  dependencies allow per the guard-infrastructure-first selection
  preference; skill-prose tasks (5–7) depend only on Task 1 and can run in
  parallel with the mechanism chain.
