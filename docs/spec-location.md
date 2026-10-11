# Spec location

Spec bundles live under the **spec root**: `specs/` at the top of the work
repository by default, or the directory the `spec_root` option names (see the
[options reference](options-reference.md)). That directory may sit elsewhere in
the repository, in a separate **holder** repository, or in no repository at
all. The root's git relationship to the work repository is its **posture**,
defined in [`storage-classes`](../doctrine/storage-classes.md) (*The posture
ladder*): `same-repo`, `separate-repo`, or `plain`.

## Finding the root

Nothing composes the root by hand. `scripts/resolve-root.sh` answers:

- `resolve-root.sh spec` prints the root as the current checkout sees it.
- `resolve-root.sh spec --primary` prints the primary view: the primary
  checkout's copy, the holder's, or the plain directory.
- `resolve-root.sh spec --posture` prints the posture.
- `resolve-root.sh --explain spec` names the config layer that set the root.

A configured directory other than the default must carry the marker file
`planwright-spec-root.yml`; without it the resolver refuses the directory and
never falls back to `specs/`. `resolve-root.sh spec --init` writes the marker
(and, in a git repository, the ignore rules for the root's local-only
entries) into a directory that already exists. `/spec-draft` offers to run it
when it meets a marker-less root.

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

**`separate-repo`.** The session stays in the work repository and works on
the holder by path. `scripts/spec-store-worktree.sh <spec>` opens the spec
worktree at `<holder>/.claude/worktrees/<spec>-spec` on `planwright/<spec>/spec`:
it reuses one already there, recreates one from a surviving branch (local,
else origin's, then tracking it), or creates both from the holder's
`origin/HEAD`, else from the branch the holder's primary checkout has out.
It prints three tab-separated lines, `worktree`, `bundle`, and `branch`, and
exits 3 when the root is not in a holder. It exits 4 when it refuses, among
other reasons when the spec branch or its worktree already holds another
project's bundle of the same identifier (one holder can serve several
projects, so an identifier must be unique across them) or a symlink sits on
the bundle path. A Draft lives only on the spec
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
halts are different: in a holder or a plain store they land as uncommitted
files, written by `scripts/halt-note.sh`.
