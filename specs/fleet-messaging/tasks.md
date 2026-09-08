# Fleet Messaging — Tasks

**Status:** Ready
**Last reviewed:** 2026-09-07
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — Doctrine and contract layer

- **Deliverables:** the messaging-transport doctrine
  (`doctrine/messaging-transport.md`) carrying, per REQ-G1.5 and D-13, its
  nine contents: the signal-vs-record rule, whose upward half is the
  harness's one-shot idle notice (the notice's status line is instruction
  text, the store row written before the worker stops is the record), with
  the sentence that only a stop ending the worker's turn fires a notice —
  a mid-turn suspension, a permission or elicitation dialog, ends no turn
  and is the healing sweep's case (obs:4c25e743); the
  fallback obligation; the discipline ladder `script` < `tiered` < `open`
  with its three directions and send-time pressure demotion; the per-path
  fallback table over D-13's fixed path set — tower→worker steer, the
  decision answer, the worker→tower idle notice, the tower's own wake
  (whose fallback is today's metronome, REQ-D1.8), the two poll cadences
  (the attention watcher's healing sweep, the dashboard's projection
  refresh; only the first demotes, REQ-E1.1), and the tower↔tower
  advisory — whose two downward rows read per rung: on `tmux` the
  attributed buffer-paste, on `stream-json-persistent` the supervisor's
  control response for a decision answer and operator handoff for a
  free-text steer, and on `headless-oneshot` none, that rung holding no
  fork to answer (D-3); the per-session probe
  definition; the
  cross-machine transit note; the sentence distinguishing the three sweep
  names — the healing sweep is `fleet-attention-watch.sh watch`'s
  level-triggered pass, the reconcile sweep is `/orchestrate`'s tower step
  that rebuilds in-flight state from disk, and `fleet-attention-watch.sh
  reconcile` is that script's own deep-reconcile verb; the glossary of the
  three ladders and their step nouns; the
  fleet-runtime version rule (mixed CLI versions across a fleet are fine,
  the probe being per session and fail-safe); plus
  REQ-G1.6's declaration that no resource class beyond the inbox socket is
  acquired (the idle-notice subscription is tower-side and self-closing;
  the tower's name rides the tower marker's name field; the worker's socket
  basename rides the worker registry's `inbox` column). The
  fleet-coordination-floor doctrine's lifecycle-closure contract amended by
  exactly one class, the inbox socket: one row in the class contract table
  and one column in the rungs-by-classes table, every cell filled, and no
  other change to the file (REQ-G1.6). The inter-orchestrator-coordination
  doctrine amendment covering its steer-in-flight section (its heading
  included), its "one audited script" sentence and `relay-command`
  description, and its tower-to-tower clause in the *Attributed,
  non-impersonating relay* section (REQ-G1.7). The backend capability
  contract doc gaining only the messaging-eligibility derivation rule from
  the `Session-grade` column
  and its distinction from dispatch eligibility (no probe definition there,
  no new column, no adapter-field change; D-17). `config/defaults.yml`
  entries, options-reference rows, and `docs/fleet.md` knobs-table rows for
  `messaging_discipline`, `messaging_cross_machine`, and
  `messaging_heal_cadence_seconds`, where the `messaging_discipline` row
  lists all four values — `off`, `script`, `tiered`, `open` — with `off`
  described as the per-fleet kill switch outside the ladder, the value that
  makes the probe read absent so every consumer takes the messaging-absent
  path (REQ-F1.2, D-4), and the `messaging_cross_machine` row states it is
  the documented cue to relax `isolatePeerMachines` (REQ-F1.6). An
  `/orchestrate` diet restoring headroom for the growth Tasks 1, 5, 6, and 8
  plan, with a per-task word allotment recorded in the PR. The
  doctrine index updated.
- **Done when:** the doctrine doc resolves through the rule-doc chain and
  `mise run check:doctrine-index` and `mise run check:links` pass with it
  indexed; each of the nine named doctrine contents and REQ-G1.6's
  declaration is present, reviewed design-level in the task PR, the
  discipline ladder reads `script` < `tiered` < `open`, the fallback
  table names a fallback for each path in D-13's set — the tower's own
  wake row naming today's metronome among them — and reads its two
  downward rows per rung (the `tmux`, `stream-json-persistent`, and
  `headless-oneshot` cells each present), the signal-vs-record rule
  carries the turn-ending-stop sentence, and the fleet-runtime version
  rule is present (literal-token greps for each); the
  fleet-coordination-floor doctrine's
  class contract table gains exactly one row, its rungs-by-classes table
  exactly one column with every cell filled, and the diff shows no other
  change to that file; the three inter-orchestrator edits are present: the
  steer-in-flight section, heading included, reads messaging-first with
  attributed buffer-paste as the fallback, the "one audited script"
  sentence and the `relay-command` description name `fleet-messaging.sh` as
  the enforcement point the relay delegates to, and the tower-to-tower
  clause cross-references the advisory rule; the contract doc states the
  derivation rule and the distinction from dispatch eligibility, and adds
  nothing else, and `scripts/check-backend-capability-drift.sh` passes with
  the adapter arity unchanged; each of the three knobs has all three
  documentation surfaces with its default and `mise run check:options`
  passes, and all three of `messaging_discipline`'s surfaces list its four
  values with `off` named the kill switch outside the ladder (literal-token
  greps for `off`, `script`, `tiered`, and `open` in each);
  `mise run check:instructions` exits 0 with no pending-diet
  allowance, the new doctrine plus the growth of the
  inter-orchestrator-coordination doctrine fitting inside the headroom this
  task measures for `/orchestrate` before writing either (at the kickoff the
  closure margin is 1009 words against a floor of 1000, and the skill file's
  margin is 253 against a floor of 250), and the diet restores enough of
  both margins to cover the per-task allotment this task records.
- **Dependencies:** none
- **Citations:** D-3, D-4, D-5, D-13, D-16, D-17, D-20 · REQ-A1.6,
  REQ-E1.1, REQ-E1.2, REQ-F1.2, REQ-F1.3, REQ-F1.6, REQ-G1.1, REQ-G1.2,
  REQ-G1.3, REQ-G1.5, REQ-G1.6, REQ-G1.7, REQ-H1.2 · obs:4c25e743
- **Estimated effort:** 2 days

### Task 2 — The enforcement point: `fleet-messaging.sh`

- **Deliverables:** `scripts/fleet-messaging.sh` with the signatures D-12
  states: `probe` (the invoking session's availability:
  `CLAUDE_CODE_MESSAGING_SOCKET` set and naming an existing socket owned by
  the invoking user, plus the CLI version compared numerically per dotted
  component against the documented minimum, 2.1.248 unconditionally, plus
  the session's effective `crossSessionInbound` resolving to `accept`,
  read from the CLI's settings files in their precedence order (user, then
  project, then local) — an unmerged tower profile reads absent rather
  than silently losing every notice — plus the resolved
  `messaging_discipline` not being `off`: that switch value sits outside
  the ladder and makes the probe read absent by design, the per-fleet kill
  switch REQ-F1.2 places one overlay layer away from any harness setting;
  test seam `--cli-version`), `eligible <rung> --launch <bare|normal>` (reads
  `orchestrate-backends.sh caps <rung>` and applies the D-17 derivation),
  `effective-mode --direction <worker-to-tower | tower-to-worker |
  tower-to-tower>` (the oracle carries all three directions; knob
  resolution through the overlay layers, send-time pressure demotion from
  `fleet-usage-gate.sh rung`, saturating at `script`, one stderr notice per
  demoted send, and a knob resolving to `off` refused with a diagnostic
  naming it the switch value outside the ladder — the direction and
  pressure offsets apply to the three ladder values alone, and a fleet at
  `off` reaches no send path to consult the oracle),
  `send --to <socket path> | --to-worker <handle>
  --message-file <path>` (the body read from the file and posted as data,
  returning the outcome the post yields; `send` mints the message id itself,
  a UUID, and writes it into the frame beside the reply address, printing it
  on stdout for every post that was written, accepted or held, and posts no
  auth line; the owner/existence predicate
  applied to the target socket first; `--to-worker` names the worker
  registry's `worker` column and resolves that row's
  `inbox` basename against the invoking session's own socket
  directory, and `send` carries the tower→worker direction only — upward
  traffic is the harness's idle notice and the tower↔tower advisory is
  model-composed — so it takes no direction argument),
  `notice-read <session name>` (the name the tower's prose reads from an
  idle notice, screened as data — printable ASCII, no path separator, at
  most 128 bytes, a different, path-safe screen from the handle grammar
  `orchestrate-relay.sh validate-handle` applies — matched against the
  worker registry's `name` column, then delegating to
  `fleet-attention.sh render --worker <handle>` — the worker-selecting
  arity this task adds to `fleet-attention.sh` — for that row),
  `self-name` (prints the session's observed name from
  `~/.claude/sessions/$CLAUDE_PID.json`, exiting non-zero when the record is
  absent or carries no name),
  `self-register` (run from the session's own SessionStart hook, never
  from a seam: it reads the invoking session's per-session record, taking
  the name from `self-name`, and, for a worker, amends its
  registry row's `name` and `inbox` columns through `fleet-state.sh amend
  <worker> --name --inbox`, that verb and its `fleet-register.sh`
  pass-through being Task 4's; a session without the worker identity
  environment takes the tower arm and writes nothing at all, the `--watch`
  loop recording the tower marker's name at loop start with
  `fleet-tower-marker.sh record --name` carrying `self-name`'s output), and
  the socket owner/existence predicate verb (test seams `--owner-uid` and
  `--socket-type`); the `PLANWRIGHT_MESSAGING_POST` post seam per D-12's
  contract: the variable names an executable invoked with the real post's
  argv and the body on stdin, which appends one record per call (argv and
  body) to `$PLANWRIGHT_MESSAGING_POST_LOG`, prints the outcome line on
  stdout or nothing, and exits with the write result; the
  `PLANWRIGHT_TEST_SEAM=1` guard on every seam (REQ-H1.5). The
  wire-contract verification as the task's first step, `[manual]`: in a
  live non-`--bare` session with the socket bound, on a CLI at or above
  the last-verified pin, observe what a raw socket post must write and
  whether any outcome comes back, with two admissible outcomes — a
  response line observed, or none, in which case write success or failure
  becomes the outcome (REQ-C1.5, D-12) — and, posting with the invoking
  session's socket as the reply address to a receiver set to refuse,
  whether a status frame arrives at that address (its shape recorded, or
  its absence, in which case surface-only recovery stands, D-9) — all
  frozen in the drift guard. The same step records the six behaviors
  D-11 lists, each with its observable, before any task relies on them:
  whether `crossSessionInbound: hold` or `refuse` gates an idle notice and
  what a second `notify_when_idle` on a live subscription does (the
  transcript line), whether `--name` applies beside `--worktree
  --tmux=classic` (the launched session's observed name), whether
  `CLAUDE_PID` reaches a SessionStart hook's environment (the hook's
  captured environment), whether a held message is released when the
  receiver relaxes to `accept` (the receiving session's transcript; either
  outcome recorded, both passing), and in
  which session types the harness's
  scheduled wakeup is available (a turn started at the requested instant,
  tried in interactive tmux, in `-p`, and in a watchdog-launched tower,
  interactive with an initial prompt) — that last one observed from the
  session's own model requesting the wakeup, the session-driven half of this
  step rather than the socket post the other five ride. The
  platform-contract drift guard, a fixture under `tests/` and not a
  `scripts/*.sh` file, so the REQ-H1.3 audit's match set never reaches the
  env var names it freezes, carrying the last-verified
  pin (2.1.259 initially), the documented minimum, the two env var names,
  the observed post framing, the reply-address field and the status-frame
  shape (or their absence), and the observed field shape of the CLI's
  per-session record `~/.claude/sessions/<pid>.json` `self-register`
  consumes
  (D-11, D-8). The notice's rendered line shape, recorded in the
  requirements' Sources, is frozen as a `[manual]` drift observation Tasks 2
  and 6 re-read — the two whose environment holds a watched worker — and the
  smoke runner re-reads once Task 7 has landed, never a parser fixture: no
  shipped
  script parses that line, the tower's prose reading only the quoted
  session name from it (D-21). Fixture tests for probe parsing,
  eligibility derivation, session-name screening refusal, knob resolution,
  outcome handling, and echo sanitization. The
  literal source audit (REQ-H1.3). The REQ-A1.5 comparand set, frozen as
  the base-commit values (`git show <base>:<file>`, `<base>` resolved from
  a one-line file under `tests/fixtures/` this task writes, one per
  comparand, which the fixture reads): the one-shot forms
  `fleet-dashboard.sh write --out`'s page and `fleet-attention-watch.sh
  watch --once`'s stdout plus its signature file, and the commands
  `orchestrate-relay.sh` and `fleet-decision.sh` emit, over a fixture store
  carrying no answered-undelivered case, so Task 7's surfacing does not
  move a comparand frozen here. `hooks/hooks.json`
  is outside the frozen set: no consumer of the signal transport is
  hook-mediated (D-20), so the file has no pre-messaging behavior for
  REQ-A1.5 to freeze. `fleet-attention.sh` gains the `render --worker`
  arity and a header citing `doctrine/messaging-transport.md`, and nothing
  else: its four signal write verbs (`heartbeat`, `decide`, `fork`, `park`)
  stay
  byte-identical to this task's base commit, and the whole-file audit
  belongs to Task 6, whose base already carries the added arity. The
  script's own header cites `doctrine/messaging-transport.md`.
- **Done when:** `probe` reads available with the variable set, a socket
  passing the predicate, an injected `--cli-version` at or above
  2.1.248, a fixture settings tree resolving `crossSessionInbound` to
  `accept`, and `messaging_discipline` resolving to a ladder value, and
  absent on each negative (variable missing or malformed, socket failing
  the predicate, version below the minimum, the acceptance conjunct
  resolving to `hold`, to `refuse`, or to nothing at all, and a fixture
  overlay resolving `messaging_discipline` to `off` with every other
  conjunct satisfied); the settings fixture builds that tree by relocating
  `HOME` and the
  working directory so the user, project, and local layers are real files,
  adding no seam, and asserts the precedence order, a local layer
  overriding a project layer overriding a user layer in both directions
  (a local `accept` over a project `refuse` reads available, the reverse
  reads absent), while an exported `PLANWRIGHT_MESSAGING_INBOUND=accept`
  reads available both over a tree carrying no value at all and over a
  project layer carrying `refuse`, the exported value standing for the
  `--settings` command-line layer and outranking every file; the settings
  and per-session record parses are awk-based with no `jq`
  (bootstrap REQ-K1.5), `crossSessionInbound` is read as a top-level
  settings key, and a parse failure reads absent; `eligible`
  maps the four cases (session-grade `yes` launched non-`--bare` is
  eligible; `no`, `deferred`, and an unknown or malformed value are
  ineligible; `yes` launched `--bare` is ineligible) and the send
  precondition refuses on either conjunct alone (probe absent with a
  recorded target path; probe available with no recorded target path);
  `send --to-worker <handle>` matches the handle against the registry's
  `worker` column, binding the worker's last registry record, resolves that
  row's `inbox`
  basename against the invoking session's own socket directory and posts
  there (the resolved path appears in the seam's recorded argv), a handle
  with no registry row, or one whose `inbox` column still holds the `-`
  sentinel, refuses the send with an empty
  post log, and `send --to <socket path>` still accepts a path directly;
  `send` prints a message id on stdout for every post that was written,
  accepted or held, and writes that same id into the posted frame beside
  the reply address, posting no auth line (the id `fleet-decision.sh`
  records, Task 5);
  `effective-mode` resolves each of the three directions and refuses a
  fourth, and refuses a knob resolving to `off` with a diagnostic naming it
  the switch value outside the ladder rather than offsetting it; each of
  the four post outcomes (accepted, held, refused, a
  failed post)
  forced through the post seam drives its stated branch, an empty seam
  stdout exercising the write-success fallback; a `send` whose target
  fails the owner/existence predicate (`--owner-uid`, `--socket-type`)
  never reaches the post seam (call counter at zero); a demoted
  `effective-mode` invocation
  writes exactly one stderr notice and an undemoted one none; the fleet
  state directory listing outside `usage/`, which `fleet-usage-gate.sh`
  legitimately writes into, is byte-identical across an `effective-mode`
  sequence; the four sanitized outputs (the `notice-read` refusal
  diagnostic, the held notice, the demotion notice, and `notice-read`'s
  own output) pass the echo-sanitization fixture, and a closure grep over
  the script's `printf` and `echo` sites finds no other site interpolating
  a message-derived field; each of the four hostile `notice-read` fixtures
  — a name carrying control bytes, an over-length name (over 128 bytes), a
  name carrying a path separator, and a well-formed name matching no
  registry row's `name` column — is refused with a sanitized diagnostic and
  reads
  no store row, and a name `validate-handle` would accept that this
  path-safe screen refuses is refused too;
  `self-name` prints the fixture record's name and exits non-zero when the
  record is absent or carries none;
  `self-register` reads the record named by `CLAUDE_PID` from a fixture
  session directory and, with the worker identity environment set, emits
  `fleet-state.sh amend <worker> --name --inbox` carrying that record's
  `name` and the basename of its `messagingSocketPath` (the invocation
  captured by a `PATH`-shadowed recorder, no new seam), refuses a record
  whose `name` fails the session-name screen, writes exactly one stderr
  notice and emits nothing when `CLAUDE_PID` is unset or names no record,
  and is a silent no-op without that environment (the tower arm);
  every seam is refused with a diagnostic when `PLANWRIGHT_TEST_SEAM=1` is
  unset; the drift guard exits non-zero with a stderr diagnostic naming
  the failed assumption when the pin is absent or a frozen assumption is
  violated, the per-session record's field shape included; the
  wire-contract observation and the notice's rendered line shape are both
  recorded in the task PR, the first frozen in the guard and the second
  carried as the `[manual]` drift observation; each of D-11's six
  wire-step behaviors (notice gating under `hold` and under `refuse`, a
  second `notify_when_idle` on a live subscription, `--name` beside
  `--worktree --tmux=classic`, `CLAUDE_PID` in a SessionStart hook's
  environment, the release of a held message when the receiver relaxes to
  `accept`, and the scheduled wakeup's availability per session type, that
  last one observed from the session's own model)
  is recorded in the task PR with its observed outcome and its observable,
  and frozen in the guard; the
  source audit passes with its literal match set, the script's `claude`
  invocation count is exactly one (the probe's version read), and
  `SendMessage` and `ListAgents` appear in no `scripts/*.sh`; the header
  cites `doctrine/messaging-transport.md`; `fleet-attention.sh render
  --worker <handle>` returns the named worker's row and no other (fixture),
  its four signal write verbs (`heartbeat`, `decide`, `fork`, `park`) are
  byte-identical to their text at this task's base commit
  (`git show <base>:scripts/fleet-attention.sh`, `<base>` read from this
  task's recorded base-SHA file), and its header cites
  `doctrine/messaging-transport.md`; each comparand's base-SHA file exists
  under `tests/fixtures/` and the comparand fixtures read it and equal the
  base-commit values; `mise run lint:shell` and
  `mise run scan:secrets` pass; the task records the observed CLI version
  in its PR and raises the last-verified pin, never lowers it (a running
  CLI below the pin halts the task).
- **Dependencies:** 1
- **Citations:** D-4, D-8, D-11, D-12, D-17, D-20, D-21 · REQ-A1.1, REQ-A1.4,
  REQ-A1.5, REQ-A1.6, REQ-C1.5, REQ-D1.6, REQ-D1.7, REQ-F1.2, REQ-F1.3,
  REQ-F1.4, REQ-H1.2, REQ-H1.3, REQ-H1.4, REQ-H1.5
- **Estimated effort:** 3 days

### Task 3 — Settings profiles and their documentation

- **Deliverables:** per D-19, the two shipped settings profiles and their
  documentation: `crossSessionInbound: accept` in
  `config/worker-settings.json`, tower acceptance in
  `config/tower-settings.json`, and `isolatePeerMachines: true` in both —
  the tower is the session that receives idle notices and tower↔tower
  advisories, so its acceptance key is load-bearing; the worker profile's
  `_about` header rewritten for the `--settings` route these keys now
  travel, its manual-merge sentence (written for a profile an operator
  copies into their own settings scope) replaced by the route a dispatched
  worker actually receives, and carrying the note that the profile's own
  guard hook stays dead under `--settings` until
  `worker-permission-ergonomics` lands (obs:a4a4fa59) while the messaging
  keys apply regardless; the tower profile's `_about` header rewritten the
  same way, naming both routes it now travels — the `--settings` flag at a
  fleet tower launch and the operator's own merge for an
  operator-launched tower — and carrying the same dead-hook note for its
  own `PreToolUse` stanza. No guard is re-scoped and no seam is wired here:
  in D-19's words, each seam builds its own launch line after validating
  any caller-supplied extras, so `fleet-dispatch-worktree.sh`'s
  launch-argument pin never sees the profile flag, and the tower
  command-guard auto-approves planwright's own scripts wholesale, so it
  never sees the launch either; the seam wiring itself is Task 4's.
- **Done when:** `mise run lint:json` passes and a `jq -e` fixture asserts
  `crossSessionInbound == "accept"` and `isolatePeerMachines == true` in
  the worker profile and the same two keys in the tower profile;
  `mise run check:hook-contracts` passes with the rewritten headers; a grep
  over the worker profile's `_about` header finds the `--settings` route
  named in place of the manual-merge instruction, and finds the note that
  its guard hook stays dead under `--settings` until
  `worker-permission-ergonomics` lands while the messaging keys apply
  regardless (both literal tokens present in one sentence), and the same
  grep over the tower profile's `_about` header finds both of its routes
  named and the same dead-hook note; `[manual]` a
  model-composed cross-machine send prompts for approval with
  `messaging_cross_machine` on and with it off alike (the environment: a
  session carrying the tower profile plus a second machine or a cloud
  session; the observable: the harness's approval prompt), recorded in the
  task PR; the task re-verifies against the running CLI, records the
  observed version in its PR, and raises the last-verified pin, never
  lowers it (a running CLI below the pin halts the task).
- **Dependencies:** 1
- **Citations:** D-5, D-11, D-19 · REQ-A1.4, REQ-F1.1, REQ-F1.6 ·
  obs:eea622de, obs:58aa232e, obs:a4a4fa59; the
  `worker-permission-ergonomics` pending note (Sources)
- **Follow-on:** when the `worker-permission-ergonomics` amendment lands,
  Task 4's `--settings` wiring migrates onto its profile-delivery
  mechanism without changing the settings content these profiles carry.
- **Estimated effort:** 1 day

### Task 4 — Addressable identity and profile delivery at the seams

- **Deliverables:** `--name` derivation from the per-backend fleet handle
  grammar `orchestrate-relay.sh` owns (`validate-handle`) at the three
  worker dispatch seams (`tmux`, `stream-json-persistent`,
  `headless-oneshot`) and at the three fleet tower launches — the
  watchdog's `tmux` relaunch, a script, so `[test]`; the meta-tower's
  subordinate and the continue-as-new handover, which reach
  `scripts/fleet-tower-launch.sh` below, so that script's argv is `[test]`
  and the prose steps invoking it stay `[design-level]` — a custom
  `PLANWRIGHT_TOWER_LAUNCHER` being
  out of scope (REQ-B1.1). A `validate-handle` arm in
  `orchestrate-relay.sh` for the two rungs it does not carry yet,
  `stream-json-persistent` and `headless-oneshot`, so every shipped worker
  rung's derived name has an owning grammar. The worker identity
  environment (`PLANWRIGHT_WORKER_HANDLE`, `PLANWRIGHT_WORKER_SCOPE`)
  exported at every session-grade dispatch seam, where today only the
  `headless-oneshot` seam exports it (obs:fbb701bc), so the hooks that
  write attention rows — and the registering hook below — run for every
  worker a tower can be woken about (REQ-B1.1, D-8). The profile delivery
  D-19 places at those same seams: `--settings <profile>` on every one of
  those launch lines, the worker profile at the three worker seams and the
  tower profile at the fleet tower launches, with
  `PLANWRIGHT_MESSAGING_INBOUND=accept` exported beside it as the
  command-line layer the probe reads (D-17), and a seam that cannot read
  its profile failing visibly rather than launching without it
  (obs:eea622de). `scripts/fleet-tower-launch.sh`, a thin launcher wrapping
  the meta-tower's subordinate launch and the continue-as-new handover: it
  passes `--settings` with the tower profile and exports
  `PLANWRIGHT_MESSAGING_INBOUND=accept`, so the tower command-guard approves
  it wholesale the way it approves `fleet-dispatch-worktree.sh` rather than
  deferring on the `--settings` flag those two launches would otherwise
  carry as classifier-exposed Bash strings. The self-registration path: the
  worker registry's two
  added columns, `name` and `inbox`, written as the store's `-` sentinel
  at registration (`fleet-state.sh register`) and filled afterwards by a
  new `fleet-state.sh amend <worker> --name --inbox` verb reached through
  `fleet-register.sh`'s per-field degrade, whose caller is the session's
  own SessionStart hook running `fleet-messaging.sh self-register` (Task
  2's verb): the plugin's `hooks/hooks.json` SessionStart entry runs
  `self-register`, whose own worker-identity guard makes a tower session's
  hook a no-op, that tower's observed name reaching the tower marker at
  `--watch` loop start instead, written with `fleet-tower-marker.sh record
  --name` carrying `fleet-messaging.sh self-name`'s output. No seam reads
  anything back —
  there is no post-launch read-back step, no retry window, and no `cwd`
  matching — so a worker whose hook never runs keeps both sentinels, is
  unaddressable (downward delivery falls back), and is never subscribed.
  The two added columns hold bare values, not `key=value` tokens; the
  registry's own field charset is the narrowest of the three name screens,
  so a name the session-name screen admits but the store refuses is not
  written and the row keeps its sentinel; and `amend` and `send
  --to-worker` bind the worker's last registry record, the append log's
  existing last-record-wins convention.
  The scripts that parse the registry file, re-derived by grep at this task
  (today `fleet-status.sh`), plus the readers this bundle adds, tolerate
  rows of three, seven, and nine columns — the store's legacy, current, and
  new arities. The tower
  marker's one added field, the observed name — no tower socket path is
  ever recorded, nothing posting to a tower socket (D-8, D-20) — carried
  on a `--name` flag with its own validator in `fleet-tower-marker.sh`
  (record, read, and validators), with both readers
  (`fleet-tower-signpost.sh`, the watchdog's marker reader) accepting
  seven- and eight-field rows; the marker is written at `--watch` loop
  start and cleared on graceful exit, and a single-step tower writes no
  marker and is addressed by a listing round-trip (D-8, D-14). Names
  validated as data before addressing, path use, or echo. No guard is
  re-scoped for the `--name` or the `--settings` shape: the seams build
  their own launch lines and the tower command-guard auto-approves
  planwright's own scripts wholesale (D-19).
- **Done when:** every derived name passes `orchestrate-relay.sh
  validate-handle` for its rung, the new `stream-json-persistent` and
  `headless-oneshot` arms included (fixture per rung, hostile names
  refused); each of the three worker dispatch seams' emitted launch
  environment carries `PLANWRIGHT_WORKER_HANDLE` and
  `PLANWRIGHT_WORKER_SCOPE` with the dispatched worker's handle and scope
  (one env fixture per rung), and a seam that cannot derive either exits
  non-zero naming the missing one; each of those three seams and the
  watchdog's relaunch emits `--settings <profile>` in its launch argv,
  naming `config/worker-settings.json` and `config/tower-settings.json`
  respectively, and exports `PLANWRIGHT_MESSAGING_INBOUND=accept` beside
  it (argv and environment fixture per seam), while a seam that cannot
  read its profile exits non-zero with a stderr diagnostic naming it (the
  injector is the existing planwright-root override, `PLANWRIGHT_ROOT`
  pointing at a temp copy whose profile is unreadable, with no new seam);
  `scripts/fleet-tower-launch.sh`'s argv carries `--settings` naming
  `config/tower-settings.json` and its environment carries
  `PLANWRIGHT_MESSAGING_INBOUND=accept` (argv and environment fixture), and
  a guard-classification check records that the tower command-guard approves
  the script wholesale rather than deferring on a flag; the meta-tower's and
  the handover's launch steps are reviewed
  design-level in the task PR for the derived name, the profile, and the
  guard's verdict on the launch as the script now shapes it;
  `fleet-state.sh register` writes `-` in both added columns and
  `fleet-state.sh amend <worker> --name --inbox` replaces exactly those
  two, every other field of the row unchanged by a before/after diff, with
  `fleet-register.sh`'s pass-through degrading per field (an amend that
  cannot write one field still writes the other and exits non-zero naming
  it); `hooks/hooks.json` carries the SessionStart entry running
  `fleet-messaging.sh self-register`, whose own worker-identity guard makes
  a tower session's hook a no-op,
  `mise run check:hook-contracts` passes, and a fixture
  drives that entry end to end — with the environment and a captured
  per-session record present the row's `name` column equals that
  record's `name` and its `inbox` column the basename of its
  `messagingSocketPath`, both as bare values, and with the hook never run
  the row keeps both
  sentinels, `send --to-worker` refuses that worker with an empty post
  log, and the start-of-tower subscribe pass skips it; a name the
  session-name screen admits but the registry's field charset refuses
  leaves the sentinel in place (fixture); each reader the grep derives, plus
  each reader this bundle adds, parses a three-, a seven-, and a
  nine-column row (fixture per reader), the nine-column arm asserting the
  two added values by field position for the readers that surface them and
  tolerance alone for the readers that surface no added field; the marker is
  written at `--watch` loop start, absent
  at the end of an `/orchestrate` step that starts no watch loop, and
  removed on graceful exit (fixtures); every marker carries the name field
  at its declared field position (the mixed-arity fixture asserts the
  parsed value by position, not merely that the row was accepted, the
  signpost's failure mode being a silent skip) and both readers parse
  seven- and eight-field rows, while a nine-field row is skipped silently
  by the signpost and escalated as ambiguous by the watchdog's marker
  reader; the launch argv with the probe absent equals the argv with it
  present (the REQ-A1.5 naming comparand); hostile name input is refused
  at the marker's `--name` flag, at the registry write, and on read
  (fixture); `[manual]` a worker on each of the three shipped rungs
  (`tmux`, `stream-json-persistent`, `headless-oneshot`) appears in the
  sender-side listing under its derived name, and on `tmux` and
  `stream-json-persistent` accepts an inbound message unattended — the
  `tmux` arm's unattended acceptance is itself the observable for D-19's
  unverified interactive `--settings` case, no surface printing a session's
  effective inbound state (the
  environment: a tower and one dispatched worker per rung on the same
  machine, the operator away) — recorded in the task PR; `[manual]` a
  watchdog-relaunched tower (the environment: a tower killed mid-run and a
  watchdog tick that relaunches it) appears under its derived name,
  recorded in the task PR; `[manual]` the live collision check (the
  environment: two same-named launches on the kickoff host) records the
  observed outcome (rename, refusal, or duplicate) into D-8's amendment
  note and the task PR, where a refusal surfaces as the CLI's own non-zero
  exit at the dispatch seam and a duplicate is read off the sender-side
  listing rather than detected, no seam reading a name back, and a
  non-rename outcome amends D-8; the task re-verifies
  against the running CLI, records the observed version in its PR, and
  raises the last-verified pin, never lowers it (a running CLI below the
  pin halts the task).
- **Dependencies:** 2
- **Citations:** D-8, D-11, D-12, D-14, D-17, D-19, D-20 · REQ-A1.4,
  REQ-A1.5, REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-F1.1 · obs:d4d66281,
  obs:fbb701bc, obs:eea622de, obs:58aa232e
- **Estimated effort:** 2 days

### Task 5 — Downward delivery: steer and decision answers

- **Deliverables:** a messaging arm in `orchestrate-relay.sh` delegating to
  `fleet-messaging.sh send --to-worker <handle>`, the handle naming the
  registry's `worker` column (never the relay's per-backend handle, which
  only the fallback step uses) and the registry `inbox`
  resolution staying inside `fleet-messaging.sh`; `fleet-decision.sh`
  delivering through the same verb, its delivery reordered to
  claim → persist the answer artifact → deliver messaging-first → consume
  the post outcome → descend the fallback ladder (the rung's attributed
  steer delivery → operator handoff), never re-claiming; the
  `stream-json-persistent` carve-out (D-3, REQ-C1.1): `fleet-decision.sh
  answer` refuses that rung outright, with a diagnostic naming
  `fleet-streamjson.sh answer` as the path that resolves it, a message
  being unable to clear the pending control request the worker is blocked
  on; the tower obtains the full request id from `fleet-streamjson.sh
  status <worker>`, the supervisor's `decide` row carrying no id field of
  its own; the fork is still claimed and its answer artifact still
  persisted before the control response is written, so REQ-C1.2's ordering
  and REQ-C1.5's surfacing hold on that rung too; and messaging carries
  free-text
  steers only there, their fallback being operator handoff, no attributed
  steer delivery existing on that rung;
  both scripts performing the post in-process, with their headers and
  `fleet-decision.sh`'s exit-code table updated: exit 0 when the post was
  accepted or the fallback delivery command was emitted, exit 5 when the
  post was held (its stderr notice written, no store row, the message left
  queued at the receiver and never re-sent), exit 4 keeping today's meaning
  (delivery not completed after a successful claim) now reached as the
  ladder's terminal operator handoff, both of its sub-case messages
  standing, and today's 2 and 3 unchanged — accepted and held
  alike being completion of the attempt, not proof of delivery — while the
  relay's messaging arm reports held with that same code; the
  post carrying the tower's own inbox
  socket as its reply address (written by `send`, D-12), so the harness's
  status frames for a message come back to the tower, with `send` printing
  the message id for every post it writes and `fleet-decision.sh` recording
  it in the answer artifact's metadata sibling
  (`<fleet-home>/attention/answers/<worker>.meta`, one line per fork
  instance id, the attention store's fork discriminator: `<instance>`,
  the message id, the epoch) so a frame names a
  fork — never inside the artifact,
  whose whole content is what the attributed steer delivery carries; a
  `fleet-decision.sh redeliver --message-id <id>` verb — resolving the
  fork from the record carrying that id and emitting the
  attributed steer delivery command for its persisted answer, once per
  fork, never performing the delivery itself (the script cannot see it
  land),
  never a messaging post, never a re-claim, the once-per-fork record being
  a `redelivered` mark on that line, and refusing an id whose fork is not
  the artifact's current fork — and the `/orchestrate` standing
  instruction that a drop, expiry, or refused status frame for an answer is
  handled
  by exactly one `redeliver`, that a status frame read mid-turn is handled
  after the step's own work rather than interleaved, and that a status
  frame the tower holds or never receives leaves the healing sweep's
  answered-undelivered surfacing as the recovery (REQ-C1.5, D-9); each
  consumer's header naming its fallback and citing
  `doctrine/messaging-transport.md`.
- **Done when:** a refusal or a failed post forced through the post seam
  yields exactly one post attempt per ladder step (call counter), one
  stderr notice per step, and the stated exit code, all five codes being
  distinct and asserted per outcome (0 for an accepted post or an emitted
  fallback delivery command, 5 held, 4 the terminal operator handoff, and
  today's 2 and 3 unchanged), 4's two existing sub-case messages asserted
  per sub-case (the artifact persisted with the delivery unfinished, and
  nothing persisted), with the relay's messaging arm returning 5
  on a held post too; both consumers address
  the worker by `--to-worker <handle>` naming the registry's `worker`
  column, never by a path they resolved
  themselves (source audit: neither script reads the registry's `inbox`
  column); on `stream-json-persistent` `fleet-decision.sh answer` exits
  non-zero with a diagnostic naming `fleet-streamjson.sh answer` and never
  reaches the post seam (empty post log), the tower resolves the full
  request id through `fleet-streamjson.sh status <worker>`, the fork is
  claimed and its answer artifact written before the control response, and
  a
  free-text steer on that rung posts once and falls back to operator
  handoff on a refusal, skipping the attributed steer delivery step
  (fixtures); `send` prints a message id for every post it writes, accepted
  or held, and
  `fleet-decision.sh` writes that id into `answers/<worker>.meta` keyed by
  fork
  instance id while the answer artifact stays byte-identical to the shape
  it has today, a second fork for the same worker adding a second keyed
  record and leaving the first in place (fixtures); a
  steer-less rung
  receives no delivery; an induced delivery failure leaves the fork's claim
  field unchanged (before/after diff) and the persisted artifact recovers
  the answer; the claim verb appears at exactly one call site in
  `fleet-decision.sh` (source audit); with the probe forced absent, the
  commands both scripts emit equal the frozen comparand (REQ-A1.5); the
  message body is read from the file and posted as data (the fixture finds
  the body in the seam's recorded payload and absent from the command
  line); the seam's recorded frame carries the invoking session's own
  socket path as its reply address (fixture); `redeliver --message-id <id>`
  resolves the fork from the record carrying that id, emits the
  attributed steer delivery command for its persisted answer and does
  nothing else (post log empty, claim field unchanged, no attributed steer
  delivery performed), writes exactly one `redelivered` mark on that line,
  and
  refuses an id no record carries, an id whose fork is not the artifact's
  current fork, and a second call for the same
  fork (fixtures); the `/orchestrate` prose contains the standing
  instruction naming `redeliver` for a drop, expiry, or refused frame, the
  rule that a status frame read
  mid-turn is handled after the step's own work, and the held-frame case,
  which runs the step's own first action instead, its recovery being the
  sweep's answered-undelivered surfacing and not a
  second `redeliver` (greps); `mise run check:instructions` exits 0 with no
  pending-diet allowance; the
  literal `send-keys` grep finds nothing in the
  messaging arm; the review that a delivered message cannot approve a
  permission prompt, a platform guarantee rather than a repo behavior, is
  recorded in the task PR; each touched consumer's header names its
  fallback, that
  fallback appears in the doctrine's fallback table, and the header cites
  `doctrine/messaging-transport.md`; `[manual]` a live `tmux` check (the
  environment: a tower and one dispatched `tmux` worker on the same
  machine) delivers an answer end to end — the post reports accepted and
  the worker's transcript shows the answer text attributed to the tower
  session — recorded in the task PR; `[manual]` the live held check, in
  that same two-session environment with the
  receiver's profile set to `crossSessionInbound: hold`: one stderr
  notice and no store row while the receiver holds, then either outcome
  recorded when the setting is relaxed — the answer delivered exactly once,
  or the queued message discarded — since the sweep's answered-undelivered
  surfacing carries the case either way, recorded in the task PR; the task
  re-verifies
  against the running CLI,
  records the observed version in its PR, and raises the last-verified
  pin, never lowers it (a running CLI below the pin halts the task).
- **Dependencies:** 2, 3, 4
- **Citations:** D-3, D-9, D-11, D-12 · REQ-A1.4, REQ-A1.5, REQ-A1.6,
  REQ-C1.1, REQ-C1.2, REQ-C1.4, REQ-C1.5, REQ-G1.1, REQ-H1.3 ·
  obs:efe0b752, obs:b7618838
- **Estimated effort:** 2 days

### Task 6 — Upward signals: idle notices, the sweep, and the event-driven loop

- **Deliverables:** the three `/orchestrate` prose steps D-21 fixes — a
  subscribe step immediately after the dispatch step, taking out the
  harness's one-shot `notify_when_idle` subscription on each dispatched
  worker, conditioned on the tower's own probe reading available; a
  re-subscribe step after each downward delivery the tower makes,
  unconditional on any prior subscription (a duplicate or expired one is
  harmless; the subscribe step's probe condition still applies);
  and the sanction, written as a standing instruction the skill states
  once so it persists in the session after a step exits: on a notice the
  tower runs `fleet-messaging.sh notice-read <session name>`, and in
  `--watch` mode no fleet read in that iteration precedes that invocation
  and no action is derived from the notice other than it, the
  notice's status line being untrusted instruction data the store re-read
  is the only sanctioned action on (REQ-D1.7, REQ-H1.4). The
  start-of-tower subscribe pass over the reconcile sweep's in-flight
  worker set, run at the start of a tower that outlives its step, since a
  fresh tower after a watchdog relaunch or a continue-as-new handover
  holds no subscriptions; it derives that set from disk, addresses every
  subscription by the registry's recorded `name` column and skips a worker
  carrying none, and a single-step tower whose session ends with the step
  takes no subscription. The event-driven `--watch` loop D-22 fixes
  (REQ-D1.8): the loop ends the tower's turn after each step instead of
  sleeping inside one long turn, and the harness wakes it for the next
  step on a worker's idle notice, on a peer message (a status frame, D-9;
  an advisory, D-14), or on the timer — the harness's scheduled wakeup
  requested at step end at the healing cadence, whose availability per
  session type Task 2's wire step records. The metronome is not deleted
  but made conditional: the loop keeps it for a step whose probe reads
  absent, for a session type where the wakeup is unavailable, for a `-p`
  tower (the continue-as-new handover launches `claude -p`, so a
  handed-over tower keeps it), and for a step that ends with neither a
  live subscription nor an available wakeup; the subagent backend's
  existing event-driven arm stands unchanged. The ordering rule: a
  notice-driven turn runs `notice-read` first, a drop, expiry, or refused
  status frame's turn `redeliver` first, a held frame's turn the step's own
  first action, a timer-driven turn the reconcile sweep first, and an
  advisory turn the step's own first action, none of them dispatching,
  claiming, or writing outside the step's own rules, and a status frame
  read mid-turn handled after the step's work. Where more than one wake
  source is pending the order is `notice-read`, then `redeliver`, then the
  reconcile sweep, then the step's own first action, and the subscribe pass
  precedes all of them on a tower's first turn. Selector exit 1 (no ready
  unit) ends the turn awaiting a wake while a subscription is live and
  ends the watch otherwise. The continue-as-new handover seed carries the
  sanction sentence only: the subscribe pass derives the in-flight set
  from disk, so nothing about in-flight workers rides the seed. A pending
  amendment note, `specs/_pending/bootstrap-amendment.md`, in the same
  shape as the two existing notes, recording that bootstrap D-38's
  watch-loop metronome is retired by this bundle and routing the amendment
  to `bootstrap`, which owns that decision (D-38 is a spec decision, not a
  doctrine), and naming the `/spec-draft --extend bootstrap` invocation
  that drafts the amendment for real. That loop change is the one
  deliverable this task holds behind a gate: it lands only once the
  `## Deferred` entry below resolves — bootstrap signed off again on the
  D-38 amendment that note routes to it — so two signed designs never
  contradict each other in flight (REQ-D1.8, D-22); everything else here
  (the subscribe steps, the sanction, the start-of-tower pass, and the note
  itself) is ungated and lands with the task. The `/execute-task`
  `Doctrine:` manifest line for the
  messaging-transport doctrine. `fleet-attention.sh` is explicitly
  unchanged by this task: no write verb delegates to `fleet-messaging.sh`
  and no worker-side script posts upward, the retained sweep carrying
  every row written while a worker still runs (D-20; the `render`
  worker-selecting arity `notice-read` calls belongs to Task 2). The task
  ships skill prose and that one pending note; no script changes.
- **Done when:** the `/orchestrate` prose contains every sentence this
  task adds,
  each found by its own grep fixture naming a literal token — the
  subscribe step naming `notify_when_idle`, the re-subscribe step naming
  `re-subscribe`, the sanction naming `notice-read` and `--watch`,
  matching exactly once, so it reads as one standing instruction and not a
  per-step repetition, the start-of-tower subscribe pass naming the
  in-flight set it derives from disk and the registry's `name` column with
  its
  skip rule, the single-step carve-out, the three wake paths (the idle
  notice, a peer message, the timer as the harness's scheduled wakeup
  requested at step end), the conditions that keep the metronome (the
  probe absent, the wakeup unavailable for the session type, a `-p` tower,
  and a step with no wake source), the selector-exit-1 rule (the turn
  ended awaiting a wake while a subscription is live, the watch ended
  otherwise), the ordering rule naming the notice-driven,
  status-frame-driven (drop, expiry, or refused running `redeliver` first
  and held running the step's own first action), timer-driven, and
  advisory turns together with the
  mid-turn frame rule, and the wake-source order for a turn with more than
  one pending — `notice-read`, then `redeliver`, then the reconcile sweep,
  then the step's own first action, the subscribe pass preceding all of
  them on a tower's first turn;
  a step in `--watch` ends the tower's turn and the loop emits no
  unconditional in-turn sleep, asserted as a source audit of the skill
  prose: the metronome sentence's unconditional form is absent from
  `skills/orchestrate/SKILL.md` at this task's head while present at its
  base commit (`git show <base>:skills/orchestrate/SKILL.md`, `<base>` read
  from the one-line base-SHA file under `tests/fixtures/` this task
  records for that comparand), and the
  wake sentence is present — this audit, the wake-path grep set above, the
  three-wake `[manual]` arm below, and the notice-consumption `[manual]`
  criterion below are the gated half, evaluated when
  the Deferred entry's gate resolves, while every other clause here stands
  without it, and the pending note
  carries the `/spec-draft --extend bootstrap` invocation as the route to
  that sign-off (literal grep); `[manual]` an idle `--watch` tower is
  woken into a step by each of the three paths in turn — a worker's idle
  notice, a peer message, and the timer (the environment: a `--watch`
  tower in a tmux window and one dispatched worker on the same machine,
  both accepting);
  pass criterion: each wake starts a new tower turn whose first fleet
  action is the step's own, read from the tower's transcript, the kickoff's
  E4 having observed the notice and message wakes and the timer being the
  new one — the timer arm takes either outcome, and where Task 2's wire
  step recorded no scheduled wakeup for this session type the arm records
  that and the metronome-retention clause is what is verified instead;
  recorded in the task PR; `[manual]` a fresh tower after a
  watchdog relaunch subscribes over its in-flight set (the environment: a
  tower killed mid-run with in-flight workers and a watchdog tick that
  relaunches it); pass criterion: the relaunched tower's first turn takes
  one subscription per in-flight worker carrying a `name` value and none
  for a
  worker without one, read from that turn's tool calls; recorded in the
  task PR; a grep over the skill's handover step finds the sentence
  instructing the continue-as-new seed to carry the sanction, and finds no
  in-flight worker list carried beside it;
  `specs/_pending/bootstrap-amendment.md` exists and carries the five
  sections the two existing notes share, each gated by a literal-token
  grep — the seed-brief title naming `bootstrap`, the capture provenance,
  the `/spec-draft --extend bootstrap` invocation, the target's derived
  status with the reopen consequence that follows from it, and a "Why this
  is an amendment and not a new bundle" section citing bootstrap D-38's
  ownership of the `--watch` dispatch loop — plus the gap it records
  (D-38's metronome, with obs:8b694bdb as the duty-cycle evidence), and
  `mise run check:links` passes with it; `mise run check:instructions`
  exits 0 with no pending-diet allowance;
  `notice-read` refuses each of Task 2's four hostile fixtures and, for a
  name whose notice text contradicts the store, returns the store row's
  content and nothing drawn from the notice; `[manual]` in a live
  two-session environment (a tower and one dispatched worker on the same
  machine, run once on `tmux` and once on `stream-json-persistent`), a
  notice is enqueued at the tower within 10 s of the worker's first stop
  and a second within 10 s of the stop that follows a delivered steer,
  the observable being the receiving session's transcript timestamp on an
  idle tower, where enqueue and model delivery coincide (on a busy tower
  the notice reaches the model at its next turn boundary, which is
  unbounded and not this criterion, D-21); the same check run on
  `headless-oneshot` records whether the notice fires before the worker's
  process exits, either outcome passing, since the sweep carries the case
  either way (D-20), the `tmux` arm of the same run being the control that
  distinguishes a notice that did not fire from a subscription that failed;
  all three rungs' outcomes recorded in the task PR
  (the kickoff experiment saw about 1 s, brief §8);
  `[manual]` in that same environment, with the tower in `--watch`, the
  iteration that consumes a notice shows no fleet read before the
  `notice-read` invocation and no action derived from the notice other
  than it (the observable: that iteration's tool calls) — gated with the
  loop change, since a metronome tower runs no such iteration — recorded in
  the task PR; the existing liveness classification tests pass
  unmodified with notices absent (the baseline: absence is never read as a
  signal); a grep for
  `^Doctrine: (run-start|point-of-use) messaging-transport` matches in
  `skills/execute-task/SKILL.md`; `scripts/fleet-attention.sh` is
  byte-identical to its text at this task's base commit (resolved from that
  comparand's own base-SHA file under `tests/fixtures/`), which already
  carries Task 2's `render --worker` arity and doctrine header, so no
  write verb gained an upward post; the task re-verifies against the
  running CLI, records the observed version in its PR, and raises the
  last-verified pin, never lowers it (a running CLI below the pin halts
  the task).
- **Dependencies:** 2, 3, 4
- **Citations:** D-9, D-11, D-12, D-13, D-14, D-16, D-20, D-21, D-22 ·
  REQ-A1.4, REQ-D1.6, REQ-D1.7, REQ-D1.8, REQ-G1.5, REQ-H1.3, REQ-H1.4 ·
  obs:8b694bdb
- **Estimated effort:** 2 days

### Task 7 — The store-load reduction

- **Deliverables:** the demoted set, two consumers: the `--watch` loop's
  own store reads, which the event-driven loop makes wake-driven rather
  than cadenced (REQ-D1.8, D-22; Task 6's turn-end audit is that half's
  verification, and this task adds none), and
  `fleet-attention-watch.sh watch` run without an `--on-change` callback
  (the tower-facing pass), whose poll interval demotes to
  `messaging_heal_cadence_seconds` when the trigger holds, with its
  `reconcile_every` recomputed as
  `reconcile_every = max(1, round(300 / cadence))`, so the deep reconcile
  period is at least the pre-demotion period and within one demoted
  interval of it;
  the operator-facing cadences keep today's intervals, nothing pushing to
  the human: the watcher run with an `--on-change` callback and
  `fleet-dashboard.sh watch`'s projection refresh (`fleet-status.sh`
  has no loop); the trigger rule (the tower's own probe reads available
  and at least one in-flight worker carries a recorded
  `inbox` value — the dispatch-time proxy for the tower's subscription,
  which is prose-side and deliberately unrecorded, D-21 — re-evaluated
  each pass; both conjuncts are facts the tower reads off the store and
  its own environment, so nothing unrecordable gates the demotion), the
  knob validated at or below the attention watcher's default liveness
  max-age (900), and the `--interval` precedence per REQ-E1.1;
  in the attention
  watcher, the demotion targets a new poll-interval variable split from the
  event branches' timeout, so the `fswatch` and `inotifywait` timeouts stay
  byte-identical; a `docs/fleet.md` bring-up line for both watcher forms,
  the tower-facing pass that demotes and the `--on-change` form that does
  not, the script having no shipped caller today; the attention view
  marking a parked worker whose fork
  carries a persisted answer artifact as answered-undelivered (REQ-C1.5's
  surfacing, the healing sweep's operator-handoff case) — the third
  consumer this task touches is therefore `fleet-attention.sh`, whose
  header gains the healing-sweep clause beside the doctrine citation
  Task 2 added, and
  whose whole-file freeze in Task 6 is against Task 6's own base, not
  this task's; the demoted
  consumer's header naming the healing cadence and its fallback and citing
  `doctrine/messaging-transport.md`, and the dashboard's header citing it
  for the frozen-cadence rule; the doctrine's fallback table
  re-verified (Task 8 carries the same re-verification). The fleet smoke
  runner D-23 places here (REQ-A1.7): `scripts/fleet-smoke.sh` behind a new
  `smoke:fleet` mise task, whose live circuit never runs in CI while its
  dry-run mode runs in the shell suite — the standing
  CI-exclusion guard `check:no-ci-evals`, which today matches the `eval:`
  namespace and the two kept-eval runner names, extended to cover the
  `smoke:` namespace and `fleet-smoke.sh` too, so one guard keeps both
  classes out of the workflows — driving the full circuit on a host with a
  messaging-capable CLI: dispatch a worker, let it park, act on the park,
  answer, observe the worker resume, each step read from a named
  observable — the park is the worker's `awaiting-input` attention row, the
  notice and answer are the tower's answer post in the post log within
  120 s of that park row (the runner's own threshold), and the resume is
  the worker's next heartbeat row — printing the observed
  latencies and the before/after duty cycle and exiting non-zero on any
  missed step, with a dry-run mode over the post seam that carries its own
  fixture. The duty cycle is store reads per worker-minute over one runner
  pass, and the figure this task records is the runner's printed one, not
  one derived by hand; before the Deferred entry's gate resolves it is the
  watcher's figure, not the tower's. From this task's capstone run on, the
  runner is what re-verifying against the running CLI means for every later
  platform-touching change (REQ-A1.4).
- **Done when:** the demoted consumer's pre-reduction default interval is
  asserted
  against the task's base commit (`git show <base>:<file>`, `<base>` read
  from the one-line base-SHA file under `tests/fixtures/` this task records
  for that comparand) as a fixture;
  it keeps that interval when the probe reads absent or when no in-flight
  worker carries a recorded `inbox`
  value, and demotes to the knob when both conjuncts hold (fixture-forced
  each way); the demoted pass recomputes
  `reconcile_every = max(1, round(300 / cadence))` (fixture: the demoted
  deep-reconcile period is at least the pre-demotion period and within one
  demoted interval of it, asserted at a cadence that divides the base
  period and at one that does not); the frozen-interval fixture asserts the
  two
  operator-facing cadences unchanged against that same base commit — the
  watcher run with an `--on-change` callback and `fleet-dashboard.sh
  watch`'s refresh — under both trigger states; a
  `messaging_heal_cadence_seconds` above the watcher's default liveness
  max-age (901) is refused with a diagnostic naming the knob and the
  bound, and the bound itself (900) is accepted (fixtures); an explicit
  `--interval`
  wins over the knob
  (fixture); with no notice delivered (the subscription fixture never
  fires), one `fleet-attention-watch.sh watch --once` pass surfaces both
  rows — the row whose notice was missed and a row written while the
  worker was still running (the healing fixture REQ-D1.4 and REQ-E1.2
  share; the
  dashboard renders a projection and heals nothing, so it carries no arm
  here and its refresh keeps today's interval); a source diff against the
  task's base commit
  (`git show <base>:scripts/fleet-attention-watch.sh`, `<base>` read from
  that comparand's base-SHA file) shows the `fswatch`
  and `inotifywait` timeout sites byte-identical
  to it; the attention view marks a parked worker whose fork
  carries a persisted answer artifact as answered-undelivered (fixture); a
  source audit shows that neither `fleet-attention-watch.sh` nor
  `fleet-dashboard.sh` reads `messaging_discipline`; the
  existing store-schema fixtures pass unmodified and the diff touches only
  read and cadence sites (design-level review recorded in the PR); the
  doctrine's fallback table still names every path in D-13's set; all
  three touched consumers' headers cite
  `doctrine/messaging-transport.md`, the `fleet-attention.sh` header also
  carrying its answered-undelivered clause; `docs/fleet.md` carries a
  bring-up line for each watcher form, the demoting tower-facing pass and
  the `--on-change` form that keeps its interval (grep), and
  `mise run check:links` passes with it; the REQ-H1.3 audit passes with
  `fleet-smoke.sh` in the tree; `scripts/fleet-smoke.sh --dry-run`
  walks the circuit's five steps in order over the post seam and a fixture
  registry (the order read from the post log and the runner's own step
  lines), exits 0 having printed a latency line per step and one
  before/after duty-cycle line, and exits non-zero naming the missed step
  when a fixture withholds that step's observable — the park row, the
  answer post inside the 120 s window, or the following heartbeat row —
  one arm per step;
  `mise.toml` carries the `smoke:fleet` task, `mise run check:no-ci-evals`
  passes with that guard extended to the `smoke:` namespace and the
  `fleet-smoke.sh` runner name, and a fixture workflow wiring either form
  fails it; `[manual]` the capstone run, one `mise run smoke:fleet` on this
  host (the environment: a `--watch` tower in a tmux window and one worker
  dispatched on the same machine, both accepting; the observable: the
  runner's exit status and its printed step, latency, and duty-cycle
  lines); pass criterion: it exits 0 having observed every step of the
  circuit — dispatch, park, the tower acting on the park, the answer, the
  worker's resume — with its latencies and before/after duty cycle recorded
  in this task's PR, the pre-gate circuit passing when a metronome tower
  acts on the park on its next iteration, while the notice-wake arm and the
  duty-cycle figure are gated with Task 6's loop change and evaluated when
  the Deferred entry's gate resolves; the observation fragment is recorded
  via
  `scripts/obs-record.sh` carrying that printed duty cycle and the poll
  counts behind it, and `mise run check:obs` passes; the task re-verifies
  against the running CLI on that same run, records the observed version in
  its PR, and raises the last-verified pin, never lowers it (a running CLI
  below the pin halts the task).
- **Dependencies:** 2, 5, 6
- **Citations:** D-1, D-9, D-11, D-13, D-16, D-21, D-22, D-23 · REQ-A1.4,
  REQ-A1.7, REQ-C1.5, REQ-D1.4, REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-G1.1 ·
  obs:8b694bdb
- **Estimated effort:** 2 days

### Task 8 — Tower↔tower advisory and skill-prose integration

- **Deliverables:** skill-prose integration for `/orchestrate`, within the
  instruction word budgets: the
  advisory rule (a tower↔tower message never claims, releases, or resolves
  a unit of work), with the advisory composed and sent by the tower's model
  through the harness's message tool, no script carrying the path and its
  fallback being not-sent (REQ-G1.4, D-14); addressing (a fleet-launched
  tower by its marker name,
  an operator-launched tower by a listing round-trip); the composition
  rule for when a session model may compose a message at each of the four
  discipline values in each of the three
  directions — `script`, `tiered`, and `open` on the ladder, and at `off`
  no model-composed message in any direction, `effective-mode`'s refusal
  being the oracle's "do not send" — with
  `effective-mode` as the oracle; the `/orchestrate` `Doctrine:` manifest
  line for the messaging-transport doctrine; the doctrine's fallback table
  re-verified (Task 7 carries the same re-verification). No script header
  changes: the task ships skill prose only.
- **Done when:** `mise run check:instructions` exits 0 with no pending-diet
  allowance, and the set of (class, target) pairs its `WARN:` lines carry
  is identical to the set at the task's base commit, resolved from the
  one-line base-SHA file under `tests/fixtures/` this task records — a base
  that includes
  Task 6's `/orchestrate` growth wherever Task 6 landed first, so the
  headroom this task measures is what remains after it (the pairs, not the
  raw lines: each line carries its own word count, which this task moves);
  the
  advisory rule cites the
  fleet-coordination-floor doctrine's assume-multiplicity floor for
  authority over the division of work and names the harness's message tool
  as the send path with not-sent as its fallback; the prose names both
  addressing paths and states the composition rule for each of the four
  values in each of the three directions, `off` sending nothing in any of
  them
  (fixture greps); a grep for
  `^Doctrine: (run-start|point-of-use) messaging-transport` matches in
  `skills/orchestrate/SKILL.md`; `[manual]` a live tower↔tower advisory
  check (the environment: two live tower sessions on the same machine, a
  marker-named fleet-launched tower and an operator-launched one): the
  sending tower's model composes and sends the advisory through the
  harness's message tool, the
  receiving tower's transcript shows the text, and the fence refs and the
  `tasks.md` record are byte-identical before and after, recorded in the
  task PR; a design-level review recorded in the task PR covers
  REQ-G1.2 (no consumer treats message content as durable state) and
  REQ-G1.3 (the carried floors are unchanged and not restated);
  `[manual]` in that same two-session environment, the receiving tower
  treats the text as advisory (no fence ref or `tasks.md` write follows in
  its next turn; presence is re-published on every heartbeat, so it gets
  the design-level review rather than this byte check), recorded in the
  task PR (no
  behavioral-eval offer: the harness drives one session); the doctrine's
  fallback table still names every path in D-13's set; the task
  re-verifies against the running CLI, records the observed version in
  its PR, and raises the last-verified pin, never lowers it (a running CLI
  below the pin halts the task).
- **Dependencies:** 2, 3, 4
- **Citations:** D-4, D-8, D-11, D-13, D-14 · REQ-A1.4, REQ-F1.2,
  REQ-F1.3, REQ-G1.2, REQ-G1.3, REQ-G1.4, REQ-G1.5, REQ-H1.4
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

- **Task 6's event-driven `--watch` loop change and the arms that rest on
  it.** The loop that ends the
  tower's turn per step retires bootstrap D-38's metronome, and D-38 is a
  signed decision another bundle owns, so landing the change before that
  bundle accepts the amendment would leave two signed designs contradicting
  each other in flight. `specs/_pending/bootstrap-amendment.md` (Task 6
  ships it) names the `/spec-draft --extend bootstrap` invocation that
  drafts the amendment; extending a Done bundle flips it Done→Draft and the
  scoped kickoff of the delta flips it back to Ready, but a bundle passes
  through Ready on its way back to Active or Done rather than resting
  there, so the amendment's sign-off is the condition and it is stated as
  free text. The gated set is exactly Task 6's loop change, Task 7's
  notice-wake step and its duty-cycle figure, REQ-D1.7's
  notice-consumption criterion, and REQ-E1.1's loop-reads half. The rest of
  Task 6 — the subscribe steps, the sanction, the
  start-of-tower subscribe pass, the pending note itself — is not gated,
  and Task 7's circuit passes before the gate when the metronome tower acts
  on the park.
  Confidence: high.
  **Gate:** bootstrap's D-38 amendment (the `--watch` loop event-driven
  under tmux) is signed off.
  Citations: D-22 · REQ-D1.7, REQ-D1.8, REQ-E1.1.

## Out of scope

(none yet)
