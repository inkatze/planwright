#!/bin/bash
# Tests for the offered Artifact publish step (REQ-G1.4, REQ-G1.9 · D-9).
#
# The helper decides and never publishes: it renders the chosen export fresh,
# screens it, and says whether the operator must be asked (`offer`) or whether
# the venture's opt-in auto-republish knob covers a republish (`republish`).
# What is pinned: a scripted run is offer-only, the knob defaults off, the first
# publish is always an offer whatever the knob says, a publish is recorded only
# on an explicit confirmation, and the machine-local state file is read as data,
# never executed.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBLISH="$REPO_ROOT/scripts/inception-publish.sh"

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

if [ ! -x "$PUBLISH" ]; then
  echo "FAIL: publish helper missing or not executable at $PUBLISH" >&2
  exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT
# Offers leave their private copies under TMPDIR for the caller to remove;
# keep them inside this run's scratch directory.
export TMPDIR="$tmp"

fresh() {
  d="$(mktemp -d "$tmp/vXXXXXX")" || exit 1
  inception_fixture_write "$d" || exit 1
  git -C "$d" init -q . >/dev/null 2>&1 || exit 1
  printf '%s' "$d"
}
# state_of <venture> — where the publish state lives: the clone's git
# directory, which no commit can write.
state_of() { printf '%s/planwright-publish.local' "$(git -C "$1" rev-parse --absolute-git-dir)"; }
# field <name> <tsv> — the value of one `name<TAB>value` line.
field() { printf '%s\n' "$2" | awk -F'\t' -v k="$1" '$1 == k { print $2; exit }'; }

export PLANWRIGHT_INCEPTION_TODAY=2026-08-26
export PLANWRIGHT_SECRET_SCREEN_TOOL=none

# ---------------------------------------------------------------------------
# 1. A scripted run on a fresh venture is offer-only (REQ-G1.4).
# ---------------------------------------------------------------------------
v="$(fresh)"
out="$("$PUBLISH" offer "$v" 2>"$tmp/err")"
rc=$?
err="$(cat "$tmp/err")"
assert_eq "fresh offer: exit 0" "0" "$rc"
assert_eq "fresh offer: the decision is an offer" "offer" "$(field decision "$out")"
assert_eq "fresh offer: the first publish is the reason" "first-publish" "$(field reason "$out")"
assert_eq "fresh offer: the dashboard is the default mode" "dashboard" "$(field mode "$out")"
offered="$(field export "$out")"
case $offered in
  "$v"/*)
    echo "FAIL: fresh offer: the offered page sits in the work tree ($offered)" >&2
    failures=$((failures + 1))
    ;;
  */venture.html) echo "ok: fresh offer: names a private copy of the dashboard" ;;
  *)
    echo "FAIL: fresh offer: unexpected export path ($offered)" >&2
    failures=$((failures + 1))
    ;;
esac
assert_eq "fresh offer: no artifact on record" "none" "$(field artifact "$out")"
assert_contains "fresh offer: tells the caller to ask first" "ask the operator" "$err"
assert_contains "fresh offer: says the page leaves this machine" "off this machine" "$err"
if [ -f "$offered" ]; then
  echo "ok: fresh offer: renders the export it offers"
else
  echo "FAIL: fresh offer: the export was not rendered" >&2
  failures=$((failures + 1))
fi
if [ -e "$(state_of "$v")" ]; then
  echo "FAIL: fresh offer: an offer wrote publish state" >&2
  failures=$((failures + 1))
else
  echo "ok: fresh offer: an offer writes no publish state"
fi

out="$("$PUBLISH" offer --mode pitch "$v" 2>/dev/null)"
case $(field export "$out") in
  */pitch.html) echo "ok: pitch offer: names a private copy of the pitch" ;;
  *)
    echo "FAIL: pitch offer: unexpected export path" >&2
    failures=$((failures + 1))
    ;;
esac
assert_eq "pitch offer: is an offer" "offer" "$(field decision "$out")"

# status answers with the decision an offer would make, and renders nothing.
v="$(fresh)"
out="$("$PUBLISH" status "$v" 2>/dev/null)"
rc=$?
assert_eq "status: exit 0" "0" "$rc"
assert_eq "status: the same decision as an offer" "offer" "$(field decision "$out")"
assert_eq "status: the same reason" "first-publish" "$(field reason "$out")"
assert_eq "status: names no export" "" "$(field export "$out")"
assert_no_dir_entries() {
  if [ -e "$2" ]; then
    echo "FAIL: $1 ($2 exists)" >&2
    failures=$((failures + 1))
  else
    echo "ok: $1"
  fi
}
assert_no_dir_entries "status: renders nothing" "$v/exports"

# ---------------------------------------------------------------------------
# 2. The knob defaults off, and never covers a first publish.
# ---------------------------------------------------------------------------
v="$(fresh)"
"$PUBLISH" auto on "$v" >/dev/null 2>&1
rc=$?
assert_eq "auto on: exit 0" "0" "$rc"
out="$("$PUBLISH" status "$v" 2>/dev/null)"
assert_eq "knob on, never published: still an offer" "offer" "$(field decision "$out")"
assert_eq "knob on, never published: first publish is the reason" "first-publish" "$(field reason "$out")"

# ---------------------------------------------------------------------------
# 3. Recording takes an explicit confirmation.
# ---------------------------------------------------------------------------
v="$(fresh)"
out="$("$PUBLISH" record --artifact art-123 "$v" 2>&1)"
rc=$?
assert_eq "record without --confirmed: exit 2" "2" "$rc"
assert_contains "record without --confirmed: says why" "confirmed" "$out"
if [ -e "$(state_of "$v")" ]; then
  echo "FAIL: record without --confirmed: state was written" >&2
  failures=$((failures + 1))
else
  echo "ok: record without --confirmed: nothing recorded"
fi

out="$("$PUBLISH" record --confirmed --artifact 'art;rm -rf x' "$v" 2>&1)"
rc=$?
assert_eq "record with a malformed artifact id: exit 2" "2" "$rc"

"$PUBLISH" record --confirmed --artifact art-123 "$v" >/dev/null 2>&1
rc=$?
assert_eq "record: exit 0" "0" "$rc"
st="$(state_of "$v")"
private="$(find "$st" ! -perm -004 2>/dev/null)"
assert_eq "record: the state file is not world-readable" "$st" "$private"

out="$("$PUBLISH" status "$v" 2>/dev/null)"
assert_eq "published, knob default: an offer" "offer" "$(field decision "$out")"
assert_eq "published, knob default: the knob is the reason" "auto-republish-off" "$(field reason "$out")"
assert_eq "published: the artifact on record" "art-123" "$(field artifact "$out")"

# ---------------------------------------------------------------------------
# 4. Knob on after a confirmed first publish: a republish, per mode.
# ---------------------------------------------------------------------------
"$PUBLISH" auto on "$v" >/dev/null 2>&1
out="$("$PUBLISH" status "$v" 2>"$tmp/err")"
assert_eq "published, knob on: a republish" "republish" "$(field decision "$out")"
assert_eq "published, knob on: the knob is the reason" "auto-republish-on" "$(field reason "$out")"
assert_eq "published, knob on: the artifact survives the knob write" "art-123" "$(field artifact "$out")"

out="$("$PUBLISH" status --mode pitch "$v" 2>/dev/null)"
assert_eq "knob on, pitch never published: an offer" "offer" "$(field decision "$out")"
assert_eq "knob on, pitch never published: first publish" "first-publish" "$(field reason "$out")"

"$PUBLISH" auto off "$v" >/dev/null 2>&1
out="$("$PUBLISH" status "$v" 2>/dev/null)"
assert_eq "knob back off: an offer again" "offer" "$(field decision "$out")"

out="$("$PUBLISH" auto maybe "$v" 2>&1)"
rc=$?
assert_eq "auto with a bad value: exit 2" "2" "$rc"

# ---------------------------------------------------------------------------
# 5. The state file is data: malformed values fail safe, nothing is executed.
# ---------------------------------------------------------------------------
v="$(fresh)"
{
  printf '%s\n' 'auto-republish=yes'
  # shellcheck disable=SC2016 # the substitution must stay literal: it is the payload
  printf '%s\n' 'published-dashboard=$(touch '"$tmp"'/pwned)'
  printf '%s\n' "touch $tmp/pwned2"
} >"$(state_of "$v")"
out="$("$PUBLISH" status "$v" 2>"$tmp/err")"
rc=$?
assert_eq "malformed state: exit 0" "0" "$rc"
assert_eq "malformed state: fails safe to an offer" "offer" "$(field decision "$out")"
assert_eq "malformed state: a bad artifact id reads as unpublished" \
  "first-publish" "$(field reason "$out")"
assert_contains "malformed state: the bad knob value is named" "auto-republish" "$(cat "$tmp/err")"
if [ -e "$tmp/pwned" ] || [ -e "$tmp/pwned2" ]; then
  echo "FAIL: malformed state: the state file was executed" >&2
  failures=$((failures + 1))
else
  echo "ok: malformed state: the state file was never executed"
fi

# Knob on plus a malformed record still offers.
printf '%s\n' 'auto-republish=on' 'published-dashboard=bad id' >"$(state_of "$v")"
out="$("$PUBLISH" status "$v" 2>/dev/null)"
assert_eq "knob on, malformed record: an offer" "offer" "$(field decision "$out")"

# ---------------------------------------------------------------------------
# 6. A page that looks like it carries a credential is never offered.
# ---------------------------------------------------------------------------
v="$(fresh)"
sed "s|^Rides the incident-tooling|token: ghp_""0123456789abcdefghijklmnopqrstuvwxyz Rides the incident-tooling|" \
  "$v/brief.md" >"$v/brief.md.new" && mv "$v/brief.md.new" "$v/brief.md"
"$PUBLISH" record --confirmed "$v" >/dev/null 2>&1
"$PUBLISH" auto on "$v" >/dev/null 2>&1
out="$("$PUBLISH" offer --mode pitch "$v" 2>"$tmp/err")"
rc=$?
assert_eq "credential in the export: exit 1" "1" "$rc"
assert_not_contains "credential in the export: no decision is printed" "decision" "$out"
assert_not_contains "credential in the export: the secret is never echoed" \
  "ghp_0123456789" "$(cat "$tmp/err")"

# ---------------------------------------------------------------------------
# 7. Version gating passes through; usage errors are exit 2.
# ---------------------------------------------------------------------------
v="$(fresh)"
for f in brief disciplines assumptions decisions plan; do
  sed 's|^\*\*Format-version:\*\* 1\.0$|**Format-version:** 7.0|' "$v/$f.md" >"$v/$f.md.new" \
    && mv "$v/$f.md.new" "$v/$f.md"
done
out="$("$PUBLISH" offer "$v" 2>&1)"
rc=$?
assert_eq "unsupported version: exit 3" "3" "$rc"
assert_not_contains "unsupported version: no decision is printed" "decision" "$out"

out="$("$PUBLISH" offer --mode slides "$v" 2>&1)"
rc=$?
assert_eq "unknown mode: exit 2" "2" "$rc"
out="$("$PUBLISH" publish "$v" 2>&1)"
rc=$?
assert_eq "unknown subcommand: exit 2" "2" "$rc"
out="$("$PUBLISH" offer "$tmp/nope" 2>&1)"
rc=$?
assert_eq "missing venture: exit 2" "2" "$rc"

# ---------------------------------------------------------------------------
# 8. The state lives where no commit can write it, behind a lock.
# ---------------------------------------------------------------------------

# A state file committed into the work tree (a web-UI create, a forced add)
# arrives with every pull. It must switch nothing on.
v="$(fresh)"
printf '%s\n' 'auto-republish=on' 'published-dashboard=attacker-artifact' >"$v/.planwright-publish.local"
git -C "$v" add -f .planwright-publish.local >/dev/null 2>&1
out="$("$PUBLISH" status "$v" 2>/dev/null)"
assert_eq "committed state file: still an offer" "offer" "$(field decision "$out")"
assert_eq "committed state file: read as never published" "first-publish" "$(field reason "$out")"
assert_eq "committed state file: its artifact is not offered" "none" "$(field artifact "$out")"

v="$(fresh)"
"$PUBLISH" auto on "$v" >/dev/null 2>&1
if [ -e "$v/.planwright-publish.local" ]; then
  echo "FAIL: state location: written into the work tree" >&2
  failures=$((failures + 1))
else
  echo "ok: state location: nothing is written into the work tree"
fi
assert_contains "state location: the knob lands in the git directory" "auto-republish=on" \
  "$(cat "$(state_of "$v")" 2>/dev/null)"

# A writer that cannot take the lock refuses rather than racing the holder.
# This test shell is the live holder, through the same lock primitive.
lockp="$(git -C "$v" rev-parse --absolute-git-dir)/planwright-publish.lock"
(
  # shellcheck source=scripts/lock-lib.sh
  . "$REPO_ROOT/scripts/lock-lib.sh"
  pw_lock_acquire "$lockp" 1 || exit 1
  out="$(PLANWRIGHT_PUBLISH_LOCK_TRIES=1 "$PUBLISH" auto off "$v" 2>&1)"
  printf '%s\n' "rc=$?" "$out" >"$tmp/held-lock.out"
  pw_lock_release "$lockp"
)
held="$(cat "$tmp/held-lock.out" 2>/dev/null)"
assert_contains "held lock: the write is refused" "rc=2" "$held"
assert_contains "held lock: says the state is busy" "busy" "$held"
assert_contains "held lock: the knob is unchanged" "auto-republish=on" "$(cat "$(state_of "$v")")"

# Outside a git repository there is nowhere safe to keep the state: offers
# still work, as first publishes, and nothing is recorded.
nogit="$(mktemp -d "$tmp/nogitXXXXXX")"
inception_fixture_write "$nogit" || exit 1
out="$("$PUBLISH" record --confirmed --artifact art-1 "$nogit" 2>&1)"
rc=$?
assert_eq "no git: record is refused" "2" "$rc"
assert_contains "no git: says why" "git repository" "$out"
out="$("$PUBLISH" status "$nogit" 2>/dev/null)"
assert_eq "no git: offers still work" "offer" "$(field decision "$out")"
assert_eq "no git: always a first publish" "first-publish" "$(field reason "$out")"

# ---------------------------------------------------------------------------
# 9. Bookkeeping: the record keeps what a republish needs.
# ---------------------------------------------------------------------------

# A later confirmed record without --artifact keeps the id already on record.
v="$(fresh)"
"$PUBLISH" record --confirmed --artifact art-123 "$v" >/dev/null 2>&1
"$PUBLISH" record --confirmed "$v" >/dev/null 2>&1
"$PUBLISH" auto on "$v" >/dev/null 2>&1
out="$("$PUBLISH" status "$v" 2>/dev/null)"
assert_eq "re-record without --artifact: the id survives" "art-123" "$(field artifact "$out")"
assert_eq "re-record without --artifact: still a republish" "republish" "$(field decision "$out")"

# A republish needs a target: with no artifact id on record, ask instead.
v="$(fresh)"
"$PUBLISH" record --confirmed "$v" >/dev/null 2>&1
"$PUBLISH" auto on "$v" >/dev/null 2>&1
out="$("$PUBLISH" status "$v" 2>/dev/null)"
assert_eq "no artifact on record: an offer, not a republish" "offer" "$(field decision "$out")"
assert_eq "no artifact on record: says why" "no-artifact-recorded" "$(field reason "$out")"
assert_eq "no artifact on record: no artifact offered" "none" "$(field artifact "$out")"

# Each page keeps its own record.
v="$(fresh)"
"$PUBLISH" record --confirmed --mode dashboard --artifact dash-1 "$v" >/dev/null 2>&1
"$PUBLISH" record --confirmed --mode pitch --artifact pitch-1 "$v" >/dev/null 2>&1
assert_eq "both pages: the dashboard record" "dash-1" "$(field artifact "$("$PUBLISH" status "$v" 2>/dev/null)")"
assert_eq "both pages: the pitch record" "pitch-1" \
  "$(field artifact "$("$PUBLISH" status --mode pitch "$v" 2>/dev/null)")"

# An unreadable state is an environment error, never silently rebuilt.
v="$(fresh)"
"$PUBLISH" record --confirmed --artifact art-9 "$v" >/dev/null 2>&1
chmod 000 "$(state_of "$v")"
if [ -r "$(state_of "$v")" ]; then
  echo "ok: unreadable state: skipped (running as a user who can read mode 000)"
else
  out="$("$PUBLISH" offer "$v" 2>&1)"
  rc=$?
  assert_eq "unreadable state: offer refuses" "2" "$rc"
  assert_contains "unreadable state: says it cannot read the state" "cannot read" "$out"
  out="$("$PUBLISH" auto on "$v" 2>&1)"
  rc=$?
  assert_eq "unreadable state: a write refuses" "2" "$rc"
fi
chmod 600 "$(state_of "$v")"

# A writer killed mid-write leaves no temp state behind. The stub mv signals
# the writer while the temp file exists and then fails, so only the signal
# path can clean up.
v="$(fresh)"
stub="$tmp/killmv"
mkdir -p "$stub"
real_mv="$(command -v mv)"
# shellcheck disable=SC2016 # $2 and $PPID belong to the stub, expanded when it runs
printf '%s\n' '#!/bin/sh' 'case "$2" in' '  */planwright-publish.local) kill -TERM "$PPID"; exit 1 ;;' 'esac' "exec $real_mv \"\$@\"" >"$stub/mv"
chmod +x "$stub/mv"
PATH="$stub:$PATH" "$PUBLISH" auto on "$v" >/dev/null 2>&1
gd="$(git -C "$v" rev-parse --absolute-git-dir)"
leftover="$(find "$gd" -maxdepth 1 -name 'planwright-publish.local.*' 2>/dev/null)"
assert_eq "killed writer: no temp state is left" "" "$leftover"
if [ -e "$gd/planwright-publish.lock" ] || [ -L "$gd/planwright-publish.lock" ]; then
  echo "FAIL: killed writer: the lock was left behind" >&2
  failures=$((failures + 1))
else
  echo "ok: killed writer: the lock is released"
fi

# --- coverage the helper's contract leans on ---

# The offered page is rendered fresh, not taken from disk.
v="$(fresh)"
mkdir -p "$v/exports"
printf 'STALE-MARKER\n' >"$v/exports/venture.html"
out="$("$PUBLISH" offer "$v" 2>/dev/null)"
assert_not_contains "fresh render: the stale page is not offered" "STALE-MARKER" \
  "$(cat "$(field export "$out")")"

# A screen that cannot run offers nothing.
v="$(fresh)"
out="$(PLANWRIGHT_SECRET_SCREEN_TOOL=not-a-tool "$PUBLISH" offer "$v" 2>&1)"
rc=$?
assert_eq "screen cannot run: exit 2" "2" "$rc"
assert_not_contains "screen cannot run: no decision" "decision" "$out"

# No network client is reached, whatever the helper calls into.
v="$(fresh)"
netstub="$tmp/netstub"
mkdir -p "$netstub"
for c in curl wget gh nc ssh scp; do
  printf '%s\n' '#!/bin/sh' "echo $c >>\"$tmp/net-calls\"" 'exit 1' >"$netstub/$c"
  chmod +x "$netstub/$c"
done
PATH="$netstub:$PATH" "$PUBLISH" offer "$v" >/dev/null 2>&1
PATH="$netstub:$PATH" "$PUBLISH" record --confirmed --artifact a-1 "$v" >/dev/null 2>&1
PATH="$netstub:$PATH" "$PUBLISH" auto on "$v" >/dev/null 2>&1
assert_eq "no network: no client was invoked" "" "$(cat "$tmp/net-calls" 2>/dev/null)"

# ---------------------------------------------------------------------------
# 10. A quoted credential is caught in the bundle, where escaping cannot hide it.
# ---------------------------------------------------------------------------
v="$(fresh)"
sed 's|^- \*\*Risk-if-wrong:\*\* the fan-out saves no time|- **Risk-if-wrong:** api_key="AbCdEfGh''IjKlMnOpQrStUvWx12" the fan-out saves no time|' \
  "$v/assumptions.md" >"$v/assumptions.new" && mv "$v/assumptions.new" "$v/assumptions.md"
out="$("$PUBLISH" offer "$v" 2>"$tmp/err")"
rc=$?
assert_eq "quoted credential: not offered" "1" "$rc"
assert_not_contains "quoted credential: no decision" "decision" "$out"
assert_not_contains "quoted credential: never echoed" "AbCdEfGh""IjKlMnOpQrStUvWx12" "$(cat "$tmp/err")"

# ---------------------------------------------------------------------------
# 11. The page offered is the page screened: a later render of the work tree
#     cannot swap different bytes in under the offer.
# ---------------------------------------------------------------------------
v="$(fresh)"
out="$("$PUBLISH" offer "$v" 2>/dev/null)"
offered="$(field export "$out")"
cp "$offered" "$tmp/screened.html"
sed 's|ten minutes|SWAPPED-IN minutes|' "$v/brief.md" >"$v/brief.new" && mv "$v/brief.new" "$v/brief.md"
"$REPO_ROOT/scripts/inception-render.sh" "$v" >/dev/null 2>&1
if cmp -s "$tmp/screened.html" "$offered"; then
  echo "ok: private copy: a later work-tree render leaves the offered page alone"
else
  echo "FAIL: private copy: the offered page changed after it was screened" >&2
  failures=$((failures + 1))
fi
private_dir="$(dirname "$offered")"
leaky="$(find "$private_dir" -maxdepth 0 -perm -004 2>/dev/null)"
assert_eq "private copy: its directory is not world-readable" "" "$leaky"

# ---------------------------------------------------------------------------
# 12. Panel-review edges.
# ---------------------------------------------------------------------------

# `yes` is the record's own word for "published, no id": not an artifact id.
v="$(fresh)"
out="$("$PUBLISH" record --confirmed --artifact yes "$v" 2>&1)"
rc=$?
assert_eq "artifact id yes: refused" "2" "$rc"

# `none` is what status and offer print for "no artifact on record", so it is
# never accepted as an id: a republish would otherwise target nothing.
v="$(fresh)"
out="$("$PUBLISH" record --confirmed --artifact none "$v" 2>&1)"
rc=$?
assert_eq "artifact id none: refused" "2" "$rc"

# A Git override inherited from the caller (a hook runs with GIT_DIR set)
# must not redirect the state into another repository.
v="$(fresh)"
other="$(fresh)"
GIT_DIR="$other/.git" GIT_WORK_TREE="$other" "$PUBLISH" auto on "$v" >/dev/null 2>&1
if [ -e "$(state_of "$other")" ]; then
  echo "FAIL: inherited GIT_DIR: the state went to another repository" >&2
  failures=$((failures + 1))
else
  echo "ok: inherited GIT_DIR: no state is written to another repository"
fi
assert_contains "inherited GIT_DIR: the venture's own state is written" "auto-republish=on" \
  "$(cat "$(state_of "$v")" 2>/dev/null)"

# The lock-tries knob is a count; anything else is refused, not computed on.
v="$(fresh)"
out="$(PLANWRIGHT_PUBLISH_LOCK_TRIES=many "$PUBLISH" auto on "$v" 2>&1)"
rc=$?
assert_eq "lock tries not a number: refused" "2" "$rc"
assert_contains "lock tries not a number: names the knob" "PLANWRIGHT_PUBLISH_LOCK_TRIES" "$out"

# An offer interrupted mid-screen leaves no private directory behind.
sand="$tmp/pw-sand"
mkdir -p "$sand/scripts"
cp "$REPO_ROOT/scripts/"inception-*.sh "$REPO_ROOT/scripts/echo-safety.sh" \
  "$REPO_ROOT/scripts/spec-parse.sh" "$REPO_ROOT/scripts/html-escape.sh" \
  "$REPO_ROOT/scripts/lock-lib.sh" "$sand/scripts/" || exit 1
# shellcheck disable=SC2016 # $PPID belongs to the stub, expanded when it runs
printf '%s\n' '#!/bin/sh' 'kill -TERM "$PPID"' 'exit 2' >"$sand/scripts/inception-secret-screen.sh"
v="$(fresh)"
offers="$tmp/offers-int"
mkdir -p "$offers"
TMPDIR="$offers" /bin/sh "$sand/scripts/inception-publish.sh" offer "$v" >/dev/null 2>&1
leftover="$(find "$offers" -mindepth 1 -maxdepth 1 2>/dev/null)"
assert_eq "interrupted offer: no private directory is left" "" "$leftover"

if [ "$failures" -ne 0 ]; then
  echo "test-inception-publish: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-inception-publish: all assertions passed"
