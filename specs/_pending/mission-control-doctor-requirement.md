# Seed brief: amend `mission-control` with a requirement for the doctor audit

Captured 2026-11-09 while shipping the two drift checks in `mc-config.sh
doctor`. No signed requirement names `doctor` today: it shipped as a flight fix
(#875), and the nearest owner is REQ-A1.2 (bring-up). Waiting on the
operator's sign-off.

Suggested invocation, from a fresh session in the planwright repo:

    /spec-draft --extend mission-control

## The requirement to add

Bring-up and every successor's self-check SHALL audit what the program runs
on that is not planwright's default, read-only, and report it as findings the
operator settles. The audit SHALL cover:

- a knob a layer sets away from its shipped value, a default duty left off,
  a launch on another rung than the knob, and a cron line touching the
  program (shipped in #875);
- a standing rule whose text names a number for a knob it governs (the
  knob's name followed by a value, or a handover at a context percent) when
  the knob's effective value differs;
- a local-layer override whose comment or value carries a date already past,
  or the word interim, temporary or until with no date still ahead.

The audit SHALL never edit a layer or a rule; each finding names where the
value is set (the file, or the layer for a rule), the knob, the rule or comment
and the effective value, in plain words.

## Why

A rule saying mission control hands over at 40% context sat beside the shipped
70 with nothing flagging it, and a dated fleet-size bump in a machine-local
layer outlived its comment. Both are drift the operator only found by hand.
