#!/bin/bash
# Tests for scripts/fleet-presence.sh — the cross-tower presence signal:
# publish, discover, liveness-classify, GC, and owner attribution
# (concurrent-orchestrator-coordination Task 2: D-2 · REQ-A1.1–REQ-A1.7).
#
# Contract under test:
#   publish  --checkout <dir> [--pid <pid>] [--session-id <uuid>]
#            [--specs <csv>] [--fenced <csv>]
#            [--tmux-session <name> --tmux-window <name>] [--meta]
#       Write/refresh this tower's own presence record atomically
#       (write-temp-then-rename) under <surface>/<repo-id>/<tower-id>.
#   discover --checkout <dir> [--pid <pid>] [--session-id <uuid>]
#            [--min-interval <sec>]
#       Scan the current repo-id sub-surface, exclude own record by tower
#       identity, classify each peer via fleet-death-evidence.sh (tri-state,
#       memoized per pass), GC positively-dead records under a re-read-and-
#       skip guard, and print peer/summary lines.
#   owner    --checkout <dir> [identity flags] <spec>/<unit-id>
#       Resolve a fenced unit's owner from live records' fenced field;
#       `unknown-owner` when no live record lists it.
#   identity --checkout <dir> [--pid <pid>] [--session-id <uuid>]
#       Print the derived tower identity (REQ-A1.7).
#   surface  --checkout <dir>
#       Print the per-repo sub-surface path.
#   Exit codes: 0 ok (incl. healthy-empty & cadence-capped); 2 usage /
#       refused input / write failure; 3 unknown-peer-status (vanished or
#       unreadable surface — fail closed, never solitude); 4 security
#       refusal (over-broad surface, verify-or-refuse); 5 no origin remote
#       (genuine solo posture).
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
h1="$tmp/h1"
mkdir -p "$h1"
run "$h1" publish --checkout "$co_a" --session-id "$uuid_a" \
  --specs demo-spec --fenced demo-spec/3 --pid 4242 \
  || fail "first publish failed"
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
  d???------ | d???------[@+.]) : ;;
  *) fail "surface root not 0700: $perms" ;;
esac
perms=$(perms_of "$sub")
case "$perms" in
  d???------ | d???------[@+.]) : ;;
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
run "$h1" publish --checkout "$co_a" --session-id "$uuid_a" \
  --specs demo-spec --fenced demo-spec/3,demo-spec/4 \
  --tmux-session tower0 --tmux-window w1 --meta \
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
echo "ok: discovery is cadence-capped (no fan-out inside the interval)"

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
echo "ok: alive/unknown never reclaim (bytes untouched); only positively-dead GCs"

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
echo "ok: GC re-reads and skips a changed record; heartbeat re-publish self-heals"

# ---------------------------------------------------------------------------
# 11. REQ-A1.6 — defensive parsing: malformed, truncated, and schema-skewed
#     records are surfaced (assume-live, never GC'd, never read as absent);
#     the tower holding only unreadable peers is NOT sole.
# ---------------------------------------------------------------------------
h11="$tmp/h11"
mkdir -p "$h11"
run "$h11" publish --checkout "$co_a" --session-id "$uuid_a" >/dev/null 2>&1 \
  || run "$h11" publish --checkout "$co_a" --session-id "$uuid_a" --pid 44444 >/dev/null
sub11=$(run "$h11" surface --checkout "$co_a")
rm -f "$sub11/$uuid_a"
printf 'garbage not a record\n' >"$sub11/one-malformed"
printf 'pw-presence-v1	short\n' >"$sub11/two-truncated"
printf 'pw-presence-v9	%s	%s	/x	-	-	1	2	process 1	false\n' \
  "$(basename "$sub11")" "$uuid_b" >"$sub11/three-skewed"
printf 'dead\n' >"$tmp/evidence-verdict"
err="$tmp/h11-err"
out=$(run "$h11" discover --checkout "$co_a" --pid $$ --min-interval 0 2>"$err") \
  || fail "discover over unreadable records failed (must degrade, not die)"
[ -f "$sub11/one-malformed" ] || fail "malformed record was GC'd (never reclaim on a guess)"
[ -f "$sub11/two-truncated" ] || fail "truncated record was GC'd"
[ -f "$sub11/three-skewed" ] || fail "schema-skewed record was GC'd"
n_unreadable=$(printf '%s\n' "$out" | grep -c "peer-unreadable") || true
[ "$n_unreadable" = 3 ] || fail "expected 3 unreadable-peer lines, got $n_unreadable"
grep -qi "unreadable\|malformed\|skew" "$err" || fail "unreadable records not surfaced on stderr"
printf '%s\n' "$out" | grep -q "sole-tower=no" \
  || fail "unreadable peers must count against solitude (assume-live)"
echo "ok: malformed/truncated/skewed records surfaced, assume-live, never GC'd"

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
echo "ok: vanished/unreadable surfaces fail closed (exit 3), empty surface is healthy"

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
rc=0
run "$h14" owner --checkout "$co_b" --pid $$ '../etc/passwd' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "hostile unit ref not refused (exit $rc)"
echo "ok: fence owner resolved from live records; unlisted → unknown-owner; hostile ref refused"

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
echo "ok: hostile publish input refused before any write"

# ---------------------------------------------------------------------------
# 16. Structural assertions over the source (REQ-A1.2 / REQ-A1.3 / REQ-A1.6):
#     write-temp-then-rename on the publish path; no shared registry file; no
#     LLM and no pane/process-listing scrape on the discovery path; the meta
#     marker is not read from fleet-tower-marker.sh; no quarantine or
#     dead-letter sub-surface exists.
# ---------------------------------------------------------------------------
src="$here/../scripts/fleet-presence.sh"
grep -q 'mktemp' "$src" || fail "publish path lacks a temp-file write (structural)"
grep -Eq 'mv (-f )?"?\$' "$src" || fail "publish path lacks the rename step (structural)"
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

echo "PASS: all fleet-presence tests"
