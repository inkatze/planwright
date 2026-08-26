# Per-tower checkouts: one clone per tower

When two towers orchestrate the same repository, the thing they collide over is
not `tasks.md` — that ledger is already state-safe — but the single mutable
local `main` they share. Every tower wants `main` current; keeping it current
means moving it; and a tower moving `main` under a peer that is mid-flight is
how a peer's unpushed work gets clobbered.

The fix is topological rather than procedural: **give each tower its own
checkout, so there is no shared mutable `main` to race over.** Towers coordinate
through `origin` and the machine-local presence surface instead of through a
local branch they both write.

This guide covers the topology, what it requires, how to migrate to it, and the
one sanctioned way to run without it.

## The topology

Each tower is a **separate clone** with its own working tree, its own object
store, and its own private mutable local `main`:

```text
~/dev/planwright-tower-a/     clone A — tower A's private main
~/dev/planwright-tower-b/     clone B — tower B's private main
                origin (GitHub) — the shared coordination substrate
```

What each tower owns privately:

- **Its local `main`.** Advanced only by fast-forward from `origin`, never
  committed to directly, never seen by any peer.
- **Its worktrees.** Worker worktrees are cut from that clone's `main`.
- **Its runtime markers and locks.** The per-spec advisory lock is
  checkout-local, which is precisely why it cannot serialize peers in *other*
  clones — see the precondition below.

What every tower shares, and coordinates through:

- **`origin`.** The per-unit dispatch fence refs under
  `refs/planwright-fence/<spec>/`, the task branches, and the PRs.
- **The presence surface.** A machine-local, single-host directory carrying one
  record per live tower (`scripts/fleet-presence.sh`), used for peer awareness
  and for attributing an orphan fence ref to its owner — never for exclusion.

Note the asymmetry: **`origin` is the correctness substrate, presence is the
awareness substrate.** A broken presence surface blinds a tower to its peers; it
cannot cause a double dispatch, because nothing on the correctness path reads it.

### Why not `git worktree`?

The obvious cheaper answer — several worktrees of one clone, one per tower —
does not solve the problem. Git forbids checking out the same branch in two
worktrees, and every worktree still shares the single `main` ref and one object
store. The shared-`main` collision is relocated, not removed. Separate clones
are what make a `main` genuinely private.

## The reachable-`origin` precondition

**Multi-tower operation requires a reachable `origin`.** This is a hard
precondition, not a performance note, and it follows from `origin` carrying
*both* coordination duties:

- **The correctness floor.** Dispatch exclusion is an atomic expect-absent
  compare-and-swap creating a per-unit fence ref on `origin`. The push *is* the
  serializer: `origin` serializes ref updates, so exactly one tower wins a unit.
  A checkout-local lock cannot stand in for this, because peers in separate
  clones never contend for it.
- **`main` currency.** Each private `main` fast-forwards from `origin`; there is
  no other channel by which one tower's merged work reaches another's checkout.

So a host with no `origin` configured is **not a degraded multi-tower setup — it
is the single-checkout solo flow.** One tower, no peers to exclude, no
cross-clone currency to maintain. That distinction is why the sync path
classifies a fetch failure before acting rather than treating every failure
alike: a missing `origin` is a configuration state and proceeds solo, while a
*transient* failure against a configured `origin` fails closed.

## Keeping `main` current

Currency runs through one script — `scripts/main-currency.sh` — so the
discipline lives in a single tested place:

```sh
scripts/main-currency.sh sync --checkout <tower-clone>
```

It fetches, then fast-forwards, and nothing else. Three hardenings matter enough
to state here; the script's own header carries the full rationale.

**It is fast-forward-only, and never a bare `git pull`.** A private `main` is
never committed to directly (commits ride task branches and reach `origin` by
PR), so currency is always a fast-forward. `--ff-only` therefore costs nothing on
the happy path while turning unexpected divergence into an explicit refusal
rather than a silent merge commit. The explicit `git fetch origin main && git
merge --ff-only FETCH_HEAD` form also neutralizes the `branch.autosetuprebase=always`
pitfall, under which a bare `git pull` silently becomes a **rebase** — a history
rewrite the never-rewrite floor forbids.

That pitfall is worth dwelling on, because it is invisible after the fact: a
fast-forward merge and a rebase of a branch with no divergent commits produce an
*identical* commit graph. You cannot audit for it in `git log`. It is only ever
detectable at the level of which command was invoked, which is how
`tests/test-main-currency.sh` asserts it.

**It never merges onto a worker branch.** `git merge FETCH_HEAD` merges into
whatever is checked out, so the operation is chosen by what *is*:

| Checked out | Operation |
| --- | --- |
| `main`, in a work tree | `git fetch origin main` + `git merge --ff-only FETCH_HEAD` |
| anything else | `git fetch origin main:main` — a ref update needing no checkout |

A bare checkout takes the second form too. It points HEAD at `main` while having
no tree to merge into, so the choice turns on whether a work tree exists as well
as on what is checked out.

The second form refuses a non-fast-forward by nature: the refspec carries no
leading `+` and no `--force`, so git rejects a non-ff update on its own.

There is one case the second form cannot serve: `main` checked out in a **sibling
worktree** of the same clone — the ordinary shape, where the primary checkout
sits on `main` and worker worktrees are cut from it. git refuses to update a
branch ref checked out anywhere, correctly, since moving it would desynchronize
that worktree's index. The sync detects this up front and names the checkout that
owns `main`, because that is where running it works (it fast-forwards there).
This is deliberately *not* reported as a fetch failure: it is permanent, and
retrying it forever would be a dead end rather than a recovery.

**It classifies each failure before acting, and names a remedy that works.** No
`origin` configured degrades to the solo flow and is not an error. A transient
failure against a configured `origin` fails closed — surfaced, with `main` left
where it was, because running a tower on a silently-stale `main` is worse than
not running it this cycle. Beyond those, each refusal is distinguished rather
than lumped together:

| Situation | What it is | What to do |
| --- | --- | --- |
| Local `main` is genuinely ahead of / apart from `origin/main` | A real divergence, which a private `main` should never have | Resolve the unexpected history yourself |
| `main` has uncommitted changes | **Not** a divergence — still a clean fast-forward behind | Commit or stash, then re-run |
| Untracked files collide with files the incoming commits add | **Not** a divergence either, and invisible to the dirty-tree check, since untracked files are not in the index | Move or remove the files git names, then re-run |
| `main` is checked out in a sibling worktree | Permanent and structural, not transient | Run the sync in that checkout |
| `origin` unreachable, but configured | Transient | Retry next cycle |
| A credential or transport error that says "rejected" | Transient — it never reached the ref, so it is not a rejected ref update | Retry next cycle |
| Anything else the sync cannot place (a locked index, a full disk, a permission error) | Transient, which is what an unclassified refusal has earned | Retry next cycle |

Only the colliding file blocks a sync, never untracked files at large: a blanket
check would refuse over any stray build artifact, so the collision is classified
from git's own refusal rather than pre-empted.

The default for an unrecognized refusal is deliberately the transient one. "Retry
next cycle" is the recovery an unknown failure has actually earned; "your history
has diverged" is a diagnosis the sync cannot support, and sending you after
history that does not exist is the more expensive mistake of the two.

The distinctions are the point. A dirty tree reported as "divergence" sends you
hunting history that does not exist; a permanent refusal reported as "retry next
cycle" is a dead end dressed as a recovery. Whatever the case, the path never
forces, rebases, or resets, and never discards uncommitted work.

Every refusal exits non-zero with the recovery action named in its message; the
script header carries the exit-code table.

## Migrating from the single-checkout model

The single-checkout model — one clone, `main` kept effectively read-only,
reconcile via a quick PR — was the mitigation this topology supersedes. Migrating
means provisioning a second clone that can sign and fetch **on its own**,
inheriting nothing from the session that created it.

### 1. Clone into its own directory

```sh
git clone <origin-url> ~/dev/planwright-tower-b
```

One clone per tower, each in its own directory. Do not point a second tower at
an existing clone's worktree.

### 2. Give the clone a repo-root machine-local env file

Machine paths and session plumbing belong in a gitignored, per-machine env file
at the **repo root**, using the stack's native convention (`mise.local.toml`,
`.envrc.local`, `.env.local`). Never in tracked config, and never as secrets in
either.

Placing it at the repo root — rather than inside each worktree — is deliberate:
ancestor-directory config loading means one file covers every worktree the clone
later creates, so a fresh worktree needs no per-worktree setup. Pair it with your
tool's trusted-path mechanism so fresh worktrees need no per-worktree trust step
either.

### 3. Point signing at a stable `auth_sock` indirection

This is the step that breaks silently if skipped, and it has a specific incident
behind it.

A forwarded SSH agent socket is **ephemeral**: its path contains the session that
created it, and it dies with that session. A long-lived tower that captured such
a path at startup keeps referencing a socket that no longer exists — and commit
signing fails across every worker it later spawns, long after the session that
supplied the path is gone.

So a tower must reference a **stable indirection**, never a captured value:

```sh
# The stable path every tower references — never the forwarded socket directly.
ln -sf "$SSH_AUTH_SOCK" ~/.ssh/auth_sock
```

Then point the clone's env file at `~/.ssh/auth_sock`. Refreshing the symlink on
login re-points every tower at once; capturing `$SSH_AUTH_SOCK` into each tower's
config would require re-provisioning all of them.

### 4. Confirm the clone stands alone

From the new clone, in a shell with no inherited session plumbing, verify it can
do both things it needs `origin` for:

```sh
git -C ~/dev/planwright-tower-b fetch origin        # reachable origin
git -C ~/dev/planwright-tower-b commit --allow-empty -m "signing probe"  # signs
```

A clone that cannot sign or cannot fetch is not ready to be a tower: it will fail
at dispatch (no fence) or at currency (fail-closed), which is the correct
behavior but a poor time to discover the problem.

## The sanctioned fallback

Where a second checkout genuinely cannot be provisioned, **the single-checkout
reconcile model remains sanctioned** — it is a supported degraded rung, not a
deprecated one. Degrade capability, never safety.

Running it means keeping the discipline the topology otherwise makes unnecessary:

- Treat local `main` as read-only. Never `reset --hard` it, never direct-push it.
- Reconcile via a quick PR rather than by moving `main` under a peer.
- Accept that exclusion between towers sharing the checkout rests on the
  checkout-local lock plus operator discipline, not on the cross-clone fence.

What you give up is the root fix: both towers still share one mutable `main`, and
one lapse still clobbers a peer's unpushed commits. That is the incident this
topology was mined from, so prefer separate clones whenever they are available.

## Invariants this preserves

The per-tower-checkout model changes the *topology* of orchestration, not its
state model. Every guarantee `orchestration-concurrency` establishes carries
through unweakened:

- **Progress state stays a derived projection.** The durable evidence is still
  git, the runtime markers, and `gh`'s PR state; `tasks.md` sections remain a
  discardable snapshot a reconcile sweep rebuilds. Per-tower clones change where
  that evidence is read from, never what counts as evidence. Since every tower
  derives from the same `origin`, the projection stays consistent across clones.
- **`main` still carries no dispatch commit.** The fence is a ref pointed at an
  *existing* commit, so fencing adds no history to `main`, and a worker worktree
  cut from `main` still inherits nothing foreign.
- **History is still never rewritten.** The sync path performs no rebase, no
  `reset --hard`, no `--amend`, and no force-push — and pushes to `main` not at
  all, since currency flows `origin`→local only. These absences are asserted at
  the command level by `tests/test-main-currency.sh`, not merely stated here.
- **The tower non-authoring boundary is untouched.** A tower still edits no
  peer's or worker's branch state. Separate clones make that boundary easier to
  hold, not weaker: a peer's branches are not even present in this clone's
  working tree.
- **Merge and PR-ready remain reserved human controls.** Nothing in this
  topology touches them.
