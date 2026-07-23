#!/bin/bash
# Tests for scripts/fleet-status.sh — the backend-agnostic CLI status view
# (execution-backends Task 7: D-10, REQ-D1.1).
#
# REQ-D1.1 `[test]`: renderer fixtures cover the source present/absent matrix
# for all three sources (`claude agents --json` shim, event-stream capture,
# attention store): each cell renders workers from the available sources and
# marks a missing source visibly rather than omitting it silently. A
# print-backend unit renders from dispatch records (the fleet-state registry)
# or a visible not-applicable marker; an escape-sequence fixture asserts
# worker-authored strings pass the echo-safety sanitizer before rendering.
#
# The `merge` subcommand is the source-merging layer (the D-10 seam Task 8's
# dashboard reuses); `render` is the human table over it. Tests assert the
# machine-readable merge stream (stable contract) and the render's visible
# markers.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-status.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
ST="$here/../scripts/fleet-status.sh"
FS="$here/../scripts/fleet-state.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$ST" ] || fail "scripts/fleet-status.sh missing or not executable"
[ -x "$FS" ] || fail "scripts/fleet-state.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tab=$(printf '\t')
esc=$(printf '\033')
bel=$(printf '\007')

# --- the agents-json oracle shim (stands in for `claude agents --json`) -----
ofix="$tmp/agents-fixture.json"
oshim="$tmp/agents-shim"
{
  echo '#!/bin/sh'
  # Refuse unexpected invocations so wiring drift fails loudly, then emit the
  # fixture.
  # shellcheck disable=SC2016 # literal shim source, expanded at shim runtime
  echo '[ "$1" = agents ] && [ "$2" = --json ] || exit 9'
  echo "cat \"$ofix\""
} >"$oshim"
chmod +x "$oshim"
# A shim that fails: the oracle-unavailable arm.
oshim_fail="$tmp/agents-shim-fail"
printf '#!/bin/sh\nexit 9\n' >"$oshim_fail"
chmod +x "$oshim_fail"
# Pre-warm fresh shims once (macOS first-exec latency must not skew runs).
printf '[]\n' >"$ofix"
"$oshim" agents --json >/dev/null 2>&1 || true
"$oshim_fail" agents --json >/dev/null 2>&1 || true

# run <fleet-home> <oracle-bin> <args...> — hermetic invocation.
run() {
  r_home=$1
  r_bin=$2
  shift 2
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    PLANWRIGHT_FLEET_STATE_DIR="$r_home" \
    PLANWRIGHT_ORACLE_CLAUDE="$r_bin" \
    /bin/sh "$ST" "$@" </dev/null
}

# mk_attention <home> <worker> <scope> <state> — append a store row the way
# fleet-attention.sh lays it out (worker scope state ts prio q def opts).
mk_attention() {
  mkdir -p "$1/attention"
  printf '%s\t%s\t%s\t%s\t\t\t\t\n' "$2" "$3" "$4" "$(date +%s)" >>"$1/attention/state"
}

# mk_sj <home> <worker> [session-id] — a streamjson runtime dir with live
# pids (this test process, so `status` reads running).
mk_sj() {
  mkdir -p "$1/streamjson/$2"
  printf '%s\n' "$$" >"$1/streamjson/$2/supervisor.pid"
  printf '%s\n' "$$" >"$1/streamjson/$2/worker.pid"
  [ -z "${3:-}" ] || printf '%s\n' "$3" >"$1/streamjson/$2/session"
}

# merge_line <output> <type> <key> — print the first merge line of <type>
# whose second field is <key>.
merge_line() {
  printf '%s\n' "$1" | awk -F'\t' -v t="$2" -v k="$3" '$1 == t && $2 == k { print; exit }'
}

# ---------------------------------------------------------------------------
# 1. All three sources present: one worker known to all three merges into a
#    single row; every source line reads ok.
# ---------------------------------------------------------------------------
h1="$tmp/h1"
mk_attention "$h1" w1 spec=alpha:task-1 working
mk_sj "$h1" w1 aaaa-1111
cat >"$ofix" <<'EOF'
[
  {"pid": 100, "cwd": "/wt/alpha", "kind": "background", "sessionId": "aaaa-1111", "name": "w1", "status": "busy"}
]
EOF
out=$(run "$h1" "$oshim" merge) || fail "1 merge: non-zero exit"
for src in attention streamjson oracle; do
  line=$(merge_line "$out" source "$src")
  case $line in
    "source$tab$src${tab}ok$tab"*) ;;
    *) fail "1 source $src: expected ok, got '$line'" ;;
  esac
done
w=$(merge_line "$out" worker w1)
[ -n "$w" ] || fail "1: no merged worker row for w1"
case $w in
  *"${tab}spec=alpha:task-1${tab}"*) ;; *) fail "1 w1 scope missing: '$w'" ;;
esac
case $w in
  *"${tab}working${tab}"*) ;; *) fail "1 w1 attention state missing: '$w'" ;;
esac
case $w in
  *"${tab}running${tab}"*) ;; *) fail "1 w1 streamjson status missing: '$w'" ;;
esac
case $w in
  *"${tab}busy"*) ;; *) fail "1 w1 oracle verdict missing: '$w'" ;;
esac
n=$(printf '%s\n' "$out" | awk -F'\t' '$1 == "worker"' | wc -l | tr -d ' ')
[ "$n" = 1 ] || fail "1: expected exactly one worker row, got $n"
# The joined oracle row must not re-render as an unjoined session line.
s=$(merge_line "$out" session aaaa-1111)
[ -z "$s" ] || fail "1: joined oracle row leaked as a session line: '$s'"
echo "ok: all-present cell merges one worker across the three sources"

# ---------------------------------------------------------------------------
# 2. Attention-only cell: worker renders from the store; the other sources
#    are marked absent, and its per-source cells read "-".
# ---------------------------------------------------------------------------
h2="$tmp/h2"
mk_attention "$h2" w2 spec=beta:task-2 idle
printf '[]\n' >"$ofix"
out=$(run "$h2" "$oshim" merge) || fail "2 merge: non-zero exit"
case $(merge_line "$out" source streamjson) in
  "source${tab}streamjson${tab}absent$tab"*) ;;
  *) fail "2: streamjson source not marked absent" ;;
esac
case $(merge_line "$out" source oracle) in
  "source${tab}oracle${tab}absent$tab"*) ;;
  *) fail "2: oracle source (zero rows) not marked absent" ;;
esac
w=$(merge_line "$out" worker w2)
[ -n "$w" ] || fail "2: attention-only worker omitted"
case $w in
  *"${tab}idle${tab}"*) ;; *) fail "2 w2 attention state missing: '$w'" ;;
esac
case $w in
  worker"${tab}w2${tab}spec=beta:task-2${tab}attention${tab}idle${tab}"*"${tab}-${tab}-${tab}-") ;;
  *) fail "2 w2 absent-source cells not dashed: '$w'" ;;
esac
echo "ok: attention-only cell renders the worker and marks the missing sources"

# ---------------------------------------------------------------------------
# 3. Streamjson-only cell: worker renders from the runtime dir alone.
# ---------------------------------------------------------------------------
h3="$tmp/h3"
mk_sj "$h3" w3
printf '[]\n' >"$ofix"
out=$(run "$h3" "$oshim" merge) || fail "3 merge: non-zero exit"
case $(merge_line "$out" source attention) in
  "source${tab}attention${tab}absent$tab"*) ;;
  *) fail "3: attention source not marked absent" ;;
esac
w=$(merge_line "$out" worker w3)
[ -n "$w" ] || fail "3: streamjson-only worker omitted"
case $w in
  worker"${tab}w3${tab}-${tab}streamjson${tab}-${tab}-${tab}running${tab}0${tab}-") ;;
  *) fail "3 w3 row shape: '$w'" ;;
esac
echo "ok: streamjson-only cell renders the worker from the runtime dir"

# ---------------------------------------------------------------------------
# 4. Oracle-only cell: a session no other source knows renders as a session
#    line (never silently dropped); no worker row is invented for it.
# ---------------------------------------------------------------------------
h4="$tmp/h4"
mkdir -p "$h4"
cat >"$ofix" <<'EOF'
[
  {"pid": 101, "cwd": "/wt/gamma", "kind": "interactive", "sessionId": "cccc-3333", "name": "gamma-1", "status": "waiting"}
]
EOF
out=$(run "$h4" "$oshim" merge) || fail "4 merge: non-zero exit"
s=$(merge_line "$out" session cccc-3333)
[ -n "$s" ] || fail "4: oracle-only session omitted"
case $s in
  session"${tab}cccc-3333${tab}waiting${tab}interactive${tab}gamma-1${tab}/wt/gamma") ;;
  *) fail "4 session row shape: '$s'" ;;
esac
n=$(printf '%s\n' "$out" | awk -F'\t' '$1 == "worker"' | wc -l | tr -d ' ')
[ "$n" = 0 ] || fail "4: invented a worker row from an unjoined oracle session"
echo "ok: oracle-only cell renders the session visibly without inventing a worker"

# ---------------------------------------------------------------------------
# 5. All-absent cell: no sources at all — every source line marked, no rows,
#    exit 0 (an empty fleet is a valid render, not an error).
# ---------------------------------------------------------------------------
h5="$tmp/h5"
mkdir -p "$h5"
printf '[]\n' >"$ofix"
out=$(run "$h5" "$oshim" merge) || fail "5 merge: non-zero exit"
for src in attention streamjson oracle registry; do
  case $(merge_line "$out" source "$src") in
    "source$tab$src${tab}absent$tab"*) ;;
    *) fail "5: source $src not marked absent" ;;
  esac
done
n=$(printf '%s\n' "$out" | awk -F'\t' '$1 == "worker" || $1 == "session"' | wc -l | tr -d ' ')
[ "$n" = 0 ] || fail "5: rows rendered from no sources"
echo "ok: the all-absent cell marks every source and renders no rows"

# ---------------------------------------------------------------------------
# 6. Oracle unavailable (failed probe) is distinct from absent: the source
#    line reads unavailable and joinable worker cells read "?" — degraded
#    visibly, never a silent omission or an invented verdict.
# ---------------------------------------------------------------------------
h6="$tmp/h6"
mk_attention "$h6" w6 spec=delta:task-3 working
mk_sj "$h6" w6 eeee-5555
out=$(run "$h6" "$oshim_fail" merge) || fail "6 merge: non-zero exit"
case $(merge_line "$out" source oracle) in
  "source${tab}oracle${tab}unavailable$tab"*) ;;
  *) fail "6: failed oracle probe not marked unavailable" ;;
esac
w=$(merge_line "$out" worker w6)
case $w in
  *"$tab?") ;; *) fail "6 w6 oracle cell not '?': '$w'" ;;
esac
echo "ok: an unavailable oracle degrades visibly (source line + ? cells)"

# ---------------------------------------------------------------------------
# 7. Print-backend unit (REQ-D1.1): a worker known only from its dispatch
#    record (the fleet-state registry) renders with a visible not-applicable
#    marker, never a silent omission.
# ---------------------------------------------------------------------------
h7="$tmp/h7"
mkdir -p "$h7"
env PLANWRIGHT_FLEET_STATE_DIR="$h7" /bin/sh "$FS" register pw7 spec=eps:task-9 >/dev/null \
  || fail "7: fleet-state register failed"
printf '[]\n' >"$ofix"
out=$(run "$h7" "$oshim" merge) || fail "7 merge: non-zero exit"
case $(merge_line "$out" source registry) in
  "source${tab}registry${tab}ok$tab"*) ;;
  *) fail "7: registry source not marked ok" ;;
esac
w=$(merge_line "$out" worker pw7)
[ -n "$w" ] || fail "7: registry-only (print) worker omitted"
case $w in
  worker"${tab}pw7${tab}spec=eps:task-9${tab}registry${tab}-${tab}-${tab}-${tab}-${tab}-") ;;
  *) fail "7 pw7 row shape: '$w'" ;;
esac
rout=$(run "$h7" "$oshim" render) || fail "7 render: non-zero exit"
# Bind the n/a marker to pw7's own render line (a loose *"n/a"* anywhere would
# pass on an unrelated scope or detail string).
pw7line=$(printf '%s\n' "$rout" | grep pw7) || fail "7: render omitted the print worker"
case $pw7line in
  *"n/a"*) ;; *) fail "7: pw7's render line shows no not-applicable marker: '$pw7line'" ;;
esac
echo "ok: a print-backend unit renders from its dispatch record with an n/a marker"

# ---------------------------------------------------------------------------
# 8. Streamjson detail: pending journal rows are counted; a result file
#    renders completed.
# ---------------------------------------------------------------------------
h8="$tmp/h8"
mk_sj "$h8" w8p
printf 'req-1\tpermission\t100\tpending\nreq-2\tquestion\t120\tpending\nreq-3\tpermission\t90\tanswered\t95\n' \
  >"$h8/streamjson/w8p/journal"
mkdir -p "$h8/streamjson/w8c"
printf 'result\t0\n' >"$h8/streamjson/w8c/result"
printf '[]\n' >"$ofix"
out=$(run "$h8" "$oshim" merge) || fail "8 merge: non-zero exit"
case $(merge_line "$out" worker w8p) in
  *"${tab}running${tab}2${tab}"*) ;;
  *) fail "8 w8p pending count: '$(merge_line "$out" worker w8p)'" ;;
esac
case $(merge_line "$out" worker w8c) in
  *"${tab}completed${tab}0${tab}"*) ;;
  *) fail "8 w8c completed: '$(merge_line "$out" worker w8c)'" ;;
esac
echo "ok: streamjson cells carry the pending count and completion"

# ---------------------------------------------------------------------------
# 9. Echo safety (REQ-D1.1): hand-corrupted store content carrying terminal
#    escape sequences is sanitized before rendering — no raw ESC/BEL/control
#    bytes reach the render output.
# ---------------------------------------------------------------------------
h9="$tmp/h9"
mkdir -p "$h9/attention"
printf 'w9%s[31mevil\tspec=%s]0;t%szeta\tworking\t100\t\t\t\t\n' "$esc" "$esc" "$bel" \
  >"$h9/attention/state"
printf '[]\n' >"$ofix"
rout=$(run "$h9" "$oshim" render) || fail "9 render: non-zero exit"
case $rout in
  *"$esc"* | *"$bel"*) fail "9: raw escape bytes reached the render output" ;;
esac
case $rout in
  *w9*evil*) ;; *) fail "9: sanitized worker row missing from render" ;;
esac
echo "ok: worker-authored strings pass the echo-safety sanitizer before rendering"

# ---------------------------------------------------------------------------
# 10. Render marks every missing source visibly (the render half of the
#     degrade contract) and lists workers from the available ones.
# ---------------------------------------------------------------------------
h10="$tmp/h10"
mk_attention "$h10" w10 spec=eta:task-4 working
printf '[]\n' >"$ofix"
rout=$(run "$h10" "$oshim" render) || fail "10 render: non-zero exit"
case $rout in
  *w10*) ;; *) fail "10: render omitted the attention worker" ;;
esac
case $rout in
  *streamjson*absent*) ;; *) fail "10: render does not mark streamjson absent" ;;
esac
case $rout in
  *oracle*absent*) ;; *) fail "10: render does not mark oracle absent" ;;
esac
echo "ok: render marks missing sources visibly while listing available workers"

# ---------------------------------------------------------------------------
# 11. Usage hygiene: an unknown subcommand or flag is refused (exit 2).
# ---------------------------------------------------------------------------
rc=0
run "$tmp/h11" "$oshim" bogus >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "11: unknown subcommand exit $rc, expected 2"
rc=0
run "$tmp/h11" "$oshim" merge --bogus >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "11: unknown flag exit $rc, expected 2"
echo "ok: unknown subcommands and flags are refused"

# ---------------------------------------------------------------------------
# 12. Registry last-record-wins: a re-registered worker renders its CURRENT
#     (last) dispatch scope, not the stale first one. An attention scope, when
#     present, still takes precedence over any registry scope.
# ---------------------------------------------------------------------------
h12="$tmp/h12"
mkdir -p "$h12"
env PLANWRIGHT_FLEET_STATE_DIR="$h12" /bin/sh "$FS" register w12 spec=old:task-1 >/dev/null \
  || fail "12: first register failed"
env PLANWRIGHT_FLEET_STATE_DIR="$h12" /bin/sh "$FS" register w12 spec=new:task-2 >/dev/null \
  || fail "12: second register failed"
printf '[]\n' >"$ofix"
out=$(run "$h12" "$oshim" merge) || fail "12 merge: non-zero exit"
w=$(merge_line "$out" worker w12)
case $w in
  *"${tab}spec=new:task-2${tab}"*) ;;
  *) fail "12: re-registered worker shows stale/wrong scope: '$w'" ;;
esac
# Attention scope wins over registry when both exist.
mk_attention "$h12" w12 spec=live:task-3 working
out=$(run "$h12" "$oshim" merge) || fail "12b merge: non-zero exit"
w=$(merge_line "$out" worker w12)
case $w in
  *"${tab}spec=live:task-3${tab}"*) ;;
  *) fail "12: attention scope did not win over registry: '$w'" ;;
esac
case $w in
  *"${tab}attention,registry${tab}"*) ;;
  *) fail "12: origins not the fixed attention,registry order: '$w'" ;;
esac
echo "ok: registry is last-record-wins; attention scope outranks it"

# ---------------------------------------------------------------------------
# 13. Degenerate oracle rows: an agents-json object with no sessionId is not a
#     renderable session — it must not emit a `session - …` line nor inflate
#     the oracle row count.
# ---------------------------------------------------------------------------
h13="$tmp/h13"
mkdir -p "$h13"
cat >"$ofix" <<'EOF'
[
  {"pid": 1},
  {"cwd": "/wt/z", "kind": "interactive", "sessionId": "zzzz-9", "name": "zeta", "status": "busy"}
]
EOF
out=$(run "$h13" "$oshim" merge) || fail "13 merge: non-zero exit"
case $(merge_line "$out" source oracle) in
  "source${tab}oracle${tab}ok${tab}1-rows") ;;
  *) fail "13: degenerate object counted in oracle rows: '$(merge_line "$out" source oracle)'" ;;
esac
s=$(printf '%s\n' "$out" | awk -F'\t' '$1 == "session" && $2 == "-"')
[ -z "$s" ] || fail "13: a degenerate all-dash session line was emitted: '$s'"
s=$(merge_line "$out" session zzzz-9)
[ -n "$s" ] || fail "13: the real oracle session was dropped"
echo "ok: a sessionId-less oracle object emits no session line"

# ---------------------------------------------------------------------------
# 14. Dot-prefixed streamjson runtime dir (`.w` is a grammar-valid handle) is
#     not silently omitted, and the source is not falsely 'no-runtime-dirs'.
# ---------------------------------------------------------------------------
h14="$tmp/h14"
mk_sj "$h14" .hidden-w
printf '[]\n' >"$ofix"
out=$(run "$h14" "$oshim" merge) || fail "14 merge: non-zero exit"
case $(merge_line "$out" source streamjson) in
  "source${tab}streamjson${tab}ok${tab}1-workers") ;;
  *) fail "14: dot-dir worker not counted as a streamjson source: '$(merge_line "$out" source streamjson)'" ;;
esac
w=$(merge_line "$out" worker .hidden-w)
[ -n "$w" ] || fail "14: dot-prefixed runtime dir silently omitted"
echo "ok: a dot-prefixed runtime dir renders, source not falsely empty"

# ---------------------------------------------------------------------------
# 15. Matrix cell 110 (attention+streamjson present, oracle ABSENT, distinct
#     from unavailable): a worker with a persisted sid gets `-` (no evidence),
#     never `?` (which is reserved for an UNAVAILABLE oracle).
# ---------------------------------------------------------------------------
h15="$tmp/h15"
mk_attention "$h15" w15 spec=th:task-1 working
mk_sj "$h15" w15 sss-15
printf '[]\n' >"$ofix"
out=$(run "$h15" "$oshim" merge) || fail "15 merge: non-zero exit"
case $(merge_line "$out" source oracle) in
  "source${tab}oracle${tab}absent$tab"*) ;;
  *) fail "15: oracle not marked absent" ;;
esac
w=$(merge_line "$out" worker w15)
case $w in
  *"$tab-") ;; *) fail "15: joinable worker under an ABSENT oracle must be '-', got: '$w'" ;;
esac
echo "ok: an absent (vs unavailable) oracle yields '-' not '?' on a joinable worker"

# ---------------------------------------------------------------------------
# 16. Matrix cell 011 (streamjson+oracle present, attention absent): the sid
#     join fires with a dashed attention state/age plus the oracle verdict.
# ---------------------------------------------------------------------------
h16="$tmp/h16"
mk_sj "$h16" w16 join-16
cat >"$ofix" <<'EOF'
[
  {"cwd": "/wt/x", "kind": "background", "sessionId": "join-16", "name": "w16", "status": "waiting"}
]
EOF
out=$(run "$h16" "$oshim" merge) || fail "16 merge: non-zero exit"
w=$(merge_line "$out" worker w16)
case $w in
  worker"${tab}w16${tab}-${tab}streamjson${tab}-${tab}-${tab}running${tab}0${tab}waiting") ;;
  *) fail "16: streamjson+oracle join shape wrong: '$w'" ;;
esac
# The joined oracle session must not also appear as an unjoined session line.
[ -z "$(merge_line "$out" session join-16)" ] || fail "16: joined session leaked as unjoined"
echo "ok: streamjson+oracle join fires with dashed attention cells"

# ---------------------------------------------------------------------------
# 17. Unreadable attention store degrades to 'unavailable', distinct from an
#     absent (missing) store. (Skipped as root, where the mode is ignored.)
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  h17="$tmp/h17"
  mkdir -p "$h17/attention"
  printf 'w17\tspec=i:task-1\tworking\t100\t\t\t\t\n' >"$h17/attention/state"
  chmod 000 "$h17/attention/state"
  printf '[]\n' >"$ofix"
  out=$(run "$h17" "$oshim" merge) || fail "17 merge: non-zero exit"
  chmod 644 "$h17/attention/state" # restore so the trap cleanup can remove it
  case $(merge_line "$out" source attention) in
    "source${tab}attention${tab}unavailable$tab"*) ;;
    *) fail "17: unreadable store not marked unavailable: '$(merge_line "$out" source attention)'" ;;
  esac
  echo "ok: an unreadable store is 'unavailable', not 'absent'"
else
  echo "ok: (skipped as root) unreadable-store unavailable arm"
fi

# ---------------------------------------------------------------------------
# 18. No fleet home ($FS root unresolvable): the three home-backed sources
#     degrade to 'unavailable no-fleet-home', and the oracle is STILL probed.
# ---------------------------------------------------------------------------
# An empty PLANWRIGHT_FLEET_STATE_DIR plus a bare env makes fleet-state.sh root
# unresolvable (no override, no plugin data, no manifest).
nohome=$(env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
  PLANWRIGHT_FLEET_STATE_DIR="" PLANWRIGHT_ORACLE_CLAUDE="$oshim" \
  /bin/sh "$ST" merge 2>/dev/null) || fail "18 merge: non-zero exit"
for src in attention streamjson registry; do
  case $(merge_line "$nohome" source "$src") in
    "source$tab$src${tab}unavailable${tab}no-fleet-home") ;;
    *) fail "18: source $src not unavailable/no-fleet-home: '$(merge_line "$nohome" source "$src")'" ;;
  esac
done
case $(merge_line "$nohome" source oracle) in
  "source${tab}oracle${tab}"*) ;;
  *) fail "18: oracle source line missing under no-fleet-home" ;;
esac
echo "ok: no fleet home degrades the home-backed sources but still probes the oracle"

# ---------------------------------------------------------------------------
# 19. render with sources ok but zero workers prints the 'workers: (none)'
#     line, and an unjoined oracle session renders under the sessions block.
# ---------------------------------------------------------------------------
h19="$tmp/h19"
mkdir -p "$h19"
cat >"$ofix" <<'EOF'
[
  {"cwd": "/wt/s", "kind": "interactive", "sessionId": "solo-19", "name": "solo", "status": "idle"}
]
EOF
rout=$(run "$h19" "$oshim" render) || fail "19 render: non-zero exit"
case $rout in
  *"workers: (none)"*) ;; *) fail "19: no 'workers: (none)' line: '$rout'" ;;
esac
case $rout in
  *"sessions (oracle, unjoined):"*solo-19*) ;;
  *) fail "19: unjoined session block missing solo-19" ;;
esac
echo "ok: render shows 'workers: (none)' and the unjoined-session block"

# ---------------------------------------------------------------------------
# 20. Registry field escapes are sanitized before rendering (the header claims
#     sanitization for registry fields; only the attention path was covered).
# ---------------------------------------------------------------------------
h20="$tmp/h20"
mkdir -p "$h20"
# Bypass fleet-state's write-time validation by hand-writing the registry file
# (a corrupted-on-disk record): the reader must still sanitize on the way out.
printf '100\tr20\tspec=%s[31mzz\n' "$esc" >"$h20/registry"
printf '[]\n' >"$ofix"
rout=$(run "$h20" "$oshim" render) || fail "20 render: non-zero exit"
case $rout in
  *"$esc"*) fail "20: raw ESC from a registry field reached render output" ;;
esac
case $rout in
  *r20*) ;; *) fail "20: sanitized registry worker missing from render" ;;
esac
echo "ok: registry fields pass the echo-safety sanitizer before rendering"

# ---------------------------------------------------------------------------
# 21. A missing fleet-state.sh (the home RESOLVER) is its own degrade cause,
#     not the 'no-fleet-home' of case 18: the taxonomy names a missing sibling
#     script separately, and conflating the two hides a broken install behind
#     what reads as a configuration gap. The oracle is still probed.
# ---------------------------------------------------------------------------
nofs="$tmp/scripts-nofs"
cp -R "$here/../scripts" "$nofs"
rm -f "$nofs/fleet-state.sh"
h21="$tmp/h21"
mkdir -p "$h21"
printf '[]\n' >"$ofix"
out21=$(env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
  PLANWRIGHT_FLEET_STATE_DIR="$h21" PLANWRIGHT_ORACLE_CLAUDE="$oshim" \
  /bin/sh "$nofs/fleet-status.sh" merge </dev/null) \
  || fail "21 merge: non-zero exit"
for src in attention streamjson registry; do
  case $(merge_line "$out21" source "$src") in
    "source$tab$src${tab}unavailable${tab}missing-state-script") ;;
    *) fail "21: source $src not unavailable/missing-state-script: '$(merge_line "$out21" source "$src")'" ;;
  esac
done
case $(merge_line "$out21" source oracle) in
  "source${tab}oracle${tab}"*) ;;
  *) fail "21: oracle source line missing under a missing state script" ;;
esac
echo "ok: a missing fleet-state.sh reports 'missing-state-script', not 'no-fleet-home'"

# ---------------------------------------------------------------------------
# 22. render's row scans are fail-closed: an awk that fails mid-render must
#     exit 2, never print a fabricated line and exit 0. emit_merge already
#     writes each awk to a temp so its status is checked; render's scans owe
#     the same discipline, or an internal failure reads as a rendered fleet.
# ---------------------------------------------------------------------------
realawk=$(command -v awk) || fail "22: no awk on PATH"
stub22="$tmp/stub22"
mkdir -p "$stub22"
# Fail only the scan named by $SCAN_FAIL; delegate every other awk untouched
# (emit_merge's awks must still work, or we would be testing the wrong arm).
# The quoted heredoc keeps the stub source literal: the `$1` below must reach
# the stub as the two characters awk's program text carries, not as the stub's
# own first argument.
{
  echo '#!/bin/sh'
  cat <<'STUB22'
want='$1 == "'"$SCAN_FAIL"'"'
for a in "$@"; do
  [ "$a" = "$want" ] && exit 1
done
STUB22
  printf 'exec %s "$@"\n' "$realawk"
} >"$stub22/awk"
chmod +x "$stub22/awk"
"$stub22/awk" 'BEGIN { exit 0 }' </dev/null # pre-warm (macOS first-exec latency)
h22="$tmp/h22"
mkdir -p "$h22/attention"
printf 'w22\tspec=i:task-1\tworking\t%s\t\t\t\t\n' "$(date +%s)" >"$h22/attention/state"
printf '[]\n' >"$ofix"
for scan in source worker session; do
  rc=0
  out22=$(PATH="$stub22:$PATH" SCAN_FAIL="$scan" \
    env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    PLANWRIGHT_FLEET_STATE_DIR="$h22" PLANWRIGHT_ORACLE_CLAUDE="$oshim" \
    /bin/sh "$ST" render 2>/dev/null) || rc=$?
  [ "$rc" = 2 ] \
    || fail "22 ($scan scan): render exited $rc, expected 2 (fail closed on an internal awk failure)"
  case $out22 in
    *'?=?(?)'*) fail "22 ($scan scan): render printed a fabricated source line: '$out22'" ;;
  esac
done
echo "ok: render fails closed (exit 2) when a row scan fails, never a fabricated line"

echo "ALL PASS: fleet-status.sh"
