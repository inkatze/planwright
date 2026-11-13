# Readiness gate notes

The readiness walk for this program follows the readiness-check duty's
design; read it at its source,
[mission-control design, D-25](../../../../../specs/mission-control/design.md),
rather than here.

Local notes:

- The forge's checks run on the merge ref, so a green head alone is not
  enough here; compare against the merge ref's run.
- The operator prefers the packet ordered by risk, highest first.
