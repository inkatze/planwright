# Orienting an idea with `/inception`

`/inception` is the stage before `/spec-draft`. It takes a product-level idea
that has no repository yet (a pitch, a gap analysis, a page of notes) and gives
it a durable orientation: a **venture repository** holding an **inception
bundle** of the problem, the disciplines and people it touches, the beliefs it
rests on, the decisions still open, and the plan for testing them. It never
writes a spec, never invents the pitch, and never starts a downstream skill:
taking a track to `/spec-draft` is your act.

This guide is for adopters. The normative definitions live in doctrine:
[inception-format](../doctrine/inception-format.md) owns the bundle,
[persona-fanout](../doctrine/persona-fanout.md) the persona table,
[venture-task](../doctrine/venture-task.md) the validation-task contract, and
[evidence-quality](../doctrine/evidence-quality.md) the evidence ladder. The
skill itself is [`skills/inception/SKILL.md`](../skills/inception/SKILL.md).

## The venture lifecycle

1. **Start.** `/inception <idea or seed path>` checks the environment, asks
   once where the venture lives (below), creates the repository under
   `ventures_root`, and scaffolds its hygiene guards.
2. **Elicit.** A phased conversation: seed intake, the opportunity, the
   discipline walk with its staffing and stakeholder map, a reframing
   checkpoint, the minimum core (success metric, kill criteria, blocking
   assumptions, open forks), the validation plan, and a closing check that
   validates the bundle and resolves what it finds. The skill drafts every
   entry for you to judge; a prompt that does not apply is skipped with a
   written reason, never silently. Every phase ends with a save.
3. **Resume.** `/inception <venture-id>` picks up at the first unfinished
   phase, confirming what is already settled from the bundle itself.
4. **Validate.** Each `T-<n>` task in the plan runs under the venture-task
   contract: a findings document committed to the venture, no pull request
   unless you ask for one on a remote-backed venture, and register updates
   applied only when you accept the findings. Agents run spikes, research,
   and analysis; demand-signal and alignment tasks are
   prepared for a person to carry out, because no agent contacts anyone
   outside the session.
5. **Look across ventures.** `/inception` with no argument lists every
   registered venture with its attention flags (a tripped or approaching kill
   date, unresolved blocking assumptions, open forks, age past appetite) and
   the catalog's health. `/inception status <venture-id>` is one venture's
   view.
6. **Decide.** A venture's status moves only through a gate outcome or your
   declaration; the statuses and the transitions between them are in
   [inception-format](../doctrine/inception-format.md#venture-lifecycle).

**Not in this release:** the skill's gate, export, and publish modes, the
graduation hand-off into `/spec-draft`, the Notion adapter, and the Cowork
sync bridge. Asked for a gate, export, or publish mode, the skill says it is
not in this release; it never improvises a gate record or an export those
layers own. The renderer and the publish helper below already ship: the
pre-commit hook drives the renderer, and you can run either script directly.

## Where a venture lives

The skill asks once per venture, with nothing pre-selected:

- **Private remote repository**, offered only when the host can create one.
  Saves are shared to it once the minimum core is recorded. Choosing it is
  your confirmation for both the repository and the pushes.
- **Local-only repository.** Nothing leaves the machine.
- **No durable home for now.** A scratch directory, warned as session-only.

The home degrades rather than fails: a git repository, then a plain folder
when git is missing, then session-only when the filesystem will not outlive
the session (a cloud session). Every degradation is said before the first
question and again at hand-off. A local venture can move to a private remote
later without losing its history (`inception-venture.sh add-remote`).

## Non-engineer and expert modes

The skill also asks once how saving should look. Both modes work on the same
repository, so a venture can change hands between them.

- **Handled for you.** Every save is reported in plain words ("saved",
  "saved here but not shared") and no turn uses git vocabulary. This is the
  mode for a founder, a product lead, or anyone who should not have to learn
  git to keep a durable, reviewable record.
- **Standard git.** Saves report as commits and you may use git directly. The
  scaffolded pre-commit hook runs on your own commits too: it blocks a staged
  credential, warns on bundle findings (set `PLANWRIGHT_VENTURE_STRICT=1` to
  make them block), and regenerates the exports into the same commit.

The repository `/inception` creates is wired already; any other clone needs
`git config core.hooksPath githooks` once before the hook runs. The
scaffold's `hygiene-wiring.md` in the venture says so and records what else
was wired.

## Stakeholder surfaces

The bundle is the source of truth; everything a stakeholder reads is derived
from it.

- **Exports.** `exports/venture.html` is the dashboard (gate readiness,
  blocking assumptions, kill criteria, open forks, then the record behind
  them); `exports/pitch.html` is the narrative for someone deciding whether to
  back the venture. Both are deterministic, self-contained, offline pages,
  regenerated by the pre-commit hook in the commit that changes the bundle.
  If the render or the staging fails, the hook warns and lets the commit
  through, so that warning means the exports may lag the bundle.
- **Publishing a page.** `scripts/inception-publish.sh` decides whether to
  ask and never publishes itself; the session holding the publishing tool
  acts. A first publish is always offered for
  your confirmation, and so is every later one unless this machine has
  auto-republish on for the venture (below) and that page's first publish is
  on record. A page that looks like it carries a
  credential is never offered.
- **The GitHub web path.** On a private-remote venture a stakeholder can read
  and edit the bundle in the GitHub web UI. The scaffolded
  `.github/workflows/venture-guard.yml` scans for secrets and validates
  each change against the version before it, so a web edit that mangles an identifier, breaks the
  structure, or rewrites a recorded gate run fails CI, while ordinary prose
  edits pass. The workflow ships pinned to action tags and planwright's
  default branch; `hygiene-wiring.md` explains how to pin it to commit SHAs
  if the venture wants the stricter posture.

## The persona layer and its boundaries

When the discipline walk staffs a discipline with an `agent-persona`, the
reframing checkpoint closes with a fan-out: a few independent seats, each
briefed from a discipline card and the venture's frame, read the venture in
parallel; one persona-free writer merges them blind; one persona-free
challenge tests the merge. You see the result at two gates in the main
conversation: Gate 1 shows the frame, the seats, the backend, and the cost
before anything spawns; Gate 2 puts each escalated item to you as a forced
choice among the powers you hold over it (disregard, override, reverse,
halt).

What the layer will not do:

- **Decide a human-authority call.** Price commitments, legal or tax
  readings, decisions about people, and one-way doors are recorded as open
  decisions with their door marked, for a person to make.
- **Count as evidence of demand.** Anything a seat produces enters the
  assumption register at no better than the `synthetic` grade, which never
  counts toward graduating a value or usability assumption.
- **Pretend to cover a discipline it cannot.** A discipline with no card is
  `unstaffed` and filed as a coverage risk; a venture with no persona row runs
  zero-seat, which is a valid outcome.
- **Wear an identity.** Cards are task framings with no backstory,
  credentials, or seniority styling.
- **Let seats talk to each other or to you.** Relay runs orchestrator-to-seat
  only, on every rung.

The core cards live in [`cards/`](../cards/); a team or company card is
overlay content added through the `discipline-cards` catalog
([discipline-cards](../doctrine/discipline-cards.md#where-cards-live)), and
new non-engineering decision domains extend the `decision-domains` catalog the
same way. Neither needs a core edit.

## Settings, and which side of the boundary each is on

Each setting this stage introduces splits on the
[capability-vs-style boundary](../doctrine/customization-boundary.md): the
mechanism ships in core with a safe default, and the value is yours, set in
the layer whose reach fits it. Full resolution rules are in the
[options reference](options-reference.md#inception-settings-outside-the-config-layers).

| Setting | The capability (core) | The value (yours) | Default, and why it is the safe one |
| --- | --- | --- | --- |
| `ventures_root` (config key) | A configurable home for venture repositories, resolved through the overlay layers | Where your ventures live; a path on one machine, so usually machine-local or adopter, and repo-tracked only for a team that shares a layout | `~/ventures`: outside every work repository, so a venture never lands inside one |
| Auto-republish (per venture) | Replacing an already-confirmed published page with its refreshed export without asking again | Whether this venture, on this machine, republishes without the question; set with `inception-publish.sh auto on\|off` | Off: every publish is offered. Stored in the clone's git directory, never in a tracked file, so a stakeholder's commit cannot switch publishing on |
| Persona seat backend | None new: seats dispatch through the existing [backend capability contract](../doctrine/backend-capability-contract.md) (subagent, tmux, print, or in-session) | Which rung a run uses, fixed when the seats are rostered and disclosed at Gate 1; a per-seat model only on the `subagent` rung | The rung the host can run; a weaker rung is reported as a degradation, never hidden |
| Discipline cards and decision domains | The catalogs and their four-layer merge | Your team's or company's own cards and domains | The core cards and domains only |
| Registry home (`PLANWRIGHT_INCEPTION_DATA_DIR`) | A machine-local registry, telemetry, and feedback drop | A different directory on this machine | Under `CLAUDE_PLUGIN_DATA`; without either, the elicitation runs without the registry and says so, while the portfolio and status views report it unavailable |
| `PLANWRIGHT_INCEPTION_EPHEMERAL`, `PLANWRIGHT_VENTURE_STRICT`, `PLANWRIGHT_SECRET_SCREEN_TOOL` | Ephemeral-session detection, strict bundle validation in the hook, whether the secret screen uses gitleaks (the built-in screen always runs as the floor) | A per-session or per-machine override | The probe's own reading, warn-only validation, and `auto` |

The adapter seam and its Notion reference adapter land in a later release;
whatever settings they need follow the same split.
