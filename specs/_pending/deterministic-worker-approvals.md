# Seed brief: deterministic worker approvals

Captured 2026-11-07 by a mission-control flight, from the operator's ask:
"I thought duties were deterministic, that's a huge miss we need to get
fixed from the root". The flight was asked to build three things with no
model in the approval path:

- a script that answers routine worker permission requests itself;
- a watcher that escalates a stuck mission control;
- a normalization of the `git -C <dir>` and `git push -q` spellings.

The watcher shipped with this note (`scripts/mc-escalate.sh`, a
session-keeper watcher), with a narrow relay for the operator's answer to a
stuck mission control's dialog (`scripts/mc-pane-answer.sh`). The other two
are below as a redesign. The measurements show the answerer, as asked,
would approve almost nothing, and the fixes that would work amend signed-off
bundles and change the worker posture.

## What the record shows

**The queue holds what the guard cannot read.** The flight replayed the
Bash permission requests that the stream-json workers journaled in the 48
hours before capture. It sampled 3,695 of them, replayed through the
installed worker command guard (0.68.0). Each replay ran in its worker's
recorded context: its cwd, its session record and its scratch `TMPDIR`. The
guard approved 7. A plain `grep -n foo README.md` in the same harness was
approved, so the low count is a real result.

About two in three sampled requests were compound lines (`&&`, `;`, pipes)
and about one in ten were here-documents. The guard approves a compound
line when every segment is a shape it knows (its header's analysis model),
so the compound count is the shape mix, not the cause by itself. What made
those lines defer was a segment the guard does not approve: a
here-document, a variable it cannot resolve, a `cd` into another tree, a
staged script, a write outside the read-only arm.

An answerer limited to "never approve what the guard would not" asks the
same deterministic question again and gets the same answer. It could only
help when the hook failed to run (a timeout, an unresolved root), and
nothing in the record shows that as a cause.

Caveat: the replay is not exact. Some requests ran under 0.66.0 and 0.67.0,
which are no longer an installed root the guard trusts, and some worktrees
are gone. Both effects push the replay toward defer.

**The guard's write policy is switched off, and switching it on helps only
at the margin.** The self-approval arms (`worker_self_approval`:
`own-branch`, `scratch`; worker-permission-ergonomics REQ-F1.1, D-12)
approve these, audited and never the floor:

- in-worktree writes;
- `git add`, `commit` and `fetch` on the unit branch;
- `mktemp` and writes under the scratch `TMPDIR`.

The knob defaults to empty (`config/defaults.yml`), and neither this
repository nor dotfiles sets it. Every worker session record from the three
days before capture says `policy=`. The flight replayed a sample of 2,332
requests from workers whose worktrees still exist, with the policy set to
`own-branch scratch`. The guard approved 61 (`mktemp -d`, the commit-trailer
script, fetch, add and plain reads). That is real but small.

**So the deterministic lever is the shape of what workers issue.** The
permission-prompt flight (worker `mc-planwright-worker-5cc9886fd3`, branch
`planwright/flight/mc-planwright-worker-5cc9886f`, unmerged at capture)
owns that lever. It adds `config/launch-shell-rules.txt` to every
stream-json launch: one plain command per call, no `cd`, no chains, no
variables of the worker's own, no staged scripts. It also adds a
step-context prefix the guard accepts. Requests in that shape are ones the
guard can read and approve at hook time, before anything is queued.

## What to do, in order

1. **Measure after the shell rules land.** Re-run the replay above
   against requests journaled after the shell-rules change reaches workers.
   The residue it leaves is what the items below are sized against.
2. **Operator decision: turn the shipped arms on.** Set
   `worker_self_approval: own-branch scratch` in the planwright primary
   checkout's `.claude/planwright.local.yml` or `.claude/planwright.yml`
   (dotfiles keeps its own). A worker picks it up on relaunch. This is a
   posture change, so it is the operator's call. Its yield grows as shapes
   become plain, because a plain `mkdir`, `git commit` or `mktemp` in the
   worktree is what the arms approve.
3. **Amend `worker-permission-ergonomics` (guard and profile).** Fold this
   into `worker-permission-ergonomics-amendment.md`. The `-C` and `-q`
   spellings differ:
   - `git -C <dir> push` and `git -C <dir> commit` are not merely
     unmatched: the worker profile denies them (`Bash(git -* push*)` and
     `Bash(git -* commit*)` in `config/worker-settings.json`), and a deny
     outranks every allow, a hook's included. Approving them means
     narrowing those denies to a `-C` outside the own worktree, a floor
     change and an explicit operator decision, plus a guard arm limited to
     the recorded unit branch and worktree (`cd_target_ok`'s check: inside
     the session's own worktree, the same top level and common directory).
     The adversarial fixture table that seed's decision 1 requires comes
     with it.
   - `git -C <dir>` with a read-only subcommand meets no deny; the guard
     defers it on purpose (see `cd_same_repo`), because a `-C` into another
     repository hands git that repository's config. Approving it exactly
     when `<dir>` passes `cd_target_ok`, then verifying the rest as if the
     shell were there, is a guard screen change only.
   - `git push -q origin <b>` meets no deny but misses the
     `Bash(git push origin:*)` prefix rule. It takes a prefix rule of its
     own, following the shipped `Bash(git push -u origin:*)` (that seed's
     decision 2).
   - Whatever lands, the shell rules should tell workers to run git in
     their own worktree without `-C`; the sibling's text does not say so
     yet.
4. **Only if item 1 leaves a measured residue: amend `execution-backends`
   D-5 and `worker-permission-ergonomics` REQ-F1.2.** D-5 rejected
   auto-answering in the supervisor ("a second approval engine in the
   supervisor would duplicate a security-critical surface"), and REQ-F1.2
   keeps the guard the only self-approval mechanism, with no tower,
   supervisor or relay answering a worker's prompt on the policy's
   strength. The narrowest form that respects their intent is a
   replay-on-failure answerer, with these properties:
   - it runs the same installed guard on the queued request, in the
     worker's recorded context;
   - it approves only on the guard's allow, logged in the session's audit
     log;
   - it carries no policy of its own;
   - it covers only a hook that never ran or timed out.

   It reverses signed-off decisions, so it needs that evidence first: a
   count of requests whose hook did not complete.

## The escalation watcher and relay, as shipped

`scripts/mc-escalate.sh` runs under the session-keeper duty on every
program that enables it (the default duty set does), every minute, with no
model in the path. Two things qualify as overdue:

- a request of one of the program's own live workers, still pending
  `mission_control_escalation_window` past the owner's pending-age alarm;
- the program's mission control showing an open dialog in its own pane for
  that long, auto mode's confirmation after blocked actions included (it
  shows in the pane, not over Remote Control). Its pane is found from this
  user's `claude` process whose prompt is `/planwright:mission-control
  <program>`.

Either one becomes a `mission-control-escalated` event in the hub program's
store (`mission_control_escalation_hub`, default `hub`, when its holder is
live). At twice the window, it goes to the notification seam. With no live
hub, a hub that refuses the event, or for the hub's own items, the first
level goes to the operator.

`scripts/mc-pane-answer.sh` delivers the operator's answer to such a
dialog: one digit into that program's own mission-control pane, only
against the configured hub's note of the operator's answer about that very
dialog (subject `<program> dialog <digest>`, answer the digit), made after
the watcher first saw the dialog and used once, and only for an option
whose label answers this dialog and nothing more (an exact allowlist). It
is not on the worker profile's allow list: without the exact-path allow
rule the operator adds, the auto-mode classifier still judges each call.

Left for a `mission-control` amendment, which owns the follow-ups:

- **Scope.** D-27 scopes session-keeper to lifecycle (D-10, D-11). The
  watcher adds cross-program escalation: it writes into another program's
  event store, and its operator push goes through the notification seam
  rather than `mc-shadow.sh raise`, so a session-keeper in shadow still
  pushes. The amendment should place this (a duty of its own, or
  session-keeper's charter widened) and say whether the hub's own duties
  gate what it receives.
- **The hub's handling.** No skill text yet says what a hub does with a
  `mission-control-escalated` event. The event text asks it to reach the
  stuck mission control or the operator and carries no request content; the
  skill should say the hub never reads or answers another program's worker.
- **The operator level** is only as good as `notification_channel`. On this
  host it resolves to `none`, and the `push` channel needs a live session to
  relay its markers, because a script cannot call the phone push tool. The
  watcher's line names the channel, so `none` is visible.
- **The relay's trust root.** The decisions log is written by mission
  control itself. The relay proves an operator-words entry was recorded
  after the dialog appeared, not that the operator said it; a session able
  to forge an entry could answer its own hub's peer. Binding the entry to an
  operator-only act (a Remote Control message id, a signed token) would
  close it.
- **Same-user trust.** The relay narrows what a mission control does
  through it, not what this user account can do: any process of the user
  can still run `tmux send-keys` itself. The relay is the sanctioned path,
  and its allow rule must name its exact installed path, never a glob.
- **The capture-to-keystroke race.** The pane is read again just before the
  keystroke, but a dialog that replaces it in between receives the digit.
  The window is one tmux call wide; closing it needs the CLI to accept an
  answer bound to a dialog id.
- **Screen scraping.** Dialogs are read from pane text, a platform surface.
  A layout change reads as no dialog, a different dialog or a broken option
  run, each of which refuses; a new label wording is refused until the
  allowlist learns it. It fails closed, but it can stop answering after a
  CLI update.
- **Reach.** A mission control on another host (the Mac) has no pane here
  to read; its requests are still raised. A session started as plain
  `claude` with the skill typed in afterwards reads `absent`; resolving the
  session through the holder record would cover it.

## Fold-detection note

Owners as read at capture:

- `worker-permission-ergonomics`: the guard and the worker profile, and
  REQ-F1.2. An amendment seed already exists.
- `execution-backends`: D-5, Ready.
- `mission-control`: D-11, D-27 and the session-keeper duty, Ready. It owns
  the watcher's follow-ups.
