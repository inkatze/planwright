#!/bin/bash
# Tests for the venture registry, catalog telemetry, the pending-observations
# drop, and the status and portfolio views built on them (REQ-A1.6, REQ-A1.7,
# REQ-A1.8, REQ-H1.6, REQ-J1.4, REQ-J1.7, REQ-J1.8 · D-8).
#
# What is pinned: registry round-trips through atomic writes; a missing, torn,
# or hostile registry rebuilds itself from a ventures_root scan that
# re-validates every identifier; a missing plugin-data home degrades the
# overlap scan instead of failing; the portfolio renders attention flags and
# catalog-health notes over fixture registries; and the drop reader
# neutralizes what it hands to planwright-side seed gathering.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REG="$REPO_ROOT/scripts/inception-registry.sh"

# shellcheck source=tests/lib/inception-fixture.sh
. "$REPO_ROOT/tests/lib/inception-fixture.sh"

failures=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected to find '$2' in output)" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_not_contains() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (did not expect '$2' in output)" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -x "$REG" ]; then
  echo "FAIL: registry helper missing or not executable at $REG" >&2
  exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
mkdir -p "$HOME"
export PLANWRIGHT_ROOT="$REPO_ROOT"
export PLANWRIGHT_INCEPTION_TODAY=2026-08-26
core_cfg="$tmp/core-defaults.yml"
printf 'ventures_root: ~/ventures\n' >"$core_cfg"
export PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg"
export PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter"
export PLANWRIGHT_REPO_ROOT=none
export PLANWRIGHT_LOCAL_CONFIG=""
unset CLAUDE_PLUGIN_DATA PLANWRIGHT_INCEPTION_DATA_DIR

roots="$HOME/ventures"
mkdir -p "$roots"
data="$tmp/data"

out=
rc=0
reg() {
  out="$(CLAUDE_PLUGIN_DATA="$data" "$REG" "$@" 2>&1)"
  rc=$?
}
reg_nodata() {
  out="$("$REG" "$@" 2>&1)"
  rc=$?
}
venture() {
  inception_fixture_write "$roots/$1" || exit 1
}
registry_file="$data/inception/registry.tsv"

# ---------------------------------------------------------------------------
# REQ-H1.6 — no plugin-data home: the registry is unavailable, said plainly,
# and the overlap scan degrades to a notice.
# ---------------------------------------------------------------------------
reg_nodata list
assert_eq "H1.6 no data home: list exits 6" "6" "$rc"
assert_contains "H1.6 no data home: names the degradation" "degraded	" "$out"
reg_nodata overlap
assert_eq "H1.6 no data home: overlap exits 6" "6" "$rc"
assert_contains "H1.6 no data home: overlap says it was skipped" "overlap scan skipped" "$out"

# ---------------------------------------------------------------------------
# REQ-A1.6 — round trip: register, read, update status, attention flags.
# ---------------------------------------------------------------------------
venture alpha
reg add alpha "$roots/alpha"
assert_eq "A1.6 add: exit 0" "0" "$rc"
assert_contains "A1.6 add: confirms" "registered	alpha" "$out"
reg get alpha
assert_eq "A1.6 get: exit 0" "0" "$rc"
assert_eq "A1.6 get: id, path, status, flags, date" \
  "$(printf 'venture\talpha\t%s\tExploring\tnone\t2026-08-26' "$roots/alpha")" "$out"
reg set alpha --status On-hold
assert_eq "A1.6 set status: exit 0" "0" "$rc"
reg set alpha --flags kill-approaching,blocked
assert_eq "A1.6 set flags: exit 0" "0" "$rc"
reg get alpha
assert_eq "A1.6 get after updates" \
  "$(printf 'venture\talpha\t%s\tOn-hold\tkill-approaching,blocked\t2026-08-26' "$roots/alpha")" "$out"
reg set alpha --status Sleeping
assert_eq "A1.6 set: an off-enum status is refused" "1" "$rc"
reg set alpha --flags 'bad flag'
assert_eq "A1.6 set: a malformed flag list is refused" "1" "$rc"
reg get nobody
assert_eq "A1.6 get: an unregistered id exits 1" "1" "$rc"
reg set alpha --status Exploring --flags none
reg get alpha
assert_contains "A1.6 flags clear back to none" "	Exploring	none	" "$out"
first_line="$(head -n 1 "$registry_file")"
assert_contains "A1.6 the registry carries its version header" "inception registry v1" "$first_line"

# ---------------------------------------------------------------------------
# REQ-A1.8 — identifiers are re-validated at consumption.
# ---------------------------------------------------------------------------
before="$(cat "$registry_file")"
reg add '../escape' "$roots/alpha"
assert_eq "A1.8 add: a traversal id is refused" "1" "$rc"
reg add 'Alpha' "$roots/alpha"
assert_eq "A1.8 add: an off-charset id is refused" "1" "$rc"
reg add beta "$roots/alpha"
assert_eq "A1.8 add: a path not named for the id is refused" "1" "$rc"
reg add ghost "$roots/ghost"
assert_eq "A1.8 add: a path with no bundle is refused" "1" "$rc"
assert_eq "A1.8 refused adds leave the registry untouched" "$before" "$(cat "$registry_file")"

# ---------------------------------------------------------------------------
# REQ-A1.6 — scan-rebuild: ventures_root recovers the fixture ventures,
# hostile directory names rejected, non-ventures ignored.
# ---------------------------------------------------------------------------
venture beta
inception_fixture_write "$roots/Bad Name" || exit 1
mkdir -p "$roots/not-a-venture"
sed "s/^\*\*Status:\*\* Exploring\$/**Status:** Killed/" "$roots/beta/brief.md" >"$tmp/b" && mv "$tmp/b" "$roots/beta/brief.md"
reg rebuild
assert_eq "A1.6 rebuild: exit 0" "0" "$rc"
assert_contains "A1.6 rebuild: recovers alpha" "$(printf 'venture\talpha\t%s\tExploring' "$roots/alpha")" "$out"
assert_contains "A1.6 rebuild: recovers beta with its status" "$(printf 'venture\tbeta\t%s\tKilled' "$roots/beta")" "$out"
assert_contains "A1.6 rebuild: rejects a hostile directory name" "rejected	Bad Name" "$out"
assert_not_contains "A1.6 rebuild: a directory without a bundle is not a venture" "not-a-venture" "$out"
reg list
assert_not_contains "A1.6 list after rebuild: no rebuild needed" "rebuilt	" "$out"

# Torn, missing, and hostile registries rebuild automatically at read time.
printf 'garbage\twithout\theader\n' >"$registry_file"
reg list
assert_eq "A1.6 torn registry: list still exits 0" "0" "$rc"
assert_contains "A1.6 torn registry: rebuilt on read" "rebuilt	" "$out"
assert_contains "A1.6 torn registry: ventures recovered" "venture	alpha	" "$out"
assert_contains "A1.6 torn registry: the file is whole again" "inception registry v1" "$(head -n 1 "$registry_file")"

rm -f "$registry_file"
reg get beta
assert_eq "A1.6 missing registry: get rebuilds and finds beta" "0" "$rc"
assert_contains "A1.6 missing registry: rebuild is reported" "rebuilt	" "$out"

printf '# planwright inception registry v1\nalpha\t/elsewhere/beta\tExploring\tnone\t2026-08-26\n' >"$registry_file"
reg list
assert_contains "A1.8 registry row whose path is not named for its id: rebuilt" "rebuilt	" "$out"

printf '# planwright inception registry v1\n../../etc\t/etc\tExploring\tnone\t2026-08-26\n' >"$registry_file"
reg list
assert_contains "A1.8 hostile registry row: rebuilt rather than trusted" "rebuilt	" "$out"
assert_not_contains "A1.8 hostile registry row: never surfaced" "/etc" "$out"

# Concurrency: interleaved writers never leave a torn registry.
reg rebuild
i=0
while [ $i -lt 12 ]; do
  CLAUDE_PLUGIN_DATA="$data" "$REG" set alpha --flags blocked >/dev/null 2>&1 &
  CLAUDE_PLUGIN_DATA="$data" "$REG" set beta --flags none >/dev/null 2>&1 &
  CLAUDE_PLUGIN_DATA="$data" "$REG" add alpha "$roots/alpha" >/dev/null 2>&1 &
  i=$((i + 1))
done
wait
reg list
assert_not_contains "A1.6 interleaved writes: the registry stays parseable" "rebuilt	" "$out"
assert_contains "A1.6 interleaved writes: both ventures present" "venture	beta	" "$out"
leftover="$(find "$data/inception" -name '.registry.*' | wc -l | tr -d ' ')"
assert_eq "A1.6 interleaved writes: no stray temp files" "0" "$leftover"

# ---------------------------------------------------------------------------
# REQ-A1.7 / REQ-H1.6 — the overlap scan hands the skill each live venture's
# framing; a corrupt brief degrades to a notice and the scan proceeds.
# ---------------------------------------------------------------------------
reg overlap
assert_eq "A1.7 overlap: exit 0" "0" "$rc"
assert_contains "A1.7 overlap: lists alpha with its framing" "overlap	alpha	Exploring	Ops leads re-key" "$out"
assert_contains "A1.7 overlap: closed ventures stay visible for extend-vs-new" "overlap	beta	Killed	" "$out"
rm -f "$roots/beta/brief.md"
mkdir "$roots/beta/brief.md"
reg overlap
assert_eq "H1.6 overlap over a corrupt brief: exit 0" "0" "$rc"
assert_contains "H1.6 overlap over a corrupt brief: degrades to a notice" "degraded	" "$out"
assert_contains "H1.6 overlap over a corrupt brief: the rest proceeds" "overlap	alpha	" "$out"
rmdir "$roots/beta/brief.md"
inception_fixture_write "$roots/beta" || exit 1

# ---------------------------------------------------------------------------
# REQ-J1.4 — the per-venture status view.
# ---------------------------------------------------------------------------
reg rebuild
reg status alpha
assert_eq "J1.4 status: exit 0" "0" "$rc"
assert_contains "J1.4 status: names the venture" "venture	alpha" "$out"
assert_contains "J1.4 status: gate readiness" "core	met" "$out"
assert_contains "J1.4 status: blockers" "unresolved	A-2	open" "$out"
assert_contains "J1.4 status: kill dates" "kill	KC-2	2026-09-15	approaching" "$out"
reg status nobody
assert_eq "J1.4 status: an unregistered venture exits 1" "1" "$rc"
reg status '../alpha'
assert_eq "J1.4 status: a hostile id is refused" "1" "$rc"

# ---------------------------------------------------------------------------
# REQ-J1.8 — telemetry and the feedback drop.
# ---------------------------------------------------------------------------
reg telemetry alpha unstaffed legal
assert_eq "J1.8 telemetry: exit 0" "0" "$rc"
reg telemetry alpha unstaffed legal
reg telemetry beta unstaffed legal
reg telemetry beta unstaffed security
reg telemetry alpha frame-discipline product-strategy
reg telemetry alpha sometimes legal
assert_eq "J1.8 telemetry: an unknown kind is refused" "1" "$rc"
reg telemetry alpha unstaffed '../x'
assert_eq "J1.8 telemetry: a hostile discipline is refused" "1" "$rc"

reg drop alpha "The gate prompt in alpha at $roots/alpha confused ops@example.com; see https://intranet.example.com/x and token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
assert_eq "J1.8 drop: exit 0" "0" "$rc"
reg drop alpha "$(printf 'two\nlines')"
assert_eq "J1.8 drop: multi-line text is refused" "1" "$rc"
reg drop alpha "$(printf 'bell\007here')"
assert_eq "J1.8 drop: control bytes are refused" "1" "$rc"
reg drop-read
assert_eq "J1.8 drop-read: exit 0" "0" "$rc"
assert_contains "J1.8 drop-read: the entry is read" "entry	2026-08-26	The gate prompt in" "$out"
assert_not_contains "J1.8 drop-read: the venture name is neutralized" " alpha " "$out"
assert_not_contains "J1.8 drop-read: the machine path is neutralized" "$roots" "$out"
assert_not_contains "J1.8 drop-read: the email is neutralized" "ops@example.com" "$out"
assert_not_contains "J1.8 drop-read: the URL is neutralized" "intranet.example.com" "$out"
assert_not_contains "J1.8 drop-read: the token is neutralized" "ghp_ABCDEFGH" "$out"
assert_contains "J1.8 drop-read: placeholders say what was removed" "<venture>" "$out"
reg_nodata drop-read
assert_eq "J1.8 drop-read without a data home: degrades, exit 6" "6" "$rc"

# The interim positioning is recorded in doctrine, not implied.
assert_contains "J1.8 the interim re-anchor pointer is in doctrine" "recorded as **interim**" \
  "$(cat "$REPO_ROOT/doctrine/storage-classes.md")"

# ---------------------------------------------------------------------------
# REQ-J1.7 — the portfolio listing over a fixture registry.
# ---------------------------------------------------------------------------
cards="$tmp/cards"
mkdir -p "$cards"
card() {
  printf '# %s — discipline card\n\n**Card-format:** 1\n**Card-id:** %s\n**Reviewed:** %s\n**Rot-rate:** %s\n' \
    "$1" "$1" "$2" "$3" >"$cards/$1.md"
}
card stale-medium 2025-01-10 medium
card fresh-medium 2026-06-01 medium
card fast-moving 2026-07-01 fast
card slow-method 2019-01-01 slow

venture gamma
sed 's/^_Skipped: appetite is set at the portfolio level.*$/Two weeks, then decide./' "$roots/gamma/brief.md" >"$tmp/g" && mv "$tmp/g" "$roots/gamma/brief.md"
venture delta
sed "s/^\*\*Status:\*\* Exploring\$/**Status:** Abandoned/" "$roots/delta/brief.md" >"$tmp/d" && mv "$tmp/d" "$roots/delta/brief.md"
reg rebuild
reg portfolio --cards "$cards"
assert_eq "J1.7 portfolio: exit 0" "0" "$rc"
assert_contains "J1.7 portfolio: alpha's attention flags" \
  "$(printf 'venture\talpha\tExploring\tkill-approaching,blocked\t25\tskipped')" "$out"
assert_contains "J1.7 portfolio: age versus appetite" \
  "$(printf 'venture\tgamma\tExploring\tkill-approaching,blocked,over-appetite\t25\t14')" "$out"
assert_contains "J1.7 portfolio: a closed venture carries no flags" \
  "$(printf 'venture\tdelta\tAbandoned\tnone')" "$out"
assert_contains "J1.7 portfolio: a medium card past its year" "$(printf 'card-review\tstale-medium\t2025-01-10\tmedium')" "$out"
assert_not_contains "J1.7 portfolio: a fresh card is quiet" "fresh-medium" "$out"
assert_contains "J1.7 portfolio: a fast card older than a live venture" "$(printf 'card-review\tfast-moving\t2026-07-01\tfast')" "$out"
assert_not_contains "J1.7 portfolio: a slow card is never date-flagged" "slow-method" "$out"
assert_contains "J1.7 portfolio: unstaffed-discipline frequency" "$(printf 'unstaffed\tlegal\t3')" "$out"
assert_contains "J1.7 portfolio: every unstaffed discipline counted" "$(printf 'unstaffed\tsecurity\t1')" "$out"
reg get alpha
assert_contains "J1.7 portfolio writes the flags back to the registry" "kill-approaching,blocked" "$out"

PLANWRIGHT_INCEPTION_TODAY=2026-10-02 reg portfolio --cards "$cards"
assert_contains "J1.7 portfolio: a tripped kill date" "$(printf 'venture\talpha\tExploring\tkill-tripped')" "$out"

rm -rf "$roots/gamma"
reg portfolio --cards "$cards"
assert_contains "J1.7 portfolio: a vanished venture is flagged, not fatal" "$(printf 'venture\tgamma\tExploring\tunreadable')" "$out"

empty_data="$tmp/empty-data"
mkdir -p "$tmp/empty-home/ventures"
out="$(HOME="$tmp/empty-home" CLAUDE_PLUGIN_DATA="$empty_data" "$REG" portfolio --cards "$tmp/no-cards" 2>&1)"
rc=$?
assert_eq "J1.7 portfolio over no ventures: exit 0" "0" "$rc"
assert_contains "J1.7 portfolio over no ventures: says none" "$(printf 'venture\tnone')" "$out"

if [ "$failures" -ne 0 ]; then
  echo "test-inception-registry: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-inception-registry: all assertions passed"
