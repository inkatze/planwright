# Substrate constraint profiles, as of 2026-10-18

One profile per tier of the script layer except tests-only, which the no-live-caller flag
dissolves (universal-binary REQ-A1.3) and which carries no profile. Each profile states every
field REQ-B1.2 names and is derived from two inputs, both regenerable:

- the partition, `mise run substrate:partition` (`scripts/substrate-partition.sh`), for who
  invokes each tier, its coupling profile, and its shell-mutation flags;
- the pain matrix, [`pain-matrix-2026-10-18.md`](pain-matrix-2026-10-18.md), for where the
  recorded defects fall.

The profiles are judgment applied to those inputs, written before any tier is screened. They
are recorded by hand, not generated, so a later partition or matrix is a reason to revisit
them, never a silent update.

## Rubrics

**Auditability weight** (the "Stay auditable" rule in `doctrine/security-posture.md`):

- **high**: the code decides a permission or gates a tool call with no human reading the
  call, so its rationale has to be readable before it is trusted;
- **medium**: the code acts on the adopter's repository or fleet state under a skill the
  operator is watching, so a reader reaches it only when something already went wrong;
- **low**: the code runs only on a maintainer's machine or in CI, never on an adopter's.

**Tier boundary precedent** (the Sources' distribution survey): every tool surveyed kept a
shell layer at its entry boundary, and the one capability a compiled program cannot recover
is mutating the calling shell. A tier is on the **entry side** when the host or a skill
invokes it by a literal command, so its entry point stays a shell-callable path whatever
runs behind it (REQ-E1.2 freezes those paths); it is on the **core side** when only other
scripts or maintainer tasks reach it, where the precedents moved logic into a compiled core.

## hook

- **Audience:** adopter runtime. Invoked by the plugin's hook registrations, the worker and
  tower settings profiles, and the tracked git hooks.
- **Latency budget:** no regression against the shell implementation on the same runner in
  the same harness run (REQ-B1.5, D-14). Each PreToolUse guard runs on every tool call, so
  this is the only tier with a per-call budget.
- **Correctness needs:** fail closed on any input the guard cannot parse; a wrong allow is a
  security failure and a wrong deny stalls a worker. Its matrix row is led by
  plugin-delivery (registrations that never resolve, allow rules that match literal
  prefixes), then duplicated-primitive, with lock-concurrency and parser-fragility next.
- **Platform reach:** every platform of the CI matrix (REQ-B1.4): Linux with glibc, macOS
  with its system bash 3.2 and BSD userland, Alpine with dash and busybox.
- **Auditability weight:** high. The command guards and the ready guard decide permissions
  on every call; the matrix's auditability column records offline replay of a plain hook as
  what found a root cause.
- **Delivery modes:** the marketplace copy and the `~/.claude/` writer (REQ-B1.3), plus the
  `--settings` profile delivery that wires the guard into worker and tower sessions.
- **Boundary side:** entry side. The host runs a command string, so the entry point stays a
  shell-callable path; no hook-tier script carries the shell-mutation flag.

## skill-called

- **Audience:** adopter runtime. Named by a skill body and run by the model through the Bash
  tool, by literal path.
- **Latency budget:** none per call (D-5): a skill step is a model turn, whose cost dwarfs a
  process start. The budget that binds is the spawn count on hot loops, which the
  perf-spawn-cost column records.
- **Correctness needs:** exact reads and writes of spec bundles, ledgers and fleet state:
  structured-format parsing, mutual exclusion on shared state, and a fail-closed exit on a
  malformed input. The widest matrix row: instruction-headroom, duplicated-primitive,
  plugin-delivery, parser-fragility, test-flakiness and lock-concurrency all weigh on it.
- **Platform reach:** every platform of the CI matrix, as for hook.
- **Auditability weight:** medium. The scripts change the adopter's repository and fleet
  state under a skill the operator watches; they do not decide permissions.
- **Delivery modes:** the marketplace copy and the `~/.claude/` writer.
- **Boundary side:** entry side for the path a skill names; the body behind it may sit on
  either side. Two skill-called entry points carry the shell-mutation flag today
  (`inception-validate.sh`, `resolve-steps.sh`); per the brief's risk R4 that flag must be
  clear before this tier moves.

## library

- **Audience:** adopter runtime, reached only through hook and skill-called scripts.
- **Latency budget:** none of its own: it inherits its caller's, so a library under a hook
  answers to the hook budget at the call sites a hook reaches.
- **Correctness needs:** the shared primitives the other tiers trust: advisory locks,
  sanitizers, config and format readers. Its matrix row is led by duplicated-primitive and
  lock-concurrency, the two classes where one wrong copy is wrong everywhere it is sourced.
- **Platform reach:** every platform of the CI matrix.
- **Auditability weight:** medium. It acts on adopter state but decides no permission
  itself; the guards that call it carry the high weight.
- **Delivery modes:** the marketplace copy and the `~/.claude/` writer.
- **Boundary side:** core side. Only other scripts reach it, which is where the surveyed
  precedents moved logic into a compiled core. One library script carries the
  shell-mutation flag (`config-get.sh`); a library is sourced into its caller, so that flag
  is a caller-side constraint on any substrate change.

## dev-check

- **Audience:** dev-only. Invoked by `mise.toml` tasks and the CI workflows, on a
  maintainer's machine or a runner, never on an adopter's.
- **Latency budget:** no per-call budget; the check aggregate's wall-clock is the cost that
  matters, recorded in the [cost baseline](cost-baseline-2026-10-18.md) and bounded by
  `config/test-time-budget.yml`.
- **Correctness needs:** a guard fails closed and never passes vacuously. Its matrix row is
  led by instruction-headroom (the budget guards), lint-gap and parser-fragility.
- **Platform reach:** the maintainer hosts and the CI matrix's platforms; a toolchain is
  permitted here, since REQ-B1.1 binds adopter tiers only.
- **Auditability weight:** low. It runs only where the code is already being reviewed.
- **Delivery modes:** neither. It runs from the repository checkout, not from either
  install.
- **Boundary side:** core side, outside the adopter boundary altogether, so the entry-side
  precedent does not bind it.
