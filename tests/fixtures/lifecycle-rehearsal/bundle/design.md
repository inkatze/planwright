# Rehearsal wedge — Design

**Status:** Draft
**Last reviewed:** 2026-10-01
**Format-version:** 2
**Execution:** derived — see the status render

### D-1: The bundle is inert input

**Decision:** The bundle exists only so a rehearsal dispatch names a real spec;
nothing in it is meant to be built.

**Alternatives considered:**
- Dispatch against a real bundle. Rejected because: a rehearsal worker would
  then be able to change real work.

**Chosen because:** an empty bundle cannot be advanced by accident.
