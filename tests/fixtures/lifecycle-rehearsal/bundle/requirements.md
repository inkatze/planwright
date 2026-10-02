# Rehearsal wedge — Requirements

**Status:** Draft
**Last reviewed:** 2026-10-01
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

Rehearsal input only. This bundle carries no real work: the lifecycle
rehearsal (`tests/rehearsal-lifecycle.sh`) copies it into a throwaway
repository under a temporary directory and dispatches a worker against it, so
the dispatch has a real spec to name. It lives under `tests/fixtures/` so
`/orchestrate` and the status render never see it, and it stays a Draft so a
copy that strayed into a spec root would still be refused.

## REQ-A — Rehearsal

- **REQ-A1.1** A worker dispatched against this bundle SHALL do nothing but the
  one command its rehearsal prompt names.
  *(Cites: D-1.)*
