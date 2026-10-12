#!/bin/bash
# Tests for scripts/fleet-messaging.sh, the messaging transport's one
# enforcement point (doctrine/messaging-transport.md), and the
# `fleet-attention.sh render --worker` arity its notice-read delegates to.
#
# Covered: the probe's four conjuncts and their negatives (REQ-A1.1, REQ-F1.2),
# rung eligibility (REQ-A1.6), the discipline oracle's directions and pressure
# demotion (REQ-F1.7, REQ-F1.4), send's preconditions, frame, and outcomes
# through the post seam (REQ-A1.6, REQ-C1.5, REQ-F1.6, REQ-H1.3), notice-read's
# screen and store re-read (REQ-D1.7, REQ-H1.4), self-name and self-register
# (REQ-B1.2), the seam guard (REQ-H1.5), echo sanitization (REQ-H1.2), and the
# literal source audit (REQ-H1.3, REQ-D1.9).
#
# Hermetic: the fleet home, the config layers, HOME, and the working directory
# are all fixtures, and no case binds a real socket: socket-ness comes from the
# --socket-type seam. Runs standalone under /bin/bash (bash 3.2).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
FM="$root/scripts/fleet-messaging.sh"
FA="$root/scripts/fleet-attention.sh"
AUDIT="$root/scripts/fleet-audit.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
ok() { echo "ok: $1"; }

[ -x "$FM" ] || fail "scripts/fleet-messaging.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
esc=$(printf '\033')

home="$tmp/home"
proj="$tmp/proj"
fleet="$tmp/fleet"
socks="$tmp/socks"
adopter="$tmp/adopter"
repo="$tmp/repo"
core_cfg="$tmp/core-defaults.yml"
mkdir -p "$home/.claude/sessions" "$proj/.claude" "$fleet" "$socks" "$adopter" "$repo/.claude"
cp "$root/config/defaults.yml" "$core_cfg"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$repo"
own_sock="$socks/tower.sock"
: >"$own_sock"
me_uid=$(id -u)
other_uid=$((me_uid + 1))
postlog="$tmp/post.log"
seam_out="$tmp/seam.out"
seam_rc="$tmp/seam.rc"
seam="$tmp/post-seam"
cat >"$seam" <<'EOF'
#!/bin/sh
{
  printf 'CALL'
  for a in "$@"; do printf ' %s' "$a"; done
  printf '\n'
  cat
  printf 'END\n'
} >>"$PLANWRIGHT_MESSAGING_POST_LOG"
out=$(cat "$SEAM_OUT_FILE")
[ -z "$out" ] || printf '%s\n' "$out"
exit "$(cat "$SEAM_RC_FILE")"
EOF
chmod +x "$seam"

# fm [--nosock] [VAR=value ...] -- <args> — run the script against the
# fixtures: the user layer under $home, the project and local layers under
# $proj (the working directory), and the config overlay under $repo.
fm() {
  fm_sock=1
  if [ "${1:-}" = --nosock ]; then
    fm_sock=0
    shift
  fi
  fm_env=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
    fm_env+=("$1")
    shift
  done
  shift
  fm_base=(HOME="$home" PLANWRIGHT_FLEET_STATE_DIR="$fleet" CLAUDE_PLUGIN_DATA="$tmp/plugin-data"
    CLAUDE_DIR="$tmp/claude-dir" PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg"
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG=""
    PLANWRIGHT_TEST_SEAM=1 PLANWRIGHT_MESSAGING_POST_LOG="$postlog"
    SEAM_OUT_FILE="$seam_out" SEAM_RC_FILE="$seam_rc")
  [ "$fm_sock" = 0 ] || fm_base+=(CLAUDE_CODE_MESSAGING_SOCKET="$own_sock")
  (cd "$proj" && env -u CLAUDE_CONFIG_DIR -u CLAUDE_CODE_MESSAGING_SOCKET -u PLANWRIGHT_MESSAGING_INBOUND \
    -u PLANWRIGHT_MESSAGING_POST -u CLAUDE_PID -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    -u CLAUDE_PLUGIN_ROOT -u PLANWRIGHT_ROOT \
    "${fm_base[@]}" ${fm_env[@]+"${fm_env[@]}"} /bin/sh "$FM" "$@")
}

user_set() { printf '%s\n' "$1" >"$home/.claude/settings.json"; }
proj_set() { printf '%s\n' "$1" >"$proj/.claude/settings.json"; }
local_set() { printf '%s\n' "$1" >"$proj/.claude/settings.local.json"; }
clear_settings() { rm -f "$home/.claude/settings.json" "$proj/.claude/settings.json" "$proj/.claude/settings.local.json"; }
knob() { printf 'messaging_discipline: %s\n' "$1" >"$repo/.claude/planwright.yml"; }
clear_knob() { rm -f "$repo/.claude/planwright.yml"; }

# probe_reads <expected> <case> [fm args...] — the probe's stdout.
probe_reads() {
  pr_want=$1
  pr_case=$2
  shift 2
  pr_got=$(fm "$@" 2>/dev/null) || true
  [ "$pr_got" = "$pr_want" ] || fail "probe: $pr_case: expected '$pr_want', got '$pr_got'"
}

AVAIL=(-- probe --cli-version 2.1.248 --socket-type socket)

# ---------------------------------------------------------------------------
# 1. The probe (REQ-A1.1): every conjunct satisfied reads available.
# ---------------------------------------------------------------------------
clear_settings
clear_knob
user_set '{"crossSessionInbound": "accept"}'
probe_reads available "all four conjuncts hold" "${AVAIL[@]}"
ok "probe reads available with the socket, the version, acceptance, and a ladder knob"

# The version compares numerically per dotted component against 2.1.248.
for v in 2.1.248 2.1.250 2.1.1000 2.2.0 3.0.0 2.1.999; do
  probe_reads available "version $v" -- probe --cli-version "$v" --socket-type socket
done
for v in 2.1.247 2.0.248 1.1.248 2.1.224 2.1.x "" 2.1 2.1.248.1 v2.1.300; do
  probe_reads absent "version '$v'" -- probe --cli-version "$v" --socket-type socket
done
ok "probe compares the CLI version numerically per component against 2.1.248"

# The socket conjunct.
probe_reads absent "variable unset" --nosock -- probe --cli-version 2.1.248 --socket-type socket
probe_reads absent "variable empty" --nosock CLAUDE_CODE_MESSAGING_SOCKET= -- probe --cli-version 2.1.248 --socket-type socket
probe_reads absent "variable relative" --nosock CLAUDE_CODE_MESSAGING_SOCKET=rel.sock -- probe --cli-version 2.1.248 --socket-type socket
probe_reads absent "variable malformed" --nosock "CLAUDE_CODE_MESSAGING_SOCKET=$socks/a b.sock" -- probe --cli-version 2.1.248 --socket-type socket
probe_reads absent "path missing" --nosock "CLAUDE_CODE_MESSAGING_SOCKET=$socks/missing.sock" -- probe --cli-version 2.1.248 --socket-type socket
ln -s "$socks/nowhere.sock" "$socks/dangling.sock"
probe_reads absent "path dangling" --nosock "CLAUDE_CODE_MESSAGING_SOCKET=$socks/dangling.sock" -- probe --cli-version 2.1.248 --socket-type socket
probe_reads absent "not a socket" -- probe --cli-version 2.1.248 --socket-type other
probe_reads absent "a regular file without the seam" -- probe --cli-version 2.1.248
probe_reads absent "another uid" -- probe --cli-version 2.1.248 --socket-type socket --owner-uid "$other_uid"
probe_reads available "this uid through the seam" -- probe --cli-version 2.1.248 --socket-type socket --owner-uid "$me_uid"
ok "probe reads absent on every socket negative (unset, empty, malformed, missing, dangling, non-socket, other uid)"

# The acceptance conjunct: real settings files, local over project over user.
clear_settings
probe_reads absent "no value in any layer" "${AVAIL[@]}"
user_set '{"crossSessionInbound":"hold"}'
probe_reads absent "user hold" "${AVAIL[@]}"
user_set '{"crossSessionInbound":"refuse"}'
probe_reads absent "user refuse" "${AVAIL[@]}"
clear_settings
proj_set '{"crossSessionInbound":"refuse"}'
local_set '{"crossSessionInbound":"accept"}'
probe_reads available "local accept over project refuse" "${AVAIL[@]}"
proj_set '{"crossSessionInbound":"accept"}'
local_set '{"crossSessionInbound":"refuse"}'
probe_reads absent "local refuse over project accept" "${AVAIL[@]}"
clear_settings
user_set '{"crossSessionInbound":"refuse"}'
proj_set '{"crossSessionInbound":"accept"}'
probe_reads available "project accept over user refuse" "${AVAIL[@]}"
user_set '{"crossSessionInbound":"accept"}'
proj_set '{"crossSessionInbound":"refuse"}'
probe_reads absent "project refuse over user accept" "${AVAIL[@]}"
clear_settings
probe_reads available "exported accept over an empty tree" PLANWRIGHT_MESSAGING_INBOUND=accept "${AVAIL[@]}"
proj_set '{"crossSessionInbound":"refuse"}'
probe_reads available "exported accept over a project refuse" PLANWRIGHT_MESSAGING_INBOUND=accept "${AVAIL[@]}"
clear_settings
ok "probe reads crossSessionInbound by precedence, the exported layer outranking every file"

# Top-level key only; a parse failure reads absent.
user_set '{"permissions":{"crossSessionInbound":"accept"}}'
probe_reads absent "a nested key is not the setting" "${AVAIL[@]}"
user_set '{"crossSessionInbound": true}'
probe_reads absent "a non-string value" "${AVAIL[@]}"
user_set '{"crossSessionInbound":"accept"'
probe_reads absent "an unterminated object" "${AVAIL[@]}"
user_set '{"crossSessionInbound":"accept"} trailing'
probe_reads absent "trailing garbage" "${AVAIL[@]}"
user_set '["crossSessionInbound","accept"]'
probe_reads absent "a non-object root" "${AVAIL[@]}"
user_set '{"crossSessionInbound":"accept"}'
proj_set '{"model": "x", "broken": }}'
probe_reads absent "an unparseable project layer" "${AVAIL[@]}"
clear_settings
user_set '{
  "env": {"A": "x\"crossSessionInbound\": \"refuse\""},
  "crossSessionInbound" : "accept",
  "hooks": {"SessionStart": [{"crossSessionInbound": "refuse"}]}
}'
probe_reads available "a multi-line object with decoys in strings and nested objects" "${AVAIL[@]}"
ok "probe reads only the top-level string key and reads absent on a parse failure"

# The discipline conjunct: off is the kill switch; the ladder values read
# available; an unknown value reads absent.
for v in script tiered open; do
  knob "$v"
  probe_reads available "knob $v" "${AVAIL[@]}"
done
knob off
probe_reads absent "knob off" "${AVAIL[@]}"
knob loud
probe_reads absent "knob unknown" "${AVAIL[@]}"
{
  printf 'messaging_discipline: open\n'
  printf 'messaging_cross_machine: true\n'
  printf 'messaging_heal_cadence_seconds: 60\n'
} >"$repo/.claude/planwright.yml"
probe_reads absent "all three knobs set, the variable unset" --nosock -- probe --cli-version 2.1.248 --socket-type socket
clear_knob
ok "probe reads absent at off and on an unknown knob, available at script, tiered, and open"

# The parse is awk, never jq or eval.
grep -v '^[[:space:]]*#' "$FM" | grep -qE '(^|[^A-Za-z_])(jq|eval)([[:space:]]|$)' \
  && fail "fleet-messaging.sh invokes jq or eval"
ok "the settings and session-record parses use neither jq nor eval"

# ---------------------------------------------------------------------------
# 2. Eligibility from the Session-grade column (REQ-A1.6).
# ---------------------------------------------------------------------------
adapters="$tmp/adapters"
mkdir -p "$adapters"
mk_adapter() {
  # shellcheck disable=SC2016 # the adapter's own $1, not this shell's
  printf '#!/bin/sh\n[ "$1" = advertise ] && printf "%%s\\n" "%s"\n' "$2" >"$adapters/planwright-backend-$1"
  chmod +x "$adapters/planwright-backend-$1"
}
mk_adapter goodrung 'true true true false true yes full-session true both'
mk_adapter norung 'true true true false true no full-session true both'
mk_adapter oddrung 'true true true false true maybe full-session true both'
mk_adapter brokenrung 'true true'
elig() { PATH="$adapters:$PATH" fm -- eligible "$@"; }
for r in tmux stream-json-persistent headless-oneshot goodrung; do
  got=$(elig "$r" --launch normal) || fail "eligible: $r normal exited non-zero"
  [ "$got" = eligible ] || fail "eligible: $r normal read '$got'"
done
for r in tmux goodrung; do
  got=$(elig "$r" --launch bare) && fail "eligible: $r bare exited zero"
  [ "$got" = ineligible ] || fail "eligible: $r bare read '$got'"
done
for r in subagent in-session print norung oddrung brokenrung; do
  got=$(elig "$r" --launch normal 2>/dev/null) && fail "eligible: $r exited zero"
  [ "$got" = ineligible ] || fail "eligible: $r read '$got'"
done
rc=0
elig nosuchrung --launch normal >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "eligible: an unknown rung was not refused (exit $rc)"
rc=0
elig tmux >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "eligible: a missing --launch was not refused (exit $rc)"
rc=0
elig tmux --launch sometimes >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "eligible: a --launch outside the pair was not refused (exit $rc)"
grep -q 'orchestrate-backends.sh' "$FM" || fail "eligible does not read orchestrate-backends.sh caps"
ok "eligible maps yes+normal to eligible and no, deferred, unknown, malformed, and --bare to ineligible"

# ---------------------------------------------------------------------------
# 3. The discipline oracle (REQ-F1.7, REQ-F1.2, REQ-F1.4).
# ---------------------------------------------------------------------------
em() { fm -- effective-mode --direction "$1"; }
expect_mode() {
  knob "$1"
  for d in worker-to-tower tower-to-worker tower-to-tower; do
    case $d in
      worker-to-tower) want=$2 ;;
      tower-to-worker) want=$3 ;;
      tower-to-tower) want=$4 ;;
    esac
    errf="$tmp/em.err"
    got=$(em "$d" 2>"$errf") || fail "effective-mode: knob $1 $d exited non-zero"
    [ "$got" = "$want" ] || fail "effective-mode: knob $1 $d: expected $want, got $got"
    if [ "$5" = demoted ] && [ "$want" != "$6" ]; then
      :
    fi
    lines=$(grep -c . "$errf" || true)
    case $5 in
      quiet) [ "$lines" = 0 ] || fail "effective-mode: knob $1 $d wrote a notice without pressure" ;;
    esac
  done
}
expect_mode script script script script quiet
expect_mode tiered tiered script tiered quiet
expect_mode open open tiered open quiet
ok "effective-mode resolves each direction at the knob, tower-to-worker one stricter, saturating at script"

rc=0
fm -- effective-mode >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "effective-mode: a missing --direction was not refused"
rc=0
fm -- effective-mode --direction sideways >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "effective-mode: a fourth direction was not refused"
knob off
rc=0
err=$(fm -- effective-mode --direction worker-to-tower 2>&1 >/dev/null) || rc=$?
[ "$rc" = 3 ] || fail "effective-mode: off was not refused (exit $rc)"
case $err in
  *"outside the ladder"*) ;;
  *) fail "effective-mode: the off refusal does not name it the switch value outside the ladder" ;;
esac
knob loud
rc=0
fm -- effective-mode --direction worker-to-tower >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "effective-mode: an unknown knob value resolved"
clear_knob
ok "effective-mode refuses a missing or fourth direction, off (outside the ladder), and an unknown knob"

# Send-time pressure demotion reads the usage gate's rung and nothing else.
audit_env() {
  env -u CLAUDE_PLUGIN_ROOT -u PLANWRIGHT_ROOT HOME="$home" PLANWRIGHT_FLEET_STATE_DIR="$fleet" \
    CLAUDE_PLUGIN_DATA="$tmp/plugin-data" CLAUDE_DIR="$tmp/claude-dir" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" /bin/sh "$AUDIT" "$@"
}
set_rung() { audit_env record usage-gate "$1" test-fixture "pressure fixture" >/dev/null 2>&1 || fail "could not record usage-gate rung $1"; }
pressure_case() {
  # pressure_case <knob> <direction> <want> <notices>
  knob "$1"
  errf="$tmp/em.err"
  got=$(em "$2" 2>"$errf") || fail "effective-mode under pressure: $1 $2 exited non-zero"
  [ "$got" = "$3" ] || fail "effective-mode under pressure: $1 $2: expected $3, got $got"
  lines=$(grep -c . "$errf" || true)
  [ "$lines" = "$4" ] || fail "effective-mode under pressure: $1 $2: expected $4 notice(s), got $lines"
}
set_rung downshift
pressure_case open tower-to-worker tiered 0
pressure_case tiered worker-to-tower tiered 0
listing_before=$(cd "$fleet" && find . -path ./usage -prune -o -print | LC_ALL=C sort)
set_rung reduce-concurrency
listing_before=$(cd "$fleet" && find . -path ./usage -prune -o -print | LC_ALL=C sort)
sums_before=$(cd "$fleet" && find . -path ./usage -prune -o -type f -print | LC_ALL=C sort | xargs cksum)
pressure_case open worker-to-tower tiered 1
pressure_case open tower-to-tower tiered 1
pressure_case open tower-to-worker script 1
pressure_case tiered worker-to-tower script 1
pressure_case tiered tower-to-worker script 0
pressure_case script tower-to-tower script 0
set_rung defer-all
listing_before=$(cd "$fleet" && find . -path ./usage -prune -o -print | LC_ALL=C sort)
sums_before=$(cd "$fleet" && find . -path ./usage -prune -o -type f -print | LC_ALL=C sort | xargs cksum)
for k in script tiered open; do
  for d in worker-to-tower tower-to-worker tower-to-tower; do
    knob "$k"
    em "$d" >/dev/null 2>&1 || fail "effective-mode: $k $d under defer-all exited non-zero"
  done
done
listing_after=$(cd "$fleet" && find . -path ./usage -prune -o -print | LC_ALL=C sort)
sums_after=$(cd "$fleet" && find . -path ./usage -prune -o -type f -print | LC_ALL=C sort | xargs cksum)
[ "$listing_before" = "$listing_after" ] || fail "effective-mode changed the fleet state directory listing"
[ "$sums_before" = "$sums_after" ] || fail "effective-mode wrote into the fleet state directory"
set_rung normal
pressure_case open tower-to-tower open 0
# A trail the gate refuses to read is never no pressure.
set_rung not-a-rung
rc=0
got=$(em worker-to-tower 2>"$tmp/em.err") || rc=$?
[ "$rc" = 4 ] || fail "effective-mode: an unreadable usage-gate rung was not refused (exit $rc, printed '$got')"
grep -q 'usage gate' "$tmp/em.err" || fail "effective-mode: the unreadable-rung refusal does not name the usage gate"
set_rung normal
clear_knob
grep -q 'context-budget' "$FM" && fail "effective-mode consults the context-budget monitor"
ok "pressure at or above reduce-concurrency demotes one value with one notice; nothing is stored"

# ---------------------------------------------------------------------------
# 4. send (REQ-A1.6, REQ-C1.5, REQ-F1.6, REQ-H1.3, REQ-H1.5).
# ---------------------------------------------------------------------------
user_set '{"crossSessionInbound":"accept"}'
reg="$fleet/registry"
row9() { printf '%s\t%s\tspec:1\t-\ttmux\t-\tnone\t%s\t%s\n' "$1" "$2" "$3" "$4"; }
{
  row9 100 w1 "fleet-w1" w1.sock
  row9 101 w-nobox "fleet-nobox" -
  printf '102\tw-seven\tspec:1\t-\ttmux\t-\tnone\n'
  printf '103\tw-three\tspec:1\n'
  row9 104 w-last "fleet-last-old" old.sock
  row9 105 w-last "fleet-last" new.sock
  row9 106 w-gone "fleet-gone" gone.sock
  printf '107\tw-gone\tspec:1\t-\ttmux\t-\tnone\tfleet-gone\tgone.sock\tclosed\n'
  row9 108 w-missing "fleet-missing" missing.sock
} >"$reg"
for s in w1 old new gone; do : >"$socks/$s.sock"; done
msg="$tmp/msg.txt"
printf 'Use option "b"; path C:\\tmp\n\tsecond line \033\n' >"$msg"
reset_post() {
  : >"$postlog"
  : >"$seam_out"
  echo 0 >"$seam_rc"
}
calls() { grep -c '^CALL' "$postlog" || true; }
SEND_SEAMS=(--cli-version 2.1.259 --socket-type socket)
send_w() { fm PLANWRIGHT_MESSAGING_POST="$seam" -- send --to-worker "$1" --message-file "$msg" "${SEND_SEAMS[@]}"; }

reset_post
id=$(send_w w1) || fail "send --to-worker w1 failed"
printf '%s\n' "$id" | grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' \
  || fail "send did not print a UUID message id (got '$id')"
[ "$(calls)" = 1 ] || fail "send --to-worker did not post exactly once"
grep -q "^CALL nc -N -w 5 -U $socks/w1.sock\$" "$postlog" || fail "send did not resolve the inbox basename against its own socket directory"
frame=$(sed -n '2p' "$postlog")
want_frame='{"type":"user","message":{"role":"user","content":"Use option \"b\"; path C:\\tmp\n\tsecond line \u001b"},"from":"uds:'"$own_sock"'","msg_id":"'"$id"'"}'
[ "$frame" = "$want_frame" ] || fail "send framed the message wrongly:
got:  $frame
want: $want_frame"
grep -q '"auth"' "$postlog" && fail "send posted an auth line"
grep '^CALL' "$postlog" | grep -q 'option' && fail "the message body reached the post's argv"
ok "send --to-worker posts the body as data to the registry inbox, framed with a minted id and its own reply address, no auth line"

reset_post
id2=$(send_w w1) || fail "second send failed"
[ "$id2" != "$id" ] || fail "send reused a message id"
reset_post
fm PLANWRIGHT_MESSAGING_POST="$seam" -- send --to "$socks/w1.sock" --message-file "$msg" "${SEND_SEAMS[@]}" >/dev/null \
  || fail "send --to <path> failed"
[ "$(calls)" = 1 ] || fail "send --to did not post"
ok "send mints a fresh id per post and still accepts --to <socket path>"

refuse_case() {
  # refuse_case <label> <expected-exit> <fm args...>
  rc_label=$1
  rc_want=$2
  shift 2
  reset_post
  rc=0
  fm "$@" >/dev/null 2>&1 || rc=$?
  [ "$rc" = "$rc_want" ] || fail "send: $rc_label: expected exit $rc_want, got $rc"
  [ "$(calls)" = 0 ] || fail "send: $rc_label: reached the post seam"
}
P=(PLANWRIGHT_MESSAGING_POST="$seam" --)
refuse_case "no registry row" 6 "${P[@]}" send --to-worker w-none --message-file "$msg" "${SEND_SEAMS[@]}"
refuse_case "inbox sentinel" 6 "${P[@]}" send --to-worker w-nobox --message-file "$msg" "${SEND_SEAMS[@]}"
refuse_case "seven-column row" 6 "${P[@]}" send --to-worker w-seven --message-file "$msg" "${SEND_SEAMS[@]}"
refuse_case "three-column row" 6 "${P[@]}" send --to-worker w-three --message-file "$msg" "${SEND_SEAMS[@]}"
refuse_case "retired row" 6 "${P[@]}" send --to-worker w-gone --message-file "$msg" "${SEND_SEAMS[@]}"
refuse_case "probe absent, basename recorded" 6 "${P[@]}" send --to-worker w1 --message-file "$msg" --cli-version 2.1.247 --socket-type socket
refuse_case "probe available, target fails the predicate" 6 "${P[@]}" send --to-worker w-missing --message-file "$msg" "${SEND_SEAMS[@]}"
refuse_case "target owned by another uid" 6 "${P[@]}" send --to "$socks/w1.sock" --message-file "$msg" --cli-version 2.1.259 --socket-type socket --owner-uid "$other_uid"
refuse_case "target not a socket" 6 "${P[@]}" send --to "$socks/w1.sock" --message-file "$msg" --cli-version 2.1.259 --socket-type other
refuse_case "host-qualified target" 2 "${P[@]}" send --to "otherhost:$socks/w1.sock" --message-file "$msg" "${SEND_SEAMS[@]}"
refuse_case "URL-shaped target" 2 "${P[@]}" send --to "uds://$socks/w1.sock" --message-file "$msg" "${SEND_SEAMS[@]}"
refuse_case "relative target" 2 "${P[@]}" send --to "w1.sock" --message-file "$msg" "${SEND_SEAMS[@]}"
refuse_case "hostile worker handle" 2 "${P[@]}" send --to-worker 'w1/../x' --message-file "$msg" "${SEND_SEAMS[@]}"
refuse_case "missing message file" 2 "${P[@]}" send --to-worker w1 --message-file "$tmp/nope" "${SEND_SEAMS[@]}"
: >"$tmp/empty.txt"
refuse_case "empty message file" 2 "${P[@]}" send --to-worker w1 --message-file "$tmp/empty.txt" "${SEND_SEAMS[@]}"
knob off
refuse_case "kill switch off" 6 "${P[@]}" send --to-worker w1 --message-file "$msg" "${SEND_SEAMS[@]}"
clear_knob
ok "send refuses with an empty post log on every unmet precondition and grammar failure"

reset_post
id=$(send_w w-last) || fail "send to w-last failed"
grep -q "^CALL nc -N -w 5 -U $socks/new.sock\$" "$postlog" || fail "send did not bind the worker's last registry record"
ok "send binds the worker's last registry record"

# The four post outcomes (REQ-C1.5).
outcome_case() {
  # outcome_case <seam line> <seam rc> <want exit> <want id on stdout: y|n> <want stderr lines>
  reset_post
  printf '%s' "$1" >"$seam_out"
  echo "$2" >"$seam_rc"
  rc=0
  out=$(send_w w1 2>"$tmp/out.err") || rc=$?
  [ "$rc" = "$3" ] || fail "outcome '$1'/$2: expected exit $3, got $rc"
  [ "$(calls)" = 1 ] || fail "outcome '$1'/$2: expected one post"
  case $4 in
    y) [ -n "$out" ] || fail "outcome '$1'/$2: no id printed" ;;
    n) [ -z "$out" ] || fail "outcome '$1'/$2: printed an id for an unwritten post" ;;
  esac
  lines=$(grep -c . "$tmp/out.err" || true)
  [ "$lines" = "$5" ] || fail "outcome '$1'/$2: expected $5 stderr line(s), got $lines"
}
outcome_case accepted 0 0 y 0
outcome_case "" 0 0 y 0
outcome_case held 0 5 y 1
outcome_case refused 0 3 n 1
outcome_case "" 1 4 n 1
outcome_case "${esc}[31mbogus" 0 4 n 1
grep -q "$esc" "$tmp/out.err" && fail "the unknown-outcome diagnostic echoed a raw escape byte"
ok "accepted, held, refused, and a failed post each take their branch; an empty response with a clean write is accepted"

# The seam guard (REQ-H1.5).
seam_refused() {
  sr_label=$1
  shift
  reset_post
  rc=0
  err=$(fm PLANWRIGHT_TEST_SEAM=0 "$@" 2>&1 >/dev/null) || rc=$?
  [ "$rc" = 2 ] || fail "seam guard: $sr_label: expected exit 2, got $rc"
  case $err in
    *PLANWRIGHT_TEST_SEAM=1*) ;;
    *) fail "seam guard: $sr_label: the diagnostic does not name the guard" ;;
  esac
  case $err in
    *"$sr_label"*) ;;
    *) fail "seam guard: $sr_label: the diagnostic does not name the seam" ;;
  esac
  [ "$(calls)" = 0 ] || fail "seam guard: $sr_label: reached the post seam"
}
seam_refused --cli-version -- probe --cli-version 2.1.259
seam_refused --owner-uid -- probe --owner-uid "$me_uid"
seam_refused --socket-type -- probe --socket-type socket
seam_refused PLANWRIGHT_MESSAGING_POST PLANWRIGHT_MESSAGING_POST="$seam" -- send --to-worker w1 --message-file "$msg"
probe_reads available "--cli-version honored" -- probe --cli-version 2.1.259 --socket-type socket
probe_reads absent "--cli-version honored low" -- probe --cli-version 2.1.200 --socket-type socket
probe_reads absent "--owner-uid honored" -- probe --cli-version 2.1.259 --socket-type socket --owner-uid "$other_uid"
fm -- socket-ok "$socks/w1.sock" --socket-type socket || fail "socket-ok: the --socket-type seam was not honored"
fm -- socket-ok "$socks/w1.sock" && fail "socket-ok: a regular file passed without the seam"
fm -- socket-ok "$socks/w1.sock" --socket-type socket --owner-uid "$other_uid" && fail "socket-ok: the --owner-uid seam was not honored"
reset_post
send_w w1 >/dev/null || fail "the post seam was not honored with the guard set"
[ "$(calls)" = 1 ] || fail "the post seam was not honored with the guard set"
ok "every seam is refused without PLANWRIGHT_TEST_SEAM=1 and honored with it"

# ---------------------------------------------------------------------------
# 5. render --worker and notice-read (REQ-D1.7, REQ-H1.4).
# ---------------------------------------------------------------------------
fa() {
  env -u CLAUDE_PLUGIN_ROOT -u PLANWRIGHT_ROOT HOME="$home" PLANWRIGHT_FLEET_STATE_DIR="$fleet" \
    CLAUDE_PLUGIN_DATA="$tmp/plugin-data" CLAUDE_DIR="$tmp/claude-dir" /bin/sh "$FA" "$@"
}
fa heartbeat w1 spec:1 working || fail "heartbeat w1"
fa heartbeat w-last spec:2 idle || fail "heartbeat w-last"
fa park w-nobox spec:3 "notification:${esc}]0;owned${esc}\\ waiting" 2>/dev/null || :
got=$(fa render --worker w1) || fail "render --worker w1 failed"
case $got in
  *"] spec:1  w1  ("*) ;;
  *) fail "render --worker w1 did not return w1's row (got '$got')" ;;
esac
[ "$(printf '%s\n' "$got" | grep -c .)" = 1 ] || fail "render --worker returned more than the named row"
got=$(fa render --worker w-unknown) || fail "render --worker for an absent worker failed"
[ -z "$got" ] || fail "render --worker for an absent worker printed a row"
rc=0
fa render --worker 'w1;rm' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "render --worker accepted a malformed handle"
rc=0
fa render --worker w1 --on-change pkey.t1 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "render --worker combined with --on-change"
ok "fleet-attention.sh render --worker returns the named worker's row and no other"

got=$(fm -- notice-read fleet-w1) || fail "notice-read fleet-w1 failed"
want=$(fa render --worker w1)
[ "$got" = "$want" ] || fail "notice-read did not return the store row for the named worker"
case $got in
  *w-last*) fail "notice-read returned another worker's row" ;;
esac
ok "notice-read matches the registry name column and returns only that worker's store row"

# A name matching one row whose worker has no attention row: empty, a no-op.
row9 109 w-quiet "fleet-quiet" quiet.sock >>"$reg"
got=$(fm -- notice-read fleet-quiet) || fail "notice-read on a store-less worker exited non-zero"
[ -z "$got" ] || fail "notice-read on a store-less worker printed something"
ok "notice-read on a named worker with no store row prints nothing"

hostile_name() {
  hn_label=$1
  shift
  rc=0
  out=$(fm -- notice-read "$1" 2>"$tmp/nr.err") || rc=$?
  [ "$rc" = 2 ] || fail "notice-read: $hn_label: expected exit 2, got $rc"
  [ -z "$out" ] || fail "notice-read: $hn_label: read a store row"
  LC_ALL=C grep -q "[$(printf '\001-\010\013-\037\177')]" "$tmp/nr.err" \
    && fail "notice-read: $hn_label: the diagnostic carries a control byte"
  return 0
}
hostile_name "control bytes" "fleet-w1${esc}[2J"
hostile_name "over-length" "$(printf 'n%.0s' $(seq 1 129))"
hostile_name "path separator" "fleet/w1"
hostile_name "no matching row" "fleet-nobody"
hostile_name "accepted by validate-handle, refused by the screen" "sess:win/x"
"$root/scripts/orchestrate-relay.sh" validate-handle tmux "sess:win/x" \
  || fail "fixture drift: validate-handle no longer accepts the name this case relies on"
row9 110 w-twin-a "fleet-twin" a.sock >>"$reg"
row9 111 w-twin-b "fleet-twin" b.sock >>"$reg"
hostile_name "ambiguous name" "fleet-twin"
# The `-` sentinel a row carries before its session registers is no name.
row9 113 w-unnamed - - >>"$reg"
fa heartbeat w-unnamed spec:4 working || fail "heartbeat w-unnamed"
hostile_name "the unregistered-name sentinel" "-"
long_ok=$(printf 'n%.0s' $(seq 1 128))
rc=0
fm -- notice-read "$long_ok" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "notice-read: a 128-byte unmatched name exited $rc"
ok "notice-read refuses control bytes, over-length, separators, no match, and ambiguity, reading no store row"

# Echo sanitization (REQ-H1.2) over the four message-derived outputs.
clean() { ! LC_ALL=C grep -q "[$(printf '\001-\010\013-\037\177')]" "$1"; }
fm -- notice-read "evil${esc}]0;x${esc}\\" >/dev/null 2>"$tmp/s1" || :
clean "$tmp/s1" || fail "sanitize: the notice-read refusal diagnostic"
reset_post
printf 'held' >"$seam_out"
send_w w1 >/dev/null 2>"$tmp/s2" || :
clean "$tmp/s2" || fail "sanitize: the held notice"
set_rung defer-heavy
knob open
em worker-to-tower >/dev/null 2>"$tmp/s3"
clean "$tmp/s3" || fail "sanitize: the demotion notice"
rc=0
fm -- send "flag${esc}]0;x${esc}\\" >/dev/null 2>"$tmp/s5" || rc=$?
[ "$rc" = 2 ] || fail "send: a lone unknown flag was not refused (exit $rc)"
clean "$tmp/s5" || fail "sanitize: send's diagnostic for a lone unknown flag"
grep -q 'unknown flag' "$tmp/s5" || fail "send: a lone unknown flag was not reported as unknown"
set_rung normal
clear_knob
row9 112 w-dirty "fleet-dirty" dirty.sock >>"$reg"
printf 'w-dirty\tspec:9%s[31m\tworking\t1\t\t\t\t\n' "$esc" >>"$fleet/attention/state"
fm -- notice-read fleet-dirty >"$tmp/s4" 2>/dev/null || fail "notice-read over a dirty store row failed"
grep -q 'w-dirty' "$tmp/s4" || fail "notice-read over a dirty store row printed nothing"
clean "$tmp/s4" || fail "sanitize: notice-read's own output"
# Closure: every printf/echo site naming a message-derived field sanitizes it.
# shellcheck disable=SC2016 # a literal pattern over the script's source
unsanitized=$(grep -nE '(printf|echo).*\$\{?md_' "$FM" | grep -v 'sanitize_printable "\$md_' || true)
[ -z "$unsanitized" ] || fail "an echo site interpolates a message-derived field unsanitized: $unsanitized"
ok "the four message-derived outputs are sanitized and no other echo site interpolates one"

# ---------------------------------------------------------------------------
# 6. self-name and self-register (REQ-B1.2).
# ---------------------------------------------------------------------------
sessions="$home/.claude/sessions"
record() {
  # record <pid> <name> <socket path>
  printf '{"pid":%s,"sessionId":"00000000-0000-4000-8000-000000000000","cwd":"/work","startedAt":1,"procStart":"1","version":"2.1.296","peerProtocol":1,"peerFeatures":["notify_idle"],"kind":"interactive","entrypoint":"cli","pidDomain":"linux:x","messagingSocketPath":"%s","name":"%s","nameSource":"derived","nameSince":1,"status":"idle","updatedAt":1,"statusUpdatedAt":1}\n' "$1" "$3" "$2" >"$sessions/$1.json"
}
record 4242 "fleet-w1 task" "/run/user/1000/cc-socks/4242.sock"
got=$(fm CLAUDE_PID=4242 -- self-name) || fail "self-name failed on a fixture record"
[ "$got" = "fleet-w1 task" ] || fail "self-name printed '$got'"
rc=0
fm CLAUDE_PID=4243 -- self-name >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "self-name succeeded with no record"
printf '{"pid":4244,"messagingSocketPath":"/run/x.sock"}\n' >"$sessions/4244.json"
rc=0
fm CLAUDE_PID=4244 -- self-name >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "self-name succeeded on a record with no name"
rc=0
fm -- self-name >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "self-name succeeded with CLAUDE_PID unset"
ok "self-name prints the record's name and exits non-zero when the record or its name is absent"

# self-register's amend is captured by a recorder beside a copy of the script:
# the script reaches its siblings by its own directory, never by PATH.
srbin="$tmp/srbin"
mkdir -p "$srbin"
cp "$FM" "$root/scripts/echo-safety.sh" "$srbin/"
amendlog="$tmp/amend.log"
printf '#!/bin/sh\nprintf "%%s|" "$@" >>"%s"\nprintf "\\n" >>"%s"\n' "$amendlog" "$amendlog" >"$srbin/fleet-state.sh"
chmod +x "$srbin/fleet-state.sh" "$srbin/fleet-messaging.sh"
sreg() {
  : >"$amendlog"
  (cd "$proj" && env -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE -u CLAUDE_PID -u CLAUDE_CONFIG_DIR \
    HOME="$home" "$@" /bin/sh "$srbin/fleet-messaging.sh" self-register)
}
sreg PLANWRIGHT_WORKER_HANDLE=w1 PLANWRIGHT_WORKER_SCOPE=spec:1 CLAUDE_PID=4242 2>"$tmp/sr.err" \
  || fail "self-register failed on a fixture record"
[ "$(cat "$amendlog")" = "amend|w1|--name|fleet-w1 task|--inbox|4242.sock|" ] \
  || fail "self-register emitted '$(cat "$amendlog")'"
[ ! -s "$tmp/sr.err" ] || fail "self-register wrote to stderr on success"
record 4245 "fleet/evil" "/run/user/1000/cc-socks/4245.sock"
rc=0
sreg PLANWRIGHT_WORKER_HANDLE=w1 PLANWRIGHT_WORKER_SCOPE=spec:1 CLAUDE_PID=4245 2>/dev/null || rc=$?
[ "$rc" != 0 ] || fail "self-register accepted a name failing the screen"
[ ! -s "$amendlog" ] || fail "self-register amended with a name failing the screen"
for pidv in "" 4299; do
  rc=0
  if [ -z "$pidv" ]; then
    sreg PLANWRIGHT_WORKER_HANDLE=w1 PLANWRIGHT_WORKER_SCOPE=spec:1 2>"$tmp/sr.err" || rc=$?
  else
    sreg PLANWRIGHT_WORKER_HANDLE=w1 PLANWRIGHT_WORKER_SCOPE=spec:1 CLAUDE_PID="$pidv" 2>"$tmp/sr.err" || rc=$?
  fi
  [ "$rc" = 0 ] || fail "self-register without a record exited $rc"
  [ "$(grep -c . "$tmp/sr.err")" = 1 ] || fail "self-register without a record did not write exactly one notice"
  [ ! -s "$amendlog" ] || fail "self-register without a record emitted an amend"
done
sreg CLAUDE_PID=4242 2>"$tmp/sr.err" || fail "self-register in a tower session exited non-zero"
[ ! -s "$tmp/sr.err" ] || fail "self-register in a tower session wrote to stderr"
[ ! -s "$amendlog" ] || fail "self-register in a tower session emitted an amend"
ok "self-register amends name and inbox from the record, refuses a bad name, notes a missing record, and is a no-op for a tower"

# ---------------------------------------------------------------------------
# 7. The literal source audit (REQ-H1.3, REQ-D1.9).
# ---------------------------------------------------------------------------
for f in "$root"/scripts/*.sh; do
  [ "$f" = "$FM" ] && continue
  if grep -q 'CLAUDE_CODE_MESSAGING_SOCKET' "$f"; then
    fail "${f#"$root"/} names CLAUDE_CODE_MESSAGING_SOCKET; only fleet-messaging.sh may"
  fi
  if grep -qE 'SendMessage|ListAgents' "$f"; then
    fail "${f#"$root"/} names SendMessage or ListAgents"
  fi
done
grep -qE 'SendMessage|ListAgents' "$FM" && fail "fleet-messaging.sh names SendMessage or ListAgents"
invocations=$(grep -v '^[[:space:]]*#' "$FM" | grep -cE '(^|[[:space:];&|(`$])claude[[:space:]]' || true)
[ "$invocations" = 1 ] || fail "fleet-messaging.sh invokes claude $invocations times; exactly one (the probe's version read) is allowed"
grep -v '^[[:space:]]*#' "$FM" | grep -E '(^|[[:space:];&|(`$])claude[[:space:]]' | grep -q -- '--version' \
  || fail "fleet-messaging.sh's one claude invocation is not the version read"
sed -n '1,20p' "$FM" | grep -q 'doctrine/messaging-transport.md' || fail "fleet-messaging.sh's header does not cite doctrine/messaging-transport.md"
sed -n '1,60p' "$FA" | grep -q 'doctrine/messaging-transport.md' || fail "fleet-attention.sh's header does not cite doctrine/messaging-transport.md"
ok "the socket variable, SendMessage, and ListAgents stay out of every other script, and claude is invoked once"

echo "PASS: test-fleet-messaging.sh"
