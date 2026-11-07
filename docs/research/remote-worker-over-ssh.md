# Remote workers over SSH: what works today

**Verdict: works today by hand, with gaps.** A second host with planwright
installed can run a stream-json worker that this host's mission control
launches, vets, steers and retires over SSH, with the branch travelling
through GitHub. Nothing in the fleet scripts is Linux-only (CI runs the suite
on macOS and Alpine too). What is missing is plumbing on the near side:
mission control's vetting loop, guards and usage gate only look at the local
host, and every remote call is an unvetted `ssh` command line.

The host is a parameter throughout: an SSH alias from `~/.ssh/config`. A Mac
on the LAN and a Coder workspace (`coder config-ssh` writes the alias) take
the same path.

Status: the recipe and gaps were read from the scripts before any live run.
Since then the first remote host (a macOS machine reached as a dedicated
account) has run the compute verb below for real; the full worker round trip
has not been run yet.

## Live results (2026-11-06)

- The stream-json supervisor suite, run on the same commit on both hosts at
  once: every check passed on each; the remote took a little over two
  minutes, this host (load around 41 on 12 cores) over eight.
- A five-second timeout on the same suite stopped it at five seconds with
  the terminate status and left no process, worktree or ref behind.
- The model-provider login worked over SSH on that host as set up, so the
  keychain gap below did not bite there.

## The recipe

Placeholders: `<alias>` the SSH alias, `<root>` the remote planwright install
root, `<repo>` the remote host's own clone of the target repository.

1. **Resolve the remote root.** Run `scripts/resolve-installed-roots.sh --current`
   from any planwright copy on the remote, or read
   `~/.claude/plugins/installed_plugins.json` there. The root is the remote's
   own path (on macOS under `/Users/<user>/.claude/plugins/cache/planwright/planwright/<version>`),
   never this host's.
2. **Launch.** Ship the brief over stdin into a remote `mktemp` file, then run
   the remote launcher, which creates the worktree, registers the session and
   starts the detached supervisor there:

   ```sh
   ssh <alias> 'f=$(mktemp "${TMPDIR:-/tmp}/brief.XXXXXX") && cat >"$f" &&
     <root>/scripts/mission-control-launch.sh launch --program <p> \
       --kind worker --scope <s> --brief "$f" --backend stream-json \
       --repo <repo>' <brief
   ```

   The remote launcher needs the program configured on the remote host. The
   lower-level `fleet-streamjson.sh launch <worker> <scope> --prompt-file "$f"
   --cwd <worktree>` works without one, with the worktree made by hand. The
   supervisor detaches with every stdio redirected, so the SSH session returns
   and the worker outlives it.
3. **Read requests.** `ssh <alias> <root>/scripts/fleet-streamjson.sh pending [<worker>]`
   prints each pending request with its full tool input, the same view the
   local vetting loop reads.
4. **Answer.** `ssh <alias> <root>/scripts/fleet-streamjson.sh answer <worker>
   <request-id> --allow` (or `--deny --message <text>`). The fifo write happens on the remote host,
   so the journal lock and the undeliverable handling work unchanged.
5. **Steer.** Same stdin trick as the brief:

   ```sh
   ssh <alias> 'f=$(mktemp "${TMPDIR:-/tmp}/brief.XXXXXX") && cat >"$f" &&
     <root>/scripts/fleet-streamjson.sh steer <worker> --message-file "$f"' <message
   ```

6. **Status and result.** `ssh <alias> <root>/scripts/fleet-streamjson.sh status <worker>`;
   the run outcome is the `result` row in the remote fleet home
   (`<fleet home>/streamjson/<worker>/result`).
7. **Retire.** `ssh <alias> <root>/scripts/mission-control-launch.sh retire
   <name>` for a launcher-made worker, which also updates its registry row
   (`fleet-streamjson.sh stop <worker> --final` for one launched by hand), then
   remove the remote worktree once its PR merged or closed.
8. **Branch.** The worker pushes its branch and opens the draft PR from the
   remote clone; review, cubic rounds and the ready flip run here against the
   PR, as for any PR.

## Gaps

- **Remote checkout.** The remote host needs its own clone per repository, with
  `gh` authenticated and push rights; the launcher makes worktrees inside it.
  Nothing on this host knows where that clone lives.
- **Plugin root and version skew.** The remote root is a different path, and
  the two hosts can run different planwright versions. Every remote call has to
  name the remote's resolved literal root, which no local config records.
- **Non-interactive SSH environment.** `ssh <alias> <cmd>` runs a non-login
  shell: mise shims, Homebrew and `claude` may be off `PATH`, and the remote's
  machine-local env (`CLAUDE_PLUGIN_DATA` for the fleet home) is not loaded.
  Calls need the remote's environment loaded explicitly (the channel below
  sources an optional environment file on the remote).
- **Claude auth over SSH on macOS.** Claude Code on macOS keeps its login in
  the user keychain, which an SSH session may find locked, so a worker can fail
  to authenticate even though the operator is signed in at the desk. It did not
  happen on the first host (see Live results), so it is a risk per host, not a
  certainty; the fallback is a long-lived token (`claude setup-token`) held in
  an untracked env file on that host, never in dotfiles.
- **Shell quoting.** `ssh` joins its arguments into one remote shell string, so
  a scope, message or path with a space or quote is re-parsed there. Hand-typed
  recipes are an injection and breakage risk; every argument needs quoting.
- **The vetting loop is local.** The pending view, `mc-keeper.sh`'s
  `alarm-scan` sweep, `mc-wake.sh`'s steer, `fleet-status.sh`, the attention
  store and push notifications all read this host's fleet home. A remote
  worker's requests are invisible here unless polled over SSH, and with no
  mission control on the remote nothing runs its alarm scan either. An
  unwatched request pends forever.
- **Guards approve local literal paths.** The tower and mission-control command
  guards approve `<local root>/scripts/fleet-streamjson.sh ...` by its resolved
  path. An `ssh <alias> ...` command matches no rule, so every remote read,
  answer and steer falls to a permission prompt or the classifier.
- **Liveness assumes a local pid.** Supervisor and worker liveness (`ps -p`,
  `kill -0`, `/proc`), the lock holder checks, the dispatch registry, the stuck
  detector and fleet cleanup all test pids on the host they run on. Run on this
  host they read a remote worker as absent, so it must never be judged from
  here, only through the remote's own `status`.
- **Usage is per account.** `~/.cache/claude-usage/rate-limits.json` is written
  by the status line of whichever account runs on that host. The second
  account's usage lives on the remote host only (and only while some
  interactive session renders a status line there); each worker's own
  `ratelimit` file under the remote fleet home is the other source. The local
  usage gate and the dynamic worker limit read this host's account alone.
- **Capacity is per host.** The dynamic worker limit reads local load and
  memory. A remote launch has to read the remote host's, and a shared personal
  machine also needs an "owner is using it" signal (input idle time) and sleep
  prevention while a worker runs, or the worker stalls when the lid closes.
- **Placement does not know hosts.** Work placement and `/offload` choose rungs
  by advertised capability on one host; there is no host dimension, no list of
  remote hosts and no per-host ceiling.
- **Coder specifics.** A Coder workspace is Linux and reached the same way, but
  may auto-stop or be rebuilt, taking the fleet home and the clone with it;
  the channel has to treat a vanished remote as a dead worker, not a lost one.

## Smallest working channel

`scripts/fleet-remote.sh` (landed with this note) is the recipe as one
command: it takes the SSH alias as a parameter, resolves the root on the
remote, sources the remote's optional `~/.config/planwright/remote-env.sh`
for `PATH` and the fleet home, quotes every argument, refuses ones that no
remote shell can read the same way, and ships briefs and steer messages over
stdin. Its verbs are `root`, `launch`, `pending`, `answer`, `steer`, `status`,
`retire` and `compute`; `--help` has the contract. `compute` needs no worker
at all: it pushes a worktree's HEAD commit into the remote's clone of the
same repository (`~/dev/<repo>`) as a hidden ref, runs the full check, a
named task or a named test file there in a scratch worktree, streams the
output back and exits with the command's status. It changes no guard, so in a session
whose guard does not approve it each call still asks. Folding remote hosts
into vetting, usage, capacity and placement is spec-sized:
`specs/remote-worker-rung/`.
