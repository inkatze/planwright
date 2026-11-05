# Didactic authoring — Requirements

**Status:** Draft
**Last reviewed:** 2026-11-04
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

Spec drafting and kickoff are where the operator meets planwright's densest
material, and they still read as heavy and cryptic. The operator's words: "spec
drafting and kickoff was never as didactic as I hope they would … it kind of
works but it's too heavy for an operator". What weighs, in the operator's own
selection: too much per message, a start pitched too advanced, no clear
statement of what is being asked, and crypticness. The number of steps is not
the complaint.

The teaching rules already exist (`interaction-style`, `kickoff-dialogue`, from
`operator-dialogue`), shipped twice, and did not hold: the kickoff skill still
tells the agent to "probe edge cases and gaps Socratically", every session
guesses the operator's level from scratch and starts high, and nothing checks
what a session actually shows the operator. This spec makes `/spec-draft`,
`/spec-kickoff`, and mission control's relay of them light by construction for
every operator, newcomer to expert: skill wording that teaches where the agent
acts, a remembered per-machine operator level that starts plain, a live
mechanical check on every question before the operator sees it, and a relay
that passes questions through and steers a cryptic one back. It is a mechanism
and instantiation deliverable under the existing doctrine, not new doctrine
(D-1), and a new bundle rather than a third extension of `operator-dialogue`
(D-2).

## Scope

### In scope

- Rewording the operator-facing steps of `/spec-kickoff` and `/spec-draft` so
  each tells the agent to teach (what a rule does today, what changes, what the
  operator would notice) and then ask one question; a plain first turn; a
  consequence-first walk when the operator authored the bundle.
- A remembered operator level: start plain, deepen on demonstrated uptake,
  stored on the machine outside every repository, adjustable by the operator in
  plain words.
- A live question check on every question asked in a session where the
  planwright plugin is enabled, with a config switch, failing open and never
  stalling a session.
- Mission control's relay of drafting and kickoff questions: pass through
  unchanged, steer a still-cryptic question back to its session.
- A static wording check over the two authoring skills, run by `mise run check`.
- The two narrow doctrine repairs the above needs (the stored-level clause and
  the per-pass question ceiling).

### Out of scope

- Shortening the walk or removing kickoff or drafting steps: the operator did
  not name step count as the weight (drafting-session decision (2026-11-04)).
- Any weakening of the sign-off record, the content anchor, the lens pass, the
  human gates, or what any artifact records: only what the operator is shown
  changes. Permanent.
- Mission control rewriting a relayed question itself.
- `operator-dialogue`'s parked work (its eval rework and acceptance rating);
  this spec neither absorbs nor blocks on it.
- New interaction doctrine principles beyond the two repairs named above.
- Rewording other skills' prose; the live check reaches their questions, their
  wording stays their own specs' work.

## REQ-A — Plain by construction

- **REQ-A1.1** Every operator-facing step instruction in `/spec-kickoff` and
  `/spec-draft` SHALL state a teaching action (what the rule or section does,
  what changes, what the operator would notice) followed by at most one
  question, and SHALL NOT instruct the agent with an audit verb (probe,
  interrogate, quiz, or "Socratically") at the operator.
  *(Cites: D-8; obs:6591d9b1, obs:5f82af96.)*
- **REQ-A1.2** The first operator-facing turn of a drafting or kickoff session
  SHALL state the situation, the problem, and a recommendation in plain
  language, SHALL carry no internal identifier, and SHALL NOT be a fork between
  readings of a rule.
  *(Cites: D-8; obs:15c75f4f, obs:662e905a.)*
- **REQ-A1.3** Every operator-facing turn SHALL lead with plain language;
  internal identifiers (requirement, decision, task, and observation IDs,
  anchors, lens names) SHALL appear only after the plain statement, where
  traceability needs them.
  *(Cites: D-8; obs:c67835a9, obs:2b4ede06.)*
- **REQ-A1.4** Every question SHALL say what is being decided, why it matters
  to the operator, and what each answer would change.
  *(Cites: D-8; the invocation seed (Sources).)*
- **REQ-A1.5** When the operator authored the bundle being kicked off, the walk
  SHALL teach consequences (what behaves differently once the spec ships, and
  who notices) instead of presenting gaps in the spec as rulings for the
  operator to make.
  *(Cites: D-8; obs:5f82af96.)*
- **REQ-A1.6** A drafting or kickoff turn SHALL carry one question, or one
  cluster of genuinely coupled questions said to be coupled; a per-pass
  question ceiling SHALL NOT be read or written as a per-turn budget.
  *(Cites: D-8, D-9; obs:5f82af96.)*
- **REQ-A1.7** A static check run by `mise run check` SHALL fail when an
  operator-facing step of either authoring skill carries an audit verb this
  spec bans.
  *(Cites: D-8; obs:6591d9b1.)*

## REQ-B — The operator's level

- **REQ-B1.1** With no stored level, a drafting or kickoff session SHALL start
  at the plain level.
  *(Cites: D-3; obs:662e905a.)*
- **REQ-B1.2** The session SHALL deepen explanation per concept only as the
  operator's answers demonstrate they hold it, and SHALL fall back to plain on a
  confusion signal, carrying `operator-dialogue` D-4's per-concept fade.
  *(Cites: D-3; operator-dialogue D-4 (Sources).)*
- **REQ-B1.3** The operator's level SHALL be remembered across sessions on the
  machine, as framework runtime state outside every repository, read at session
  start and updated at session end.
  *(Cites: D-3; drafting-session decision (2026-11-04).)*
- **REQ-B1.4** The operator SHALL be able to ask in plain words for simpler or
  more detailed explanation at any turn; the change SHALL take effect from the
  next turn and SHALL be remembered.
  *(Cites: D-3.)*
- **REQ-B1.5** The stored level SHALL hold only a coarse level and the concepts
  the operator demonstrated, never transcript text, answers, or secrets; a
  missing, unreadable, or malformed store SHALL start the session plain with no
  error shown to the operator.
  *(Cites: D-3; storage-classes (Sources).)*

## REQ-C — The live question check

- **REQ-C1.1** Every question asked through the question tool in a session
  with the planwright plugin enabled SHALL be checked before the operator sees
  it, and a failing question SHALL be returned to the session with a plain
  reason naming the rule it failed and the fix.
  *(Cites: D-4, D-5.)*
- **REQ-C1.2** A question SHALL fail the check when its question text or an
  option label carries an internal identifier, when its question text exceeds
  the configured length, or when an option lacks a description of its action
  and consequence.
  *(Cites: D-4; obs:c67835a9, obs:15c75f4f.)*
- **REQ-C1.3** The length limits SHALL be configuration with core defaults, and
  one configuration switch, on by default, SHALL turn the check off.
  *(Cites: D-5; customization-boundary (Sources).)*
- **REQ-C1.4** The check SHALL fail open: malformed hook input, a missing
  dependency, or an internal error SHALL let the question through.
  *(Cites: D-6.)*
- **REQ-C1.5** The check SHALL never stall a session: after the configured
  number of consecutive returns in one session, the next question SHALL pass
  with a note to the session that the check may have misfired.
  *(Cites: D-6.)*
- **REQ-C1.6** The check SHALL treat the question payload as untrusted data:
  it SHALL NOT evaluate, execute, or interpolate payload text into a command.
  *(Cites: D-4; security-posture (Sources).)*

## REQ-D — Mission control's relay

- **REQ-D1.1** Mission control SHALL relay a question raised by a drafting or
  kickoff session it launched to the operator unchanged, adding only which
  session it came from and how far along that session is.
  *(Cites: D-7; drafting-session decision (2026-11-04).)*
- **REQ-D1.2** When a relayed question still reads as cryptic or heavy,
  mission control SHALL steer it back to its session with what to change, and
  SHALL NOT rewrite it itself.
  *(Cites: D-7; drafting-session decision (2026-11-04).)*
- **REQ-D1.3** The relay rules SHALL cover drafting sessions as well as
  kickoff sessions.
  *(Cites: D-7.)*

## REQ-E — Nothing weakens

- **REQ-E1.1** No change under this spec SHALL remove or weaken the sign-off
  record, the content anchor, the lens pass, a human gate, or any content an
  artifact records; the changes govern operator-facing turns only.
  *(Cites: D-1; operator-dialogue (Sources).)*
- **REQ-E1.2** Every doctrine and skill-prose change under this spec SHALL pass
  `check:instructions`, and the two authoring skills' charged instruction
  closure SHALL NOT grow.
  *(Cites: D-9; instruction-headroom (Sources).)*

## Changelog

- 2026-11-04 — Drafted (Status Draft) via `/spec-draft`, relayed by mission
  control. Fold-detection found `operator-dialogue` owning the domain; the
  operator chose a new bundle (D-2).

## Sources

- **The invocation seed** — the operator, 2026-11-04, relayed by mission
  control: "spec drafting and kickoff was never as didactic as I hope they
  would :( it kind of works but it's too heavy for an operator", and "when spec
  draft and kickoff starts getting too criptic or yourself even I expect you to
  correct and work on permanent fixes". *Pinned altitude claims:* "never as
  didactic as I hope" (a recurring gap the shipped doctrine did not close) and
  "permanent fixes" (a structural fix, not a one-session correction); both
  resolved in D-1.
- **The drafting-kickoff-too-heavy fragment** — the observation recorded on PR
  #826 (UID c52287be), not yet on main at drafting; to be consumed by this spec
  once that PR merges.
- **obs:6591d9b1** — skill drift: the kickoff walk still says "probe edge cases
  and gaps Socratically", contradicting the didactic doctrine.
- **obs:5f82af96** — kickoff auditor-mode root cause: audit verbs in the skill
  body, no rule for an operator-authored bundle, and the five-per-pass ceiling
  read as a per-turn budget.
- **obs:15c75f4f** — the first kickoff question carried requirement IDs; the
  operator could not answer it.
- **obs:662e905a** — the opening pitch started too high because nothing probed
  the operator's level first.
- **obs:c67835a9** — the operator disengaged from a wall of requirement and
  decision IDs at kickoff.
- **obs:2b4ede06** — kickoff turns packed several groups and asks together in
  ID-heavy prose.
- **operator-dialogue** — the bundle owning the interaction disciplines and the
  turn/artifact arbitration this spec instantiates; its D-4 (teach the frontier
  and fade) is carried here.
- **interaction-style** and **kickoff-dialogue** — the doctrine docs governing
  attended turns and the kickoff walk.
- **storage-classes** — the doctrine placing framework runtime state in the
  machine-local plugin data directory.
- **customization-boundary** — the capability-in-core, value-in-config call.
- **security-posture** — the untrusted-input rule for hook payloads.
- **instruction-headroom** — the bundle owning the instruction budget and
  `check:instructions`.
- **research: Claude Code hooks reference** (code.claude.com/docs/en/hooks) —
  a `PreToolUse` matcher on a tool name, and a deny decision whose reason is
  shown to the model.
