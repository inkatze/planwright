# Seed brief: isolated remote workers (an extension of `remote-worker-rung`)

Suggested invocation, once the `remote-worker-rung` Draft (PR #871) is on main, in a fresh
session in the planwright repo with this file as the seed:

    /spec-draft remote-worker-rung

Fold-detection should land this in `remote-worker-rung` as an extension before that bundle's
kickoff, since it answers several of that bundle's open `(Q)` decisions (see
[What this changes in the remote-worker-rung draft](#what-this-changes-in-the-remote-worker-rung-draft)).
It does not prejudge extend-vs-spin-new if the draft has moved by then.

This is a design for the operator's review. Nothing here is signed off, and nothing in it changes
behaviour, configuration or workflows.

## The short version

**Goal.** Workers on the offload Mac run inside a restricted macOS account with **no permission
prompts at all**, and every guardrail sits at the boundary of that account instead of inside it:
the operating system keeps them out of the owner's files and Homebrew, and GitHub writes leave the
account only through the hub.

**The finding that shapes everything.** GitHub cannot limit a token to one branch. A fine-grained
token is scoped to repositories and permissions, never to branches; branch rules (rulesets) apply
per actor, and a token acting as the operator inherits the operator's admin bypass of them. This
repository's main-branch ruleset also asks for zero approvals, so any token that can write contents
and pull requests here can merge a green pull request into main. And anyone who can push a branch
can add a workflow that runs with a write-capable `GITHUB_TOKEN`. So "a token that can push only
its own branch" cannot be a token. It has to be a boundary that chooses the refspec.

**Recommendation.** The work account holds **no GitHub write credential**, only a read-only
fine-grained token. A worker commits in its own clone and asks the hub to publish. The hub fetches
the branch over the existing SSH channel and checks it mechanically: the exact branch name from
its dispatch record, fast-forward only, no workflow or hook files, a secret scan and the commit
lint. Then it pushes exactly that one ref with its own credential and opens or updates the draft
pull request. The few other GitHub writes a worker's cadence needs (triggering the hosted reviewer,
replying to and resolving bot threads on its own pull request) are also fixed hub verbs.
The worker never marks anything ready; the hub's readiness check does, as it already does. That
makes the per-branch limit exact, merge impossible, and workflow injection refusable. Inside the
account the worker runs prompt-free, with planwright's hooks kept as tripwires that only ever allow
or deny.

**What it retires.** For Mac workers: the per-command vetting loop, the worker command guard's
role, the stream-json permission queue's traffic, the pre-approval lists and the escalation
watcher. They stay for this host's local workers until those move into an isolated account too
(the last migration phase, an open question).

**Decisions for the operator** are in [Open questions](#open-questions-for-the-operator), each with
options and a recommendation. The first one, the credential shape, is the one that matters most.

## What exists today (grounding)

- **The channel.** PR #871 adds `scripts/fleet-remote.sh`: this host reaches the Mac by an SSH
  alias and runs fixed verbs (`root`, `launch`, `pending`, `answer`, `steer`, `status`, `retire`,
  `compute`) on the Mac's own installed planwright, every argument quoted, free text over stdin.
  Its Draft spec `remote-worker-rung` plans dispatch records, remote liveness, vetting of remote
  prompts through the channel (its D-7, D-9), and remote workers pushing their own branches with
  fetch-back through this host as the fallback (D-10, REQ-B1.7).
- **The Mac.** Dotfiles PR #225 makes the work account a standard (non-admin) macOS account
  reached by one key-only SSH key from this host's address, with password login off for every
  account. Tools come from mise in the account's home, and the owner's Homebrew is used read-only.
- **The credentials in that account today**, per the PR #225 runbook:
  - the second Claude subscription's login, in the account's keychain;
  - a `gh` login under the operator's GitHub identity, stored in plain text (the account has no
    keychain an SSH session can open);
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

1. **The OS boundary (the real one).** The work account is a standard macOS user. It cannot write
   the owner's home, the Homebrew prefix, `/Applications` or system settings, and cannot escalate
   (no admin group, no sudo rule). Everything the worker can damage is the account's own home.
2. **The GitHub boundary (the hub).** The account can read GitHub but not write it. Every write is
   a request the hub executes through a fixed, mechanical verb against the worker's dispatch
   record. No model judgment sits in that path, so a worker cannot argue its way past it.
3. **The inside layer (defense in depth, not a boundary).** The worker runs with prompts off.
   Planwright's hooks still fire there and refuse the reserved acts (push, ready flip, merge). An
   honest worker gets a clear message instead of a stall; a compromised one can edit its own
   settings, so nothing depends on this layer. Claude Code's OS sandbox for Bash commands (Seatbelt
   on macOS: a filesystem deny list and a network allowlist) is the candidate for the same layer,
   after a probe.

A worker's life: the hub dispatches through the channel. The worker runs its whole cadence on the
Mac (implementation, tests, polish), commits and asks to publish. The hub publishes and opens the
draft PR. The worker's post-PR steps ask the hub to trigger the hosted reviewer and to reply to bot
threads. The worker reports done, and the hub's readiness check flips the PR when the conditions
hold.

## 1. What workers lose, and how each is replaced

| Lost compared with this host | Replacement or acceptance |
| --- | --- |
| The operator's `~/.claude`: global instructions, settings, memory, personal skills (`review-shared`, `bot-review`, `panel-review`) | A **worker profile** for the account, rendered by the dotfiles playbook from tracked files: a sanitized global instructions file (git, PR and writing conventions only), a settings file with prompts off and the tripwire hooks, and the skills the cadence calls. The operator's `~/.claude` is never copied. Memory is not replaced: the brief carries what a unit needs (accepted, and it trims context). |
| GitHub write access (push, PR create and edit, comments, thread replies, ready flip) | The hub's publish and PR verbs (Section 3). The ready flip moves to the hub entirely. |
| Commit signing as the operator | Accepted: worker-branch commits are unsigned. What lands on main is GitHub's own signed squash commit, which the main ruleset already requires. The Mac's signing key is removed. |
| The GitHub MCP server and claude.ai connectors (Slack, docs) | Not needed by a worker: reads go through `gh` with the read-only token, writes through the hub. Connectors tied to the operator's account stay on the hub. |
| Non-Anthropic review backends (`panel-review`'s CLIs and their keys) | Run as hub-side steps against the pushed head, or not for remote units. Their keys never reach the Mac. |
| The fleet home (registry, journals, gate lock, attention store) | The Mac keeps its own fleet home. The hub sees it only through channel verbs and its local dispatch record (`remote-worker-rung` D-5, D-6). |
| Warm caches (mise tools, test caches, plugin cache) | Rebuilt once in the account's home; the playbook pre-installs the pinned tools. The first unit pays the cold start. |
| The 1Password service token | Removed from the account. Values the Mac's playbook needs that are not secret (the public key, the trusted address) are rendered on the hub and shipped as files. See open question Q4. |
| The host gate lock and the operator's machine-local config | The Mac's own gate pool (one slot) under its own machine-local layer. Nothing is shared with this host's. |
| Interactive help when a worker is stuck on a prompt | No prompts to get stuck on. Steering through the channel stays. |

## 2. Host-only checks

The rule: **a check that protects the boundary runs at the boundary; a check that only tests the
work runs wherever it fits, with CI as the gate of record.**

- **Boundary checks, run by the hub at publish time** on the fetched commits, never trusted from
  the worker:
  - the secret scan (gitleaks over the new commits);
  - the commit-message lint;
  - the refused-path check (workflows, composite actions, git hooks, hook config; Q3);
  - the branch-name and fast-forward checks;
  - the step-record audit (`step-run.sh audit`), re-run over the records the worker ships.

  A worker can disable its own pre-commit hooks, so the copies inside the account are a
  convenience. The hub runs these over git objects only: it never checks out or executes
  Mac-authored code, so a branch cannot run code on this host through a hook or a test.
- **Linux-only tests** (`/proc` liveness, `setsid`, `flock`, GNU-only paths): CI already runs the
  suite on Linux and macOS and is the gate of record. A worker skips the tests it cannot run on
  macOS by their existing platform guards, and the hub does not run them for it. Executing worker
  code on this host would breach the boundary above.
- **The planwright gate** (`mise run check`): the worker runs it on the Mac, which is faster there
  (PR #871 measured the supervisor suite at 134 s on the Mac against 501 s here). The PR #871
  finding that the whole gate does not fit one 10-minute tool call applies: the worker runs it
  detached (`detached-run.sh`) and waits in-turn. When the Mac's gate pool is busy, the standing
  rule holds: skip the local gate, CI decides.
- **`compute` (PR #871)** stays the way this host offloads its own test runs to the Mac. With no
  GitHub or 1Password credential left in the account, its credential exposure (`remote-worker-rung`
  D-16, REQ-G1.6) shrinks to the Claude login (Section 4).

## 3. How the hub and mission control supervise

- **Launch.** As in `remote-worker-rung`: the channel's `launch` verb on the Mac's own launcher,
  with the brief over stdin, the worker profile applied, prompts off and a dispatch record on the
  hub. The launch also records the branch the worker may publish and the pull request once one
  exists. That record is what makes "its own branch" checkable.
- **Observe.** The channel's `status` (remote evidence only, D-6) plus a new read of the worker's
  request queue. The Mac's capacity, the owner's idle signal and per-account usage are read on the
  Mac (D-8, D-12, D-13).
- **Steer.** The channel's `steer` verb, unchanged.
- **Permission flow: none inside.** The stream-json supervisor still carries the worker's stdio,
  but it receives no permission requests. Every planwright hook in the worker profile answers allow
  or deny, never ask, because an `ask` with nobody inside to answer is a stall. Mapping today's
  ask-returning hooks to deny-with-a-reason in the worker profile is one of the build tasks.
- **The request queue (replaces vetting).** A worker asks for an outward act by writing a request
  into its worker directory through a small planwright script that then waits, bounded, for the
  answer. The hub's vetting pass reads the queue through the channel and runs the matching verb.
  Each verb is a script with fixed checks:
  - `publish`: the checks in Section 2, then a push of exactly `refs/heads/<branch>` (fast-forward
    only by default), then a draft PR created or updated as the operator. Its body comes from the
    worker and is treated as data: length-capped, with `@` mentions defanged except configured bot
    logins, so a worker cannot notify a person (the messages rule).
  - `comment`: on the worker's own PR only, and only a comment addressed to a configured automated
    reviewer, such as the hosted reviewer's trigger.
  - `reply` and `resolve`: on a thread of the worker's own PR in which only automated reviewers
    have spoken. A thread a person has replied in is drafted into the handoff and held for the
    operator's yes, as today.
  - `report-done`: the worker's cadence is finished. The hub's readiness check (step audit, CI,
    mergeability, review convergence) decides the ready flip; the worker never flips.

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
| Runner offline (sleep, shutdown, reboot) | `caffeinate` while a worker runs (REQ-B1.6). After a reboot the keychain is locked and the login fails with a named auth error (REQ-C1.6). Today that needs a manual unlock, which Q5 addresses. The hub stops placing work on the host until a health probe passes. |
| A stuck worker | The "parked on a prompt" class disappears. The rest remains: a hung command, a loop burning tokens, a wait on a request the hub never answers. The remote status gives the last-event age, and the stall detector applies to it as remote evidence. The ladder is steer, then stop, then a fresh relaunch on the same branch. Per-unit caps on wall-clock time and turns, enforced by the Mac's supervisor, bound a prompt-free worker's spend (Q8). |
| The hub is down | Workers keep running and requests queue. On return the hub reconciles from its dispatch records. Nothing publishes while it is down, which is the safe direction. |
| Version skew between the hosts | The channel's version check before a dispatch (REQ-A1.6), extended to the request-queue format. |

## 4. Trust boundary and threat model

**Assets.** The owner's files, Homebrew and system; the operator's GitHub account and repositories;
this host; the second Claude subscription; the integrity of what reaches main.

**Assume the worker is fully compromised** (a prompt injection in a fetched page, a malicious
dependency, a model error that runs away). Everything inside the account, including its settings,
hooks and the sandbox configuration, is then attacker-controlled.

What it **can** do:

- Run any code as the work account, and read or change anything that account owns, including
  **other Mac workers' worktrees** in the same account. The hub's publish checks bound what such
  tampering can push. Per-worker accounts would close it fully (Q6).
- Read the second Claude subscription's login and spend or steal that account's usage. This is the
  one credential that must live there. Mitigations: the OS sandbox denies Bash commands reads of
  the login's location; usage per account is watched (D-13); the login can be revoked from the
  Claude account settings.
- Read the read-only GitHub token: it can read what that token selects, at most the source a
  worker already has.
- Reach the network: the LAN, and any host on the internet unless the sandbox allowlist holds.
- Plant persistence inside the account (a LaunchAgent, a crontab, a second SSH key in the
  account's unmanaged `authorized_keys`, which works from any LAN address). Q7 fixes the last one.
- Send the hub hostile data: request fields, PR bodies, result text. The hub's verbs are scripts
  that treat all of it as data, and mission control reads worker output as data, never as
  instructions. The one model in the path, mission control reading a result, is exposed to
  injection only through what it reads, so the verbs must not need it.

What it **cannot** do:

- Write the owner's files, the Homebrew prefix, `/Applications` or system settings, or escalate:
  a standard account, no sudo rule, the owner's home not writable. Reading parts of the owner's
  home depends on that home's permissions (Q7).
- Push any branch, merge, mark ready, close or edit any PR, or touch main or a tag. The account
  holds no write credential, and the hub pushes exactly one ref named by its own record.
- Run workflow code with a write token. The hub refuses to publish a branch that changes
  workflows or composite actions (Q3). Without that refusal, a pushed workflow could request
  `contents: write` and merge, since main needs zero approvals and its required checks are not
  pinned to a source.
- Reach this host. The account holds no key to it and this host trusts none from the Mac; the
  channel runs one way only.
- Run code on this host through its branch. The hub handles Mac-authored commits as git objects
  and never checks them out with hooks or runs them. They reach this host only after the
  operator's merge, through the normal review gate.

**Token scope and lifetime.** One fine-grained token, created by the operator:

- **Scope:** read-only (contents, pull requests, metadata, checks) on only the selected
  repositories.
- **Lifetime:** 90 days, rotated through the laptop-script 1Password flow, with a hub reminder
  before expiry.
- **Storage:** an owner-only file in the work account; nothing else.

The hub's own credential, the one that pushes, never leaves this host. If Q1 picks an on-Mac
write token instead, the recommended shape is a GitHub App installation token (one repository,
expiring after an hour, minted per worker by the hub), never a long-lived token acting as the
operator.

**How the boundary is verified.** A **boundary probe** suite the hub runs through the channel at
setup, after every Mac playbook run, and daily. Each probe has a positive control and must be seen
failing once before it is trusted (the repo's "green signals that measure nothing" lesson). It
asserts, as the work account:

- no admin group, and `sudo -n true` fails;
- writes to the Homebrew prefix, `/Applications` and the owner's home fail;
- reads of the owner's home fail, if Q7 chooses that;
- no `gh` login with write scopes, no GitHub SSH key, no signing key and no 1Password token;
- the read-only token's permissions read back as read-only, and a push of a canary ref with it
  is refused by GitHub;
- the worker profile's settings match the rendered copy;
- no unexpected LaunchAgents or crontab entries, and only the managed authorized key.

On the hub side the probe asserts that the publish verb refuses a canary branch for each refusal
class, and a periodic audit lists GitHub events on the operator's repositories that did not come
from the hub (a ready flip, a push or a comment by anyone but the hub's identity or the operator).
The audit's own output is reported, never silently green.

## 5. Approval machinery: what this retires, what stays, the migration

**Retired for Mac workers:**

- `scripts/worker-command-guard.sh` and the profile's allow rules: nothing prompts, so there is
  nothing to auto-approve.
- The stream-json permission queue's traffic (`fleet-streamjson.sh pending` and `answer` for
  remote workers): the supervisor stays as transport, and the queue stays empty.
- The pre-approval lists and literal-path allow rules for worker prompts.
- `remote-worker-rung` D-7 and REQ-C1.1 to REQ-C1.3 (vetting remote prompts) and the `answer
  --allow` half of D-9.
- The escalation watcher and the pending-age alarm for remote workers. The request-queue age
  replaces them, with the same alarm, and stall detection stays.

**Kept:**

- The hub's own guards: `policy-guard.sh` and `ready-guard.sh` on the hub's flips and pushes, and
  the hub guard's approval of the channel's fixed verbs (D-9), which grows to the request verbs.
- Planwright's hooks inside the account, as tripwires that allow or deny only.
- The readiness check and the review cadence, unchanged, now run by the hub for remote units.
- Everything local workers on this host use today, until phase 4.

**Migration, each phase reversible and gated on the one before:**

0. **Clean the account** (a dotfiles PR): sign out the operator's `gh`, remove the GitHub keys,
   the signing key and the 1Password token; install the read-only token and the worker profile;
   pin the account's authorized keys (Q7). The operator revokes the removed keys on GitHub.
   Until the request verbs exist, Mac workers use `remote-worker-rung`'s fetch-back path (REQ-B1.7)
   for delivery, with the hub pushing.
1. **Build the boundary** (a spec task series): the boundary probe, the request queue and the hub
   verbs over the channel, and the refused-path and secret checks on publish.
2. **Canary.** One low-risk unit on the Mac with prompts off, the probe green before and after. Its
   run is compared with a local twin for denials, wall time and review findings.
3. **Default the Mac** for session-grade units placed on that host. The remote vetting paths are
   deleted from `remote-worker-rung`'s plan, not built.
4. **Optional, long term:** the same isolation on this host, with a restricted Linux account for
   local workers. Once both hosts run isolated workers, the worker command guard, the permission
   queue, the pre-approval lists and the escalation watcher retire entirely, and mission control
   is the only session that ever asks anything (Q9).

## Open questions for the operator

Each has a recommendation; the first is the one that shapes the rest.

**Q1. How does a Mac worker get its branch onto GitHub?**

- (a) **Recommended:** no write credential on the Mac. The hub pushes exactly the worker's branch
  and makes its PR writes through fixed verbs. The per-branch limit is exact, merge is impossible,
  and workflow changes are refusable. Cost: the hub is in the path of every publish; it adds a
  few seconds per push and nothing when the hub is down.
- (b) An hourly GitHub App token on the Mac, one repository, plus a ruleset confining it to a
  worker branch prefix and restricting updates to main. Workers push directly, but any worker
  can push to any other worker's branch under the prefix, and workflow injection needs a
  push-path rule the plan may not offer.
- (c) A fine-grained write token acting as you. Not recommended: it inherits your admin bypass
  of the main branch rules, so it can push to main.

**Q2. Who opens the pull request?** (a) **Recommended:** the hub, as you, so PRs look and are
handled exactly like today's (authorship, the review bots, the merge). (b) A bot identity: clearer
attribution, but hosted reviewers may skip bot-authored PRs, and every "my own PR" rule needs a
second identity.

**Q3. Branches that change workflows, composite actions or git hooks.** (a) **Recommended:** the
hub refuses to publish them from the Mac and the unit is re-placed on this host, where those
zones already pause for you. (b) Publish after your explicit yes per branch. (c) Allow, relying on
review: unsafe, since the workflow runs before anyone reviews it.

**Q4. The Mac's 1Password service token.** (a) **Recommended:** remove it. The hub renders what the
Mac's playbook needs and ships the files, since none of it is secret. (b) Keep it in a separate,
second macOS account that runs only the playbook. (c) Accept that worker code can read the dotfiles
vault.

**Q5. The Claude login after a reboot.** (a) **Recommended after a probe:** a long-lived token
(`claude setup-token`) in an owner-only file, with Bash commands sandboxed away from it. That
removes the manual keychain unlock after each reboot. The probe checks that the token does not
leak into commands' environment. (b) Keep the keychain login and unlock it by hand after each
reboot.

**Q6. One work account, or one per worker slot?** (a) **Recommended now:** one account. Cross-worker
tampering is bounded by the publish checks and review. (b) One account per slot: full isolation
between workers, at the cost of per-account setup and caches. Revisit if the Mac runs untrusted
inputs routinely.

**Q7. Hardening the Mac further (a dotfiles PR).** (a) **Recommended:** both of the following.
sshd reads the work account's keys only from a root-owned file, so a worker cannot add a backdoor
key. The owner's home is made unreadable to other accounts (`chmod 700`), which the owner's own
apps never notice. (b) Only the sshd change. (c) Neither: accept persistence and reads of the
owner's readable files.

**Q8. Spend caps for prompt-free workers.** (a) **Recommended:** a per-unit wall-clock and turn cap
enforced by the Mac's supervisor, set from measured unit sizes, ending the worker with a named
result. (b) No caps; rely on the stall detector.

**Q9. Isolate this host's workers too (migration phase 4)?** (a) **Recommended:** yes, after the
Mac canary. Then the approval machinery retires everywhere, and this host stops prompting except
for mission control. (b) Keep local workers on today's guards.

**Q10. Main-branch hardening (independent of the Mac).** (a) **Recommended:** pin the required
`check` and `title` statuses to the GitHub Actions app, so no other token can post them. (b) Leave
it: under Q1 (a) nothing on the Mac can post statuses anyway.

## What this changes in the remote-worker-rung draft

- **D-7 and REQ-C1.1 to REQ-C1.3** (this host vets remote prompts): replaced. There are no remote
  prompts; the request queue and its age alarm take their place.
- **D-9** (guard approval of the channel): kept for the hub's own calls and extended to the request
  verbs. The `answer --allow` posture is no longer needed for isolated workers.
- **D-10 and REQ-B1.4, REQ-B1.7** (remote workers push; fetch-back is the fallback): inverted.
  Hub-side publish becomes the only path for isolated workers, which fixes the per-branch limit.
- **D-11 and REQ-F1.2** (remote login is the host's own): narrowed. The Claude login stays the
  host's own; the GitHub write login leaves the host, and a read-only token replaces it.
- **D-16 and REQ-G1.6** (compute's credential boundary): mostly resolved, since the account holds
  no GitHub or 1Password credential. What remains is the Claude login (Q5's sandbox answer).
- **REQ-E1.4** (no safety rule relaxed by placement): restated. The worker runs with prompts off,
  but its rules move to the boundary rather than disappearing.
- **New:** the worker profile, the request queue and its verbs, the publish checks, the boundary
  probe, per-unit caps, and the main-branch status pinning (Q10).

## Sources

- The operator's decision, relayed by the hub (2026-11-07): the best long-term, ergonomic setup,
  built around using the Mac ("we need to be able to use the mac or we won't get much done");
  workers in a restricted account with no prompts inside, guardrails at the boundary, a token that
  pushes only the worker's own branch, no operator secrets or `~/.claude` in the account, no access
  to the owner's files or Homebrew.
- PR #871: `specs/remote-worker-rung/` (Draft), `docs/research/remote-worker-over-ssh.md` and
  `scripts/fleet-remote.sh`, read from its branch.
- Dotfiles PR #225, read-only: the Mac's offload posture and runbook (`docs/offload-host.md`),
  including the standard-account change and the credentials the runbook installs.
- This repository's ruleset, workflow permissions and secrets, read through the GitHub API on
  2026-11-07, and `.github/workflows/`.
- `scripts/worker-command-guard.sh`, `hooks/hooks.json` and the standing rules on Mac workers
  (full workers, inside the work account) and the ready flip on reviewer convergence.
- GitHub documentation: fine-grained tokens are scoped by repository and permission, not branch;
  installation tokens expire after an hour and can be narrowed to repositories and permissions at
  mint time ([creating a personal access token](https://docs.github.com/en/enterprise-server@3.11/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token),
  [authenticating as an installation](https://docs.github.com/en/enterprise-server@3.4/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation)).
- Claude Code sandboxing: OS-enforced (Seatbelt on macOS) filesystem and network limits on Bash
  commands, with `failIfUnavailable` to refuse running unsandboxed
  ([sandboxing](https://code.claude.com/docs/en/sandboxing)). Whether deny rules and the sandbox
  hold under prompts-off mode is a probe for the build, not a settled fact.
