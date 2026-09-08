# Recurring failure classes in planwright

> **A dated snapshot, not a live document.** Written 2026-09-07 against
> `origin/main` at `49a529e` by an independent analysis pass, and preserved
> as it was written. Several of its findings have shipped since; the status
> note below says which, and the body has deliberately not been edited to
> match — a record of what was true when it was written is worth more than a
> tidied one that hides how the reading changed.
>
> **Shipped since:** the guard-reachability check it proposes in §4.5 (#424,
> which also restored `check-backend-capability-drift.sh` to the gate and
> allowlisted `check-confirmation.sh`); the fixture supervisor leak (#423);
> the vacuous-guard round it catalogues, in part.
>
> **Still open:** the sibling `check:script-reachability`, the demonstrated-red
> requirement in §4.6, and the dead mechanisms it enumerates. The
> observation store carries the individual findings; this is the reasoning
> behind them.

An independent analysis of the recurring failure classes in planwright, written
against `origin/main` at `49a529e` (#417) on 2026-09-07.

---

## 0. Method, and one correction that changes the reading of everything below

**The primary checkout is nine commits behind `origin/main`.** `HEAD` is
`e69806c` (#400); `origin/main` is `49a529e` (#417). `HEAD` is a strict
ancestor, so this is lag, not divergence. It matters for two reasons:

1. Four of the merged PRs in the brief (#405, #407, #412, #417) are *not in the
   working tree*. Anything verified against the checkout will report them
   unfixed. My first sweep did exactly that and reported two already-fixed
   `test-fleet-worktree-track.sh` sites as live. Every finding below has been
   re-verified against `origin/main` content, and I say so where a claim
   survives only on a branch.
2. `specs/_observations/entries/` holds 347 fragments in the checkout and **377
   on `origin/main`**. The 30 missing ones are dated 2026-09-04 to 09-07 -- the
   densest, most on-theme part of the record, including both fragments the brief
   names by slug. A tower analysing its own two days from this checkout is
   analysing them with the last three days deleted.

Method: four parallel read-only sweeps (vacuous assertions; echo/dash plus dead
mechanisms; false comments; observations and git history), each finding
re-verified by me against `origin/main` before it appears here. Where I ran an
experiment (awk, shellcheck, `gh run view`) I say so.

---

## 1. Verdict on the seven classes

| # | Class | Verdict |
| --- | --- | --- |
| 1 | Guards and tests that cannot fail | **Confirmed, and understated.** 9 more live instances found, plus 2 guards that never run at all. |
| 2 | Comments asserting properties the code lacks | **Confirmed 3 of 4; the 4th is not reproducible.** 4 new demonstrably-false claims found, one of which is a live idempotency bug. |
| 3 | Load-sensitive failures dismissed as flaky | **Confirmed 6 of 7 as real bugs.** One (throttle) was a genuine retiming, honestly done. One (c12) conflates two distinct findings. |
| 4 | Fail-open on admission gates | **Confirmed as introduced, refuted as shipped.** All three were caught on-branch pre-squash. The real fail-open is one layer up and is still live. |
| 5 | `echo` re-expanding escapes under dash | **Confirmed. ~157-186 live call sites.** The guard is written, clean, and blocked on a PR title. |
| 6 | Mechanisms shipped correct and uninvoked | **Confirmed, and badly understated.** Not 2 scripts -- **18**, plus a 4-script subtree under a skill that does not exist. |
| 7 | Workers stalling on self-started background waits | **Confirmed by the repo's own record.** The mechanism that would detect it shipped dead (see class 6). |

### Corrections to the brief

**Class 5 -- PR #414 does not hang.** I pulled the job log
(`gh run view 34065191020`). The guard runs clean:

```text
[check:echo-safety] check-echo-safety: clean (137 files scanned, of which 6 allowlisted;
                    189 bash-interpreter files not at risk, 37 not shell)
[check:echo-safety] Finished in 5.51s
```

All 176 test files pass. Total job time 4m08s, well inside normal. The job fails
at the **last step**, on the PR-title lint:

```text
PR_TITLE: Guard against echoing sanitized text, and convert the call sites that did
check-commit-msgs: not conventional: Guard against echoing sanitized text, ...
##[error]Process completed with exit code 1
```

**Retitling the PR is the entire fix.** The single most valuable action
available from this whole analysis costs one word, and the guard for the most
frequently reintroduced bug class in the repo has been sitting behind it.

**Class 2, instance 4 -- the awk strnum claim is not reproducible.** The brief
says a corrected comment introduced a new false claim about awk strnum handling.
`scripts/fleet-attention.sh:632-637` claims "both the split labels and the
ENVIRON recommendation carry that attribute", and that is **true** -- verified by
running mawk 1.3.4: `split()` elements and `ENVIRON[]` elements do carry strnum,
so the string-forcing at `:641` is load-bearing, not redundant. I could not find
a false strnum claim in the surviving comments. What I did find is the inverse,
and it is worse: a place where the *absence* of that idiom is a live bug with a
comment asserting the property it breaks. See finding 2 in section 2.3.

**Class 4 -- the three fail-open bugs did not ship.** All three were introduced
and fixed on `planwright/model-allocation/task-6` before the squash. `origin/main`
carries the closed forms: `scripts/allocation-apply.sh:347` refuses a missing
`admit` row (`exit 5`), and `:355-360` uses a closed `case "$ADMIT" in yes |
withheld) ;; *) ... exit 5`. The class-4 story is a **review success**, not a
shipping failure -- but see 2.4 for why that is cold comfort.

**Class 1, the spec survey filtered to `remaining <= 2`** -- not verifiable. No
such filter exists in the tracked tree (`scripts/spec-status.sh` has no
`remaining` predicate). It was an ad-hoc interactive command, which is itself
the point: ad-hoc analysis commands are the one artifact class in this repo with
*no* review path at all, and one produced a materially wrong report ("all specs
complete") that a human acted on.

---

## 2. New instances

**31 new instances**, in three groups. Every one verified against `origin/main`
content.

### 2.1 Vacuous test assertions (9 new)

Shape key: **(A)** command substitution as a `case` word, discarding exit status;
**(B)** a grep that can error, with empty output read as clean; **(C)** no
negative control -- nothing proves the machinery was exercised; **(E)** a
type-specific residue predicate blind to other shapes; **(F)** an assertion an
empty result satisfies.

1. **`tests/test-allocation-adapt.sh:120` (stub) -- (C).** Four stub binaries
   (`claude curl wget gh`) are planted on `PATH` and append to `$tmp/invocations`.
   That path appears exactly twice in the file: the stub's own append, and an
   `rm -f` in `reset_state`. **Nothing ever reads it.** This is the exact shape
   of the `test-allocation-petition.sh` bug (#407), still live in a sibling
   suite. Five sibling suites do assert on the log; this one dropped it.
   *Fails to catch:* an LLM or network call inserted anywhere in the adaptation
   path -- the determinism floor the stubs exist to defend.

2. **`tests/test-allocation-clamps.sh:234` -- (C).**
   `[ ! -f "$tmp/invocations" ] || fail "1z: an outbound client was invoked"`.
   Stubs built at `:121`; no assertion anywhere in the file proves a stub is
   reachable. A bad `chmod`, a `run()` variant that forgets the `PATH` prefix, or
   a SUT resolving an absolute binary path all render this permanently green.

3. **`tests/test-fleet-credit-continuation.sh:144-145` -- (C).** Same shape, same
   file family. No positive control anywhere in the file.

4. **`tests/test-fleet-credit-continuation.sh:146-149` -- (F).**
   `rows=$(audit_query --mechanism credit-continuation)` then
   `case $rows in *"$esc"*) fail ...`. The query's exit status is discarded and
   `$rows` is never asserted non-empty. *The assertion is green on an empty audit
   trail* -- which is also the state a broken recorder produces. A second instance
   in the same block as the one the brief already names.

5. **`tests/test-fleet-throttle.sh:226-229` -- (F).** Identical shape.
   `audit_rows` never proven non-empty. Two sibling blocks ten lines below
   (`:236`, `:242`) do it correctly with a positive `*throttle*engage*) ;; *) fail`
   branch, so the right pattern is already in the file.

6. **`tests/test-fleet-throttle.sh:468` -- (B).**
   `grep -q "$esc" "$fleet_home"/audit/audit-*.tsv 2>/dev/null`. With no matching
   file and no `nullglob`, the literal `audit-*.tsv` reaches grep, which exits 2
   with its diagnostic swallowed -- read as "clean". *Fails to catch:* an escape
   byte in the durable store the moment the audit filename convention changes.
   Permanently-green-on-refactor.

7. **`tests/test-orchestrate-select-v2-hygiene.sh:259-262` -- (F).** The exit
   status is checked; the content is not. **An empty critical path satisfies the
   assertion perfectly**, and an empty critical path is the most likely way a
   fence-handling bug manifests. The non-critical-path sibling one line above
   *does* pin `[ "$got" = 1 ]`.

8. **`tests/test-allocation-ledger.sh:326` -- (E).**
   `[ -L "$lock_file" ] && fail "8f: the owner's unlock did not release the lock"`.
   `-L` sees only a symlink. Section 8h, twenty lines later in the same file,
   documents that a plain file squatting the lock path is **unclearable by
   definition** ("the stale break only ever claims a SYMLINK"). The assertion is
   blind to the one residue its own file calls catastrophic. `[ ! -e ]` is the
   correct predicate -- the same fix `a6d9781` applied to `fleet-state.sh`.

9. **`tests/test-allocation-docs.sh:496-511` -- (C).** This one deserves its own
   paragraph. It is the doc-rot tether that PR #417 *fixed* for the stray-`--`
   bug. Its `live_refs()` helper still has no positive control: nothing proves
   the search roots or the pattern can ever match. It is currently in its
   always-pass state by design, and if `$root/scripts` were wrong it would report
   "no callers" forever. **A new instance of the class, on the PR that fixed the
   previous instance of the class.** The same PR needed *two* fix commits
   (`3355b11`, `a6a6fa3`) both titled "make ... able to fail".

**Borderline, listed for completeness, not counted:** `test-fleet-usage-gate.sh:153`,
`test-fleet-tower-signpost.sh:138`, `test-fleet-presence.sh:910-912`,
`test-fleet-throttle.sh:222-224`, `test-orchestrate-lock.sh:122/136/150/164`,
`test-fleet-fence.sh` (7 sites). Each has adjacent positive assertions that
partially cover it.

### 2.2 Guards that exist, are tested, and never run (2 new -- a distinct sub-class)

I audited every `scripts/check-*.sh` against `mise.toml`, `.github/workflows/`,
`lefthook.yml` and `githooks/`. Twenty-one guards; nineteen wired; **two wired
nowhere at all**:

- **`scripts/check-confirmation.sh`** -- and `doctrine/interaction-style.md:179`
  states the rule "is machine-checkable by `scripts/check-confirmation.sh`".
  That sentence is false. The guard has a passing test suite
  (`tests/test-check-confirmation.sh`), so every signal a reviewer sees says it
  is alive.
- **`scripts/check-backend-capability-drift.sh`** -- guard-coverage Task 9's
  three-way tether between `doctrine/backend-capability-contract.md`,
  `orchestrate-backends.sh caps_for()` and `docs/fleet.md`. Also fully tested,
  also never invoked.

This is class 1 and class 6 fused, at the guard layer. A guard with a green test
suite and no caller is *the* maximally deceptive artifact in this repo: every
proxy for health is positive.

### 2.3 Comments asserting properties the code does not have (4 new)

1. **`scripts/allocation-ledger.sh:706-709`** -- "This verb answers 'the last tier
   a launch used', **so only launch rows may answer it**." The awk immediately
   below excludes exactly one event (`feedback`) and tests neither the event nor
   the scope column. Every `record` call site in `allocation-adapt.sh` for
   `step-failure`, `retry`, `flailing`, `non-convergence`,
   `petition-escalate/-de-escalate` writes real tiers into `$11`/`$12` and
   satisfies the pattern. So an escalation row answers `last-tier` -- precisely
   the harm the comment says it prevents. Unmerged commit `0c635b9` confirms
   independently: "a unit whose escalation the clamps had just refused would then
   come back running at exactly the tier it was refused." Repeated at `:104-107`.

2. **`scripts/allocation-adapt.sh:145` + `incident_seen` (`:452-464`)** -- the
   header states "The idempotency key is (unit, step, attempt, incident)". The
   awk compares with a bare `$4 == st && $5 == at` under `-v`, with no
   string-forcing, unlike every sibling reader in the repo
   (`fleet-attention.sh:392`, `fleet-liveness.sh:395-396`,
   `fleet-pane-detect.sh:186-188`). **I ran this:**

   ```text
   printf 'a\tb\tu\t01\t0\tx\n' | awk -F'\t' -v st=1 -v at=0 '$4==st && $5==at{print "MATCHED"}'
   -> MATCHED
   printf 'a\tb\tu\t1.0\t0\tx\n' | awk -F'\t' -v st=1 '$4==st{print "MATCHED"}'
   -> MATCHED
   ```

   The step grammar (`:631`, `:647`) admits `[A-Za-z0-9._=@:-]`, so `1`, `01`,
   `1.0`, `1e0` are all legal *distinct* steps that key the same incident, and a
   genuine escalation is silently skipped as a replay. **This is a live bug, not
   just a false comment.** Tellingly, the author closed this exact hazard for
   `attempt` two lines later (`:546-548`) and left `step` open.

3. **`scripts/allocation-ledger.sh:77-78` (repeated `:171-172`)** -- "the whole row
   well under PIPE_BUF, so even the lockless read path can never observe a
   half-written row." `PIPE_BUF` is a POSIX atomicity guarantee for pipes and
   FIFOs. The store is a regular file (`<dir>/<unit>.tsv`, `:657-661`). POSIX
   gives no atomicity guarantee for `write()` to a regular file, and none over
   NFS. **A category error presented as a proof** -- and contradicted inside the
   same file: `:80-81` says `health` reports "a torn or short row", `:698` says
   "a torn row is skipped rather than trusted", and every reader guards with
   `NF == 15`. Those defences would be dead code if the claim held.

4. **`scripts/orchestrate-lock.sh:6-16`** -- two false claims in one header.
   (a) "mutually exclude **by construction**": the acquire is a non-atomic
   check-then-`rm -rf`-then-`mkdir` at `:145-149`, and `scripts/fleet-state.sh:417-421`
   names *this file* as sharing the defect ("if 2 or more towers race the break of
   the SAME genuinely-stale lock ... both mkdir-succeed -- two holders").
   `orchestrate-lock.sh` carries no such caveat, and `release` at `:100-103` is an
   unconditional `rmdir` with no owner check. (b) "a lock holder writes no
   authoritative state (D-1)": `tasks-pr-sync.sh:701-705` rewrites the `**Status:**`
   header in all four spec files under the held lock, and
   `migrate-format-version.sh:493-496` rewrites the whole bundle.
   `doctrine/orchestration-concurrency.md:13-21` exempts only the `tasks.md`
   sections as derived state.

**Not reproducible as claimed:** a `githooks/commit-msg:44` untrusted-echo
finding one sweep reported. The `case` arm constrains the subject to
`squash!`/`fixup!`/`amend!`, so `${subject%%!*}` can only expand to one of three
literals. Reported here because I asked for it to be checked and it did not hold.

### 2.4 Dead mechanisms (16 new, plus a 4-script orphan subtree)

The brief names two. There are **eighteen** scripts with no caller anywhere in
`scripts/`, `skills/`, `hooks/`, `githooks/`, `config/`, `.github/`, `mise.toml`
or `lefthook.yml` -- referenced only by their own tests and by prose. I verified
each on `origin/main`. The ones that matter most:

| Script | What it was for |
| --- | --- |
| `fleet-fence.sh` | "At dispatch, BEFORE any worker forks, the tower fences the unit." **The dispatch path never fences.** |
| `fleet-stuck-detector.sh` | The four-state worker classifier -- merged as #400, the checkout's own HEAD. **The mechanism for class 7 shipped dead on arrival.** |
| `fleet-allocate.sh` | The budget-aware allocation layer. `skills/orchestrate/SKILL.md:227` calls `allocation-adapt.sh resolve` instead -- bypassed by its own successor. |
| `fleet-decision.sh` | The answer + delivery half of the worker-to-tower decision channel. |
| `fleet-attention-watch.sh` | The tower-side attention-store event watch. The tower never invokes it. |
| `orchestrate-degrade.sh` | The degradation ladder and runtime failover. |
| `orchestrate-meta-select.sh` | The selector for `/orchestrate --meta`. |
| `context-budget-peer.sh` | The peer-pane corroborator; its sibling monitor *is* skill-wired. |
| `fleet-credit-continuation.sh` | The rate-limit-wall responder. |
| `rubric-grade.sh`, `rubric-self-audit.sh` | The independent grader and self-audit; `behavioral-eval.sh --grader` is never given one. |
| `release-checklist.sh` | The private-to-public release readiness gate. |
| `inception-scaffold.sh` | Header says "`/inception` calls this". **There is no `/inception` skill.** It is the sole caller of `inception-render.sh`, `inception-validate.sh` and `inception-secret-screen.sh`, so all four are dead. |

(Legitimately caller-less by design, excluded from the count: `fleet-sweep.sh`,
`fleet-cleanup.sh`, `fleet-tower-watchdog.sh`, `fleet-statusline.sh`,
`main-currency.sh`, `install.sh`, the two command guards, `anchor-sweep.sh`, and
the two migrations -- each has documented human or hook wiring.)

**And the sharpest thing in this section.** `tests/test-allocation-docs.sh:504-511`
now *guards the deadness*: it fails if anything wires `allocation-feedback.sh`
without editing `docs/allocation.md`. The repo took an unfinished integration and
converted it into a protected invariant. The comment above it is honest about
why -- "the options reference already rotted this exact way once" -- but the
effect is that the pipeline's response to a dead mechanism was to make the
deadness load-bearing.

---

## 3. The mechanism

Nine forces, in rough order of explanatory power. Taxonomy is not the point; each
of these predicts the classes rather than restating them.

### 3.1 The verification layer and the thing verified are the same substance

Everything here is POSIX shell doing text processing. The guards are shell
scripts that grep shell scripts. The tests are shell scripts. So a defect in
shell semantics -- a masked exit status, empty output reading as clean -- lands
identically in the product, in the guard, and in the test *of* the guard, and a
guard written in the idiom of the bug cannot see it. This is why class 1
recurred at the guard layer (#415's originating-repository clause satisfied by a
comment) as readily as at the test layer, and why the echo guard itself needed
seven fix commits.

### 3.2 The repo's dominant assertion shape is the one that fails open

Look at what these guards actually assert: no escape byte, no leaked lock, no
caller, no ledger free text, no fenced task on the path, no `pull_request_target`,
no purged identifier, no eval in CI, no `cd` without `unset CDPATH`. The
architecture is **absence-shaped**. And absence assertions are precisely the ones
any failure satisfies: anything that yields empty output reads as compliant.

The repo *knows* this. The string `vacuous` appears 73 times across ~30 files,
and the fail-closed reasoning in `check-purged-identifiers.sh`,
`check-no-ci-evals.sh`, `check-cdpath.sh` and `check-workflow-posture.sh` is
genuinely excellent -- "a guard that cannot read its seeds fails closed rather
than passing vacuously." **The doctrine is asymmetric.** It was applied to the
guards and never to the tests of the guards. Zero test files reason about their
own vacuity. All the confirmed instances live on the side the doctrine does not
cover.

### 3.3 The language's safety net is off exactly where the class lives

`set -e` never fires for a command inside `$( )` used as a `case` word, inside
`[ ]`, or on the left of `&&`/`||`. That is the location of **every one** of the
confirmed findings. `set -o pipefail` appears in exactly one of 175 test files
(`test-release-please.sh`), so every `cmd | grep ...` in the suite discards the
left-hand status -- which is what makes shape (B) invisible by construction.

And the linter the repo already pins does not close it. I tested this:

```text
$ cat sc.sh
case $(false) in
  *X*) echo bad ;;
esac
[ "$(false)" = "" ] && echo y

$ shellcheck -o all sc.sh
sc.sh:2:1: note: Consider adding a default *) case ... [SC2249]
sc.sh:6:6: note: Consider invoking this command separately to avoid masking
                 its return value ... [SC2312]
```

**SC2312 does not fire on the `case` word.** The one optional check everyone
would reach for is blind to the dominant shape. SC2249 (`add-default-case`) *is*
the right detector -- a fail-on-match-only `case` with no `*)` arm is exactly the
vacuous absence assertion -- and it is not enabled. There is no `.shellcheckrc` in
the repo. Enabling SC2249 blanket is impractical today (108 hits in `tests/`, 442
in `scripts/`), which is why 4.3 proposes the narrow rule instead.

Coverage gap while we are here: `lint:shell` runs on `scripts/*.sh tests/*.sh
tests/lib/*.sh githooks/*`. Shell embedded in `mise.toml` run bodies, in
`skills/**/*.md`, and in heredoc-generated scripts is linted by nothing.

### 3.4 There is no seam to put a house rule in

All 175 test files define their own `fail()` inline. There is no shared assertion
library, so there is nowhere to encode "an absence assertion must take the
producing command, not its output". The one place the repo *did* build a seam --
`tests/lib/ready-guard-harness.sh`, whose `gh` stub records argv to
`$STATE/argv.log` and whose `assert_gh_calls` lets a fixture prove the stubbed
call site was traversed **before** asserting a negative -- is exactly the pattern
every one of the (C) findings is missing. It works. It is used by two suites.

### 3.5 Review is diff-shaped, and a vacuous assertion reads correct

Neither `/self-review` nor `/polish` runs the test suite or a linter; I grepped
both SKILL files for `mise run`, `shellcheck`, or any suite invocation and found
none. Their evidence base is *reading*. And reading is the one method that cannot
distinguish a vacuous assertion from a real one: `case $(cat "$tmp/err") in
*"$esc"*) fail "a raw escape byte reached stderr"` reads as impeccable English,
and it is green either way. The only way to tell is to break the thing and watch
it go red.

Nothing does that. `doctrine/discovery-rigor.md:43-44`, lens 8, reads "Tests /
verification (coverage of new behavior, missing failing-case tests, brittle
assertions)" -- it asks whether a test **exists**, never whether it **can fail**.
`doctrine/validation-rigor.md` pass 1 requires reproduction, but of a *finding*
about the product; there is no counterpart for a claim made by the verification
layer. The whole rigor apparatus is pointed one way.

`/execute-task`'s test-first loop is the one place the discipline exists -- step 2
requires confirming the test "fails for the right reason", and it is a listed
hard stop condition (`skills/execute-task/SKILL.md:216-219`, `:425`). Two things
defeat it. It is scoped to "every piece of new behavior", which in practice means
the file, not each assertion -- a vacuous sub-assertion added beside assertions
that do go red sails straight through. And **it leaves no artifact**: nothing in
the commit, the PR, or CI records that a red was ever observed. In a repo where
every REQ is pinned to a verification path in `test-spec.md`, the test-first red
step is the single load-bearing step with no verification path of its own. A
reviewer cannot check it; an agent under pressure can skip it silently and
nothing notices.

### 3.6 Green is the reward signal, and vacuity is the cheapest path to it

`/execute-task` converges on CI green. A vacuous assertion is the locally
cheapest way to reach green while still producing an artifact that looks like
diligence. Nothing anywhere measures assertion strength, so there is no
counter-pressure. This is not carelessness -- it is selection, and it predicts
that the class gets *more* frequent as autonomy increases and as more assertions
are added per unit of behavior. The record bears that out: the highest-density
occurrence is on the PRs that were themselves fixing the class.

The same force explains class 5's most damning detail. Two workers reintroduced
the dash-echo bug **after being explicitly warned about it in their briefs**.
That is the clearest possible evidence that instruction-level warnings do not
work against a mechanical class. Only a mechanical guard does. The guard exists,
runs clean in 5.5 seconds, and is blocked on a PR title.

### 3.7 The spec pipeline decomposes by artifact, not by reaching a live path

A task's `Done when:` is satisfied by "the script exists and its tests pass".
Call-site wiring is a different task, frequently in a different spec, frequently
owned by nobody. The repo's own record says this in as many words:
`2026-09-02-allocation-feedback-callsite-7c8e69ca.md` states that Task 4 delivers
the script but "no task in the bundle owns the TERMINAL-STATE call sites that
would invoke it". So the pipeline structurally produces orphans, and it produced
eighteen.

Class 7 is where this and class 6 collide with the most cost. The record
(`2026-09-06-worker-waiting-looks-like-working-8a99fb7d.md`) is precise: "liveness
checks answer 'is the process alive', not 'is the process advancing' ... a spinner
turns identically whether the worker is progressing or blocked on a condition
that will never fire." It even names the candidate signal -- byte-identical
successive reports. The mechanism that would classify this,
`fleet-stuck-detector.sh`, merged four days ago with zero callers.

### 3.8 The observation loop records everything and changes nothing

This is the force behind the *recurrence*, as distinct from the occurrence.

- `origin/main` holds **377 fragments in `entries/` against 101 in `archive/`**.
  Of the 65 fragments from 2026-09-01 to 09-07, two have been consumed.
- `scripts/obs-consume.sh` -- the archiver -- has **no script caller anywhere**.
  Its only invocation path is a human running `/spec-draft`.
- `scripts/drain-gates.sh:956-990` emits one line: an unmined count and an
  oldest-entry age. It reads no fragment content, evaluates no theme, opens no
  issue, creates no guard.

So the store is write-mostly. And the consequence is not abstract. The lock
defect was **measured** on 2026-08-26 (`0087f433`: 13 interleaved critical
sections under mkdir, 0 under `ln -s`), the fragment named the exact fix, noted
that `fleet-state.sh` still had it, and was left. It was then independently
re-discovered by five different workers over four days
(`35c48c71` to `4c6a31ee` to `8c04c8ac`), each ruling out its own branch, the
verdict strengthening from "load-sensitive flake" to "deterministic in isolation,
19/18/18 of 20". The fix (`ca53e6c`, PR #409) is still open;
`origin/main:scripts/fleet-state.sh:403` is still `mkdir`.

Class 3's "flaky" prior is the same force in miniature. Six of seven were real.
The prior is imported from ecosystems where tests are flaky for infrastructural
reasons; here the tests are deterministic file and process manipulation and the
concurrency is real, so a load-sensitive failure is a race until proven
otherwise. The one fragment that read a failure as "load-sensitive rather than a
real regression" (`286d53ee`) was later refuted by `f02d1e05`.

One detail earns a line of its own, because it is the mechanism eating its own
tail: the `worker-waiting-looks-like-working` fragment closes by noting that
"the first attempt to write this fragment was itself mangled by unquoted
backticks reaching a shell, which ate two words silently -- the same escaping
family as the dash-echo hazard recorded separately."

### 3.9 Why class 2 is more dangerous than its count

Comments are the only artifact in this repo with no verification path, in a repo
whose entire discipline is verification paths. A search for "header comment",
"code comment", "comment claim" or "stale comment" across `scripts/`, `doctrine/`
and `skills/` returns zero. `doctrine/validation-rigor.md:119-127` explicitly
*downgrades* comment changes to "substitute review angles ... record why no test
was added." Lens 7 names "docstrings, READMEs, specs, ADRs, config docs,
doctrine" -- shell header comments are not in the list.

And the harm compounds, because in this repo comments are load-bearing *for
review*. A reviewer who reads "a clobber cannot happen because the owner token
crosses the boundary" will not re-derive it. A false safety comment does not
merely fail to help; it **actively disables review of that spot**, and it does so
most reliably at the spots that most need reviewing, because that is where people
write safety comments.
`2026-09-03-comment-volume-manufactures-review-work-a81cee76.md` measures the
other edge of the same problem: 20,807 comment lines against 33,843 code lines in
`scripts/`, 30% of comments in blocks of 25 lines or more, largest header 252
lines. Every prose claim is an untested assertion that the Discovery-Rigor lens
will hunt forever.

---

## 4. What is missing, prioritised

Each item names what it would have caught.

### 4.1 P0 -- Retitle PR #414. Cost: one word

`Guard against echoing sanitized text...` becomes `feat(scripts): guard against
echoing sanitized text`. The guard runs clean; all tests pass; the only failing
check is the PR-title conventional-commit lint.

*Catches:* class 5, all 5+ instances, permanently. This is the highest
value-per-unit-effort action available and it is not close.

Two riders, since the guard should merge with its limits understood. Its
allowlist exempts the six highest-density offenders (`allocation-adapt.sh`,
`allocation-ledger.sh`, `allocation-select.sh`, `fleet-attention.sh`,
`fleet-liveness.sh`, `offload-dispatch.sh`) rather than fixing them -- fine as a
ratchet, but the ~157 sites are still live behind it. And it is a
*sanitizer-consistency* check, not a taint tracker: it cannot see helper-function
indirection (`err "$(sanitize_printable "$x")"` where `err()` does `echo "$1"` --
live at `scripts/prompt-eval.sh:97`), two-hop variables, heredoc-generated
scripts, or any untrusted value that never met a sanitizer at all.

### 4.2 P0b -- Move the PR-title lint to the front of the CI job

It currently runs **after** the 228-second test suite, so a title typo costs a
full cycle and produces a `FAILURE` with no visible cause in the task summaries.
It should run first and be available locally (`lint:pr-title`) -- `lint:commits`
lints commit subjects, not the PR title, so there is no local way to catch this.

*Catches:* the specific 4-minute-late failure that has kept the echo guard
unmerged, and the general "CI red for a reason unrelated to the change" noise
that trains reviewers to discount red.

### 4.3 P1 -- `check:test-falsifiability`, a `check:*` guard in the house style

A guard over `tests/` in the same shape as `check-cdpath.sh` (enumerate by
shebang or suffix, fail closed on anything that would narrow the scan). Rules, in
descending confidence:

1. **Error:** a command substitution as a `case` word (`case $(...) in`) inside
   `tests/`. The sanctioned form is already house-approved and in-tree -- #405's
   fix: `listing=$(wt list) || fail "list failed (exit $?)..."` then `case
   $listing in`.
2. **Error:** a `case` block in `tests/` whose arms all call `fail` with no `*)`
   catch-all. (This is SC2249's rule; implementing it narrowly avoids the 550
   repo-wide hits that make a blanket enable impractical.)
3. **Error:** a PATH-stub log file that is written but never read by an
   assertion in the same file.
4. **Warn:** `[ ! -L ]` / `[ ! -f ]` / `[ ! -d ]` used as a residue assertion
   without a paired `! -e`.
5. **Warn:** a `grep` inside an emptiness assertion whose exit status is
   unchecked, or an unquoted glob passed to `grep` with `2>/dev/null`.

*Catches:* rules 1-2 catch the brief's `test-fleet-worktree-track.sh`,
`test-fleet-credit-continuation.sh`, `test-allocation-feedback.sh:317`, and new
findings 4, 5, 7. Rule 3 catches `test-allocation-petition.sh` and new findings
1, 2, 3, 9. Rule 4 catches `fleet-state.sh`'s lock leak (#409) and new finding 8.
Rule 5 catches new finding 6 and the `test-allocation-docs.sh` stray-`--` bug
(#417). That is **essentially all of class 1**, in one guard.

Add a `.shellcheckrc` at the same time enabling `check-extra-masked-returns` for
`tests/` only if the 2,871 hits can be triaged; if not, skip it -- rule 1 covers
the shape SC2312 misses anyway.

### 4.4 P2 -- A shared assertion library, so the convention has a seam

`tests/lib/assert.sh` providing `refute_output_contains <cmd...> <pattern>`,
`assert_absent <path>`, `assert_stub_reached <log>`, `assert_nonempty`. The key
property: the negative assertions take **the producing command**, not its output,
so the exit status cannot be discarded by construction. Then a guard rule
flagging a new inline `fail()` redefinition in `tests/`.

`tests/lib/ready-guard-harness.sh` already proves the design works
(`assert_gh_calls` proving the stubbed call site was traversed before asserting a
negative). This generalises it from two suites to 175.

*Catches:* all of class 1 prospectively rather than retroactively, and -- unlike
4.3 -- the shapes a regex guard cannot see.

### 4.5 P3 -- `check:script-reachability` and `check:guard-wiring`

Two guards, one trivial and one moderate.

- **`check:guard-wiring`** (~20 lines): every `scripts/check-*.sh` must appear in
  the `check` aggregate in `mise.toml` or in a CI workflow. *Catches:*
  `check-confirmation.sh` and `check-backend-capability-drift.sh`, today.
- **`check:script-reachability`**: every `scripts/*.sh` must have a caller in
  `scripts/`, `skills/`, `hooks/`, `mise.toml` or `.github/`, **or** an entry in
  a tracked allowlist naming its human or cron entry point (which the ten
  legitimately caller-less scripts already have documented in `docs/fleet.md` and
  `docs/per-tower-checkouts.md` -- the allowlist just makes that machine-visible).
  *Catches:* all 18 dead mechanisms, including `fleet-stuck-detector.sh` on the
  day it merged, `fleet-fence.sh`, and the `/inception` orphan subtree.

Pair it with a `Done when:` convention change: a unit that ships a new executable
is not done until a caller exists or the allowlist entry names who will call it.
That is the doctrine fix for 3.7; the guard is what makes it stick.

### 4.6 P4 -- A demonstrated-red requirement, with an artifact

The doctrine change that closes 3.5. Two parts:

- **Lens 8 gets a second question.** Not only "does a test exist for this
  behavior" but "**can each new negative assertion fail?**" -- with a required
  answer of one of: (a) a positive control in the same test proving the machinery
  ran, (b) a recorded mutation ("I broke X, the assertion went red"), or (c) an
  explicit note why neither applies.
- **The red gets written down.** `/execute-task`'s test-first step 2 already
  requires observing the red; it should record it, one line per new assertion, in
  the PR body. That converts the repo's only unverifiable step into a reviewable
  artifact at near-zero cost.

*Catches:* every class-1 instance, including the ones a regex guard cannot see --
finding 7 (an empty critical path satisfying the assertion) is invisible to any
syntactic rule and instantly obvious to a mutation.

### 4.7 P5 -- A load policy and a stress mode

- **Doctrine line:** a load-sensitive test failure is a real defect until a race
  has been positively excluded. "Flaky" is a conclusion, never a starting
  hypothesis, and it requires evidence in the same shape as any other finding.
- **`test:stress`:** run one named test file N times at high parallelism.
  `run-tests.sh` already has `PLANWRIGHT_TEST_JOBS`; this is a thin wrapper. The
  fragments show workers hand-rolling this repeatedly (20 concurrent
  `bound-incr`, 16 concurrent runs, 24 workers on 12 cores), so the demand is
  demonstrated.
- **Maintain the known-load-sensitive list as data, not lore.**
  `2026-09-06-fleet-bound-incr-overcount-876398c1.md` makes the point exactly:
  case 9 is *not* on the list, so it reads to every worker as a real defect in
  whatever branch happens to be under test -- which burns a worker per encounter.

*Catches:* class 3, 6 of 7. Specifically the registry lost-write race, which has
now been independently rediscovered five times over four days.

### 4.8 P6 -- Close the observation loop, or stop pretending it is closed

Currently 377 unmined against 101 archived, with no automated path from a
fragment to anything. Cheapest useful change: `/drain` should surface not just a
count and an age, but a **recurrence cluster** -- fragments sharing a theme, with
the count and the age of the oldest. Five independent rediscoveries of one lock
defect would have surfaced as one loud row instead of five quiet ones.

Stronger version: a fragment that names a specific file and a specific defect
should be able to carry a machine-readable `Guard:` line proposing the check, and
`/drain` should list proposed-but-unwritten guards as its top section.

*Catches:* the recurrence of classes 3 and 6. It is the difference between a repo
that finds the same bug five times and one that finds it once.

### 4.9 P7 -- Narrow the comment problem rather than trying to solve it

Comment truth cannot be checked mechanically in general. Two things can be:

- **A guard flagging absolute-impossibility phrases** ("cannot happen", "can
  never", "by construction", "no race", "guaranteed", "atomic") in `scripts/`
  that do not cite a test. Not proof -- a review trigger. It converts the
  highest-risk comment shape into a thing that must be justified once.
- **A doctrine rule:** a safety claim about *cross-process* behavior must name
  the test that demonstrates it, or state the limitation instead. All four new
  class-2 findings are cross-process claims (lock exclusion, write atomicity,
  ledger row provenance, idempotency keying), and the pattern is exact: the
  comment describes the intended design, the code implements a weaker thing, and
  nothing rechecks the prose when the code moves.

`scripts/fleet-state.sh:417-423` is the model to copy. It states its known
limitation plainly instead of claiming safety. That posture, not more comments,
is the fix.

---

## 5. Leverage ranking

**Do first, today: retitle PR #414.** One word, unblocks a whole class. Then
move the PR-title lint to the front of CI so the next one costs 5 seconds instead
of 4 minutes.

**The single highest-leverage structural change: make a demonstrated red the
price of a new negative assertion -- mechanized where possible (4.3), seamed
where not (4.4), and required as an artifact where neither reaches (4.6).**

The argument for it over the alternatives:

- Class 1 is the largest class by count (8 in the brief, 9 more here, plus 2
  unwired guards), and it is the class that **hides the others**. A vacuous
  assertion is why a dead mechanism looks alive, why a false comment survives a
  review pass, and why a real race reads as a flake. Fixing class 1 raises the
  signal quality of every other detector in the repo.
- It attacks the actual generating force (3.6) rather than an instance. Guards
  and briefs both lose to gradient descent toward green; a requirement that green
  be *earned* by a demonstrated red changes what "cheapest path to green" means.
- It is the only proposal that scales to the shapes no regex can catch. Finding 7
  -- an empty critical path satisfying the assertion -- is syntactically flawless
  and instantly obvious to a mutation.
- The pattern already exists in-tree and works (`assert_gh_calls`), so this is
  generalising a proven local solution, not importing a new framework.

**Runner-up, and much cheaper: `check:script-reachability` + `check:guard-wiring`
(4.5).** It catches 20 instances for a day of work and would have caught
`fleet-stuck-detector.sh` on its merge day -- the mechanism for class 7, dead on
arrival.

**What I would not prioritise:** more doctrine prose. The repo already has
excellent, correct doctrine about vacuity -- it was simply never pointed at the
tests. And `a81cee76` measures the cost of prose volume directly: 30 commits to
change 42 insertions of doctrine text. The gap is not knowledge; it is that the
knowledge has no enforcement surface.

---

## 6. What I could not verify

- **The `remaining <= 2` spec survey.** No such filter exists in the tracked
  tree. It was ad-hoc and left no artifact, so I have only the tower's account.
- **The awk strnum "new false claim".** Not reproducible. The surviving strnum
  comment at `fleet-attention.sh:632-637` is *correct* under mawk 1.3.4, and
  POSIX agrees that `split()` and `ENVIRON[]` elements carry strnum. The claim
  may refer to a comment on an unmerged branch I did not locate, or it may be a
  misrecollection. What I did verify is the inverse bug at `allocation-adapt.sh`
  `incident_seen`, which is real and live.
- **Whether the usage gate has *never* admitted by refusal.** I read the path
  (`derive_rung` reports both windows `unavailable` with no cache; unavailable
  decays to `normal`; `normal` admits everything) and the fragment asserts it
  empirically, but I did not execute the gate.
- **Exactly how much of the two days went into repairing the verification
  layer.** A history sweep counted ~34 such commits against 135 no-merge commits
  since 09-04 (~25%), but the boundary between "guard" and "product" is arguable
  -- the echo-safety guard's seven commits could be counted either way. What is
  not arguable: **all four open PRs at the end of the window (#414, #415, #416,
  #418) exist solely to repair tests and guards**, and two of them (#416, #418)
  fix the two specific sites that fragment `6108e668` had already predicted.
- **The borderline vacuous assertions in 2.1.** I judged them weaker because
  adjacent positive assertions partially cover them; a mutation run would settle
  each in seconds and I did not run one.
- **The dead-mechanism list's intent.** I verified the absence of callers
  mechanically. Whether each was *meant* to have one comes from script headers
  and spec citations, which is the authors' stated intent, not proof.
- **The 157 vs 186 echo call-site counts.** Two sweeps produced different totals
  from different inclusion rules (bash-shebang exclusion, variable-form
  detection). Both are large; neither is exact.

---

## Appendix: the compressed evidence trail

- Checkout `e69806c`, `origin/main` `49a529e`, 9 commits behind, `HEAD` an
  ancestor.
- Guard surface: 21 `scripts/check-*.sh`, 18 wired as `check:*` tasks, 19 wired
  anywhere, **2 wired nowhere**.
- Test surface: 175 files, 176 in the runner, each with its own inline `fail()`;
  `pipefail` set in 1.
- `shellcheck` 0.11.0 pinned; no `.shellcheckrc`; SC2249 108 hits in `tests/`,
  442 in `scripts/`; SC2312 2,871 hits in `tests/` and blind to the `case` word.
- Observations: 377 unmined / 101 archived; `obs-consume.sh` has no script
  caller; `drain-gates.sh` emits a count and an age.
- PR #414 CI: `check:echo-safety` clean in 5.51s, 176/176 tests pass, job fails
  on the PR-title lint at 4m08s.
- PR #415 needed three successive fix commits to the same guard
  (`1e00f80`, `33479d1`, `5a316d5`), each titled some variant of "make it a
  real gate" / "fail for their own reason" / "judge only live content".
- PR #417 needed two (`3355b11`, `a6a6fa3`), both titled "make ... able to fail".
