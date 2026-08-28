# Concurrent Orchestrator Coordination — Verification notes

Manual verification records for the checks this bundle marks `[manual]`, which by
definition no fixture can stand in for. Each task whose `Done when:` carries a
manual anchor is **not complete until its entry exists here** — the anchor exists
so a manual check cannot be silently dropped.

This file is not part of the content anchor (`scripts/spec-anchor.sh` covers
`requirements.md`, `design.md`, `tasks.md`, and `test-spec.md` only), so
appending a record here neither moves the anchor nor needs a re-anchor entry.

## Task 3 — Per-tower checkout model, migration path & cross-checkout `main` currency

### 2026-08-25 — Two-checkout run (REQ-B1.1)

Two towers on two **separate checkouts** of one shared `origin`, each with
`branch.autosetuprebase=always` and `pull.rebase=true` set so the rebase pitfall
was live throughout.

**The two tower identities** (`scripts/fleet-presence.sh identity`, derived from
two real live processes, not fabricated pids):

| Tower | Checkout | Identity |
| --- | --- | --- |
| A | `tower-a` | `p791423.t2314714566.c1798629508` |
| B | `tower-b` | `p791424.t2314714566.c434091863` |

The identities differ in their checkout-hash component (`c1798629508` vs
`c434091863`), which is what confirms these are genuinely separate checkouts
rather than one checkout addressed twice.

**No shared-`main` mutation was observed.** With `origin/main` advanced to
`373a20a`:

- Tower A synced (`sync fast-forward`), moving **its own** `main` to `373a20a`.
- Tower B's `main` stayed at `fec1621` — **unchanged by A's sync**. This is the
  observation the requirement asks for: A moving `main` is invisible to B,
  because there is no shared mutable `main` for A to move under B.
- Tower B then synced independently while **mid-flight on a worker branch**
  (`planwright/demo/task-9`). It took the ref-update path (`sync ref-update`),
  advancing its `main` ref to `373a20a` while its checked-out worker branch
  stayed at `3324c25` — no foreign commit was dragged onto the worker branch.
- Neither tower's `main` reflog contains a `rebase` or `reset` entry.

**Sequencing, stated precisely.** The two towers were both live with work in
flight (B held an uncommitted worker branch across A's sync), but the two syncs
were run in sequence, not simultaneously. That is sufficient for what REQ-B1.1
asks: the isolation being verified is *topological* — A's `main` and B's `main`
are different refs in different clones — so simultaneity cannot strengthen it,
and the observation that matters (A moving `main` is invisible to B) is exactly
what the sequenced run shows. Recorded rather than left implicit, since the
requirement's wording says "concurrently".

Reproduction: `tests/test-main-currency.sh` covers the same paths as fixtures;
this entry records the two-checkout run those fixtures stand in for.

### 2026-08-25 — Fresh per-tower clone signs and fetches standing alone (REQ-B1.3)

A throwaway clone of `git@github.com:inkatze/planwright.git` was provisioned by
following `docs/per-tower-checkouts.md` step by step, then exercised with the
inherited `SSH_AUTH_SOCK` **unset** to simulate a dead session's plumbing.

- **Its own repo-root machine-local env file.** A `mise.local.toml` at the clone
  root, confirmed gitignored (`git check-ignore`), setting
  `SSH_AUTH_SOCK = "{{env.HOME}}/.ssh/auth_sock"`.
- **The env file demonstrably resolved.** In a shell entering the clone,
  `SSH_AUTH_SOCK` came back as `/home/inkatze/.ssh/auth_sock` — the stable
  symlink path, not a per-session socket and not empty.
- **The indirection is real.** That symlink targets the agent socket
  (`~/.1password/agent.sock`) today; re-pointing the symlink re-points every
  tower at once, whereas a captured `$SSH_AUTH_SOCK` would need every clone
  re-provisioned.
- **Fetch:** `git fetch origin main` against the real `origin` succeeded.
- **Sign:** an empty probe commit verified as `G` (good signature).

**Scope limit, recorded rather than glossed.** On this host, git signs with an
ssh key *file* (`gpg.format=ssh`, `user.signingkey=~/.ssh/id_signing`), so the
agent socket is not load-bearing for signing *here*. What this run positively
establishes is that a fresh clone provisioned by the documented path resolves the
stable indirection from its own repo-root env file and both fetches and signs
while standing alone. It does **not** establish that signing would fail without
the indirection on a host whose signing goes through the agent — that negative is
the 2026-06-12 incident this guard was mined from, and it remains the reason for
the step rather than something this run re-demonstrates.

A first attempt at this check was discarded as invalid: mise had not yet trusted
the config, so `SSH_AUTH_SOCK` resolved empty and the fetch and signature
succeeded through the machine's global plumbing — passing while proving nothing
about the clone's own env file. The record above is from the re-run with trust
established and the resolution asserted before the fetch and signing steps.

## Task 4 — Peer fence (per-unit origin CAS at dispatch, operator-surfaced strands)

### 2026-08-26 — Two-clone race for one unit (REQ-C1.6)

Two towers on two **separate clones** of one shared bare `origin`, both reaching
for the same unit (`coc-demo/9`) in the same pass. A bare-repo fixture in the
test suite stands in for this in CI; this is the end-to-end run it stands in for.

**The two tower identities** (`scripts/fleet-presence.sh identity`, derived from
two real live processes, not fabricated pids):

| Tower | Clone | Identity |
| --- | --- | --- |
| A | `tower-a` | `p720088.t1524824804.c2467175528` |
| B | `tower-b` | `p720091.t1524824804.c3789898683` |

The identities share a start-time component and differ in their checkout hash
(`c2467175528` vs `c3789898683`), which is what confirms two separate clones
rather than one addressed twice. Each tower saw the other:
`summary peers=1 sole-tower=no`.

**One winning fence ref.** Both towers ran the same fence command against the
same unit:

- Tower A: exit `0`, `fenced refs/planwright-fence/coc-demo/9`
- Tower B: exit `3`, `taken refs/planwright-fence/coc-demo/9`

`origin` ended the race holding exactly one fence ref,
`refs/planwright-fence/coc-demo/9`, at `eae6fbae` — which is the `origin/main`
tip itself. `main` stayed at one commit throughout: the fence is a ref at an
existing commit, so it adds no history (REQ-C1.2).

**Only one worker, and only one PR's worth of branch.** After the race, the
selection guard reported the unit fenced from *both* clones, so neither would
re-dispatch it. Tower A (the winner) dispatched; tower B dispatched nothing.
`origin` finished with a single task branch,
`refs/heads/planwright/coc-demo/task-9` — one worker, therefore one PR. Had the
losing tower treated its push's exit code as the verdict it would have dispatched
too, since git resolves a same-tip update to `[up to date]` and exits 0; the
winner is read from the per-ref `--porcelain` status instead.

**The fence retired itself on merge.** With task 9 merged to `main`, tower A's
sweep printed `gc refs/planwright-fence/coc-demo/9` and the fence namespace
returned to empty (REQ-C1.5).

Run on git 2.53.0, 2026-08-26. Clone names are the run-local ones; the machine
paths and the towers' death handles are deliberately not recorded here
(REQ-D1.4).
