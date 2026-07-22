#!/bin/bash
# Tests for scripts/fleet-presence.sh — the cross-tower presence signal:
# publish, discover, liveness-classify, GC, and owner attribution
# (concurrent-orchestrator-coordination Task 2: D-2 · REQ-A1.1–REQ-A1.7).
#
# Contract under test:
#   publish  --checkout <dir> (--session-id <uuid> | --pid <pid>)
#            [--tmux-session <name> --tmux-window <name>]
#            [--specs <csv>] [--fenced <csv>] [--meta]
#       Write/refresh this tower's own presence record atomically
#       (write-temp-then-rename) under <surface>/<repo-id>/<tower-id>.
#       Needs an identity AND a death handle: the tmux pair when given
#       (preferred), else --pid doubles as the handle. Records over the
#       8191-byte cap are refused at the writer.
#   discover --checkout <dir> (--session-id <uuid> | --pid <pid>)
#            [--min-interval <sec>]     (default 30; 0 disables the cap)
#       Scan the current repo-id sub-surface, exclude own record by tower
#       identity, classify each peer via fleet-death-evidence.sh (tri-state,
#       memoized per pass), GC positively-dead records under a re-read-and-
#       skip guard (gc | gc-skip | gc-fail — a failed unlink is never
#       claimed as done), and print peer / peer-unreadable (malformed |
#       schema-skew | unreadable) / foreign-record / summary lines. A pass
#       inside --min-interval prints only `cadence-capped`.
#   owner    --checkout <dir> (--session-id <uuid> | --pid <pid>) <spec>/<unit-id>
#       Resolve a fenced unit's owner from LIVE records' fenced field;
#       `unknown-owner` when no live record lists it. Never cadence-capped.
#   identity --checkout <dir> (--session-id <uuid> | --pid <pid>)
#       Print the derived tower identity (REQ-A1.7).
#   surface  --checkout <dir>
#       Print the per-repo sub-surface path.
#   Exit codes: 0 ok (incl. healthy-empty & cadence-capped); 2 usage /
#       refused input / non-repository checkout / write failure; 3
#       unknown-peer-status (vanished, unreadable, or obstructed surface —
#       fail closed, never solitude); 4 security refusal (over-broad,
#       ACL-bearing, mis-owned, or symlink-tampered surface,
#       verify-or-refuse); 5 no origin remote (genuine solo posture).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FP="$here/../scripts/fleet-presence.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FP" ] || fail "scripts/fleet-presence.sh missing or not executable"

# pwd -P canonical from the start: the script canonicalizes checkout paths,
# and on macOS mktemp hands out /var/... whose physical path is /private/var.
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

# --- fixtures -------------------------------------------------------------
# Stub script dir: sibling resolution picks up the counting death-evidence
# stub (verdict from a file, argv appended to a call log). Invoked via `sh`
# so fresh temp-dir scripts never hit the Gatekeeper first-exec stall.
stubbin="$tmp/stub-scripts"
mkdir -p "$stubbin"
cp "$here/../scripts/"*.sh "$stubbin/"
cat >"$stubbin/fleet-death-evidence.sh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/evidence-calls"
if [ -f "$tmp/swap-on-call" ]; then
  target=\$(cat "$tmp/swap-on-call")
  cp "$tmp/fresh-record" "\$target"
fi
if [ -f "$tmp/delete-on-call" ]; then
  rm -f "\$(cat "$tmp/delete-on-call")"
fi
verdict=\$(cat "$tmp/evidence-verdict")
printf '%s\n' "\$verdict"
case \$verdict in
  dead) exit 0 ;;
  alive) exit 1 ;;
  *) exit 3 ;;
esac
EOF
chmod +x "$stubbin/fleet-death-evidence.sh"
printf 'alive\n' >"$tmp/evidence-verdict"
: >"$tmp/evidence-calls"

# Two checkouts that are clones of the SAME repository (same origin URL) and
# one checkout of a DIFFERENT repository (different origin).
mk_checkout() {
  mc_dir=$1
  mc_url=$2
  mkdir -p "$mc_dir"
  git -C "$mc_dir" init -q
  git -C "$mc_dir" remote add origin "$mc_url"
}
co_a="$tmp/clone-a"
co_b="$tmp/clone-b"
co_other="$tmp/other-repo"
co_noremote="$tmp/no-remote"
mk_checkout "$co_a" "ssh://git@example.invalid/acme/widgets.git"
mk_checkout "$co_b" "ssh://git@example.invalid/acme/widgets.git"
mk_checkout "$co_other" "ssh://git@example.invalid/acme/gadgets.git"
mkdir -p "$co_noremote"
git -C "$co_noremote" init -q

uuid_a="11111111-2222-3333-4444-555555555555"
uuid_b="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

run() {
  r_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    PLANWRIGHT_FLEET_STATE_DIR="$r_home" \
    /bin/sh "$stubbin/fleet-presence.sh" "$@"
}

# Portable perms read (stat's flags differ across BSD/GNU); only the mode
# column is parsed, never a filename (SC2012 n/a).
perms_of() {
  # shellcheck disable=SC2012
  ls -ld "$1" | awk '{print $1}'
}

record_count() {
  find "$1" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' '
}

# ---------------------------------------------------------------------------
# 1. REQ-A1.2 / REQ-A1.5 (a') — first-run bootstrap + publish: the surface
#    root and repo sub-surface are created 0700 with persistence sentinels,
#    and the record lands as one file per tower carrying every field.
# ---------------------------------------------------------------------------
# h1 is deliberately NOT pre-created: a genuinely fresh host (no fleet
# command has ever run) must bootstrap the fleet home + surface itself.
h1="$tmp/h1"
run "$h1" publish --checkout "$co_a" --session-id "$uuid_a" \
  --specs demo-spec --fenced demo-spec/3 --pid 4242 \
  || fail "first publish failed (pristine-home bootstrap, REQ-A1.5)"
sub=$(run "$h1" surface --checkout "$co_a") || fail "surface resolution failed"
[ -d "$sub" ] || fail "sub-surface not created"
case "$sub" in
  "$h1"/presence/*) : ;;
  *) fail "sub-surface not under <home>/presence: $sub" ;;
esac
case "$sub" in
  "$co_a"*) fail "surface must live outside the checkout (REQ-A1.4)" ;;
esac
[ -f "$h1/presence.sentinel" ] || fail "host persistence sentinel missing (REQ-A1.5)"
repo_id=$(basename "$sub")
[ -f "$h1/presence.sentinels/$repo_id" ] || fail "per-repo sentinel missing (REQ-A1.5)"
perms=$(perms_of "$h1/presence")
case "$perms" in
  d???------ | d???------[@.]*) : ;;
  *) fail "surface root not 0700: $perms" ;;
esac
perms=$(perms_of "$sub")
case "$perms" in
  d???------ | d???------[@.]*) : ;;
  *) fail "repo sub-surface not 0700: $perms" ;;
esac
rec="$sub/$uuid_a"
[ -f "$rec" ] || fail "record not keyed by tower identity (uuid)"
line=$(cat "$rec")
case "$line" in
  "pw-presence-v1	$repo_id	$uuid_a	$co_a	demo-spec	demo-spec/3	"*) : ;;
  *) fail "record fields wrong: $line" ;;
esac
case "$line" in
  *"	process 4242	false") : ;;
  *) fail "record death-handle/meta tail wrong (expected 'process 4242' + false): $line" ;;
esac
echo "ok: first-run bootstrap creates 0700 surface + sentinels; record carries all fields"

# ---------------------------------------------------------------------------
# 2. REQ-A1.2 — heartbeat refresh: same tower re-publishes in place (fenced
#    set refreshed, beat epoch advances, start epoch preserved); tmux towers
#    publish the reuse-resistant tmux-window handle; --meta stamps the
#    record's own validated boolean field.
# ---------------------------------------------------------------------------
start1=$(awk -F'	' '{print $7}' "$rec")
beat1=$(awk -F'	' '{print $8}' "$rec")
sleep 1
# --pid AND the tmux pair together: the reuse-resistant tmux-window handle
# must win (the "preferred under tmux" precedence).
run "$h1" publish --checkout "$co_a" --session-id "$uuid_a" \
  --specs demo-spec --fenced demo-spec/3,demo-spec/4 \
  --pid 4242 --tmux-session tower0 --tmux-window w1 --meta \
  || fail "heartbeat re-publish failed"
[ "$(record_count "$sub")" = 1 ] || fail "re-publish landed a second file"
line=$(cat "$rec")
start2=$(printf '%s' "$line" | awk -F'	' '{print $7}')
beat2=$(printf '%s' "$line" | awk -F'	' '{print $8}')
[ "$start2" = "$start1" ] || fail "start epoch not preserved across heartbeat"
[ "$beat2" -gt "$beat1" ] || fail "beat epoch did not advance"
case "$line" in
  *"	demo-spec/3,demo-spec/4	"*) : ;;
  *) fail "fenced set not refreshed on heartbeat" ;;
esac
case "$line" in
  *"	tmux-window tower0 w1	true") : ;;
  *) fail "tmux handle / meta marker wrong: $line" ;;
esac
echo "ok: heartbeat refreshes fenced set + beat epoch in place; tmux handle + meta field stamped"

# ---------------------------------------------------------------------------
# 3. REQ-A1.2 — concurrent writers land distinct files by construction; a
#    second tower ON THE SAME CHECKOUT (composite identity) collides with
#    neither the uuid tower nor another composite tower (REQ-A1.7 c).
# ---------------------------------------------------------------------------
run "$h1" publish --checkout "$co_a" --pid $$ || fail "composite publish failed"
id_self=$(run "$h1" identity --checkout "$co_a" --pid $$) || fail "identity failed"
[ -f "$sub/$id_self" ] || fail "composite record missing"
[ "$(record_count "$sub")" = 2 ] || fail "distinct towers did not land distinct files"
echo "ok: concurrent writers land distinct files (no shared registry)"

# ---------------------------------------------------------------------------
# 4. REQ-A1.7 — identity derivation: uuid wins when present (validated);
#    composite is pid + start-time + checkout-hash, not the bare pid and not
#    the checkout path; same checkout + different pid → distinct; same pid +
#    different checkout → distinct; malformed uuid refused.
# ---------------------------------------------------------------------------
id_uuid=$(run "$h1" identity --checkout "$co_a" --session-id "$uuid_a")
[ "$id_uuid" = "$uuid_a" ] || fail "uuid identity not the session uuid"
[ "$id_self" != "$$" ] || fail "composite identity is the bare pid"
[ "$id_self" != "$co_a" ] || fail "composite identity is the checkout path"
case "$id_self" in
  *$$*) : ;;
  *) fail "composite identity does not include the pid" ;;
esac
id_otherco=$(run "$h1" identity --checkout "$co_b" --pid $$)
[ "$id_self" != "$id_otherco" ] || fail "same pid on different checkouts computed one identity"
rc=0
run "$h1" identity --checkout "$co_a" --session-id "not-a-uuid" 2>/dev/null || rc=$?
[ "$rc" = 2 ] || fail "malformed session uuid not refused (exit $rc)"
rc=0
run "$h1" identity --checkout "$co_a" \
  --session-id "------------------------------------" 2>/dev/null || rc=$?
[ "$rc" = 2 ] || fail "all-dashes 36-char pseudo-uuid not refused (exit $rc)"
echo "ok: identity = session uuid, else pid+start-time+checkout composite; hostile uuid refused"

# ---------------------------------------------------------------------------
# 5. REQ-A1.1 / REQ-A1.2 — repo identity is origin-anchored: two clones of
#    one repo (different paths) share a sub-surface and discover each other;
#    a different repo's records are excluded; the derivation is not the
#    checkout path. No origin remote → solo posture (exit 5).
# ---------------------------------------------------------------------------
sub_b=$(run "$h1" surface --checkout "$co_b")
[ "$sub" = "$sub_b" ] || fail "two clones of one repo derived different repo ids (REQ-A1.2)"
sub_other=$(run "$h1" surface --checkout "$co_other")
[ "$sub" != "$sub_other" ] || fail "different repos derived one repo id"
run "$h1" publish --checkout "$co_other" --session-id "$uuid_b" --pid 4243 \
  || fail "other-repo publish failed"
printf 'alive\n' >"$tmp/evidence-verdict"
out=$(run "$h1" discover --checkout "$co_b" --pid $$ --min-interval 0 2>/dev/null) \
  || fail "discover from clone-b failed"
printf '%s\n' "$out" | grep -q "peer	$uuid_a	live" \
  || fail "clone-b did not discover clone-a's tower as a live peer"
printf '%s\n' "$out" | grep -q "$uuid_b" \
  && fail "a different repository's tower leaked into the peer set"
rc=0
run "$h1" publish --checkout "$co_noremote" --pid $$ 2>/dev/null || rc=$?
[ "$rc" = 5 ] || fail "no-origin checkout not classified solo posture (exit $rc)"
notrepo="$tmp/not-a-repo"
mkdir -p "$notrepo"
rc=0
run "$h1" publish --checkout "$notrepo" --pid $$ 2>/dev/null || rc=$?
[ "$rc" = 2 ] || fail "non-repository checkout misread as solo/other (exit $rc, expected refusal 2)"
echo "ok: repo id is origin-anchored (clones converge, repos split); no-origin = solo (exit 5)"

# ---------------------------------------------------------------------------
# 6. REQ-A1.1 — self-exclusion by tower identity, and the sole-tower flag:
#    with ≥1 live peer, sole-tower=no; a tower alone reads sole-tower=yes.
# ---------------------------------------------------------------------------
out_self=$(run "$h1" discover --checkout "$co_a" --session-id "$uuid_a" --min-interval 0 2>/dev/null) \
  || fail "self discover failed"
printf '%s\n' "$out_self" | grep -q "peer	$uuid_a	" \
  && fail "tower counted itself as a peer (REQ-A1.1/REQ-A1.7 d)"
printf '%s\n' "$out_self" | grep -q "sole-tower=no" \
  || fail "≥1 live peer but sole-tower flag not 'no'"
h6="$tmp/h6"
mkdir -p "$h6"
out6=$(run "$h6" discover --checkout "$co_a" --session-id "$uuid_a" --min-interval 0 2>/dev/null) \
  || fail "empty-surface discover failed"
printf '%s\n' "$out6" | grep -q "peers=0" || fail "empty surface not peers=0"
printf '%s\n' "$out6" | grep -q "sole-tower=yes" || fail "empty surface not sole-tower=yes"
echo "ok: own record excluded by identity; sole-tower flag tracks the live-peer count"

# ---------------------------------------------------------------------------
# 7. REQ-A1.1 — per-pass liveness cache: one death-predicate invocation per
#    record per pass, and records sharing one handle share one verdict call.
# ---------------------------------------------------------------------------
h7="$tmp/h7"
mkdir -p "$h7"
run "$h7" publish --checkout "$co_a" --session-id "$uuid_a" --pid 11111 >/dev/null
run "$h7" publish --checkout "$co_a" --session-id "$uuid_b" --pid 11111 >/dev/null
run "$h7" publish --checkout "$co_a" --pid $$ >/dev/null
: >"$tmp/evidence-calls"
printf 'alive\n' >"$tmp/evidence-verdict"
run "$h7" discover --checkout "$co_a" --session-id "99999999-0000-0000-0000-000000000000" \
  --min-interval 0 >/dev/null 2>&1 || fail "cache-fixture discover failed"
calls=$(wc -l <"$tmp/evidence-calls" | tr -d ' ')
[ "$calls" = 2 ] || fail "expected 2 memoized predicate calls (2 distinct handles, 3 records), got $calls"
echo "ok: liveness memoized per pass (≤1 predicate call per handle)"

# ---------------------------------------------------------------------------
# 8. REQ-A1.1 — capped cadence: a second discover inside --min-interval is
#    cadence-capped (no scan, no predicate fan-out, no summary line).
# ---------------------------------------------------------------------------
: >"$tmp/evidence-calls"
run "$h7" discover --checkout "$co_a" --session-id "$uuid_a" --min-interval 9999 \
  >/dev/null 2>&1 || fail "cadence pass 1 failed"
calls1=$(wc -l <"$tmp/evidence-calls" | tr -d ' ')
out=$(run "$h7" discover --checkout "$co_a" --session-id "$uuid_a" --min-interval 9999 2>/dev/null) \
  || fail "cadence pass 2 failed"
printf '%s\n' "$out" | grep -q "cadence-capped" || fail "second pass not cadence-capped"
printf '%s\n' "$out" | grep -q "sole-tower" && fail "cadence-capped pass emitted a summary"
calls2=$(wc -l <"$tmp/evidence-calls" | tr -d ' ')
[ "$calls1" = "$calls2" ] || fail "cadence-capped pass still invoked the death predicate"
# owner is a targeted query: never capped, even inside the interval.
printf 'alive\n' >"$tmp/evidence-verdict"
out=$(run "$h7" owner --checkout "$co_a" --session-id "$uuid_a" demo-spec/99 2>/dev/null) \
  || fail "owner inside the cadence window failed"
[ "$out" = "unknown-owner" ] || fail "owner was cadence-capped (got: $out)"
echo "ok: discovery is cadence-capped (no fan-out inside the interval); owner never capped"

# ---------------------------------------------------------------------------
# 9. REQ-A1.3 — tri-state reclaim: alive → live (file untouched, bytes
#    unchanged); unknown → not-dead (never reclaimed); stale heartbeat alone
#    is not death; dead → GC'd on discovery.
# ---------------------------------------------------------------------------
h9="$tmp/h9"
mkdir -p "$h9"
run "$h9" publish --checkout "$co_a" --session-id "$uuid_a" --pid 22222 >/dev/null
sub9=$(run "$h9" surface --checkout "$co_a")
# Age the heartbeat far into the past: stale-by-timeout but predicate=alive.
awk -F'	' 'BEGIN{OFS="\t"} {$8=1000000; print}' "$sub9/$uuid_a" >"$sub9/.tmp" \
  && mv "$sub9/.tmp" "$sub9/$uuid_a"
before=$(cat "$sub9/$uuid_a")
printf 'alive\n' >"$tmp/evidence-verdict"
out=$(run "$h9" discover --checkout "$co_a" --pid $$ --min-interval 0 2>/dev/null)
printf '%s\n' "$out" | grep -q "peer	$uuid_a	live" \
  || fail "stale-heartbeat-but-alive peer not classified live (staleness is not death)"
[ "$(cat "$sub9/$uuid_a")" = "$before" ] || fail "a live peer's file bytes changed on discovery"
printf 'unknown\n' >"$tmp/evidence-verdict"
out=$(run "$h9" discover --checkout "$co_a" --pid $$ --min-interval 0 2>/dev/null)
printf '%s\n' "$out" | grep -q "peer	$uuid_a	unknown" \
  || fail "unknown verdict not surfaced as a not-dead peer"
[ -f "$sub9/$uuid_a" ] || fail "unknown verdict reclaimed a record (must fail closed)"
printf 'dead\n' >"$tmp/evidence-verdict"
out=$(run "$h9" discover --checkout "$co_a" --pid $$ --min-interval 0 2>/dev/null)
printf '%s\n' "$out" | grep -q "gc	$uuid_a" || fail "positively-dead record not GC'd"
[ ! -f "$sub9/$uuid_a" ] || fail "positively-dead record still present after GC"
# A failed unlink is never reported as a successful gc: 0500 sub-surface
# (owner-only, passes the group/other privacy gate) makes rm fail.
run "$h9" publish --checkout "$co_a" --session-id "$uuid_a" --pid 22222 >/dev/null
chmod 0500 "$sub9"
err9="$tmp/h9-err"
out=$(run "$h9" discover --checkout "$co_a" --pid $$ --min-interval 0 2>"$err9") \
  || {
    chmod 0700 "$sub9"
    fail "discover over a read-only sub-surface failed"
  }
chmod 0700 "$sub9"
printf '%s\n' "$out" | grep -q "gc-fail	$uuid_a" \
  || fail "failed unlink not reported as gc-fail (got: $out)"
printf '%s\n' "$out" | grep -q "gc	$uuid_a$" \
  && fail "failed unlink falsely reported as gc"
[ -f "$sub9/$uuid_a" ] || fail "gc-fail fixture: record unexpectedly gone"
grep -qi "could not GC" "$err9" || fail "gc failure not surfaced on stderr"
rm -f "$sub9/$uuid_a"
echo "ok: alive/unknown never reclaim (bytes untouched); only positively-dead GCs; failed unlink surfaced"

# ---------------------------------------------------------------------------
# 10. REQ-A1.3 (d') — guarded GC: when the record no longer matches the
#     classified dead record at re-read (a dead-then-restarted tower's fresh
#     re-publish), the delete is skipped; and a racing delete self-heals via
#     the next heartbeat re-publish.
# ---------------------------------------------------------------------------
h10="$tmp/h10"
mkdir -p "$h10"
run "$h10" publish --checkout "$co_a" --session-id "$uuid_a" --pid 33333 >/dev/null
sub10=$(run "$h10" surface --checkout "$co_a")
# Fresh record the stub swaps in DURING classification (before the unlink):
awk -F'	' 'BEGIN{OFS="\t"} {$8=$8+100; print}' "$sub10/$uuid_a" >"$tmp/fresh-record"
printf '%s\n' "$sub10/$uuid_a" >"$tmp/swap-on-call"
printf 'dead\n' >"$tmp/evidence-verdict"
out=$(run "$h10" discover --checkout "$co_a" --pid $$ --min-interval 0 2>/dev/null)
rm -f "$tmp/swap-on-call"
printf '%s\n' "$out" | grep -q "gc-skip	$uuid_a" \
  || fail "re-read guard did not skip the delete of a re-published record"
[ -f "$sub10/$uuid_a" ] || fail "fresh re-published record was deleted despite the guard"
# Self-heal: even a lost record is restored by the next heartbeat publish.
rm -f "$sub10/$uuid_a"
run "$h10" publish --checkout "$co_a" --session-id "$uuid_a" --pid 33333 >/dev/null
[ -f "$sub10/$uuid_a" ] || fail "heartbeat re-publish did not self-heal the record"
# A peer's sweep unlinking the dead record between classification and our
# re-read: the GC outcome holds (gc, not gc-skip) and nothing argues
# against solitude.
printf '%s\n' "$sub10/$uuid_a" >"$tmp/delete-on-call"
printf 'dead\n' >"$tmp/evidence-verdict"
out=$(run "$h10" discover --checkout "$co_a" --pid $$ --min-interval 0 2>/dev/null)
rm -f "$tmp/delete-on-call"
printf '%s\n' "$out" | grep -q "gc	$uuid_a" \
  || fail "peer-raced unlink not reported as gc (got: $out)"
printf '%s\n' "$out" | grep -q "sole-tower=yes" \
  || fail "a peer-raced-away dead record argued against solitude"
echo "ok: GC re-reads and skips a changed record; heartbeat re-publish self-heals; raced unlink is gc"

# ---------------------------------------------------------------------------
# 11. REQ-A1.6 — defensive parsing: malformed, truncated, and schema-skewed
#     records are surfaced (assume-live, never GC'd, never read as absent);
#     the tower holding only unreadable peers is NOT sole.
# ---------------------------------------------------------------------------
h11="$tmp/h11"
mkdir -p "$h11"
run "$h11" publish --checkout "$co_a" --session-id "$uuid_a" --pid 44444 >/dev/null \
  || fail "h11 seed publish failed"
sub11=$(run "$h11" surface --checkout "$co_a")
rm -f "$sub11/$uuid_a"
printf 'garbage not a record\n' >"$sub11/one-malformed"
printf 'pw-presence-v1	short\n' >"$sub11/two-truncated"
printf 'pw-presence-v9	%s	%s	/x	-	-	1	2	process 1	false\n' \
  "$(basename "$sub11")" "$uuid_b" >"$sub11/three-skewed"
printf 'pw-presence-v3	only	three\n' >"$sub11/five-skewshort"
printf 'dead\n' >"$tmp/evidence-verdict"
err="$tmp/h11-err"
out=$(run "$h11" discover --checkout "$co_a" --pid $$ --min-interval 0 2>"$err") \
  || fail "discover over unreadable records failed (must degrade, not die)"
[ -f "$sub11/one-malformed" ] || fail "malformed record was GC'd (never reclaim on a guess)"
[ -f "$sub11/two-truncated" ] || fail "truncated record was GC'd"
[ -f "$sub11/three-skewed" ] || fail "schema-skewed record was GC'd"
[ -f "$sub11/five-skewshort" ] || fail "short schema-skewed record was GC'd"
n_unreadable=$(printf '%s\n' "$out" | grep -c "peer-unreadable") || true
[ "$n_unreadable" = 4 ] || fail "expected 4 unreadable-peer lines, got $n_unreadable"
# Kind labels are part of the contract: full-width skew and short skew both
# classify schema-skew; plain garbage classifies malformed.
printf '%s\n' "$out" | grep -q "peer-unreadable	one-malformed	malformed" \
  || fail "garbage record kind not 'malformed'"
printf '%s\n' "$out" | grep -q "peer-unreadable	three-skewed	schema-skew" \
  || fail "10-field vN record kind not 'schema-skew'"
printf '%s\n' "$out" | grep -q "peer-unreadable	five-skewshort	schema-skew" \
  || fail "short vN record kind not 'schema-skew' (empty-parsed branch)"
grep -qi "unreadable\|malformed\|skew" "$err" || fail "unreadable records not surfaced on stderr"
printf '%s\n' "$out" | grep -q "sole-tower=no" \
  || fail "unreadable peers must count against solitude (assume-live)"
# A present-but-unreadable (mode 000) record is a peer whose details are
# unreadable — surfaced assume-live, never the benign mid-scan vanish.
printf 'pw-presence-v1	x\n' >"$sub11/four-perms"
chmod 000 "$sub11/four-perms"
out=$(run "$h11" discover --checkout "$co_a" --pid $$ --min-interval 0 2>/dev/null) \
  || fail "discover over a mode-000 record failed"
chmod 600 "$sub11/four-perms"
printf '%s\n' "$out" | grep -q "peer-unreadable	four-perms	unreadable" \
  || fail "mode-000 record read as absent, not as an unreadable peer (REQ-A1.6)"
# A well-formed record carrying ANOTHER repo's id inside this sub-surface is
# a surfaced anomaly: excluded from the peer set, never GC'd.
other_repo_id=$(basename "$(run "$h11" surface --checkout "$co_other")")
printf 'pw-presence-v1	%s	%s	/x	-	-	1	2	process 1	false\n' \
  "$other_repo_id" "$uuid_b" >"$sub11/$uuid_b"
printf 'dead\n' >"$tmp/evidence-verdict"
out=$(run "$h11" discover --checkout "$co_a" --pid $$ --min-interval 0 2>"$err") \
  || fail "discover over a foreign-repo record failed"
[ -f "$sub11/$uuid_b" ] || fail "foreign-repo record was GC'd (never reclaim on a guess)"
printf '%s\n' "$out" | grep -q "foreign-record	$uuid_b" \
  || fail "foreign-repo record not surfaced as a machine-readable anomaly line"
printf '%s\n' "$out" | grep -q "peer	$uuid_b" \
  && fail "foreign-repo record leaked into the peer set"
rm -f "$sub11/$uuid_b"
echo "ok: malformed/truncated/skewed/unreadable/foreign records surfaced, never GC'd"

# ---------------------------------------------------------------------------
# 12. REQ-A1.5 — surface-level fail-closed: (a) present-but-empty is healthy;
#     (a'') vanished surface (sentinel present, dir gone) fails closed at the
#     host AND per-repo level; (b) unreadable surface is unknown-peer-status,
#     never solitude; (c) pre-existing well-moded dir is bootstrap success.
# ---------------------------------------------------------------------------
h12="$tmp/h12"
mkdir -p "$h12"
run "$h12" publish --checkout "$co_a" --session-id "$uuid_a" --pid 55555 >/dev/null
sub12=$(run "$h12" surface --checkout "$co_a")
rm -f "$sub12/$uuid_a"
out=$(run "$h12" discover --checkout "$co_a" --pid $$ --min-interval 0 2>/dev/null) \
  || fail "present-but-empty surface not healthy"
printf '%s\n' "$out" | grep -q "peers=0" || fail "present-but-empty not an empty peer set"
# (a'') per-repo vanish: repo sentinel survives, sub-dir removed.
rmdir "$sub12"
rc=0
run "$h12" discover --checkout "$co_a" --pid $$ --min-interval 0 >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "vanished repo sub-surface read as exit $rc, expected fail-closed 3"
# (a'') host vanish: host sentinel survives, whole surface removed.
rm -rf "$h12/presence"
rc=0
run "$h12" discover --checkout "$co_a" --pid $$ --min-interval 0 >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "vanished host surface read as exit $rc, expected fail-closed 3"
rc=0
run "$h12" publish --checkout "$co_a" --pid $$ >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "publish onto a vanished surface not failing closed (exit $rc)"
# (b) unreadable sub-surface: exists, 0700-clean, but not readable.
h12b="$tmp/h12b"
mkdir -p "$h12b"
run "$h12b" publish --checkout "$co_a" --session-id "$uuid_a" --pid 55555 >/dev/null
sub12b=$(run "$h12b" surface --checkout "$co_a")
chmod 000 "$sub12b"
rc=0
errb="$tmp/h12b-err"
run "$h12b" discover --checkout "$co_a" --pid $$ --min-interval 0 >/dev/null 2>"$errb" || rc=$?
chmod 700 "$sub12b"
[ "$rc" = 3 ] || fail "unreadable surface read as exit $rc, expected unknown-peer-status 3"
grep -qi "unknown peer status" "$errb" || fail "unreadable surface did not surface unknown-peer-status"
# (c) Concurrent-bootstrap contract: a surface a PEER already bootstrapped
# (sentinels + 0700 dirs pre-existing, our tower's mkdir would EEXIST) is
# success, not an error.
h12c="$tmp/h12c"
sub12c_repo=$(basename "$sub12b")
mkdir -p "$h12c"
date +%s >"$h12c/presence.sentinel"
mkdir -m 0700 "$h12c/presence"
mkdir -m 0700 "$h12c/presence.sentinels"
date +%s >"$h12c/presence.sentinels/$sub12c_repo"
mkdir -m 0700 "$h12c/presence/$sub12c_repo"
run "$h12c" publish --checkout "$co_a" --session-id "$uuid_a" --pid 55556 >/dev/null \
  || fail "peer-bootstrapped surface not treated as success (EEXIST contract)"
printf 'alive\n' >"$tmp/evidence-verdict"
out=$(run "$h12c" discover --checkout "$co_a" --pid $$ --min-interval 0 2>/dev/null) \
  || fail "discover on a peer-bootstrapped surface failed"
printf '%s\n' "$out" | grep -q "peer	$uuid_a	live" \
  || fail "peer-bootstrapped surface scan missed the published record"
echo "ok: vanished/unreadable surfaces fail closed (exit 3), empty surface is healthy, peer bootstrap is success"

# ---------------------------------------------------------------------------
# 13. REQ-A1.4 — verify-or-refuse: a pre-existing over-broad surface (group/
#     other-accessible) is refused with a security error, never chmod-
#     narrowed and reused.
# ---------------------------------------------------------------------------
h13="$tmp/h13"
mkdir -p "$h13"
run "$h13" publish --checkout "$co_a" --session-id "$uuid_a" --pid 66666 >/dev/null
chmod 755 "$h13/presence"
rc=0
err13="$tmp/h13-err"
run "$h13" discover --checkout "$co_a" --pid $$ --min-interval 0 >/dev/null 2>"$err13" || rc=$?
[ "$rc" = 4 ] || fail "over-broad surface root not refused (exit $rc, expected 4)"
grep -qi "over-broad\|security" "$err13" || fail "over-broad refusal did not surface a security error"
perms=$(perms_of "$h13/presence")
case "$perms" in
  d???r-x*) : ;;
  *) fail "refusal chmod-narrowed the surface (must refuse, not repair): $perms" ;;
esac
chmod 700 "$h13/presence"
sub13=$(run "$h13" surface --checkout "$co_a")
chmod 750 "$sub13"
rc=0
run "$h13" publish --checkout "$co_a" --session-id "$uuid_a" --pid 66666 >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "over-broad repo sub-surface not refused on publish (exit $rc)"
# ACL-bearing (`+`-suffixed) and mis-owned surfaces are refused structurally:
# the mode pattern admits only `@`/`.` suffixes, and the owner uid is
# compared against id -u (an actual chown/ACL cannot be staged in a test).
src_check="$here/../scripts/fleet-presence.sh"
grep -q 'd???------\[@\.\]\*' "$src_check" \
  || fail "check_private accepts mode suffixes beyond @/. (ACL '+' must refuse, structural)"
grep -q 'id -u' "$src_check" \
  || fail "check_private lacks the owner-uid comparison (structural)"
echo "ok: over-broad surface refused (exit 4), never silently narrowed or reused"

# ---------------------------------------------------------------------------
# 14. REQ-A1.2 / REQ-C1.3 — owner attribution: a fenced unit resolves to the
#     live record listing it; a unit no live record lists is unknown-owner;
#     hostile unit refs are refused before any scan.
# ---------------------------------------------------------------------------
h14="$tmp/h14"
mkdir -p "$h14"
printf 'alive\n' >"$tmp/evidence-verdict"
run "$h14" publish --checkout "$co_a" --session-id "$uuid_a" --pid 77777 \
  --fenced demo-spec/3,demo-spec/4.5-5 >/dev/null
out=$(run "$h14" owner --checkout "$co_b" --pid $$ demo-spec/3 2>/dev/null) \
  || fail "owner resolution failed"
[ "$out" = "owner	$uuid_a" ] || fail "owner not resolved from the fenced field: $out"
out=$(run "$h14" owner --checkout "$co_b" --pid $$ demo-spec/9 2>/dev/null) \
  || fail "unknown-owner probe failed"
[ "$out" = "unknown-owner" ] || fail "unlisted unit not classified unknown-owner: $out"
# Attribution is from LIVE records only (REQ-A1.2/REQ-C1.3): a fence listed
# only by an unknown-liveness record is unknown-owner.
printf 'unknown\n' >"$tmp/evidence-verdict"
out=$(run "$h14" owner --checkout "$co_b" --pid $$ demo-spec/3 2>/dev/null) \
  || fail "unknown-verdict owner probe failed"
[ "$out" = "unknown-owner" ] || fail "unknown-liveness record used as an attribution source: $out"
printf 'alive\n' >"$tmp/evidence-verdict"
# A second live record claiming the same unit: first match kept
# (deterministic by tower-id sort order), the duplicate surfaced on stderr.
run "$h14" publish --checkout "$co_b" --session-id "$uuid_b" --pid 77778 \
  --fenced demo-spec/3 >/dev/null
err14="$tmp/h14-err"
out=$(run "$h14" owner --checkout "$co_b" --pid $$ demo-spec/3 2>"$err14") \
  || fail "duplicate-claim owner probe failed"
[ "$out" = "owner	$uuid_a" ] || fail "duplicate claim changed the first-match owner: $out"
grep -q "second live record" "$err14" || fail "duplicate live fence claim not surfaced"
rc=0
run "$h14" owner --checkout "$co_b" --pid $$ '../etc/passwd' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "hostile unit ref not refused (exit $rc)"
echo "ok: fence owner resolved from live records only; unlisted/unknown → unknown-owner; duplicates surfaced; hostile ref refused"

# ---------------------------------------------------------------------------
# 15. Hostile publish input is refused before any write (REQ-D1.5 posture):
#     bad spec ids, bad fenced refs, bad pids, bad tmux tokens.
# ---------------------------------------------------------------------------
h15="$tmp/h15"
mkdir -p "$h15"
for args in \
  "--specs ../evil" \
  "--specs UPPER" \
  "--fenced demo-spec/;rm" \
  "--fenced noslash" \
  "--pid 0x10" \
  "--pid 007" \
  "--tmux-session bad;name --tmux-window w" \
  "--tmux-session s --tmux-window -w"; do
  rc=0
  # shellcheck disable=SC2086
  run "$h15" publish --checkout "$co_a" --session-id "$uuid_a" --pid 88888 $args \
    >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "hostile publish input not refused: '$args' (exit $rc)"
done
[ ! -d "$h15/presence" ] || {
  n=$(find "$h15/presence" -type f | wc -l | tr -d ' ')
  [ "$n" = 0 ] || fail "a refused publish still wrote a record"
}
# An oversize record (> the 8191-byte cap peers enforce) is refused at the
# WRITER, so the publisher gets the signal instead of every peer silently
# classifying it malformed.
big_fenced=$(awk 'BEGIN{s="demo-spec/1";for(i=2;i<=800;i++)s=s ",demo-spec/" i; print s}')
rc=0
run "$h15" publish --checkout "$co_a" --session-id "$uuid_a" --pid 88888 \
  --fenced "$big_fenced" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "oversize publish not refused (exit $rc)"
sub15=$(run "$h15" surface --checkout "$co_a")
[ ! -f "$sub15/$uuid_a" ] || fail "an oversize refused publish still wrote a record"
echo "ok: hostile publish input refused before any write; oversize record refused at the writer"

# ---------------------------------------------------------------------------
# 16. Structural assertions over the source (REQ-A1.2 / REQ-A1.3 / REQ-A1.6):
#     write-temp-then-rename on the publish path; no shared registry file; no
#     LLM and no pane/process-listing scrape on the discovery path; the meta
#     marker is not read from fleet-tower-marker.sh; no quarantine or
#     dead-letter sub-surface exists.
# ---------------------------------------------------------------------------
src="$here/../scripts/fleet-presence.sh"
# Call-level: the PUBLISH primitive is a temp file created inside the
# sub-surface, renamed onto the per-tower target — a mkdir-then-populate or
# direct-write publish would fail these exact-line asserts. The patterns are
# literal source text: `$` must NOT expand here.
# shellcheck disable=SC2016
grep -q 'mktemp "\$sub/\.pub\.' "$src" \
  || fail "publish path lacks the in-surface temp-file write (structural)"
# shellcheck disable=SC2016
grep -q 'mv -f "\$pub_tmp" "\$own"' "$src" \
  || fail "publish path lacks the temp→record rename (structural)"
# No shared-registry write: the publish rename target is the per-tower file
# keyed by identity, and no fixed shared filename is ever written on the
# publish path.
# shellcheck disable=SC2016
grep -q 'own="\$sub/\$identity"' "$src" \
  || fail "publish target is not the per-tower identity-keyed file (structural)"
grep -q 'fleet-tower-marker' "$src" \
  && fail "meta marker must be the record's own field, not fleet-tower-marker.sh"
grep -Ewq 'claude|anthropic' "$src" && fail "discovery path invokes an LLM"
grep -Eq 'capture-pane|list-windows|list-panes|ps -e|ps ax' "$src" \
  && fail "discovery path scrapes panes or process listings"
grep -Eq '(^|[^-A-Za-z])tmux +(ls|has-session|new|send-keys|attach)' "$src" \
  && fail "presence must not query tmux directly (death-evidence owns it)"
grep -Eiq 'quarantine|dead-letter' "$src" \
  && fail "no quarantine / dead-letter sub-surface may exist (REQ-A1.6)"
grep -q 'fleet-death-evidence.sh' "$src" \
  || fail "liveness must route through fleet-death-evidence.sh"
echo "ok: structural asserts (temp+rename, no registry/LLM/scrape/quarantine, predicate reuse)"

# ---------------------------------------------------------------------------
# 17. Panel-review coverage additions: identity/handle refusals, strict
#     per-command flags, hostile --min-interval, lone tmux flag, checkout
#     refusals, missing flag value, empty-origin solo posture, owner
#     contract lines (range refs, self-exclusion, dead-record skip),
#     field-level record validation, obstructed sub-surface, sentinel
#     symlink refusal, start-epoch preserve/reset, cadence edges, and
#     gc-skip's contribution to the peer count.
# ---------------------------------------------------------------------------
h17="$tmp/h17"

# Identity refusals: no identity flags at all, and publish with an identity
# but no death handle (session-id only: no tmux pair, no pid).
rc=0
run "$h17" publish --checkout "$co_a" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "publish without identity not refused (exit $rc)"
rc=0
run "$h17" discover --checkout "$co_a" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "discover without identity not refused (exit $rc)"
rc=0
run "$h17" publish --checkout "$co_a" --session-id "$uuid_a" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "publish without a death handle not refused (exit $rc)"

# Strict per-command grammar: a flag irrelevant to the subcommand is a usage
# error, never a silent no-op.
rc=0
run "$h17" publish --checkout "$co_a" --session-id "$uuid_a" --pid 4242 \
  --min-interval 5 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "publish --min-interval not refused (exit $rc)"
rc=0
run "$h17" discover --checkout "$co_a" --session-id "$uuid_a" \
  --fenced demo-spec/1 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "discover --fenced not refused (exit $rc)"
rc=0
run "$h17" discover --checkout "$co_a" --session-id "$uuid_a" --meta \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "discover --meta not refused (exit $rc)"
rc=0
run "$h17" owner --checkout "$co_a" --session-id "$uuid_a" --tmux-session s \
  --tmux-window w demo-spec/1 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "owner with tmux flags not refused (exit $rc)"
rc=0
run "$h17" surface --checkout "$co_a" --session-id "$uuid_a" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "surface --session-id not refused (exit $rc)"

# Hostile --min-interval, a lone tmux flag (both-required), checkout
# refusals, and a flag missing its value.
rc=0
run "$h17" discover --checkout "$co_a" --session-id "$uuid_a" \
  --min-interval abc >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "malformed --min-interval not refused (exit $rc)"
rc=0
run "$h17" discover --checkout "$co_a" --session-id "$uuid_a" \
  --min-interval -5 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "negative --min-interval not refused (exit $rc)"
rc=0
run "$h17" publish --checkout "$co_a" --session-id "$uuid_a" --pid 4242 \
  --tmux-session sess >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "lone --tmux-session not refused (exit $rc)"
rc=0
run "$h17" publish --checkout "$co_a" --session-id "$uuid_a" --pid 4242 \
  --tmux-window win >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "lone --tmux-window not refused (exit $rc)"
rc=0
run "$h17" identity --checkout relative/path --pid $$ >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "relative checkout not refused (exit $rc)"
rc=0
run "$h17" identity --checkout "$tmp/does-not-exist" --pid $$ >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "nonexistent checkout not refused (exit $rc)"
rc=0
run "$h17" identity --checkout "$(printf '%s/ctl\001dir' "$tmp")" --pid $$ \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "control-byte checkout not refused (exit $rc)"
rc=0
run "$h17" identity --pid $$ --checkout >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "missing --checkout value not refused (exit $rc)"

# Empty origin URL: hashing "" would converge every such repo on one shared
# sub-surface — must be the no-usable-origin solo posture instead (exit 5).
co_emptyorigin="$tmp/empty-origin"
mkdir -p "$co_emptyorigin"
git -C "$co_emptyorigin" init -q
git -C "$co_emptyorigin" config remote.origin.url ""
rc=0
run "$h17" identity --checkout "$co_emptyorigin" --pid $$ >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "empty origin URL not the solo posture (exit $rc, expected 5)"
echo "ok: refusals — identity/handle, per-command flags, hostile values, empty origin"

# Owner contract lines: a range/dotted unit ref resolves; the querying
# tower's own record is identity-excluded; a positively-dead record is
# never an attribution source and owner (read-only) never GCs it.
printf 'alive\n' >"$tmp/evidence-verdict"
run "$h17" publish --checkout "$co_a" --session-id "$uuid_a" --pid 4242 \
  --fenced demo-spec/3,demo-spec/4.5-5 >/dev/null || fail "owner fixture publish failed"
sub17=$(run "$h17" surface --checkout "$co_a")
out=$(run "$h17" owner --checkout "$co_b" --pid $$ demo-spec/4.5-5 2>/dev/null) \
  || fail "range-ref owner query failed"
[ "$out" = "owner	$uuid_a" ] || fail "range unit ref not resolved from the fenced field: $out"
out=$(run "$h17" owner --checkout "$co_a" --session-id "$uuid_a" demo-spec/3 2>/dev/null) \
  || fail "self owner query failed"
[ "$out" = "unknown-owner" ] || fail "own record not identity-excluded from owner (got: $out)"
printf 'dead\n' >"$tmp/evidence-verdict"
out=$(run "$h17" owner --checkout "$co_b" --pid $$ demo-spec/3 2>/dev/null) \
  || fail "dead-record owner query failed"
[ "$out" = "unknown-owner" ] || fail "dead record used for owner attribution (got: $out)"
[ -f "$sub17/$uuid_a" ] || fail "owner (read-only) GC'd a record"
printf 'alive\n' >"$tmp/evidence-verdict"
echo "ok: owner — range refs resolve, self-excluded, dead records never attribute or GC"

# Field-level record validation: a well-tagged, 10-field record with one
# off-grammar field (a bad death handle) classifies malformed.
badrec_id="99999999-8888-7777-6666-555555555555"
printf 'pw-presence-v1\t%s\t%s\t%s\t-\t-\t100\t100\tprocess nope\tfalse\n' \
  "$(basename "$sub17")" "$badrec_id" "$co_a" >"$sub17/$badrec_id"
out=$(run "$h17" discover --checkout "$co_a" --pid $$ --min-interval 0 2>/dev/null)
printf '%s\n' "$out" | grep -q "peer-unreadable	$badrec_id	malformed" \
  || fail "field-level invalid record not classified malformed: $out"
rm -f "$sub17/$badrec_id"

# Obstructed sub-surface: a FILE where the directory should be is exit 3
# (unknown peer status), never solitude and never a bootstrap.
h17b="$tmp/h17b"
run "$h17b" publish --checkout "$co_a" --session-id "$uuid_a" --pid 4242 \
  >/dev/null || fail "obstruction fixture publish failed"
sub17b=$(run "$h17b" surface --checkout "$co_a")
rm -rf "$sub17b"
: >"$sub17b"
rc=0
run "$h17b" discover --checkout "$co_a" --pid $$ --min-interval 0 \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "obstructed sub-surface not exit 3 (got $rc)"

# Sentinel symlink refusal: a (dangling) symlink at the sentinel path is
# refused (exit 4) and never written through.
h17c="$tmp/h17c"
mkdir -p "$h17c"
ln -s "$tmp/sentinel-target" "$h17c/presence.sentinel"
rc=0
run "$h17c" publish --checkout "$co_a" --session-id "$uuid_a" --pid 4242 \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "symlinked sentinel not refused (exit $rc, expected 4)"
[ ! -e "$tmp/sentinel-target" ] || fail "sentinel written through a symlink"
echo "ok: field-level malformed, obstructed surface exit 3, sentinel symlink refused"

# Start epoch across heartbeats: a valid preserved start survives a
# re-publish; a garbage own record resets start to the fresh beat.
h17d="$tmp/h17d"
run "$h17d" publish --checkout "$co_a" --session-id "$uuid_a" --pid 4242 \
  >/dev/null || fail "start-epoch fixture publish failed"
sub17d=$(run "$h17d" surface --checkout "$co_a")
awk -F'	' 'BEGIN{OFS="\t"} {$7=100; print}' "$sub17d/$uuid_a" \
  >"$sub17d/.tmp-start" && mv "$sub17d/.tmp-start" "$sub17d/$uuid_a"
run "$h17d" publish --checkout "$co_a" --session-id "$uuid_a" --pid 4242 \
  >/dev/null || fail "heartbeat re-publish failed"
start_f=$(awk -F'	' '{print $7}' "$sub17d/$uuid_a")
[ "$start_f" = "100" ] || fail "valid start epoch not preserved across heartbeat ($start_f)"
printf 'garbage no tabs\n' >"$sub17d/$uuid_a"
run "$h17d" publish --checkout "$co_a" --session-id "$uuid_a" --pid 4242 \
  >/dev/null || fail "re-publish over garbage failed"
start_f=$(awk -F'	' '{print $7}' "$sub17d/$uuid_a")
beat_f=$(awk -F'	' '{print $8}' "$sub17d/$uuid_a")
[ "$start_f" = "$beat_f" ] || fail "start epoch not reset over an unreadable own record ($start_f vs $beat_f)"

# Cadence edges: --min-interval 0 never writes a stamp; a future-dated
# stamp (clock step) and garbage stamp content never lock discovery out.
h17e="$tmp/h17e"
run "$h17e" publish --checkout "$co_a" --session-id "$uuid_b" --pid 4242 \
  >/dev/null || fail "cadence fixture publish failed"
sub17e=$(run "$h17e" surface --checkout "$co_a")
run "$h17e" discover --checkout "$co_a" --session-id "$uuid_a" \
  --min-interval 0 >/dev/null 2>&1 || fail "cap-disabled discover failed"
stamp17="$h17e/presence.cadence/$(basename "$sub17e").$uuid_a"
[ ! -e "$stamp17" ] || fail "--min-interval 0 wrote a cadence stamp"
printf '%s\n' "$(($(date +%s) + 99999))" >"$stamp17"
out=$(run "$h17e" discover --checkout "$co_a" --session-id "$uuid_a" \
  --min-interval 9999 2>/dev/null) || fail "future-stamp discover failed"
case "$out" in
  cadence-capped*) fail "future-dated stamp capped discovery (clock-skew lockout)" ;;
esac
printf '%s\n' "$out" | grep -q '^summary	' || fail "future-stamp discover produced no summary"
printf 'not-a-number\n' >"$stamp17"
out=$(run "$h17e" discover --checkout "$co_a" --session-id "$uuid_a" \
  --min-interval 9999 2>/dev/null) || fail "garbage-stamp discover failed"
case "$out" in
  cadence-capped*) fail "garbage stamp capped discovery" ;;
esac

# gc-skip argues against solitude: a re-published-during-GC record is
# spared AND counted (sole-tower=no on that pass).
h17f="$tmp/h17f"
run "$h17f" publish --checkout "$co_a" --session-id "$uuid_b" --pid 4242 \
  >/dev/null || fail "gc-skip fixture publish failed"
sub17f=$(run "$h17f" surface --checkout "$co_a")
awk -F'	' 'BEGIN{OFS="\t"} {$8=$8+100; print}' "$sub17f/$uuid_b" >"$tmp/fresh-record"
printf '%s\n' "$sub17f/$uuid_b" >"$tmp/swap-on-call"
printf 'dead\n' >"$tmp/evidence-verdict"
out=$(run "$h17f" discover --checkout "$co_a" --pid $$ --min-interval 0 2>/dev/null)
rm -f "$tmp/swap-on-call"
printf 'alive\n' >"$tmp/evidence-verdict"
printf '%s\n' "$out" | grep -q "gc-skip	$uuid_b" || fail "gc-skip fixture did not gc-skip: $out"
printf '%s\n' "$out" | grep -q "sole-tower=no" \
  || fail "gc-skip did not count toward the peer set (summary: $out)"
echo "ok: start-epoch preserve/reset, cadence edges never lock out, gc-skip counts as a peer"

echo "PASS: all fleet-presence tests"
