# Worker Permission Ergonomics — Test Spec

**Status:** Draft
**Last reviewed:** 2026-10-10
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: the hook's behavior is verified almost entirely by `[test]`
(the adversarial suite `tests/test-worker-command-guard.sh`, run under
`mise run test` in CI), backed by `[design-level]` for the tool-grounded
quality guards and `[manual]` for the end-to-end dispatch confirmation that no
prompt-flood occurs under the wired profile. The security-critical target is
ZERO false-allows; the suite is the primary evidence.

The 2026-10-05 extension keeps that mix and adds two evidence sources: the
sanitized real-prompt corpus (REQ-H1.3), which every guard task enforces for
its own classes, and floor rows that must defer under every policy value. Its
doctrine and documentation REQs are `[design-level]`; the meta-tower and
relaunch changes add `[manual]` end-to-end confirmations alongside their tests.

## REQ-A — The auto-approve hook

### REQ-A1.1 — Auto-approve known-safe shapes, no LLM in path [test + design-level]

Suite fixtures assert `permissionDecision: allow` for representative known-safe
commands and defer for the rest. `[design-level]`: the hook is pure shell + `jq`
with no network or model call — reviewable by reading the script; no LLM
invocation exists in the decision path.

### REQ-A1.2 — Allow-only, never deny/ask [test]

Suite asserts the hook's stdout is either a well-formed `allow` decision or
empty (defer, exit 0); no fixture ever produces a `deny` or `ask` decision.

### REQ-A1.3 — Allow cannot override deny/ask; deny block verbatim [test + design-level]

`[test]`: a fixture with a deny-listed command (e.g. `git push --force`) is not
auto-approved by the hook (it defers, leaving the `deny` rule to fire). Plus the
deny-precedence **collision** fixture (REQ-B1.6): a command matching BOTH the
known-safe set AND a rule in the actual `config/worker-settings.json` `deny`
block, asserted not auto-approved — the case that actually exercises precedence,
derived from the real `deny` block so a future overlapping deny entry is caught.
`[design-level]`: Claude Code's documented `deny`→`ask`→`allow` precedence means
a hook `allow` cannot un-block a denied command; the wiring test (REQ-C1.1)
asserts the `deny` block is byte-for-byte unchanged.

### REQ-A1.11 — Never allow a deny-matched command, asserted as an outcome [test]

Supersedes REQ-A1.3's entry. Fixtures derived from the actual `deny` block of
`config/worker-settings.json`: for every `Bash(…)` deny rule, a generated
command matching it never receives `allow`, under every self-approval policy
value and for every approval category (a deny-matching declared command step
included). The generated rows read the deny block at test time, so a future
deny entry is covered without editing the fixture list; a curated collision
row (a command the known-safe set or an arm would otherwise approve) is added
for every rule whose verb is otherwise approvable, and the suite fails when
such a rule lacks one. The `deny` block differs from its pre-change content
only by the `Write`/`Edit` path rules REQ-F1.6 and REQ-G1.8 add.

### REQ-A1.4 — Every-segment-safe compound analysis [test]

Fixtures cover compound commands split on `;`, `&&`, `||`, `|`, `&`, and
newlines: a compound where all segments are safe allows; one where any segment
is unsafe defers (regression: `echo ok; rm -rf x` MUST defer). Ambiguity
fixtures — unbalanced quotes, `$(…)`/backtick/`<(…)`/`>(…)` substitution, a
non-`/dev/null` write-redirect, an unknown verb — all defer. Redirect fixtures:
`>&file`, `>|`, `&>`, `>>`, and a leading redirect (`>f cat x`) all defer;
**positive** fd-dup fixtures (`cat x >/dev/null 2>&1`, `cmd >&2`, `cmd 2>&-`) must
still ALLOW (the fd-dup carve-out does not over-defer the `>/dev/null 2>&1`
idiom — regression guard).

### REQ-A1.12 — Run-order every-segment analysis with the narrow substitution rule [test]

Supersedes REQ-A1.4's entry, which it keeps in full under the empty policy
(every compound, ambiguity, redirect, and fd-dup fixture still applies there;
under an enabled arm, a segment that arm admits follows REQ-F, and a `$(…)`
REQ-E1.3 admits follows REQ-E1.3) and extends: state carried across `&&`
only, except that a plain assignment also carries across `;` and `||`
(`cd <own worktree> && grep -n x f`, `f=README.md; grep -n x $f`, and
`f=README.md || grep -n x $f` allow; `x=-delete; find . $x` defers because
the carried value meets the `find` screen; `cd /tmp && ls`,
`cd missing; rm -r ../x`, `cd sub || ls`, `cd sub | rm -r ../x`, and
`x=a | grep $x` defer; `read f`, `printf -v f`, or `mapfile f` before a use
of `$f` makes it opaque);
a write-redirect into an enabled arm's root allows only under that arm;
backtick and process substitution defer everywhere; a `$(…)` defers unless
REQ-E1.3 admits it.

### REQ-A1.5 — The enumerated known-safe set [test]

Fixtures exercise each known-safe class from the enumerated allowlist (not a
category match): direct `scripts/*.sh` and `tests/*.sh` (and via `bash`/`sh
<path>`, never `-c`); enumerated read-only coreutils/builtins (with
`find -delete`/`-exec`, `sed -i`, and `sed` `w`/`s///w` file-write commands all
deferring); enumerated read-only `git` subcommands with flag guards
(`git status`/`log`/`diff` allow, `git branch -m` and `git config k v` defer);
lint/test runners (`shellcheck`, `markdownlint(-cli2)`, `yamllint`, `bats`,
`mise run`/`tasks`); read-only `gh`; control structures with verified
bodies/conditions; and `fish -c "<safe-inner>"` allowing while
`fish -c "<unsafe-inner>"` defers, including a nested-but-within-depth buried
unsafe (`fish -c "fish -c '<unsafe>'"` defers by recursive analysis, not only by
hitting the depth cap). Guard-completeness fixtures: `find -execdir`/`-ok`/
`-fprint*` and `sed W` defer; `git branch -D`/`git remote add`/`git remote
set-url`/`git tag -d`/`git stash drop`/`git stash pop` defer while the positive
list-forms (`git branch`, `git stash list`) allow.

### REQ-A1.6 — The explicit defer set [test]

Fixtures assert defer for `rm`, `curl … | sh`, `sudo`, `bash -c`/`sh -c`,
in-place edits, non-`/dev/null` write-redirects, command substitution, mutating
`git`/`gh` subcommands, `kill`/`pkill`, command-runner verbs that wrap an
arbitrary sub-command (`env rm …`, `xargs rm`, `timeout 5 rm …`, `nohup`,
`nice`, `setsid`, `stdbuf`, `chroot`), writer coreutils (`tee`, `dd`, `cp`, `mv`,
`install`, `truncate`, `ln`, `touch`), and text-tool write-escapes (`sed 'w
file'`, `awk 'print > "file"'`, and the severest, `awk 'system("rm -rf x")'`).

### REQ-A1.13 — Defer set, with transparent `time`/`timeout` [test]

Supersedes REQ-A1.6's entry, which it keeps (every listed defer fixture still
defers, now under every policy value where the verb falls outside the arms)
and extends: `python3`/`perl`/`node` with a program defer; every `gh` write
defers; `time git status`, `time -p git status`, and `timeout 30 git status`
allow; `timeout 30 rm -rf x`, `timeout -k 5 30 git status`, and
`time bash -c x` defer; `test -v 'a[$(…)]'`, `[ -v 'a[$(…)]' ]`,
`printf -v 'a[$(…)]' x`, `printf -v PATH /x`, and `sed -i '1e touch x' f`
defer under every policy value.

### REQ-A1.7 — Bash-only [test]

Fixtures with `tool_name` other than `Bash` (e.g. `Read`, `Write`, `Edit`)
defer unconditionally.

### REQ-A1.8 — Safe-invocation rule: unknown flag/arg defers [test]

Fixtures assert defer for un-enumerated flags/args on otherwise-allowlisted
verbs: `sort -o FILE`, `uniq in out`, `markdownlint --fix`, `date -s`, `file -C`,
`find -okdir`/`-fls`, and any `git` carrying a pre-subcommand global option
(`git -c core.pager=… log`, `git -c alias.x='!cmd' x`, `git -C /elsewhere log`,
`git --exec-path=… …`). A recognized-safe invocation of the same verb (`sort
input`, `git log`) allows — the guard is per-invocation, not per-verb.

### REQ-A1.9 — Grammar-conservative deferral [test]

Fixtures assert defer for: inline env-assignment prefixes (`BASH_ENV=x bash
ok.sh`, `LD_PRELOAD=x cat f`, `GIT_PAGER='!cmd' git log`); a path-prefixed verb
(`/tmp/evil/cat f`, `./cat f`) that is not the enumerated repo-script case; fish
bare-paren substitution inside `fish -c` (`fish -c "echo (rm -rf x)"`); subshell
/ brace grouping (`(rm -rf x)`, `{ rm -rf x; }`); bundled/long `-c` (`bash -ec
'rm'`, `fish --command 'rm'`); input here-documents / here-strings (`cat <<EOF
… EOF`, `cmd <<< "x"`); and a redirect-tokenization case proving `>|`/`&>` and
`<<`/`<<<` are not mis-split into a spurious safe segment (`echo x >| stat`
defers).

### REQ-A1.10 — Script/test/bats path containment [test]

Fixtures assert that an enumerated `scripts/*.sh`/`tests/*.sh`/`bats <file>`
invocation whose (expanded) path resolves OUTSIDE the repository defers
(`bash ../../../tmp/evil/scripts/x.sh`, `bats /tmp/evil.bats`), while an
in-repository path allows — the containment check backing the trust boundary.

### REQ-A1.14 — Raw-path containment against repository and plugin roots [test]

Supersedes REQ-A1.10's entry, which it keeps (both outside-path fixtures
defer, an in-repository path allows) and extends: a script under an installed
planwright plugin root allows; `bash $X/scripts/x.sh` with `X` unassigned
defers; `X=../../../tmp/evil; bash $X/scripts/x.sh` resolves to the literal
and defers on containment.

## REQ-B — Implementation, robustness, and security

### REQ-B1.1 — Portable POSIX/bash, pure-shell analysis [test + design-level]

`[test]`: the suite runs the hook under `/bin/bash` (the repo's bash 3.2 floor
via `run-tests.sh`), and an **inert-data side-effect probe** — a fixture whose
command would create an observable side effect if the analyzer expanded or
evaluated it (e.g. `$(touch MARKER)` / a backtick that writes `MARKER`) —
asserts the marker file is never created (analysis never executes the command).
`[design-level]`: `shellcheck`/`shfmt` in CI plus review confirm no
python/fish/mise/tmux dependency and that analysis is pure shell.

### REQ-B1.2 — jq extraction with degrade-to-defer [test]

A fixture invoking the hook with `jq` forced absent (PATH-stripped) asserts
defer-all; a normal fixture asserts correct extraction of `tool_name` and a
command containing quotes/escapes.

### REQ-B1.3 — Fail-safe on malformed input [test]

Malformed/empty stdin, non-JSON input, missing fields, and `fish -c` nested
past the bounded recursion depth all defer without error.

### REQ-B1.4 — No untrusted echo; fixed reason [test + design-level]

`[test]`: the emitted `permissionDecisionReason` is the fixed string; a fixture
whose command carries a distinctive **marker token** asserts the marker is absent
from the reason (the no-reflection check exercises a real reflection path, not
just a benign command). `[design-level]`: review confirms no raw command content
is written to stderr/stdout in a terminal-driving way.

### REQ-B1.5 — Held to the framework-script security bar [design-level]

The script lives under `scripts/`, is covered by `mise run lint` (shellcheck +
shfmt) and the secret scan, and is small enough to read before trusting — the
security-posture framework-script bar, verified by its presence in those gates.

### REQ-B1.6 — Adversarial suite: zero false-allows, deny never approved [test]

The suite itself is the verification: ≥30 adversarial cases (the prototype set
plus surfaced regressions), a positive assertion of zero false-allows across
the corpus, and an assertion that no deny-listed command is ever auto-approved.
The corpus MUST include the kickoff-surfaced false-allow vectors:
command-runner wrappers (`env`/`xargs`/`timeout`/`nohup`/`nice`/`setsid` of an
`rm`), writer coreutils (`tee`/`dd`/`cp`/`mv`/`install`/`truncate`/`ln`/
`touch`), and text-tool write-escapes (`sed 'w file'`, `awk 'print > "f"'`), each
asserted to defer. Runs under `mise run test` / CI.

### REQ-B1.7 — Fail-closed emission contract [test + design-level]

Fixtures assert: the defer path emits empty stdout and exits 0; an internal
error / signal path never emits a partial `allow` and never exits 2 (a fixture
forcing an error asserts exit 0 + empty stdout, not the CC block signal); a
present-but-empty (`""`) and a non-string `tool_input.command` both defer.
`[design-level]`: the hook decides from the command string + path metadata only
and never reads a target script's contents (no `bash -n <target>`, no file-content
read) — reviewable by reading the script; a hook-script start failure produces no
output, which Claude Code treats as its normal prompt (structural fail-safe, not
an emitted decision). `[test]` where a failure can be induced under the suite;
the no-hang / bounded-runtime guarantee is exercised with a large/pathological
input asserting prompt termination.

### REQ-B1.8 — Fail-closed emission with policy and identity inputs [test + design-level]

Supersedes REQ-B1.7's entry, which it keeps (empty stdout plus exit 0 on
defer, never exit 2, never a partial allow, bounded runtime, empty command
defers). Adds, per session-record field: a missing or unparseable policy
behaves as the empty list; a missing worktree root or unit branch yields no
`own-branch` approval and makes every `cd` defer; a missing scratch root
yields no `scratch` approval; a missing PR base or `worker_base_merge` value
yields no base-merge approval; an unreadable record leaves only the read-only
arm; a record field disabling one arm leaves the other arm working.
`[design-level]`: the hook reads no target script's contents and no input
outside the record, the declared steps, and the deny rules (reviewable in the
script).

## REQ-C — Wiring and delivery

### REQ-C1.1 — Wired into worker-settings via ${CLAUDE_PLUGIN_ROOT} [test + manual]

`[test]`: a JSON-shape assertion confirms `config/worker-settings.json` carries
a `PreToolUse` (Bash) hook referencing the script via `${CLAUDE_PLUGIN_ROOT}`,
`defaultMode` is `default`, and the `deny` block is unchanged from baseline.
*(Amended at the 2026-10-05 extension kickoff: Task 12 moves the baseline to
include exactly the `Write`/`Edit` path rules REQ-F1.6 and REQ-G1.8 add; the
`Bash(…)` deny rules stay unchanged.)*
`[manual]`: a dispatched worker under the wired profile runs a full task without
a prompt-flood. This confirmation MUST be re-run against the shipped pure-shell
hook (Task 1); the PR #232 evidence covered the python prototype, not the port,
so it does not transfer.

### REQ-C1.2 — Worker-scoped only [test + design-level]

`[test]`: an assertion that the auto-approve hook appears in
`config/worker-settings.json` and NOT in the plugin-global `hooks/hooks.json`.
`[design-level]`: review confirms the tower and human interactive sessions do
not load this hook.

### REQ-C1.3 — Human-reviewed delivery; _about updated [design-level]

Review confirms the `_about` field documents the hook and the human-sign-off
posture, that delivery remains manual merge/reference (no `settings.json`
auto-edit by any skill), and that the fragment still reads as a
human-review-before-use artifact.

## REQ-D — Root-cause: literal script-path invocation

### REQ-D1.1 — Literal script-path invocation in the dispatching skills [test + manual]

`[test]`: a grep-based assertion over `/execute-task`, `/orchestrate`, and
`/spec-kickoff` confirms plugin-script call sites use a resolved literal path
and no `"$VAR/scripts/x.sh"` invocation shape remains at those sites.
`[manual]`: a dispatched worker confirms such invocations are now
statically analyzable (offered a persistent-allow, or matched by a literal-path
allow entry) even with the hook disabled.

## REQ-E — Expansion and compound-shape coverage

### REQ-E1.1 — Unresolved or opaque `$` in a screened position defers [test]

In both the worker and tower guard suites: `for d in "<flags>"; do find . $d;
done`, the `$_` form, a non-literal loop head reaching a screened operand
(`for d in $X; do cat $d; done`), a glob in a verb path
(`bash scripts/s*.sh`), and a symlinked cache root all defer, each first
shown allowing against the pre-change guard; a loop variable reaching `bash`
or a containment check defers as a regression-only fixture (the pre-change
guard already defers it); a loop head past the stated bound defers whole;
`for f in a b; do grep -n x $f; done` still allows, matching its substituted
literal form.

### REQ-E1.2 — Plain-literal assignments resolve [test]

`f=README.md && grep -n x $f` allows; a whitespace-bearing value resolves
only inside double quotes, so `F='a b' && find . -name "$F"` and
`F='x -delete' && find . -name "$F"` allow as one operand while
`F='-name a.sh' && find . $F` and `F='x -delete' && find . -name $F` defer
(unquoted, the value stays unresolved, since zsh does not split it); an
empty value removes an unquoted word (`f= && find . $f -name a` allows);
`IFS=- && …`, `PATH=x && …`, and a conditional `false && f=x` before
a use of `$f` defer under the name and placement rules; an assignment whose
value carries a glob, an expansion, or an unmodelled quote leaves the
variable opaque and its use in a screened position defers.

### REQ-E1.3 — Argument-independent command substitution [test]

`<plugin-root>/scripts/step-record.sh write --head $(git rev-parse HEAD)` and
`until [ -z "$(git status --porcelain)" ]; do sleep 5; done` allow;
`find . $(echo -maxdepth 0 -exec id \;)`, `cat $(git ls-files)` (`cat` is
outside the enumerated argument-independent set), `test -v "$(cat f)"`,
`printf "$(cat f)"`, a nested substitution, a backtick, a substitution in the
verb position, and `x=$(git log -1) && find . $x` defer. Each fixture that
depends on the argument-independence check is first shown allowing against
the over-broad variant Task 7 defines; the nesting and backtick fixtures are
regression-only.

### REQ-E1.4 — `cd` into the own worktree only [test + design-level]

`cd <own worktree> && ls` and `cd sub && ls` (an existing in-worktree
directory) allow; `cd /tmp && ls`, `cd $X && ls`, `cd .. && ls` from the
worktree root, `cd missing && ls`, `cd sub; ls`, and a `cd` with `CDPATH`
set in the command defer. `[design-level]`: the fleet guide and worker
launch text state that a worker issues `git` without a `cd`, since Claude
Code's own `cd`-before-`git` gate is outside the hook's reach.

### REQ-E1.5 — Timing and inspection verbs [test]

`sleep 5`, `ps -A`, `ps -o pid,args`, `uptime`, `which git`,
`command -v jq`, `git check-ignore x`, `git ls-remote origin`, `jq --version`
allow; `sleep $X`, `ps` with an unrecognized flag, every `ps` form carrying
`-e` (`ps -ef`, `ps -e`, `ps -eo pid,args`; D-26), `git ls-remote https://h/x`,
`git ls-remote ./path`, and `git ls-remote --upload-pack=x origin` defer.

## REQ-F — The self-approval policy

### REQ-F1.1 — One knob, read-only always on, fail-closed fallback [test]

With no overlay, the resolved `worker_self_approval` is the empty list, the
read-only arm (pre-extension categories plus REQ-E shapes) approves, and the
corpus's own-branch and scratch rows defer; a value with an unknown member, a
malformed value, and an unreadable config each resolve to the empty list; an
overlay setting `own-branch` is honoured through the layer chain, and a
machine-local overlay setting the empty list narrows a repo-tracked
`own-branch scratch` (last-value-wins).

### REQ-F1.2 — The guard is the only evaluator [test + design-level]

`[test]`: the policy is applied per segment (`git add x && rm -rf /` defers
under `own-branch`). `[design-level]`: no tower, supervisor, or relay script
reads the policy to answer a prompt (a grep over the fleet scripts for the
knob name finds only the launcher, the guard, and the config readers).

### REQ-F1.3 — The own-branch arm [test]

Under `own-branch`, with the session record naming the unit branch and the
session on it: `sed -i s/a/b/ f`, `rm -r build`, `git add -A`,
`git commit -m x`, `git fetch origin`, `git fetch origin main`, and
`git merge origin/main` (PR base `main`, `worker_base_merge: allow`) allow;
the same merge under `deny`, after `git switch other`, or from a source other
than the PR base defers; `git fetch origin main:main`, `git fetch <url>`,
`sed -i '1e touch x' f`, `cp -l <outside> x`, `cp -s <outside> x`,
`mv <outside> x`, a write to a file with a second hard link outside the
worktree, and a write following a link-creating segment defer; a write whose
target canonicalizes outside the worktree defers; `git push origin <unit>`
gets no guard approval (the static rule covers it); a record with no unit
branch gives no own-branch approval.

### REQ-F1.4 — The scratch arm [test]

Under `scratch`: `mkdir -p <scratch>/x`, `mkdir -p $TMPDIR/x` (resolved to the
recorded root), `cmd > <scratch>/out.log 2>&1`, and `rm -r <scratch>/x`
allow; a write to `/tmp/other`, a symlink in the scratch root pointing
outside it, `cp -l <outside> <scratch>/x`, and `bash <scratch>/x.sh` /
`. <scratch>/x.sh` defer.

### REQ-F1.5 — The floor holds under every policy value [test]

For every policy value including both arms: `gh pr merge`, `gh pr ready`,
`git push --force`, `git commit --amend`, `git rebase`, `git reset --hard`,
`git push origin HEAD:main`, `git push origin <other branch>`, a write
outside worktree and scratch, and `gh pr comment` all defer;
`cat x >/dev/null 2>&1` still allows (`/dev/null` is not a floor write), and
`git commit -m x` under `own-branch` is not refused for writing git's own
directory. A fixture shows the floor check runs before the arm (a floor
command that an arm would otherwise match).

### REQ-F1.6 — Execution-bearing paths closed in both layers [test]

Under `own-branch`: writes (Bash writers and redirects) to the worktree's
`.git`, the configured hooks directory, `.claude/settings.json`,
`mise.toml`, and `lefthook.yml` defer; a permission-matcher fixture row shows
`Write`/`Edit` on each of those paths denied by the profile; editing
`scripts/x.sh` then running `bash scripts/x.sh` still allows.

## REQ-G — Profiles, delivery, and the unattended contract

### REQ-G1.1 — Static read-only allow set [test]

The permission-matcher fixture table carries a row for every new allow rule
and the test fails on an allow rule with no row; assertions that no new rule
names `awk`, `find`, `xargs`, `sed` (any form), `sort`, `uniq`, a diff-family
`git` subcommand, `git grep`, or `git cat-file`.

### REQ-G1.2 — Launcher-created scratch root [test]

A launched worker's environment carries `TMPDIR` set to a directory the
launcher created for it, owned by the worker's user, and recorded in the
session record; a `recover` keeps the same root; the final stop removes it;
the guard treats no other directory as scratch.

### REQ-G1.3 — Relaunch under the current profile [test + manual]

`[test]`: `relaunch` on a live worker stops it and runs `recover`, whose argv
carries `--resume <persisted id>` and the installed profile path passed
explicitly; it refuses a worker with no persisted session or holding a lock
the stop would release; the session record is rewritten from current config
and the scratch root kept. `[manual]`: a live worker relaunched after a
policy change approves a command the new policy admits.

### REQ-G1.4 — Unattended defined in doctrine [design-level]

The inter-orchestrator-coordination doctrine's permission-prompt section
carries the statement, consistent with its standing-decision clause; the
doctrine index row and budget checks pass.

### REQ-G1.5 — Meta-tower direct dispatch [test + manual]

`[test]`: the meta-step script takes and releases the per-spec lock around
the single-spec step, launches a worker and no subordinate tower session, and
is excluded by a concurrent single-spec tower's lock. `[manual]`: a live
`--fleet --unattended` run starts a worker with no subordinate-tower prompt.

### REQ-G1.6 — `git push -u origin` allowed [test]

A permission-matcher fixture row shows `git push -u origin <unit branch>`
allowed and `git push -u origin main` and `git push -u origin --force x`
denied.

### REQ-G1.7 — `_about` describes every category [design-level]

The profile's `_about` names the read-only, trusted-repo-task, and
declared-step categories, each policy arm, and the floor.

### REQ-G1.8 — Trust inputs from a launcher-written record [test]

A launched worker has a session record outside its worktree and scratch
root holding the policy, unit branch, worktree root, PR base, scratch root,
audit-log home, and `worker_base_merge` value; changing the overlay after
launch does not change the guard's verdicts until relaunch; after
`git switch other` the own-branch arm still treats the recorded branch as the
unit branch; a permission-matcher fixture row shows `Write`/`Edit` on the
record and on each overlay config file denied.

## REQ-H — Source fixes and verified premises

### REQ-H1.1 — Scripts self-resolve substitution-fed values [test]

`step-record.sh write` without `--head` records the current `HEAD`; the
explicit form is unchanged; each swept script has a test for its default.

### REQ-H1.2 — Matcher model pinned to the documented nested behaviour [test + design-level]

`[test]`: matcher fixture rows show a deny rule firing on the command nested
in `$(…)`, a subshell, and a `for` body. `[design-level]`: the model doc and
`_about` cite the permissions documentation and drop the boundary that
assumed otherwise.

### REQ-H1.3 — Real-prompt regression corpus [test]

The corpus harness runs under `mise run test`: in-policy rows approve under
their arm, floor rows defer under every value, uncovered rows defer, and a
pending class becomes enforced once marked shipped, so any of its rows that
misses its expected verdict then fails; the rows of the earlier
`tests/fixtures/worker-guard-corpus.tsv` are migrated or retired with a
recorded reason; the secret scan and purged-identifier guard pass over the
corpus file.

### REQ-H1.4 — Hashed audit log of allow decisions [test]

An approved fixture writes exactly one line to the per-session log with time,
session, arm, and command hash and no command text; an unwritable log leaves
the `allow` well-formed; a record with no log home yields no `own-branch` or
`scratch` approval while read-only approvals proceed; the launcher or stop
pruning step enforces the retention bound.
