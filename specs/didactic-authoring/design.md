# Didactic authoring — Design

**Status:** Draft
**Last reviewed:** 2026-11-04
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` new; `C, <spec> D-<n>` carried from another bundle.

## Decision log

### D-1: Altitude: mechanism and instantiation under the existing doctrine  (N)

**Decision:** The deliverable sits at the mechanism and instantiation rungs:
skill wording where the agent acts, a mechanical check on every question, a
machine-local level store, and a relay rule. Doctrine changes are limited to two
repairs where current doctrine text contradicts the fix (D-3, D-9). Both pinned
seed claims (Sources: the invocation seed) resolve here: "never as didactic as I
hope" names a gap the doctrine already covers but no mechanism enforces, and
"permanent fixes" asks for a fix that holds without anyone remembering it.

**Alternatives considered:**
- A new or rewritten interaction doctrine. Rejected because: the doctrine
  shipped twice (`operator-dialogue`'s first pass and its extension) and the
  failure recurred; obs:5f82af96 traces it to concrete skill verbs beating a
  cited discipline, so more doctrine adds words where words already lost.
- Wording fixes alone. Rejected because: that is what faded twice; the
  autopilot reflex's step 5 prefers a mechanical tool over an instruction an
  LLM follows, because a comparator cannot be pencil-whipped.

**Chosen because:** the gap is enforcement, not principle. A mechanical check
plus wording that names the right action at the point of action is the
smallest change that does not depend on the agent remembering a doctrine.

### D-2: A new bundle, not a third extension of `operator-dialogue`  (N)

**Decision:** Draft `didactic-authoring` as its own bundle that cites
`operator-dialogue`'s disciplines and leaves that bundle's parked items in place.

**Alternatives considered:**
- Extend `operator-dialogue`. Rejected because: fold-detection's size trigger
  fires (that bundle has already been extended once and is past what a reader
  holds in their head), and a delta kickoff inside it would be exactly the heavy walk this
  spec removes. Recommended and declined at drafting.

**Chosen because:** the operator chose it at drafting (drafting-session decision
(2026-11-04)); a small bundle is light to read and to kick off, and the domain
link is kept by citation.

### D-3: Start plain, remember the level per machine  (C, operator-dialogue D-4)

**Decision:** Every drafting or kickoff session with no stored level starts
plain. Within a session, explanation deepens per concept on demonstrated uptake
and falls back on confusion (`operator-dialogue` D-4, carried). At session end
the session writes a small store under the machine-local plugin data directory:
a coarse level and the concepts the operator demonstrated, nothing else. The
next session starts from it. "Simpler" or "more detail" from the operator moves
the level immediately and is stored. `kickoff-dialogue`'s sentence that the
estimate "is not a stored profile" is repaired to admit this store as the
estimate's starting point; the in-session estimate stays lightweight.

**Alternatives considered:**
- Ask the operator to pick a level up front. Rejected because: `operator-dialogue`
  D-4 already rejected it as a crude one-shot setting, and it is a setup
  question the operator should not have to answer.
- Start plain with no memory. Rejected because: an expert re-earns depth every
  session, which is its own kind of heavy.
- Store it in the repository config. Rejected because: the level is
  framework-authored and derived, which `storage-classes` puts in runtime
  state, and it is per operator, not per repository.

**Chosen because:** the operator chose it at drafting; starting plain fixes the
recurring too-high opening (obs:662e905a), and the store is losable by design:
losing it only means starting plain again.

### D-4: The live question check is a `PreToolUse` hook on the question tool  (N)

**Decision:** A new script wired in `hooks/hooks.json` as a `PreToolUse` hook
matching the question tool (`AskUserQuestion`) reads the tool input, checks each question, and on a
failure returns a deny decision whose reason, in plain words, names the rule
failed and the fix; the session rewrites and asks again. The rules are
structural only: no internal identifier in the question text or option labels
(identifiers may appear in option descriptions and previews), question text
within the configured length, and every option carrying a description. The
script parses the payload with `jq` and never evaluates it. Prose quality
beyond structure stays a human rating (REQ-A1.4's manual entry). The tool-input
shape is probed and recorded by Task 1 before the rules are written against it.

**Alternatives considered:**
- A pre-merge simulated-session eval. Rejected because: it catches regressions
  in skill prose, not a bad question in a live session, and costs a run per
  change; `operator-dialogue` keeps that harness.
- A `Stop` hook grading the whole turn. Rejected because: it fires after the
  operator has already seen the turn.
- Mission control checks only. Rejected because: it reaches relayed sessions,
  not a directly attended one.

**Chosen because:** the operator chose a live check at drafting; the hooks
reference (Sources) confirms a tool-name matcher and a deny whose reason the
model sees, which is the forcing function the autopilot reflex asks for.

### D-5: Check scope: every question in a plugin-enabled session, on by default  (N)

**Decision:** The hook runs on every question asked in any session where the
planwright plugin is enabled. A core config knob (default on) turns it off, and
the length limits are knobs with core defaults, overridable through the usual
config chain.

**Alternatives considered:**
- Drafting and kickoff sessions only. Rejected because: the same plain-language
  rules govern every attended surface, and a hook has no reliable way to know
  which skill is running.
- Warn without returning the question. Rejected because: a cryptic question
  would still reach the operator.

**Chosen because:** the operator chose it at drafting. Per
`customization-boundary`, the capability lands in core with a
default-preserving switch and tunable values; the operator explicitly chose
default on.

### D-6: The check fails open and caps consecutive returns  (N)

**Decision:** Any malformed input, missing dependency, or internal error lets
the question through. The hook counts consecutive returns per session in
runtime state; once the configured cap is reached the next question passes with
a note to the session that the check may have misfired, and the count resets on
any passing question.

**Alternatives considered:**
- Fail closed. Rejected because: this is a usability guard, not a security
  boundary; failing closed would trade a cryptic question for a stalled
  session.
- No cap. Rejected because: a misfiring rule could loop a session forever.

**Chosen because:** a stall is worse for the operator than one heavy question.

### D-7: Mission control passes questions through and steers back  (N)

**Decision:** Mission control relays a drafting or kickoff question unchanged,
adding only the source session and its progress. When a relayed question still
reads as cryptic or heavy, mission control steers it back to its session with
what to change, never rewriting it. Drafting sessions are covered, not only
kickoffs.

**Alternatives considered:**
- Mission control rewrites relayed questions. Rejected because: a rewrite can
  drift from what the session meant, and the operator's answers must stay tied
  to the session's actual question.

**Chosen because:** the operator chose it at drafting and added "mission
control steers when necessary" (drafting-session decision (2026-11-04)); this
drafting session was itself steered back once and the rewrite passed.

### D-8: Teaching verbs at the point of action  (N)

**Decision:** Each operator-facing step in both authoring skills names the
teaching action directly (what the section does today, what changes, what the
operator would notice, then one question) in place of audit verbs; the first
turn is plain situation, problem and recommendation with no identifiers and no
rule-reading fork; when the operator authored the bundle, the walk teaches
consequences rather than posing gaps as rulings. A static check in
`mise run check` owns the banned-verb list and fails on any operator-facing
step carrying one.

**Alternatives considered:**
- Keep the steps and add a pointer to the doctrine. Rejected because:
  obs:5f82af96 shows a concrete verb beats a cited discipline.

**Chosen because:** it removes the cause obs:6591d9b1 and obs:5f82af96 name,
and the static check keeps it from returning.

### D-9: One question per turn; the instruction budget does not grow  (N)

**Decision:** The "at most five per pass" ceiling in `interaction-style` and
`kickoff-dialogue` is reworded so it reads as a session-pass bound beside the
one-question-per-turn rule, never as a per-turn budget. Every prose change is
word-neutral or shrinking against `check:instructions`, trimming the replaced
wording rather than adding beside it.

**Alternatives considered:**
- Drop the per-pass ceiling. Rejected because: it still bounds a long
  interview; only its reading as a per-turn allowance is the defect.
- Grow the skills' instruction closure. Rejected because: the budget is
  owned by `instruction-headroom` and is already tight.

**Chosen because:** obs:5f82af96 names the ceiling's misreading as one of three
root causes, and a heavier skill would undo the point of this spec.

## Cross-cutting concerns

- **Decision domains touched.** Data at rest (the level store: runtime state,
  coarse, no transcript or secrets, D-3); integration surface (the Claude Code
  hook contract, version-sensitive, probed by Task 1, D-4); security posture
  (untrusted payload, fail-open declared as a usability guard, D-6). No
  authentication, authorization, or data-model decision beyond the store's
  shape.
- **Cross-spec edits.** Task 5 edits `skills/mission-control/SKILL.md`, owned
  by `mission-control`; Task 3 edits doctrine owned by `operator-dialogue`.
  Each PR names the owning spec.
