# Seed brief: deterministic worker approvals

Captured 2026-11-07 by a mission-control flight, from the operator's ask:
"I thought duties were deterministic, that's a huge miss we need to get
fixed from the root". The flight was asked to build three things with no
model in the approval path. The first was a script that answers routine
worker permission requests itself. The second was a watcher that escalates
a stuck mission control. The third was a normalization of the `git -C <dir>`
and `git push -q` spellings.

The watcher shipped with this note (`scripts/mc-escalate.sh`, a
session-keeper watcher). The other two are below as a redesign, because the
measurements show the answerer, as asked, would approve almost nothing. The
fixes that would work amend two signed-off bundles and change the worker
posture.

## What the record shows

**The queue holds what the guard cannot read.** The flight replayed the
Bash permission requests that the stream-json workers journaled in the 48
hours before capture. It sampled 3,695 of them, replayed through the
installed worker command guard (0.68.0). Each replay ran in its worker's
recorded context: its cwd, its session record and its scratch `TMPDIR`. The
guard approved 7. A plain `grep -n foo README.md` in the same harness was
approved, so the low count is a real result. About two in three sampled
requests were compound lines (`&&`, `;`, pipes), about one in ten were
here-documents, and others carried variable-held paths or a `cd` into
another tree. The guard defers every one of those shapes by design (its
header's analysis model).

An answerer limited to "never approve what the guard would not" asks the
same deterministic question again and gets the same answer. It could only
help when the hook failed to run (a timeout, an unresolved root), and
nothing in the record shows that as a cause.

Caveat: the replay is not exact. The installed root has moved since some
requests were made (0.66.0 and 0.67.0 scripts no longer resolve), and some
worktrees are gone. Both effects push the replay toward defer.

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
script, fetch, add and plain reads). That is real but small: in-worktree
writes matter, and shape is the dominant cause.

**So the deterministic lever is the shape of what workers issue.** The
permission-prompt flight (worker `mc-planwright-worker-5cc9886fd3`) owns
that lever. It added `config/launch-shell-rules.txt` to every stream-json
launch: one plain command per call, no `cd`, no chains, no variables of the
worker's own, no staged scripts. It also added the step-context prefix the
guard now accepts. Requests in that shape are ones the guard can read and
approve at hook time, before anything is queued.

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
   into `worker-permission-ergonomics-amendment.md`:
   - `git -C <dir>`: the guard defers it on purpose (see `cd_same_repo`),
     because a `-C` into another repository hands git that repository's
     config. Approve it exactly when `<dir>` passes the check a `cd` already
     gets (`cd_target_ok`: inside the session's own worktree, with the same
     top level and common directory). Then verify the rest of the command as
     if the shell were there. A `-C` outside the worktree keeps deferring.
     This is a guard screen change and needs an adversarial fixture table, as
     that seed's decision 1 requires.
   - Push spellings: the guard never approves a push (floor), so pushes rely
     on the profile's `Bash(git push origin:*)` prefix rule. That rule misses
     `git push -q origin <b>` and `git -C <wt> push origin <b>`.
     - The `-q` form takes a prefix rule of its own, following the shipped
       `Bash(git push -u origin:*)` (that seed's decision 2).
     - The `-C` form cannot be bounded to the own worktree by a prefix rule.
       Either the guard gains a push arm limited to the recorded unit branch
       (a floor change, so an explicit operator decision), or `-C` pushes
       keep asking. The shell rules already tell workers to run git in their
       own worktree without `-C`.
4. **Only if item 1 leaves a measured residue: amend `execution-backends`
   D-5.** D-5 rejected auto-answering in the supervisor ("a second approval
   engine in the supervisor would duplicate a security-critical surface").
   The narrowest form that respects it is a replay-on-failure answerer, with
   these properties:
   - it runs the same installed guard on the queued request, in the
     worker's recorded context;
   - it approves only on the guard's allow, logged in the session's audit
     log;
   - it carries no policy of its own;
   - it covers a hook that never ran or timed out.

   It reverses a signed-off decision, so it needs that evidence first: a
   count of requests whose hook did not complete.

## The escalation watcher, as shipped

`scripts/mc-escalate.sh` runs under the session-keeper duty on every
program, with no model in the path. Two things qualify as overdue:

- a request of one of the program's own workers, still pending
  `mission_control_escalation_window` past the owner's pending-age alarm;
- the program's mission control showing an open dialog in its own pane for
  that long. Its pane is found from the `claude` process whose prompt is
  `/planwright:mission-control <program>`.

Either one becomes a `mission-control-escalated` event in the hub program's
store (`mission_control_escalation_hub`, default `hub`). At twice the
window, it goes to the notification seam. With no hub, or for the hub's
own items, the first level goes to the operator.

Two limits are left for a mission-control amendment:

- The operator level is only as good as `notification_channel`. On this
  host it resolves to `none`, and the `push` channel needs a live session to
  relay its markers, because a script cannot call the phone push tool.
- A mission control on another host (the Mac) has no pane here to read; its
  requests are still raised.

## Fold-detection note

Owners as read at capture:

- `worker-permission-ergonomics`: the guard and the worker profile. An
  amendment seed already exists.
- `execution-backends`: D-5, Ready.
- `mission-control`: D-11 and the session-keeper duty, Ready. It owns the
  watcher's follow-ups.
