# Refactor Instinct

Guiding principle: **small, continuous refactors prevent large, breaking
ones.** Favor composable code shaped by frequent small cleanups over big
periodic rewrites. How to act on the instinct depends on the mode the agent
is in: writing code, or reviewing it.

Citations: REQ-D1.3.

## Tool-grounded over vibes (both modes)

Before claiming code needs a refactor, check what the repository already
runs: linters, formatters, type checkers, static analyzers, complexity and
duplication meters (same discovery channels as Discovery Rigor). If a tool
flags it, the finding is grounded; cite the tool and rule. If no tool flags
it but something still feels wrong, that judgment is less reliable, so be
more conservative, especially in review mode. If the repository has no
relevant tooling for the language or area, prefer proposing that tooling be
added over making subjective calls.

## Implementation mode (low bar, clean as you go)

- Rename a confusing variable, extract a helper when a third caller appears,
  split a function that grew past one screen.
- Before adding to messy code, pause and either make the small cleanup
  inline, or surface the friction with a concrete proposal. Do not barrel
  through and add more mess.
- **Pre-ship self-review.** Before declaring a task done, run the project's
  linters, formatters, and type checkers locally and fix what they surface
  in the touched area, in the same change. Then walk the Discovery Rigor
  lens checklist against the new work and address what it finds. This shifts
  iteration cost from external review loops to internal ones.
- Refactor proposals during implementation should be small, scoped to the
  area being touched, and easy to accept or reject.

## Review mode (high bar)

- Only flag refactors when the change under review materially worsens
  structure: new duplication introduced, nesting deepened, an abstraction
  muddled, naming made worse. Pre-existing mess unrelated to the diff is out
  of scope.
- Anchor flags in tool output where possible. A named rule from a tool the
  project runs is grounded; "this could be cleaner" is not, and should be
  dropped.
- Prefer follow-up suggestions over blocking findings. "Consider as a
  follow-up" is usually the right framing.
- Do not propose alternative architectures, rewrites, or stylistic
  preferences unless the current shape will demonstrably cause maintenance
  pain.
- Do not invent abstractions for hypothetical future requirements. Three
  similar lines is fine; demanding a helper for them is noise.

## Proportionality

The two bars are themselves an application of the proportionality principle
(see [proportionality.md](proportionality.md)): implementation-mode cleanups
are cheap and reversible inside the change being made, so the bar is low;
review-mode flags impose work on others and reshape code outside the diff's
purpose, so the bar is high.
