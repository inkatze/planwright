# Release-tagging policy

Cutting a release is a recurring ritual that, left to memory, fires only when a
human remembers to bump a version and push a tag. That is exactly the ceremony
gap the [autopilot reflex](autopilot-reflex.md) exists to close, so release
tagging is its first runtime instantiation. This note states the policy the
reflex produces for planwright's own release loop and for any adopter who
scaffolds the same machinery: what is automated, where the human gates sit, and
which altitude each shipped piece lives at. It is policy, not procedure; the
concrete scripts, workflows, and config knobs that implement it are cited here
by name and defined in their own tasks.

Citations: autopilot-reflex REQ-B1.1, REQ-B1.2 · autopilot-reflex D-2, D-3,
D-5, D-7, D-13.

## The five policy points

Each point is one reflex step applied to the release ceremony; together they
close the gap without crossing a human gate.

1. **Detection and proposal are automated.** Releasable changes are detected
   from conventional commits and surfaced as a standing, automatically
   maintained release PR that bumps the version source of truth and updates the
   changelog (release-please in PR-only mode, `D-3`). Editing the PR corrects
   the proposal, closing it cancels, and no human has to initiate it for the
   proposal to exist. This is reflex steps 2 and 3: the machinery carries the
   work to the gate's edge, and the remaining human act is a response to a
   standing artifact, never a ritual recalled unprompted.

2. **Approval is the human merge of the release PR.** Merging the release PR is
   the release approval, and it stays a human act in GitHub's UI (`D-5`). No
   planwright command, script, or skill merges it. This is reflex step 1: merge
   is a named, conscious, reserved gate, and reusing the merge the human already
   exercises everywhere else keeps the gate bright-line and its enforcement
   trivially checkable (no merge call sites exist).

3. **Publish is human-gated and signed per repo policy.** Tagging and creating
   the GitHub Release happen only through the publish step, run consciously by
   the human after the merge, never by CI. The tag is an annotated tag on the
   observed release-merge commit and is signed when the repo configures signing
   (the policy value, not a capability the framework hardcodes). CI automation
   creates no tags or Releases: the release PR is proposal only.

4. **The untagged window is locked by forcing-function.** From the moment a
   version bump lands on `main` until its tag is published, a required CI check
   fails and names the publish command in its output, blocking further merges
   until the publish runs (`D-7`). This is reflex step 4: the pending act is
   pushed to the human by a red required check rather than left to a dashboard
   they must remember to poll. The lock closes the forget-window; publish
   correctness does not depend on it (the tag lands on the true release commit
   under any interleaving regardless).

5. **Merge and publish are never performed autonomously.** The two irreversible,
   externally-visible acts, approving the release (merge) and cutting the signed
   tag and Release (publish), are always conscious human acts. planwright
   automates everything up to them and nothing through them: no auto-merge, no
   background auto-sign, no timeout-approval, no bypass flag. This is the reflex
   step 1 and 2 bright line, the carried never-auto-merge invariant left
   absolute and unrefined.

## The altitude split

The reflex's step 5 places each piece of the solution at its right altitude, so
that a repo-local mechanism is never promoted into core doctrine and a general
capability is never buried in one repo's script. The
[capability-vs-style boundary](customization-boundary.md) is the rule this
split applies (`D-13`): the boundary runs *through* the release feature, not
around it. The capability (the ability to publish) is general and lands in core;
the mechanism (a particular GitHub-Actions wiring) is per-repo and ships as an
opt-in template; the value (whether to require signing, where the version lives,
which scheme) is configuration.

| Altitude | Pieces | Home |
| --- | --- | --- |
| **Capability** (general, core) | The publish script (`scripts/release-publish.sh`), the release-pending comparator (`scripts/release-pending.sh`), and this doctrine | Ships in planwright core |
| **Mechanism** (per-repo, opt-in template) | The release-please PR-only config, the untagged-window lock workflow, and merge serialization (merge queue / require-up-to-date) | Scaffolded into an adopter repo only through the guard catalog's opt-in consent flow, never auto-landed |
| **Value** (configuration) | `require_signed_tags`, `version_file`, and the versioning scheme (SemVer for planwright, `D-9`) | Config knobs and overlay values, defaults preserving existing behavior |

Reading the table top to bottom is reading reflex step 5 in practice: the
publish capability is core because any adopter shipping a versioned artifact
plausibly wants it; the GitHub-specific mechanism is a template because forcing
a third-party action and a write-token posture on every adopter would push
mechanism up to capability altitude; the signing and version-file choices are
values because they are one repo's taste riding the shared capability. A piece
promoted or demoted from its row is the drift this note exists to prevent.
