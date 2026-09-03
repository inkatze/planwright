#!/bin/bash
# Tests for the coordination-artifact hygiene guard and the framework-script
# security bars on the coordination scripts
# (concurrent-orchestrator-coordination Task 5: D-6, D-9 ·
# REQ-D1.1, REQ-D1.2, REQ-D1.4, REQ-D1.5).
#
# Two contracts under test.
#
# (1) scripts/check-coordination-hygiene.sh — the CONDITIONAL hygiene guard.
#     Presence records, the fence namespace, and the strand sink are runtime
#     machine-local surfaces, so normally nothing lands in git and the guard is
#     a clean no-op. When a deployment DOES commit a coordination artifact (an
#     audit or handover log, a summary of presence records, a PR body carrying
#     one), the guard screens it for the four leak classes REQ-D1.4 names:
#     checkout paths, death handles, internal hostnames, and credentials.
#       (default)       detect committed artifacts by record shape, then screen
#       <path>...       screen declared artifacts unconditionally
#     Exit: 0 clean or nothing to screen · 1 a leak · 2 usage/environment.
#     Findings are reported as `<file>:<line>: <rule>` and NEVER carry the
#     matched text (echo discipline: a guard that prints what it caught has
#     moved the leak into the CI log).
#
# (2) The REQ-D1.5 security bars on scripts/fleet-presence.sh and
#     scripts/fleet-fence.sh: every parsed field of a peer record refused when
#     it violates its declared grammar — asserted PER FIELD, including the
#     meta-tower marker, the checkout path, the death handle (against its two
#     fleet-death-evidence.sh forms), and each entry of the fenced-unit-ids
#     list; the unit and spec id validated before any origin fence-ref push or
#     delete, with the ref name confirmed inside refs/planwright-fence/<spec>/;
#     canonicalization and containment on the surface directory itself,
#     including against a surface-root symlink; the echo sanitizer on untrusted
#     fields; and the data-not-code discipline on peer records.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
GUARD="$root/scripts/check-coordination-hygiene.sh"
FP="$root/scripts/fleet-presence.sh"
FF="$root/scripts/fleet-fence.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$GUARD" ] || fail "scripts/check-coordination-hygiene.sh missing or not executable"
[ -x "$FP" ] || fail "scripts/fleet-presence.sh missing or not executable"
[ -x "$FF" ] || fail "scripts/fleet-fence.sh missing or not executable"

tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

TAB=$(printf '\t')
ESC=$(printf '\033')

# --- fixtures -------------------------------------------------------------
# The death-evidence stub logs every call, so "validated before use, never
# interpolated" is checked directly: an off-grammar handle must produce NO
# predicate call at all.
stubbin="$tmp/stub-scripts"
mkdir -p "$stubbin"
cp "$root/scripts/"*.sh "$stubbin/"
cat >"$stubbin/fleet-death-evidence.sh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/evidence-calls"
printf 'alive\n'
exit 1
EOF
chmod +x "$stubbin/fleet-death-evidence.sh"
: >"$tmp/evidence-calls"

co="$tmp/checkout"
mkdir -p "$co"
git -C "$co" init -q
git -C "$co" remote add origin "ssh://git@example.invalid/acme/widgets.git"

uuid_self="11111111-2222-3333-4444-555555555555"
uuid_peer="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

run_fp() {
  rf_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    PLANWRIGHT_FLEET_STATE_DIR="$rf_home" \
    /bin/sh "$stubbin/fleet-presence.sh" "$@"
}

# A fixture git repo with one tracked file of the caller's choosing.
mk_repo() {
  mr_dir=$1
  mkdir -p "$mr_dir"
  git -C "$mr_dir" init -q
  git -C "$mr_dir" config user.email t@example.invalid
  git -C "$mr_dir" config user.name t
}

commit_all() {
  git -C "$1" add -A
  git -C "$1" commit -qm fixture
}

# ---------------------------------------------------------------------------
# 1. REQ-D1.4 — the guard is CONDITIONAL: a repository that commits no
#    coordination record is a clean no-op, never a false failure.
# ---------------------------------------------------------------------------
r1="$tmp/repo-none"
mk_repo "$r1"
printf 'a project readme mentioning pw-presence-v1 in prose\n' >"$r1/README.md"
printf 'the fence namespace is refs/planwright-fence/<spec>/<unit>\n' >"$r1/DESIGN.md"
printf 'peer at /home/alice/dev/widgets held by process 4242\n' >>"$r1/DESIGN.md"
commit_all "$r1"
rc=0
out=$("$GUARD" --repo "$r1" 2>&1) || rc=$?
[ "$rc" = 0 ] || fail "no committed coordination record must be a no-op (exit $rc): $out"
printf '%s\n' "$out" | grep -qi "nothing to screen\|no committed coordination" \
  || fail "the no-op arm did not say it found nothing to screen: $out"
echo "ok: no committed coordination record — clean no-op, never a false failure"

# ---------------------------------------------------------------------------
# 2. REQ-D1.4 — a committed presence record IS detected (record shape at
#    column 1, not a prose mention) and its checkout path and death handle
#    are both flagged: the two operational-detail classes REQ-D1.4 names.
# ---------------------------------------------------------------------------
r2="$tmp/repo-record"
mk_repo "$r2"
printf 'pw-presence-v1%s0123456789abcdef%s%s%s/home/alice/dev/widgets%sdemo-spec%s-%s100%s200%sprocess 4242%sfalse\n' \
  "$TAB" "$TAB" "$uuid_peer" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" \
  >"$r2/handover-log.txt"
commit_all "$r2"
rc=0
out=$("$GUARD" --repo "$r2" 2>&1) || rc=$?
[ "$rc" = 1 ] || fail "a committed presence record must be flagged (exit $rc): $out"
printf '%s\n' "$out" | grep -q "handover-log.txt:1: checkout-path" \
  || fail "committed checkout path not flagged: $out"
printf '%s\n' "$out" | grep -q "handover-log.txt:1: death-handle" \
  || fail "committed death handle not flagged: $out"
echo "ok: a committed presence record is detected; checkout path and death handle both flagged"

# ---------------------------------------------------------------------------
# 3. REQ-D1.4 — the guard NEVER echoes the matched text: a finding is a
#    location plus a rule name, so the leak does not move into the CI log.
# ---------------------------------------------------------------------------
printf '%s\n' "$out" | grep -q "/home/alice/dev/widgets" \
  && fail "the guard echoed the checkout path it caught (leak moved into the log)"
printf '%s\n' "$out" | grep -q "process 4242" \
  && fail "the guard echoed the death handle it caught"
echo "ok: findings report location + rule only, never the matched text"

# ---------------------------------------------------------------------------
# 4. REQ-D1.4 — a CLEAN committed coordination artifact passes: detection
#    alone is not a finding.
# ---------------------------------------------------------------------------
r4="$tmp/repo-clean"
mk_repo "$r4"
printf 'pw-presence-v1%s0123456789abcdef%s%s%s-%sdemo-spec%sdemo-spec/3%s100%s200%s-%sfalse\n' \
  "$TAB" "$TAB" "$uuid_peer" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" \
  >"$r4/summary.txt"
commit_all "$r4"
rc=0
out4=$("$GUARD" --repo "$r4" 2>&1) || rc=$?
[ "$rc" = 0 ] || fail "a clean committed coordination artifact must pass (exit $rc): $out4"
echo "ok: a clean committed coordination artifact passes"

# ---------------------------------------------------------------------------
# 5. REQ-D1.4 — the other two leak classes: an internal hostname and a
#    credential, each in a committed coordination artifact.
# ---------------------------------------------------------------------------
r5="$tmp/repo-host"
mk_repo "$r5"
{
  printf 'refs/planwright-fence/demo-spec/4\n'
  printf 'owner tower reachable at build-07.corp.internal\n'
} >"$r5/strand-log.txt"
commit_all "$r5"
rc=0
out5=$("$GUARD" --repo "$r5" 2>&1) || rc=$?
[ "$rc" = 1 ] || fail "an internal hostname must be flagged (exit $rc): $out5"
printf '%s\n' "$out5" | grep -q "strand-log.txt:2: internal-hostname" \
  || fail "internal hostname not flagged at its line: $out5"
printf '%s\n' "$out5" | grep -q "build-07.corp.internal" \
  && fail "the guard echoed the hostname it caught"

r6="$tmp/repo-secret"
mk_repo "$r6"
{
  printf 'refs/planwright-fence/demo-spec/4\n'
  printf -- '-----BEGIN RSA PRIVATE KEY-----\n'
} >"$r6/audit-log.txt"
commit_all "$r6"
rc=0
out6=$(PLANWRIGHT_SECRET_SCREEN_TOOL=none "$GUARD" --repo "$r6" 2>&1) || rc=$?
[ "$rc" = 1 ] || fail "a seeded credential must be flagged (exit $rc): $out6"
printf '%s\n' "$out6" | grep -qi "private-key-block\|secret" \
  || fail "credential not flagged: $out6"
echo "ok: internal hostname and credential classes flagged in committed artifacts"

# ---------------------------------------------------------------------------
# 6. REQ-D1.4 — declared-path mode: a PR body is not record-shaped, so the
#    deployment names it. Both a peer checkout path AND a death handle are
#    shown not to reach it — the no-leak assertion the Done-when pins.
# ---------------------------------------------------------------------------
pr_dirty="$tmp/pr-body-dirty.md"
{
  printf '## Summary\n\n'
  printf -- '- fenced by peer tower at /home/alice/dev/widgets\n'
  printf -- '- owner death handle: tmux-window fleet worker-3\n'
} >"$pr_dirty"
rc=0
outp=$("$GUARD" "$pr_dirty" 2>&1) || rc=$?
[ "$rc" = 1 ] || fail "a PR body carrying peer operational detail must be flagged (exit $rc): $outp"
printf '%s\n' "$outp" | grep -q "pr-body-dirty.md:3: checkout-path" \
  || fail "PR-body checkout path not flagged: $outp"
printf '%s\n' "$outp" | grep -q "pr-body-dirty.md:4: death-handle" \
  || fail "PR-body tmux-window death handle not flagged: $outp"

pr_clean="$tmp/pr-body-clean.md"
{
  printf '## Summary\n\n'
  printf -- '- the unit was fenced by a peer tower; see the strand sink\n'
} >"$pr_clean"
rc=0
outc=$("$GUARD" "$pr_clean" 2>&1) || rc=$?
[ "$rc" = 0 ] || fail "a clean PR body must pass (exit $rc): $outc"
echo "ok: declared-path mode — a peer checkout path and a death handle never reach a PR body"

# ---------------------------------------------------------------------------
# 7. REQ-D1.4 — the guard is wired into `mise run check` alongside the
#    existing secret scan, so it runs on every gate rather than on request.
# ---------------------------------------------------------------------------
grep -q 'check:coordination-hygiene' "$root/mise.toml" \
  || fail "the hygiene guard has no mise task"
awk '/^\[tasks\.check\]/ { in_check = 1 } in_check && /coordination-hygiene/ { hit = 1 } END { exit !hit }' \
  "$root/mise.toml" || fail "check:coordination-hygiene is not in the check aggregate"
echo "ok: the hygiene guard is wired into mise run check"

# ---------------------------------------------------------------------------
# 8. REQ-D1.5 — per-field grammar refusal on an untrusted peer record,
#    asserted PER FIELD. Each fixture is a well-formed ten-field record with
#    exactly ONE field off-grammar; it must classify unreadable (never a
#    readable peer) and must never be GC'd on a guess.
# ---------------------------------------------------------------------------
h8="$tmp/h8"
run_fp "$h8" publish --checkout "$co" --session-id "$uuid_self" --pid $$ >/dev/null \
  || fail "field-grammar fixture publish failed"
sub8=$(run_fp "$h8" surface --checkout "$co")
repo_id=$(basename "$sub8")

# write_record <tag> <repo> <id> <checkout> <specs> <fenced> <start> <beat> <handle> <meta>
write_record() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" >"$sub8/$uuid_peer"
}

# A record that is on-grammar in every field: the control that proves each
# refusal below comes from the ONE field the case mutates.
write_record pw-presence-v1 "$repo_id" "$uuid_peer" "$co" demo-spec demo-spec/3 \
  100 200 "process 4242" false
out=$(run_fp "$h8" discover --checkout "$co" --session-id "$uuid_self" --min-interval 0 2>/dev/null)
printf '%s\n' "$out" | grep -q "peer${TAB}${uuid_peer}${TAB}live" \
  || fail "the all-fields-valid control record was not read as a live peer: $out"

# field <n> <name> <hostile-value>
assert_field_refused() {
  af_name=$1
  af_field=$2
  af_value=$3
  set -- pw-presence-v1 "$repo_id" "$uuid_peer" "$co" demo-spec demo-spec/3 \
    100 200 "process 4242" false
  af_args=""
  af_i=1
  for af_v in "$@"; do
    if [ "$af_i" = "$af_field" ]; then af_v=$af_value; fi
    af_args="$af_args$af_v$TAB"
    af_i=$((af_i + 1))
  done
  printf '%s\n' "${af_args%"$TAB"}" >"$sub8/$uuid_peer"
  af_out=$(run_fp "$h8" discover --checkout "$co" --session-id "$uuid_self" \
    --min-interval 0 2>/dev/null)
  printf '%s\n' "$af_out" | grep -q "peer-unreadable${TAB}${uuid_peer}${TAB}" \
    || fail "field $af_field ($af_name) off-grammar was not refused: $af_out"
  printf '%s\n' "$af_out" | grep -q "peer${TAB}${uuid_peer}${TAB}live" \
    && fail "field $af_field ($af_name) off-grammar was still read as a live peer"
  [ -f "$sub8/$uuid_peer" ] \
    || fail "field $af_field ($af_name) off-grammar record was GC'd (never reclaim on a guess)"
}

assert_field_refused "schema tag" 1 pw-presence-v9
assert_field_refused "repository id" 2 "not-a-hex-repo"
assert_field_refused "tower identity" 3 "p1.tX.c2"
assert_field_refused "checkout path" 4 "relative/not/absolute"
assert_field_refused "spec list" 5 "Bad_Spec"
assert_field_refused "fenced unit-ids" 6 "demo-spec/not-a-unit"
assert_field_refused "start epoch" 7 "notanepoch"
assert_field_refused "heartbeat epoch" 8 "-5"
assert_field_refused "death handle" 9 "reboot now"
assert_field_refused "meta-tower marker" 10 "yes"

# The death handle's declared grammar is EXACTLY the two
# fleet-death-evidence.sh forms — no third spelling, and neither form's
# operand may be off-grammar.
assert_field_refused "death handle (pid zero)" 9 "process 0"
assert_field_refused "death handle (non-numeric pid)" 9 "process nope"
assert_field_refused "death handle (tmux, no window)" 9 "tmux-window sess"
assert_field_refused "death handle (tmux, hostile token)" 9 "tmux-window sess ../../x"
echo "ok: every parsed record field refused when off-grammar, asserted per field"

# ---------------------------------------------------------------------------
# 9. REQ-D1.5 — an off-grammar death handle is refused BEFORE use: it never
#    reaches fleet-death-evidence.sh, so nothing hostile is interpolated into
#    the predicate's argv.
# ---------------------------------------------------------------------------
: >"$tmp/evidence-calls"
write_record pw-presence-v1 "$repo_id" "$uuid_peer" "$co" demo-spec demo-spec/3 \
  100 200 "process 4242; touch $tmp/pwned" false
run_fp "$h8" discover --checkout "$co" --session-id "$uuid_self" --min-interval 0 \
  >/dev/null 2>&1 || true
[ ! -e "$tmp/pwned" ] || fail "a hostile death handle was executed"
grep -q "touch" "$tmp/evidence-calls" \
  && fail "an off-grammar death handle was passed to the death predicate"
echo "ok: an off-grammar death handle never reaches the death predicate"

# ---------------------------------------------------------------------------
# 10. REQ-D1.5 — echo discipline: an escape sequence in an untrusted record
#     field is stripped before the value is echoed to a terminal or log.
# ---------------------------------------------------------------------------
rm -f "$sub8/$uuid_peer"
esc_name="peer${ESC}[31mred"
printf 'garbage\n' >"$sub8/$esc_name"
out=$(run_fp "$h8" discover --checkout "$co" --session-id "$uuid_self" \
  --min-interval 0 2>&1 || true)
case "$out" in
  *"$ESC"*) fail "an escape sequence in a record field reached the terminal unsanitized" ;;
esac
rm -f "$sub8/$esc_name"
echo "ok: an embedded escape sequence is stripped before echo"

# ---------------------------------------------------------------------------
# 11. REQ-D1.5 — containment on the SURFACE DIRECTORY itself: a surface-root
#     symlink cannot redirect the surface, and the redirect target is never
#     written through.
# ---------------------------------------------------------------------------
h11="$tmp/h11"
mkdir -p "$h11"
elsewhere="$tmp/elsewhere"
mkdir -p "$elsewhere"
chmod 700 "$elsewhere"
ln -s "$elsewhere" "$h11/presence"
rc=0
run_fp "$h11" publish --checkout "$co" --session-id "$uuid_self" --pid $$ \
  >/dev/null 2>"$tmp/err11" || rc=$?
[ "$rc" = 4 ] || fail "a surface-root symlink was not refused (exit $rc, expected 4)"
grep -qi "symlink" "$tmp/err11" \
  || fail "the surface-root symlink refusal did not name the symlink: $(cat "$tmp/err11")"
[ -z "$(find "$elsewhere" -mindepth 1 -print -quit)" ] \
  || fail "the surface-root symlink target was written through"

# ... and in the DANGLING state too. `docs/fleet.md` promises a symlink-tampered
# surface is refused "in any state" (exit 4), and the sibling sentinel check
# already spells out why: a dangling link is the sharper case, since the write
# would CREATE the attacker-chosen target rather than merely reach an existing
# one. The mode read cannot reach this state — `-d` is false through a dangling
# link — so without an explicit bar the operator is sent to fix a writability
# problem that was never the problem.
h11b="$tmp/h11b"
mkdir -p "$h11b"
ln -s "$tmp/never-created" "$h11b/presence"
rc=0
run_fp "$h11b" publish --checkout "$co" --session-id "$uuid_self" --pid $$ \
  >/dev/null 2>"$tmp/err11b" || rc=$?
[ "$rc" = 4 ] \
  || fail "a DANGLING surface-root symlink was not refused (exit $rc, expected 4): $(cat "$tmp/err11b")"
grep -qi "symlink" "$tmp/err11b" \
  || fail "the dangling surface-root symlink refusal did not name the symlink: $(cat "$tmp/err11b")"
[ ! -e "$tmp/never-created" ] \
  || fail "the dangling surface-root symlink target was created through the redirect"
echo "ok: a surface-root symlink is refused in both states, its target never written through"

# ---------------------------------------------------------------------------
# 12. REQ-D1.5 — the fence-ref name: spec id and unit id validated, the
#     assembled name confirmed inside refs/planwright-fence/<spec>/.
# ---------------------------------------------------------------------------
ref=$(/bin/sh "$stubbin/fleet-fence.sh" refname --spec demo-spec 4) \
  || fail "a well-formed fence refname was refused"
[ "$ref" = "refs/planwright-fence/demo-spec/4" ] \
  || fail "fence refname is not the namespaced name (got: $ref)"
for bad_spec in "../../heads" "demo spec" "-demo" "demo/spec" ".."; do
  rc=0
  /bin/sh "$stubbin/fleet-fence.sh" refname --spec "$bad_spec" 4 >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "hostile spec id '$bad_spec' not refused (exit $rc)"
done
for bad_unit in "../../../heads/main" "4;rm -rf /" "4 5" "-4" "" ".."; do
  rc=0
  /bin/sh "$stubbin/fleet-fence.sh" refname --spec demo-spec "$bad_unit" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "hostile unit id '$bad_unit' not refused (exit $rc)"
done
echo "ok: fence refname refuses hostile spec/unit ids and stays inside its namespace"

# ---------------------------------------------------------------------------
# 13. REQ-D1.5 — the unit id and spec id are validated BEFORE any origin ref
#     push or delete: a hostile id never reaches `git push`. Proven with a git
#     stub that logs every invocation.
# ---------------------------------------------------------------------------
gitstub="$tmp/gitstub"
mkdir -p "$gitstub"
cat >"$gitstub/git" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/git-calls"
exit 0
EOF
chmod +x "$gitstub/git"
for bad in "../../../heads/main" "4;rm -rf /" "-4"; do
  for sub in fence gc; do
    : >"$tmp/git-calls"
    rc=0
    PATH="$gitstub:$PATH" /bin/sh "$stubbin/fleet-fence.sh" "$sub" --checkout "$co" \
      --spec demo-spec "$bad" >/dev/null 2>&1 || rc=$?
    [ "$rc" = 2 ] || fail "hostile unit id '$bad' not refused by $sub (exit $rc)"
    grep -q "push" "$tmp/git-calls" \
      && fail "hostile unit id '$bad' reached a git push on the $sub path"
  done
done
: >"$tmp/git-calls"
rc=0
PATH="$gitstub:$PATH" /bin/sh "$stubbin/fleet-fence.sh" gc --checkout "$co" \
  --spec "../../heads" 4 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "hostile spec id not refused by gc (exit $rc)"
grep -q "push" "$tmp/git-calls" && fail "a hostile spec id reached a git push"
echo "ok: hostile unit/spec ids are refused before any origin ref push or delete"

# ---------------------------------------------------------------------------
# 14. REQ-D1.5 — data-not-code: peer records are never evaluated, and
#     pathname expansion is off on both coordination scripts.
# ---------------------------------------------------------------------------
for src in "$FP" "$FF"; do
  # Comments are stripped first: both files DOCUMENT the no-eval discipline,
  # and a guard that trips on its own rationale teaches nothing.
  sed 's/#.*//' "$src" | grep -Eq '(^|[^[:alnum:]_-])eval[[:space:]]' \
    && fail "$(basename "$src") has an eval path over peer data"
  grep -q '^set -uf' "$src" \
    || fail "$(basename "$src") does not disable pathname expansion (set -f)"
done
echo "ok: no eval path; pathname expansion disabled on both coordination scripts"

# ---------------------------------------------------------------------------
# 15. REQ-D1.1 / REQ-D1.2 — cross-reference wiring: the seams to the three
#     adjacent owners are legible and RESOLVE to real bundles, the relay is
#     consumed positively (its entry point is named and it exists), and no
#     relay or usage-governance mechanism is re-implemented here.
# ---------------------------------------------------------------------------
floor="$root/doctrine/fleet-coordination-floor.md"
[ -f "$floor" ] || fail "doctrine/fleet-coordination-floor.md missing"
for bundle in orchestration-concurrency orchestration-fleet fleet-autonomy; do
  grep -q "$bundle" "$floor" || fail "the coordination floor does not name $bundle"
  [ -f "$root/specs/$bundle/requirements.md" ] \
    || fail "cross-reference to $bundle does not resolve to a spec bundle"
done

# Positive: the relay is CONSUMED — the floor names orchestration-fleet's relay
# entry point, and that entry point exists and runs. Absence of a local send
# path alone would not show this (REQ-D1.1, REQ-D1.2).
grep -q 'scripts/orchestrate-relay.sh' "$floor" \
  || fail "the coordination floor does not name the relay entry point it consumes"
[ -x "$root/scripts/orchestrate-relay.sh" ] \
  || fail "the named relay entry point does not resolve to an executable script"
/bin/sh "$root/scripts/orchestrate-relay.sh" validate-handle tmux "planwright:worker-1" \
  >/dev/null 2>&1 \
  || fail "the named relay entry point does not answer its validate-handle contract"

# Negative: no forked relay and no usage/quota governance in this bundle's
# scripts (REQ-D1.1, REQ-D1.2).
for src in "$FP" "$FF"; do
  grep -q 'send-keys' "$src" && fail "$(basename "$src") has a local send path (relay must be consumed)"
  grep -Eq '(^|[^[:alnum:]_-])/usage|quota' "$src" \
    && fail "$(basename "$src") implements usage/quota governance (fleet-autonomy owns it)"
done
echo "ok: cross-references resolve; the relay is positively consumed, never forked"

echo "PASS: coordination-artifact hygiene guard + framework-script security bars"
