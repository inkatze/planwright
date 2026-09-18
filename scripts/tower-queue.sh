#!/bin/sh
# tower-queue.sh — the operator queue's script (tower-comms). Three parts:
# the event log (`log`), the scorecard computed from it alone (`report`), and
# the queue store with its verbs (`add`, `list`, `next`, `ack`, `shelve`,
# `settle`, `catchup`, `counts`) — D-2 to D-6, D-8, D-14, D-18; REQ-A1.1 to
# REQ-A1.9, REQ-B1.1 to REQ-B1.5, REQ-C1.1, REQ-C1.2, REQ-C1.5, REQ-C1.10,
# REQ-C1.11, REQ-F1.4, REQ-G1.1 to REQ-G1.8, REQ-H1.2.
#
# THE STORE. `<home>/tower-comms/queue`, one tab-separated record per item,
# the index and delivery state only: the content lives where its kind already
# does (a worker's question or a piece of news in the attention store row, a
# request, an approval or a standing decision in a file under a declared
# root) and is written there BEFORE the record that points at it — `add`
# refuses a pointer at nothing. The record's fields, every one validated
# against its grammar before a write and sanitized on the way out:
#
#    1 id          i + 8 hex, derived from the content home's key (below)
#    2 kind        question | approval | request | news | standing
#    3 urgency     high | normal | low (a worker question inherits its row's)
#    4 origin      the source worker's handle, or the operator's turn
#    5 born        epoch
#    6 home        attention | path
#    7 pointer     the worker handle (attention) or a relative path (path)
#    8 instance    the row's instance id (a question), its state.stamp
#                  (news), or -
#    9 root        the canonical absolute root the path pointer and the park
#                  path are under, or - (never part of an attention item's
#                  identity)
#   10 park        a second relative path under that root (the Awaiting-input
#                  bullet of a parked question), or -
#   11 closes      the human action or the evidence that closes the item
#   12 state       open | closed
#   13 knocked     epoch of the last knock naming it, or 0
#   14 delivered   epoch of the last hand-over, or 0
#   15 acked       epoch of the acknowledgement, or 0
#   16 shelved     epoch the shelve returns at, or 0
#   17 settled     epoch it settled, or 0
#   18 settled_by  what settled it, or -
#   19 lease       the holding tower's identity, or -
#   20 lease_until the lease's backstop expiry, or 0
#   21 subject     the subject key the settling pass and the pairing rule
#                  join on: worker:<handle>, pr:<n>, branch:<name>,
#                  ledger:<key>, or -. `add --subject` sets it; with none it is
#                  derived as the worker the item came from, so most items
#                  carry one and can be paired or settled by a worker fact
#   22 away        1 when the item settled while no tower conversation had
#                  the operator present, else 0 (REQ-B1.4)
#   23 sources     the origins merged into this item, comma-joined, or -
#   24 held_by     the tower holding the lease when the item settled, or -.
#                  Settling is evidence-driven and never asks a conversation,
#                  so an item can close under a tower that was holding it;
#                  this is how the catch-up tells that tower so rather than
#                  leaving it to find a closed record.
#
# A record written before any of the last four fields shipped is completed on
# read (subject -, away 0, sources -, held_by -) and rewritten by the next
# locked verb, so an older store is never stranded.
#
# The identifier is derived from the content home's key (kind, home, pointer,
# and for news the row's instance, for a path item its root), so an `add` of
# content already queued is a no-op that prints the existing id, content
# queued again after its item closed re-opens that same item, and a rebuild
# from the content homes mints the same ids the lost store held. Closing
# conditions and settle reasons pass the same secret-shaped redaction the
# log applies, since the store is rendered back into the conversation. A closing condition that promises
# an automatic step is refused: it names the human action (an answer, a
# go-ahead) or the evidence that settles the item. A standing decision is
# registered like any other item and is the one kind `next` never ranks or
# hands over; its closing condition is the operator revoking the rule.
#
# Every write rides the fleet advisory lock, bounded by `tower_hook_lock_wait`
# and reported as an error at expiry rather than written unlocked, and lands
# by same-directory temp and atomic rename after the store is re-read and
# compared with the copy taken on entry: the lock carries no holder token, so
# a store that changed under it is the signature of a broken lock and the
# write is refused. The lock is held for the read, the in-process rewrite and
# the rename only; the event-log line each verb owes is appended AFTER the
# lock is released, through the `log` verb's own critical section. Retention
# runs inside every write: the open items are kept whole and the closed ones
# (acknowledged or settled) only the most recent `tower_catchup_limit` of
# them, the catch-up's own horizon (the history beyond it is the event
# log's, REQ-A1.5); every locked verb commits what the derived pass changed,
# whatever its own outcome.
#
# ATTENTION AND THE LEASE (`next`). `next` hands over at most one item per
# call, ordered by consequence: questions (blocked workers) before approvals
# before the operator's requests before news, then urgency, then age. It is
# knock-first, enforced here rather than by instruction: the only thing that
# confirms attention is the per-tower marker file the prompt-submit hook
# writes at `<home>/tower-comms/attention/<tower>` — one line holding the
# epoch of the operator's last reply, owner-only, written lock-free by the
# hook alone, by same-directory temp and rename so a reader never sees a
# torn value. Per tower, `<home>/tower-comms/delivery/<tower>` records the
# last knock and the last hand-over as one tab-separated line: knock epoch,
# the item it named, hand-over epoch, the item it handed. Attention is
# confirmed when the marker shows a reply at or after the last knock, later
# than the last hand-over, and within `tower_quiet_interval` (a knock of the
# tower's own opens the session: a marker with no knock on record confirms
# nothing, and one reply releases one item);
# then `next` hands over the item the knock pinned (or the top item when the
# top has not been pinned) and stamps the hand-over, printing one line:
# `item`, id, kind, urgency, the origins (the source, plus any merged into it,
# comma-joined), age in seconds, the content pointer
# (`attention:<worker>[@instance]` or `path:<root>/<rel>`), the park path
# or -, and the closing condition, tab-separated. With attention unconfirmed
# it prints the knock line — `knock`, kind and urgency of the top item, and
# how many items are waiting for this tower, tab-separated — when a knock
# is due: nothing is outstanding, the last hand-over has gone unanswered
# past the quiet interval, or the top item changed since the knock (the
# lease that knock pinned goes with it). While a knock or a hand-over is
# outstanding it prints nothing at all, and never repeats the knock on a
# schedule; the away re-knock on worsening is the delivery task's. A
# marker that never appears is reported on stderr after the first knock
# rather than knocked at forever.
#
# The item handed over is leased to the calling tower under the lock, at
# the knock (which pins it) and at each hand-over. Another tower skips a
# leased item. The lease is released by acknowledgement, shelve and
# settling, and expires at `tower_lease_interval` only as a backstop; it is
# renewed by the holder's replies (the holder's marker plus the interval
# extends it, read at each pass, so the hook writes nothing here) and may be
# preempted by a tower whose attention is confirmed while the holder's
# operator is away (no reply there within the quiet interval; a holder whose
# marker has not appeared counts as present for one quiet interval after
# its own last knock or hand-over): the other tower knocks about the item
# without taking the lease, and takes it over on the reply that confirms
# its attention. `tower_lease_interval` below `tower_quiet_interval` is
# refused: an attended conversation must never lose the item it is holding.
# A delivered item stays out of the caller's own candidates while its lease
# lives (it is in hand); when the lease lapses the hand-over is void and the
# item is a candidate again for every tower, which is the one redelivery the
# loss budget allows. The tower's identity is the `--tower` flag, else
# PLANWRIGHT_TOWER_ID, else PLANWRIGHT_TOWER_SESSION_ID (a UUID, the presence
# surface's own identity form; a value that is no UUID is refused, not
# skipped), else PLANWRIGHT_TOWER_PID (a positive integer, likewise refused
# when malformed) resolved through the presence script into the composite
# identity the tower published under, else a session-scoped fallback minted
# from that pid (or, last, the invoking shell) and its start time, written
# into the lease record so a later reader can tell whose lease it is.
#
# A record pointing at an attention row is checked against the row at every
# pass: a question whose row re-forked has its instance id and urgency
# refreshed; one whose row is no longer awaiting input, or whose row is gone,
# is not handed over (the settling pass closes it with the reason). A store,
# a marker or a delivery file that cannot be written is an error in the turn
# (exit 6); the one fail-open case is the `delivered` log line, whose failure
# is reported while the hand-over stands (REQ-C1.11).
#
# `ack <id>` closes an item and never releases the next; it is refused (exit
# 1, a `refused` line logged) when the caller holds no lease on it and is a
# logged no-op on a closed item. `shelve <id>` parks an item until
# `tower_shelve_return` (or `--for`), releasing any lease, and never drops
# it; it is refused the same way when another tower holds the lease. `settle
# <id> --reason` closes one item on evidence, naming what settled it; `settle`
# with no id runs the level-triggered pass below. Every locked verb applies
# the derived part — shelve returns, lease expiry, pointer refresh — before it
# acts. `list`
# prints every open item and never a settled one (`--all` adds the closed
# ones the store still keeps): id, kind, urgency, origin, birth epoch, a
# state of open / delivered / shelved / leased:<tower> / closed, the content
# pointer, and the closing condition. `counts` prints the open, unshelved
# count per kind, the total over the ranked kinds, the top item's kind (what
# the status line's `waiting` field reads), the number of store lines that
# do not parse, and whether the store is present. Both are lock-free reads.
#
# THE SETTLING PASS (`settle` with no id) — D-5, REQ-B1.1 to REQ-B1.5,
# REQ-F1.4, REQ-H1.2. Level-triggered: every pass re-evaluates every open
# item's closing condition against the evidence available NOW, never a stream
# of events since the last pass, so an item whose condition was met before the
# previous pass still settles. One pass serves a whole tower-loop iteration:
# it stamps `settle.stamp` with a key over everything it read — the evidence
# stamp, the normalised table and the attention-store fields it settles and
# merges on — and the `next` that follows reuses that pass instead of running
# its own. Any of those moving is a pass `next` has not run, so it settles
# first and a lone `next` is never stale.
#
# Evidence is gathered OUTSIDE the lock — it is read from a file the caller
# has already derived, never polled here — and the lock is taken for the
# writes alone; `Q_SETTLE_HOLD_BOUND` states the bound the hold is measured
# against, which the pass reports as its `held` line and warns past on stderr.
# Nothing aborts a long hold — the bound is reported, not enforced. Two sources:
#
#   * The worker attention store, read directly: a row that is GONE is a
#     content home that vanished and settles its item with that reason; a row
#     still present whose claim field (the 11th, `fleet-attention.sh claim`'s
#     first-answer-wins label) is set settles it as answered by another route.
#     A row that merely moved on — a heartbeat, a completion or success the
#     worker reported of itself — is a CLAIM, not evidence, and settles
#     nothing (REQ-B1.2).
#   * `<surface>/evidence` (or `--evidence <file>`; a path given explicitly
#     and not found is refused, while an absent default simply means no
#     evidence), the reconcile sweep's
#     already-derived, TTL-stamped facts, one per line, joined to items by the
#     subject key:
#
#       stamp<TAB><epoch>                    when the facts were derived
#       pr<TAB><number><TAB>open|merged|closed
#       branch<TAB><name><TAB>commits|none
#       ledger<TAB><key><TAB>closed|open
#       report<TAB><worker><TAB><text>       a worker's own claim; settles nothing
#       unavailable<TAB><source>[<TAB><detail>]
#
#     An open or merged PR, commits on the branch, and a closed ledger item
#     settle; `closed`, `none`, `open` and every `report` line do not. A
#     source that cannot be reached is an `unavailable` line: distinct from
#     one reporting nothing, logged as `unavailable`, settling nothing, and
#     holding the away re-knock by writing `reknock.hold` (the delivery task
#     reads it; the pass removes it once every source answers again).
#
# A path item whose content file has gone settles with that reason too. An
# item is recorded as settled-while-away when no tower conversation had the
# operator present.
#
# On stdout the pass prints, tab-separated: `settled`, id, kind, away, the
# reason, and the tower that was holding it (or -); `merged`, the absorbed id,
# the id it went into, kind; `unavailable` and the source; and finally `held`
# and the seconds the fleet lock was held. Every one of those also lands in the
# event log. The `settled` tag is the pass's own shape and is NOT the catch-up's
# — that one carries more fields, below.
#
# A standing decision is not re-evaluated: it is the one kind no evidence
# closes, since what closes it is the operator revoking the rule (REQ-A1.2).
#
# MERGING (REQ-B1.3). In the same pass, over every open, unleased,
# undelivered, unshelved candidate that has a question and an option set to
# compare — which today means an answerable fork on an attention row; a path
# item and a park carry no option set and never merge — keyed once: two items
# of the same kind
# whose normalised question text and option set are identical merge into one
# that names every source. Normalised means case-folded and
# whitespace-collapsed with the origin worker handle and the row's scope
# removed by fixed-string replacement — except that an item carrying a worker
# command (the permission record's command field) merges only on byte equality
# after that removal, with no case-folding and no collapse. The survivor is
# the best-ranked source; it takes the highest urgency and the oldest birth of
# the group, and the others close with `merged into <id>`.
#
# PAIRING (REQ-B1.3) happens at the hand-over, not in the store: `next` pairs
# at most two open, unleased, undelivered items of the same kind naming the
# same subject key and hands them over as ONE unit — one `item` line whose
# origin names both sources and whose urgency and age are the higher and the
# older, plus one `pair` line carrying the partner's own pointer and closing
# condition — `pair`, the partner's id, its content pointer, its park path and
# its closing condition. The partner is the OLDEST candidate on that subject, so
# the two inherited fields both stay meaningful and nothing starves; a third
# item on the subject waits. Both are leased and stamped delivered, so the bound
# of one hand-over per call holds (REQ-C1.1) — and both ids are acknowledged:
# an unacknowledged partner is not lost, but it waits out the lease backstop
# before it is offered again.
#
# CATCH-UP (`catchup`, D-8, REQ-B1.4, REQ-C1.8). A lock-free read of what
# settled without the operator since their last reply in that tower's
# conversation (`--since` overrides; with neither, the whole retained settled
# history): one `settled` line per item — its reason, whether it settled while
# they were away, and the tower that was holding it if one was — most recent
# first, bounded to `tower_catchup_limit`, then a `remainder` line and the
# open counts by kind. It is what the tower READS to compose the first turn
# after silence; the list itself is shown only on request, and nothing here is
# ever pushed. Each line is `settled`, id, kind, urgency, the origins, the
# epoch it settled, the away flag, the reason, and the holder — nine fields,
# where the settling pass's own `settled` line has six.
#
# `--now` is accepted for symmetry with the other verbs and does not move the
# window, which is `--since` (or the marker) alone.
#
# The two halves come from different places, because the store keeps only the
# most recent closed records and the history past that horizon is the event
# log's (REQ-A1.5): the LIST is rendered from the store, and the REMAINDER is
# counted from the log's `settled` and `merged` lines inside the same window.
# The remainder line says which it is — `exact` only when the log still holds
# its first line and has dropped nothing at a lock-wait expiry, otherwise
# `floor` with the reason (`log-rotated`, `log-absent`, `lines-dropped`, or
# `no-store` when there is no store to render a list from at all). A floor is
# said as a floor rather than printed as a count nobody can stand behind, and
# it is the better of the two counts available — the log's, or the store's own
# in-window total — so a rotated log never under-reports what the store still
# holds.
#
# REBUILD. When the store is absent a locked verb rebuilds it inside the lock
# (absence re-checked there, so two towers cannot both rebuild) from the
# content homes: every awaiting-input attention row becomes a question item,
# and every `born` line in the event log with no `acknowledged`, `settled`
# or rebuild `dropped` after it is re-registered when its content home still
# holds the content — with the same identifier, since it comes from the same
# key — or logged as `dropped` with reason `rebuild` when the home has moved
# on (a path home is re-checked for containment exactly as `add` checks it)
# or the line's identifier does not derive from its own key. A rebuilt item
# is undelivered and the per-tower delivery records go with the lost store,
# so a delivered-but-open item is delivered once more; shelve deadlines and
# settling reasons are the store's alone and do not return; the settled
# history is the event log's (REQ-A1.5). The log lines a rebuild owes are
# written to `rebuild.debt` under the sub-surface before the store lands and
# paid once the lock is released, by that verb or the next one.
#
# THE LOG. One flat JSON object per line under a 0700 sub-surface of the
# cross-spec fleet home (`fleet-state.sh root`): `<home>/tower-comms/`, holding
# `events.log`, the sequence counter `events.seq`, and `events.dropped`, one
# line per log line dropped at a lock-wait expiry. Every value is a string or
# a number and never a nested object or array, so the script's own awk reads
# it back with no JSON tool on the host (REQ-G1.7). Every line carries the schema version, a
# monotonic sequence read and bumped from the counter file inside the same
# critical section, the timestamp, and the event kind; `reply`, `acknowledged`,
# `delivered`, `knocked` and `tick` lines carry the writing tower's identity,
# without which two towers' lines are indistinguishable (REQ-G1.6).
#
#   log <kind> [--tower <id>] [--now <epoch>] [<key>=<value> ...]
#
# Kinds: born settled merged knocked delivered acknowledged shelved pushed
# session tick reply dropped unavailable refused. A `tick` needs `live=<n>`
# (the live-worker count) and coalesces with the previous line when that is a
# tick from the same tower with the same count within `tower_tick_gap_max`:
# the previous line's `until` advances instead of a new line landing, so a
# steady fleet costs one line per count change and a gap in the tick stream
# stays visible to the report. A `session` needs `event=start|rebuild`.
#
# Field grammar: keys match ^[a-z][a-z0-9_]{0,31}$ and are not one of the
# reserved names (v seq ts kind tower until); a value is at most 4096 bytes,
# carries no C0 or C1 control byte and no DEL (a multi-line text is the
# caller's to flatten), and is refused when it is shaped like a JSON object
# or array. A
# value matching the JSON number grammar is written as a number, anything
# else as a string with `"` and `\` escaped. Every string value passes the
# secret-shaped redaction below before it is written, whatever the kind, so
# the hook and `capture` reuse this one helper instead of carrying their own
# (REQ-G1.8, REQ-H1.3).
#
# The lock wait is bounded by `tower_hook_lock_wait` (sub-second values are
# legal). On expiry nothing is written unlocked: the verb reports the expiry
# on stderr, appends one line to `events.dropped`, and exits 3, so the
# prompt-submit hook never delays the operator's turn on a busy lock and the
# drop is still counted. Rotation by age runs inside the same critical
# section: lines older than the larger of `tower_log_rotate_age` and
# `tower_report_window` are removed, the second being the floor that keeps
# the experiment's own sessions readable whatever the age is set to. It
# removes only what it can positively judge as old — a line it parses, whose
# header it reads, stamped behind the cutoff — so a torn line, a line from a
# writer on a schema version it does not know, and every line at all when the
# cutoff sits past the whole log (a stepped clock) survive it.
#
# THE SCORECARD.
#
#   report [--log <path>] [--now <epoch>] [--window <duration>]
#          [--tick-gap-max <duration>]
#
# Reads the log lock-free (a torn or malformed line is counted and skipped,
# never fatal), keeps the lines inside the `tower_report_window` window, and
# prints `<measure><TAB><value>` lines. Every measure is the window's except
# `malformed`, which is the whole file's: a line that will not parse carries
# no timestamp to place it in a window, and that count is the only evidence
# the operator ever gets that a write tore. The headline is the operator's load:
# items that reached the operator per hour of fleet work, against items
# settled without them. Fleet hours are wall-clock with at least one live
# worker, computed per tower from its own tick stream (a tick's span counts
# while its count is above zero, and so does the stretch to the next tick
# when it is within `tower_tick_gap_max`; a longer stretch is excluded and
# reported as a gap), the per-tower intervals unioned so an hour two towers
# both tick through counts once. Secondary measures: blocked-worker wait
# (question items from birth to acknowledgement, an open one to the window
# end), turns carrying more than one ask, items delivered in prose with no
# queue record, friction (what-does-that-mean replies, and a request of three
# or more words repeated), jargon in delivered text (spec identifiers,
# internal names, and the terms listed in tower-jargon.txt beside this
# script), items dropped at a rebuild, and the lines `log` itself dropped at
# a lock-wait expiry (read from `events.dropped` beside the log), without
# which the rest is computed from the survivors and printed as confident
# fact. `--log` and `--now` exist for
# fixtures and tests. On demand only: `mise run tower:report`, never CI
# (REQ-G1.5).
#
# Exit: 0 done (a coalesced tick included); 1 `report` found no log to read,
#   or a queue verb refused on state (an `ack` by a tower that holds no lease
#   on the item, or a `shelve` of an item another tower holds); 2 usage or
#   refused input, an item id the store does not hold included; 3 the
#   bounded lock wait expired (a log line dropped; a queue write not made,
#   or made and its own log line then dropped at the log's wait, which the
#   message says);
#   4 the sub-surface, the log, a counter, the store, a marker, a delivery
#   file, the evidence table or the settle stamp is not verifiably owner-only,
#   the attention store or its directory
#   is a redirect or foreign-owned, or a repo-tracked knob is malformed
#   (the by-layer policy), or `tower_lease_interval` is below
#   `tower_quiet_interval`, or `tower_catchup_limit` is above its cap; 5
#   broken install;
#   6 an infrastructure failure — a directory, temp file, rename, append,
#   clock or helper fork that would not answer, or a store that changed under
#   the lock, so the event was NOT recorded. The one exception is the settling
#   pass, whose store write commits before it publishes `reknock.hold` and
#   `settle.stamp`: a 6 from there means those two files, not the settlements,
#   are what failed — the settlements are printed and logged first, so the
#   record stays complete across it. A caller reading 3 as "expected
#   drop, carry on" and 2 as "I called it wrong" needs 6 to stay distinct
#   from both: it is the code that says the host, not the call, is what
#   stopped the log.
#
# Plain portable shell, no model invocation anywhere (REQ-H1.4); bash 3.2 /
# BSD tooling floor. Pathname expansion is off (set -f): the mode checks
# word-split an `ls` line that ends in a path, and a `*` in the fleet home's
# path must not expand against the working directory there.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 6

# Guarded like the jargon list `report` checks for: an unguarded `.` exits
# with the shell's own status for a missing file, which says nothing about
# which dependency went missing.
if [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "tower-queue: scripts/echo-safety.sh is missing — broken install" >&2
  exit 5
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

FS="$script_dir/fleet-state.sh"
RCK="$script_dir/resolve-config-knob.sh"
for _dep in "$FS" "$RCK"; do
  if [ ! -x "$_dep" ]; then
    printf '%s\n' "tower-queue: scripts/${_dep##*/} is missing or not executable — broken install" >&2
    exit 5
  fi
done
JARGON="$script_dir/tower-jargon.txt"
SCHEMA=1
KINDS="born settled merged knocked delivered acknowledged shelved pushed session tick reply dropped unavailable refused"
TOWER_KINDS="reply acknowledged delivered knocked tick"
RESERVED="v seq ts kind tower until"

usage() {
  cat >&2 <<'EOF'
usage: tower-queue.sh log <kind> [--tower <id>] [--now <epoch>] [<key>=<value> ...]
       tower-queue.sh report [--log <path>] [--now <epoch>] [--window <duration>] [--tick-gap-max <duration>]
       tower-queue.sh add --kind <kind> --origin <who> --closes <text> [--urgency high|normal|low] [--now <epoch>]
                      (--worker <handle> [--root <dir> --park <rel>] | --root <dir> --pointer <rel> [--park <rel>])
                      [--subject worker:<handle>|pr:<n>|branch:<name>|ledger:<key>]
                      --closes defaults for a standing decision; a question inherits its row's urgency and refuses --urgency
       tower-queue.sh next [--tower <id>] [--now <epoch>] [--evidence <file>]
       tower-queue.sh ack <id> [--tower <id>] [--now <epoch>]
       tower-queue.sh shelve <id> [--tower <id>] [--for <duration>] [--now <epoch>]
       tower-queue.sh settle <id> --reason <text> [--now <epoch>]
       tower-queue.sh settle [--evidence <file>] [--now <epoch>]   the level-triggered pass
       tower-queue.sh catchup [--tower <id>] [--since <epoch>] [--now <epoch>]
       tower-queue.sh list [--all] [--now <epoch>]
       tower-queue.sh counts [--now <epoch>]
EOF
  exit 2
}

err() {
  printf '%s\n' "tower-queue: $1" >&2
}

is_epoch() {
  case "$1" in
    "" | *[!0-9]* | 0?*) return 1 ;;
  esac
  [ "${#1}" -le 12 ]
}

# A tower identity: the presence surface's UUID or composite form, or the
# session-scoped fallback the queue verbs mint; a single path-safe token,
# never the fleet's absent-owner sentinel.
is_tower() {
  case "$1" in
    "" | unknown-owner | *[!A-Za-z0-9._-]* | .* | -*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

is_key() {
  case "$1" in
    "" | *[!a-z0-9_]*) return 1 ;;
    [a-z]*) ;;
    *) return 1 ;;
  esac
  [ "${#1}" -le 32 ] || return 1
  for _r in $RESERVED; do
    [ "$1" != "$_r" ] || return 1
  done
  return 0
}

is_number() {
  case "$1" in
    -*) _nv=${1#-} ;;
    *) _nv=$1 ;;
  esac
  case "$_nv" in
    "" | *[!0-9.]* | .* | *. | *.*.*) return 1 ;;
    0?*)
      case "$_nv" in
        0.*) ;;
        *) return 1 ;;
      esac
      ;;
  esac
  [ "${#1}" -le 20 ]
}

is_count() {
  case "$1" in
    "" | *[!0-9]* | 0?*) return 1 ;;
  esac
  [ "${#1}" -le 15 ]
}

# The span grammar resolve-config-knob.sh's `duration` type defines, applied
# to the CLI flags and re-applied to whatever that resolver hands back. Kept
# in step with it: a value one accepts and the other refuses is a knob that
# behaves differently depending on whether it came from a flag or a layer.
is_duration() {
  _dv=$1
  case "$_dv" in
    *ms) _dv=${_dv%ms} ;;
    *[smhd]) _dv=${_dv%?} ;;
  esac
  case "$_dv" in
    "" | *[!0-9.]* | .* | *. | *.*.*) return 1 ;;
  esac
  [ "${#_dv}" -le 16 ] || return 1
  _di=${_dv%%.*}
  _df=""
  case "$_dv" in
    *.*) _df=${_dv#*.} ;;
  esac
  case "$_di" in
    0) [ -n "$_df" ] || return 1 ;;
    0*) return 1 ;;
  esac
  [ "${#_df}" -le 6 ] || return 1
  case "$_dv" in
    *[1-9]*) return 0 ;;
  esac
  return 1
}

# duration_seconds <duration> — print the span in seconds (decimal), a bare
# number read as seconds.
duration_seconds() {
  case "$1" in
    *ms)
      _dn=${1%ms}
      _dm=0.001
      ;;
    *s)
      _dn=${1%s}
      _dm=1
      ;;
    *m)
      _dn=${1%m}
      _dm=60
      ;;
    *h)
      _dn=${1%h}
      _dm=3600
      ;;
    *d)
      _dn=${1%d}
      _dm=86400
      ;;
    *)
      _dn=$1
      _dm=1
      ;;
  esac
  awk -v n="$_dn" -v m="$_dm" 'BEGIN {
    v = n * m
    # A span the validator accepted must not arrive here as zero: the
    # validator checks the literal and this rounds to milliseconds, so
    # without the floor a sub-millisecond span switches its knob off — a zero
    # lock wait drops every line, a zero window reports an empty scorecard.
    if (v > 0 && v < 0.001) v = 0.001
    printf "%.3f\n", v }'
}

# knob <key> <fallback> — resolve one duration knob through the shared
# resolver into seconds. Exit 4 and 5 (a malformed team-shared value, a
# broken install) propagate as this script's own exit.
knob() {
  _kv=$("$RCK" --key "$1" --type duration --fallback "$2")
  _krc=$?
  if [ "$_krc" -ne 0 ]; then
    err "cannot resolve the '$1' knob (resolve-config-knob exit $_krc)"
    exit "$_krc"
  fi
  check_duration "$1" "$_kv"
  duration_seconds "$_kv"
}

# check_duration <key> <value> — the resolver's output is re-checked before it
# is converted, the way the CLI spans are. duration_seconds reads anything
# non-numeric as 0.000, and a zero lock wait drops every line while a zero
# rotation span deletes the log, so an unexpected value must stop the verb
# rather than quietly become one of those.
check_duration() {
  is_duration "$2" || {
    err "the '$1' knob resolved to '$(sanitize_printable "$2" "(unprintable value)")', which is not a positive span"
    exit 4
  }
}

# resolve_knobs <name:type:fallback> ... — the knobs a verb reads, resolved
# side by side. Each resolution is a chain of forks costing a third of a
# second on the support bar, and `log` runs on every operator prompt from
# the hook and every queue verb on every tower-loop pass, so they run
# concurrently and the wall clock pays for one. Each resolver's exit and
# value land in its own file; stderr is replayed in order so a degrade
# warning is never lost, and the first non-zero exit is this script's exit,
# the same contract as `knob`. A duration lands in its variable as seconds,
# a posint as itself; the name-to-variable mapping is the case below.
resolve_knobs() {
  _kd=$(mktemp -d 2>/dev/null) || {
    err "cannot create a scratch dir for the knob reads"
    exit 6
  }
  KNOB_DIR=$_kd
  for _ks in "$@"; do
    (
      _kn=${_ks%%:*}
      _kr=${_ks#*:}
      _kt=${_kr%%:*}
      _kf=${_kr#*:}
      _kv=$("$RCK" --key "$_kn" --type "$_kt" --fallback "$_kf" 2>"$_kd/$_kn.err")
      _krc=$?
      printf '%s\n%s\n' "$_krc" "$_kv" >"$_kd/$_kn"
    ) &
  done
  wait
  for _ks in "$@"; do
    _kn=${_ks%%:*}
    _kr=${_ks#*:}
    _kt=${_kr%%:*}
    [ ! -s "$_kd/$_kn.err" ] || cat "$_kd/$_kn.err" >&2
    _krc=""
    _kv=""
    {
      read -r _krc
      read -r _kv
    } <"$_kd/$_kn" 2>/dev/null || true
    case "$_krc" in
      0) ;;
      "" | *[!0-9]*)
        err "cannot resolve the '$_kn' knob (no result from resolve-config-knob)"
        exit 6
        ;;
      *)
        err "cannot resolve the '$_kn' knob (resolve-config-knob exit $_krc)"
        exit "$_krc"
        ;;
    esac
    if [ "$_kt" = duration ]; then
      check_duration "$_kn" "$_kv"
      _kv=$(duration_seconds "$_kv")
    else
      is_count "$_kv" && [ "$_kv" -gt 0 ] || {
        err "the '$_kn' knob resolved to '$(sanitize_printable "$_kv" "(unprintable value)")', which is not a positive integer"
        exit 4
      }
    fi
    case "$_kn" in
      tower_hook_lock_wait) lock_wait=$_kv ;;
      tower_tick_gap_max) gap_max=$_kv ;;
      tower_log_rotate_age) rotate_age=$_kv ;;
      tower_report_window) window=$_kv ;;
      tower_quiet_interval) quiet=$_kv ;;
      tower_lease_interval) lease_iv=$_kv ;;
      tower_catchup_limit) catchup_limit=$_kv ;;
      tower_shelve_return) shelve_return=$_kv ;;
    esac
  done
  rm -rf "$_kd"
  KNOB_DIR=""
}

resolve_log_knobs() {
  resolve_knobs tower_hook_lock_wait:duration:2s tower_tick_gap_max:duration:10m \
    tower_log_rotate_age:duration:30d tower_report_window:duration:7d
}

# resolve_queue_knobs — the knobs every queue verb reads. The lease interval
# is floored at the quiet interval and a value below it refused: an attended
# conversation must never lose the item it is holding to the backstop.
resolve_queue_knobs() {
  resolve_knobs tower_hook_lock_wait:duration:2s tower_quiet_interval:duration:10m \
    tower_lease_interval:duration:15m tower_catchup_limit:posint:20 tower_shelve_return:duration:1h
  if awk -v l="$lease_iv" -v q="$quiet" 'BEGIN { exit (l < q) ? 0 : 1 }'; then
    err "tower_lease_interval (${lease_iv}s) is below tower_quiet_interval (${quiet}s); the lease is floored at the quiet interval, so raise the one or lower the other"
    exit 4
  fi
  if [ "$catchup_limit" -gt "$Q_CATCHUP_CAP" ]; then
    err "tower_catchup_limit ($catchup_limit) is above the cap of $Q_CATCHUP_CAP closed records the store keeps; the history beyond it is the event log's"
    exit 4
  fi
}

# redact <value> [<key>] — the one secret-shaped redaction helper (REQ-G1.8).
# The rules mirror inception-secret-screen.sh's built-in screen; a match is
# replaced by `[redacted:<rule>]`, the text around it kept. `#` delimits the
# sed expressions because `/` appears inside a bracket expression.
#
# The key is screened with the value because the log's own CLI shape puts the
# assignment's left half OUTSIDE the value: `password=<opaque>` as an argument
# and `password=<opaque>` inside a sentence are the same secret, but only the
# second one has the `key<sep>value` run the opaque-assignment rule needs. So
# for a secret-shaped key, an opaque run at the head of the value is that
# assignment's right half and goes the same way.
redact() {
  _rv=$1
  case "${2:-}" in
    *api_key* | *apikey* | *api-key* | *secret* | *token* | *password* | *passwd*)
      _rv=$(printf '%s' "$_rv" | sed -E 's#^[A-Za-z0-9/+=_-]{20,}#[redacted:opaque-assignment]#')
      ;;
  esac
  printf '%s' "$_rv" | sed -E \
    -e 's#-----BEGIN ([A-Z]+ )?PRIVATE KEY-----#[redacted:private-key-block]#g' \
    -e 's#(AKIA|ASIA)[0-9A-Z]{16}#[redacted:aws-access-key-id]#g' \
    -e 's#gh[pousr]_[A-Za-z0-9]{36,}#[redacted:github-token]#g' \
    -e 's#xox[abpsr]-[A-Za-z0-9-]{16,}#[redacted:slack-token]#g' \
    -e 's#sk-[A-Za-z0-9_-]{24,}#[redacted:provider-api-key]#g' \
    -e "s#(api[_-]?key|secret|token|password|passwd)['\"]?[[:blank:]]*[:=][[:blank:]]*['\"]?[A-Za-z0-9/+=_-]{20,}#[redacted:opaque-assignment]#g"
}

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# The awk parser both verbs share: parse(line, F, T) fills F[key] = value and
# T[key] = "s" | "n" and returns 1 for a well-formed flat object of string
# and number values, 0 for anything else (a nested value included).
AWK_PARSE='
function parse(line, F, T,    s, n, i, c, c2, key, val, k) {
  split("", F); split("", T)
  if (substr(line, 1, 1) != "{" || substr(line, length(line), 1) != "}") return 0
  s = substr(line, 2, length(line) - 2)
  n = length(s); i = 1; k = 0
  while (i <= n) {
    if (k > 0) { if (substr(s, i, 1) != ",") return 0; i++ }
    if (substr(s, i, 1) != "\"") return 0
    i++; key = ""
    while (i <= n && substr(s, i, 1) != "\"") {
      c = substr(s, i, 1)
      if (c == "\\") return 0
      key = key c; i++
    }
    if (i > n || key == "" || (key in F)) return 0
    i++
    if (substr(s, i, 1) != ":") return 0
    i++
    c = substr(s, i, 1)
    if (c == "\"") {
      i++; val = ""
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\") {
          c2 = substr(s, i + 1, 1)
          if (c2 != "\"" && c2 != "\\") return 0
          val = val c2; i += 2; continue
        }
        if (c == "\"") break
        val = val c; i++
      }
      if (i > n) return 0
      i++
      F[key] = val; T[key] = "s"
    } else if (c ~ /[-0-9]/) {
      val = ""
      while (i <= n && substr(s, i, 1) ~ /[-0-9.]/) { val = val substr(s, i, 1); i++ }
      if (val !~ /^-?(0|[1-9][0-9]*)(\.[0-9]+)?$/) return 0
      F[key] = val; T[key] = "n"
    } else return 0
    k++
  }
  return k > 0
}
function header_ok(F, T) {
  if (!("v" in F) || !("seq" in F) || !("ts" in F) || !("kind" in F)) return 0
  if (T["v"] != "n" || T["seq"] != "n" || T["ts"] != "n" || T["kind"] != "s") return 0
  if (F["v"] != 1) return 0
  return 1
}
'

# ---------------------------------------------------------------------------
# Surface: verify-or-refuse, never chmod-narrowed (REQ-A1.4)
# ---------------------------------------------------------------------------

my_uid=""
check_private_dir() {
  _cd=$1
  if [ -L "$_cd" ]; then
    err "security: $(sanitize_printable "$_cd" "(unprintable path)") is a symlink — refusing to write through a redirect; investigate and remove it yourself"
    exit 4
  fi
  # shellcheck disable=SC2012
  _cl=$(ls -ldn "$_cd" 2>/dev/null) || _cl=""
  if [ -z "$_cl" ]; then
    err "the sub-surface $(sanitize_printable "$_cd" "(unprintable path)") vanished while being verified"
    exit 4
  fi
  # shellcheck disable=SC2086
  set -- $_cl
  # The group and other columns must carry no permission at all, but the
  # EXECUTE column of each also spells the setgid and sticky bits: a setgid
  # fleet home makes every mkdir under it inherit the bit, so a sub-surface
  # this script just created at 0700 lists as `drwx--S---`. Nothing widened
  # there, and refusing it would hard-fail every write with advice ("chmod
  # 700 it") that a fresh mkdir undoes.
  case "${1:-}" in
    d???--[-S]--[-T] | d???--[-S]--[-T][@.]*) ;;
    *)
      err "security: the sub-surface is not verifiably owner-only (mode ${1:-unreadable}); chmod 700 it yourself after finding out how it widened"
      exit 4
      ;;
  esac
  if [ "${3:-}" != "$my_uid" ]; then
    err "security: the sub-surface is owned by uid ${3:-?}, not this user; refusing it"
    exit 4
  fi
}

check_private_file() {
  _cf=$1
  [ -e "$_cf" ] || [ -L "$_cf" ] || return 0
  if [ -L "$_cf" ]; then
    err "security: $(sanitize_printable "$_cf" "(unprintable path)") is a symlink — refusing to write through a redirect"
    exit 4
  fi
  # shellcheck disable=SC2012
  _cl=$(ls -ln "$_cf" 2>/dev/null) || _cl=""
  # shellcheck disable=SC2086
  set -- $_cl
  case "${1:-}" in
    -???------ | -???------[@.]*) ;;
    *)
      err "security: $(sanitize_printable "$_cf" "(unprintable path)") is not owner-only (mode ${1:-unreadable}); chmod 600 it yourself after finding out how it widened"
      exit 4
      ;;
  esac
  if [ "${3:-}" != "$my_uid" ]; then
    err "security: $(sanitize_printable "$_cf" "(unprintable path)") is owned by uid ${3:-?}, not this user; refusing it"
    exit 4
  fi
}

resolve_surface() {
  home=$("$FS" root 2>/dev/null) || {
    err "cannot resolve the fleet home (fleet-state.sh root failed)"
    exit 6
  }
  my_uid=$(id -u 2>/dev/null) || {
    err "cannot resolve the current uid"
    exit 6
  }
  # fleet-state.sh owns this name; it is read here only to check the link's
  # target against the token this process holds, never to create the lock.
  LOCK_PATH="$home/.fleet.lock"
  surface="$home/tower-comms"
  log_file="$surface/events.log"
  seq_file="$surface/events.seq"
  dropped_file="$surface/events.dropped"
  store_file="$surface/queue"
  delivery_dir="$surface/delivery"
  marker_dir="$surface/attention"
  attn_store="$home/attention/state"
}

# The fleet home is fleet-state's surface, not this script's: created here
# only when absent, and otherwise verified rather than narrowed (REQ-A1.4).
# It is verified at all because the 0700 sub-surface below it is only as
# private as the directory that holds it — a home anyone but its owner can
# write to is one where the sub-surface can be moved aside and replaced
# between the checks below and the write they guard.
check_home() {
  if [ -L "$home" ]; then
    err "security: the fleet home $(sanitize_printable "$home" "(unprintable path)") is a symlink — refusing to write through a redirect"
    exit 4
  fi
  # shellcheck disable=SC2012
  _hl=$(ls -ldn "$home" 2>/dev/null) || _hl=""
  if [ -z "$_hl" ]; then
    err "the fleet home $(sanitize_printable "$home" "(unprintable path)") vanished while being verified"
    exit 4
  fi
  # shellcheck disable=SC2086
  set -- $_hl
  # Only the two WRITE columns: a home readable or traversable by others is
  # the ordinary shape (fleet-state creates it under the caller's umask), and
  # narrowing someone else's surface is not this script's call.
  case "${1:-}" in
    d????-??-? | d????-??-?[@.]*) ;;
    *)
      err "security: the fleet home is writable beyond its owner (mode ${1:-unreadable}); the private surface under it is only as private as the home, so chmod go-w it yourself after finding out how it widened"
      exit 4
      ;;
  esac
  if [ "${3:-}" != "$my_uid" ]; then
    err "security: the fleet home is owned by uid ${3:-?}, not this user; refusing it"
    exit 4
  fi
}

ensure_surface() {
  if [ ! -d "$home" ]; then
    mkdir -p "$home" 2>/dev/null || {
      err "cannot create the fleet home $(sanitize_printable "$home" "(unprintable path)")"
      exit 6
    }
    chmod 0700 "$home" 2>/dev/null || {
      err "cannot narrow the fleet home $(sanitize_printable "$home" "(unprintable path)") to 0700"
      exit 6
    }
  fi
  if [ -L "$surface" ]; then
    err "security: the sub-surface $(sanitize_printable "$surface" "(unprintable path)") is a symlink — refusing to write through a redirect"
    exit 4
  fi
  if [ ! -d "$surface" ]; then
    mkdir "$surface" 2>/dev/null || true
  fi
  if [ ! -d "$surface" ]; then
    err "cannot create the sub-surface $(sanitize_printable "$surface" "(unprintable path)")"
    exit 6
  fi
  verify_surface
}

# Every check the write path makes, in one place so it can be repeated: the
# checks below and the writes they guard are separated by the whole bounded
# lock wait, plus rotation and coalescing, so a surface tested once before the
# wait says nothing about the surface being written afterwards. Re-tested
# under the lock for the same reason fleet-presence keeps its symlink test
# adjacent to the mode read it guards.
verify_surface() {
  check_home
  check_private_dir "$surface"
  check_private_file "$log_file"
  check_private_file "$seq_file"
  check_private_file "$dropped_file"
}

# ---------------------------------------------------------------------------
# The fleet lock, bounded
# ---------------------------------------------------------------------------

HOLD_LOCK=0
LOCK_PATH=""
LOCK_AT=""
LOCK_TOKEN=""
LOCK_CHILD=""
PENDING_TMP=""
WORK_TMP=""
# Declared with the other tracked scratch paths rather than beside ev_prepare:
# cleanup() runs on every exit, including one taken long before the evidence
# section is reached, and an unset name there is a `set -u` failure inside the
# trap.
EVID_FILE=""
KNOB_DIR=""
# fleet-state disowns the lock its `lock` verb takes to this caller, and its
# `unlock` is an unconditional `rm -f` its own header calls out as able to
# delete a successor's lock. What closes both is the discipline try_acquire
# documents: claim ownership BEFORE anything can publish the link, and unlink
# only while the link is still ours. The claim here is the pid of the forked
# child, which is the `<pid>-<epoch>` owner token fleet-state writes, recorded
# before that child can be waited on; the check is the link's target read back.
# So a signal inside the acquire window still releases a lock this process
# took, and a lock broken as stale and retaken by a peer reads back a foreign
# target and is left standing.
release_lock() {
  [ "$HOLD_LOCK" = 1 ] || return 0
  HOLD_LOCK=0
  [ -n "$LOCK_PATH" ] || return 0
  _lt=$(readlink "$LOCK_PATH" 2>/dev/null) || _lt=""
  [ -n "$_lt" ] || return 0
  # The pid-prefix fallback stands in only while the token was never read
  # back (a signal inside the acquire window); once a token is known, a
  # mismatch is a lock that changed hands and is left standing.
  if [ "$_lt" = "$LOCK_TOKEN" ] || { [ -z "$LOCK_TOKEN" ] && [ -n "$LOCK_CHILD" ] && [ "${_lt%%-*}" = "$LOCK_CHILD" ]; }; then
    rm -f "$LOCK_PATH" 2>/dev/null || err "could not release the fleet lock at $(sanitize_printable "$LOCK_PATH" "(unprintable path)"); it stays held until fleet-state breaks it"
  fi
}
# Every scratch path this script mints is tracked, because each one is
# created inside the 0700 sub-surface: a signal between `mktemp` and the
# rename that consumes it would otherwise leave a full copy of the event log
# behind, one per interruption.
SCRATCH=""
cleanup() {
  release_lock
  [ -z "$PENDING_TMP" ] || rm -f "$PENDING_TMP" 2>/dev/null || true
  [ -z "$WORK_TMP" ] || rm -f "$WORK_TMP" 2>/dev/null || true
  [ -z "$EVID_FILE" ] || rm -f "$EVID_FILE" 2>/dev/null || true
  [ -z "$KNOB_DIR" ] || rm -rf "$KNOB_DIR" 2>/dev/null || true
  [ -z "$SCRATCH" ] || rm -rf "$SCRATCH" 2>/dev/null || true
}
trap 'cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# clock_s — the time as seconds with millisecond decimals when `date +%N`
# yields a real nanosecond field (GNU and BSD date both do), else whole
# seconds. A sub-second lock wait needs a sub-second deadline; on a
# whole-second clock the wait can overshoot by up to a second and says so.
clock_s() {
  _t=$(date '+%s %N' 2>/dev/null)
  case "$_t" in
    [0-9]*' '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9])
      _ns=${_t##* }
      printf '%s.%.3s\n' "${_t%% *}" "$_ns"
      ;;
    *) date +%s ;;
  esac
}

# wait_tries <seconds> — the attempt budget that stands in for the deadline
# when the clock will not answer. Each attempt costs a fork plus the sleep
# below, so a budget scaled to the sleep keeps the wait near the configured
# bound; without it the deadline comparison reads `0 >= w`, which is never
# true, and the prompt-submit hook's caller waits forever.
wait_tries() {
  awk -v w="$1" 'BEGIN {
    n = int(w / 0.02)
    if (n > 100000) n = 100000
    printf "%d\n", n + 25 }'
}

# acquire_lock <seconds> — take fleet-state's one-shot lock, retrying a busy
# holder until the wall-clock deadline (every attempt is a fork, so the bound
# is a deadline, not a try count) or, with no readable clock, until the
# attempt budget runs out. 0 held; 1 the wait expired; 2 a real error.
acquire_lock() {
  _deadline=$(clock_s)
  if [ -n "$_deadline" ]; then
    _deadline=$(awk -v s="$_deadline" -v w="$1" 'BEGIN { printf "%.3f\n", s + w }')
    _tries=0
  else
    _tries=$(wait_tries "$1")
  fi
  while :; do
    # Forked rather than run in the foreground so the pid inside the owner
    # token is this process's knowledge BEFORE the child can publish the link.
    LOCK_TOKEN=""
    "$FS" lock >/dev/null 2>&1 &
    LOCK_CHILD=$!
    HOLD_LOCK=1
    wait "$LOCK_CHILD"
    _rc=$?
    case $_rc in
      0)
        LOCK_TOKEN=$(readlink "$LOCK_PATH" 2>/dev/null) || LOCK_TOKEN=""
        LOCK_AT=$(clock_s)
        return 0
        ;;
      1) HOLD_LOCK=0 ;;
      *)
        HOLD_LOCK=0
        err "cannot acquire the fleet lock (fleet-state exit $_rc)"
        return 2
        ;;
    esac
    if [ -n "$_deadline" ]; then
      _cnow=$(clock_s)
      if [ -z "$_cnow" ]; then
        _deadline=""
        _tries=$(wait_tries "$1")
      elif awk -v now="$_cnow" -v dl="$_deadline" 'BEGIN { exit (now >= dl) ? 0 : 1 }'; then
        return 1
      fi
    fi
    if [ -z "$_deadline" ]; then
      _tries=$((_tries - 1))
      [ "$_tries" -gt 0 ] || return 1
    fi
    sleep 0.02
  done
}

# read_counter <file> — the integer at <file>, or 0 when absent or malformed
# (a leading zero included: this script only writes canonical decimals).
read_counter() {
  _cv=$(cat "$1" 2>/dev/null) || _cv=""
  case $_cv in
    "" | *[!0-9]* | 0?*) printf '0\n' ;;
    *) printf '%s\n' "$_cv" ;;
  esac
}

# last_logged_seq — the highest sequence carried by the log's own last lines,
# or 0. The counter file is a cache of this: every line records the sequence
# it was given, so a counter that went missing or malformed is recoverable
# rather than a reason to restart at 1 against a log holding higher values,
# which is how two lines end up sharing one number. The tail is the window
# that matters, the log being append-ordered.
last_logged_seq() {
  [ -s "$log_file" ] || {
    printf '0\n'
    return 0
  }
  tail -n 20 "$log_file" 2>/dev/null | awk "$AWK_PARSE"'
    { if (!parse($0, F, T) || !header_ok(F, T)) next
      s = F["seq"] + 0
      if (s > m) m = s }
    END { printf "%d\n", m + 0 }'
}

# write_counter <n> — the counter, replaced through a same-dir temp. 0 written,
# 1 the surface refused it.
write_counter() {
  PENDING_TMP=$(mktemp "$surface/.seq.XXXXXX" 2>/dev/null) || return 1
  printf '%s\n' "$1" >"$PENDING_TMP" 2>/dev/null || return 1
  mv -f "$PENDING_TMP" "$seq_file" 2>/dev/null || return 1
  PENDING_TMP=""
  return 0
}

# rewrite_log — replace the log's contents with the file at $1 via a
# same-dir temp and rename, so a lock-free reader never sees a torn file.
rewrite_log() {
  PENDING_TMP=$(mktemp "$surface/.events.XXXXXX" 2>/dev/null) || return 1
  cat "$1" >"$PENDING_TMP" 2>/dev/null || return 1
  mv -f "$PENDING_TMP" "$log_file" 2>/dev/null || return 1
  PENDING_TMP=""
  return 0
}

# ---------------------------------------------------------------------------
# log
# ---------------------------------------------------------------------------

cmd_log() {
  [ "$#" -ge 1 ] || usage
  kind=$1
  shift
  found=0
  for _k in $KINDS; do
    [ "$kind" != "$_k" ] || found=1
  done
  if [ "$found" -ne 1 ]; then
    err "unknown event kind '$(sanitize_printable "$kind" "(unprintable kind)")'"
    exit 2
  fi
  tower=""
  now=""
  now_set=0
  payload=""
  keys=""
  live=""
  event=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tower)
        [ "$#" -ge 2 ] || usage
        tower=$2
        shift 2
        ;;
      --now)
        [ "$#" -ge 2 ] || usage
        now=$2
        now_set=1
        shift 2
        ;;
      --*)
        usage
        ;;
      *=*)
        key=${1%%=*}
        val=${1#*=}
        shift
        if ! is_key "$key"; then
          err "refusing field '$(sanitize_printable "$key" "(unprintable key)")': keys match ^[a-z][a-z0-9_]{0,31}\$ and are none of: $RESERVED"
          exit 2
        fi
        for _k in $keys; do
          if [ "$_k" = "$key" ]; then
            err "refusing field '$key': given twice"
            exit 2
          fi
        done
        if [ "${#val}" -gt 4096 ]; then
          err "refusing field '$key': value longer than 4096 bytes"
          exit 2
        fi
        if [ "$(printf '%s' "$val" | tr -d '\000-\037\177\200-\237')" != "$val" ]; then
          err "refusing field '$key': the value carries a control byte (flatten the text first)"
          exit 2
        fi
        case "$val" in
          '{'*'}' | '['*']')
            err "refusing field '$key': a nested JSON value; the log holds strings and numbers only"
            exit 2
            ;;
        esac
        keys="$keys $key"
        [ "$key" != live ] || live=$val
        [ "$key" != event ] || event=$val
        if is_number "$val"; then
          payload="$payload,\"$key\":$val"
        else
          payload="$payload,\"$key\":\"$(json_escape "$(redact "$val" "$key")")\""
        fi
        ;;
      *)
        err "refusing argument '$(sanitize_printable "$1" "(unprintable argument)")': expected <key>=<value>"
        exit 2
        ;;
    esac
  done
  if [ -n "$tower" ] && ! is_tower "$tower"; then
    err "refusing tower identity '$(sanitize_printable "$tower" "(unprintable identity)")'"
    exit 2
  fi
  for _k in $TOWER_KINDS; do
    if [ "$kind" = "$_k" ] && [ -z "$tower" ]; then
      err "a '$kind' event needs --tower <id>: every $_k line carries the writing tower's identity"
      exit 2
    fi
  done
  if [ "$kind" = tick ] && ! is_count "$live"; then
    err "a tick needs live=<n>, the live-worker count as a non-negative integer"
    exit 2
  fi
  if [ "$kind" = session ]; then
    case "$event" in
      start | rebuild) ;;
      *)
        err "a session event needs event=start or event=rebuild"
        exit 2
        ;;
    esac
  fi
  # `[ -n "$now" ]` here would make `--now ""` a silent no-op, which reads as
  # the caller's own timestamp being honoured when it was in fact discarded.
  if [ "$now_set" = 1 ]; then
    if ! is_epoch "$now"; then
      err "refusing --now '$(sanitize_printable "$now" "(unprintable epoch)")': an epoch is a canonical positive integer"
      exit 2
    fi
  else
    now=$(date +%s 2>/dev/null) || now=""
    is_epoch "$now" || {
      err "cannot read the clock (date +%s failed)"
      exit 6
    }
  fi

  lock_wait=""
  gap_max=""
  rotate_age=""
  window=""
  resolve_log_knobs

  resolve_surface
  umask 077
  ensure_surface

  acquire_lock "$lock_wait"
  case $? in
    0) ;;
    1)
      err "the fleet lock stayed busy for the whole tower_hook_lock_wait; dropping this '$kind' line rather than writing unlocked (counted in events.dropped)"
      (printf '%s\t%s\n' "$now" "$kind") 2>/dev/null >>"$dropped_file" \
        || err "the dropped line could not be counted either: events.dropped would not take it"
      exit 3
      ;;
    *) exit 6 ;;
  esac

  # Under the lock now, so the surface is re-verified adjacent to the writes
  # that follow rather than trusted from before the wait.
  verify_surface

  # Rotation removes only what it can positively judge as old: a line this
  # script parses, whose header it reads, carrying a timestamp behind the
  # cutoff. Everything else stays. A line it cannot parse is the only evidence
  # that a write tore, and report's `malformed` count is what carries that
  # evidence to the operator; a line carrying a schema version this script does
  # not know belongs to another writer, and deleting it is how two writers
  # sharing a fleet home would destroy each other's history.
  #
  # Judged on the first JUDGEABLE line: the log is append-ordered, so when the
  # oldest line it can read is inside the cutoff nothing older can follow.
  if [ -s "$log_file" ]; then
    cutoff=$(awk -v now="$now" -v a="$rotate_age" -v w="$window" 'BEGIN { f = (a > w) ? a : w; printf "%.3f\n", now - f }')
    needs=$(awk -v cutoff="$cutoff" "$AWK_PARSE"'
      { if (!parse($0, F, T) || !header_ok(F, T)) next
        t = F["ts"] + 0
        if (F["kind"] == "tick" && ("until" in F)) t = F["until"] + 0
        print (t < cutoff) ? "yes" : "no"; exit }' "$log_file") || needs=no
    if [ "$needs" = yes ]; then
      rot_tmp=$(mktemp "$surface/.rotate.XXXXXX" 2>/dev/null) || {
        err "cannot create a scratch file for rotation"
        exit 6
      }
      WORK_TMP=$rot_tmp
      awk -v cutoff="$cutoff" "$AWK_PARSE"'
        { if (!parse($0, F, T) || !header_ok(F, T)) { print; next }
          t = F["ts"] + 0
          if (F["kind"] == "tick" && ("until" in F)) t = F["until"] + 0
          if (t >= cutoff) print }' "$log_file" >"$rot_tmp" 2>/dev/null || {
        err "rotation failed while filtering the log"
        exit 6
      }
      # A filter that keeps nothing is the signature of a clock that stepped
      # forward, not of a log that is entirely stale: one future-stamped write
      # puts the cutoff past every real line at once. Refuse it. The genuinely
      # idle case costs one write of delay — this write's own line lands, and
      # the next rotation then keeps it and removes the rest — while a clock
      # step costs nothing at all.
      if [ ! -s "$rot_tmp" ]; then
        err "refusing a rotation that would empty the event log; the cutoff is past every line, which is a stepped clock more often than a wholly stale log"
      else
        rewrite_log "$rot_tmp" || {
          err "rotation failed while replacing the log"
          exit 6
        }
      fi
      rm -f "$rot_tmp"
      WORK_TMP=""
    fi
  fi

  # A tick coalesces with the last line when that is this tower's tick at the
  # same count and the stretch since its `until` is within the gap bound.
  if [ "$kind" = tick ] && [ -s "$log_file" ]; then
    last=$(tail -n 1 "$log_file")
    merged=$(printf '%s\n' "$last" | awk -v tower="$tower" -v live="$live" -v now="$now" -v gap="$gap_max" "$AWK_PARSE"'
      { if (!parse($0, F, T) || !header_ok(F, T)) exit
        if (F["kind"] != "tick" || F["tower"] != tower || (F["live"] + 0) != (live + 0)) exit
        u = ("until" in F) ? F["until"] + 0 : F["ts"] + 0
        if (now < u || now - u > gap) exit
        sub(/,"until":[-0-9.]+}$/, "", $0)
        sub(/}$/, "", $0)
        print $0 ",\"until\":" now "}" }')
    if [ -n "$merged" ]; then
      co_tmp=$(mktemp "$surface/.coalesce.XXXXXX" 2>/dev/null) || {
        err "cannot create a scratch file for the tick"
        exit 6
      }
      WORK_TMP=$co_tmp
      {
        # Everything but the last record. A line count would disagree with
        # `tail -n 1` above whenever the final line is unterminated — the
        # count sees terminated lines, tail sees records — and the rewrite
        # would then drop a good line along with the one it means to replace.
        awk 'NR > 1 { print prev } { prev = $0 }' "$log_file"
        printf '%s\n' "$merged"
      } >"$co_tmp" 2>/dev/null || {
        err "coalescing failed while rewriting the log"
        exit 6
      }
      rewrite_log "$co_tmp" || {
        err "coalescing failed while replacing the log"
        exit 6
      }
      rm -f "$co_tmp"
      WORK_TMP=""
      exit 0
    fi
  fi

  seq=$(read_counter "$seq_file")
  logged=$(last_logged_seq)
  case $logged in
    "" | *[!0-9]*) logged=0 ;;
  esac
  if [ "$logged" -gt "$seq" ]; then
    err "the sequence counter is behind the event log (counter $seq, log $logged); continuing from the log's own last sequence"
    seq=$logged
  fi
  seq=$((seq + 1))

  line="{\"v\":$SCHEMA,\"seq\":$seq,\"ts\":$now,\"kind\":\"$kind\""
  # The identity is a string value like any other: its grammar admits
  # exactly the shape of an access key id or an opaque bearer token, and the
  # header promises every string value is screened whatever the kind.
  [ -z "$tower" ] || line="$line,\"tower\":\"$(json_escape "$(redact "$tower")")\""
  line="$line$payload"
  [ "$kind" != tick ] || line="$line,\"until\":$now"
  line="$line}"
  # A final line left unterminated by an earlier torn write has no newline to
  # end it, so a bare append lands INSIDE it and one tear costs two events.
  # Close the tear first: the torn line stays whole enough for report to count
  # it as malformed, and this line lands on its own.
  torn=0
  if [ -s "$log_file" ] && [ -n "$(tail -c 1 "$log_file" 2>/dev/null)" ]; then
    torn=1
    err "the event log's last line is unterminated (a torn write); closing it so this line lands whole"
  fi
  # The subshell keeps a failed redirect's raw shell diagnostic (which names
  # a line number and a bare path) off stderr: what reaches the operator is
  # this script's own sanitized line and nothing else. The stderr redirect
  # comes FIRST — redirections apply left to right, and a failing append
  # reports itself against whatever stderr is at that moment.
  (
    [ "$torn" = 0 ] || printf '\n'
    printf '%s\n' "$line"
  ) 2>/dev/null >>"$log_file" || {
    err "cannot append to the event log"
    exit 6
  }
  # After the line it numbers, never before: a counter bumped first burns a
  # sequence number on an append that then fails, and the hole that leaves is
  # indistinguishable from a rotated-away line, which is the one thing the
  # sequence exists to tell apart. A counter that does not land is repaired by
  # the next write, which reads the log.
  write_counter "$seq" \
    || err "the line landed but the sequence counter did not; the next write repairs it from the log"
  exit 0
}

# ---------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------

cmd_report() {
  log_path=""
  now=""
  now_set=0
  window_arg=""
  gap_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --log)
        [ "$#" -ge 2 ] || usage
        log_path=$2
        shift 2
        ;;
      --now)
        [ "$#" -ge 2 ] || usage
        now=$2
        now_set=1
        shift 2
        ;;
      --window)
        [ "$#" -ge 2 ] || usage
        window_arg=$2
        shift 2
        ;;
      --tick-gap-max)
        [ "$#" -ge 2 ] || usage
        gap_arg=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  if [ "$now_set" = 1 ]; then
    is_epoch "$now" || {
      err "refusing --now '$(sanitize_printable "$now" "(unprintable epoch)")': an epoch is a canonical positive integer"
      exit 2
    }
  else
    # Checked exactly as `log` checks it: an unread clock here prints a
    # window ending at the epoch and a fleet_hours of zero, which is
    # indistinguishable from a genuinely idle fleet.
    now=$(date +%s 2>/dev/null) || now=""
    is_epoch "$now" || {
      err "cannot read the clock (date +%s failed)"
      exit 6
    }
  fi
  if [ -n "$window_arg" ]; then
    is_duration "$window_arg" || {
      err "refusing --window '$(sanitize_printable "$window_arg" "(unprintable duration)")': a positive span such as 90m, 2h or 7d"
      exit 2
    }
    window=$(duration_seconds "$window_arg")
  else
    window=$(knob tower_report_window 7d) || exit $?
  fi
  if [ -n "$gap_arg" ]; then
    is_duration "$gap_arg" || {
      err "refusing --tick-gap-max '$(sanitize_printable "$gap_arg" "(unprintable duration)")': a positive span such as 10m"
      exit 2
    }
    gap_max=$(duration_seconds "$gap_arg")
  else
    gap_max=$(knob tower_tick_gap_max 10m) || exit $?
  fi
  if [ -z "$log_path" ]; then
    resolve_surface
    # The verify-or-refuse gate is the read path's too (REQ-A1.4). A
    # redirected or foreign-owned log feeds the scorecard whatever it points
    # at, and a fabricated scorecard printed at exit 0 reads exactly like a
    # real one. `--log` stays unverified: it is the fixture and test hatch,
    # and its path came from the caller rather than from the fleet home.
    if [ -d "$surface" ] || [ -L "$surface" ]; then
      check_home
      check_private_dir "$surface"
      check_private_file "$log_file"
    fi
    log_path=$log_file
  fi
  if [ ! -f "$log_path" ] || [ ! -r "$log_path" ]; then
    err "no event log to read at $(sanitize_printable "$log_path" "(unprintable path)")"
    exit 1
  fi
  # Beside the log it belongs to, so a fixture log and the live one are read
  # the same way; an absent file simply counts zero.
  case "$log_path" in
    */*) dropped_path="${log_path%/*}/events.dropped" ;;
    *) dropped_path="events.dropped" ;;
  esac
  [ -r "$dropped_path" ] || dropped_path=""
  [ -r "$JARGON" ] || {
    err "the jargon word list $JARGON is missing — broken install"
    exit 5
  }

  # The log arrives on stdin, never as a trailing operand: awk reads an
  # operand shaped like `name=value` as a variable assignment, so a relative
  # --log path whose text before the first `=` is an awk identifier would be
  # consumed as one, leaving the program with no file to read — all zeros at
  # exit 0, or a wait on stdin.
  awk -v now="$now" -v window="$window" -v gap_max="$gap_max" -v jargon_file="$JARGON" \
    -v dropped_file="$dropped_path" -v q="'" "$AWK_PARSE"'
  function norm_text(s) {
    s = tolower(s)
    gsub(/[^a-z0-9]+/, " ", s)
    sub(/^ /, "", s); sub(/ $/, "", s)
    return s
  }
  # Every needle here is delimiter-padded (" term "), and back-to-back repeats
  # SHARE the delimiter between them: consuming the whole needle eats the
  # space the next match needs to start, so "drain drain" scored one. Resuming
  # one character back leaves that delimiter in place.
  function count_phrase(hay, needle,    c, p, rest) {
    c = 0; rest = hay
    while ((p = index(rest, needle)) > 0) { c++; rest = substr(rest, p + length(needle) - 1) }
    return c
  }
  # Only `.` and `:` can reach here: the tokenizer below replaces every byte
  # outside [A-Za-z0-9.:_/-] with a space before splitting, so a wider class
  # would read as protection that nothing needs.
  function strip_punct(t) {
    sub(/[.:]+$/, "", t)
    return t
  }
  function jargon(text,    padded, i, ntok, tok, t, w) {
    padded = " " norm_text(text) " "
    for (i = 1; i <= nterms; i++) terms_hit += count_phrase(padded, " " terms[i] " ")
    t = text
    gsub(/[^A-Za-z0-9.:_\/-]+/, " ", t)
    ntok = split(t, tok, " ")
    for (i = 1; i <= ntok; i++) {
      w = strip_punct(tok[i])
      if (w ~ /^REQ-[A-Z]+[0-9]+(\.[0-9]+)?$/ || w ~ /^D-[0-9]+$/ || w ~ /^obs:[0-9a-f]+$/) ident_hit++
      else if (w ~ /^[a-z0-9]+([._-][a-z0-9]+)*\.(sh|md|yml|yaml|json|txt|toml)$/ || w ~ /^[a-z][a-z0-9]*(_[a-z0-9]+)+$/) internal_hit++
    }
  }
  BEGIN {
    nterms = 0
    while ((getline l < jargon_file) > 0) {
      sub(/#.*/, "", l)
      l = norm_text(l)
      if (l != "") terms[++nterms] = l
    }
    close(jargon_file)
    re_what = "[^a-z]what(" q "s| is| are| does| do)[^a-z]"
    ws = now - window; we = now + 0
    # The lines `log` dropped at a lock-wait expiry. Without them the
    # scorecard is computed from the survivors and printed as confident fact,
    # with nothing to say part of the window went unrecorded.
    dropped = 0
    if (dropped_file != "") {
      while ((getline dl < dropped_file) > 0) {
        if (split(dl, dp, "\t") >= 1 && dp[1] + 0 >= ws && dp[1] + 0 <= we) dropped++
      }
      close(dropped_file)
    }
    lines = 0; malformed = 0; nticks = 0; nint = 0
    delivered_prose = 0; multi_ask = 0; friction_meaning = 0; friction_repeat = 0
    terms_hit = 0; ident_hit = 0; internal_hit = 0; lost = 0
  }
  {
    if (!parse($0, F, T) || !header_ok(F, T)) { malformed++; next }
    kind = F["kind"]; ts = F["ts"] + 0
    inwin = (ts >= ws)
    if (kind == "tick") {
      u = ("until" in F) ? F["until"] + 0 : ts
      if (u >= ws) inwin = 1
    }
    if (!inwin) next
    lines++
    if ("tower" in F) towers[F["tower"]] = 1
    if (kind == "tick") {
      if (!("live" in F) || T["live"] != "n") next
      nticks++
      tk_tower[nticks] = ("tower" in F) ? F["tower"] : ""
      tk_ts[nticks] = ts
      tk_until[nticks] = ("until" in F) ? F["until"] + 0 : ts
      tk_live[nticks] = F["live"] + 0
    } else if (kind == "delivered") {
      if ("item" in F) delivered_items[F["item"]] = 1
      else delivered_prose++
      if (("asks" in F) && (F["asks"] + 0) > 1) multi_ask++
      if ("text" in F) jargon(F["text"])
    } else if (kind == "settled") {
      if ("item" in F) settled_items[F["item"]] = 1
    } else if (kind == "born") {
      if (("item" in F) && ("item_kind" in F) && F["item_kind"] == "question" && !(F["item"] in born_ts)) born_ts[F["item"]] = ts
    } else if (kind == "acknowledged") {
      if (("item" in F) && !(F["item"] in ack_ts)) ack_ts[F["item"]] = ts
    } else if (kind == "reply") {
      if ("text" in F) {
        low = " " tolower(F["text"]) " "
        if (low ~ re_what || low ~ /[^a-z]mean(s|ing)?[^a-z]/) friction_meaning++
        nt = norm_text(F["text"])
        if (split(nt, dummy, " ") >= 3) { if (nt in seen_reply) friction_repeat++; seen_reply[nt] = 1 }
      }
    } else if (kind == "dropped") {
      if (("reason" in F) && F["reason"] == "rebuild") lost++
    }
  }
  function add_interval(a, b) {
    if (a < ws) a = ws
    if (b > we) b = we
    if (b <= a) return
    nint++; ia[nint] = a; ib[nint] = b
  }
  END {
    # Per tower: order its ticks by ts, count live spans and bridged stretches.
    gaps = 0; gap_seconds = 0
    for (i = 1; i <= nticks; i++) if (!(tk_tower[i] in tick_towers)) tick_towers[tk_tower[i]] = 1
    for (tw in tick_towers) {
      m = 0
      for (i = 1; i <= nticks; i++) if (tk_tower[i] == tw) {
        # insertion by ts
        j = m
        while (j >= 1 && tk_ts[ord[j]] > tk_ts[i]) { ord[j + 1] = ord[j]; j-- }
        ord[j + 1] = i; m++
      }
      for (j = 1; j <= m; j++) {
        i = ord[j]
        if (tk_live[i] > 0) add_interval(tk_ts[i], tk_until[i])
        if (j < m) {
          nx = ord[j + 1]
          stretch = tk_ts[nx] - tk_until[i]
          if (stretch > gap_max) { gaps++; gap_seconds += stretch }
          else if (stretch > 0 && tk_live[i] > 0) add_interval(tk_until[i], tk_ts[nx])
        }
      }
      split("", ord)
    }
    # Union of the intervals, sorted by start.
    for (i = 1; i <= nint; i++) sidx[i] = i
    for (i = 2; i <= nint; i++) { v = sidx[i]; j = i - 1; while (j >= 1 && ia[sidx[j]] > ia[v]) { sidx[j + 1] = sidx[j]; j-- } sidx[j + 1] = v }
    total = 0; cur_a = 0; cur_b = -1; have = 0
    for (k = 1; k <= nint; k++) {
      i = sidx[k]
      if (!have) { cur_a = ia[i]; cur_b = ib[i]; have = 1; continue }
      if (ia[i] <= cur_b) { if (ib[i] > cur_b) cur_b = ib[i] }
      else { total += cur_b - cur_a; cur_a = ia[i]; cur_b = ib[i] }
    }
    if (have) total += cur_b - cur_a
    hours = total / 3600
    ndel = delivered_prose; for (x in delivered_items) ndel++
    nset = 0; for (x in settled_items) nset++
    wait_total = 0; wait_max = 0; wait_open = 0
    for (x in born_ts) {
      if ((x in ack_ts) && ack_ts[x] >= born_ts[x]) w = ack_ts[x] - born_ts[x]
      else { w = we - born_ts[x]; wait_open++ }
      if (w < 0) w = 0
      wait_total += w; if (w > wait_max) wait_max = w
    }
    ntow = 0; for (x in towers) ntow++
    printf "window_start\t%d\n", ws
    printf "window_end\t%d\n", we
    printf "lines\t%d\n", lines
    printf "malformed\t%d\n", malformed
    printf "dropped_lines\t%d\n", dropped
    printf "towers\t%d\n", ntow
    printf "fleet_hours\t%.2f\n", hours
    printf "tick_gaps\t%d\n", gaps
    printf "tick_gap_seconds\t%d\n", gap_seconds
    printf "delivered_items\t%d\n", ndel
    if (hours > 0) printf "delivered_per_fleet_hour\t%.2f\n", ndel / hours; else print "delivered_per_fleet_hour\tn/a"
    printf "settled_items\t%d\n", nset
    if (hours > 0) printf "settled_per_fleet_hour\t%.2f\n", nset / hours; else print "settled_per_fleet_hour\tn/a"
    printf "blocked_wait_seconds\t%d\n", wait_total
    printf "blocked_wait_max_seconds\t%d\n", wait_max
    printf "blocked_open\t%d\n", wait_open
    printf "multi_ask_turns\t%d\n", multi_ask
    printf "prose_deliveries\t%d\n", delivered_prose
    printf "friction_meaning\t%d\n", friction_meaning
    printf "friction_repeat\t%d\n", friction_repeat
    printf "jargon_identifiers\t%d\n", ident_hit
    printf "jargon_internal\t%d\n", internal_hit
    printf "jargon_terms\t%d\n", terms_hit
    printf "lost_across_restart\t%d\n", lost
  }' <"$log_path"
}

# ---------------------------------------------------------------------------
# The queue store: grammar and helpers
# ---------------------------------------------------------------------------

Q_KINDS="question approval request news standing"
Q_URGENCIES="high normal low"
STANDING_CLOSES="the operator revokes the rule"
QUESTION_CLOSES="the operator answers"
# The most closed (acknowledged or settled) records a write keeps: the
# catch-up knob is a small window, and the retention pass sorts what it
# keeps, so a runaway value would put that sort inside the fleet lock on
# every write.
Q_CATCHUP_CAP=500
# The bound the settling pass holds the fleet lock for, stated here because
# this is where it is enforced (REQ-B1.1): evidence is read before the lock is
# taken, so the hold covers the rewrite alone. The pass reports the hold it
# actually took as its `held` line and warns past this many seconds.
Q_SETTLE_HOLD_BOUND=2
TAB=$(printf '\t')
# The C1 control range as a case pattern (the byte-range form dash and bash
# both take under the C locale): [[:cntrl:]] stops at DEL, and a raw CSI at
# 0x9B drives a terminal the same as ESC does.
C1_BYTES=$(printf '[\200-\237]')
LOG_FAILED=0

refuse() {
  err "$1"
  exit 2
}

is_item_id() {
  case "$1" in
    i[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) return 0 ;;
  esac
  return 1
}

# is_one_of <value> <space-separated list>
is_one_of() {
  # shellcheck disable=SC2086
  for _ix in $2; do
    [ "$1" != "$_ix" ] || return 0
  done
  return 1
}

# has_control <value> — 0 when the value carries a C0 byte, DEL, or a C1
# byte. Fork-free: this runs on every field of every verb.
has_control() {
  case "$1" in
    *[[:cntrl:]]* | *$C1_BYTES*) return 0 ;;
  esac
  return 1
}

# is_text <value> <max> — a free-text field: non-empty, at most <max> bytes,
# no control byte (a tab or a newline included), no leading whitespace, and
# not shaped like a JSON object or array, which is the one shape the event
# log refuses: a value the store took and the log then refused would leave a
# record with no birth on record.
is_text() {
  [ -n "$1" ] || return 1
  [ "${#1}" -le "$2" ] || return 1
  has_control "$1" && return 1
  case "$1" in
    ' '* | '{'*'}' | '['*']') return 1 ;;
  esac
  return 0
}

# is_handle <value> — a worker handle or the operator's name as the
# attention store admits them: one token, no path separator, no
# whitespace, no control byte.
is_handle() {
  case "$1" in
    "" | . | .. | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

# is_subject <value> — the subject key the settling pass joins evidence on and
# the pairing rule groups by: a worker handle, a PR number, a branch, or a
# ledger key, each under its own prefix so two namespaces never collide.
is_subject() {
  case "$1" in
    -) return 0 ;;
    worker:*) is_handle "${1#worker:}" ;;
    pr:*)
      # The same shape the record grammar admits, so a subject `add` accepts is
      # never one the store then refuses to parse.
      case "${1#pr:}" in
        "" | 0* | *[!0-9]*) return 1 ;;
      esac
      [ "${#1}" -le 32 ]
      ;;
    branch:* | ledger:*)
      # Held to the character set the evidence table's own keys are checked
      # against, so a subject that parses can always be matched by a fact.
      _sv=${1#*:}
      [ -n "$_sv" ] || return 1
      [ "${#_sv}" -le 256 ] || return 1
      case "$_sv" in
        *[!A-Za-z0-9._/@:=+-]*) return 1 ;;
      esac
      return 0
      ;;
    *) return 1 ;;
  esac
}

UUID_PAT='[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]'
is_uuid() {
  # shellcheck disable=SC2254
  case "$1" in
    $UUID_PAT) return 0 ;;
  esac
  return 1
}

# promises_automation <closes> — 0 when the closing condition promises a
# future automatic step rather than naming a human action or evidence.
promises_automation() {
  _pl=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$_pl" in
    *automatic* | *auto-* | *'on its own'* | *'by itself'* | *'self-'* | *'will be closed'* | *'will close'*) return 0 ;;
  esac
  return 1
}

# resolve_tower <flag> — the calling tower's identity by the header's ladder;
# sets tower and tower_fallback. The session id is the presence surface's
# own identity form, so it is taken as the identity once it parses as a
# UUID; a pid is asked of the presence script first, which mints the same
# composite identity the tower published under, and only a pid the presence
# script cannot resolve falls back to the session-scoped label.
resolve_tower() {
  tower=$1
  tower_fallback=0
  [ -n "$tower" ] || tower=${PLANWRIGHT_TOWER_ID:-}
  if [ -z "$tower" ] && [ -n "${PLANWRIGHT_TOWER_SESSION_ID:-}" ]; then
    is_uuid "$PLANWRIGHT_TOWER_SESSION_ID" || refuse "refusing PLANWRIGHT_TOWER_SESSION_ID '$(sanitize_printable "$PLANWRIGHT_TOWER_SESSION_ID" "(unprintable id)")': a session id is a UUID"
    tower=$PLANWRIGHT_TOWER_SESSION_ID
  fi
  if [ -z "$tower" ]; then
    _tp=${PLANWRIGHT_TOWER_PID:-}
    if [ -n "$_tp" ]; then
      is_count "$_tp" || refuse "refusing PLANWRIGHT_TOWER_PID '$(sanitize_printable "$_tp" "(unprintable pid)")': a positive integer"
      if [ -x "$script_dir/fleet-presence.sh" ]; then
        _pi=$("$script_dir/fleet-presence.sh" identity --checkout "$PWD" --pid "$_tp" 2>/dev/null) || _pi=""
        is_tower "$_pi" && tower=$_pi
      fi
    else
      # The last resort names the invoking shell, which a tower session that
      # runs each verb from a fresh shell changes between calls; the header
      # says so, and the identity is announced so the drift is visible.
      _tp=$PPID
    fi
    if [ -z "$tower" ]; then
      _tl=$(ps -p "$_tp" -o lstart= 2>/dev/null | tr -d ' ') || _tl=""
      [ -n "$_tl" ] || {
        err "cannot mint a fallback tower identity: ps reports no start time for pid $_tp"
        exit 6
      }
      _th=$(printf '%s' "$_tl" | cksum | cut -d' ' -f1)
      is_count "$_th" || {
        err "cannot mint a fallback tower identity: cksum did not answer"
        exit 6
      }
      tower="fallback.p$_tp.t$_th"
      tower_fallback=1
    fi
  fi
  is_tower "$tower" || refuse "refusing tower identity '$(sanitize_printable "$tower" "(unprintable identity)")'"
}

canon_dir() {
  (cd -P -- "$1" 2>/dev/null && pwd -P)
}

# check_pointer <root> <rel> <what> — validate a content pointer against the
# declared root and set PTR_ROOT (the canonical root) and PTR_REL (the
# canonical relative path). The traversal refusal runs on the text before
# anything is resolved, then the directory is resolved physically and
# containment-checked, and the last component may not be a symlink: a
# pointer that escapes through a link is refused the same as one that walks
# out with `..`. The resolved forms are re-checked against the field grammar,
# because a link can resolve to a directory whose real name carries a byte
# the supplied text did not. The content must already be at its home.
check_pointer() {
  _pr=$1
  _pp=$2
  _pw=$3
  is_text "$_pp" 1024 || refuse "refusing the $_pw pointer: a relative path of at most 1024 bytes with no control byte or leading whitespace"
  case "$_pp" in
    /*) refuse "refusing the $_pw pointer: it is absolute; a pointer is a relative path under the declared root" ;;
    .. | ../* | */.. | */../*) refuse "refusing the $_pw pointer: it carries a traversal segment" ;;
  esac
  [ -n "$_pr" ] || refuse "the $_pw pointer needs --root <dir>, the declared root it sits under"
  is_text "$_pr" 1024 || refuse "refusing --root: at most 1024 bytes with no control byte or leading whitespace"
  case "$_pr" in
    /*) ;;
    *) refuse "refusing --root: the declared root must be an absolute directory" ;;
  esac
  [ -d "$_pr" ] || refuse "refusing --root: not a directory"
  PTR_ROOT=$(canon_dir "$_pr") || refuse "refusing --root: cannot resolve it"
  PTR_ROOT=${PTR_ROOT%/}
  [ -n "$PTR_ROOT" ] || PTR_ROOT=/
  _pt="$PTR_ROOT/$_pp"
  _pd=${_pt%/*}
  _pb=${_pt##*/}
  [ -n "$_pb" ] || refuse "refusing the $_pw pointer: it names no file"
  _pc=$(canon_dir "$_pd") || refuse "refusing the $_pw pointer: its directory does not exist under the root"
  case "$_pc" in
    "$PTR_ROOT" | "$PTR_ROOT"/*) ;;
    *)
      [ "$PTR_ROOT" = / ] || refuse "refusing the $_pw pointer: it canonicalises outside the declared root"
      ;;
  esac
  [ ! -L "$_pc/$_pb" ] || refuse "refusing the $_pw pointer: it is a symlink"
  [ -f "$_pc/$_pb" ] || refuse "refusing the $_pw pointer: no content at its home yet (content is written before the index record)"
  PTR_REL="${_pc#"$PTR_ROOT"}/$_pb"
  PTR_REL=${PTR_REL#/}
  if ! is_text "$PTR_REL" 1024 || ! is_text "$PTR_ROOT" 1024; then
    refuse "refusing the $_pw pointer: its resolved path carries a byte the record grammar refuses"
  fi
}

# item_id <kind> <home> <pointer> <instance> <root> — the identifier derived
# from the content home's key: the fields joined by a tab, which no field
# can carry, so two keys never read as one. A question's key carries no
# instance (one awaiting-input row is one question, however often it
# re-forks) and no attention-home key carries a root.
item_id() {
  _ck=$(printf '%s\t%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4" "$5" | cksum | cut -d' ' -f1)
  is_count "$_ck" || {
    err "cannot derive an item identifier (cksum did not answer)"
    exit 6
  }
  printf 'i%08x\n' "$_ck"
}

# id_for <kind> <home> <pointer> <instance> <root> — item_id over the key's
# canonical form: instance dropped for a question, root dropped for an
# attention home.
id_for() {
  _ii=$4
  _ir=$5
  [ "$1" != question ] || _ii=-
  [ "$2" != attention ] || _ir=-
  item_id "$1" "$2" "$3" "$_ii" "$_ir"
}

# attn_row <worker> — set row_state row_ts row_prio row_iid from the
# worker's attention row; all empty when there is no such row. Both key
# operands are pinned to string type, the way fleet-attention.sh reads its
# own store. A store that exists but will not read is the host's failure,
# never "no such row".
attn_row() {
  row_state=""
  row_ts=""
  row_prio=""
  row_iid=""
  [ -f "$attn_store" ] || return 0
  _ar=$(awk -F '\t' -v w="$1" '($1 "") == (w "") { print $3 "\t" $4 "\t" $5 "\t" $10; exit }' "$attn_store" 2>/dev/null) || {
    err "cannot read the attention store"
    exit 6
  }
  [ -n "$_ar" ] || return 0
  IFS="$TAB" read -r row_state row_ts row_prio row_iid <<EOF
$_ar
EOF
  return 0
}

# log_event <log args> — the event-log line a verb owes, appended AFTER the
# lock is released through the `log` verb's own critical section. 0 landed;
# otherwise the verb's exit, reported by the caller.
log_event() {
  "$script_dir/tower-queue.sh" log "$@"
}

# owe_log <kind> <log args...> — a line that must land. A bounded wait that
# expired on the log's own lock is the counted drop the log contract
# defines, reported as this verb's exit 3 with the store write standing;
# anything else the log verb refused is exit 6.
owe_log() {
  _ok=$1
  shift
  log_event "$_ok" "$@"
  _orc=$?
  case $_orc in
    0) ;;
    3)
      err "the '$_ok' line was dropped at the event log's lock wait (counted in events.dropped); the store write stands"
      [ "$LOG_FAILED" = 6 ] || LOG_FAILED=3
      ;;
    *)
      err "the '$_ok' line did not reach the event log (log exit $_orc); the store write stands but the record is incomplete"
      LOG_FAILED=6
      ;;
  esac
}

# finish_exit [<code>] — the verb's own exit, unless an owed log line failed.
finish_exit() {
  case "$LOG_FAILED" in
    6) exit 6 ;;
    3) exit 3 ;;
  esac
  exit "${1:-0}"
}

# --- the queue surface --------------------------------------------------------

check_store_file() {
  if [ -d "$1" ] && [ ! -L "$1" ]; then
    err "$(sanitize_printable "$1" "(unprintable path)") is a directory where the store should be; refusing to write into it"
    exit 6
  fi
  check_private_file "$1"
}

# check_owned <path> — the attention store is fleet-attention's surface,
# created under that script's umask, so its mode is its owner's call; what
# this reader refuses is a redirect or a foreign owner, since the rows
# decide which questions exist and what urgency they carry.
check_owned() {
  _co=$1
  [ -e "$_co" ] || [ -L "$_co" ] || return 0
  if [ -L "$_co" ]; then
    err "security: $(sanitize_printable "$_co" "(unprintable path)") is a symlink — refusing to read through a redirect"
    exit 4
  fi
  # shellcheck disable=SC2012
  _ol=$(ls -ldn "$_co" 2>/dev/null) || _ol=""
  # shellcheck disable=SC2086
  set -- $_ol
  if [ "${3:-}" != "$my_uid" ]; then
    err "security: $(sanitize_printable "$_co" "(unprintable path)") is owned by uid ${3:-?}, not this user; refusing it"
    exit 4
  fi
}

# ensure_queue_surface — the surface a locked verb writes, created when
# absent and verified once before the lock (the under-lock re-verification
# is verify_queue_surface, adjacent to the writes it guards).
ensure_queue_surface() {
  ensure_surface
  if [ -L "$delivery_dir" ]; then
    err "security: $(sanitize_printable "$delivery_dir" "(unprintable path)") is a symlink — refusing to write through a redirect"
    exit 4
  fi
  [ -d "$delivery_dir" ] || mkdir "$delivery_dir" 2>/dev/null || true
  [ -d "$delivery_dir" ] || {
    err "cannot create the delivery sub-surface $(sanitize_printable "$delivery_dir" "(unprintable path)")"
    exit 6
  }
  check_private_dir "$delivery_dir"
  check_store_file "$store_file"
}

verify_queue_surface() {
  verify_surface
  check_private_dir "$delivery_dir"
  check_store_file "$store_file"
  if [ -d "$marker_dir" ] || [ -L "$marker_dir" ]; then
    check_private_dir "$marker_dir"
  fi
  check_owned "${attn_store%/*}"
  check_owned "$attn_store"
}

# The read path's verify-or-refuse: a redirected or foreign-owned store would
# feed `list` and `counts` whatever it points at.
verify_read_surface() {
  if [ -d "$surface" ] || [ -L "$surface" ]; then
    check_home
    check_private_dir "$surface"
    check_store_file "$store_file"
  fi
}

# read_marker <tower> — the epoch of the operator's last reply in that
# tower's conversation, from the marker the prompt-submit hook owns, or
# nothing. A marker anyone else could write is a self-satisfiable gate, so
# its mode is verified like every other file on the surface. Prints
# `unreadable` for a file that exists and will not read.
read_marker() {
  _mf="$marker_dir/$1"
  [ -e "$_mf" ] || [ -L "$_mf" ] || return 0
  check_private_file "$_mf"
  _ml=""
  if ! IFS= read -r _ml <"$_mf" 2>/dev/null && [ -z "$_ml" ]; then
    [ -s "$_mf" ] || return 0
    printf 'unreadable\n'
    return 0
  fi
  # The whole line is the epoch (a fractional part allowed); anything else
  # on it is no reply, never a prefix to salvage.
  case "$_ml" in
    "" | *[!0-9.]* | .* | *. | *.*.*) return 0 ;;
    *) printf '%s\n' "$_ml" ;;
  esac
}

# read_delivery <tower> — set d_kt d_kitem d_dt d_ditem from the tower's
# delivery record; zeros when absent, and any malformed field reads as zero.
read_delivery() {
  d_kt=0
  d_kitem=-
  d_dt=0
  d_ditem=-
  _df="$delivery_dir/$1"
  [ -e "$_df" ] || [ -L "$_df" ] || return 0
  check_private_file "$_df"
  _d1=""
  _d2=""
  _d3=""
  _d4=""
  if ! IFS="$TAB" read -r _d1 _d2 _d3 _d4 <"$_df" 2>/dev/null && [ -z "$_d1" ]; then
    if [ -s "$_df" ]; then
      err "cannot read the delivery record $(sanitize_printable "$_df" "(unprintable path)")"
      exit 6
    fi
    return 0
  fi
  is_epoch "$_d1" && d_kt=$_d1
  is_item_id "$_d2" && d_kitem=$_d2
  is_epoch "$_d3" && d_dt=$_d3
  is_item_id "$_d4" && d_ditem=$_d4
  return 0
}

write_delivery() { # write_delivery <tower> <kt> <kitem> <dt> <ditem>
  PENDING_TMP=$(mktemp "$delivery_dir/.$1.XXXXXX" 2>/dev/null) || {
    err "cannot create a scratch file for the delivery record"
    exit 6
  }
  printf '%s\t%s\t%s\t%s\n' "$2" "$3" "$4" "$5" >"$PENDING_TMP" 2>/dev/null || {
    err "cannot write the delivery record"
    exit 6
  }
  mv -f "$PENDING_TMP" "$delivery_dir/$1" 2>/dev/null || {
    err "cannot replace the delivery record"
    exit 6
  }
  PENDING_TMP=""
}

# build_towers_file — the towers the pass must know about: the caller and
# every lease owner in the snapshot, one line each: tower, last reply, last
# knock, the item it named, last hand-over, the item it handed. The caller's
# own files are verified strictly; a peer's file that refuses verification
# leaves that peer out with a warning, so one tower's widened marker cannot
# stop every other tower's verbs.
build_towers_file() {
  : >"$SCRATCH/names"
  [ -z "${tower:-}" ] || printf '%s\n' "$tower" >>"$SCRATCH/names"
  [ ! -s "$SCRATCH/snap" ] || awk -F '\t' '(NF == 20 || NF == 23 || NF == 24) && $19 != "-" { print $19 }' "$SCRATCH/snap" >>"$SCRATCH/names"
  # The settling pass runs under no tower of its own and still has to know
  # whether the operator is present anywhere before it records an item as
  # settled while they were away (REQ-B1.4), so it — and only it — sweeps every
  # conversation that has a delivery record or a marker. A verb that knows its
  # own tower keeps the old two-name table: this sweep costs a mode read per
  # name and both directories grow for the life of the fleet home, which is not
  # a cost `ack` should pay inside the lock.
  if [ -z "${tower:-}" ]; then
    # shellcheck disable=SC2012
    ls -1 "$delivery_dir" 2>/dev/null >>"$SCRATCH/names" || true
    # shellcheck disable=SC2012
    ls -1 "$marker_dir" 2>/dev/null >>"$SCRATCH/names" || true
  fi
  : >"$SCRATCH/towers"
  sort -u "$SCRATCH/names" | while IFS= read -r _tn; do
    is_tower "$_tn" || continue
    if [ "$_tn" = "${tower:-}" ]; then
      _tr=$(read_marker "$_tn") || exit $?
      read_delivery "$_tn" || exit $?
      [ "$_tr" != unreadable ] || {
        err "cannot read the attention marker for tower '$_tn'"
        exit 6
      }
    else
      _tr=$(read_marker "$_tn" 2>/dev/null) || {
        err "skipping tower '$_tn': its attention marker refuses verification (it counts as away)"
        _tr=""
      }
      [ "$_tr" != unreadable ] || _tr=""
      _dl=$(
        read_delivery "$_tn" 2>/dev/null || exit 1
        printf '%s\t%s\t%s\t%s\n' "$d_kt" "$d_kitem" "$d_dt" "$d_ditem"
      ) || {
        err "skipping tower '$_tn': its delivery record refuses verification"
        _dl="0	-	0	-"
      }
    fi
    if [ "$_tn" = "${tower:-}" ]; then
      _dl=$(printf '%s\t%s\t%s\t%s\n' "$d_kt" "$d_kitem" "$d_dt" "$d_ditem")
    fi
    printf '%s\t%s\t%s\n' "$_tn" "${_tr:-0}" "$_dl" >>"$SCRATCH/towers" || exit 6
  done || exit $?
}

# take_snapshot — the store as it is on entry to the critical section, for
# the re-read-and-compare before the rename.
SNAP_EXISTED=0
take_snapshot() {
  if [ -f "$store_file" ]; then
    cp "$store_file" "$SCRATCH/snap" 2>/dev/null || {
      err "cannot read the queue store"
      exit 6
    }
    SNAP_EXISTED=1
  else
    : >"$SCRATCH/snap"
    SNAP_EXISTED=0
  fi
}

# commit_store — replace the store with $SCRATCH/new, refusing when the
# store no longer matches the snapshot (removed under the lock, or appeared
# where the rebuild found none, included): the lock carries no holder token,
# and a store that moved under it means the lock was broken.
commit_store() {
  if { [ "$SNAP_EXISTED" = 1 ] && { [ -L "$store_file" ] || [ ! -f "$store_file" ] || ! cmp -s "$store_file" "$SCRATCH/snap"; }; } \
    || { [ "$SNAP_EXISTED" = 0 ] && { [ -e "$store_file" ] || [ -L "$store_file" ]; }; }; then
    err "the queue store changed while this verb held the fleet lock (a broken lock?); nothing written"
    return 1
  fi
  PENDING_TMP=$(mktemp "$surface/.queue.XXXXXX" 2>/dev/null) || {
    err "cannot create a scratch file for the queue store"
    return 1
  }
  cat "$SCRATCH/new" >"$PENDING_TMP" 2>/dev/null || {
    err "cannot write the queue store"
    return 1
  }
  mv -f "$PENDING_TMP" "$store_file" 2>/dev/null || {
    err "cannot replace the queue store"
    return 1
  }
  PENDING_TMP=""
}

# The awk prelude every store pass shares: the record grammar, the ranking,
# the derived pass (shelve returns, lease expiry and renewal, attention
# pointer refresh), attention per tower, and the emit with retention.
# shellcheck disable=SC2016
AWK_Q='
function rec_ok(   i) {
  if (NF != 24) return 0
  if ($1 !~ /^i[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$/) return 0
  if ($2 !~ /^(question|approval|request|news|standing)$/) return 0
  if ($3 !~ /^(high|normal|low)$/) return 0
  if ($6 !~ /^(attention|path)$/) return 0
  if ($12 !~ /^(open|closed)$/) return 0
  if ($5 !~ /^(0|[1-9][0-9]*)$/) return 0
  for (i = 13; i <= 17; i++) if ($i !~ /^(0|[1-9][0-9]*)$/) return 0
  if ($20 !~ /^(0|[1-9][0-9]*)$/) return 0
  if ($21 !~ /^(-|worker:[^ \t]+|pr:[1-9][0-9]*|branch:[^ \t]+|ledger:[^ \t]+)$/) return 0
  if ($22 !~ /^[01]$/) return 0
  for (i = 1; i <= 24; i++) if ($i == "") return 0
  return 1
}
function krank(k) { return (k == "question") ? 0 : (k == "approval") ? 1 : (k == "request") ? 2 : (k == "news") ? 3 : 9 }
function urank(u) { return (u == "high") ? 0 : (u == "normal") ? 1 : 2 }
function better(a, b,   x, y) {
  x = krank(F[a, 2]); y = krank(F[b, 2]); if (x != y) return x < y
  x = urank(F[a, 3]); y = urank(F[b, 3]); if (x != y) return x < y
  if (F[a, 5] + 0 != F[b, 5] + 0) return F[a, 5] + 0 < F[b, 5] + 0
  return F[a, 1] < F[b, 1]
}
function clean(s) { gsub(/[^[:print:]]/, "", s); return s }
function fail(what) { print "fail\t" what; exit }
function load_towers(file,   l, f, rc) {
  while ((rc = (getline l < file)) > 0) {
    split(l, f, "\t")
    tw_reply[f[1]] = f[2] + 0; tw_kt[f[1]] = f[3] + 0; tw_kitem[f[1]] = f[4]; tw_dt[f[1]] = f[5] + 0; tw_ditem[f[1]] = f[6]
  }
  close(file)
  if (rc < 0) fail("cannot read the tower table")
}
function load_attention(file,   l, f, n, rc) {
  if (file == "") return
  while ((rc = (getline l < file)) > 0) {
    n = split(l, f, "\t")
    if (n < 8) continue
    at_state[f[1]] = f[3]; at_ts[f[1]] = f[4]; at_prio[f[1]] = f[5]; at_iid[f[1]] = (n >= 10) ? f[10] : ""
    # The settling pass reads four more: the scope and the question with its
    # option set are what the merge key is computed from, and the claim
    # label (the first-answer-wins field fleet-attention.sh claim stamps) is the
    # answered-by-another-route evidence. The 12th is the command text on
    # a permission record, which merges only on byte equality.
    at_q[f[1]] = f[6]; at_opts[f[1]] = f[8]
    # A lone "-" reads as absent alongside the empty field the writers use:
    # no option label is a bare dash, and taking one for an answer would
    # settle an item the operator never saw. The scope takes the same guard
    # for a different reason: the valid_field grammar fleet-attention writes
    # through admits a bare "-" as a handle, and the merge key removes the
    # scope from the question text as a literal, so an unguarded dash would
    # strip every hyphen out of the text two different items are keyed on and
    # collide questions that differ only in one.
    at_scope[f[1]] = (f[2] != "-") ? f[2] : ""
    at_claim[f[1]] = (n >= 11 && f[11] != "-") ? f[11] : ""
    at_cmd[f[1]] = (n >= 12 && f[12] != "-") ? f[12] : ""
  }
  close(file)
  if (rc < 0) fail("cannot read the attention store")
}
# The evidence table the settling pass runs against, normalised by the shell
# before the lock was taken: one `settles` line per fact, keyed by an item id
# or a subject key, and one `unavailable` line per source that would not
# answer (distinct from a source reporting nothing, REQ-B1.2).
function load_evidence(file,   l, f, n, rc) {
  if (file == "") return
  while ((rc = (getline l < file)) > 0) {
    n = split(l, f, "\t")
    if (n >= 3 && f[1] == "settles") ev[f[2]] = f[3]
    else if (n >= 2 && f[1] == "unavailable") unavail[f[2]] = 1
  }
  close(file)
  if (rc < 0) fail("cannot read the evidence table")
}
# fsrep(s, pat): every occurrence of the LITERAL pat removed. Fixed-string,
# never a regex: inbound text is data and is never used as a pattern.
function fsrep(s, pat,   i, out) {
  if (pat == "") return s
  out = ""
  while ((i = index(s, pat)) > 0) { out = out substr(s, 1, i - 1); s = substr(s, i + length(pat)) }
  return out s
}
function norm(s) {
  s = tolower(s); gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s)
  return s
}
# merge_key(n): what two items have to share to be the same question. Only an
# attention item has one — its question text and option set live on the row;
# a path item carries no option set and never merges.
function merge_key(n,   w, s) {
  if (F[n, 6] != "attention") return ""
  w = F[n, 7]
  if (!(w in at_state)) return ""
  if (at_cmd[w] != "") {
    s = fsrep(fsrep(at_cmd[w], F[n, 4]), at_scope[w])
    return (s == "") ? "" : "c\002" s
  }
  # Only an answerable fork merges on its text. A row with no option set is a
  # park — today that is the permission-prompt shape, whose command text lands
  # in the 12th field only once the capture task ships — and collapsing two of
  # those on case-folded prose is exactly what the byte-equality rule exists to
  # prevent.
  if (at_q[w] == "" || at_opts[w] == "") return ""
  return "q\002" norm(fsrep(fsrep(at_q[w], F[n, 4]), at_scope[w])) "\003" norm(fsrep(fsrep(at_opts[w], F[n, 4]), at_scope[w]))
}
# settle_reason(n): the closing condition re-read against the evidence
# available NOW, or "" for an item that stays open. Order matters only in
# that a vanished home is reported as itself rather than as whatever a
# subject-keyed fact would have said about it.
function settle_reason(n,   w) {
  if (("item:" F[n, 1]) in ev) return ev["item:" F[n, 1]]
  if (F[n, 6] == "attention") {
    # No attention store at all is a source that cannot be reached, not a
    # store saying every row is gone: reading it the second way would close
    # every attention-homed item unseen the moment the file went missing.
    if (!attn_present) { attn_needed = 1; return "" }
    w = F[n, 7]
    if (!(w in at_state)) return "its attention row is gone (the content home has vanished)"
    # A row that merely moved on carries the status the worker reported of
    # itself, which is a claim and settles nothing (REQ-B1.2).
    # The label itself is deliberately NOT quoted into the reason: this string
    # is stored and rendered back into the conversation, and the one redaction
    # helper lives in the shell (REQ-G1.8, REQ-H1.3), out of awk`s reach. The
    # label stays on the row it came from and in the redacted log line.
    if (at_claim[w] != "") return "answered by another route (its worker record was claimed)"
  }
  if (F[n, 21] != "-" && (F[n, 21] in ev)) return ev[F[n, 21]]
  return ""
}
function add_source(have, who,   i, p) {
  if (who == "" || who == "-") return have
  if (index("," have ",", "," who ",") > 0) return have
  if (length(have) + length(who) + 1 > 480) return have
  return (have == "") ? who : have "," who
}
# settle_pass(): the level-triggered pass. Every open condition is
# re-evaluated against the evidence available now, then the survivors are
# keyed once and the duplicates merged (REQ-B1.1, REQ-B1.3).
function settle_pass(   n, r, t, i, j, key, best, src, parts, np) {
  attn_needed = 0
  away = 1
  for (t in tw_reply) if (present(t)) away = 0
  for (n = 1; n <= N; n++) {
    if (!OK[n] || F[n, 12] != "open" || F[n, 2] == "standing") continue
    r = settle_reason(n)
    if (r == "") continue
    F[n, 12] = "closed"; F[n, 17] = now; F[n, 18] = r; F[n, 22] = away; F[n, 24] = F[n, 19]
    F[n, 19] = "-"; F[n, 20] = 0
    changed = 1
    print "settled\t" clean(F[n, 1]) "\t" clean(F[n, 2]) "\t" away "\t" r "\t" clean(F[n, 24])
  }
  for (n = 1; n <= N; n++) {
    if (!OK[n] || F[n, 12] != "open" || F[n, 2] == "standing") continue
    if (F[n, 19] != "-" || F[n, 14] + 0 > 0 || F[n, 16] + 0 > 0) continue
    # An item the derived pass just marked non-deliverable is not a question
    # the operator will be asked. Keying one anyway lets it win the group and
    # close a duplicate that WAS still deliverable, which loses that question
    # for good: the survivor is skipped at every hand-over from then on.
    if (skip_reason[n] != "") continue
    key = merge_key(n)
    if (key == "") continue
    key = F[n, 2] "\001" key
    gn[key]++
    gi[key, gn[key]] = n
  }
  for (key in gn) {
    if (gn[key] < 2) continue
    best = gi[key, 1]
    for (i = 2; i <= gn[key]; i++) if (better(gi[key, i], best)) best = gi[key, i]
    src = (F[best, 23] == "-") ? "" : F[best, 23]
    for (i = 1; i <= gn[key]; i++) {
      j = gi[key, i]
      if (j == best) continue
      if (urank(F[j, 3]) < urank(F[best, 3])) F[best, 3] = F[j, 3]
      if (F[j, 5] + 0 < F[best, 5] + 0) F[best, 5] = F[j, 5]
      if (F[j, 4] != F[best, 4]) src = add_source(src, F[j, 4])
      if (F[j, 23] != "-") { np = split(F[j, 23], parts, ","); for (t = 1; t <= np; t++) if (parts[t] != F[best, 4]) src = add_source(src, parts[t]) }
      F[j, 12] = "closed"; F[j, 17] = now; F[j, 18] = "merged into " F[best, 1]
      F[j, 22] = away; F[j, 24] = F[j, 19]
      F[j, 19] = "-"; F[j, 20] = 0
      changed = 1
      print "merged\t" clean(F[j, 1]) "\t" clean(F[best, 1]) "\t" clean(F[j, 2])
    }
    if (src != "" && F[best, 23] != src) { F[best, 23] = src; changed = 1 }
  }
  # Reported only when something actually depended on it: a fleet with no
  # workers has no attention store and nothing to say about one.
  if (!attn_present && attn_needed) unavail["attention-store"] = 1
  for (t in unavail) print "unavailable\t" clean(t)
}
# attended(t): a reply at or after the tower last knocked and last handed
# over, after a knock (an attention session is opened by one), within the
# quiet interval. At-or-after: the stamps are whole seconds and the reply
# can only follow the tower turn that produced the knock.
function attended(t,   r) {
  if (!(t in tw_kt)) return 0
  r = tw_reply[t]; if (r <= 0 || tw_kt[t] <= 0) return 0
  # A stamp past now (a skewed clock, a planted marker) has not happened yet.
  return (r <= now && r >= tw_kt[t] && r > tw_dt[t] && now - r <= quiet)
}
# present(t): the operator is not away in that conversation: a reply within
# the quiet interval, or, while the marker has not appeared at all, a knock
# or hand-over of that tower within the quiet interval (the marker is not
# proof of absence until the quiet interval has run). A lease held by a
# present tower is left alone even between a hand-over and its reply.
function present(t,   last) {
  if ((t in tw_reply) && tw_reply[t] > 0 && tw_reply[t] <= now) return (now - tw_reply[t] <= quiet)
  if (!(t in tw_kt)) return 0
  last = (tw_kt[t] > tw_dt[t]) ? tw_kt[t] : tw_dt[t]
  return (last > 0 && last <= now && now - last <= quiet)
}
function derived_pass(   n, eff, o, w, ii) {
  for (n = 1; n <= N; n++) {
    skip_reason[n] = ""
    if (!OK[n] || F[n, 12] != "open") continue
    if (F[n, 16] + 0 > 0 && F[n, 16] + 0 <= now) { F[n, 16] = 0; changed = 1 }
    if (F[n, 19] != "-") {
      o = F[n, 19]; eff = F[n, 20] + 0
      if ((o in tw_reply) && tw_reply[o] + lease_iv > eff) eff = tw_reply[o] + lease_iv
      # An expired lease releases the item AND its hand-over: the tower that
      # held it may be dead, and the item must be deliverable again to
      # whichever tower asks next, that one included.
      if (eff <= now) { F[n, 19] = "-"; F[n, 20] = 0; F[n, 14] = 0; changed = 1 }
    }
    if (F[n, 6] == "attention") {
      w = F[n, 7]
      if (!(w in at_state)) skip_reason[n] = "its row is gone from the attention store"
      else if (F[n, 2] == "question") {
        if (at_state[w] != "awaiting-input") skip_reason[n] = "its row is no longer awaiting input (" clean(at_state[w]) ")"
        else {
          ii = (at_iid[w] == "") ? "-" : at_iid[w]
          if (ii != F[n, 8]) { F[n, 8] = ii; changed = 1 }
          if (at_prio[w] ~ /^(high|normal|low)$/ && at_prio[w] != F[n, 3]) { F[n, 3] = at_prio[w]; changed = 1 }
        }
      } else if (F[n, 2] == "news") {
        if (at_state[w] "." at_ts[w] != F[n, 8]) skip_reason[n] = "its row has moved on (" clean(at_state[w]) ")"
      }
    }
  }
}
# emit(out): the store rewritten, keeping every open record and only the
# most recent `limit` closed ones (acknowledged or settled, by the later of
# the two stamps). The sort runs only when there is something to drop.
function emit(out,   n, i, m, v, tv, j, line) {
  m = 0
  for (n = 1; n <= N; n++) if (OK[n] && F[n, 12] == "closed") {
    m++; ci[m] = n; ct[m] = (F[n, 15] + 0 > F[n, 17] + 0) ? F[n, 15] + 0 : F[n, 17] + 0
  }
  if (m > limit) {
    for (i = 2; i <= m; i++) {
      v = ci[i]; tv = ct[i]; j = i - 1
      while (j >= 1 && ct[j] < tv) { ci[j + 1] = ci[j]; ct[j + 1] = ct[j]; j-- }
      ci[j + 1] = v; ct[j + 1] = tv
    }
    for (i = limit + 1; i <= m; i++) { drop[ci[i]] = 1; changed = 1 }
  }
  for (n = 1; n <= N; n++) {
    if (!OK[n]) { print L[n] > out; continue }
    if (n in drop) continue
    line = F[n, 1]
    for (i = 2; i <= 24; i++) line = line "\t" F[n, i]
    print line > out
  }
  close(out)
}
# render_item(n, urg, age, orig): the hand-over line. The three overrides are
# the pairing rule(REQ-B1.3): a pair is delivered as one unit carrying the
# higher urgency, the older age, and both origins. Empty otherwise.
function srcs(n) { return F[n, 4] ((F[n, 23] == "-") ? "" : "," F[n, 23]) }
# One home for the rendered content pointer: the `item` line and the `pair`
# line of the same hand-over must never disagree about its shape.
function ptr_of(n) {
  return clean(F[n, 6] ":" ((F[n, 6] == "path") ? F[n, 9] "/" F[n, 7] : F[n, 7]) ((F[n, 8] == "-") ? "" : "@" F[n, 8]))
}
function render_item(n, urg, age, orig) {
  if (urg == "") urg = F[n, 3]
  if (age == "") age = now - F[n, 5]
  if (orig == "") orig = srcs(n)
  return "item\t" clean(F[n, 1]) "\t" clean(F[n, 2]) "\t" clean(urg) "\t" clean(orig) "\t" age "\t" ptr_of(n) "\t" clean(F[n, 10]) "\t" clean(F[n, 11])
}
# A record written before the settling task shipped carries twenty fields; it
# is completed here rather than refused, so an older store keeps its items.
{
  N++; L[N] = $0
  if (NF == 20) { $21 = "-"; $22 = 0; $23 = "-"; changed = 1 }
  if (NF == 23) { $24 = "-"; changed = 1 }
  if (rec_ok()) { OK[N] = 1; for (i = 1; i <= 24; i++) F[N, i] = $i } else OK[N] = 0
}
'

# run_store_pass <mode> [<awk -v assignments>...] — the derived pass plus
# one verb's action over the store, the new store landing in $SCRATCH/new and
# the action's result lines on stdout: a `status` or `decision` line, then
# `changed<TAB>0|1`. Free text (the record, a reason) travels through files,
# never through -v, which escape-processes its value: a backslash in a
# closing condition would otherwise tear the record.
run_store_pass() {
  _mode=$1
  shift
  awk -F '\t' -v OFS='\t' -v mode="$_mode" -v now="$now" -v quiet="${quiet:-0}" -v lease_iv="${lease_iv:-0}" \
    -v limit="${catchup_limit:-20}" -v towers_file="$SCRATCH/towers" -v attn_file="$attn_file_for_awk" \
    -v evid_file="${EVID_FILE:-}" -v do_settle="${DO_SETTLE:-0}" \
    -v attn_present="$([ -n "$attn_file_for_awk" ] && echo 1 || echo 0)" \
    -v out="$SCRATCH/new" -v tower="${tower:-}" -v record_file="$SCRATCH/record" -v reason_file="$SCRATCH/reason" "$@" "$AWK_Q"'
  BEGIN {
    load_towers(towers_file); load_attention(attn_file); load_evidence(evid_file); changed = 0
    record = ""; reason = ""
    if ((getline record < record_file) <= 0) record = ""
    close(record_file)
    if ((getline reason < reason_file) <= 0) reason = ""
    close(reason_file)
  }
  END {
    derived_pass()
    # The settling pass runs before any verb acts, so a `next` that follows it
    # in the same iteration selects from what the pass left (REQ-B1.1).
    if (mode == "pass" || do_settle == 1) settle_pass()
    if (mode == "pass") { emit(out); print "changed\t" changed; exit }
    if (mode == "add") {
      t = 0
      for (n = 1; n <= N; n++) if (OK[n] && F[n, 1] == item) t = n
      if (t && F[t, 12] == "open") { print "status\tpresent"; emit(out); print "changed\t" changed; exit }
      $0 = record
      if (!rec_ok()) fail("the new record does not parse")
      if (t) {
        # The same content home queued again after its item closed: the
        # record is re-opened in place, born now, so one home is one id.
        for (i = 1; i <= 24; i++) F[t, i] = $i
        changed = 1; print "status\treopened"; emit(out); print "changed\t" changed; exit
      }
      N++; OK[N] = 1; L[N] = ""
      for (i = 1; i <= 24; i++) F[N, i] = $i
      changed = 1; print "status\tadded"; emit(out); print "changed\t" changed; exit
    }
    if (mode == "ack" || mode == "settle" || mode == "shelve") {
      t = 0
      for (n = 1; n <= N; n++) if (OK[n] && F[n, 1] == item) t = n
      if (!t) print "status\tabsent"
      else if (F[t, 12] == "closed") print "status\tclosed"
      else if (mode == "ack") {
        if (F[t, 19] != tower) print "status\tnolease\t" clean(F[t, 19])
        else { F[t, 12] = "closed"; F[t, 15] = now; F[t, 19] = "-"; F[t, 20] = 0; changed = 1; print "status\tok\t" clean(F[t, 2]) }
      } else if (mode == "settle") {
        F[t, 12] = "closed"; F[t, 17] = now; F[t, 18] = reason; F[t, 24] = F[t, 19]
        F[t, 19] = "-"; F[t, 20] = 0; changed = 1
        print "status\tok\t" clean(F[t, 2]) "\t" clean(F[t, 24])
      } else {
        if (F[t, 19] != "-" && F[t, 19] != tower) print "status\tnolease\t" clean(F[t, 19])
        else { F[t, 16] = until; F[t, 19] = "-"; F[t, 20] = 0; F[t, 14] = 0; changed = 1; print "status\tok\t" clean(F[t, 2]) }
      }
      emit(out); print "changed\t" changed; exit
    }
    if (mode == "next") {
      me = attended(tower)
      top = 0; nwait = 0
      for (n = 1; n <= N; n++) {
        if (!OK[n] || F[n, 12] != "open" || F[n, 2] == "standing") continue
        if (F[n, 16] + 0 > 0) continue
        if (skip_reason[n] != "") { print "skip\t" clean(F[n, 1]) "\t" skip_reason[n]; continue }
        o = F[n, 19]
        if (o == tower) { if (F[n, 14] + 0 > 0) continue }
        else if (o != "-") { if (present(o)) continue }
        nwait++
        cand[n] = 1
        if (!top || better(n, top)) top = n
      }
      kt = tw_kt[tower]; dt = tw_dt[tower]; r = tw_reply[tower]
      if (r > now) r = 0
      nkt = kt; nkitem = tw_kitem[tower]; ndt = dt; nditem = tw_ditem[tower]
      if (!top) print "decision\tnone"
      else if (me) {
        target = top
        if (kt > dt && tw_kitem[tower] != "-") for (n in cand) if (F[n, 1] == tw_kitem[tower]) target = n
        # Pairing (REQ-B1.3): at most two candidates of the same kind naming
        # the same subject go over as ONE unit, so the hand-over stays one
        # decision and a third on that subject waits for the next call.
        # The partner is the OLDEST candidate on the subject, not the
        # best-ranked one: the delivered pair inherits the highest urgency and
        # the oldest age of its sources, so taking the oldest keeps both
        # inherited fields meaningful, and starvation is the failure that
        # actually degrades a decision queue. The id breaks a tie.
        # `cand` admits an item an away tower still holds, because the target
        # may take that lease over. A partner may not: REQ-B1.3 pairs only
        # items that are neither leased nor delivered, so a pair is one
        # hand-over of two waiting items, never a second tower reclaim.
        mate = 0
        if (F[target, 21] != "-")
          for (n in cand)
            if (n != target && F[n, 19] == "-" && F[n, 14] + 0 == 0 && F[n, 2] == F[target, 2] && F[n, 21] == F[target, 21])
              if (!mate || F[n, 5] + 0 < F[mate, 5] + 0 || (F[n, 5] + 0 == F[mate, 5] + 0 && F[n, 1] < F[mate, 1])) mate = n
        purg = F[target, 3]; page = now - F[target, 5]; porig = srcs(target)
        if (mate) {
          if (urank(F[mate, 3]) < urank(purg)) purg = F[mate, 3]
          if (now - F[mate, 5] > page) page = now - F[mate, 5]
          porig = porig "," srcs(mate)
          F[mate, 19] = tower; F[mate, 20] = int(now + lease_iv); F[mate, 14] = now
        }
        F[target, 19] = tower; F[target, 20] = int(now + lease_iv); F[target, 14] = now; changed = 1
        ndt = now; nditem = F[target, 1]
        print "decision\tdeliver\t" clean(F[target, 1]) "\t" clean(F[target, 2]) "\t" clean(purg) "\t" (mate ? clean(F[mate, 1]) : "-")
        print render_item(target, purg, page, porig)
        if (mate) print "pair\t" clean(F[mate, 1]) "\t" ptr_of(mate) "\t" clean(F[mate, 10]) "\t" clean(F[mate, 11])
      } else {
        # The same reading attended() takes: a reply stamped in the same second
        # as the knock answers the knock; a hand-over needs a later one.
        pend_deliv = (dt > 0 && dt >= kt && r <= dt && now - dt <= quiet)
        pend_knock = (kt > 0 && kt > dt && r < kt)
        if (pend_deliv) print "decision\twait\thand-over outstanding"
        else if (pend_knock && tw_kitem[tower] == F[top, 1]) print "decision\twait\tknock outstanding"
        else {
          # A knock about a new top supersedes the earlier pin: the lease that
          # knock took goes with it, since that item was never handed over.
          if (tw_kitem[tower] != "-" && tw_kitem[tower] != F[top, 1])
            for (n = 1; n <= N; n++)
              if (OK[n] && F[n, 1] == tw_kitem[tower] && F[n, 19] == tower && F[n, 14] + 0 == 0) { F[n, 19] = "-"; F[n, 20] = 0 }
          if (F[top, 19] == "-") { F[top, 19] = tower; F[top, 20] = int(now + lease_iv) }
          F[top, 13] = now; changed = 1
          nkt = now; nkitem = F[top, 1]
          print "decision\tknock\t" clean(F[top, 1]) "\t" clean(F[top, 2]) "\t" clean(F[top, 3])
          print "knock\t" clean(F[top, 2]) "\t" clean(F[top, 3]) "\t" nwait
        }
      }
      print "delivery\t" nkt "\t" nkitem "\t" ndt "\t" nditem
      emit(out); print "changed\t" changed; exit
    }
    emit(out); print "changed\t" changed
  }' "$SCRATCH/snap"
}

# pass_failed <result> — 0 when the pass reported an I/O failure (its
# `fail` line), which is the host's, never the caller's.
pass_failed() {
  case "$1" in
    fail"$TAB"* | *"${NL}fail$TAB"*)
      err "the store pass failed: $(sanitize_printable "${1##*fail"$TAB"}" "(unprintable reason)")"
      return 0
      ;;
  esac
  return 1
}
NL='
'

# rebuild_if_absent — inside the lock: when the store is absent, rebuild it
# from the content homes and the event log (REBUILD in the header). The
# log lines a rebuild owes are written to a debt file under the surface
# inside the same critical section and drained after the lock is released,
# so a verb that fails between the two still leaves the debt for the next
# verb to pay.
rebuild_if_absent() {
  [ ! -f "$store_file" ] || return 0
  : >"$SCRATCH/dropped"
  : >"$SCRATCH/fresh"
  _rl=""
  [ ! -s "$log_file" ] || _rl=$log_file
  _ra=""
  [ ! -s "$attn_store" ] || _ra=$attn_store
  awk -F '\t' -v log_file="$_rl" -v attn_file="$_ra" "$AWK_PARSE"'
  function nz(s) { return (s == "") ? "-" : s }
  BEGIN {
    if (attn_file != "") {
      while ((rc = (getline l < attn_file)) > 0) {
        n = split(l, f, "\t"); if (n < 8) continue
        at_state[f[1]] = f[3]; at_ts[f[1]] = f[4]; at_prio[f[1]] = f[5]; at_iid[f[1]] = (n >= 10) ? f[10] : ""
      }
      close(attn_file)
      if (rc < 0) { print "fail\tcannot read the attention store"; exit }
    }
    nb = 0
    if (log_file != "") {
      # Event order matters: a birth after a closure re-opens the item, and
      # a closure after a birth closes it.
      while ((rc = (getline l < log_file)) > 0) {
        if (!parse(l, F, T) || !header_ok(F, T)) continue
        k = F["kind"]; it = ("item" in F) ? F["item"] : ""
        if (it == "") continue
        if (k == "born") {
          if (it in idx) i = idx[it]; else { nb++; i = nb; idx[it] = i; bid[i] = it }
          delete closed[it]
          bkind[i] = F["item_kind"]; burg[i] = F["urgency"]; borig[i] = F["origin"]; bts[i] = F["ts"] + 0
          bhome[i] = F["home"]; bptr[i] = F["pointer"]; binst[i] = F["instance"]; broot[i] = F["root"]; bpark[i] = F["park"]; bcl[i] = F["closes"]
          bsub[i] = ("subject" in F) ? F["subject"] : ""
        } else if (k == "acknowledged" || k == "settled" || k == "merged") closed[it] = 1
        else if (k == "dropped" && ("reason" in F) && F["reason"] == "rebuild") closed[it] = 1
      }
      close(log_file)
      if (rc < 0) { print "fail\tcannot read the event log"; exit }
    }
    for (i = 1; i <= nb; i++) {
      it = bid[i]
      if (it in closed) continue
      if (bhome[i] == "attention") {
        w = bptr[i]
        if (bkind[i] == "question" && (w in at_state) && at_state[w] == "awaiting-input") {
          covered[w] = 1
          ii = (at_iid[w] == "") ? "-" : at_iid[w]
          u = (at_prio[w] ~ /^(high|normal|low)$/) ? at_prio[w] : burg[i]
          print "cand\t" nz(bkind[i]) "\t" nz(u) "\t" nz(borig[i]) "\t" bts[i] "\tattention\t" w "\t" ii "\t" nz(broot[i]) "\t" nz(bpark[i]) "\t" nz(bcl[i]) "\t" it "\t" nz(bsub[i])
        } else if (bkind[i] == "news" && (w in at_state) && at_state[w] "." at_ts[w] == binst[i]) {
          print "cand\t" nz(bkind[i]) "\t" nz(burg[i]) "\t" nz(borig[i]) "\t" bts[i] "\tattention\t" w "\t" nz(binst[i]) "\t-\t-\t" nz(bcl[i]) "\t" it "\t" nz(bsub[i])
        } else print "drop\t" it
      } else if (bhome[i] == "path") {
        print "path\t" nz(bkind[i]) "\t" nz(burg[i]) "\t" nz(borig[i]) "\t" bts[i] "\tpath\t" nz(bptr[i]) "\t-\t" nz(broot[i]) "\t" nz(bpark[i]) "\t" nz(bcl[i]) "\t" it "\t" nz(bsub[i])
      } else print "drop\t" it
    }
    for (w in at_state) if (at_state[w] == "awaiting-input" && !(w in covered)) {
      ii = (at_iid[w] == "") ? "-" : at_iid[w]
      u = (at_prio[w] ~ /^(high|normal|low)$/) ? at_prio[w] : "normal"
      print "cand\tquestion\t" u "\t" w "\t" at_ts[w] + 0 "\tattention\t" w "\t" ii "\t-\t-\t'"$QUESTION_CLOSES"'\t-\tworker:" w
    }
  }' >"$SCRATCH/cands" 2>"$SCRATCH/cands.err" || {
    err "the rebuild pass failed: $(sanitize_printable "$(head -n 1 "$SCRATCH/cands.err" 2>/dev/null)" "(no diagnostic)")"
    exit 6
  }
  if [ "$(head -n 1 "$SCRATCH/cands" 2>/dev/null | cut -f 1)" = fail ]; then
    err "the rebuild pass failed: $(sanitize_printable "$(head -n 1 "$SCRATCH/cands" | cut -f 2)" "(no diagnostic)")"
    exit 6
  fi
  : >"$SCRATCH/new"
  _seen=""
  while IFS="$TAB" read -r _tag _k _u _o _b _h _p _i _r _pk _c _was _sub; do
    case "$_tag" in
      drop)
        printf '%s\n' "$_k" >>"$SCRATCH/dropped"
        continue
        ;;
      cand | path) ;;
      *) continue ;;
    esac
    # A candidate that fails the record grammar is dropped, never repaired:
    # a rewritten field would register an item nobody registered.
    if ! is_one_of "$_k" "$Q_KINDS" || ! is_one_of "$_u" "$Q_URGENCIES" || ! is_handle "$_o" \
      || ! is_epoch "$_b" || ! is_text "$_c" 512 || ! is_text "$_i" 256 || ! is_text "$_pk" 1024; then
      [ "$_was" = "-" ] || printf '%s\n' "$_was" >>"$SCRATCH/dropped"
      continue
    fi
    if [ "$_tag" = path ]; then
      # The same containment check `add` ran, on the home as it is now: the
      # content must still be there, under its root, not through a link.
      if ! (check_pointer "$_r" "$_p" content) >/dev/null 2>&1; then
        printf '%s\n' "$_was" >>"$SCRATCH/dropped"
        continue
      fi
    fi
    _id=$(id_for "$_k" "$_h" "$_p" "$_i" "$_r")
    if [ "$_was" != "-" ] && [ "$_was" != "$_id" ]; then
      err "rebuild: dropping a born line whose identifier does not derive from its own key ($(sanitize_printable "$_was" "?"))"
      printf '%s\n' "$_was" >>"$SCRATCH/dropped"
      continue
    fi
    case " $_seen " in *" $_id "*) continue ;; esac
    _seen="$_seen $_id"
    # A born line from before the subject field shipped carries none, and one
    # that carries an unusable value is treated the same way: the worker the
    # item came from is what its content home still attests. `-` is a legal
    # subject but is also what an absent field reads as, so it takes the
    # derivation too.
    if [ "$_sub" = "-" ] || ! is_subject "$_sub"; then
      if [ "$_h" = attention ]; then
        _sub="worker:$_p"
      elif [ "$_o" != operator ]; then
        _sub="worker:$_o"
      else
        _sub=-
      fi
    fi
    if [ "$_was" = "-" ]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_id" "$_k" "$_u" "$_o" "$_b" "$_h" "$_p" "$_i" "$_r" "$_pk" "$_c" "$_sub" >>"$SCRATCH/fresh"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\topen\t0\t0\t0\t0\t0\t-\t-\t0\t%s\t0\t-\t-\n' \
      "$_id" "$_k" "$_u" "$_o" "$_b" "$_h" "$_p" "$_i" "$_r" "$_pk" "$_c" "$_sub" >>"$SCRATCH/new" || exit 6
  done <"$SCRATCH/cands"
  # The debt lands before the store: a store whose births could never be
  # logged is worse than no store, which the next verb rebuilds again. A
  # predecessor's unpaid debt is carried, not replaced.
  _debt="$surface/rebuild.debt"
  if [ -d "$_debt" ] || [ -L "$_debt" ]; then
    err "cannot write the rebuild's log debt: $(sanitize_printable "$_debt" "(unprintable path)") is not a plain file"
    exit 6
  fi
  {
    [ ! -f "$_debt" ] || grep -v '^session$' "$_debt"
    printf 'session\n'
    sed 's/^/born\t/' "$SCRATCH/fresh"
    sed 's/^/dropped\t/' "$SCRATCH/dropped"
  } >"$SCRATCH/debt" 2>/dev/null || {
    err "cannot record the rebuild's log debt"
    exit 6
  }
  PENDING_TMP=$(mktemp "$surface/.debt.XXXXXX" 2>/dev/null) || {
    err "cannot create a scratch file for the rebuild's log debt"
    exit 6
  }
  if ! cat "$SCRATCH/debt" >"$PENDING_TMP" || ! mv -f "$PENDING_TMP" "$_debt"; then
    err "cannot write the rebuild's log debt"
    exit 6
  fi
  PENDING_TMP=""
  commit_store || exit 6
  # The per-tower delivery records describe hand-overs of the lost store;
  # a rebuilt item is undelivered, so the records go with the store.
  # shellcheck disable=SC2012
  ls -1 "$delivery_dir" 2>/dev/null | while IFS= read -r _dn; do
    is_tower "$_dn" && rm -f "$delivery_dir/$_dn"
  done
  err "the queue store was absent and has been rebuilt from the content homes ($(grep -c . "$SCRATCH/fresh") registered from their homes, $(grep -c . "$SCRATCH/dropped") dropped)"
}

# drain_debt — the log lines a rebuild owes, paid after the lock is released
# (this verb's rebuild or a predecessor's that died before paying). A line
# that lands leaves the file; one dropped at the log's own lock wait stays
# for the next verb; one the log refuses outright is reported and dropped,
# since keeping it would wedge every later verb on the same line. The
# debt's fate never sets this verb's exit: that is its own owed line's.
drain_debt() {
  _debt="$surface/rebuild.debt"
  [ -f "$_debt" ] || return 0
  check_private_file "$_debt"
  _keep=$(mktemp "$surface/.debt.XXXXXX" 2>/dev/null) || {
    err "cannot create a scratch file for the log debt"
    exit 6
  }
  PENDING_TMP=$_keep
  _retry=0
  _dsaved=$LOG_FAILED
  while IFS= read -r _dl; do
    IFS="$TAB" read -r _dk _f1 _f2 _f3 _f4 _f5 _f6 _f7 _f8 _f9 _f10 _f11 _f12 <<EOF
$_dl
EOF
    LOG_FAILED=0
    case "$_dk" in
      session)
        if [ -n "${tower:-}" ]; then
          owe_log session --now "$now" --tower "$tower" event=rebuild
        else
          owe_log session --now "$now" event=rebuild
        fi
        ;;
      born)
        is_item_id "$_f1" || continue
        is_epoch "$_f5" || _f5=$now
        is_subject "$_f12" || _f12=-
        owe_log born --now "$_f5" item="$_f1" item_kind="$_f2" urgency="$_f3" origin="$_f4" \
          home="$_f6" pointer="$_f7" instance="$_f8" root="$_f9" park="$_f10" closes="$_f11" subject="$_f12"
        ;;
      dropped)
        is_item_id "$_f1" || continue
        owe_log dropped --now "$now" item="$_f1" reason=rebuild
        ;;
      *) continue ;;
    esac
    case "$LOG_FAILED" in
      0) ;;
      3)
        printf '%s\n' "$_dl" >>"$_keep"
        _retry=1
        ;;
      *) err "dropping a rebuild debt line the event log refuses ($(sanitize_printable "$_dk $_f1" "?")); it will not be paid" ;;
    esac
  done <"$_debt"
  LOG_FAILED=$_dsaved
  if [ "$_retry" = 1 ]; then
    mv -f "$_keep" "$_debt" 2>/dev/null || {
      err "cannot rewrite the rebuild's log debt"
      exit 6
    }
  else
    rm -f "$_keep" "$_debt"
  fi
  PENDING_TMP=""
}

# parse_now — the shared --now handling: a caller's epoch, else the clock.
parse_now() {
  if [ "$now_set" = 1 ]; then
    is_epoch "$now" || refuse "refusing --now '$(sanitize_printable "$now" "(unprintable epoch)")': an epoch is a canonical positive integer"
  else
    now=$(date +%s 2>/dev/null) || now=""
    is_epoch "$now" || {
      err "cannot read the clock (date +%s failed)"
      exit 6
    }
  fi
}

# --- evidence, gathered before the lock (REQ-B1.1) ----------------------------

DO_SETTLE=0
ev_stamp=none
ev_key=none

# put_file <path> <text> — replace a file on the sub-surface through a
# same-directory temp and rename, so a lock-free reader never sees it torn.
# Returns 1 rather than exiting: its callers run AFTER the store has committed,
# and have settlements to publish before they report the failure.
put_file() {
  # `mv` into a directory succeeds by moving the temp INSIDE it, so the write
  # would be lost and the temp leaked.
  if [ -d "$1" ] && [ ! -L "$1" ]; then
    err "$(sanitize_printable "$1" "(unprintable path)") is a directory where a file should be; refusing to write into it"
    return 1
  fi
  check_private_file "$1"
  PENDING_TMP=$(mktemp "$surface/.tqf.XXXXXX" 2>/dev/null) || {
    err "cannot create a scratch file for $(sanitize_printable "$1" "(unprintable path)")"
    return 1
  }
  printf '%s\n' "$2" >"$PENDING_TMP" 2>/dev/null || {
    err "cannot write $(sanitize_printable "$1" "(unprintable path)")"
    return 1
  }
  mv -f "$PENDING_TMP" "$1" 2>/dev/null || {
    err "cannot replace $(sanitize_printable "$1" "(unprintable path)")"
    return 1
  }
  PENDING_TMP=""
}

# ev_prepare <path or ""> — normalise the caller's already-derived facts into
# the two-tag table the settling pass reads, and add the content homes that
# have gone. Every read here happens BEFORE the lock is taken and nothing in
# it polls a remote: the pass consumes evidence, it never gathers it.
ev_prepare() {
  _ep=$1
  ev_stamp=none
  # Inside the 0700 sub-surface like every other scratch path this script mints,
  # and in its own cleanup slot rather than WORK_TMP's: that one is log
  # rotation's, and rotation runs inside the lock this file is prepared before.
  ensure_surface
  EVID_FILE=$(mktemp "$surface/.evid.XXXXXX" 2>/dev/null) || {
    err "cannot create a scratch file for the evidence table"
    exit 6
  }
  _ef=$_ep
  [ -n "$_ef" ] || _ef="$surface/evidence"
  if [ -d "$_ef" ] && [ ! -L "$_ef" ]; then
    err "the evidence table $(sanitize_printable "$_ef" "(unprintable path)") is a directory"
    exit 6
  fi
  if [ -e "$_ef" ] || [ -L "$_ef" ]; then
    # What settles an item settles it without the operator ever seeing it, so
    # the table is held to the same owner-only bar as the store itself.
    check_private_file "$_ef"
    _es=$(awk -F '\t' '$1 == "stamp" && $2 ~ /^[1-9][0-9]*$/ && length($2) <= 12 { print $2; exit }' "$_ef" 2>/dev/null) || _es=""
    [ -z "$_es" ] || ev_stamp=$_es
    awk -F '\t' -v OFS='\t' '
      # The same character set is_subject admits, so a fact can always reach
      # the subject it names.
      function keyok(s) { return (s != "" && length(s) <= 256 && s ~ /^[A-Za-z0-9._\/@:=+-]+$/) }
      $1 == "pr" && $3 ~ /^(open|merged)$/ && $2 ~ /^[1-9][0-9]*$/ && length($2) <= 12 { print "settles", "pr:" $2, "PR #" $2 " is " $3; next }
      $1 == "branch" && $3 == "commits" && keyok($2) { print "settles", "branch:" $2, "the branch " $2 " carries commits"; next }
      $1 == "ledger" && $3 == "closed" && keyok($2) { print "settles", "ledger:" $2, "the ledger item " $2 " is closed"; next }
      $1 == "unavailable" && keyok($2) { print "unavailable", $2; next }
    ' "$_ef" >>"$EVID_FILE" || {
      err "cannot read the evidence table"
      exit 6
    }
  elif [ -n "$_ep" ]; then
    refuse "no evidence table at $(sanitize_printable "$_ep" "(unprintable path)")"
  fi
  # A content home that has gone settles its item with that reason (REQ-B1.2).
  # The store is read lock-free here, the same way `list` and `counts` read it;
  # what the pass then acts on is re-read under the lock.
  if [ -f "$store_file" ]; then
    awk -F '\t' '(NF == 20 || NF == 23 || NF == 24) && $12 == "open" && $6 == "path" && $9 != "-" { print $1 "\t" $9 "/" $7 }' "$store_file" 2>/dev/null \
      | while IFS="$TAB" read -r _gi _gp; do
        is_item_id "$_gi" || continue
        [ -f "$_gp" ] || printf 'settles\titem:%s\tits content home has gone\n' "$_gi"
      done >>"$EVID_FILE"
  fi
}

# ev_lock_key — the reuse key, computed AFTER the fleet lock is taken. Every
# attention-store writer holds that same lock, so a key read before it can
# already be stale by the time the pass reads the rows, and the verb would
# reuse a pass that never saw the change. The evidence table is still gathered
# before the lock (REQ-B1.1); only this comparison sits inside it.
ev_lock_key() {
  ev_key=none
  [ "$ev_stamp" != none ] || return 0
  _fp=$(ev_fingerprint)
  # Nothing to compare against is not a match: the key stays `none` so the pass
  # runs rather than reusing a marker it cannot stand behind.
  [ -n "$_fp" ] || return 0
  ev_key="$ev_stamp.$_fp"
}

# ev_fingerprint — the settling pass's OTHER inputs, in one comparable value:
# the normalised table (the evidence facts plus the content homes that have
# gone) and the attention-store fields the pass acts on. The stamp alone would
# let a claim, a vanished row, a vanished home or a worker returning to its
# fork arrive between the pass and the `next` that reuses it, and go unsettled
# until the facts were next re-derived. Keyed: the handle and scope, the
# question and its option set, the state (which decides what may merge), the
# claim and the command. Not the heartbeat timestamp, which every worker
# rewrites seconds apart and which would defeat the reuse this exists to keep;
# the cost is that a `news` item whose row merely ticked can be merged by a
# reused pass, where the state and the text are what a question turns on.
ev_fingerprint() {
  {
    cat "$EVID_FILE" 2>/dev/null
    # Marked present or absent explicitly: a store that is there and empty and
    # one that is gone both contribute no rows, and the pass reads them
    # differently — gone is a source it could not reach, which holds the away
    # re-knock, and empty is every row having answered.
    if [ -f "$attn_store" ]; then
      printf 'attention\tpresent\n'
      awk -F '\t' '{ print $1 "\t" $2 "\t" $3 "\t" $6 "\t" $8 "\t" $11 "\t" $12 }' "$attn_store" 2>/dev/null
    else
      printf 'attention\tabsent\n'
    fi
  } | cksum 2>/dev/null | awk 'NF >= 2 { print $1 "." $2; exit }'
}

# ev_reuse — whether the settling pass this verb would run has already been
# run against the same evidence. The key the pass leaves is what makes one
# pass serve a whole tower-loop iteration (REQ-B1.1); unstamped evidence is
# never reused, because nothing then says the facts have not moved.
ev_reuse() {
  _pv=""
  if [ -f "$surface/settle.stamp" ]; then
    check_private_file "$surface/settle.stamp"
    IFS="$TAB" read -r _ps _pv <"$surface/settle.stamp" 2>/dev/null || _pv=""
  fi
  [ "$ev_stamp" != none ] && [ "$ev_key" != none ] && [ "$ev_key" = "$_pv" ]
}

# pass_writes <result> — the two files the settling pass owns, written while
# the lock is still held: the hold the away re-knock waits on (delivery task)
# and the key the next verb reuses. Returns 1 rather than exiting, so a caller
# whose store write has already committed can still publish what it settled
# before it reports the failure.
pass_writes() {
  _un=$(printf '%s\n' "$1" | awk -F '\t' '$1 == "unavailable" { print $2 }')
  if [ -n "$_un" ]; then
    put_file "$surface/reknock.hold" "$_un" || return 1
  elif [ -e "$surface/reknock.hold" ] || [ -L "$surface/reknock.hold" ]; then
    rm -f "$surface/reknock.hold" || {
      err "cannot clear the re-knock hold at $(sanitize_printable "$surface/reknock.hold" "(unprintable path)"); the away re-knock stays held"
      return 1
    }
  fi
  put_file "$surface/settle.stamp" "$now$TAB$ev_key" || return 1
}

# pass_logs <result> — one log line per thing the pass did, appended after the
# lock is released through the `log` verb's own critical section.
pass_logs() {
  # Materialised first: owe_log records a failed line in LOG_FAILED, which a
  # loop on the far side of a pipe would keep in its own subshell.
  printf '%s\n' "$1" | awk -F '\t' '$1 == "settled" || $1 == "merged" || $1 == "unavailable"' >"$SCRATCH/passlog"
  while IFS="$TAB" read -r _tag _p1 _p2 _p3 _p4 _p5; do
    case "$_tag" in
      settled) owe_log settled --now "$now" item="$_p1" item_kind="$_p2" away="$_p3" reason="$_p4" held_by="${_p5:--}" ;;
      merged) owe_log merged --now "$now" item="$_p1" into="$_p2" item_kind="$_p3" ;;
      unavailable) owe_log unavailable --now "$now" source="$_p1" ;;
    esac
  done <"$SCRATCH/passlog"
}

# pass_held — the seconds the fleet lock was held, against the stated bound.
pass_held() {
  _t1=$(clock_s)
  _held=$(awk -v a="${LOCK_AT:-0}" -v b="${_t1:-0}" 'BEGIN { d = b - a; if (d < 0 || a + 0 == 0) d = 0; printf "%.3f\n", d }')
  if awk -v b="$Q_SETTLE_HOLD_BOUND" -v d="$_held" 'BEGIN { exit (d > b) ? 0 : 1 }'; then
    err "the settling pass held the fleet lock for ${_held}s, past the stated bound of ${Q_SETTLE_HOLD_BOUND}s"
  fi
  printf '%s\n' "$_held"
}

# enter_store — the shared prologue of every locked verb: knobs, the surface
# (verified once before the lock), the bounded lock, the re-verification
# under it, the rebuild when the store is absent, then the snapshot taken
# after it (commit compares against the snapshot, so it must postdate the
# rebuild's own commit) and the tower table.
enter_store() {
  resolve_queue_knobs
  resolve_surface
  umask 077
  ensure_queue_surface
  SCRATCH=$(mktemp -d "$surface/.scratch.XXXXXX" 2>/dev/null) || {
    err "cannot create a scratch dir"
    exit 6
  }
  acquire_lock "$lock_wait"
  case $? in
    0) ;;
    1)
      err "the fleet lock stayed busy for the whole tower_hook_lock_wait; nothing written"
      exit 3
      ;;
    *) exit 6 ;;
  esac
  verify_queue_surface
  attn_file_for_awk=""
  [ ! -f "$attn_store" ] || attn_file_for_awk=$attn_store
  rebuild_if_absent
  take_snapshot
  build_towers_file
}

# leave_store — release the lock, then pay any log debt.
leave_store() {
  release_lock
  drain_debt
}

# ---------------------------------------------------------------------------
# add
# ---------------------------------------------------------------------------

cmd_add() {
  kind=""
  origin=""
  closes=""
  urgency=""
  worker=""
  root=""
  pointer=""
  park=""
  subject=""
  now=""
  now_set=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --kind | --origin | --closes | --urgency | --worker | --root | --pointer | --park | --subject | --now)
        [ "$#" -ge 2 ] || usage
        case "$1" in
          --kind) kind=$2 ;;
          --origin) origin=$2 ;;
          --closes) closes=$2 ;;
          --urgency) urgency=$2 ;;
          --worker) worker=$2 ;;
          --root) root=$2 ;;
          --pointer) pointer=$2 ;;
          --park) park=$2 ;;
          --subject) subject=$2 ;;
          --now)
            now=$2
            now_set=1
            ;;
        esac
        shift 2
        ;;
      *) usage ;;
    esac
  done
  [ -n "$kind" ] && [ -n "$origin" ] || usage
  is_one_of "$kind" "$Q_KINDS" || refuse "refusing kind '$(sanitize_printable "$kind" "(unprintable kind)")': one of $Q_KINDS"
  is_handle "$origin" || refuse "refusing origin '$(sanitize_printable "$origin" "(unprintable origin)")': a worker handle or the operator, a single token with no whitespace or path separator"
  [ -z "$subject" ] || is_subject "$subject" || refuse "refusing subject '$(sanitize_printable "$subject" "(unprintable subject)")': worker:<handle>, pr:<n>, branch:<name> or ledger:<key>"
  [ -z "$urgency" ] || is_one_of "$urgency" "$Q_URGENCIES" || refuse "refusing urgency '$(sanitize_printable "$urgency" "(unprintable urgency)")': high, normal or low"
  parse_now
  resolve_surface
  if [ "$kind" = standing ]; then
    [ -n "$closes" ] || closes=$STANDING_CLOSES
  else
    [ -n "$closes" ] || refuse "an item needs --closes <text>: the human action or the evidence that closes it"
  fi
  # The store is rendered back into the conversation, so it carries the
  # same redaction the log does. Redaction comes before the shape check: a
  # value that is only a secret redacts to a bracketed marker, the one shape
  # the log refuses, and the store must never take what the log will not.
  closes=$(redact "$closes")
  is_text "$closes" 512 || refuse "refusing the closing condition: at most 512 bytes with secrets redacted, no control byte or leading whitespace, not shaped like a JSON value"
  if [ "$kind" = standing ]; then
    case "$(printf '%s' "$closes" | tr '[:upper:]' '[:lower:]')" in
      *revoke*) ;;
      *) refuse "refusing the closing condition: a standing decision closes on the operator revoking the rule" ;;
    esac
  fi
  if promises_automation "$closes"; then
    refuse "refusing the closing condition: it promises a future automatic step; name the human action (an answer, a go-ahead) or the evidence that settles the item"
  fi
  instance=-
  PTR_ROOT=-
  PTR_REL=-
  park_rel=-
  case "$kind" in
    question | news)
      [ -n "$worker" ] || refuse "a $kind item points at a worker's attention row: --worker <handle>"
      [ -z "$pointer" ] || refuse "a $kind item points at its worker's row, not at a path"
      is_handle "$worker" || refuse "refusing worker handle '$(sanitize_printable "$worker" "(unprintable handle)")'"
      check_owned "${attn_store%/*}"
      check_owned "$attn_store"
      attn_row "$worker"
      [ -n "$row_state" ] || refuse "no attention row for worker '$worker'; the content is written to its home before the index record"
      if [ "$kind" = question ]; then
        [ -z "$urgency" ] || refuse "a worker question inherits its row's priority; drop --urgency"
        [ "$row_state" = awaiting-input ] || refuse "worker '$worker' is not awaiting input (its row says '$(sanitize_printable "$row_state" "?")'), so there is no question to queue"
        is_one_of "$row_prio" "$Q_URGENCIES" && urgency=$row_prio || urgency=normal
        instance=$row_iid
        [ -n "$instance" ] || instance=-
      else
        [ -n "$urgency" ] || { is_one_of "$row_prio" "$Q_URGENCIES" && urgency=$row_prio || urgency=normal; }
        instance="$row_state.$row_ts"
      fi
      is_text "$instance" 256 || refuse "the attention row's instance field is not a usable identifier"
      ihome=attention
      ptr=$worker
      if [ -n "$park" ]; then
        check_pointer "$root" "$park" park
        park_rel=$PTR_REL
      else
        [ -z "$root" ] || refuse "a $kind item takes --root only with --park <rel>, the parked bullet under that root"
      fi
      ;;
    *)
      [ -z "$worker" ] || refuse "a $kind item points at a file under a declared root: --root <dir> --pointer <rel>"
      [ -n "$pointer" ] || refuse "a $kind item needs --root <dir> --pointer <rel>, the content's home"
      check_pointer "$root" "$pointer" content
      ihome=path
      ptr=$PTR_REL
      if [ -n "$park" ]; then
        _cr=$PTR_ROOT
        check_pointer "$root" "$park" park
        park_rel=$PTR_REL
        PTR_ROOT=$_cr
      fi
      [ -n "$urgency" ] || urgency=normal
      ;;
  esac
  # The subject the settling pass joins evidence on. A caller that names one
  # wins; otherwise it is the worker the item came from, which is the only
  # subject derivable from the content home alone — a PR, a branch or a
  # ledger key is named by whoever captured the item.
  if [ -z "$subject" ]; then
    if [ "$ihome" = attention ]; then
      subject="worker:$ptr"
    elif [ "$origin" != operator ]; then
      subject="worker:$origin"
    else
      subject=-
    fi
  fi
  id=$(id_for "$kind" "$ihome" "$ptr" "$instance" "$PTR_ROOT")
  record=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\topen\t0\t0\t0\t0\t0\t-\t-\t0\t%s\t0\t-\t-' \
    "$id" "$kind" "$urgency" "$origin" "$now" "$ihome" "$ptr" "$instance" "$PTR_ROOT" "$park_rel" "$closes" "$subject")

  tower=""
  enter_store
  printf '%s\n' "$record" >"$SCRATCH/record" || {
    err "cannot write the scratch record"
    exit 6
  }
  result=$(run_store_pass add -v item="$id") || {
    err "the store pass failed"
    exit 6
  }
  pass_failed "$result" && exit 6
  st=$(printf '%s\n' "$result" | awk -F '\t' '$1 == "status" { print $2; exit }')
  changed=$(printf '%s\n' "$result" | awk -F '\t' '$1 == "changed" { print $2; exit }')
  [ "$changed" != 1 ] || commit_store || exit 6
  leave_store
  printf '%s\n' "$id"
  case "$st" in
    present)
      err "already queued as $id (the same content home); nothing changed"
      finish_exit
      ;;
    added | reopened)
      owe_log born --now "$now" item="$id" item_kind="$kind" urgency="$urgency" origin="$origin" \
        home="$ihome" pointer="$ptr" instance="$instance" root="$PTR_ROOT" park="$park_rel" closes="$closes" \
        subject="$subject"
      finish_exit
      ;;
    *)
      err "the store pass returned nothing usable"
      exit 6
      ;;
  esac
}

# ---------------------------------------------------------------------------
# next
# ---------------------------------------------------------------------------

cmd_next() {
  tower_flag=""
  evidence=""
  now=""
  now_set=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tower)
        [ "$#" -ge 2 ] || usage
        tower_flag=$2
        shift 2
        ;;
      --evidence)
        [ "$#" -ge 2 ] || usage
        evidence=$2
        shift 2
        ;;
      --now)
        [ "$#" -ge 2 ] || usage
        now=$2
        now_set=1
        shift 2
        ;;
      *) usage ;;
    esac
  done
  parse_now
  resolve_tower "$tower_flag"
  resolve_surface
  # The settling pass runs before the selection (REQ-B1.1), unless the pass
  # that serves this loop iteration has already run against the same evidence.
  ev_prepare "$evidence"
  enter_store
  ev_lock_key
  if ev_reuse; then DO_SETTLE=0; else DO_SETTLE=1; fi
  result=$(run_store_pass next) || {
    err "the store pass failed"
    exit 6
  }
  pass_failed "$result" && exit 6
  dec_what=""
  dec_item=""
  dec_kind=""
  dec_urg=""
  dec_pair=-
  changed=0
  out_line=""
  pair_line=""
  n_kt=0
  n_kitem=-
  n_dt=0
  n_ditem=-
  while IFS="$TAB" read -r _tag _a _b _c _d _e _f _g _h; do
    case "$_tag" in
      decision)
        dec_what=$_a
        dec_item=$_b
        dec_kind=$_c
        dec_urg=$_d
        [ -z "$_e" ] || dec_pair=$_e
        ;;
      delivery)
        n_kt=$_a
        n_kitem=$_b
        n_dt=$_c
        n_ditem=$_d
        ;;
      changed) changed=$_a ;;
      skip) err "not handing over $(sanitize_printable "$_a" "?"): $(sanitize_printable "$_b" "?")" ;;
      item) out_line="item	$_a	$_b	$_c	$_d	$_e	$_f	$_g	$_h" ;;
      pair) pair_line="pair	$_a	$_b	$_c	$_d" ;;
      knock) out_line="knock	$_a	$_b	$_c" ;;
    esac
  done <<EOF
$result
EOF
  case "$dec_what" in
    deliver | knock)
      # The delivery record goes first: a failure there leaves the store
      # untouched, whereas a stamped store with no record would hide the
      # item from its own holder until the backstop.
      read_delivery "$tower"
      write_delivery "$tower" "$n_kt" "$n_kitem" "$n_dt" "$n_ditem"
      if [ "$changed" = 1 ] && ! commit_store; then
        write_delivery "$tower" "$d_kt" "$d_kitem" "$d_dt" "$d_ditem"
        exit 6
      fi
      ;;
    *)
      [ "$changed" != 1 ] || commit_store || exit 6
      ;;
  esac
  pw=0
  if [ "$DO_SETTLE" = 1 ]; then
    pass_writes "$result" || pw=6
    # Measured on this path too, because the tower loop reaches the settling
    # pass through `next` far more often than through `settle`. pass_held is
    # what warns past the bound; `next` has no stdout slot for the number, and
    # announcing every in-bound hold on stderr would bury the one that matters.
    pass_held >/dev/null
  fi
  leave_store
  [ "$DO_SETTLE" != 1 ] || pass_logs "$result"
  # Same order as the pass verb: whatever this `next` settled is published
  # before a failed stamp/hold write becomes its exit.
  [ "$pw" = 0 ] || exit 6
  [ "$tower_fallback" = 0 ] || err "no presence identity resolved; this tower leases as '$tower' (a tower-session-scoped fallback)"
  case "$dec_what" in
    deliver)
      printf '%s\n' "$out_line"
      [ -z "$pair_line" ] || printf '%s\n' "$pair_line"
      # The one fail-open line: the hand-over stands, the failure is
      # surfaced, and the redelivery it risks is inside the loss budget.
      log_event delivered --now "$now" --tower "$tower" item="$dec_item" item_kind="$dec_kind" urgency="$dec_urg" pair="$dec_pair" \
        || err "the 'delivered' line did not reach the event log; the hand-over stands"
      finish_exit
      ;;
    knock)
      printf '%s\n' "$out_line"
      owe_log knocked --now "$now" --tower "$tower" item="$dec_item" item_kind="$dec_kind" urgency="$dec_urg"
      finish_exit
      ;;
    wait)
      [ -n "$(read_marker "$tower")" ] \
        || err "no attention marker for tower '$tower' (the prompt-submit hook has written nothing there since the knock); is the hook installed in this session?"
      finish_exit
      ;;
    *) finish_exit ;;
  esac
}

# ---------------------------------------------------------------------------
# ack, shelve, settle
# ---------------------------------------------------------------------------

# parse_item_args <verb> <args...> — the shared flag parse of the per-item
# verbs; sets item, tower_flag, span, reason, now. A flag the verb does not
# implement is a usage error, never silently discarded.
parse_item_args() {
  _pv=$1
  shift
  item=""
  tower_flag=""
  span=""
  reason=""
  now=""
  now_set=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tower | --for | --reason | --now)
        [ "$#" -ge 2 ] || usage
        case "$1" in
          --tower)
            [ "$_pv" != settle ] || usage
            tower_flag=$2
            ;;
          --for)
            [ "$_pv" = shelve ] || usage
            span=$2
            ;;
          --reason)
            [ "$_pv" = settle ] || usage
            reason=$2
            ;;
          --now)
            now=$2
            now_set=1
            ;;
        esac
        shift 2
        ;;
      -*) usage ;;
      *)
        [ -z "$item" ] || usage
        item=$1
        shift
        ;;
    esac
  done
  [ -n "$item" ] || usage
  is_item_id "$item" || refuse "refusing item id '$(sanitize_printable "$item" "(unprintable id)")': an identifier is i followed by eight hex digits"
  parse_now
}

# item_pass <mode> [<awk -v>...] — run the per-item pass and commit whatever
# the derived pass changed, whatever the verb's own status; sets st and
# st_extra.
item_pass() {
  result=$(run_store_pass "$@") || {
    err "the store pass failed"
    exit 6
  }
  pass_failed "$result" && exit 6
  st=$(printf '%s\n' "$result" | awk -F '\t' '$1 == "status" { print $2; exit }')
  st_extra=$(printf '%s\n' "$result" | awk -F '\t' '$1 == "status" { print $3; exit }')
  st_held=$(printf '%s\n' "$result" | awk -F '\t' '$1 == "status" { print $4; exit }')
  changed=$(printf '%s\n' "$result" | awk -F '\t' '$1 == "changed" { print $2; exit }')
  [ "$changed" != 1 ] || commit_store || exit 6
  leave_store
}

cmd_ack() {
  parse_item_args ack "$@"
  resolve_tower "$tower_flag"
  enter_store
  item_pass ack -v item="$item"
  case "$st" in
    ok)
      owe_log acknowledged --now "$now" --tower "$tower" item="$item" item_kind="$st_extra"
      finish_exit
      ;;
    closed)
      err "item $item is already closed; nothing to acknowledge (a logged no-op)"
      owe_log refused --now "$now" --tower "$tower" item="$item" verb=ack reason=already-closed
      finish_exit
      ;;
    nolease)
      if [ "$st_extra" = - ]; then
        err "refusing: tower '$tower' holds no lease on item $item (its lease lapsed at the backstop, so the item is deliverable again); an acknowledgement comes from the conversation the item was handed to (a logged duplicate no-op)"
      else
        err "refusing: tower '$tower' holds no lease on item $item (held by '$(sanitize_printable "$st_extra" "?")'); an acknowledgement comes from the conversation the item was handed to (a logged duplicate no-op)"
      fi
      owe_log refused --now "$now" --tower "$tower" item="$item" verb=ack reason=no-lease
      finish_exit 1
      ;;
    absent)
      err "no item $item in the queue"
      finish_exit 2
      ;;
    *)
      err "the store pass returned nothing usable"
      exit 6
      ;;
  esac
}

cmd_shelve() {
  parse_item_args shelve "$@"
  resolve_tower "$tower_flag"
  [ -z "$span" ] || is_duration "$span" || refuse "refusing --for '$(sanitize_printable "$span" "(unprintable span)")': a positive span such as 30m or 2h"
  enter_store
  if [ -n "$span" ]; then
    shelve_s=$(duration_seconds "$span")
  else
    shelve_s=$shelve_return
  fi
  # Whole seconds, at least one ahead: a sub-second span must still park.
  until=$(awk -v n="$now" -v s="$shelve_s" 'BEGIN { u = int(n + s); if (u <= n) u = n + 1; printf "%d\n", u }')
  item_pass shelve -v item="$item" -v until="$until"
  case "$st" in
    ok)
      owe_log shelved --now "$now" --tower "$tower" item="$item" returns="$until"
      finish_exit
      ;;
    closed)
      err "item $item is already closed; nothing to shelve (a logged no-op)"
      owe_log refused --now "$now" --tower "$tower" item="$item" verb=shelve reason=already-closed
      finish_exit
      ;;
    nolease)
      err "refusing: item $item is held by another tower's conversation ('$(sanitize_printable "$st_extra" "?")') (a logged no-op)"
      owe_log refused --now "$now" --tower "$tower" item="$item" verb=shelve reason=no-lease
      finish_exit 1
      ;;
    absent)
      err "no item $item in the queue"
      finish_exit 2
      ;;
    *)
      err "the store pass returned nothing usable"
      exit 6
      ;;
  esac
}

# cmd_settle_pass — `settle` with no item id: the level-triggered pass over
# every open item (REQ-B1.1). It takes no --tower: settling is evidence-driven
# and asks no conversation, which is also why it releases a lease it finds.
cmd_settle_pass() {
  evidence=""
  now=""
  now_set=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --evidence | --now)
        [ "$#" -ge 2 ] || usage
        case "$1" in
          --evidence) evidence=$2 ;;
          --now)
            now=$2
            now_set=1
            ;;
        esac
        shift 2
        ;;
      *) usage ;;
    esac
  done
  parse_now
  resolve_surface
  ev_prepare "$evidence"
  tower=""
  enter_store
  ev_lock_key
  result=$(run_store_pass pass) || {
    err "the store pass failed"
    exit 6
  }
  pass_failed "$result" && exit 6
  changed=$(printf '%s\n' "$result" | awk -F '\t' '$1 == "changed" { print $2; exit }')
  [ "$changed" != 1 ] || commit_store || exit 6
  # The store has committed, so what it settled is fact. A failure to publish
  # `reknock.hold` / `settle.stamp` is reported as this verb's 6 AFTER those
  # settlements have reached stdout and the event log, never instead of them.
  pw=0
  pass_writes "$result" || pw=6
  held=$(pass_held)
  leave_store
  printf '%s\n' "$result" | awk -F '\t' '$1 == "settled" || $1 == "merged" || $1 == "unavailable"'
  printf 'held\t%s\n' "$held"
  pass_logs "$result"
  [ "$pw" = 0 ] || exit 6
  finish_exit
}

cmd_settle() {
  # One non-flag argument is an item id, and `settle <id> --reason` closes
  # that item alone; with none, this is the pass above.
  _sk=0
  _sid=0
  for _sa in "$@"; do
    if [ "$_sk" = 1 ]; then
      _sk=0
      continue
    fi
    case "$_sa" in
      --reason | --now | --evidence | --tower | --for) _sk=1 ;;
      -*) ;;
      *) _sid=1 ;;
    esac
  done
  # The pass ends in finish_exit, so the per-item path below is reached only
  # when an item id was given.
  [ "$_sid" = 1 ] || cmd_settle_pass "$@"
  parse_item_args settle "$@"
  [ -n "$reason" ] || refuse "settle needs --reason <text>: what settled the item (the evidence, never a guess)"
  reason=$(redact "$reason")
  is_text "$reason" 512 || refuse "refusing the settle reason: at most 512 bytes with secrets redacted, no control byte or leading whitespace, not shaped like a JSON value"
  tower=""
  enter_store
  printf '%s\n' "$reason" >"$SCRATCH/reason" || {
    err "cannot write the scratch reason"
    exit 6
  }
  item_pass settle -v item="$item"
  case "$st" in
    ok)
      owe_log settled --now "$now" item="$item" item_kind="$st_extra" reason="$reason" held_by="${st_held:--}"
      finish_exit
      ;;
    closed)
      err "item $item is already closed (a logged no-op)"
      owe_log refused --now "$now" item="$item" verb=settle reason=already-closed
      finish_exit
      ;;
    absent)
      err "no item $item in the queue"
      finish_exit 2
      ;;
    *)
      err "the store pass returned nothing usable"
      exit 6
      ;;
  esac
}

# ---------------------------------------------------------------------------
# list, counts — lock-free reads
# ---------------------------------------------------------------------------

cmd_list() {
  all=0
  now=""
  now_set=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --all)
        all=1
        shift
        ;;
      --now)
        [ "$#" -ge 2 ] || usage
        now=$2
        now_set=1
        shift 2
        ;;
      *) usage ;;
    esac
  done
  parse_now
  resolve_surface
  verify_read_surface
  [ -f "$store_file" ] || {
    [ ! -d "$surface" ] || err "no queue store yet (absent; the next locked verb rebuilds it)"
    exit 0
  }
  SCRATCH=$(mktemp -d 2>/dev/null) || {
    err "cannot create a scratch dir"
    exit 6
  }
  awk -F '\t' -v now="$now" -v all="$all" "$AWK_Q"'
  END {
    for (n = 1; n <= N; n++) {
      if (!OK[n]) { bad++; continue }
      if (F[n, 12] != "open" && !all) continue
      if (F[n, 12] == "closed") st = "closed"
      else if (F[n, 16] + 0 > now) st = "shelved"
      else if (F[n, 14] + 0 > 0) st = "delivered"
      else if (F[n, 19] != "-") st = "leased:" F[n, 19]
      else st = "open"
      print clean(F[n, 1]) "\t" clean(F[n, 2]) "\t" clean(F[n, 3]) "\t" clean(F[n, 4]) "\t" F[n, 5] "\t" clean(st) "\t" clean(F[n, 6] ":" ((F[n, 6] == "path") ? F[n, 9] "/" F[n, 7] : F[n, 7]) ((F[n, 8] == "-") ? "" : "@" F[n, 8])) "\t" clean(F[n, 11])
    }
    if (bad > 0) print bad " store line(s) do not parse and were skipped" > "/dev/stderr"
  }' "$store_file" 2>"$SCRATCH/warn" || {
    err "cannot read the queue store"
    exit 6
  }
  [ ! -s "$SCRATCH/warn" ] || err "$(sanitize_printable "$(head -n 1 "$SCRATCH/warn")" "(unprintable diagnostic)")"
}

cmd_counts() {
  now=""
  now_set=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --now)
        [ "$#" -ge 2 ] || usage
        now=$2
        now_set=1
        shift 2
        ;;
      *) usage ;;
    esac
  done
  parse_now
  resolve_surface
  verify_read_surface
  if [ ! -f "$store_file" ]; then
    printf 'question\t0\napproval\t0\nrequest\t0\nnews\t0\nstanding\t0\ntotal\t0\ntop\t-\nmalformed\t0\nstore\tabsent\n'
    exit 0
  fi
  awk -F '\t' -v now="$now" "$AWK_Q"'
  END {
    top = 0; bad = 0
    for (n = 1; n <= N; n++) {
      if (!OK[n]) { bad++; continue }
      if (F[n, 12] != "open") continue
      if (F[n, 16] + 0 > now) continue
      c[F[n, 2]]++
      if (F[n, 2] == "standing") continue
      if (!top || better(n, top)) top = n
    }
    print "question\t" c["question"] + 0
    print "approval\t" c["approval"] + 0
    print "request\t" c["request"] + 0
    print "news\t" c["news"] + 0
    print "standing\t" c["standing"] + 0
    print "total\t" c["question"] + c["approval"] + c["request"] + c["news"]
    print "top\t" (top ? clean(F[top, 2]) : "-")
    print "malformed\t" bad
    print "store\tpresent"
  }' "$store_file" 2>/dev/null || {
    err "cannot read the queue store"
    exit 6
  }
}

# ---------------------------------------------------------------------------
# catchup — what settled without the operator, lock-free
# ---------------------------------------------------------------------------

cmd_catchup() {
  tower_flag=""
  since=""
  now=""
  now_set=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tower | --since | --now)
        [ "$#" -ge 2 ] || usage
        case "$1" in
          --tower) tower_flag=$2 ;;
          --since) since=$2 ;;
          --now)
            now=$2
            now_set=1
            ;;
        esac
        shift 2
        ;;
      *) usage ;;
    esac
  done
  parse_now
  [ -z "$since" ] || is_epoch "$since" || refuse "refusing --since '$(sanitize_printable "$since" "(unprintable epoch)")': an epoch is a canonical positive integer"
  resolve_queue_knobs
  resolve_surface
  verify_read_surface
  # The window is the operator's own last reply in this conversation; with no
  # tower and no --since it is the whole settled history the store still keeps.
  if [ -z "$since" ] && [ -n "$tower_flag" ]; then
    is_tower "$tower_flag" || refuse "refusing tower identity '$(sanitize_printable "$tower_flag" "(unprintable identity)")'"
    since=$(read_marker "$tower_flag")
    [ "$since" != unreadable ] || {
      err "cannot read the attention marker for tower '$tower_flag'"
      exit 6
    }
  fi
  [ -n "$since" ] || since=0
  if [ ! -f "$store_file" ]; then
    printf 'remainder\t0\tfloor\tno-store\nopen\tquestion\t0\nopen\tapproval\t0\nopen\trequest\t0\nopen\tnews\t0\nopen\tstanding\t0\n'
    exit 0
  fi
  SCRATCH=$(mktemp -d 2>/dev/null) || {
    err "cannot create a scratch dir"
    exit 6
  }
  # The list comes from the store, which keeps only the most recent closed
  # records; the count of everything past it comes from the event log, which
  # is where the history beyond the store's horizon lives (REQ-A1.5).
  awk -F '\t' -v now="$now" -v since="$since" -v limit="$catchup_limit" "$AWK_Q"'
  END {
    m = 0
    for (n = 1; n <= N; n++) {
      if (!OK[n]) continue
      # The open counts read the same way `counts` reads them, shelved items
      # excluded, so the two never disagree about what is waiting.
      if (F[n, 12] == "open") { if (F[n, 16] + 0 <= now) c[F[n, 2]]++; continue }
      if (F[n, 17] + 0 <= 0 || F[n, 17] + 0 <= since + 0) continue
      m++; ci[m] = n; ct[m] = F[n, 17] + 0
    }
    for (i = 2; i <= m; i++) {
      v = ci[i]; tv = ct[i]; j = i - 1
      while (j >= 1 && ct[j] < tv) { ci[j + 1] = ci[j]; ct[j + 1] = ct[j]; j-- }
      ci[j + 1] = v; ct[j + 1] = tv
    }
    shown = (m > limit) ? limit : m
    for (i = 1; i <= shown; i++) {
      n = ci[i]
      print "settled\t" clean(F[n, 1]) "\t" clean(F[n, 2]) "\t" clean(F[n, 3]) "\t" clean(srcs(n)) "\t" F[n, 17] "\t" F[n, 22] "\t" clean(F[n, 18]) "\t" clean(F[n, 24])
    }
    print "storetotal\t" m "\t" shown
    print "open\tquestion\t" c["question"] + 0
    print "open\tapproval\t" c["approval"] + 0
    print "open\trequest\t" c["request"] + 0
    print "open\tnews\t" c["news"] + 0
    print "open\tstanding\t" c["standing"] + 0
  }' "$store_file" >"$SCRATCH/list" 2>/dev/null || {
    err "cannot read the queue store"
    exit 6
  }
  stotal=$(awk -F '\t' '$1 == "storetotal" { print $2; exit }' "$SCRATCH/list")
  shown=$(awk -F '\t' '$1 == "storetotal" { print $3; exit }' "$SCRATCH/list")
  log_settled=0
  log_first=0
  if [ -s "$log_file" ]; then
    check_private_file "$log_file"
    _lc=$(awk -v since="$since" "$AWK_PARSE"'
      { if (!parse($0, F, T) || !header_ok(F, T)) next
        if (first == 0 || F["seq"] + 0 < first) first = F["seq"] + 0
        if ((F["kind"] == "settled" || F["kind"] == "merged") && F["ts"] + 0 > since + 0) n++ }
      END { printf "%d %d\n", n + 0, first + 0 }' "$log_file" 2>/dev/null) || _lc=""
    case "$_lc" in
      [0-9]*' '[0-9]*)
        log_settled=${_lc%% *}
        log_first=${_lc##* }
        ;;
    esac
  fi
  # The count is exact only when the log still holds its first line and no
  # line was ever dropped at a lock-wait expiry. Rotated, truncated, absent or
  # lossy, it can only bound the remainder from below — so it is said as a
  # floor rather than as a number nobody can stand behind.
  quality=floor
  why=log-rotated
  if [ ! -s "$log_file" ]; then
    why=log-absent
  elif [ "$log_first" != 1 ]; then
    why=log-rotated
  elif [ -s "$dropped_file" ]; then
    why=lines-dropped
  else
    quality=exact
    why=-
  fi
  remainder=$(awk -v l="$log_settled" -v s="$stotal" -v k="$shown" 'BEGIN {
    m = (l > s) ? l : s
    r = m - k
    if (r < 0) r = 0
    printf "%d\n", r }')
  awk -F '\t' '$1 == "settled"' "$SCRATCH/list"
  printf 'remainder\t%s\t%s\t%s\n' "$remainder" "$quality" "$why"
  awk -F '\t' '$1 == "open"' "$SCRATCH/list"
  [ "$quality" = exact ] \
    || err "the remainder is a floor, not a count ($why): the event log no longer covers the whole window"
}

cmd=${1:-}
[ -n "$cmd" ] || usage
shift
case "$cmd" in
  log) cmd_log "$@" ;;
  report) cmd_report "$@" ;;
  add) cmd_add "$@" ;;
  next) cmd_next "$@" ;;
  ack) cmd_ack "$@" ;;
  shelve) cmd_shelve "$@" ;;
  settle) cmd_settle "$@" ;;
  catchup) cmd_catchup "$@" ;;
  list) cmd_list "$@" ;;
  counts) cmd_counts "$@" ;;
  *)
    err "unknown command '$(sanitize_printable "$cmd" "(unprintable command)")' (log | report | add | next | ack | shelve | settle | catchup | list | counts)"
    exit 2
    ;;
esac
