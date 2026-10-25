# Spec location

Spec bundles live under the **spec root**: `specs/` at the top of the work
repository by default, or the directory the `spec_root` option names (see the
[options reference](options-reference.md)). That directory may sit elsewhere in
the repository, in a separate **holder** repository, or in no repository at
all. The root's git relationship to the work repository is its **posture**,
defined in [`storage-classes`](../doctrine/storage-classes.md) (*The posture
ladder*): `same-repo`, `separate-repo`, or `plain`.

| Posture | Where the root sits | Use it for |
| --- | --- | --- |
| `same-repo` | inside the work repository (the default `specs/`, or another directory in it) | the recommended rung: bundles ride the same branches, PRs, and guards as the code |
| `separate-repo` | in a holder: a second git repository holding one root per project it serves | specs shared across projects, or kept out of a repository others read |
| `plain` | in a directory no git repository contains | a personal store; every commit, push, PR, and guard step is skipped |

## Setting the option

Unset, the root is `specs/` and nothing changes. To move it, set `spec_root`
in any config layer; a path on one machine belongs in the machine-local file,
which git ignores:

```yaml
# <repo>/.claude/planwright.local.yml
spec_root: ~/spec-holder/acme
```

The value is absolute, `~/`-prefixed, or relative to the primary checkout
(`docs/specs` keeps the root in the repository under another name). An empty
value cancels one a lower layer set. A value naming no directory is refused,
never replaced by the default. The full rules are in the `spec_root` row of
the options reference.

## Finding the root

Nothing composes the root by hand. `scripts/resolve-root.sh` answers:

- `resolve-root.sh spec` prints the root as the current checkout sees it.
- `resolve-root.sh spec --primary` prints the primary view: the primary
  checkout's copy, the holder's, or the plain directory.
- `resolve-root.sh spec --posture` prints the posture.
- `resolve-root.sh --explain spec` names the config layer that set the root.

## The marker

A configured directory other than the default must carry the marker file
`planwright-spec-root.yml`; without it the resolver refuses the directory and
never falls back to `specs/`. The marker is a regular file (never a symlink)
of two lines:

```yaml
project: acme
layout: 1
```

`project:` is a spec identifier naming the project the root serves, and
`layout:` is `1`. `resolve-root.sh spec --init` writes the marker (and, in a
git repository, the ignore rules for the root's local-only entries) into a
directory that already exists. `/spec-draft` offers to run it when it meets a
marker-less root. `resolve-root.sh marker <dir>` checks a directory by shape
alone, reading no config, which is how a caller vets a root another checkout
owns.

## The holder layout

A holder serves several projects, one root each, side by side:

```text
<holder>/
  acme/                      the root one project's spec_root names
    planwright-spec-root.yml   project: acme
    _observations/             that project's own accumulator
    <spec>/                    its bundles
  globex/
    planwright-spec-root.yml   project: globex
    ...
  .claude/worktrees/         spec worktrees (ignored, as in a work repository)
```

Each root carries its own marker and its own reserved children
(`_observations/`, `_pending/`), so the projects' observations never mix. A
spec identifier must be unique across every project the holder serves, since
all of them share the holder's spec branches (`planwright/<spec>/spec`). The
observation carry (`scripts/observation-carry.sh`) works in the holder: its
chore branch, lock, and PR live there. In `plain` the carry has no git to work
through and says so.

## Authoring by posture

`/spec-draft` and `/spec-kickoff` read the posture before any branch,
worktree, or commit step, and follow this table. Task branches, task PRs, and
commit trailers stay in the work repository in every posture.

| Step | `same-repo` | `separate-repo` | `plain` |
| --- | --- | --- | --- |
| Spec branch and worktree | `planwright/<spec>/spec` in the work repository, worktree via the native mechanism | in the holder: `scripts/spec-store-worktree.sh <spec>` | none, anywhere |
| What the skills' `<root>/<spec>` names (bundle reads, validator, anchor, writes) | `<root>/<spec>/` in the spec worktree | the `bundle` path the script prints | `<root>/<spec>/` |
| Draft, consume, and kickoff commits | on the spec branch | on the spec branch, `git -C <worktree>` | skipped |
| Push and spec PR | the work repository | the holder | skipped |
| Spec PR ready flip | per `mark_spec_pr_ready_on_kickoff` | the same, on the holder's PR | skipped |
| Spec guards (CI, hooks) | the work repository's | the holder's, if wired | none |
| `/spec-walkthrough` suggestion | made | skipped until the spec PR merges: until then the bundle's changes live only on the spec branch | made |
| Status render (Ready or Active) | `scripts/spec-status.sh <root>/<spec>` | the same, `<root>` as `resolve-root.sh spec` prints it, never the worktree's `bundle` path, which would derive state from the holder; no bundle sits there before its first spec PR merges, and until then it is Ready, since the execution skills find bundles in the root's primary view | the same |
| `/spec-draft` fold-detection scan | every bundle under `<root>` | every bundle under `<root>`, plus the Draft in each open holder spec worktree (`<holder>/.claude/worktrees/<id>-spec`, at the root's place inside it), since a Draft lives only there until its spec PR merges | every bundle under `<root>` |

**`separate-repo`.** The session stays in the work repository and works on
the holder by path. `scripts/spec-store-worktree.sh <spec>` opens the spec
worktree at `<holder>/.claude/worktrees/<spec>-spec` on `planwright/<spec>/spec`:
it reuses one already there, recreates one from a surviving branch (local,
else origin's, then tracking it), or creates both from the holder's
`origin/HEAD`, else from the branch the holder's primary checkout has out.
It prints three lines, each a name, a tab, and a value: `worktree`, `bundle`,
and `branch`. It exits 3 when the root is not in a holder. It exits 4 when
it refuses, among other reasons when the spec branch, its worktree, or (for
a new spec branch) the holder's default branch already holds another
project's bundle of the same identifier (one holder can serve several
projects, so an identifier must be unique across them), a symlink sits on
the bundle path or inside the bundle, a file inside the bundle has more than
one link or is neither a directory nor a regular file (a FIFO, socket, or
device), or the bundle cannot be scanned. A Draft lives only on the spec
branch, so the skills read, validate, and anchor it through the printed
`bundle` path, never the holder's primary checkout; `/spec-walkthrough`
reads the root's primary view, so it shows a holder bundle only once its
spec PR has merged. Before writing, check `git -C <worktree> status
--porcelain` and ask on a dirty tree, as in the work repository. Commit with
`git -C <worktree>`, push with `git -C <worktree> push -u origin
planwright/<spec>/spec`, and give `gh` the holder with `-R` (`gh pr create -R
<holder origin URL> --head planwright/<spec>/spec --draft`, the URL from
`git -C <worktree> remote get-url origin`). The work repository gains no
commit or branch. A holder should ignore `.claude/worktrees/`, as a work
repository does, so the spec worktrees never show as untracked there.

**`plain`.** The skills write the files at `<root>/<spec>/` and create no
spec branch or worktree anywhere. Every commit, push, PR, and ready-flip step
is skipped, and the handoff names each one it skipped. No state file stands
in for git. No spec guard runs on a plain store, since neither CI nor a
commit hook ever sees it, and the authoring handoff says so; the validator
and the anchor tool still run from the session, since they read files.

**The anchor in every posture.** Compute it over the bundle directory
(`scripts/spec-anchor.sh <root>/<spec>`, or the holder worktree's bundle
path) and record it in the namespace form `scripts/spec-anchor.sh
specs/<spec>`: the execution gate reads that form as naming the bundle, and
finds the bundle through the resolver itself, so no machine path enters the
brief. A kickoff recomputing a recorded entry runs it over the bundle
directory the same way, never over the literal `specs/<spec>`.

**Halts while authoring.** A kickoff that degrades to an Awaiting-input
note writes it on the spec branch in `same-repo` and `separate-repo`, as any
authoring write; in `plain` the note is a file like the rest. Execution
halts are different: see below.

## Halt notes in a holder or plain store

A halting `/execute-task` or `/orchestrate` records its Awaiting-input or
Deferred bullet in the bundle's `tasks.md`. In `same-repo` the bullet is
committed on the task branch. A holder or plain store has no task branch, so
`scripts/halt-note.sh` writes the bullet into the store's primary-view
`tasks.md` as an **uncommitted** edit and prints that file's path, which the
handoff names. No execution skill commits, branches, or pushes in the holder.
**Committing the note is the operator's**: in a holder, commit it (or open a
PR for it) when you act on the halt; in `plain` there is nothing to commit,
and the edited file is the record.

## Named observation targets

A session can record an observation into **another** project's accumulator on
the same machine, for a finding that belongs to that project. Name each target
in the `observation_targets` option, a flat map of aliases to roots, usually in
the machine-local or adopter layer since the paths are one machine's:

```yaml
observation_targets: {dotfiles: ~/dev/dotfiles/specs, acme: ~/spec-holder/acme}
```

Then `scripts/obs-record.sh --target <alias> --slug <topic> --scope <repo>
--text '<observation>'` writes the fragment into `<path>/_observations/entries/`.
An alias is a spec identifier. A path is absolute or `~/`, and must be, by
shape, either a directory carrying a valid marker or the default `specs`
root of a git checkout; the target checkout's own config is never read. An
unknown alias, a malformed map, or a misshapen path is refused with nothing
written.

**The hygiene screen.** A routed fragment leaves the project it was written
in, so its scope and text pass a screen first. The screen refuses, never
rewrites, a fragment carrying any of three pattern classes:

- **an absolute path**: a token opening `/<segment>/`, such as `/home/x/`. A
  single segment (`/tmp`) passes, and so does a slash command (`/polish`).
- **a `~` path**: `~/`, `~user`, or a `~` ending the text. A `~` before a
  number (`~400s`) or standing alone in prose passes.
- **a dotted hostname**: a name whose last label is `local`, `internal`, or a
  listed public suffix (`com`, `io`, `dev`, and the rest). Suffixes that double
  as file extensions (`sh`, `md`, `py`) are left off the list, so a file name
  is not read as a host, nor is a name opening right after a dot
  (`.env.local`) or a slash inside a relative path.

The authoritative patterns are in `scripts/obs-record.sh` (the `--target`
header and `screen_class`). Whether a repository name in the fragment is
private is the receiving project's call when it consumes the fragment. No
observation script writes to a remote: a fragment reaches a public surface
only through a human act.

## Guards in a holder

A holder repository runs planwright's spec guards in its own check, the same
four a work repository runs over its root: the validator, the observation
store guard, anchor freshness, and the memory-link check. `/builder` does not
wire them (its catalog carries only universal guards), so copy this task into
the holder's `mise.toml`:

```toml
[tasks."check:specs"]
description = "planwright spec guards over every project root this holder serves"
run = '''
pw=${PLANWRIGHT_ROOT:?set PLANWRIGHT_ROOT to a planwright checkout}
rc=0
for root in */; do
  root=${root%/}
  [ -f "$root/planwright-spec-root.yml" ] || continue
  "$pw/scripts/resolve-root.sh" marker "$root" >/dev/null || rc=1
  "$pw/scripts/spec-validate.sh" "$root/" || rc=1
  "$pw/scripts/check-obs.sh" --obs-dir "$root/_observations" || rc=1
  set --
  for b in "$root"/[!_]*/; do
    if [ -d "$b" ]; then set -- "$@" "$b"; fi
  done
  if [ "$#" -gt 0 ]; then
    "$pw/scripts/check-anchor-freshness.sh" "$root" || rc=1
    "$pw/scripts/check-memory-links.sh" "$@" || rc=1
  fi
done
exit $rc
'''
```

Run it from the holder's top level. `PLANWRIGHT_ROOT` points at a planwright
checkout or release: set it in the holder's machine-local env file
(`mise.local.toml`) for local runs, and in CI check planwright out at the
release you run and export the variable to that path. Wire the task into the
holder's aggregate check and its CI. A root with no bundle yet gets only the
marker, validator, and store checks, since anchor freshness refuses a root
with nothing to anchor. Anchor freshness compares against
`origin/main` by default; pass `--baseline <ref>` when the holder's default
branch has another name.

A `plain` store runs no guards: neither CI nor a commit hook ever sees it.
The validator and `scripts/spec-anchor.sh` still run by hand, since they read
files.
