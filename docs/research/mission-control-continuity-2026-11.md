<!-- markdownlint-disable MD033 -- folded <details> sections are the document shape -->

# Mission control continuity, coordination and remote reach (research, 2026-11)

A decision document, not a design. Research only: nothing here changes behaviour.

## The short version

**Recommendation.** Make the zero-act path the default on every surface: when mission control
passes its handover threshold it compacts *in place*, seeded by its own handover note, so the
operator's window, phone and Remote Control link never move. A fresh successor becomes an
opt-in for surfaces that can host one (tmux today, background sessions later). After repeated
compactions, mission control asks for one act at a quiet moment: type `/clear`, after which a
hook re-seeds it as mission control from its durable state. Around it: a host roster built from
the holder records mission control already writes, one shared reservation for heavy bursts, and
one channel owner per host for reaching the operator off-terminal (a work channel for work
programs, a personal one for the rest), which also links mission controls on other accounts and
machines through a hub.

**Decisions this needs from you** (each a plain picklist; details in
[Decisions, phrased as picklists](#decisions-phrased-as-picklists)):

1. When mission control's memory fills: compact in place everywhere (recommended), or open a
   successor wherever the surface allows, or keep today's split.
2. Your 40% tmux-pane rule on this host: keep it as an opt-in for you, or fold it into the
   in-place default.
3. After repeated compactions: ask you for one `/clear` at a quiet moment (recommended), keep
   compacting, or launch a successor without asking.
4. How mission controls on one computer find and pace each other: a shared roster plus one
   heavy-burst slot (recommended), or keep coordinating by messages.
5. How you reach mission control when away from the terminal, at work: work email, a Slack bot,
   or wait.
6. The same, for personal programs: the Claude app (Remote Control and pushes), a Telegram or
   Discord channel, or email.
7. Mission controls on another account or computer: one hub talks to you and relays to the rest
   (recommended), or each talks to you separately.
8. Your own review rules (such as "help with reviews nobody picked up"): stored as standing rules
   on a review duty (recommended), or a fixed menu.

The current code and your standing rule disagree: the spec says an operator-attended session
compacts and never hands over (D-42), while your 2026-11-06 rule asks for a tmux-pane successor at
40%. Whatever you pick, the spec needs an amendment to match.

<details>
<summary>How to read the rest</summary>

Each section states what is known with a citation, then what is unknown. Claude Code facts cite
the official docs (fetched 2026-11-06), abbreviated **D/** for `https://code.claude.com/docs/en/`
(so D/sessions is `https://code.claude.com/docs/en/sessions`). planwright facts cite this
repository's files. Where neither settles a point, the text says *unknown*.

</details>

## 1. Continuity per surface

<details>
<summary>What mission control can do on each surface when its context fills</summary>

### Facts that hold on every surface

- **The model cannot compact or clear itself.** The Skill tool runs a few built-in commands, but
  "`/compact` [is] not" among them (D/skills); a `/loop` fire sends built-ins such as `/clear` as
  plain text (D/scheduled-tasks); a cross-session message carrying `/compact` "arrives as plain
  text" (D/cross-session-messaging). No doc names a model-callable compact or clear tool.
- **Automatic compaction is configurable but late by default.** With the 1M window it fires at
  about 967K tokens; the window can be set from 100K to 1M with `/autocompact`, the
  `autoCompactWindow` setting, the `--autocompact` flag or `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
  (D/model-config). So a 40% threshold on a 1M window is 400K tokens, well before any automatic
  compaction, and a settings value can move the automatic trigger to that point.
- **Hooks can shape a compaction.** `PreCompact` stdout "becomes instructions for the compaction
  summary"; `SessionStart` with the `compact` source adds its output to the compacted context;
  `SessionStart` also matches `clear` (D/hooks, D/context-window).
- **What survives a compaction:** the project CLAUDE.md and auto memory are re-injected from disk;
  invoked skill bodies come back capped (5,000 tokens a skill, 25,000 in total); background
  commands keep running; context that hooks added earlier is summarised with everything else
  (D/context-window).
- **A spawned `claude` and permissions:** the docs do not say whether a `claude` started from the
  Bash tool inherits the parent's mode or its "allow for this session" grants; they say
  `--fork-session` "starts without them" (D/sessions) and that a background session reads
  settings "from the directory it runs in" (D/agent-view). *Unknown* for the Bash-spawned case.

### planwright today

- `scripts/mc-handover.sh` carries the verbs `due`, `holder`, `path`, `offer`, `write`, `launch`,
  `verify`, `release`, `take` and `resume`. `launch` knows only the `stream-json` and `tmux`
  backends, and over an attended holder it exits 4: "that session compacts instead"
  (`scripts/mc-handover.sh:666-668`).
- The default thresholds are 70% context, 150 wakes or 2 compactions
  (`config/defaults.yml:1062-1064`); the operator's 40% is a standing rule, recorded with a
  natural-break proposal in
  `specs/_observations/entries/2026-11-06-mc-handover-context-threshold-3b1fad05.md`.
- The skill: "The operator's own session, whose terminal cannot move, just compacts, offering no
  handover (D-42)" (`skills/mission-control/SKILL.md:121-127`).
- The tmux self-succession the operator asked for is recorded as refused by design, and the
  by-hand successor stalled on permission prompts
  (`specs/_observations/entries/2026-11-06-mc-attended-self-succession-32bde2c6.md`).
- Phone and remote-control access and cross-machine mission control are out of scope for the
  mission-control spec (`specs/mission-control/requirements.md:99-104`).

### Surface by surface

**tmux.** Everything works: a new pane or window, a successor under the same name with
`--remote-control`, and the predecessor's pane closed after `take`. planwright already dispatches
workers with `tmux new-window -d` (`scripts/offload-dispatch.sh`). Risks: the by-hand successor
stalled on prompts (above); a tmux prompt cannot be answered from mission control today; and the
retire step closes nothing for an attended holder (`scripts/mc-handover.sh:406-409`), so the pane
close is new work.

**Plain terminal (no multiplexer).** Mission control cannot open a window the operator will see.
It could start a background session (`claude --bg`, research preview, run by a supervisor that
outlives the shell, D/agent-view), but the operator's terminal stays on the old session, so the
successor would be invisible unless the operator runs `claude attach`. The docs do not say whether
`claude --bg` from the Bash tool is supported, and scripts get a "Workspace not trusted" error
where no trust dialog can show (D/agent-view). Workable rungs: compaction (zero acts) or one
operator act (`/clear`, or quit and run one command).

**Desktop app (Code tab).** Compaction works and the Context card shows the percentage
(D/desktop). Desktop's Claude "can list your other Code tab sessions… and send messages between
them" (D/desktop), but the docs name no tool that opens a new Code tab session for the model.
*Unknown* whether the planwright panel mod, which runs the rule re-injection after compaction,
runs inside Desktop. Workable rungs: compaction, or one operator act.

**Web (claude.ai/code, cloud sessions).** `/compact` and `/clear` work; `/clear` "starts a fresh
conversation… in the same cloud session" (D/claude-code-on-the-web). Cloud sessions set their own
`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`; the window variable is the one to change (same page). A cloud
session "can't use `SendMessage` to answer a message from another machine"
(D/cross-session-messaging), so it cannot hold a host-local fleet at all. Mission control on the
web is a different product shape (no local tmux, no host fleet), *unexplored* by planwright.

**Remote Control from a phone.** The phone follows the process, not the name: when the process
stops, "the session goes offline until you bring it back"; `/clear` "resets on connected devices
too"; a `/branch` is followed (D/remote-control, D/sessions). The docs say nothing about name
uniqueness or one session taking over another's name; with several live sessions of one name,
messaging "adds a short identifier" (D/cross-session-messaging). So a pane successor started with
the same `--remote-control` name appears on the phone as *another* session, and the operator must
switch to it: *unverified* in practice. `/compact`, `/clear` and `/rename` work from the phone;
`/resume` is local-only (D/remote-control). This makes in-place compaction and `/clear` the only
continuations the phone experiences as seamless.

**IDE extensions.** VS Code compacts automatically and shares history with the CLI; only a subset
of commands is available and `/remote-control` takes no name (D/vs-code, D/remote-control).
JetBrains runs the CLI in the IDE terminal (D/jetbrains), so its terminal is the plain-terminal
case. Mission control cannot open an IDE panel.

**Headless or stream-json.** This is planwright's launched-holder path: `write`, then
`launch --handover`, then the successor's `verify` and `take`
(`skills/mission-control/SKILL.md:121-127`, the successor brief at
`scripts/mc-handover.sh:503-514`). No operator terminal is involved, so a successor is the right
rung. The docs' own advice for SDK sessions agrees: "Don't rely on session resume.
Capture the results… and pass them into a fresh session's prompt" (D/agent-sdk/sessions), which
is what the handover file already does.

### Unknown, and worth one probe each

- Whether the panel mod (and so the rule re-injection) runs in Desktop, the IDE extension and a
  Remote Control-driven session.
- Whether a `SessionStart` hook with the `clear` matcher fires, and its context lands, when
  `/clear` is typed from the phone.
- Whether `/clear` keeps the session id the holder record and lease name, or issues a new one.
- Whether a Bash-spawned `claude` inherits mode and session grants.

</details>

## 2. Costs and risks of each continuation

<details>
<summary>Risk by continuation, and what planwright already has for each</summary>

| Risk | Successor (pane or background) | In-place compaction | One operator act (`/clear` + reseed) |
| --- | --- | --- | --- |
| Lost context | Low: reads the handover file and durable stores | Medium: summary loses tone and in-flight nuance | Low: same as a successor |
| Drift over time | None: each generation starts clean | Grows with each repeat | None |
| Duplicate holder | Real: two live sessions until `take` | None: one process | None if the session id handling holds (*unknown*) |
| Operator's terminal or phone moves | Yes, except a hidden background one | No | No |
| Permissions a successor needs | Yes: prompts stalled the by-hand successor | None new | None new |
| Usage | Successor start-up reads the brief and stores | One summary call | Start-up read, like a successor |

What planwright already has against each:

- **Lost context:** the handover file `<program home>/handover.tsv` (format, program, predecessor,
  ledger, rules digest, items, sessions; `scripts/mc-handover.sh:54-58`) and the brief's
  "Succession" section (`scripts/mc-handover.sh:503-514`).
- **Duplicate holder:** the holder record with a generation number
  (`scripts/mc-handover.sh:42-52`), refusal of a second pending successor (647-658), race
  detection in `succeed` (441-445), all under `handover.lock`; `take` refuses an unverified
  successor (797).
- **Liveness:** an attended holder's wake lease, stale after five minutes
  (`scripts/mc-handover.sh:34`, `scripts/mc-wake.sh` help); positive-evidence liveness in
  `scripts/mc-stall.sh`.
- **Drift after compaction:** the post-compaction self-check (next section).
- **Permissions:** mission control's own launch profile (`config/mission-control-settings.json`);
  the posture check D-32 has no script yet.
- **Gaps:** nothing consumes the `handover-requested` or `mission-control-announce` events, and
  the skill never tells a predecessor to run `release`, so a successor waits out the window and
  retires the predecessor itself.

</details>

## 3. Compaction as a rung

<details>
<summary>What the self-check guarantees, what it does not, and whether repeating it is acceptable</summary>

**Guaranteed today.** After a compaction the panel mod re-injects the active rules with a header
asking for the self-check (`hooks/mission-control/register.tsx:40-42`, 744-761), and toasts when
the rules cannot be loaded. `scripts/mc-rules.sh selfcheck` (727-775) proves two things: the
loaded rules digest equals the store's active digest, and every durable item and session is
present in what the session holds. The mod defers an automatic compaction while a handover is
due, up to 95% (`register.tsx:24`, 723-743).

**Not guaranteed.**

- Extra held entries (things the session believes that the stores do not hold).
- The ledger position: only `mc-handover.sh verify` checks it, and it runs only in a handover.
- Tone, the operator's recent preferences and in-flight reasoning: D-42 says so directly ("the
  self-check catches lost rules and state, not lost tone").
- Any of it where the panel mod does not run; the skill text alone then carries the instruction.
- The `--durable` list is built by the caller, so a session that has forgotten an item can also
  forget to list it.

**Is repeated compaction acceptable as the last resort?** Yes, with two changes and a cap.

1. *Seed it.* A `PreCompact` hook can write the handover note into the summary instructions and a
   `SessionStart` `compact` hook can re-inject the note and run `verify` (ledger included), which
   makes a compaction close to a handover that never moves the terminal.
2. *Cover the ledger.* Run `verify`'s ledger check in the self-check, not only in a handover.
3. *Cap it.* After the existing compaction count (`mission_control_handover_compactions`, default
   2), ask the operator, at a natural break, for one `/clear`; a `SessionStart` `clear` hook
   re-seeds the session as mission control from the durable stores. That resets drift on every
   surface, the phone included, without a second process.

Two cheap levers make the in-place rung fire at the right time: set `autoCompactWindow` (or the
environment variable) in mission control's launch profile to the handover threshold, and keep the
mod's deferral for launched holders only.

</details>

## 4. Shared decisions with permissions and spec formats

<details>
<summary>Where continuity touches first-run permissions and other spec formats</summary>

**First-run permissions.** Every new process is a new chance to stall on a prompt, which is what
stopped the by-hand successor. In-place compaction and `/clear` reuse the running process and its
grants, so they need no new permission work; a successor needs the posture check (D-32) shipped
and its launch profile proven against an attended session first. The shared decision: *a
newcomer's first hour should never show a prompt that only a second session can cause*, which
favours the in-place default. The first-run rule that setup asks only questions the operator can
answer applies to the `/clear` ask too: phrase it as one plain act, never as a choice of
mechanisms.

**Other spec formats.** No shared decision with continuity. One shared principle with
coordination: an imported spec goes through a normal kickoff, so it lands in the same fleet and
the same roster; nothing here needs to change for importers.

</details>

## 5. Candidate strategies

<details>
<summary>Three strategies with their trade-offs</summary>

**A. Keep today's split.** Launched holders hand over; the operator's own session compacts, with
the tmux pane successor added for operators who run tmux. *For:* least new code; the operator's
rule works on this host. *Against:* a newcomer outside tmux gets plain compaction with its known
gaps; the phone sees a second session after a pane handover; the successor's permission stall is
unsolved.

**B. In place by default, successor by opt-in (recommended).** Seeded compaction at the
threshold on every surface; a `/clear` ask after the compaction cap; the pane successor as an
opt-in knob for tmux users (the operator's 40% rule maps here); launched holders keep today's
handover. *For:* the same zero-act experience on every surface; nothing moves on the phone; no
new permission surface; uses hooks Claude Code documents. *Against:* seeded compaction still
loses tone; needs the hooks above plus a probe of the unknowns in section 1.

**C. Successor everywhere.** Mission control always starts a fresh session (pane in tmux,
background session elsewhere) and the operator follows it. *For:* clean context every time.
*Against:* outside tmux the operator must find the new session (`claude attach`, a new Desktop
tab, a new phone entry); background-session launch from the model is undocumented; a duplicate
holder window on every handover; worst for a newcomer.

</details>

## 6. Coordination and discovery (the fourth touchpoint)

<details>
<summary>How mission controls find each other and share a host, today and missing</summary>

**The discovery cases.**

- *Other programs on this host.* Each program's holder record lives at
  `<fleet home>/mission-control/<program>/holder` (`scripts/mc-lib.sh:261-266`), so listing that
  directory is already a host roster, but nothing reads it that way. `ListAgents` lists local
  sessions with no setup (D/cross-session-messaging), and the skill uses `SendMessage` when the
  target is listed (`skills/mission-control/SKILL.md:225-227`).
- *Successor and predecessor.* Solved by the holder record, generation and handover file
  (section 2), except that no one consumes the announce and request events.
- *Another machine or another person's hub.* Nothing: `SendMessage` and `ListAgents` are
  local-only in planwright's use, and the operator bridged machines with ssh and a tmux paste
  (`specs/_observations/entries/2026-11-05-mc-cross-machine-relay-57770415.md`). The docs say
  messages to other machines go through Anthropic's servers via Remote Control
  (D/cross-session-messaging); whether that spans two accounts is *unknown*.

**Coordination duties.**

- *Shared capacity and usage.* `scripts/mc-budget.sh` measures per-program dimensions only and
  `admit heavy` waits on host load; the usage mirror is read only by
  `scripts/fleet-usage-gate.sh`. Host-shared admission is specified (REQ-L1.7, D-41, Task 28 of
  the mission-control spec) but unshipped: no `mission_control_admit` key exists.
- *One heavy burst at a time, with a heads-up.* Today a standing rule and a message by hand; the
  gate lock is an operator-made `flock` outside the code.
- *Clean only your own state.* `scripts/mc-keeper.sh` leaves a worker registered to another
  program to that program, and holds a unit another program's launcher holds. One known breach:
  a retire emptied the shared scratch root under other live sessions
  (`specs/_observations/entries/2026-11-05-shared-scratch-root-emptied-c7ff1358.md`).
- *Handing work across.* Nothing beyond a free-text message.

**What a fix looks like.** A host roster read from the holder records (program, generation,
holder kind, lease age) shown in the panel; the Task 28 reservation store as the one heavy-burst
slot, with the heads-up emitted as an event every roster member reads; scratch and cleanup scoped
by program. Cross-machine reach rides the communication channel below rather than a new
transport.

</details>

## 7. Remote operator communication (the fifth touchpoint)

<details>
<summary>Reaching mission control from a sanctioned medium, and linking accounts and machines</summary>

### What exists

Pushes are marker files a tower loop relays to the `PushNotification` tool
(`doctrine/attention-notification-capability.md`), and `PushNotification` reaches a phone only
"with Remote Control or in a cloud session" (D/tools-reference). The never-send rule's only code
enforcement is that `scripts/mc-inbox.sh draft` has no sending path. Remote Control needs the
Claude app and, on Team or Enterprise, an Owner to enable it (D/remote-control), which is the
operator's exact gap at work.

### One channel owner per host

A relay duty, held by one mission control on the host (the main account's), owns the channel for
every program there: outbound items and pushes become messages; inbound replies are parsed back
as the operator's own words and routed to the program they answer. Rules it must keep:

- Act only on a message from the operator's identity, verified (below); never on forwarded or
  quoted text, only the newest reply text.
- Each outbound message carries a per-item token; a reply without the matching token is held,
  not acted on.
- A reply is the operator's words, relayed; it is never an approval of a permission prompt.
- The never-send-to-a-person rule is unchanged: a message to a colleague is drafted, its exact
  text echoed to the operator over the channel, and posted only on a yes to that text.
- Data hygiene: a work program's items go only to the work channel; personal programs never use
  it.

### Options compared

| Option | Sanctioned at work | Operator setup | Sender authentication | Reliability | Data hygiene |
| --- | --- | --- | --- | --- | --- |
| Work email via provider API (Microsoft Graph or Gmail API, OAuth) | Usually the most sanctioned | An app registration, often admin consent | Weak alone: require `dmarc=pass` from the own provider's `Authentication-Results`, an exact From, and the item token; S/MIME for strong | Seconds to minutes; Graph push needs a public endpoint or Event Hubs, Gmail push a Pub/Sub pull | Stays in the work mailbox |
| Email over IMAP and SMTP with an app password | Personal Gmail only | 2-Step Verification, an app password | As above | Seconds to minutes (IMAP IDLE) | Personal mailbox |
| Slack bot (Socket Mode) | High where the company runs Slack | Create the app; admin approval is common | Strong: user and team id over an authenticated socket | Sub-second; 1 message a second a channel | Company data, retained by the company |
| Discord bot | Rarely | Bot token, a private server | Strong: user id | Sub-second | Not end-to-end encrypted; personal only |
| Telegram bot | Personal only | BotFather token | Chat id allowlist | Sub-second; updates kept 24 hours | Not end-to-end encrypted; personal only |
| WhatsApp Cloud API | No | Meta business account, number, templates | Phone number | Free text only in a 24-hour window | Poor fit |
| Facebook Messenger | No | A Page, app review for anyone else | Page-scoped id | 24-hour window | Poor fit |
| Claude Code Channels (Telegram, Discord, iMessage plugins) | Off on Team or Enterprise until an Owner enables it | `claude --channels plugin:…`, pairing code | Pairing plus allowlist | Only while the session is open | As the platform |

Sources: Google on app passwords and the end of password sign-in for Workspace
(<https://support.google.com/accounts/answer/185833>,
<https://knowledge.workspace.google.com/admin/apps/control-access-to-less-secure-apps>);
Microsoft on SMTP Basic auth retirement
(<https://techcommunity.microsoft.com/blog/exchange/exchange-online-to-retire-basic-auth-for-client-submission-smtp/4114750>);
Gmail push (<https://developers.google.com/workspace/gmail/api/guides/push>); Graph webhooks
(<https://learn.microsoft.com/en-us/graph/change-notifications-delivery-webhooks>); DMARC and
Authentication-Results (RFC 7489, RFC 8601); Slack Socket Mode, app approval and limits
(<https://docs.slack.dev/apis/events-api/using-socket-mode>,
<https://slack.com/help/articles/222386767-Manage-app-approval-for-your-workspace>,
<https://docs.slack.dev/apis/web-api/rate-limits>); Telegram Bot API
(<https://core.telegram.org/bots/api>); WhatsApp Cloud API
(<https://developers.facebook.com/docs/whatsapp/cloud-api/guides/send-messages>); Messenger policy
(<https://developers.facebook.com/docs/messenger-platform/policy/policy-overview>); Channels
(D/channels). Claude's Gmail connector reads only ("Claude can't create, send, or modify
emails", <https://claude.com/docs/connectors/google/gmail>), so it cannot be the channel.

A caution on Channels: "Anyone who can reply through the channel can approve or deny tool use"
when permission relay is on (D/channels). Mission control's relay must keep that off.

**Recommendation per use.**

- *Operator to mission control, work:* the work mailbox through the provider API with OAuth, or a
  Slack bot where the company runs Slack; the operator picks whichever their employer sanctions.
  Both may need an admin.
- *Operator to mission control, personal:* the Claude app (Remote Control plus pushes) already
  works; a Telegram or Discord channel adds a reach that does not need the app.
- *Mission control to mission control across accounts or machines:* a hub. The main account's
  mission control talks to the operator; the others report to it over a dedicated relay mailbox
  (work-safe, crosses accounts) or a private Discord server (personal), with the same token and
  sender checks. Whether Remote Control's cross-machine messaging could replace this across two
  accounts is *unknown* and worth one probe.

### Reviews while away (the key work case)

What the operator needs from the channel: review requests and their state (new, waiting on the
operator, drafted, posted), the ability to approve or steer a review from the channel, and the yes
on any reply to a person, given against the exact text.

- **Mission control runs the review sessions** as launched sessions, as the deferred review desk
  seed describes (`specs/_pending/review-desk.md`); `scripts/mc-reviews.sh` is a read-only
  snapshot today.
- **Cost without losing effect:** a cheap triage pass picks and sizes each request, a full review
  runs only on the picked ones, and the review-effectiveness spec's per-finding yield decides
  which passes earn their cost.
- **Operator-defined rules.** A rule such as "help with reviews people are not picking up" is a
  standing rule with scope `duty:review-desk` (the scope grammar exists:
  `scripts/mc-rules.sh` help), carrying a filter over signals mission control can read: a
  review requested from a team, the age of the request, no individual reviewer assigned, no
  review activity. The rule set stays open-ended: the filter vocabulary grows with new signals,
  never as a fixed menu.
- **The never-send gate holds:** a review of a colleague's PR is drafted, its exact text sent to
  the operator, and posted only on a yes to that text.
- **A work repository changes two things:** the ready-flip is the operator's to request
  (`ready_flip_policy: human`), and its items travel only on the work channel.

</details>

## Decisions, phrased as picklists

1. **When mission control's memory fills, what should happen?**
   - Tidy up in place, so nothing on your screen or phone moves (Recommended)
   - Start a fresh copy beside it wherever your setup allows
   - Keep today's behaviour (only sessions mission control launched get a fresh copy)
2. **Your rule to open a new tmux pane at 40%: keep it?**
   - Keep it as an option for you on this computer (Recommended)
   - Replace it with the tidy-up-in-place default
3. **After it has tidied up a few times, should it ask you for a fresh start?**
   - Yes, ask me to type `/clear` at a quiet moment (Recommended)
   - No, keep tidying up
   - Start a fresh copy without asking
4. **How should mission controls on one computer share it?**
   - A shared list of who is running, and one heavy job at a time (Recommended)
   - Keep sending each other messages, as now
5. **At work, how do you want to reach mission control when away?**
   - Work email
   - A Slack bot
   - Not yet
6. **For personal programs?**
   - The Claude app, as now (Recommended)
   - A Telegram or Discord bot
   - Email
7. **Mission controls on another account or computer:**
   - One main mission control talks to me and passes things on (Recommended)
   - Each one talks to me directly
8. **Your own rules for which reviews to take on:**
   - Rules I write in plain words, kept with the review duty (Recommended)
   - A fixed menu of choices
