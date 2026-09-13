# Tower-comms scorecard fixtures

Each `<name>.log` is an event log in the shape `scripts/tower-queue.sh log`
writes, and `<name>.expected` is the scorecard `report` must reproduce over
it, computed by hand from the lines. The report's `--now` for each fixture
is recorded beside the arithmetic below; the window is the default seven
days and the tick-gap bound the default ten minutes unless a test overrides
them.

`dropped_lines` counts the lines `log` dropped at a lock-wait expiry, read
from an `events.dropped` file beside the log; no fixture ships one, so it is
zero throughout. `malformed` is the whole file's count rather than the
window's, a line that will not parse carrying no timestamp to place it.

Fleet hours come from the tick lines alone: a tick's `[ts, until]` span
counts when its `live` count is above zero, the stretch from one tick's
`until` to the next tick's `ts` on the same tower counts when the earlier
tick was live and the stretch is within the gap bound, a longer stretch is
excluded and reported as a gap, and the per-tower intervals are unioned so
two towers ticking through the same hour count it once.

## baseline (`--now 908000`)

One tower. Live spans: `900000..903600` (3600 s), `905400..907200`
(1800 s), the 300 s bridge to the tick at `907500`, and `907500..907800`
(300 s); the idle tick at `903600` adds nothing. 6000 s is 1.67 hours.
Two items reached the operator (`q1`, and one prose delivery with no queue
record), 1.20 per fleet hour; one item settled without them, 0.60 per fleet
hour. Blocked-worker wait: `q1` waited 700 s from birth to acknowledgement,
`q2` is still open at 700 s, so 1400 s total, 700 s at most, one open. One
delivered turn carried two asks. One reply asks what a name means, and one
request is repeated (the third-last and last replies, after case folding).
Delivered text carries one spec identifier (`REQ-A1.4`), one internal name
(`fleet-state.sh`), and three listed terms (reconcile, sweep, anchor). One
item was dropped at a rebuild.

## two-tower (`--now 906000`)

Two towers whose live spans overlap: `900000..903600` and
`901800..905400` union to `900000..905400`, 5400 s, 1.50 hours, not the
7200 s a plain sum would give. Two items delivered, 1.33 per fleet hour.

## gap (`--now 905000`)

One tower with two live spans of 600 s each and a 3600 s stretch between
them, longer than the ten-minute bound: the stretch is one reported gap of
3600 s and the denominator is 1200 s, 0.33 hours; one delivered item is
3.00 per fleet hour.
