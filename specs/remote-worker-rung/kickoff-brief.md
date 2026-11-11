# Remote worker rung — Kickoff brief

## 1. Header

- **Spec:** `specs/remote-worker-rung`
- **Spec commit at walkthrough start:** `59175a1135dc0a082469a34df89cb97174b330b4`
- **Walkthrough date:** 2026-11-10
- **Mode:** first activation (Status Draft, no prior brief), relayed through
  mission control; every question was answered in the operator's own words.
- **Validator at pre-flight:** `scripts/spec-validate.sh` — 0 errors, 0 warnings
- **Doctrine resolved at run start:** spec-format, kickoff-verification and
  the other kickoff docs (resolved from the installed plugin).
- **Structured decision/transcript log:** no harness-provided log in this
  session; the turn mirror is skipped, not improvised into the repository.
- **Working location:** the flight worktree on its own branch off main; the
  spec branch for the push is created from it at sign-off.

## 2. Goal & glossary

**Restatement.** Let a session on this host run a worker on another SSH-reachable
host (today the shared Mac, tomorrow possibly a cloud workspace) and supervise it
as closely as a local one, with the branch travelling through GitHub. The same
channel also runs a worktree's committed test or check on that host with no
worker involved. The host is always an SSH alias in machine-local config.

**Rules out:** a second mission control, cross-machine messaging, installing
anything on the remote host, cloud workspace lifecycle, interactive attach,
dollar spend limits, other model providers, and per-account usage tracking.

**Assumes:** the remote host has its own planwright, Claude login and
(normally) GitHub login set up by the operator; one Claude account covers
both hosts.

**Implicit terms, resolved:** "free" for a shared host means its input has been
idle for 15 minutes and the hold switch is off; "lost" means unreachable past a
30-minute grace; the "simple usage version" means the existing shared gate.

**Spec edits applied in this section:** none.

Signed off: 2026-11-11

## 3. Requirements walkthrough

Operator decisions recorded (2026-11-10):

1. Accounts: one account covers every host. Per-account tracking, differing
   reset days and metered accounts move out of scope; remote dispatch uses the
   shared usage gate and a host on a different account is refused.
2. A shared host takes work after 15 minutes of idle input, with the hold
   switch; running work is not stopped when the owner returns.
3. This host's mission control vets remote prompts; the guard approves the
   channel's fixed verbs.
4. Test runs on the Mac execute branch code as the fleet account that holds
   its logins; the exposure is accepted and recorded in the host's entry.
5. Placement: a free remote host first, this host otherwise, a pin wins.
6. The fetch-back path for a host with no GitHub login stays.
7. Unreachable grace: 30 minutes.

**Spec edits applied (consolidated):**

1. `requirements.md`: goal, scope, out-of-scope, REQ-B1.3 and REQ-D1.2
   defaults, REQ-D1.3 to D1.5 rewritten, REQ-E1.2 rule, changelog, sources.
2. `design.md`: origin tag `K` added; D-7, D-8, D-9 and the credential
   boundary marked settled; D-13 and D-15 rewritten; D-2 grace default.
3. `tasks.md`: usage verb dropped from Task 1; Task 7 reshaped and its
   dependencies and effort cut; Task 8 effort and rule; Task 2 citations;
   Task 11 extends `compute-route.sh`, which shipped meanwhile.
4. `test-spec.md`: REQ-D1.3 to D1.5, REQ-E1.2, REQ-B1.3, REQ-D1.2 entries.

Signed off: 2026-11-11

## 4. Design walkthrough

All decisions accounted for: D-1 to D-6, D-10 to D-12, D-14 and D-16 confirmed;
D-7, D-8, D-9 confirmed by the operator; D-13 and D-15 amended (one account);
none superseded. No decision contradicts a requirement.

Signed off: 2026-11-11

## 5. Verification approach

`[test]` entries run in CI on the fake-SSH harness; the live run (REQ-B1.4,
the REQ-C1.6 manual arm) is a `[manual]` acceptance owned by the last task.
No dead paths found: every requirement names a verification that can run.

Signed off: 2026-11-11

## 6. Task graph

Dependencies lines are authoritative. Tasks 1 and 2 start in parallel; Task 7
now needs only Task 2. Critical path runs Task 1, 3, 5, 10 and Task 2, 6, 8, 10.
Deliberate non-edges: Task 9 does not wait on vetting (Task 5); Task 11 does not
wait on dispatch (Task 3), because gate runs need no worker.

Signed off: 2026-11-11

## 7. Risk register

1. Compute runs branch code under an account holding the GitHub and Claude
   logins (plain-text GitHub token on the Mac). Accepted by the operator for
   the first host; recorded in its registry entry; a host with no recorded
   stance takes no compute.
2. A second Claude account on a host is refused, not tracked: a future
   second-account setup needs its own bundle.
3. The shared Mac's owner may return mid-run: running workers continue by
   decision; the cost is the owner's machine being busy.
4. Decision-domains gap check: no catalogued domain was found touched but
   undecided beyond the above.

Signed off: 2026-11-11

## 8. Lens review

Delta-scoped and whole-bundle lens review walked inline (declared: a
four-file bundle with one operator-settled delta; the Discovery-Rigor fan-out
was not launched, given host load and the narrow delta). Findings, all
dispositioned: (1) stale per-account wording in Task 1, Task 7 and the
test-spec: applied; (2) Task 7 title and Task 1 citations stale: applied;
(3) test-spec defaults for grace and idle: applied; (4) the plain-language
summary given to the operator mid-walk misstated size as eight build steps
about eight days; the bundle has eleven tasks and about twelve days of
estimate, and nothing in the bundle carries the wrong figure: reported, no
spec edit. Validator re-run: 0 errors, 0 warnings.

## Sign-off record

Signed off 2026-11-11 by the operator, relayed through mission control: the
sign-off question was answered "Sign off (Recommended)". First activation:
`**Status:**` Draft to Ready and `**Last reviewed:**` 2026-11-11 on all four
spec files.

Class: meaning
Lens-pass: section 8, whole-bundle lens review above (every finding dispositioned)
Anchor: `bafbcc088159cf16c98a54b8e1be4d10207a5402` — computed as
`scripts/spec-anchor.sh specs/remote-worker-rung`
