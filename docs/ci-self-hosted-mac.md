# The self-hosted macOS runner

CI's two macOS jobs (`macos-suite` and `macos-smoke` in
`.github/workflows/ci.yml`) can run on a self-hosted runner on the offload
Mac instead of GitHub's hosted macOS. That runner is used only for code from
this repository's own branches, and only after a repository variable turns it
on. Everything else, fork pull requests included, keeps running on GitHub's
`macos-latest`.

| Name | Value |
| --- | --- |
| Runner account on the Mac | `gharunner` (a standard account, not admin) |
| Runner labels | `self-hosted`, `macOS`, `ARM64`, `offload-mac-ci` |
| Label the workflow selects on | `offload-mac-ci` (no GitHub-hosted image carries it) |
| Switch | repository variable `PLANWRIGHT_MAC_RUNNER` |

The account and labels must match what the dotfiles repository provisions on
the Mac. The labels appear in the two `runs-on:` lines of `ci.yml`, which
must stay identical.

## How a run picks its runner

The `plan` job's `mac` step decides, and prints its reason in the run
summary:

- **Self-hosted** only when `PLANWRIGHT_MAC_RUNNER` is `self-hosted` **and**
  the event is a push to this repository (CI runs on pushes to `main` only)
  or a `pull_request` whose head repository is this repository
  (`github.event.pull_request.head.repo.full_name == github.repository`).
- **GitHub's hosted macOS** in every other case: the variable unset or any
  other value, a pull request from a fork, or an event the step does not
  name. An unknown case falls back to hosted, never the other way.

Both jobs then run on
`${{ <self-hosted?> && fromJSON('[...labels...]') || 'macos-latest' }}`.
`check:workflow-posture` (`scripts/check-workflow-posture.sh --matrix`)
accepts exactly this shape as a macOS job: the label list must name
`self-hosted` and `macOS`, and GitHub's hosted macOS must be the fallback. A
bare self-hosted label list fails it, because it would leave fork pull
requests no hosted path.

## Fork policy

The repository is public, so no fork's code may ever run on the Mac. Three
layers keep it off, and only the last two hold against a hostile fork:

1. **The workflow's routing** (above) never sends a fork's pull request to
   the self-hosted labels. This covers honest forks. It cannot stop a fork
   whose pull request edits `ci.yml` to name the labels itself, because a
   `pull_request` run uses the pull request's copy of the workflow.
2. **The runner's job-started hook** (below) refuses, before any step runs,
   every job that is not a push to this repository or a pull request from one
   of its own branches. A fork that rewrote the workflow fails here, on the
   runner, where its edit cannot reach.
3. **The repository's fork-approval setting** should be
   `all_external_contributors`, so no outside contributor's workflow runs at
   all until a maintainer has read it and approved the run. It was
   `first_time_contributors` when this runner was set up. Set it with:

   ```sh
   gh api -X PUT repos/inkatze/planwright/actions/permissions/fork-pr-contributor-approval \
     -f approval_policy=all_external_contributors
   ```

Trigger review: `ci.yml` fires only on `pull_request` and on `push` to
`main`. No workflow here uses `pull_request_target` (the posture guard bans
it). The one `workflow_run` workflow (`release-please.yml`) runs on
`ubuntu-latest`, never the Mac, and every other workflow does too. Any new
trigger that can carry another
repository's code must stay on hosted runners. The hook refuses everything
but `push` and `pull_request`, so a new trigger is refused there by default.

The macOS jobs carry `permissions: contents: read` and reference no stored
secret. The `gharunner` account should hold no credentials either: no `gh`
sign-in, no SSH keys, nothing in its keychain the jobs could read.

### The job-started hook

The runner runs this script before every job when its `.env` file (in the
runner's install directory) sets
`ACTIONS_RUNNER_HOOK_JOB_STARTED=<absolute path to the script>`. A non-zero
exit fails the job before its first step. It fails closed: an unreadable
payload, an unknown event, or a missing value all refuse.

```sh
#!/bin/sh
# Refuse any job whose code is not this repository's own.
set -eu
repo=inkatze/planwright
refuse() {
  echo "offload-mac-ci: refusing this job: $*" >&2
  exit 1
}
[ "${GITHUB_REPOSITORY:-}" = "$repo" ] \
  || refuse "repository '${GITHUB_REPOSITORY:-}' is not $repo"
case "${GITHUB_EVENT_NAME:-}" in
  push) ;;
  pull_request)
    head=$(/usr/bin/jq -r '.pull_request.head.repo.full_name // empty' \
      "${GITHUB_EVENT_PATH:?}") || refuse "cannot read the event payload"
    [ "$head" = "$repo" ] || refuse "pull request head '$head' is not $repo"
    ;;
  *) refuse "event '${GITHUB_EVENT_NAME:-}' is not push or pull_request" ;;
esac
```

`/usr/bin/jq` ships with macOS 15 and later. If the runner ever stops
passing the `GITHUB_*` values to the hook, the hook refuses every job, which
fails loudly rather than letting anything through. After installing the hook, check
it once: a pull request from a branch of this repository must pass the hook
(its log shows the hook ran), and the hook must refuse when run by hand with
`GITHUB_EVENT_NAME=pull_request` and an event file whose head repository is a
fork.

## One job at a time, and the shard count

A runner takes one job at a time, so the self-hosted path runs the suite as a
single shard (`[1]`) instead of the hosted path's four. Four shards on one
runner would run one after another and repeat the setup each time. One shard
already uses every core, because `scripts/run-tests.sh` runs as many test
files at once as the machine has cores.

Estimate, from the last green `ci` run before this change (no queueing): the
four hosted shards took 18, 24, 9 and 22 minutes on 3-core hosted Macs, about
200 core-minutes of suite. On the offload Mac (16 cores, `hw.ncpu`, which
counts efficiency cores too) that comes to roughly 10 to 20 minutes for the
suite, plus about 2 minutes of setup and the smoke job's minute after it.
That is about 13 to 23 minutes for the macOS side, against 24 minutes for
that run with no queueing and 69 minutes for a run that queued for hosted
Macs. This is an estimate; the first self-hosted runs measure it.

More runner instances on the Mac do not add compute. Every instance runs as
`gharunner`, and the suite's parallel ticket pool is per user, so the
instances share one pool of 16. A second instance would only stop two pull
requests' runs from waiting on each other. If it is added, raise the
self-hosted shard count in the `mac` step to match. The Mac's other work (the
fleet account's workers) competes with CI for the same cores.

The runner app is persistent, not ephemeral: an ephemeral runner needs a
fresh registration token per job, which needs an admin credential on the Mac,
and the hook already keeps foreign code off. `actions/checkout` cleans the
workspace each job.

## What the Mac must provide

The jobs narrow `PATH` to the system directories plus a directory linking
`gh`, `node`, `mise` and the Claude CLI, so they meet macOS's own bash 3.2,
awk and sed. `jdx/mise-action` installs mise and the pinned tools, and the job
installs the pinned Claude CLI with `npm install -g`. So `gharunner`'s runner
service needs `git`, `gh` and `node` (with an npm global prefix it can write)
on its `PATH`, with no Homebrew GNU tools ahead of the system ones. `gh` needs
no sign-in.

## Registering and deregistering

Registration and removal tokens need admin access to the repository, so fetch
them where `gh` is signed in as an admin, then run the runner's scripts on the
Mac as `gharunner` in the runner's install directory.

Register in this order. The labels are public in `ci.yml`, so a fork can
target them as soon as the runner is online; the runner must never be online
without the hook.

1. Set the fork-approval policy (see [Fork policy](#fork-policy)).
2. Configure the runner without starting it (the OS and architecture labels
   `self-hosted`, `macOS` and `ARM64` are added automatically):

   ```sh
   gh api -X POST repos/inkatze/planwright/actions/runners/registration-token --jq .token
   ./config.sh --url https://github.com/inkatze/planwright --token <token> \
     --name offload-mac-ci --labels offload-mac-ci --unattended --replace
   ```

3. Install the [job-started hook](#the-job-started-hook) outside the runner's
   install directory (GitHub's guidance, since runner updates replace that
   directory), and add its `ACTIONS_RUNNER_HOOK_JOB_STARTED` line to the
   runner's `.env`. The runner reads `.env` only when it starts, so a later
   edit needs a restart.
4. Start the runner as a service that comes up at boot without anyone
   logging in. On macOS the runner's `./svc.sh install` writes a LaunchAgent
   to the account's `~/Library/LaunchAgents`, which runs only inside a login
   session, and `gharunner` normally has none. So either install a
   LaunchDaemon that runs as `gharunner` (built from the runner's
   `bin/actions.runner.plist.template`, an admin act for the dotfiles side),
   or have `gharunner` log in automatically. Otherwise the runner goes
   offline at every reboot and, with the switch on, macOS jobs queue.

Then turn the switch on:

```sh
gh variable set PLANWRIGHT_MAC_RUNNER --body self-hosted --repo inkatze/planwright
```

Deregister: turn the switch off first (below), stop and remove the service
in whichever form step 4 installed it (`./svc.sh stop` then
`./svc.sh uninstall` for the LaunchAgent), then:

```sh
gh api -X POST repos/inkatze/planwright/actions/runners/remove-token --jq .token
./config.sh remove --token <token>
```

If the Mac is gone, remove the runner from GitHub instead: list it with
`gh api repos/inkatze/planwright/actions/runners` and delete it with
`gh api -X DELETE repos/inkatze/planwright/actions/runners/<id>`.

## When the runner is offline

A job waiting for a self-hosted runner does not fail fast. `timeout-minutes`
counts only from when a job starts (45 minutes for the suite, 15 for the
smoke), and GitHub keeps a queued job waiting up to 24 hours before failing
it. The workflow cannot check whether the runner is online, because that API
needs an admin credential the read-only token lacks. So when the Mac will be
away (asleep, off the network, its runner stopped):

```sh
gh variable delete PLANWRIGHT_MAC_RUNNER --repo inkatze/planwright
```

New runs then use GitHub's hosted macOS. For a run already stuck in the
queue, cancel it and re-run **all** of its jobs (`gh run cancel <run-id>`,
then `gh run rerun <run-id>`). Re-running only the failed jobs reuses the old
`plan` job's choice and queues for the Mac again. A new push to the same pull
request also cancels the stuck run, through the workflow's concurrency group.
Set the variable back when the runner is up again.
