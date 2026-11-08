# Seed brief: isolated remote workers (an extension of `remote-worker-rung`)

Suggested invocation, in a fresh session in the planwright repo with this file as the seed. The
`remote-worker-rung` bundle (merged in PR #871) is still Draft, so extending it triggers no reopen
cycle:

    /spec-draft --extend remote-worker-rung

This answers some of that bundle's open `(Q)` decisions and amends some settled ones (see
[What this changes in the remote-worker-rung draft](#what-this-changes-in-the-remote-worker-rung-draft)).
If the draft has moved by the time this runs, fold-detection decides extend-vs-spin-new as usual.

This is a design for the operator's review. Nothing here is signed off, and nothing in it changes
behaviour, configuration or workflows.

## The short version

**Goal.** Workers on the offload Mac run inside a restricted macOS account with **no permission
prompts at all**, and every guardrail sits at the boundary of that account instead of inside it:
the operating system keeps them out of the owner's files and Homebrew, and GitHub writes leave the
account only through the hub.

**The hub** is this host's mission control together with the fixed scripts it runs. For a
worker's request, mission control only invokes a script by worker and request id; the script reads
the request and makes every check itself, so no model judgment sits in a check.

**The finding that shapes everything.** GitHub cannot limit a token to one branch. A fine-grained
token is scoped to repositories and permissions, never to branches; branch rules (rulesets) apply
per actor, and a token acting as the operator inherits the operator's admin bypass of them. This
repository's main-branch ruleset also asks for zero approvals, so any token that can write contents
and pull requests here can merge a green pull request into main. And any credential allowed to
change workflow files (the operator's SSH key, or a `gh` login holding the `workflow` scope) can
push a branch that adds a workflow with a write-capable `GITHUB_TOKEN`. So "a token that can push
only its own branch" cannot be a token. It has to be a boundary that chooses the refspec.

**Recommendation.** The work account holds **no GitHub write credential**, only a read-only
fine-grained token. A worker commits in its own clone and asks the hub to publish. The hub fetches
the branch over the SSH alias (the git path `remote-worker-rung`'s fetch-back already names, not a
channel verb) and checks it mechanically: the exact branch name from its dispatch record,
fast-forward only, no workflow or hook files, a secret scan and the commit lint. Then it pushes
exactly that one ref with its own credential and opens or updates the draft pull request. The few
other GitHub writes a worker's cadence needs (triggering the hosted reviewer, replying to and
resolving bot threads on its own pull request) are also fixed hub verbs. The worker never marks
anything ready; the hub's readiness check does. That makes the per-branch limit exact per request,
merge impossible, and workflow injection refusable. Inside the account the worker runs prompt-free,
with planwright's worker profile kept as a tripwire that only ever allows or denies.

**What it retires.** For Mac workers: the per-command vetting loop, the worker command guard's
auto-approval role and the pre-approval lists as approvers (under `dontAsk` their allows remain
the list of what may run), the stream-json permission queue's traffic, and the
pending-prompt alarms and sweeps. They stay for this host's local workers until those move into an
isolated account too (the last migration phase, an open question).

**Decisions for the operator** are in [Open questions](#open-questions-for-the-operator), each with
options and a recommendation. The first one, the credential shape, is the one that matters most.

## What exists today (grounding)

- **The channel.** PR #871 adds `scripts/fleet-remote.sh`: this host reaches the Mac by an SSH
  alias and runs fixed verbs (`root`, `launch`, `pending`, `answer`, `steer`, `status`, `retire`,
  `compute`), every argument quoted, free text over stdin. The worker verbs run the Mac's own
  installed planwright; `compute` runs the shipped commit in the Mac's clone. Its Draft spec
  `remote-worker-rung` plans dispatch records, remote liveness, vetting of remote prompts through
  the channel (its D-7, D-9), and remote workers pushing their own branches with fetch-back through
  this host as the fallback (D-10, REQ-B1.4, REQ-B1.7).
- **The Mac.** Dotfiles PR #225 makes the work account a standard (non-admin) macOS account
  reached by one key-only SSH key from this host's address, with password login off for every
  account. Tools come from mise in the account's home, and the owner's Homebrew is used read-only.
- **The credentials in that account today**, per the PR #225 runbook:
  - the second Claude subscription's login, in the account's keychain, which an SSH session does
    not unlock by itself;
  - a `gh` login under the operator's GitHub identity, stored in plain text for that reason;
  - an SSH authentication key and a signing key registered to the operator's GitHub account;
  - a read-only 1Password service-account token for the dotfiles vault.

  Code a worker runs can read all of them. The `gh` login and the authentication key can push to
  every repository the operator owns, with the operator's admin bypass. That is the exposure this
  design removes.
- **This repository's GitHub posture** (read on 2026-11-07):
  - the default branch's ruleset blocks deletion and force pushes, requires linear history,
    signatures, a squash pull request with **zero** required approvals, and the `check` and
    `title` status checks;
  - the repository-admin role bypasses it always;
  - the required checks are not pinned to a source app;
  - workflows default to a read-only `GITHUB_TOKEN`, but the token can approve pull requests;
  - there are no repository secrets.

## The shape

Three layers, from the outside in:

1. **The OS boundary (the real one).** The work account is a standard macOS user. It cannot read
   or write the owner's home (made unreadable to other accounts, `chmod 700`, before any worker
   runs), cannot write the Homebrew prefix, `/Applications` or system settings, and cannot escalate
   (no admin group, no sudo rule). Everything the worker can damage is the account's own home and
   the world-writable shared directories (`/Users/Shared`, the temporary directories).
2. **The GitHub boundary (the hub).** The account can read GitHub but not write it. Every write is
   a request the hub executes through a fixed, mechanical verb against the worker's dispatch
   record. No model judgment sits in that path, so a worker cannot argue its way past it.
3. **The inside layer (defense in depth, not a boundary).** The worker runs with prompts off.
   Planwright's worker profile (`config/worker-settings.json` and its guards) still applies there.
   Today it refuses merge, force pushes and pushes to main, but allows a worker to push its own
   branch and flip its own PR; the isolated worker settings add denies for both, since the hub
   does them.
   An honest worker gets a clear message instead of a stall; a compromised one can edit its own
   settings, so nothing depends on this layer. Claude Code's OS sandbox for Bash commands (Seatbelt
   on macOS: filesystem limits and a network allowlist) is the candidate for the same layer, after
   a probe.

**"Prompts off" means `dontAsk` mode.** Anything not pre-approved is denied, so the worker
command guard's allow rules stay load-bearing, and the profile also denies the tools that need a
person (`AskUserQuestion` among them). `bypassPermissions` is not an option: the fleet dispatch
guard refuses it at launch (`scripts/fleet-dispatch-guard.sh check-launch`, as it refuses `auto`
under `fleet-autonomy` D-19), because it takes the allowlist out of the approval path, and this
design does not reverse that. An isolated worker that raises a permission request is denied and
alarmed, and the sandbox runs with its unsandboxed retry off (`allowUnsandboxedCommands: false`).

A worker's life: the hub dispatches through the channel. The worker runs its whole cadence on the
Mac (implementation, tests, polish), commits and asks to publish. The hub publishes and opens the
draft PR. The worker's post-PR steps ask the hub to trigger the hosted reviewer and to reply to bot
threads. The worker reports done, and the hub's readiness check flips the PR when the conditions
hold.

## 1. What workers lose, and how each is replaced

| Lost compared with this host | Replacement or acceptance |
| --- | --- |
| The operator's `~/.claude`: global instructions, settings, memory, personal skills (`review-shared`, `bot-review`, `panel-review`) | An **account profile**: a sanitized global instructions file (git, PR and writing conventions only), the isolated worker settings (prompts off, the tripwire denies), and the skills the cadence calls. Planwright ships the isolated worker settings (its worker profile plus the push and flip denies and the prompts-off mode), loaded by the launcher; the dotfiles playbook renders the rest from tracked files. The operator's `~/.claude` is never copied. Memory is not replaced: the brief carries what a unit needs (accepted, and it trims context). |
| GitHub write access (push, PR create and edit, comments, thread replies, ready flip) | The hub's publish and PR verbs (Section 3). The ready flip moves to the hub entirely. |
| Commit signing as the operator | The main ruleset's signature rule also checks the head branch's commits, so unsigned worker commits block a squash merge even though GitHub signs the squash commit itself. The Mac's signing key is still removed; how Mac branches get signed is Q11. |
| The GitHub MCP server and claude.ai connectors (Slack, docs) | Not needed by a worker: reads go through `gh` with the read-only token, writes through the hub. Connectors tied to the operator's account stay on the hub. |
| Non-Anthropic review backends (`panel-review`'s CLIs and their keys) | Run as hub-side steps against the pushed head, or not for remote units (undecided; see [What this changes](#what-this-changes-in-the-remote-worker-rung-draft)). Their keys never reach the Mac. |
| The fleet home (registry, journals, attention store) | The Mac keeps its own fleet home. The hub sees it only through channel verbs and its local dispatch record (`remote-worker-rung` D-5, D-6). |
| Warm caches (mise tools, test caches, plugin cache) | Rebuilt once in the account's home; the playbook pre-installs the pinned tools. The first unit pays the cold start. |
| The 1Password service token | Removed from the account. Values the Mac's playbook needs that are not secret (the public key, the trusted address) are rendered on the hub and copied in at the console playbook run, since no channel verb ships files. See open question Q4. |
| This host's test pool, gate serialization and machine-local config | The Mac's own test pool and gate serialization under its own machine-local layer. Nothing is shared with this host's. |
| Interactive help when a worker is stuck on a prompt | No prompts to get stuck on. Steering through the channel stays. |

## 2. Host-only checks

The rule: **a check that protects the boundary runs at the boundary; a check that only tests the
work runs wherever it fits, with CI as the gate of record.**

- **Boundary checks, run by the hub at publish time** on the fetched commits, never trusted from
  the worker, each run from the hub's own base-branch copy of its configuration (a branch cannot
  add an allowlist entry for its own secret):
  - the secret scan (gitleaks over the new commits);
  - the commit-message lint, in a refusing mode (over a commit range today's lint only reports);
  - the refused-path check. This is the one canonical list: workflows, composite actions, git
    hooks, hook configuration, and the configuration of these checks themselves (Q3);
  - the branch-name and fast-forward checks.

  The in-account copies (the commit-msg hook, a local scan) are a convenience, since a worker can
  disable its own hooks. The hub runs these over git objects only: it fetches with one fixed
  refspec into a hook-free quarantine repository with object checking on, and never checks out or
  executes Mac-authored code, so a branch cannot run code on this host through a hook or a test.
- **Step records are self-attested.** The worker writes its own step records, uncommitted in its
  worktree, and a compromised worker can forge them, so the step audit (`step-run.sh audit`) is a
  consistency check, not a boundary check. How the records reach the hub's readiness check is a
  build task; for remote units CI and the hosted review are the independent signals.
- **Linux-only tests** (`/proc` liveness, `setsid`, `flock`, GNU-only paths): CI already runs the
  suite on Linux and macOS and is the gate of record. A worker skips the tests it cannot run on
  macOS by their existing platform guards, and the hub does not run them for it. Executing worker
  code on this host would breach the boundary above.
- **The planwright gate** (`mise run check`): the worker runs it on the Mac. PR #871's description
  measured a supervisor suite faster there, with this host heavily loaded; the whole gate's speed
  on the Mac is unmeasured. The same description found that the whole gate does not fit one tool
  call's timeout, so the worker runs it detached
  (`detached-run.sh`) and waits in-turn. When the Mac's gate is busy, the worker skips the local
  gate and CI decides.
- **`compute` (PR #871)** stays the way this host offloads its own test runs to the Mac. It runs
  over SSH outside any Claude Code session, so the Bash sandbox never covers it. With no GitHub
  write or 1Password credential left in the account, its credential exposure (`remote-worker-rung`
  D-16, REQ-G1.6) shrinks to the Claude login and the read-only GitHub token, both of which a
  compute run can still read (Section 4). Its results are advisory: a compromised account can fake
  them, and CI decides.

## 3. How the hub supervises

- **Launch.** As in `remote-worker-rung`: the channel's `launch` verb on the Mac's own launcher,
  with the brief over stdin, the account profile applied, prompts off and a dispatch record on the
  hub. The hub chooses the branch name at dispatch; D-5's record already names it, and here it
  becomes the only branch the worker may publish. The record also gains the pull request once one
  exists. That record is what makes "its own branch" checkable.
- **Observe.** The channel's `status` (remote evidence only, D-6) plus a new read of the worker's
  request queue. The Mac's capacity, the owner's idle signal and per-account usage are read on the
  Mac (D-8, D-12, D-13).
- **Steer.** The channel's `steer` verb, unchanged.
- **Permission flow: none inside.** The stream-json supervisor still carries the worker's stdio,
  but it should receive no permission requests: every guard in the isolated worker settings
  answers allow or deny, never ask, because an `ask` with nobody inside to answer is a stall.
  Claude Code's own prompts are the mode's job (see The shape), and any request that still arrives
  is denied and alarmed.
- **The request queue (replaces vetting).** A worker asks for an outward act by writing a request
  into its worker directory through a small planwright script that then waits, bounded, for the
  answer. The hub's vetting pass reads the queue through the channel and hands each request, by
  worker and request id only, to the matching verb script; request bodies never reach the model.
  Each verb is a script with fixed checks:
  - `publish`: the checks in Section 2, then a push of exactly `refs/heads/<branch>`, fast-forward
    only (a rewrite is the operator's call, never a verb), then a draft PR created or updated as
    the operator. It always refuses `main`, protected branches, tags and any name outside the
    worker prefix, whatever the record says.
  - `comment`: on the worker's own PR only, and only a comment whose body starts with one
    configured automated reviewer's login and mentions nobody else, such as the hosted reviewer's
    trigger.
  - `reply` and `resolve`: on a thread of the worker's own PR in which nobody has spoken except
    automated reviewers and the hub's own recorded posts (matched by comment id). A thread a person
    has replied in is drafted into the handoff and held for the operator's yes, as today.
  - `report-done`: the worker's cadence is finished. The hub's readiness check (step audit, CI,
    mergeability, review convergence) decides the ready flip; the worker never flips.

  Every text a verb posts (a PR body, a comment, a reply) comes from the worker and is treated as
  data: length-capped, secret-scanned, closing keywords stripped, and `@` mentions defanged except
  configured bot logins, so a worker cannot notify a person (the messages rule).

  Requests run in order per worker. A refused request answers with the check that refused it,
  which the worker can act on (drop the flagged change, fix the flagged commit, or park).
- **Result handoff.** The branch and the draft PR, as for any worker. The worker's commits also
  stay in the Mac's clone until retire, so a publish that failed can be retried from them.
- **Retire.** The channel's `retire`, plus removal of the remote worktree on the usual conditions
  (`remote-worker-rung` REQ-B1.5).

**Failure modes.**

| Failure | What happens |
| --- | --- |
| Network loss between the hosts | The worker keeps running: its model traffic uses the Mac's own internet. Its requests wait in the queue, and its bounded wait parks it on the publish step if the loss outlasts it. The hub reads the host as unreachable, not dead, until the grace period ends (D-6), then reports the unit. |
| The Mac loses the internet | Model calls fail. The worker ends with a named error in its result, and the hub relaunches once the host reads healthy. Committed work survives in the Mac's clone. |
| Runner offline (sleep, shutdown, reboot) | `caffeinate` while a worker runs (REQ-B1.6). After a reboot the PR #225 runbook unlocks the account's keychain by hand before dispatching; until then the login fails with a named auth error (REQ-C1.6). Q5 addresses that. The hub stops placing work on the host until a health probe passes. |
| A stuck worker | The "parked on a prompt" class disappears. The rest remains: a hung command, a loop burning tokens, a wait on a request the hub never answers. The remote status gives the last-event age, and the stall detector applies to it as remote evidence. The ladder is steer, then stop, then a fresh relaunch on the same branch. Per-unit caps on wall-clock time and turns, enforced by the Mac's supervisor, bound an honest or runaway worker's spend (Q8). |
| The hub is down | Workers keep running and requests queue until each worker's bounded wait parks it. On return the hub reconciles from its dispatch records and the Mac's queues. Nothing publishes while it is down, which is the safe direction. |
| Version skew between the hosts | The channel's version check before a dispatch (REQ-A1.6), extended to the request-queue format. |

## 4. Trust boundary and threat model

**Assets.** The owner's files, Homebrew and system; the operator's GitHub account and repositories;
this host; the second Claude subscription; the integrity of what reaches main.

**Assume the worker is fully compromised** (a prompt injection in a fetched page, a malicious
dependency, a model error that runs away). Everything inside the account, including its settings,
hooks, the sandbox configuration and the Mac's supervisor, is then attacker-controlled. Controls
inside the account limit an honest or runaway worker only.

What it **can** do:

- Run any code as the work account, and read or change anything that account owns, including
  **other Mac workers' worktrees and request queues** in the same account. Under Q6 (a) a request
  has no authenticated origin: the hub cannot tell which worker wrote it, and no secret the hub
  hands a worker stays out of another same-account worker's reach. So one worker can file any
  verb in another's queue: publish tampered commits on its branch (the publish checks bound what
  that can push), reply to and resolve its bot threads without a fix, and report it done. "Its own
  PR" then means the queue's PR, not the writer's, and review convergence on any Mac PR is only
  as trustworthy as every worker in the account. What still holds: no worker can merge, touch
  main or a tag, or reach a PR outside the hub's dispatch records, and CI and the operator's merge
  stay independent. Per-worker accounts close it fully (Q6).
- Read the second Claude subscription's login and spend or steal that account's usage. This is the
  one credential that must live there. The sandbox keeps an honest worker's Bash commands away from
  it, but it covers Bash only (not the Read tool, hooks or `compute`), and a compromised worker
  controls it. The real controls are revoking the login from the Claude account settings and
  watching that account's usage from the Claude side, not from the Mac (D-13 reads it on the Mac).
- Read the read-only GitHub token: it can read what that token selects, at most the source a
  worker already has.
- Reach the network: the LAN, and any host on the internet. The sandbox allowlist limits only an
  honest worker; network-level egress limits are undecided (see
  [What this changes](#what-this-changes-in-the-remote-worker-rung-draft)).
- Plant persistence inside the account (a LaunchAgent, a crontab, a second SSH key in the
  account's unmanaged `authorized_keys`, which works from any LAN address). Q7 fixes the last one.
- Send the hub hostile data: request fields, PR bodies, result text, and the git objects and refs
  the hub's fetch receives. The hub's verbs are scripts that treat all of it as data (the fetch per
  Section 2), and mission control reads worker output as data, never as instructions. The one model
  in the path, mission control reading a result, is exposed to injection only through what it
  reads, so the verbs must not need it.
- Fake `compute` results. They are advisory, and CI is the gate of record.

What it **cannot** do:

- Read or write the owner's files, write the Homebrew prefix, `/Applications` or system settings,
  or escalate: a standard account, no sudo rule, the owner's home unreadable to other accounts.
- Under Q1 (a): push any branch, merge, mark ready, close any PR, edit any PR except its own
  through the hub's verbs, or touch main or a tag. The account holds no write credential, and the
  hub pushes exactly one ref named by its own record.
- Under Q3 (a): run workflow code with a write token. The hub refuses to publish a branch that
  touches the refused paths (Section 2). Without that refusal, the hub's own credential, which may
  change workflow files, could push a workflow that requests `contents: write` and merges, since
  main needs zero approvals.
- Log in to this host. The account holds no key to it and this host trusts none from the Mac; the
  channel runs one way only. This host is still on the LAN the account can reach.
- Run code on this host through its branch. The hub handles Mac-authored commits as git objects
  and never checks them out or executes them. They run on this host only after the operator's
  merge, through the normal review gate.

**Token scope and lifetime.** One fine-grained token, created by the operator:

- **Scope:** read-only (contents, pull requests, metadata, commit statuses) on only the selected
  repositories. Fine-grained tokens cannot call the Checks API, so check-run reads go through the
  hub or GraphQL.
- **Lifetime:** 90 days, rotated by the operator, with a hub reminder before expiry.
- **Storage:** an owner-only file in the work account, installed by a playbook run at the Mac's
  console (never over the channel, per REQ-F1.2); nothing else.

The hub's own credential, the one that pushes, never leaves this host. If Q1 picks an on-Mac
write token instead, the recommended shape is a GitHub App installation token (one repository,
expiring after an hour, minted per worker by the hub), never a long-lived token acting as the
operator.

**How the boundary is verified.** A **boundary probe** suite the hub runs through the channel at
setup, after every Mac playbook run, and daily. Each probe has a positive control and must be seen
failing once before it is trusted (`doctrine/evidence-quality.md`, "Failable in practice").
Positive controls that need rights the work account lacks are run once at setup by an
administrator in the owner account. Run as the work account, the probes catch **configuration
drift, not compromise**: a compromised account can answer them falsely. They assert:

- no admin group, and `sudo -n true` fails;
- writes to the Homebrew prefix, `/Applications` and the owner's home fail;
- reads of the owner's home fail;
- no `gh` login, no GitHub SSH key, no signing key and no 1Password token;
- a push of a canary ref with the read-only token, against a canary repository the token also
  selects, is refused by GitHub;
- the isolated worker settings match planwright's shipped copy;
- no unexpected LaunchAgents or crontab entries, and only the managed authorized key.

Checks that must hold under compromise run where the account cannot reach, never through the
channel (which reaches only the work account) or the playbook (which runs in it): the persistence
and key checks by an administrator at the console, or by a root-owned scheduled job an
administrator installs; the credential lists from GitHub's side.

On the hub side the probe asserts that the publish verb refuses a canary branch for each refusal
class, and a periodic audit matches GitHub events on the worker branch prefix and on the PRs in the
hub's dispatch records (pushes, comments, ready flips) against the hub's own publish log by head
SHA, PR and comment id. Since the hub acts as the operator (Q2 (a)), identity alone cannot separate the hub's writes from a stolen operator
credential; the log can. The audit's own output is reported, never silently green.

## 5. Approval machinery: what this retires, what stays, the migration

**Retired for Mac workers:**

- The worker command guard's auto-approval role (`scripts/worker-command-guard.sh` and the
  profile's allow rules): nothing prompts, so there is nothing to auto-approve. Under `dontAsk` its
  allows stay as the list of what may run (The shape).
- The stream-json permission queue's traffic (`fleet-streamjson.sh pending` and `answer` for
  remote workers): the supervisor stays as transport, and the queue stays empty.
- The pre-approval lists and literal-path allow rules for worker prompts.
- `remote-worker-rung` D-7's prompt vetting, REQ-C1.1 and REQ-C1.2, REQ-C1.3's alarm over remote
  prompts, and the `answer --allow` posture in D-9.
- The supervisor's pending-age alarm and mission control's pending-prompt sweep for remote
  workers. The request-queue age replaces them, with the same alarm, and stall detection stays.

**Kept:**

- The hub's own guards: `ready-guard.sh` on the hub's flips, and the command guard's approval of
  the channel's fixed verbs (D-9, REQ-C1.5), which grows to the request-queue read and answer.
  Mission control itself still runs no git mutation (`policy-guard.sh`'s mission-control tier), so
  the hub's verb scripts (`publish`, `comment`, `reply`, `resolve`), which run the fetch and push
  inside them, need the command guard to approve them by resolved path: a guard change listed
  below.
- Planwright's worker profile inside the account, as a tripwire that allows or denies only.
- The worker's cadence, unchanged and run on the Mac. The readiness check moves to the hub for
  remote units.
- Everything local workers on this host use today, until phase 4.

**Migration, each phase gated on the one before.** Each reverts by its own undo, except that phase
0's revocations are undone only by minting new credentials:

0. **Clean the account** (a dotfiles PR): sign out the operator's `gh`, remove the GitHub keys,
   the signing key and the 1Password token; install the read-only token and the account profile,
   without the isolated worker settings (phase 2 turns those on); make the owner's home unreadable
   to other accounts (`chmod 700`); pin the account's authorized keys (Q7). Removal is not
   revocation (`gh auth logout` revokes nothing), so the operator also revokes the removed keys and
   the `gh` token on GitHub and rotates the 1Password service token. Revoking the GitHub CLI app's
   access revokes every `gh` token, this host's included, so this host signs in again afterwards.
   Until the request verbs exist,
   Mac workers use `remote-worker-rung`'s fetch-back path (REQ-B1.7, still to be built) for
   delivery, with the hub pushing; a session on this host opens the PR and runs the post-PR steps.
   Remote prompts are vetted by hand through the channel's `pending` and `answer` verbs (each call
   prompts on this host until REQ-C1.5's guard approval is built). Until signed publishing exists,
   a Mac branch merges only through your admin bypass (Q11 (b)).
1. **Build the boundary** (a spec task series): the boundary probe, the request queue and the hub
   verbs over the channel, signed publishing (Q11), and the refused-path and secret checks on
   publish. The guarantees in Section 4 start here.
2. **Canary.** One low-risk unit on the Mac with prompts off, the probe green before and after, and
   zero permission requests. Its run is compared with a local twin for denials, wall time and
   review findings.
3. **Default the Mac** for session-grade units placed on that host. The remote vetting paths
   (D-7's loop coverage, REQ-C1.1, REQ-C1.2) are dropped from `remote-worker-rung`'s plan before
   they are built; phases 0 to 2 vet by hand.
4. **Optional, long term:** the same isolation on this host, with a restricted Linux account for
   local workers. Once both hosts run isolated workers, the worker command guard, the permission
   queue, the pre-approval lists and the pending-prompt alarms retire entirely, and mission control
   is the only session that ever asks anything (Q9).

## Open questions for the operator

Each has a recommendation; the first is the one that shapes the rest.

**Q1. How does a Mac worker get its branch onto GitHub?**

- (a) **Recommended:** no write credential on the Mac. The hub pushes exactly the worker's branch
  and makes its PR writes through fixed verbs. The per-branch limit is exact per request (Q6 bounds
  which worker asked), merge is impossible, and workflow changes are refusable. Cost: the hub is in
  the path of every publish; it adds a few seconds per push, and publishing, review triggers and
  replies wait while the hub is down.
- (b) An hourly GitHub App token on the Mac, one repository, minted without the Workflows
  permission (so it cannot push workflow files), plus a ruleset confining it to a worker branch
  prefix and restricting updates to main. Workers push directly, but any worker can push to any
  other worker's branch under the prefix, since rulesets cannot bind one actor to one branch.
- (c) A fine-grained write token acting as you. Not recommended: it inherits your admin bypass
  of the main branch rules, so it can push to main.

**Q2. Who opens the pull request?** (a) **Recommended:** the hub, as you, so PRs look and are
handled exactly like today's (authorship, the review bots, the merge). (b) A bot identity: clearer
attribution, but some hosted reviewers skip bot-authored PRs, and every "my own PR" rule needs a
second identity.

**Q3. Branches that touch the refused paths** (Section 2's list: workflows, composite actions, git
hooks and the rest). (a) **Recommended:** the hub refuses to publish them from the Mac and the unit
restarts from the base on this host, where those zones already pause for you; the Mac's commits
are not carried over, so no Mac-authored code runs here. (b) Publish after your explicit yes per
branch. (c) Allow, relying on review: unsafe, since the workflow runs before anyone reviews it.

**Q4. The Mac's 1Password service token.** (a) **Recommended:** remove it. The hub renders what the
Mac's playbook needs and the files are copied in at the console playbook run, since none of it is
secret (the read-only GitHub token is installed the same way, per Section 4). (b) Keep it in a
separate, second macOS account that runs only the playbook. (c) Accept that worker code can read the dotfiles vault.

**Q5. The Claude login after a reboot.** (a) **Recommended after a probe:** a long-lived token
(`claude setup-token`, D-11's documented fallback) in an owner-only file, with Bash commands
sandboxed away from it and a Read deny rule on the file. The launcher reads it for the `claude`
process only, never through `remote-env.sh`, which every channel verb (`compute` included) sources
and which must hold no secrets; D-11 currently loads it through that file. That removes the manual
keychain unlock after each reboot. The probe checks that the token does not leak into commands'
environment. The trade-off: a compromised account can read this token, which lives longer than a keychain session.
(b) Keep the keychain login and unlock it by hand after each reboot; a compromised account can
still use it while unlocked.

**Q6. One work account, or one per worker slot?** (a) **Recommended now:** one account. Any worker
can file requests in another's queue (Section 4), so a compromised worker can push commits to,
resolve bot threads on and report done any other Mac PR in flight. The publish checks bound what
it can push; merge, main and tags stay out of reach; CI and your merge review are the independent
signals; but the hub's review-convergence reading of a Mac PR can be forged while another worker
shares the account. (b) One account per slot: the OS then authenticates each queue's writer, so
"its own PR" and convergence hold per worker, at the cost of per-account setup and caches.
Revisit if the Mac runs untrusted inputs routinely.

**Q7. Pinning the work account's SSH keys (a dotfiles PR).** (a) **Recommended:** sshd reads the
work account's keys only from a root-owned file, so a worker cannot add a backdoor key. (b) Leave
the account's `authorized_keys` unmanaged: accept that persistence. Making the owner's home
unreadable to other accounts (`chmod 700`, which the owner's own apps never notice) is not part of
this question: your decision rules out access to the owner's files (Sources), so phase 0 does it
and the boundary probe asserts it.

**Q8. Spend caps for prompt-free workers.** (a) **Recommended:** a per-unit wall-clock and turn cap
enforced by the Mac's supervisor, set from measured unit sizes, ending the worker with a named
result. It bounds an honest or runaway worker; a compromised one is bounded by revoking the login.
(b) No caps; rely on the stall detector.

**Q9. Isolate this host's workers too (migration phase 4)?** (a) **Recommended:** yes, after the
Mac canary. Then the approval machinery retires everywhere, and this host stops prompting except
for mission control. (b) Keep local workers on today's guards.

**Q10. Main-branch hardening (independent of the Mac).** (a) **Recommended:** pin the required
`check` and `title` statuses to the GitHub Actions app, so no personal or other app token can post
them. It does not stop a pushed workflow, which posts as that same app; only Q3's refusal does.
(b) Leave it: under Q1 (a) and Q3 (a) nothing on the Mac can post statuses anyway.

**Q11. How do Mac branches get signed commits?** The main ruleset rejects a squash merge whose head
branch carries unsigned commits. (a) **Recommended:** the hub re-signs the fetched commits with its
own key at publish (same trees, new signatures, done with git plumbing and no checkout), pushes
those, and the worker resets its branch to the published head before its next commit. Later
fetches must descend from that published head. Re-signing changes commit ids, so the hub keeps the
old-to-new map and the step audit, which matches records by commit ancestry, reads the worker's
records through it. (b) You merge every Mac PR through your admin bypass,
which also skips the required checks, and the readiness check reads such PRs as blocked. (c) A
signing key in the work account registered to your GitHub account: no push power, but a
compromised worker could mint commits that GitHub shows as verified from you.

## What this changes in the remote-worker-rung draft

Of the draft's open `(Q)` items, this decides D-7 (replaced), assumes D-9's yes and extends it,
and only partly answers D-16's credential boundary; D-8 is untouched. The rest are amendments to
settled decisions and requirements.

- **D-7, REQ-C1.1, REQ-C1.2 and REQ-C1.3's alarm over remote prompts** (this host vets remote
  prompts): replaced. There are no remote prompts; the request queue and its age alarm take their
  place, and the plan drops the vetting paths at migration phase 3 (phases 0 to 2 vet by hand).
  REQ-C1.4 (steer and the wake relay through the channel) and REQ-C1.3's attention item for
  an unreadable host survive, and need a decision to cite once D-7 goes.
- **D-9 and REQ-C1.5** (guard approval of the channel): kept for the hub's own calls and extended
  to the request-queue read and answer, plus approval of the hub's verb scripts by resolved path.
  The `answer --allow` posture is no longer needed for isolated workers.
- **REQ-A1.2** (a fixed set of channel verbs): amended to add the request-queue read and a
  request-answer write, as are the draft's tasks that list the verb set. The request verbs
  themselves (`publish`, `comment`, `reply`, `resolve`, `report-done`) are hub-side scripts, not
  channel verbs.
- **D-10 and REQ-B1.4, REQ-B1.7** (remote workers push; fetch-back is the fallback): inverted.
  Hub-side publish becomes the only path for isolated workers, which fixes the per-branch limit.
- **D-11 and REQ-F1.2** (remote login is the host's own): narrowed. The Claude login stays the
  host's own; the GitHub write login leaves the host, and a read-only token replaces it. D-11's
  token fallback stops loading through the remote environment file (Q5).
- **D-16 and REQ-G1.6** (compute's credential boundary): narrowed, not resolved. The account holds
  no GitHub write or 1Password credential, but it still holds the Claude login and the read-only
  GitHub token, which a compute run can read since the sandbox does not cover it. REQ-G1.6's first
  stance (no hosting-remote login at all) stays unmet either way. D-16's own options remain: a
  login-free account for compute, or your explicit acceptance.
- **D-14 and REQ-E1.4** (no safety rule relaxed by placement; the same profile, guards and
  cadence): amended. The cadence stays the same, but the profile and guards differ by design: the
  worker runs with prompts off, and its rules move to the boundary rather than disappearing. The
  REQ-E1.4 test-spec entry changes with it.
- **New:** the account profile, the request queue and its verbs, the publish checks, the boundary
  probe, per-unit caps, signed publishing (Q11), the command guard's approval of the hub's verb
  scripts, and the main-branch status pinning (Q10).
- **Undecided here, for `/spec-draft`:** the request queue's delivery semantics (at-most-once or
  idempotent verbs, the fate of a request whose worker has parked, what "park" means for a
  prompt-free worker); whether the stream-json queue can carry requests instead of a new queue;
  network-level egress limits for the work account; whether non-Anthropic review backends run
  hub-side for remote units; and the canary's pass thresholds beyond zero permission requests.

## Sources

- The operator's decision, relayed by the hub (2026-11-07): the best long-term, ergonomic setup,
  built around using the Mac ("we need to be able to use the mac or we won't get much done");
  workers in a restricted account with no prompts inside, guardrails at the boundary, a token that
  pushes only the worker's own branch, no operator secrets or `~/.claude` in the account, no access
  to the owner's files or Homebrew.
- PR #871 (merged): `specs/remote-worker-rung/` (Draft), `docs/research/remote-worker-over-ssh.md`
  and `scripts/fleet-remote.sh`, read at the PR's head; the suite timing and the gate-timeout
  finding come from the PR's description.
- Dotfiles PR #225, read-only: the Mac's offload posture and runbook (`docs/offload-host.md`),
  including the standard-account change, the credentials the runbook installs and its
  after-reboot keychain unlock.
- This repository's ruleset, workflow permissions and secrets, read through the GitHub API on
  2026-11-07, and `.github/workflows/`.
- `scripts/worker-command-guard.sh`, `config/worker-settings.json`, `scripts/policy-guard.sh`,
  `scripts/fleet-dispatch-guard.sh` (its refused launch modes, tested in
  `tests/test-fleet-dispatch-guard.sh`),
  `hooks/hooks.json` and the standing rules on Mac workers (full workers, inside the work account)
  and the ready flip on reviewer convergence.
- GitHub documentation: fine-grained tokens are scoped by repository and permission, not branch,
  and cannot call the Checks API
  ([managing your personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens));
  installation tokens expire after an hour and can be narrowed to repositories and permissions at
  mint time ([generating an installation access token](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app));
  the signed-commits rule checks the head branch's commits before a squash merge, and required
  checks can name an expected source app
  ([available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)).
- Claude Code: OS-enforced (Seatbelt on macOS) filesystem and network limits on Bash commands
  only, with `failIfUnavailable` to refuse running unsandboxed and `allowUnsandboxedCommands` to
  turn off the unsandboxed retry ([sandboxing](https://code.claude.com/docs/en/sandboxing)); what
  `dontAsk` and `bypassPermissions` approve, deny and still prompt for
  ([permission modes](https://code.claude.com/docs/en/permission-modes)). Whether deny rules and
  the sandbox hold under prompts-off mode in practice is a probe for the build, not a settled fact.
