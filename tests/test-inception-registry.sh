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
sed_i() { sed "$2" "$1" >"$1.new" && mv "$1.new" "$1"; }
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
: >"$tmp/not-a-dir"
out="$(CLAUDE_PLUGIN_DATA="$tmp/not-a-dir" "$REG" list 2>&1)"
assert_eq "H1.6 a data home that cannot be created: exit 6" "6" "$?"
assert_contains "H1.6 a data home that cannot be created: says so" "degraded	" "$out"
out="$(cd "$tmp" && CLAUDE_PLUGIN_DATA=relative-data "$REG" list 2>&1)"
assert_eq "H1.6 a relative data home is refused: exit 6" "6" "$?"
assert_eq "H1.6 a relative data home writes nothing in the working directory" "no" \
  "$([ -e "$tmp/relative-data" ] && echo yes || echo no)"
out="$(PLANWRIGHT_INCEPTION_TODAY=2026-02-30 CLAUDE_PLUGIN_DATA="$data" "$REG" list 2>&1)"
assert_eq "A1.6 an impossible pinned date is refused: exit 2" "2" "$?"

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

# A backslash in the path is stored as written, not read as an escape.
odd="$tmp/back\\tslash"
inception_fixture_write "$odd/zeta" || exit 1
reg add zeta "$odd/zeta"
reg get zeta
assert_eq "A1.6 a path with a backslash round-trips verbatim" \
  "$(printf 'venture\tzeta\t%s\tExploring\tnone\t2026-08-26' "$odd/zeta")" "$out"

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
reg add alpha ""
assert_eq "A1.8 add: an empty path is refused" "1" "$rc"
reg add alpha /
assert_eq "A1.8 add: the root directory is refused" "1" "$rc"
assert_eq "A1.8 refused adds leave the registry untouched" "$before" "$(cat "$registry_file")"

sed_i "$roots/alpha/brief.md" "s/^\*\*Status:\*\* Exploring\$/**Status:** On-hold/"
reg add alpha "$roots/alpha"
reg get alpha
assert_contains "A1.6 re-adding refreshes the status from the bundle" "	On-hold	" "$out"
sed_i "$roots/alpha/brief.md" "s/^\*\*Status:\*\* On-hold\$/**Status:** Exploring/"
reg add alpha "$roots/alpha"

# A failed write is a failure, never a reported success.
mkdir -p "$tmp/failing-bin"
printf '#!/bin/sh\nexit 1\n' >"$tmp/failing-bin/mktemp"
chmod +x "$tmp/failing-bin/mktemp"
PATH="$tmp/failing-bin:$PATH" reg add alpha "$roots/alpha"
assert_eq "A1.6 an unwritable registry: add exits 6" "6" "$rc"
assert_not_contains "A1.6 an unwritable registry: add claims nothing" "registered	" "$out"

# ---------------------------------------------------------------------------
# REQ-A1.6 — scan-rebuild: ventures_root recovers the fixture ventures,
# hostile directory names rejected, non-ventures ignored.
# ---------------------------------------------------------------------------
venture beta
inception_fixture_write "$roots/Bad Name" || exit 1
mkdir -p "$roots/not-a-venture"
sed_i "$roots/beta/brief.md" "s/^\*\*Status:\*\* Exploring\$/**Status:** Killed/"
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

# A valid registry that lost a row to a racing session gets it back on read.
reg rebuild
grep -v '^alpha	' "$registry_file" >"$tmp/lost" && cp "$tmp/lost" "$registry_file"
reg list
assert_contains "A1.6 a lost update: the read reports the merge" "rebuilt	merged" "$out"
assert_contains "A1.6 a lost update: the venture is back" "venture	alpha	" "$out"

# A missing ventures root writes nothing, so the registry rebuilds once the
# root is back.
rm -f "$registry_file"
mv "$roots" "$tmp/roots-away"
reg list
assert_eq "A1.6 no registry and no root (a fresh install): an empty list" "0" "$rc"
assert_not_contains "A1.6 no registry and no root: lists nothing" "venture	" "$out"
assert_eq "A1.6 missing root: no registry is written" "no" "$([ -e "$registry_file" ] && echo yes || echo no)"
printf 'garbage\n' >"$registry_file"
reg list
assert_eq "A1.6 a corrupt registry and no root to rebuild from: unavailable" "6" "$rc"
rm -f "$registry_file"
mv "$tmp/roots-away" "$roots"
reg list
assert_contains "A1.6 root back: the registry rebuilds" "venture	alpha	" "$out"

# A ventures root spelled with dot segments still yields a stable registry.
mkdir -p "$HOME/x"
printf 'ventures_root: ~/x/../ventures\n' >"$core_cfg"
rm -f "$registry_file"
reg list
reg set alpha --flags blocked
reg get alpha
assert_contains "A1.6 dot-segment root: a set survives the next read" "	blocked	" "$out"
assert_not_contains "A1.6 dot-segment root: no rebuild loop" "rebuilt	" "$out"
printf 'ventures_root: ~/ventures\n' >"$core_cfg"

out="$(cd "$HOME" && CLAUDE_PLUGIN_DATA="$data" "$REG" rebuild --root ventures 2>&1)"
assert_contains "A1.6 rebuild --root: a relative root is stored absolute" "$(printf 'venture\talpha\t%s\t' "$roots/alpha")" "$out"
mkdir -p "$tmp/other-root"
inception_fixture_write "$tmp/other-root/omega" || exit 1
reg rebuild --root "$tmp/other-root"
assert_contains "A1.6 rebuild --root: scans the named root" "venture	omega	" "$out"
assert_not_contains "A1.6 rebuild --root: and only it" "venture	alpha	" "$out"

# Symlinks: a linked registry is replaced, never written through; a linked
# venture directory is not a venture.
printf 'keep me\n' >"$tmp/link-target"
rm -f "$registry_file"
ln -s "$tmp/link-target" "$registry_file"
reg list
assert_contains "A1.6 symlinked registry: rebuilt" "rebuilt	" "$out"
assert_eq "A1.6 symlinked registry: the link target is untouched" "keep me" "$(cat "$tmp/link-target")"
assert_eq "A1.6 symlinked registry: replaced by a regular file" "no" "$([ -h "$registry_file" ] && echo yes || echo no)"
mkdir -p "$tmp/outside"
inception_fixture_write "$tmp/outside/linked" || exit 1
ln -s "$tmp/outside/linked" "$roots/linked"
reg rebuild
assert_not_contains "A1.6 rebuild: a symlinked venture directory is skipped" "venture	linked	" "$out"
rm -f "$roots/linked"

# Concurrency: interleaved writers never leave a torn registry, and a reader
# running alongside them never sees one.
reg rebuild
(
  n=0
  while [ $n -lt 150 ]; do
    awk -F '\t' 'NR == 1 && $0 != "# planwright inception registry v1" { bad = 1 } NR > 1 && NF != 5 { bad = 1 } END { exit bad }' \
      "$registry_file" 2>/dev/null || echo torn >>"$tmp/torn"
    n=$((n + 1))
  done
) &
i=0
while [ $i -lt 12 ]; do
  CLAUDE_PLUGIN_DATA="$data" "$REG" set alpha --flags blocked >/dev/null 2>&1 &
  CLAUDE_PLUGIN_DATA="$data" "$REG" set beta --flags none >/dev/null 2>&1 &
  CLAUDE_PLUGIN_DATA="$data" "$REG" add alpha "$roots/alpha" >/dev/null 2>&1 &
  i=$((i + 1))
done
wait
assert_eq "A1.6 interleaved writes: no reader saw a torn registry" "no" "$([ -s "$tmp/torn" ] && echo yes || echo no)"
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
CLAUDE_PLUGIN_DATA="$data" "$REG" status alpha >"$tmp/status-out" 2>/dev/null
assert_contains "J1.4 status: redirected to a file, the venture line survives" "venture	alpha" "$(cat "$tmp/status-out")"
assert_contains "J1.4 status: redirected to a file, the view follows" "core	met" "$(cat "$tmp/status-out")"
reg status nobody
assert_eq "J1.4 status: an unregistered venture exits 1" "1" "$rc"
reg status '../alpha'
assert_eq "J1.4 status: a hostile id is refused" "1" "$rc"
venture epsilon
reg add epsilon "$roots/epsilon"
sed_i "$roots/epsilon/brief.md" 's/^\*\*Format-version:\*\* 1\.0$/**Format-version:** 9.0/'
reg status epsilon
assert_eq "J1.4 status: an unsupported bundle version passes exit 3 through" "3" "$rc"
assert_contains "J1.4 status: the refusal reason is named" "degraded	" "$out"
rm -rf "$roots/epsilon"
reg status epsilon
assert_eq "J1.4 status: a vanished bundle exits 2" "2" "$rc"

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
assert_eq "J1.8 drop: the drop is private to the operator" "$data/inception/drop.tsv" \
  "$(find "$data/inception/drop.tsv" -perm 0600)"
assert_eq "J1.8 telemetry: the log is private to the operator" "$data/inception/telemetry.tsv" \
  "$(find "$data/inception/telemetry.tsv" -perm 0600)"
reg drop-read
assert_eq "J1.8 drop-read: exit 0" "0" "$rc"
assert_contains "J1.8 drop-read: the entry is read" "entry	2026-08-26	The gate prompt in" "$out"
assert_not_contains "J1.8 drop-read: the venture name is neutralized" " alpha " "$out"
assert_not_contains "J1.8 drop-read: the machine path is neutralized" "$roots" "$out"
assert_not_contains "J1.8 drop-read: the email is neutralized" "ops@example.com" "$out"
assert_not_contains "J1.8 drop-read: the URL is neutralized" "intranet.example.com" "$out"
assert_not_contains "J1.8 drop-read: the token is neutralized" "ghp_ABCDEFGH" "$out"
assert_contains "J1.8 drop-read: placeholders say what was removed" "<venture>" "$out"
reg drop alpha "Compare beta with Alpha's flow (see ventures/alpha/brief.md, \`$roots/beta/plan.md\`), Northwind Signals at intranet.example.com, key AKIAIOSFODNN7EXAMPLE, ping @opslead"
reg drop alpha "Café ops leads liked it; ops@example.com's note, @alice's view, db at 10.0.4.17 and db.internal:5432, the market moved"
venture zed
sed_i "$roots/zed/brief.md" "s/^# Northwind Signals — Brief\$/# Bob’s Ark — Brief/"
reg add zed "$roots/zed"
reg drop zed "Asked Bob’s Ark about it"
assert_eq "J1.8 drop: UTF-8 text is accepted" "0" "$rc"
reg drop-read
assert_not_contains "J1.8 drop-read: another registered venture is neutralized" "beta" "$out"
assert_not_contains "J1.8 drop-read: capitalized and possessive ids are neutralized" "Alpha's" "$out"
assert_not_contains "J1.8 drop-read: an id inside a relative path is neutralized" "ventures/alpha" "$out"
assert_not_contains "J1.8 drop-read: the venture title is neutralized" "Northwind" "$out"
assert_not_contains "J1.8 drop-read: a bare domain is neutralized" "intranet.example" "$out"
assert_not_contains "J1.8 drop-read: an access-key id is neutralized" "AKIAIOSFODNN7EXAMPLE" "$out"
assert_not_contains "J1.8 drop-read: a handle is neutralized" "@opslead" "$out"
assert_contains "J1.8 drop-read: UTF-8 text survives" "Café ops leads" "$out"
assert_not_contains "J1.8 drop-read: a possessive email is neutralized" "ops@example.com" "$out"
assert_not_contains "J1.8 drop-read: a possessive handle is neutralized" "@alice" "$out"
assert_not_contains "J1.8 drop-read: an IP address is neutralized" "10.0.4.17" "$out"
assert_not_contains "J1.8 drop-read: a host and port are neutralized" "db.internal" "$out"
assert_contains "J1.8 drop-read: a title with typographic punctuation is neutralized" "Asked <venture> about it" "$out"
assert_contains "J1.8 drop-read: a title matches whole words only" "the market moved" "$out"
mv "$registry_file" "$tmp/registry-aside"
mv "$roots" "$tmp/roots-aside"
reg drop-read
assert_eq "J1.8 drop-read without a registry: still reads" "0" "$rc"
assert_not_contains "J1.8 drop-read without a registry: ids the drop names stay neutralized" " alpha " "$out"
mv "$tmp/roots-aside" "$roots"
mv "$tmp/registry-aside" "$registry_file"
printf 'not-a-date\talpha\tescape %s[31m here\n' "$(printf '\033')" >>"$data/inception/drop.tsv"
reg drop-read
assert_not_contains "J1.8 drop-read: a hostile drop row loses its escape byte" "$(printf '\033')" "$out"
assert_contains "J1.8 drop-read: a hostile drop row is undated" "entry	undated	escape" "$out"
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
card fast-fresh 2026-08-20 fast
card slow-method 2019-01-01 slow

venture gamma
sed_i "$roots/gamma/brief.md" 's/^_Skipped: appetite is set at the portfolio level.*$/Two weeks, then decide./'
venture delta
sed_i "$roots/delta/brief.md" "s/^\*\*Status:\*\* Exploring\$/**Status:** Abandoned/"
reg rebuild
reg portfolio --cards "$cards"
assert_eq "J1.7 portfolio: exit 0" "0" "$rc"
assert_contains "J1.7 portfolio: alpha's attention flags" \
  "$(printf 'venture\talpha\tExploring\tkill-approaching,blocked,open-forks\t25\tskipped')" "$out"
assert_contains "J1.7 portfolio: age versus appetite" \
  "$(printf 'venture\tgamma\tExploring\tkill-approaching,blocked,open-forks,over-appetite\t25\t14')" "$out"
assert_contains "J1.7 portfolio: a closed venture carries no flags" \
  "$(printf 'venture\tdelta\tAbandoned\tnone')" "$out"
assert_contains "J1.7 portfolio: a medium card past its year" "$(printf 'card-review\tstale-medium\t2025-01-10\tmedium')" "$out"
assert_not_contains "J1.7 portfolio: a fresh card is quiet" "fresh-medium" "$out"
assert_contains "J1.7 portfolio: a fast card older than a live venture" "$(printf 'card-review\tfast-moving\t2026-07-01\tfast')" "$out"
assert_not_contains "J1.7 portfolio: a slow card is never date-flagged" "slow-method" "$out"
assert_not_contains "J1.7 portfolio: a fast card reviewed after every venture began is quiet" "fast-fresh" "$out"
assert_eq "J1.7 portfolio: unstaffed disciplines, distinct ventures, most first" \
  "$(printf 'unstaffed\tlegal\t2\nunstaffed\tsecurity\t1')" "$(printf '%s\n' "$out" | grep '^unstaffed	')"
reg get alpha
assert_contains "J1.7 portfolio writes the flags back to the registry" "kill-approaching,blocked,open-forks" "$out"

PLANWRIGHT_INCEPTION_TODAY=2026-10-02 reg portfolio --cards "$cards"
assert_contains "J1.7 portfolio: a tripped kill date" "$(printf 'venture\talpha\tExploring\tkill-tripped')" "$out"

rm -rf "$roots/gamma"
reg portfolio --cards "$cards"
assert_contains "J1.7 portfolio: a vanished venture is flagged, not fatal" "$(printf 'venture\tgamma\tExploring\tunreadable')" "$out"
reg get gamma
assert_contains "J1.7 portfolio: an unreadable venture keeps its last flags" "over-appetite" "$out"

# Without --cards the portfolio reads the merged card catalog: a stub stands in
# for resolve-card.sh to pin the column layout this helper consumes.
cp -R "$REPO_ROOT/scripts" "$tmp/scripts-copy"
printf '#!/bin/sh\nprintf "stale-medium\\tcore\\t%%s\\n" "%s"\n' "$cards/stale-medium.md" >"$tmp/scripts-copy/resolve-card.sh"
out="$(CLAUDE_PLUGIN_DATA="$data" "$tmp/scripts-copy/inception-registry.sh" portfolio 2>&1)"
assert_contains "J1.7 portfolio without --cards reads the card catalog" "$(printf 'card-review\tstale-medium\t2025-01-10\tmedium')" "$out"

empty_data="$tmp/empty-data"
mkdir -p "$tmp/empty-home/ventures"
out="$(HOME="$tmp/empty-home" CLAUDE_PLUGIN_DATA="$empty_data" "$REG" portfolio --cards "$tmp/no-cards" 2>&1)"
rc=$?
assert_eq "J1.7 portfolio over no ventures: exit 0" "0" "$rc"
assert_contains "J1.7 portfolio over no ventures: says none" "$(printf 'venture\tnone')" "$out"
out="$(HOME="$tmp/fresh-home" CLAUDE_PLUGIN_DATA="$tmp/fresh-data" "$REG" portfolio --cards "$tmp/no-cards" 2>&1)"
assert_eq "J1.7 portfolio on a fresh install (no ventures root yet): exit 0" "0" "$?"
assert_contains "J1.7 portfolio on a fresh install: says none" "$(printf 'venture\tnone')" "$out"

if [ "$failures" -ne 0 ]; then
  echo "test-inception-registry: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-inception-registry: all assertions passed"
