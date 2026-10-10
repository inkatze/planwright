# Worker Permission Ergonomics — Requirements

**Status:** Draft
**Last reviewed:** 2026-10-10
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

Dispatched planwright workers (`/orchestrate` → `/execute-task`) flood on
permission prompts. fleet-autonomy's dispatch guard forbids launching workers
under Claude Code's `auto`/`bypassPermissions` modes — an LLM classifier in the
approval path violates the D-18 deterministic-mechanics floor (fleet-autonomy
REQ-E1.4/D-19) — so workers run `defaultMode: default` under the static
`config/worker-settings.json` allowlist. That allowlist silences plain commands
but not the command shapes `/execute-task` actually issues: plugin-script
invocations through an unexpanded shell variable
(`"$PLANWRIGHT_ROOT/scripts/x.sh"`), `for`/`while` loops, and other expansions
that Claude Code flags "cannot be statically analyzed" and offers **no
persistent-allow** for. The result is near-continuous manual approval that both
floods the tower context and strains the never-type-into-worker-input posture.

This spec closes the flood with a **deterministic PreToolUse hook** that
auto-approves an enumerated set of known-safe command shapes and defers
everything else to the normal permission flow, keeping every existing
guardrail intact: no LLM in the approval path (honors fleet-autonomy D-18), the
worker-settings `deny` block enforced verbatim (a hook "allow" can never
override Claude Code's `deny`→`ask`→`allow` precedence), and human sign-off on
the permissions artifact. It complements the hook with the root-cause cleanup —
having the dispatching skills invoke plugin scripts by resolved literal path —
so the most common worker command shape is statically approvable even when the
hook degrades. The deliverable is a **mechanism** instantiating fleet-autonomy's
existing D-18 doctrine floor, not a new doctrine gap (D-1).
*(Amended at the 2026-10-05 extension: the `deny` guarantee is asserted as an
outcome (REQ-A1.11) rather than taken from Claude Code's evaluation order, and
the hook sees the raw, unexpanded command (D-10).)*

**The 2026-10-05 extension.** The hook shipped, and an unattended fleet still
reached the operator on nearly every routine step: a replay of the Bash prompts
19 workers raised between 2026-10-02 and 2026-10-05 found the shipped guard
approving almost none of them, the hook active throughout. The residual comes
from shapes the guard never modelled (a leading `cd` into the worker's own
worktree, command substitution, writes into the worker's own temp scratch)
and from ordinary work on the worker's own unit branch that the guard, by
design, never approved. This extension makes an unattended fleet unattended for
in-scope work. A worker self-approves, deterministically and worker-side, every
command inside **one configurable self-approval policy** (read-only work, work
confined to its own unit branch and worktree, writes into its own scratch
root). Everything outside the policy reaches the operator as before, and the
reserved floor (PR merge, the ready flip, force-push, amend, rebase, pushes to
any other branch, writes outside the worktree and scratch) stays out of the
guard's reach at every policy value; the profile's fixed allow rules and the
ready-guard hook keep governing the ready flip as before. Core ships the
read-only arm only; an operator turns on the others in an overlay. The delta also closes a live false-allow the replay
work re-confirmed (an unexpanded operand smuggling `find -exec` past the
argument screens), corrects the bundle's false premise that the hook sees an
expanded command, and removes the meta-tower's subordinate session layer whose
own bookkeeping prompted under the worker profile. Its altitude is policy plus
mechanism with one doctrine clarification of what "unattended" means (D-9).

## Scope

### In scope

- A deterministic `PreToolUse` hook (portable POSIX/bash shell) that
  auto-approves a conservative, enumerated set of known-safe Bash command
  shapes issued by a dispatched worker, and defers everything else.
- The enumerated known-safe set and the every-segment-must-be-safe compound
  analysis, including recursive analysis of `fish -c "<inner>"`.
- Wiring the hook into `config/worker-settings.json` (the existing
  human-reviewed worker-permissions channel), keeping `defaultMode: default`
  and the `deny` block verbatim, scoped to worker sessions only.
- The root-cause cleanup: `/execute-task`, `/orchestrate`, and `/spec-kickoff`
  resolve the plugin/planwright root once and invoke plugin scripts by resolved
  literal absolute path.
- An adversarial test suite asserting zero false-allows and that the `deny`
  precedence holds.

- **The 2026-10-05 extension:** closing the unexpanded-operand false-allow;
  modelling a leading `cd` into the worker's own worktree, plain-literal
  variable assignments, timing verbs, and command substitution under the
  narrow argument-independent rule; the configurable self-approval policy
  (read-only, own-branch-and-worktree, scratch arms) and the floor it can never
  reach; a per-worker scratch root the launcher creates; a static read-only
  allow set shipped in the worker profile; a relaunch path that picks up a
  changed profile; the doctrine statement of what unattended means; the
  meta-tower running the single-spec step itself; plugin scripts resolving the
  values workers fetched by substitution; and the bundle's carried corrections
  (the deny-outcome assertion, the matcher's command-substitution behaviour
  pinned, the `git push -u` spelling, the profile's `_about` categories).

### Out of scope

- Claude Code's `auto` / `bypassPermissions` permission modes (rejected by
  fleet-autonomy D-19; this hook is the LLM-free alternative that reaches the
  same no-flood goal).
- The `fleet-state-home-unresolved` observation (fleet-throttle / tower-marker
  failing under a marketplace install): a fleet-governance robustness gap
  orthogonal to worker permissions, left to fleet-autonomy or its own bundle
  (considered and scoped out; see Sources, left unconsumed).
- Coverage of any tool other than Bash (the hook considers only Bash; every
  other tool defers).
- An arbitrary per-verb allowlist extension knob. *(Amended at the 2026-10-05
  extension: the drain evidence the original deferral waited for arrived, and
  the self-approval policy (REQ-F, D-12) is that knob's graduated form; the
  `tasks.md` Deferred entry was removed.)*
- Skills emitting one plain command per Bash call: a separate visual flight
  owns that skill-prose change; this bundle covers the guard, the profile, and
  the plugin scripts' own interfaces.
- Any tower-side answering of a worker's permission prompt on the tower's own
  judgment: doctrine forbids it, and a tower-side filter was refused by the
  harness's own classifier as a bypass.
- Standing-decision matching over split segments, deny-polarity standing
  decisions, and settle-route delivery: tower-comms owns the matcher; segment
  matching is deferred until a settle actually unblocks a worker (D-18).
- The shared command-guard library extraction, the awk relational lexer, and
  the guards' per-call process-spawn cost.
- `git -C <path>` and inline environment-assignment prefixes, which keep
  deferring (REQ-A1.8, REQ-A1.9).
- Claude Code's sensitive-path prompt on reads under the harness's own plugin
  directories, which a hook `allow` cannot override.
- Approving a script the worker wrote itself outside the repository's tracked
  `scripts/` and `tests/` (scratch included): executing self-written code is
  arbitrary execution and reaches the operator. Running an edited repo script
  or test stays approvable under the trusted-checkout residual (kickoff R1,
  R9); the own-branch arm's excluded paths (REQ-F1.6) keep a worker from
  planting code that git, Claude Code, or the toolchain run implicitly.

## REQ-A — The auto-approve hook

- **REQ-A1.1** A deterministic `PreToolUse` hook SHALL auto-approve a
  conservative, enumerated set of known-safe Bash command shapes issued by a
  dispatched worker and SHALL defer every other command to the normal
  permission flow; no LLM SHALL be invoked in the decision path.
  *(Cites: D-1, D-2; fleet-autonomy REQ-G1.2/D-18 (Sources).)*
- **REQ-A1.2** The hook SHALL emit only an `allow` decision or defer
  (no decision); it SHALL NEVER emit a `deny` or `ask` decision. Approval is
  upgrade-only; blocking remains the job of `permissions.deny`/`ask`.
  *(Cites: D-3.)*
- **REQ-A1.3** The hook's `allow` SHALL NOT be capable of overriding
  `permissions.deny` or `ask`; the worker-settings `deny` block (planwright's
  hard invariants) SHALL remain enforced verbatim, since Claude Code evaluates
  `deny`→`ask`→`allow` regardless of hook output.
  *(Cites: D-3; fleet-autonomy REQ-E1.4/D-19 (Sources); the grounded permission facts (Sources).)*
  **Superseded-by: REQ-A1.11** (2026-10-05) — it relied on Claude
  Code's evaluation order instead of asserting the outcome; the replacement
  asserts it, so a platform change cannot silently widen a hook `allow`.
- **REQ-A1.11** (supersedes REQ-A1.3) The hook SHALL NEVER emit `allow` for a
  command that any `Bash(…)` rule of the worker profile's `deny` block
  matches, at any self-approval policy value and for every approval category,
  declared command-step lines included: the guard SHALL read those rules and
  refuse a match before any approval is considered. The suite SHALL assert
  this outcome against the actual `deny` block rather than relying on Claude
  Code's evaluation order, and the `deny` block SHALL remain enforced
  verbatim, changing only by the additions REQ-F1.6 and REQ-G1.8 name.
  *(Cites: D-10, D-13; obs:4dda9fe1; the 2026-08-18 amendment note (Sources).)*
- **REQ-A1.4** A command SHALL be auto-approved only if EVERY segment of a
  compound command (quote-aware split on `;`, `&&`, `||`, `|`, `&`, and
  newlines) is independently known-safe. Any ambiguity SHALL defer: unbalanced
  quotes, command or process substitution (`$(…)`, backticks, `<(…)`, `>(…)`),
  an input here-document or here-string (`<<`, `<<-`, `<<<` — the multi-line body
  a here-document introduces cannot be soundly segmented by the newline split, so
  it defers), a write-redirect to a file target other than `/dev/null` —
  appearing anywhere in the segment including a leading redirect (`>f cmd`), and
  in any of the forms `>`, `>>`, `>|`, `&>`, `&>>`, and `>&`/`<&` when the operand
  is a filename rather than a digit or `-` (`cmd >& file` writes a file) — or an
  unrecognized verb. File-descriptor duplication or closing whose operand is a
  digit or `-` (`2>&1`, `>&2`, `2>&-`) is not a file write and does not defer.
  *(Cites: D-3; kickoff §7 (2026-07-18).)*
  **Superseded-by: REQ-A1.12** (2026-10-05) — the extension admits
  command substitution under a narrow rule and reads the segments in their
  run order, so a leading `cd` and plain assignments can be modelled.
- **REQ-A1.12** (supersedes REQ-A1.4) A command SHALL be auto-approved only if
  EVERY segment of a compound command (quote-aware split on `;`, `&&`, `||`,
  `|`, `&`, and newlines) is independently approvable, the segments analysed
  in run order so state a segment establishes (the working directory, a
  variable's value) is applied to the segments after it. State SHALL carry
  only from a segment that runs unconditionally in the current shell to a
  successor joined by `&&`, except that a REQ-E1.2 plain assignment, which
  cannot fail once its name passes the name screen, also carries to a
  successor joined by `;` or `||`; a state-setting segment followed by any
  other operator, inside a pipeline, backgrounded, or under a prefix such as
  `timeout`, SHALL defer the command. Any segment that assigns a variable by a
  means other than a REQ-E1.2 plain assignment (`read`, `printf -v`,
  `mapfile`/`readarray`, `declare`/`typeset`/`local`/`export` with a value,
  `let`, `((…))`, or a loop the REQ-E1.1 modelling does not cover) SHALL make
  that variable opaque from that point. Any ambiguity SHALL
  defer: unbalanced quotes; process substitution (`<(…)`, `>(…)`); backtick
  substitution; a `$(…)` substitution outside the narrow form of REQ-E1.3; an
  input here-document or here-string (`<<`, `<<-`, `<<<`); a write-redirect,
  in any of the forms `>`, `>>`, `>|`, `&>`, `&>>`, and `>&`/`<&` with a
  filename operand, appearing anywhere in the segment including a leading
  redirect, to a target other than `/dev/null` or a target an enabled policy
  arm admits (REQ-F1.3, REQ-F1.4); subshell or brace grouping; or an
  unrecognized verb. File-descriptor duplication or closing whose operand is a
  digit or `-` is not a file write and does not defer.
  *(Amended at the 2026-10-10 extension: a plain assignment also carries
  across `;` and `||` (D-24).)*
  *(Cites: D-3, D-11, D-19, D-24; obs:885bc3c9, obs:01629047; the live-run
  prompt replay; the Task 6 review forks (Sources).)*
- **REQ-A1.5** The known-safe set SHALL be an explicit enumerated allowlist of
  verbs and invocation shapes — never a category match — comprising: plugin/repo
  `scripts/*.sh` and `tests/*.sh` executed directly or via `bash`/`sh <path>`
  (never `-c`); an enumerated list of read-only shell builtins and read-only
  coreutils (for example `cat`, `head`, `tail`, `wc`, `grep`, `cut`, `sort`,
  `uniq`, `comm`, `diff`, `cmp`, `basename`, `dirname`, `realpath`, `printf`,
  `echo`, `pwd`, `ls`, `stat`, `file`, `od`, `tr`, `date`, `seq`, `test`,
  `true`, `false`), with `find` excluding
  `-delete`/`-exec`/`-execdir`/`-ok`/`-fprint*` and `sed` excluding both `-i`
  and its file-writing commands (`w`/`W`/`s///w`); an enumerated list of
  read-only `git` subcommands (for example `log`, `show`, `diff`, `status`,
  `rev-parse`, `cat-file`, `ls-files`, `ls-tree`, `for-each-ref`, `describe`,
  `blame`, `shortlog`, `rev-list`) with per-subcommand flag guards wherever a
  read-only subcommand has a mutating form (`branch` without
  `-m`/`-M`/`-d`/`-D`/`-f`, `config` in read form only, `remote` without
  `add`/`remove`/`set-url`, `tag`/`stash` in list/show form only); the
  lint/test runners `shellcheck`, `markdownlint`/`markdownlint-cli2`,
  `yamllint`, `bats`, and `mise run`/`tasks` (repo-defined tasks, trusted per
  the kickoff trust boundary — distinct from the arbitrary-command runners
  REQ-A1.6 defers); read-only `gh`
  (`pr view`/`list`/`status`/`diff`/`checks`, `auth status`, `repo view`); and
  shell control structures (`for`/`while`/`if`/`case`) whose conditions and
  bodies are themselves verified, including `fish -c "<inner>"` where `<inner>`
  recursively passes the same analysis within a bounded recursion depth. The
  exhaustive positive verb membership is carried by the implementation (Task 1)
  and pinned by the adversarial suite (REQ-B1.6).
  *(Cites: D-3; the validated prototype (Sources).)*
- **REQ-A1.6** Everything not in the known-safe set SHALL defer, explicitly
  including `rm`, `curl … | sh`, `sudo`, `bash -c`/`sh -c`, in-place edits,
  write-redirects to a non-`/dev/null` target, command substitution, mutating
  `git`/`gh` subcommands, process kills (`kill`/`pkill`), command-runner verbs
  that execute an arbitrary sub-command supplied on the command line without
  further inspection (`env`, `xargs`, `timeout`, `nohup`, `nice`, `setsid`,
  `stdbuf`, `chroot`), writer coreutils (`tee`, `dd`, `cp`, `mv`, `install`,
  `truncate`, `ln`, `touch`), and text-tool write-escapes (`sed`
  `w`/`W`/`s///w`, `awk` `print >`/`system()`) — surfaced to the human via the
  normal prompt. (`awk` is deliberately *not* in the REQ-A1.5 allowlist and so
  defers wholesale — it is too capable to safely allowlist, `system()` and
  command-`getline` being arbitrary execution; the `awk` write-escape callout
  here is belt-and-suspenders documenting why, not an implication that `awk` is
  otherwise approvable.)
  *(Cites: D-3; brief Amendment 1 (2026-07-18).)*
  **Superseded-by: REQ-A1.13** (2026-10-05) — `timeout` and `time`
  wrap a command the hook can inspect, so they join the analysable set.
- **REQ-A1.13** (supersedes REQ-A1.6) Everything no enabled policy arm
  approves SHALL defer, explicitly including `rm`, `curl … | sh`, `sudo`,
  `bash -c`/`sh -c`, interpreters given a program (`python3`, `perl`, `node`,
  `awk -f`), command substitution outside REQ-E1.3, process kills
  (`kill`/`pkill`), command-runner verbs that execute an arbitrary
  sub-command (`env`, `xargs`, `nohup`, `nice`, `setsid`, `stdbuf`, `chroot`),
  writer coreutils and in-place edits whose target falls outside every enabled
  arm, mutating `git`/`gh` subcommands outside the own-branch arm, every `gh`
  write (they are outward-facing), text-tool write- and execute-escapes (`sed`
  `w`/`W`/`s///w`/`e`/`s///e`, in every form including `sed -i`, `awk`
  `print >`/`system()`), and the variable-naming forms `test -v`, `[ -v`, and
  `printf -v`, whose operand bash evaluates as an arithmetic subscript that
  can run a command substitution. The `time` keyword (bare or with `-p`) and
  `timeout <duration>` (no flags; a duration matching
  `^[0-9]+(\.[0-9]+)?[smhd]?$`) SHALL be analysed as transparent prefixes:
  the command they wrap is verified exactly as if it stood alone, and
  approval follows its verdict; any other `timeout` or `time` form defers.
  *(Cites: D-3, D-19; brief Amendment 1 (2026-07-18); the live-run prompt
  replay (Sources).)*
- **REQ-A1.7** The hook SHALL consider only the Bash tool; for every other tool
  it SHALL defer.
  *(Cites: D-2.)*
- **REQ-A1.8** An allowlisted verb SHALL be auto-approved only when its flags,
  options, and arguments match an enumerated recognized-safe invocation for that
  verb; ANY unrecognized flag or option, or any argument that could designate an
  output/target file, SHALL defer. This is the safe-invocation rule that makes
  the allowlist robust without chasing every dangerous flag: examples that MUST
  defer under it include `sort -o FILE`/`--output`, `uniq IN OUT` (second
  operand), `markdownlint --fix`/`markdownlint-cli2 --fix`, `date -s`, `file -C`,
  `find -okdir`/`-fls`, and any `git` invocation carrying a pre-subcommand global
  option (`-c`, `-C`, `--git-dir`, `--work-tree`, `--exec-path`), which can
  inject config- or alias-driven command execution even on a read-only
  subcommand.
  *(Cites: D-3; kickoff §7 (2026-07-18).)*
- **REQ-A1.9** The analyzer SHALL pin the shell grammar it parses (the shell the
  Bash tool executes) and SHALL defer on any construct it does not confidently
  parse, explicitly including: an inline environment-assignment prefix
  (`VAR=value cmd`, e.g. `BASH_ENV=…`, `LD_PRELOAD=…`, `GIT_PAGER=…`); a verb
  given as a path containing `/` (`/abs/cat`, `./cat`) except the enumerated repo
  `scripts/*.sh`/`tests/*.sh` case (REQ-A1.5/REQ-A1.10); fish command
  substitution (bare `(…)`) encountered within `fish -c` inner analysis;
  subshell or brace grouping (`(…)`, `{ …; }`); a bundled or long-form `-c`
  (`bash -ec`, `sh -xc`, `fish --command`); and backslash line-continuations,
  escaped operators or quotes, and ANSI-C `$'…'` quoting whose semantics it does
  not model. The operator splitter SHALL correctly tokenize multi-character
  redirect operators — output forms (`>>`, `>|`, `&>`, `&>>`, `2>&1`) and input
  here-document / here-string forms (`<<`, `<<-`, `<<<`) — before splitting on
  the control operators, so an operator is never mis-split into a spurious safe
  segment; a here-document defers per REQ-A1.4.
  *(Cites: D-3; kickoff §7 (2026-07-18).)*
- **REQ-A1.10** Before approving an enumerated `scripts/*.sh`/`tests/*.sh`
  script invocation or a `bats <file>` invocation, the hook SHALL canonicalize
  the (already-expanded) path and containment-check it against the repository
  root; a path resolving outside the repository SHALL defer. The repo-resident
  trust boundary (brief §2) holds only for paths that actually resolve inside the
  checkout: `bash ../../../tmp/evil/scripts/x.sh` and `bats /tmp/evil.bats` MUST
  defer.
  *(Cites: D-3; security-posture path-access (Sources); kickoff §7 (2026-07-18).)*
  **Superseded-by: REQ-A1.14** (2026-10-05) — the hook never sees an
  expanded path (D-10), and the shipped guard already trusts installed
  planwright plugin roots alongside the repository.
- **REQ-A1.14** (supersedes REQ-A1.10) Before approving an enumerated
  `scripts/*.sh`/`tests/*.sh` script invocation or a `bats <file>`
  invocation, the hook SHALL resolve the raw path operand only as REQ-E1.1 and
  REQ-E1.2 allow (any other `$` defers), canonicalize it, and containment-check
  it against the repository root or an installed planwright plugin root; a
  path resolving outside every such root SHALL defer, so
  `bash ../../../tmp/evil/scripts/x.sh` and `bats /tmp/evil.bats` MUST defer.
  *(Cites: D-3, D-10; security-posture path-access (Sources).)*

## REQ-B — Implementation, robustness, and security

- **REQ-B1.1** The hook SHALL be implemented in portable POSIX/bash shell with
  no dependency on python, fish, mise, tmux, or Ansible; the security-critical
  command-analysis logic SHALL be pure shell. The analyzer SHALL treat the
  extracted command string strictly as inert data — never `eval`-ed,
  re-expanded, glob-expanded, or used as a pattern, format string, or unquoted
  argument — so that analyzing a hostile command can never execute it.
  *(Cites: D-4; bootstrap REQ-K1.5 (Sources); security-posture (Sources).)*
- **REQ-B1.2** Extraction of `tool_name` and `tool_input.command` from the hook
  stdin payload SHALL use `jq`; when `jq` is absent the hook SHALL degrade to
  deferring every command (auto-approving nothing), never to a hand-rolled JSON
  parse and never to a false-allow.
  *(Cites: D-4; the `tasks-pr-sync.sh` jq-with-degradation precedent (Sources).)*
- **REQ-B1.3** The hook SHALL fail safe (defer) on any malformed input,
  unreadable stdin, internal error, or `fish -c` nesting past its bounded
  recursion depth.
  *(Cites: D-3, D-4.)*
- **REQ-B1.4** The hook SHALL NOT echo untrusted command content to a
  terminal-driving stream; its `permissionDecisionReason` SHALL be a fixed
  string rather than a reflection of the analyzed command.
  *(Cites: security-posture echo discipline (Sources).)*
- **REQ-B1.5** The hook script SHALL be held to planwright's framework-script
  security bar and gated by the self-hosting quality guards (shellcheck, shfmt,
  secret scan) that cover every shipped script.
  *(Cites: security-posture framework-script security (Sources).)*
- **REQ-B1.6** The hook SHALL ship with an adversarial test suite exercising at
  least the validated prototype's ~30 cases plus the regressions it surfaced
  (for example `echo ok; rm -rf x` MUST defer) and the kickoff-surfaced vectors
  (REQ-A1.4/A1.8/A1.9/A1.10), asserting ZERO false-allows and that a
  `deny`-listed command is never auto-approved; the suite SHALL include a
  deny-precedence collision case derived from the actual
  `config/worker-settings.json` `deny` block — a command matching BOTH the
  known-safe set AND a `deny` rule — asserting the hook does not auto-approve it;
  and it SHALL assert (design-level where not executable) that the classifier's
  fallthrough branch is defer, so "zero false-allows" is guaranteed by
  construction rather than only across the corpus. The suite SHALL run under the
  repo's `mise run test` / CI.
  *(Cites: D-3; the validated prototype and its 30-case suite (Sources); security-posture (Sources); kickoff §7 (2026-07-18).)*
- **REQ-B1.7** The hook SHALL fail closed at the emission boundary: it SHALL
  write its `allow` decision as a single final action only after every check has
  passed (never a partially-written `allow`), and on the defer path and on any
  error, signal, or unexpected state it SHALL produce empty stdout and exit 0.
  It SHALL NEVER exit with status 2 or otherwise emit Claude Code's block/deny
  signal (approval is upgrade-only; blocking stays with `permissions.deny`/`ask`,
  REQ-A1.2). It SHALL bound its own runtime and read stdin defensively so it can
  never hang a worker's tool call, and a present-but-empty or non-string
  `tool_input.command` SHALL defer. The hook SHALL decide solely from the command
  string and path metadata (the canonicalization/containment of REQ-A1.10, which
  reads filesystem metadata, not file contents) and SHALL NOT read or parse the
  contents of any target script (consistent with REQ-B1.1's inert-data rule).
  Failure of the hook script *itself* to start (missing interpreter,
  non-executable, unreadable, or a parse error on the bash floor) fails safe
  structurally — Claude Code receives no `allow` and runs its normal permission
  flow — rather than being a decision the hook emits.
  *(Cites: D-3, D-4; kickoff §7 (2026-07-18); brief Amendment 1 (2026-07-18).)*
  **Superseded-by: REQ-B1.8** (2026-10-05) — the hook now also
  reads a launcher-written session record, the declared command steps, and the
  profile's `deny` rules, which the original sole-input clause did not admit.
- **REQ-B1.8** (supersedes REQ-B1.7) The hook SHALL fail closed at the
  emission boundary: it SHALL write its `allow` decision as a single final
  action only after every check has passed, and on the defer path and on any
  error, signal, or unexpected state it SHALL produce empty stdout and exit 0;
  it SHALL NEVER exit with status 2 or emit Claude Code's block signal. It
  SHALL bound its own runtime and read stdin defensively, and a
  present-but-empty or non-string `tool_input.command` SHALL defer. The hook
  SHALL decide solely from the command string, path metadata, the
  launcher-written session record (REQ-G1.8), the declared command steps, and
  the `Bash(…)` rules of the profile's `deny` block (REQ-A1.11); it SHALL NOT
  read or parse the contents of any target script. A record field an arm or
  rule needs that is missing or unparseable SHALL disable that arm, and every
  rule that reads the field (the REQ-E1.4 `cd` rule included) SHALL defer;
  an unreadable record leaves only the read-only arm in force. Failure of the
  hook script itself to start fails safe structurally.
  *(Cites: D-3, D-4, D-12; kickoff §7 (2026-07-18).)*

## REQ-C — Wiring and delivery

- **REQ-C1.1** The hook SHALL be wired into `config/worker-settings.json` as a
  `PreToolUse` (Bash) hook, referencing the plugin script through the same
  `${CLAUDE_PLUGIN_ROOT}` mechanism the plugin's `hooks/hooks.json` uses so it
  resolves under a marketplace install; `defaultMode: default` and the `deny`
  block SHALL be kept verbatim.
  *(Cites: D-5, D-6.)*
- **REQ-C1.2** The auto-approve hook SHALL apply only to dispatched worker
  sessions (via `config/worker-settings.json`), never to the tower session or a
  human's interactive session; it SHALL NOT be added to the plugin-global
  `hooks/hooks.json`.
  *(Cites: D-5.)*
- **REQ-C1.3** `config/worker-settings.json` SHALL remain a human-reviewed,
  human-installed permissions artifact requiring human sign-off before use, and
  its manual merge/reference delivery SHALL be preserved (planwright never edits
  a user's `settings.json`); the fragment's `_about` documentation SHALL be
  updated to describe the hook, its no-LLM/allow-only/deny-precedence
  properties, and the human-sign-off posture.
  *(Cites: D-6; fleet-autonomy REQ-E1.4/D-19 (Sources); bootstrap REQ-I1.2 (Sources).)*

## REQ-D — Root-cause: literal script-path invocation

- **REQ-D1.1** `/execute-task`, `/orchestrate`, and `/spec-kickoff` SHALL
  resolve the plugin/planwright root once per invocation and call plugin
  scripts by resolved literal absolute path rather than through an unexpanded
  shell variable, so those invocations are statically analyzable by Claude Code
  (persistent-allow-able, and matchable by a literal-path allow entry) — closing
  the flood at its root for the `jq`-absent degradation path and independent of
  the hook.
  *(Cites: D-7; obs:344dd129.)*

## REQ-E — Expansion and compound-shape coverage

- **REQ-E1.1** A word carrying an unresolved or opaque `$` expansion (a
  variable the same command did not assign a plain literal, a special
  parameter such as `$_` or `$?` used as an operand, or a variable assigned
  from a substitution) SHALL defer wherever the verb's approval depends on that
  word's value: an operand of a verb with flag or argument screens, a verb
  position, or a path the hook containment-checks. A `for` loop variable SHALL
  be modelled by verifying the loop body once per plain-literal head word with
  that word substituted, deferring when any head word is not a plain literal
  or the head holds more words than the bound the implementation states (the
  whole loop defers past the bound; it is never verified in part). The worker
  guard and the tower command guard, which
  shares the operand screens, SHALL both carry this rule.
  *(Cites: D-11; obs:9255e1d1; drafting-session decision (2026-10-05).)*
- **REQ-E1.2** A plain assignment `NAME=<plain literal>` segment SHALL be
  approvable, and a later `$NAME` or `${NAME}` in the same command SHALL be
  analysed as that literal, for any literal value and not only a trusted-root
  path. A value holding whitespace SHALL resolve only inside double quotes,
  where it stays one word in every shell; unquoted, bash splits it and zsh
  (the Bash tool's shell on macOS) does not, so the use SHALL stay unresolved
  under REQ-E1.1. An empty value SHALL remove an unquoted word, as both
  shells do. Only
  the value rule widens: the shipped guard's name screen (`assign_name_ok`:
  shell-consumed names such as `PATH`, `IFS`, `CDPATH`, `HOME`, `TMPDIR`, and
  `BASH*`, and any name exported in the hook's environment) and its
  unconditional top-level placement rule still apply, and a refused name
  defers the command. An
  assignment whose value carries a quote the analyzer does not model, a glob,
  or an expansion SHALL leave the variable opaque.
  *(Amended at the 2026-10-10 extension: unquoted word splitting is no longer
  reproduced; a whitespace-bearing value resolves only inside double quotes
  (D-25).)*
  *(Cites: D-19, D-25; obs:885bc3c9, obs:23a619c0, obs:8d46a461; the Task 6
  review forks (Sources).)*
- **REQ-E1.3** A `$(…)` substitution SHALL be approvable only when all of these
  hold: its inner text is a single simple command or pipeline that
  independently passes the read-only analysis; it contains no nested
  substitution, no backtick, and no parenthesis inside a quoted string; and
  every position its output reaches (directly, or through a variable assigned
  from it) is argument-independent: an operand of a verb whose approval does
  not depend on its operand values (an enumerated set comprising the trusted
  repo and plugin scripts, counting only the operands after the script path;
  `echo`; `printf` after a literal format; and `test` and `[` in any form but
  `-v`), or the value of such an assignment. Output reaching any other
  position, a script path or a `printf` format included, SHALL defer.
  *(Cites: D-11; obs:9255e1d1; the live-run prompt replay (Sources).)*
- **REQ-E1.4** A `cd <dir>` segment SHALL be approvable only when `<dir>` is a
  plain literal, absolute or relative to the modelled working directory (never
  resolved through `CDPATH`), that canonicalizes to an existing directory
  inside the session's own worktree, and the segment carries state under
  REQ-A1.12's `&&` rule; the segments after it SHALL be analysed with that
  directory as the working directory. A `cd` to any other target, a `cd` whose
  operand is not a plain literal, or a `cd` the `&&` rule does not cover SHALL
  defer the whole command. Claude Code's own gate on
  a `cd` that changes directory before a `git` call is outside any hook's
  reach, so the fleet guide and worker launch text SHALL state that a worker
  already runs in its own worktree and issues `git` without a `cd`.
  *(Cites: D-19; obs:885bc3c9, obs:01629047; research: Claude Code
  permissions doc (Sources).)*
- **REQ-E1.5** The read-only set SHALL include the timing and inspection verbs
  workers use for waits and diagnostics, each under the REQ-A1.8
  safe-invocation rule: `sleep` with a numeric operand, `ps`, `uptime`,
  `which`, `command -v`, `git check-ignore`, `git ls-remote` whose only
  operands are a configured remote name and optional ref patterns (no URL or
  path, no `--upload-pack`/`-u`), and the `--version` form of an allowlisted
  tool; the exhaustive membership is
  carried by the implementation and pinned by the suite.
  *(Cites: D-19, D-26; the live-run prompt replay (Sources).)*

## REQ-F — The self-approval policy

- **REQ-F1.1** The worker's self-approval surface SHALL be one configurable
  policy, the knob `worker_self_approval` resolved through the overlay layers
  last-value-wins (no union across layers), whose value is a space-separated
  list of additional arms drawn from `own-branch` and `scratch`. The
  `read-only` arm is always in force and comprises every pre-extension
  approval category (read-only shapes, trusted-repo-task shapes, declared
  command-step lines) plus the REQ-E shapes; the core default SHALL be the
  empty list, which reproduces the pre-extension write posture (no write
  approvals beyond the trusted-repo-task shapes). An unknown member, a
  malformed value, or a read failure SHALL resolve the whole value to the
  empty list.
  *(Cites: D-12; customization-boundary (Sources).)*
- **REQ-F1.2** The policy SHALL be evaluated by the worker guard against its own
  per-segment command classification, never by literal-prefix matching, and
  the guard SHALL remain the only self-approval mechanism: no tower,
  supervisor, or relay SHALL answer a worker's permission prompt on the
  strength of the policy.
  *(Cites: D-12, D-13; inter-orchestrator-coordination doctrine (Sources).)*
- **REQ-F1.3** The `own-branch` arm SHALL approve, beyond the read-only set,
  writes confined to the session's own unit branch and worktree: file writers
  and in-place edits (`sed -i` whose script passes the read-only `sed` script
  check, `rm`, `mkdir`, `cp`, `mv`, `touch`, `tee`, and a write-redirect)
  under the REQ-A1.8 enumerated-flags rule (no link-creating or
  symlink-preserving flags such as `cp -l`/`-s`/`-a`/`-P`, `ln`), whose every
  target canonicalizes inside the worktree and outside the REQ-F1.6 excluded
  paths, counting a `mv` source as a target; a write to an existing file with
  more than one hard link, or any write following a link-creating segment in
  the same command, SHALL defer. Also `git add`, `git rm`, `git mv`,
  `git restore`, `git checkout -- <paths>`, and `git commit` without a
  history-rewriting flag; `git fetch` whose only operands are a configured
  remote name and optional plain ref names (any `src:dst` refspec, URL, path,
  or `--upload-pack` defers); and a `git merge` whose source is the unit's PR
  base (as the session record names it, in the `<remote>/<base>` spelling),
  only while the session is on its own unit branch and the human-gates
  `worker_base_merge` value allows it. The unit branch, worktree root, and PR
  base come from the session record (REQ-G1.8), never from the current
  checkout; a session whose record lacks them SHALL get no `own-branch`
  approvals. The guard approves no `git push`: the profile's static
  `git push origin` rule covers the unit push.
  *(Cites: D-12, D-13; obs:82bab6e3; human-gates Task 10 (Sources).)*
- **REQ-F1.4** The `scratch` arm SHALL approve writes (`mkdir`, `mktemp`, `rm`,
  `cp`, `mv`, `touch`, `tee`, and a write-redirect), under the same flag,
  `mv`-source, hard-link, and link-creation rules as REQ-F1.3, whose every
  target canonicalizes inside the session's own scratch root as the session
  record names it (REQ-G1.2, REQ-G1.8); a literal `$TMPDIR` or `${TMPDIR}`
  SHALL resolve to that recorded root and to nothing else. It SHALL NOT
  approve executing or sourcing anything located there.
  *(Cites: D-14; obs:1f1141ec, obs:65c35236.)*
- **REQ-F1.5** The floor SHALL be outside every policy value: the guard SHALL
  NOT approve a PR merge, a ready flip or its undo, a force-push, `--amend`,
  rebase, squash, reset of a branch, any `git push`, a write-classified segment
  (writer verb, in-place edit, or write-redirect) whose target canonicalizes
  outside the worktree, the scratch root, and `/dev/null`, a write to a
  REQ-F1.6 excluded path, a `gh` write, or anything a `Bash(…)` rule of the
  profile's `deny` block matches. Git's own writes to its object store and
  index during an approved `git` subcommand are not write-classified segments.
  Evaluating the floor SHALL precede evaluating the policy. The floor bounds
  the guard's approvals only: the profile's static allow rules (which already
  admit `gh pr create`, `gh pr ready`, `git commit` including a permitted
  `--amend`, and `git push origin`), its `deny` block, and `policy-guard.sh`
  (the human-gates deny-emitting hook, which keeps running beside the guard)
  govern independently of it.
  *(Cites: D-13; the operator's live-run delegation (Sources).)*
- **REQ-F1.6** The `own-branch` arm SHALL exclude, and the floor SHALL refuse,
  writes to paths a tool runs or reads as trust input without a further
  prompt: the worktree's `.git` entry, the configured git hooks directory,
  `.claude/`, and tool configuration that executes commands (`mise.toml`,
  `mise.local.toml`, `.mise/`, `lefthook.yml`). The worker profile SHALL add
  `Write`/`Edit` deny rules for the same paths, so the `Write` and `Edit`
  tools cannot reach what the guard refuses. Running an edited repo
  `scripts/`/`tests/` file stays approvable (the trusted-checkout residual).
  *(Cites: D-22; kickoff Amendment 2 decision (2026-10-05).)*

## REQ-G — Profiles, delivery, and the unattended contract

- **REQ-G1.1** `config/worker-settings.json` SHALL ship a static read-only
  allow set scoped to the worker profile, covering `grep`, `cat`, `head`,
  `tail`, `wc`, `ls`, `jq`, `cut`, `diff`, `stat`, and the read-only `git`
  subcommands Task 12 enumerates, so an adopter needs no user-scope allow
  rule. Because a static rule bypasses the guard's argument screens, no new
  rule SHALL name a verb or subcommand that has a file-writing or
  program-running form (for `git`: no `log`, `show`, `diff`, or other
  diff-family subcommand, which take `--output`; no `grep`, which takes
  `-O`; no `cat-file`, which takes `--textconv`): the set SHALL NOT include
  `awk`, `find`, `xargs`, `sed` in any form (`w` and `e` write and execute
  even under `-n`), `sort` (`-o`, `--compress-program`), or `uniq` (a second
  operand is an output file). The guard approves the safe forms of `sed`,
  `sort`, `uniq`, `find`, and the `git` subcommands through its screens;
  `awk` and `xargs` defer there too (REQ-A1.13). Every rule SHALL pass the
  permission-matcher fixture table, and the matcher test SHALL fail on an
  allow rule with no fixture row.
  *(Amended at kickoff 2026-10-05: `sed -n`, `sort`, and `uniq` dropped.)*
  *(Cites: D-15; the dotfiles stopgap (Sources); obs:65c35236.)*
- **REQ-G1.2** The worker launcher SHALL create a per-worker scratch root
  owned by the worker, export it as the worker's `TMPDIR`, and record it in
  the session record (REQ-G1.8); the guard SHALL treat no other directory as
  scratch. The root SHALL survive a `recover` or relaunch of the same worker
  and be removed only by the worker's final stop or reap.
  *(Cites: D-14; obs:1f1141ec.)*
- **REQ-G1.3** The fleet guide SHALL state that a worker reads its permission
  profile and the policy's launch-time inputs at session start, so a change
  reaches a running worker only by relaunch. The stream-json supervisor's
  existing `recover` path already resumes a stopped worker's persisted session
  with the installed profile passed explicitly (a resumed session does not
  restore `--settings`); the supervisor SHALL add a `relaunch` verb for a live
  worker that performs a graceful `stop` then `recover`, refusing while the
  worker holds a lock the stop would release, re-resolving the session record
  (REQ-G1.8) from current config and keeping the scratch root.
  *(Cites: D-16; the live-run report (Sources); research: Claude Code
  sessions doc (Sources).)*
- **REQ-G1.4** The doctrine SHALL state what unattended mode means for
  permission prompts: a prompt outside the self-approval policy and outside
  any operator-written standing decision is parked as a decision-queue item
  for the operator, never answered by a tower's or supervisor's judgment, and
  the configured policy is the only self-approval surface (a standing decision
  is the operator's own answer recorded in advance, not a self-approval).
  *(Cites: D-9, D-12; inter-orchestrator-coordination doctrine (Sources).)*
- **REQ-G1.5** The meta-tower SHALL run the selected spec's single-spec step
  (its per-spec lock, freshness gate, dispatch record, and worker launch)
  itself, under its own tower profile, rather than launching a subordinate
  tower session through the worker backend; the step's mechanical part SHALL
  be a plugin script the orchestration doctrine tells the meta-tower to call,
  so CI can test it. This reverses orchestration-fleet REQ-D1.1 and D-6's
  subordinate-tower clause (D-17 records the reconciliation).
  *(Cites: D-17; work-placement doctrine (Sources); orchestration-fleet D-6
  (Sources).)*
- **REQ-G1.6** The worker profile SHALL allow the first-push spelling
  `git push -u origin <branch>` under the same `deny` floor as
  `git push origin`.
  *(Cites: D-15; obs:33812f90.)*
- **REQ-G1.7** The profile's `_about` text SHALL describe every approval
  category the worker guard applies (read-only shapes, trusted-repo-task
  shapes, declared command-step lines, and each policy arm) and the floor.
  *(Cites: D-12; obs:62411beb.)*
- **REQ-G1.8** The worker launcher SHALL resolve, once at launch, the
  self-approval policy, the unit branch, the worktree root, the unit's PR
  base, the scratch root, the audit-log home (REQ-H1.4), and the human-gates
  `worker_base_merge` value, and write them to a session record outside the
  worktree and the scratch root; the guard SHALL read these inputs only from
  that record, never from live config or the current checkout. The worker
  profile SHALL add `Write`/`Edit` deny rules for the session record's
  location and the overlay config files the policy resolves through. A policy
  change reaches a worker only through relaunch (REQ-G1.3).
  *(Cites: D-23; kickoff Amendment 2 decision (2026-10-05).)*

## REQ-H — Source fixes and verified premises

- **REQ-H1.1** A plugin script that takes a value a worker would otherwise
  fetch by command substitution SHALL resolve that value itself when the
  argument is omitted; `step-record.sh`'s `--head` is the observed instance.
  *(Cites: D-11; the live-run report (Sources).)*
- **REQ-H1.2** The permission-matcher model doc, its re-implementation, and the
  worker profile's `_about` SHALL state the documented behaviour that `deny`
  and `ask` rules apply to a command nested in a command substitution, a
  subshell, or a control-flow body, closing the model boundary that assumed
  otherwise, with a fixture row per nesting form.
  *(Cites: D-10; obs:aed9ca33; research: Claude Code permissions doc
  (Sources).)*
- **REQ-H1.3** The adversarial suite SHALL include a sanitized regression
  corpus drawn from real worker prompts, asserting that every row in an
  in-policy class approves under the arm it belongs to, that every floor row
  defers under every policy value, and that every row the policy does not
  cover defers.
  *(Cites: D-20; the live-run prompt replay (Sources).)*
- **REQ-H1.4** Every `allow` the hook emits SHALL append one line, with a
  single append write, to a per-session, append-only audit log in the
  audit-log home the session record names (under the fleet state home): the
  time, the session, the arm or approval category that approved it, and a
  hash of the command, never the command text. The hook only appends; the
  launcher or the worker's final stop prunes logs beyond the retention bound
  the options reference states. A failure to write the line SHALL NOT turn an
  approval into a block or a partial decision; when the record names no
  usable log home, the `own-branch` and `scratch` arms SHALL be disabled for
  the session (read-only approvals proceed unlogged), so no write approval
  goes untraced.
  *(Cites: D-21; obs:9255e1d1; drafting-session decision (2026-10-05).)*

## Changelog

- 2026-10-10 — Bundle extended via `/spec-draft` to match three operator
  decisions taken while Task 6's PR (#637) was in review, which the merged
  guard already implements. Reopen cycle: stored Ready→Draft on all four
  headers, although the bundle derives Active (Task 8 in progress), because
  the content-anchor gate refuses an unanchored edit to a signed bundle and
  a v2 bundle has no valid park form; the `/spec-kickoff` delta
  re-walkthrough flips it back and re-anchors before this branch merges, so
  main and Task 8 never see the Draft status. REQ-A1.12 and REQ-E1.2 are amended in place rather
  than superseded, an operator choice at this drafting session (2026-10-10)
  that keeps the guard suite's fixture labels and the task citations valid;
  the kickoff classifies both as meaning-class. REQ-A1.12 widens: a plain
  assignment also carries across `;` and `||` (D-24). REQ-E1.2 narrows: a
  whitespace-bearing value resolves only inside double quotes (D-25). The
  REQ-E1.5 test-spec entry now pins every `ps` form carrying `-e` as
  deferring (D-26); the REQ text, whose membership the implementation
  carries, is unchanged beyond the citation. Mints D-24, D-25, D-26; D-19
  carries an amendment note. No task block changes.

- 2026-10-05 — Bundle extended via `/spec-draft` (reopen cycle: stored
  Ready→Draft on all four headers; the scoped kickoff of the delta flips it
  back). Adds REQ groups E (expansion and compound-shape coverage), F (the
  self-approval policy), G (profiles, delivery, the unattended contract), and H
  (source fixes and verified premises); supersedes REQ-A1.3 (by REQ-A1.11),
  REQ-A1.4 (by REQ-A1.12), REQ-A1.6 (by REQ-A1.13), and REQ-B1.7 (by REQ-B1.8);
  supersedes D-2 (by D-10) and D-8 (by D-12); scope amended in place to match.
  Drafting-session decisions: fold the whole amendment here rather than split
  it by owning bundle; core ships the read-only arm only; standing-decision
  segment matching deferred behind the settle-delivery fix; the meta-tower
  dispatches directly; the live unexpanded-operand false-allow travels as this
  delta's first task rather than an urgent flight; the tower command guard
  carries the expansion rule too (REQ-E1.1); the deferred audit log is lifted
  (REQ-H1.4). Removes the `tasks.md` Deferred entries for the allowlist knob
  and the runtime audit log (lifted by D-12 and D-21).
- 2026-10-05 — Delta kickoff via `/spec-kickoff` (brief Amendment 2).
  Operator decisions: the floor bounds only the guard; the static allow set
  drops `sed -n`, `sort`, and `uniq`; the guard-editing tasks are serialized;
  the `test -v`/`[ -v`/`printf -v` false-allow live in both shipped guards
  folds into Task 4; own-branch writes to execution-bearing config paths are
  refused in both the guard and the profile (REQ-F1.6, D-22); the guard reads
  its policy and identity only from a launcher-written session record
  (REQ-G1.8, D-23); the meta step becomes a tested script. Mints REQ-A1.14
  (supersedes REQ-A1.10), REQ-F1.6, REQ-G1.8, D-22, D-23. The sign-off lens
  pass's grounded fixes tighten REQ-A1.11, A1.12, A1.13, B1.8, E1.1–E1.5,
  F1.1, F1.3–F1.5, G1.1–G1.5, and H1.4 in place (the brief's Amendment 2 lens
  table lists each); D-3 and D-1 carry amendment notes.

- 2026-07-18 — Delta re-walkthrough (panel-review pass, gemini backend);
  pre-merge meaning-class amendment on the Ready spec PR. REQ-A1.4 and REQ-A1.9
  add explicit here-document / here-string (`<<`/`<<-`/`<<<`) deferral (M1);
  REQ-B1.7 reworded to drop the target-script content-inspection implication and
  affirm the hook decides from the command string + path metadata only, with a
  hook-script start failure failing safe structurally (M3); REQ-A1.6 clarifies
  `awk` defers wholesale (not in the A1.5 allowlist) (M4). test-spec REQ-A1.9 and
  REQ-B1.7 updated to match. A gemini-flagged TOCTOU symlink-swap concern on
  REQ-A1.10 was considered and declined as non-applicable to the single-agent
  trusted-checkout threat model (no concurrent adversary; R1 already accepts
  worker-run code).
- 2026-07-18 — Kickoff sign-off via `/spec-kickoff` (Draft→Ready). Walkthrough
  and sign-off lens pass hardened the command-analysis contract: REQ-A1.5 became
  an explicit enumerated allowlist (sed/git flag guards); REQ-A1.6 gained the
  command-runner / writer-coreutil / write-escape defer set; REQ-A1.4 pinned
  file-write vs fd-dup redirects; REQ-B1.1 added the inert-data analysis clause;
  and four new requirements closed the false-allow vectors the lens pass found —
  REQ-A1.8 (safe-invocation / unknown-flag-defers), REQ-A1.9
  (grammar-conservative deferral: env-prefixes, path-prefixed verbs, fish
  bare-paren, redirect tokenization), REQ-A1.10 (script/bats path containment),
  and REQ-B1.7 (fail-closed emission contract). REQ-B1.6 gained a deny-precedence
  collision case; test-spec fixtures and Task 1 (2d→3–4d) updated to match. All
  meaning-class, human-classified at sign-off. Pre-merge expression-only fix on
  the spec PR: test-spec REQ entries grouped under `## REQ-<group>` headings
  (`lint:md` MD001) and brief trailing blank lines removed (MD012) — no REQ
  meaning or coverage changed; anchor recomputed.
- 2026-07-18 — Bundle drafted at Status Draft via `/spec-draft`, building on
  fleet-autonomy (Ready) as a new spec rather than an amendment. Four
  drafting-session decisions shaped scope: include the literal-path root-cause
  cleanup (REQ-D); scope `fleet-state-home-unresolved` out and leave it
  unconsumed; use `jq` with degrade-to-defer for JSON extraction (D-4);
  reconcile with fleet-autonomy REQ-E1.4/D-19 in place by citation rather than
  cross-bundle supersession (D-6).

## Sources

- **The worker-permission-ergonomics seed brief** — the invocation's framing
  document: the problem statement, the grounded permission facts, the validated
  prototype pointer, and the shipped-hook constraints (POSIX sh; new spec, not
  a fleet-autonomy amendment).
- **The validated prototype** — `worker-pre-tool-use.py` (python3, reference
  only) plus `worker-settings-hook.json` and a 30-case adversarial test suite,
  validated 2026-07-18 by carrying a full instruction-headroom Task-1 run
  (edit + verify + CI + polish + push + PR #232) with zero false-allows across
  ~30 adversarial cases and the live run; a quote-aware operator splitter fixed
  a real false-allow (`echo ok; rm -rf x`).
- **The grounded permission facts** (claude-code-guide, Claude Code docs
  v2.1.x): `permissions.deny` is enforced in every mode; `auto` mode is a
  server-hosted LLM classifier; a `PreToolUse` hook returning
  `permissionDecision: allow` skips the prompt, sees the full expanded command
  string, is deterministic, and cannot override `deny`/`ask`.
  *(Corrected 2026-10-05: the hook sees the raw, unexpanded command, measured
  on the CLI (D-10, obs:9c1cf997); the deny outcome is asserted by REQ-A1.11.)*
- **fleet-autonomy REQ-E1.4, D-18, D-19** — the no-LLM-daemon-mechanics floor
  (D-18/REQ-G1.2), the `auto`-mode rejection (D-19/REQ-E1.4), and the
  static-allowlist-as-permission-channel posture this spec reconciles with in
  place (D-6). The deterministic, same-channel, human-reviewed hook honors
  D-19's actual intent (no LLM in the approval path) and is not the `auto` mode
  REQ-E1.4 ruled out.
- **fleet-autonomy `tasks-pr-sync.sh`** — the shipped `#!/bin/sh` PostToolUse
  hook that already extracts hook-stdin JSON with `jq` and no-ops cleanly when
  `jq` is absent: the precedent for D-4's jq-with-degradation choice.
- **bootstrap REQ-K1.5** — planwright's validator, hooks, and scripts run on a
  portable POSIX/bash runtime with no dependency on fish, mise, tmux, or
  Ansible.
- **bootstrap REQ-I1.2** — planwright never edits a user's `settings.json`; the
  worker-settings profile is merged or referenced by the human.
- **security-posture** — framework-script security bar (never execute untrusted
  input, echo discipline, stay auditable, gated by the quality guards).
- **customization-boundary** — the capability-vs-style rule applied in D-8:
  the fixed conservative allowlist is core policy; an operator-configurable
  extension knob stays deferred until drain-loop evidence shows it generalizes.
  *(2026-10-05: the evidence arrived; D-12 graduates the knob as the
  self-approval policy, opt-in with a behaviour-preserving default.)*
- **obs:cf529bca** — `tmux-worker-prompt-flood`: the core problem observation
  (consumed by this bundle).
- **obs:344dd129** — `execute-task-literal-script-paths`: the root-cause
  literal-path observation framing REQ-D (consumed by this bundle).
- **`fleet-state-home-unresolved`** (observation, uid b085ac53) — considered as
  a seed and scoped out as orthogonal fleet-governance robustness; left
  **unconsumed** so it stays live for a future fleet-autonomy fix.
- **The 2026-10-05 extension seed** — the `/spec-draft` invocation: the
  compound-shape gaps, the branch-scoped standing decision, the subordinate
  tower's profile, and the three live-run reports from an
  `/orchestrate --fleet --unattended` run (2026-10-03/04), including the
  stream-json worker that stalled about 80 minutes on a `step-record.sh` call
  carrying a command substitution.
- **Pinned altitude seed claims (2026-10-05)** — two explicit statements about
  the deliverable's nature, reconciled by D-9: the operator's "Wasn't this
  supposed to be unattended?", and the request to "state plainly what
  unattended mode means today, then define the self-approval surface as one
  configurable standing policy instead of a live delegation to the tower".
- **The operator's live-run delegation (2026-10-03)** — "if I have to approve
  execution writes for spec tasks this is pointless": every worker action
  confined to its own unit branch and worktree delegated live, keeping the
  floor (PR merge, the ready flip, force-push, amend, rebase, pushes to main or
  any other branch, writes outside the worktree). The shape REQ-F encodes.
- **The live-run report** — the operator's account of the same run: two
  parallel workers each running a nine-reviewer polish produced a stream of
  mostly read-only prompts; a tower-side filter auto-answering them was
  refused by the harness classifier as a bypass; settings load at session
  start, so a fix never reached the running workers; a local edit of the
  installed worker profile was refused too.
- **The dotfiles stopgap** — the operator's interim user-scope allow rules
  for read-only verbs (read-only `git` subcommands, `grep`, `sed -n`, `cat`,
  `head`, `tail`, `wc`, `ls`, `jq`, `cut`, `sort`, `uniq`, `diff`, `stat`,
  `cd`), deliberately excluding `awk`, `find`, `xargs`, and bare `sed`; it
  widened the operator's interactive sessions too, which REQ-G1.1 undoes.
  REQ-G1.1 moves it to the profile minus `sed -n`, `sort`, `uniq`, and `cd`
  (kickoff 2026-10-05: each has a write or execution form a static rule
  cannot screen).
- **The live-run prompt replay (2026-10-05)** — a read-only replay, during
  drafting, of every Bash permission request journaled by the stream-json
  supervisor between 2026-10-02 and 2026-10-05 through the then-current guard.
  The guard would have approved almost none, with the hook active throughout;
  the largest classes were a leading `cd`, command substitution, writes into
  temp scratch, own-branch write verbs, unknown verbs, and self-written temp
  scripts. The classified table stays machine-local (it holds raw commands);
  the bundle records only its shape.
- **The 2026-08-18 amendment note** — `specs/_pending/worker-permission-ergonomics-amendment.md`,
  captured during fleet-lifecycle-closure drafting. Its screen-narrowing and
  self-resolved plugin roots have since shipped through flights; its still-open
  items (the `-u` push spelling, the deny-outcome reword, the matcher's
  command-substitution behaviour) are carried by REQ-G1.6, REQ-A1.11, and
  REQ-H1.2.
- **research: Claude Code permissions doc** (code.claude.com, consulted
  2026-10-05) — `deny` and `ask` rules apply regardless of a PreToolUse hook's
  `allow`, and to commands nested in a substitution, subshell, or control-flow
  body; a `cd` that changes directory before a `git` call prompts as a
  separate safety gate.
- **research: Claude Code sessions doc** (code.claude.com, consulted
  2026-10-05) — a resumed session does not restore `--settings`; it must be
  passed again.
- **inter-orchestrator-coordination doctrine** — "never answer a worker's
  permission prompt on the tower's judgment"; the shipped worker profile is
  the sanctioned way to remove routine prompts. REQ-G1.4 adds the unattended
  statement there.
- **work-placement doctrine** — the smallest-sufficient-rung and
  tower-frugality axioms D-17 applies.
- **orchestration-fleet D-6** (and its REQ-D1.1) — the meta-tower as a tower
  of disposable subordinate towers. D-17 reverses its subordinate-session
  clause and keeps its intent (single-spec machinery unchanged, one spec per
  step) by the per-spec lock rather than a session boundary.
- **human-gates Task 10** — the worker base merge and the
  `worker_base_merge` knob the `own-branch` arm composes with.
- **tower-comms REQ-E1.5** — the literal-prefix standing-decision matcher D-18
  leaves unchanged.
- **obs:885bc3c9** — skills compose compound Bash a standing decision cannot
  match (consumed by this bundle).
- **obs:01629047** — worker-command-guard compound forms (consumed).
- **obs:23a619c0** — the stream-json allowlist gap on the opening doctrine
  resolution (consumed).
- **obs:9255e1d1** — the unexpanded-operand false-allow, still live at
  drafting (consumed; closed by Task 4).
- **obs:9c1cf997** — the raw-command premise behind D-10 (consumed).
- **obs:62411beb** — `_about` misses the declared-step category (consumed).
- **obs:4dda9fe1** — hook allow versus deny precedence undocumented
  (consumed).
- **obs:aed9ca33** — the matcher's command-substitution behaviour unknown
  (consumed).
- **obs:33812f90** — the `-u` push spelling misses the allow rule (consumed).
- **obs:1f1141ec** — operator decision: self-created temp-dir writes as a
  knob (consumed).
- **obs:82bab6e3** — forward-merging main into its own task branch is worker
  work (consumed).
- **obs:65c35236** — residual escalations carry output redirects (consumed).
- **obs:3ed95276** — the awk lexer's false-allows, cited for its lesson
  (left unconsumed).
- **obs:fd1824a4** — the standing-decision settle does not deliver, gating
  D-18's deferral (left unconsumed).
- **The Task 6 review forks** — the "Open spec forks" list in the
  description of PR #637 (merged 2026-10-10) and its review record: the
  three interpretation forks between the signed text and the reviewed guard,
  with the operator's decisions of 2026-10-09 ("Refuse -e" among them).
  Framed D-24, D-25, and D-26.
- **obs:8d46a461** — the shared guard tokenizer models bash while the Bash
  tool runs zsh on macOS; background for D-25 (left unconsumed: its
  shared-tokenizer root fix is outside this delta).
- **Research: the `ps(1)` manual pages** (consulted 2026-10-10) — FreeBSD's
  page documents `-e` as "Display the environment as well"; Apple's
  (`adv_cmds`) documents `-e` as identical to `-A` with `-E` printing the
  environment, and `-e` printing it under the legacy mode. Grounds D-26.
