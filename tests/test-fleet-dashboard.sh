#!/bin/bash
# Tests for scripts/fleet-dashboard.sh — the rendered status dashboard
# (execution-backends Task 8: D-10, REQ-D1.2).
#
# REQ-D1.2 `[test]`: dashboard render fixtures assert the output is produced
# from the shared source-merging layer (no second source-reading
# implementation) and covers the same source-availability matrix as the CLI
# view, missing sources marked visibly; an output-encoding fixture asserts
# script-tag/markup content in worker-authored strings renders inert; the
# surface exposes no state-mutating endpoint (read-only assertion).
#
# HOW THE REUSE CLAUSE IS PROVEN. Every fixture runs the dashboard from a
# SANDBOX scripts dir holding exactly three files: fleet-dashboard.sh,
# echo-safety.sh, and a fleet-status.sh SHIM that logs its invocation and
# refuses any subcommand but `merge`. None of the sibling readers
# (fleet-state.sh, fleet-liveness.sh, fleet-streamjson.sh, fleet-attention.sh)
# exist there, so a second source-reading implementation cannot even resolve
# its dependencies — it fails loudly rather than passing quietly. The final
# fixture runs the REAL script against the REAL fleet-status.sh to prove the
# wiring, so the shim can never drift into testing itself.
#
# SERVING IS OUT OF SCOPE HERE. The serving/exposure mechanism is an open
# operator decision; this suite covers only the option-neutral core (render +
# write). No fixture assumes a server, a port, or a network surface.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-dashboard.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
DB="$here/../scripts/fleet-dashboard.sh"
ST="$here/../scripts/fleet-status.sh"
ES="$here/../scripts/echo-safety.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$DB" ] || fail "scripts/fleet-dashboard.sh missing or not executable"
[ -r "$ES" ] || fail "scripts/echo-safety.sh missing"
[ -x "$ST" ] || fail "scripts/fleet-status.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tab=$(printf '\t')
esc=$(printf '\033')

# --- the sandbox: dashboard + sanitizer + a merge shim, nothing else --------
sandbox="$tmp/sandbox"
mkdir -p "$sandbox"
cp "$DB" "$sandbox/fleet-dashboard.sh"
cp "$ES" "$sandbox/echo-safety.sh"
chmod +x "$sandbox/fleet-dashboard.sh"

mergefix="$tmp/merge.tsv"
shimlog="$tmp/shim.log"

# mk_shim — (re)install the merge shim: it logs its invocation and refuses
# anything but `merge`, so a second source read fails loudly instead of
# passing quietly. The heredoc is unquoted so the fixture paths interpolate;
# `\$` and `\\n` reach the file literally.
mk_shim() {
  cat >"$sandbox/fleet-status.sh" <<EOF
#!/bin/sh
printf '%s\\n' "\$*" >>"$shimlog"
[ "\$1" = merge ] && [ \$# -eq 1 ] || exit 9
cat "$mergefix"
EOF
  chmod +x "$sandbox/fleet-status.sh"
}
mk_shim

# A shim that fails the merge outright (the fail-closed arm).
shim_fail="$tmp/status-fail.sh"
printf '#!/bin/sh\nexit 2\n' >"$shim_fail"
chmod +x "$shim_fail"

# Pre-warm the fresh sandbox scripts once (macOS first-exec latency must not
# skew the runs, and the shim's own first exec is inside a timed fixture).
/bin/sh "$sandbox/fleet-status.sh" merge >/dev/null 2>&1 || true
: >"$shimlog"

# run <args...> — invoke the sandboxed dashboard hermetically.
run() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_FLEET_STATE_DIR \
    /bin/sh "$sandbox/fleet-dashboard.sh" "$@" </dev/null
}

# set_merge <<EOF ... EOF — install the merge stream the shim will emit.
set_merge() {
  cat >"$mergefix"
}

has() {
  case $2 in
    *"$1"*) ;;
    *) fail "$3: expected to find [$1]" ;;
  esac
}

hasnt() {
  case $2 in
    *"$1"*) fail "$3: expected NOT to find [$1]" ;;
    *) ;;
  esac
}

# ---------------------------------------------------------------------------
# 1. The reuse clause: one `merge` call, no second source read, full render.
# ---------------------------------------------------------------------------
set_merge <<EOF
source${tab}attention${tab}ok${tab}2-rows
source${tab}streamjson${tab}ok${tab}1-workers
source${tab}oracle${tab}ok${tab}1-rows
source${tab}registry${tab}ok${tab}1-records
worker${tab}w1${tab}spec=alpha:task-1${tab}attention,streamjson${tab}working${tab}12${tab}running${tab}0${tab}busy
worker${tab}w2${tab}spec=beta:task-3${tab}attention${tab}waiting${tab}300${tab}-${tab}-${tab}-
session${tab}ssss-9999${tab}idle${tab}interactive${tab}operator${tab}/home/op
EOF
: >"$shimlog"
out=$(run render) || fail "1: render exited non-zero"
[ "$(wc -l <"$shimlog" | tr -d ' ')" = "1" ] \
  || fail "1: expected exactly one fleet-status.sh invocation, log: $(cat "$shimlog")"
[ "$(cat "$shimlog")" = "merge" ] \
  || fail "1: expected the sole invocation to be \`merge\`, got [$(cat "$shimlog")]"
has "<!doctype html>" "$out" 1
has "w1" "$out" 1
has "w2" "$out" 1
has "spec=alpha:task-1" "$out" 1
has "ssss-9999" "$out" 1
for src in attention streamjson oracle registry; do
  has "$src" "$out" "1 ($src)"
done

# ---------------------------------------------------------------------------
# 2. The source-availability matrix: every cell names every source with its
#    state; a missing source is marked visibly, never silently omitted.
# ---------------------------------------------------------------------------
for a_state in ok absent unavailable; do
  for s_state in ok absent unavailable; do
    for o_state in ok absent unavailable; do
      set_merge <<EOF
source${tab}attention${tab}${a_state}${tab}detail-a
source${tab}streamjson${tab}${s_state}${tab}detail-s
source${tab}oracle${tab}${o_state}${tab}detail-o
source${tab}registry${tab}ok${tab}1-records
worker${tab}w1${tab}spec=alpha:task-1${tab}registry${tab}-${tab}-${tab}-${tab}-${tab}-
EOF
      cell="2 ($a_state/$s_state/$o_state)"
      out=$(run render) || fail "$cell: render exited non-zero"
      # Every source is named with its state, in every cell.
      has "attention" "$out" "$cell"
      has "streamjson" "$out" "$cell"
      has "oracle" "$out" "$cell"
      has "registry" "$out" "$cell"
      has "state-$a_state" "$out" "$cell attention state"
      has "state-$s_state" "$out" "$cell streamjson state"
      has "state-$o_state" "$out" "$cell oracle state"
      # The details ride along, so a degrade names its cause.
      has "detail-a" "$out" "$cell"
      has "detail-s" "$out" "$cell"
      has "detail-o" "$out" "$cell"
      # The worker is rendered in every cell — a degraded source never
      # silently drops a row.
      has "w1" "$out" "$cell"
    done
  done
done

# ---------------------------------------------------------------------------
# 3. Degraded cells render visible markers, never blanks, with a legend.
# ---------------------------------------------------------------------------
set_merge <<EOF
source${tab}attention${tab}ok${tab}1-rows
source${tab}streamjson${tab}ok${tab}1-workers
source${tab}oracle${tab}unavailable${tab}probe-failed
source${tab}registry${tab}ok${tab}1-records
worker${tab}wreg${tab}spec=gamma:task-9${tab}registry${tab}-${tab}-${tab}-${tab}-${tab}-
worker${tab}wq${tab}spec=delta:task-2${tab}streamjson${tab}-${tab}-${tab}running${tab}1${tab}?
EOF
out=$(run render) || fail "3: render exited non-zero"
# Assert markers inside the WORKER'S OWN ROW, not merely somewhere on the
# page: the legend also spells `n/a`, so a page-wide grep would pass even if
# the cell rendered blank — the silent omission REQ-D1.2 forbids.
# row <handle> — the single rendered <tr> carrying that worker.
row() {
  printf '%s\n' "$out" | grep -F "\"cell handle\">$1<" || true
}
r=$(row wreg)
[ -n "$r" ] || fail "3: registry-only worker wreg is missing from the table"
has "n/a" "$r" "3 (registry-only marker in the row)"
has "marker" "$r" "3 (marker class in the row)"
r=$(row wq)
[ -n "$r" ] || fail "3: worker wq is missing from the table"
has "?" "$r" "3 (degraded oracle marker in the row)"
has "marker" "$r" "3 (marker class in the row)"
has "legend" "$out" "3 (legend)"

# ---------------------------------------------------------------------------
# 4. Output encoding: worker-authored markup renders inert.
# ---------------------------------------------------------------------------
set_merge <<EOF
source${tab}attention${tab}ok${tab}1-rows
source${tab}streamjson${tab}absent${tab}no-runtime-dirs
source${tab}oracle${tab}ok${tab}1-rows
source${tab}registry${tab}absent${tab}no-records
worker${tab}<script>alert(1)</script>${tab}a&b"c'd${tab}attention${tab}working${tab}5${tab}-${tab}-${tab}-
session${tab}sid-1${tab}idle${tab}interactive${tab}<img src=x onerror=alert(2)>${tab}/tmp/x
EOF
out=$(run render) || fail "4: render exited non-zero"
hasnt "<script>alert" "$out" "4 (raw script tag)"
hasnt "<img" "$out" "4 (raw img tag)"
# NB: the encoded value legitimately still READS `onerror=alert(2)` as text —
# that is the point of encoding. What must not survive is the tag that would
# make the browser treat it as an attribute, asserted above.
has "&lt;script&gt;alert(1)&lt;/script&gt;" "$out" "4 (encoded script tag)"
has "&lt;img src=x onerror=alert(2)&gt;" "$out" "4 (encoded img tag)"
has "a&amp;b&quot;c&#39;d" "$out" "4 (encoded ampersand and quotes)"

# ---------------------------------------------------------------------------
# 5. Read-only surface: the rendered artifact carries no state-mutating
#    endpoint — no form, no script, no control that could POST anywhere.
# ---------------------------------------------------------------------------
for frag in "<form" "<script" "<button" "<input" "<textarea" "method=" "javascript:" "onclick" "onload"; do
  hasnt "$frag" "$out" "5 (mutating/active fragment $frag)"
done

# ---------------------------------------------------------------------------
# 6. Escape sequences in the merge stream never reach the output raw.
# ---------------------------------------------------------------------------
set_merge <<EOF
source${tab}attention${tab}ok${tab}1-rows
source${tab}streamjson${tab}absent${tab}no-runtime-dirs
source${tab}oracle${tab}absent${tab}0-rows
source${tab}registry${tab}absent${tab}no-records
worker${tab}w${esc}[31mred${tab}scope${tab}attention${tab}working${tab}1${tab}-${tab}-${tab}-
EOF
out=$(run render) || fail "6: render exited non-zero"
hasnt "$esc" "$out" "6 (raw escape byte)"

# ---------------------------------------------------------------------------
# 7. Fail closed: an unusable merge layer is an error, never a half page.
# ---------------------------------------------------------------------------
cp "$shim_fail" "$sandbox/fleet-status.sh"
rc=0
out=$(run render 2>/dev/null) || rc=$?
[ "$rc" -eq 2 ] || fail "7: expected exit 2 on a failed merge, got $rc"
hasnt "<!doctype html>" "$out" "7 (no partial page)"
rm -f "$sandbox/fleet-status.sh"
rc=0
run render >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "7: expected exit 2 with fleet-status.sh absent, got $rc"
# Restore the working shim.
mk_shim

# ---------------------------------------------------------------------------
# 8. An empty fleet renders as an empty page, sources still marked.
# ---------------------------------------------------------------------------
set_merge <<EOF
source${tab}attention${tab}absent${tab}no-store
source${tab}streamjson${tab}absent${tab}no-runtime-dirs
source${tab}oracle${tab}absent${tab}0-rows
source${tab}registry${tab}absent${tab}no-records
EOF
out=$(run render) || fail "8: render exited non-zero"
has "no workers" "$out" 8
has "no-store" "$out" 8

# ---------------------------------------------------------------------------
# 9. The refresh knob (serving-neutral: a browser-level hint, no server).
# ---------------------------------------------------------------------------
out=$(run render) || fail "9: render exited non-zero"
hasnt "http-equiv=\"refresh\"" "$out" "9 (no refresh by default)"
out=$(run render --refresh 15) || fail "9: render --refresh exited non-zero"
has "<meta http-equiv=\"refresh\" content=\"15\">" "$out" 9
rc=0
run render --refresh abc >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "9: expected exit 2 on a non-numeric refresh, got $rc"
rc=0
run render --refresh -1 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "9: expected exit 2 on a negative refresh, got $rc"

# ---------------------------------------------------------------------------
# 10. `write` produces the same document atomically, leaving no debris.
# ---------------------------------------------------------------------------
set_merge <<EOF
source${tab}attention${tab}ok${tab}1-rows
source${tab}streamjson${tab}absent${tab}no-runtime-dirs
source${tab}oracle${tab}absent${tab}0-rows
source${tab}registry${tab}absent${tab}no-records
worker${tab}w1${tab}spec=alpha:task-1${tab}attention${tab}working${tab}7${tab}-${tab}-${tab}-
EOF
outdir="$tmp/out"
mkdir -p "$outdir"
run write "$outdir/fleet.html" >/dev/null || fail "10: write exited non-zero"
[ -f "$outdir/fleet.html" ] || fail "10: write produced no file"
# Exactly one file: the atomic temp must not survive.
n=$(find "$outdir" -type f | wc -l | tr -d ' ')
[ "$n" = "1" ] || fail "10: expected 1 file in the output dir, found $n"
body=$(cat "$outdir/fleet.html")
has "w1" "$body" 10
has "<!doctype html>" "$body" 10
# Same document as `render`, modulo the generated-at line.
strip_generated() {
  grep -v 'class="generated"' || true
}
a=$(run render | strip_generated)
b=$(strip_generated <"$outdir/fleet.html")
[ "$a" = "$b" ] || fail "10: write and render disagree outside the generated line"
# An overwrite replaces the document in place.
run write "$outdir/fleet.html" >/dev/null || fail "10: overwrite exited non-zero"
n=$(find "$outdir" -type f | wc -l | tr -d ' ')
[ "$n" = "1" ] || fail "10: overwrite left debris, found $n files"
# A path whose directory does not exist fails closed.
rc=0
run write "$tmp/nope/fleet.html" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "10: expected exit 2 writing into a missing dir, got $rc"
rc=0
run write >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "10: expected exit 2 on a missing write path, got $rc"

# ---------------------------------------------------------------------------
# 11. Usage errors fail closed (no subcommand, unknown subcommand, stray flag).
# ---------------------------------------------------------------------------
for args in "" "bogus" "render --bogus" "render extra"; do
  rc=0
  # shellcheck disable=SC2086 # deliberate word splitting of the arg fixture
  run $args >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "11: expected exit 2 for [$args], got $rc"
done

# ---------------------------------------------------------------------------
# 12. Real wiring: the shipped script over the REAL fleet-status.sh, so the
#     shim can never drift into testing itself.
# ---------------------------------------------------------------------------
realhome="$tmp/realhome"
mkdir -p "$realhome"
oshim="$tmp/agents-shim"
printf '#!/bin/sh\nexit 9\n' >"$oshim"
chmod +x "$oshim"
"$oshim" agents --json >/dev/null 2>&1 || true
out=$(env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
  PLANWRIGHT_FLEET_STATE_DIR="$realhome" \
  PLANWRIGHT_ORACLE_CLAUDE="$oshim" \
  /bin/sh "$DB" render </dev/null) || fail "12: real render exited non-zero"
has "<!doctype html>" "$out" 12
has "no workers" "$out" 12
for src in attention streamjson oracle registry; do
  has "$src" "$out" "12 ($src)"
done
has "state-unavailable" "$out" "12 (failed oracle probe marked)"

echo "ok: fleet-dashboard"
