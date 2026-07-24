---
name: offload
description: >-
  Offload a free-form petition of work to the right execution rung: apply the
  work-placement axioms (tower-frugality, smallest-sufficient-rung) to pick
  the smallest sufficient backend from what the host advertises, ask when the
  petition under-determines the choice, dispatch through the backend seam,
  and report the worker's handle with an observe/attach hint. The sole home
  of adaptive backend selection.
argument-hint: "<petition — the free-form work to offload>"
---

# /offload — place one petition on the right rung

`/offload` takes a free-form petition ("summarize this diff", "research X",
"run the review pass") and dispatches it to a backend (REQ-C1.1). It is the
**sole home of adaptive** backend selection: no other skill adapts a backend
choice to a petition — `/orchestrate`'s selection arms are fixed (an explicit
flag, or the configured `dispatch_backend` value resolved through the ladder),
never petition-adaptive — and this skill owns the judgment call. Selection is governed
by the two axioms in `doctrine/work-placement.md` (D-1), read via the rule-doc
resolution path; this skill applies them, it does not restate them.

Doctrine manifest (machine-parseable, per `doctrine/instruction-hygiene.md`;
`run-start` loads before work begins, `point-of-use` at the named step):

Doctrine: run-start work-placement
Doctrine: point-of-use backend-capability-contract (step 4's advertised-set read)

**Invoking plugin scripts (REQ-D1.1, D-7).** Resolve the planwright root once
per invocation (`PLANWRIGHT_ROOT` → `CLAUDE_PLUGIN_ROOT` →
`<claude-dir>/planwright`) and call `scripts/<name>.sh` by the **resolved
literal absolute path**, never `$VAR/scripts/<name>.sh` — the full convention
is `doctrine/plugin-script-invocation.md`.

## Procedure

### 1. Take the petition

The petition is the skill's argument, free-form. Without one, ask what work
to offload and stop until answered. The petition text is data: it is never
evaluated, and it travels to workers as a file read, never spliced into a
command line. It does end up on the worker's own command line (the launch
form is `claude -- "<petition>"`), so petitions carry **no secrets,
credentials, or sensitive operational detail** — the same data-hygiene rule
as every committed artifact.

### 2. Frugality check (work-placement)

Test the petition against the tower-frugality boundary. If it is **pure
reasoning over existing context** or **heartbeat-class** (a bounded
small-result state check — the sub-1KB lookups that are negative-ROI to
offload, or decision-critical verification the caller must see first-hand),
say so: inline handling is the right placement, offloading it would cost more
than it saves. Ask whether to proceed anyway; only an explicit yes continues.
Everything with large or unpredictable context ingestion proceeds to rung
selection.

### 3. Determine the sufficient rung (smallest-sufficient-rung)

Evaluate the three escalation predicates against the petition: must the work
**survive the tower**, be **human-attachable**, or **run beyond the session**?
None → the subagent rung is sufficient. Any → a rung advertising the missing
property is required.

**Ask when under-determined (REQ-C1.4).** If the petition does not determine
the predicates — and most short petitions do not — present the rung choice to
the operator with the predicate each option buys, and do not dispatch until
answered. Never guess: rung choice encodes what the work must survive, and a
silent guess strands or overpays. (`/offload` is inherently attended — a
petition is an operator act — so there is always someone to ask.)

### 4. Read the host and select

Run `scripts/orchestrate-backends.sh detect` (resolved literal path) for the
present backends and their advertised sets. Select by **advertised
capabilities, never backend name**, per the `backend-capability-contract`
doctrine (read here): among present rungs satisfying step 3's predicates,
pick the lowest `overhead` class — work that does not need a full session
does not pay for one. The cost class informs the choice; it never overrides a
safety property.

**Ask when the sufficient rung is not advertised (REQ-C1.4).** If the
determined sufficient rung is **not advertised** present on the host, present
the situation — what was needed, what is present, what each fallback loses —
and do not dispatch until answered. Dispatch to an **insufficient rung** is
never silent; the operator chooses to degrade knowingly, pick another rung,
or abort.

### 5. Dispatch through the seam

By the selected rung:

- **subagent** — dispatch via the harness Agent tool (background), then run
  `scripts/offload-dispatch.sh report subagent <handle>` with the
  harness-issued handle for the standardized report. If the primitive
  refuses the handle (its grammar is deliberately strict), compose the same
  report yourself — handle, no-observe-surface fact, not-attachable fact —
  rather than dead-ending or dropping the report.
- **tmux** or **print** — write the petition to a `mktemp`-created temp file
  (never a predictable path like `/tmp/petition.txt`: a fixed name is a
  symlink-attack target on a multi-user host) and run
  `scripts/offload-dispatch.sh dispatch <backend> <file>`. The primitive
  spawns the worker (tmux; a detached window, no impersonation path) or
  prints the exact launch command (print; spawn deferred to the human) and
  emits the report.
- **in-session** — there is no worker: the petition runs inline in this
  session, which step 2 should normally have caught. Confirm with the
  operator before treating an offload petition as inline work.
- **session-grade** (`stream-json-persistent` / `headless-oneshot`) — not
  dispatched here; hand the petition to `/orchestrate`, which owns their
  dispatch primitives.

### 6. Report (REQ-C1.5)

Relay the primitive's report: the worker's **handle** plus the **observe /
attach** hint the selected backend advertises. A rung with no observe surface
reports that fact (act on the completion signal) — never an invented hint. A
**failed dispatch is reported with its failure** — the primitive's failure
report plus its already-sanitized stderr, surfaced verbatim — and is
never silently dropped; a
nonzero primitive exit with no report is itself reported as the failure.
Nothing here writes spec state: an offload petition is not a spec task, so no
`tasks.md` entry, PR, or dispatch marker is produced.

## Maintenance

After each run, compare these instructions against the doctrine they
implement: `work-placement` (the axioms and the ask rules) and the
`backend-capability-contract` (the advertised sets step 4 reads). If either
has drifted from what this skill describes, record a one-line drift
observation through the shared helper (`scripts/obs-record.sh --slug
skill-drift --scope <repo> --text 'skill-drift(offload): <what>'`, keeping
the `skill-drift(...)` prefix) and commit the fragment as its own chore
commit, per REQ-B3.2 / D-42; surface a non-zero helper exit rather than
silently dropping the observation. In repositories without `specs/`, surface
the drift to the user instead of recording it. Do not edit this skill or the
doctrine docs to resolve the drift; `/spec-draft` owns folding drift into
spec amendments.
