#!/bin/sh
# Unit tests for scripts/spec-graph.sh — the dependency-graph and critical-path
# view for /spec-walkthrough (Task 7 of specs/spec-comprehension; D-4, D-5, D-6;
# REQ-C1.3, REQ-C1.6, REQ-E1.3).
#
# The graph view reads the bundle model (Task 2), computes a layout for the task
# DAG, and emits a tab-separated record stream the assembler (Task 6) draws as an
# inline SVG. The critical path it highlights is the one orchestrate-select.sh
# emits (D-6, --critical-path), reused rather than recomputed, so the two cannot
# disagree. The layout is built-in by default and is enriched by Graphviz (`dot`)
# when present; a failed or absent `dot` degrades identically to the built-in
# path with an in-artifact note (D-5, REQ-E1.3).
#
# Record vocabulary (tab-separated, column 1 the tag):
#   GRAPHMETA  <width>  <height>  <layout:builtin|graphviz>
#   GRAPHNOTE  <text>
#   GRAPHCRIT  <space-joined critical-path ids>
#   GRAPHNODE  <id>  <x>  <y>  <crit:0|1>  <title verbatim>
#   GRAPHEDGE  <from-id>  <to-id>  <crit:0|1>
#
# Properties verified:
#   1.  dir mode emits one node per task, one edge per dependency, a GRAPHCRIT
#       line, GRAPHMETA, and GRAPHNOTE; exit 0.
#   2.  The critical path matches orchestrate-select.sh --critical-path for the
#       same bundle (D-6, REQ-C1.3) — reused, not recomputed.
#   3.  Critical nodes and edges carry the crit=1 flag; off-path ones crit=0.
#   4.  Node titles are carried verbatim (escaping is the assembler's job, D-2).
#   5.  Coordinates are numeric; parallel tasks (same dependency depth) share a
#       column (built-in layout) so parallelism is visible.
#   6.  Built-in layout is the default with a "Graphviz not detected" note.
#   7.  Graphviz present (stubbed): layout=graphviz, the note names it, and node
#       coordinates come from the dot -Tplain output.
#   8.  Graphviz present-but-failing (stubbed non-zero / garbage): degrades to
#       the built-in layout with the note, exactly as absence (REQ-E1.3).
#   9.  A bundle with no task graph degrades to an empty-graph note, exit 0.
#  10.  A missing spec directory fails closed (exit 2); the view is read-only.
#
# Runs standalone: ./tests/test-spec-graph.sh
set -eu

LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/spec-graph.sh"
sel="$here/../scripts/orchestrate-select.sh"
repo_root=$(cd "$here/.." && pwd)

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$script" ] || fail "scripts/spec-graph.sh missing or not executable"

tmp=$(mktemp -d)
trap 'chmod -R u+rwx "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

out=
run_dir() {
  rexp=$1
  rc=0
  out=$("$script" "$2" 2>&1) || rc=$?
  [ "$rc" -eq "$rexp" ] \
    || fail "dir mode: expected exit $rexp, got $rc for $2 — output: $out"
}

# rec <tag> — the records with column-1 tag <tag> from $out.
rec() {
  printf '%s\n' "$out" | awk -F'\t' -v t="$1" '$1==t'
}
# field <tag> <colnum> — the given 1-indexed column of the first <tag> record.
field() {
  printf '%s\n' "$out" | awk -F'\t' -v t="$1" -v c="$2" '$1==t{print $c; exit}'
}
has() {
  case $out in
    *"$1"*) ;;
    *) fail "output lacks \"$1\"" ;;
  esac
}

# A small bundle with a known DAG:
#   1 (none, 1d) -> {2 (2d), 3 (half)};  2 -> 4 (1d)
# Full-graph effort-weighted longest chain: 1 -> 2 -> 4 (1 + 2 + 1 = 4);
# task 3 is a short leaf off 1. So the critical path is "1 2 4".
# Task 3's title carries HTML/SVG markup to prove the view carries it verbatim
# (the assembler escapes it; the view must not mangle or pre-escape it).
make_bundle() {
  d=$1
  mkdir -p "$d"
  cat >"$d/requirements.md" <<'EOF'
# Fixture — Requirements

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

## REQ-A — group

- **REQ-A1.1** A thing SHALL exist. *(Cites: D-1.)*
EOF
  cat >"$d/design.md" <<'EOF'
# Fixture — Design

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

### D-1: Only decision  (N)

**Decision:** Exist.

**Alternatives considered:**
- Nothing. Rejected because: nothing.

**Chosen because:** needed.
EOF
  cat >"$d/tasks.md" <<'EOF'
# Fixture — Tasks

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

## Forward plan

### Task 1 — root task

- **Deliverables:** a thing.
- **Done when:** done.
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** 1 day

### Task 2 — heavy middle

- **Deliverables:** a thing.
- **Done when:** done.
- **Dependencies:** 1
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** 2 days

### Task 3 — parallel leaf <script>alert(1)</script>

- **Deliverables:** a thing.
- **Done when:** done.
- **Dependencies:** 1
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** half day

### Task 4 — tail

- **Deliverables:** a thing.
- **Done when:** done.
- **Dependencies:** 2
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** 1 day
EOF
  cat >"$d/test-spec.md" <<'EOF'
# Fixture — Test Spec

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

### REQ-A1.1 — exists [test]

Assert it exists.
EOF
}

bundle="$tmp/specs/demo"
make_bundle "$bundle"

# Force the built-in path by pointing the Graphviz override at a missing binary,
# so this host's real dot (if any) does not perturb the default-path assertions.
SPEC_WALKTHROUGH_DOT=dot-not-installed-xyz
export SPEC_WALKTHROUGH_DOT

# ---------------------------------------------------------------------------
# 1. dir mode: nodes, edges, crit, meta, note.
# ---------------------------------------------------------------------------
run_dir 0 "$bundle"
nnodes=$(rec GRAPHNODE | wc -l | tr -d ' ')
[ "$nnodes" -eq 4 ] || fail "expected 4 GRAPHNODE records, got $nnodes"
nedges=$(rec GRAPHEDGE | wc -l | tr -d ' ')
[ "$nedges" -eq 3 ] || fail "expected 3 GRAPHEDGE records (1->2,1->3,2->4), got $nedges"
[ -n "$(rec GRAPHMETA)" ] || fail "no GRAPHMETA record"
[ -n "$(rec GRAPHNOTE)" ] || fail "no GRAPHNOTE record"

# ---------------------------------------------------------------------------
# 2. Critical path matches orchestrate-select.sh --critical-path (D-6).
# ---------------------------------------------------------------------------
crit_line=$(field GRAPHCRIT 2)
[ "$crit_line" = "1 2 4" ] || fail "GRAPHCRIT [$crit_line], expected [1 2 4]"
sel_path=$(/bin/sh "$sel" --critical-path "$bundle" | awk '{printf (NR>1?" ":"") $0} END{print ""}')
[ "$crit_line" = "$sel_path" ] \
  || fail "graph crit [$crit_line] != selector path [$sel_path] (D-6 reuse broken)"

# ---------------------------------------------------------------------------
# 3. Critical nodes/edges flagged; off-path ones not.
# ---------------------------------------------------------------------------
node_crit() { printf '%s\n' "$out" | awk -F'\t' -v id="$1" '$1=="GRAPHNODE"&&$2==id{print $5; exit}'; }
[ "$(node_crit 1)" = 1 ] || fail "node 1 should be critical"
[ "$(node_crit 2)" = 1 ] || fail "node 2 should be critical"
[ "$(node_crit 4)" = 1 ] || fail "node 4 should be critical"
[ "$(node_crit 3)" = 0 ] || fail "node 3 (leaf) should not be critical"
edge_crit() { printf '%s\n' "$out" | awk -F'\t' -v a="$1" -v b="$2" '$1=="GRAPHEDGE"&&$2==a&&$3==b{print $4; exit}'; }
[ "$(edge_crit 1 2)" = 1 ] || fail "edge 1->2 should be critical"
[ "$(edge_crit 2 4)" = 1 ] || fail "edge 2->4 should be critical"
[ "$(edge_crit 1 3)" = 0 ] || fail "edge 1->3 should not be critical"

# ---------------------------------------------------------------------------
# 4. Titles carried verbatim (no escaping at this layer — D-2).
# ---------------------------------------------------------------------------
title3=$(printf '%s\n' "$out" | awk -F'\t' '$1=="GRAPHNODE"&&$2==3{print $6; exit}')
case $title3 in
  *'<script>alert(1)</script>'*) ;;
  *) fail "node 3 title not carried verbatim: [$title3]" ;;
esac

# ---------------------------------------------------------------------------
# 5. Numeric coordinates; parallel tasks share a column (built-in layout).
# ---------------------------------------------------------------------------
for id in 1 2 3 4; do
  x=$(printf '%s\n' "$out" | awk -F'\t' -v i="$id" '$1=="GRAPHNODE"&&$2==i{print $3; exit}')
  y=$(printf '%s\n' "$out" | awk -F'\t' -v i="$id" '$1=="GRAPHNODE"&&$2==i{print $4; exit}')
  case $x in '' | *[!0-9]*) fail "node $id x not a non-negative integer: [$x]" ;; esac
  case $y in '' | *[!0-9]*) fail "node $id y not a non-negative integer: [$y]" ;; esac
done
x2=$(printf '%s\n' "$out" | awk -F'\t' '$1=="GRAPHNODE"&&$2==2{print $3; exit}')
x3=$(printf '%s\n' "$out" | awk -F'\t' '$1=="GRAPHNODE"&&$2==3{print $3; exit}')
x1=$(printf '%s\n' "$out" | awk -F'\t' '$1=="GRAPHNODE"&&$2==1{print $3; exit}')
x4=$(printf '%s\n' "$out" | awk -F'\t' '$1=="GRAPHNODE"&&$2==4{print $3; exit}')
[ "$x2" = "$x3" ] || fail "parallel tasks 2,3 should share a column: x2=$x2 x3=$x3"
[ "$x1" -lt "$x2" ] || fail "task 1 (root) should be left of task 2: x1=$x1 x2=$x2"
[ "$x4" -gt "$x2" ] || fail "task 4 (tail) should be right of task 2: x4=$x4 x2=$x2"

# ---------------------------------------------------------------------------
# 6. Built-in layout is the default, with a Graphviz-not-detected note.
# ---------------------------------------------------------------------------
[ "$(field GRAPHMETA 4)" = builtin ] || fail "expected layout=builtin by default"
note=$(field GRAPHNOTE 2)
case $note in
  *Graphviz* | *graphviz*) ;;
  *) fail "built-in note should mention Graphviz: [$note]" ;;
esac

# ---------------------------------------------------------------------------
# 7. Graphviz present (stubbed dot emitting valid -Tplain): layout=graphviz.
# ---------------------------------------------------------------------------
stub="$tmp/gv-ok"
mkdir -p "$stub"
cat >"$stub/dot" <<'STUB'
#!/bin/sh
# Stub Graphviz: ignore stdin, emit a valid -Tplain layout for nodes 1..4.
cat <<'PLAIN'
graph 1.0 6.0 2.0
node 1 0.5 1.0 1.2 0.5 t1 solid box black lightgrey
node 2 2.5 1.5 1.2 0.5 t2 solid box black lightgrey
node 3 2.5 0.5 1.2 0.5 t3 solid box black lightgrey
node 4 4.5 1.0 1.2 0.5 t4 solid box black lightgrey
edge 1 2 4 0.5 1.0 1.0 1.1 1.5 1.3 2.5 1.5 solid black
stop
PLAIN
STUB
chmod +x "$stub/dot"
out=$(SPEC_WALKTHROUGH_DOT="$stub/dot" "$script" "$bundle" 2>&1) \
  || fail "graphviz-present run failed"
[ "$(field GRAPHMETA 4)" = graphviz ] || fail "expected layout=graphviz with a working dot"
gnote=$(field GRAPHNOTE 2)
case $gnote in
  *Graphviz* | *graphviz*) ;;
  *) fail "graphviz note should name Graphviz: [$gnote]" ;;
esac
# The critical path is layout-independent: still reused from the selector.
[ "$(field GRAPHCRIT 2)" = "1 2 4" ] || fail "critical path changed under graphviz layout"
# Still one node per task.
[ "$(rec GRAPHNODE | wc -l | tr -d ' ')" -eq 4 ] || fail "graphviz layout lost a node"

# ---------------------------------------------------------------------------
# 8. Graphviz present-but-failing degrades to the built-in layout (REQ-E1.3).
# ---------------------------------------------------------------------------
# 8a. dot exits non-zero.
badexit="$tmp/gv-fail"
mkdir -p "$badexit"
printf '#!/bin/sh\nexit 1\n' >"$badexit/dot"
chmod +x "$badexit/dot"
out=$(SPEC_WALKTHROUGH_DOT="$badexit/dot" "$script" "$bundle" 2>&1) \
  || fail "graphviz-failing run should still succeed (degrade), exit non-zero"
[ "$(field GRAPHMETA 4)" = builtin ] \
  || fail "a failing dot must degrade to layout=builtin (REQ-E1.3)"
# 8b. dot emits garbage (no parseable layout).
garbage="$tmp/gv-garbage"
mkdir -p "$garbage"
printf '#!/bin/sh\necho not a plain layout\n' >"$garbage/dot"
chmod +x "$garbage/dot"
out=$(SPEC_WALKTHROUGH_DOT="$garbage/dot" "$script" "$bundle" 2>&1) \
  || fail "graphviz-garbage run should still succeed (degrade)"
[ "$(field GRAPHMETA 4)" = builtin ] \
  || fail "garbage dot output must degrade to layout=builtin (REQ-E1.3)"

# 8c. Graphviz present but slow past the bound (REQ-E1.3 "timeout"): a dot that
#     would emit a VALID layout but only after sleeping longer than the bound is
#     killed by the watchdog and degrades to the built-in layout. The stub sleeps
#     2s and then prints a valid -Tplain; with a 1s bound it must never reach the
#     graphviz layout. (Without the watchdog this would wait 2s and pick
#     layout=graphviz — the assertion below is what catches a missing bound.)
slow="$tmp/gv-slow"
mkdir -p "$slow"
cat >"$slow/dot" <<'STUB'
#!/bin/sh
sleep 2
cat <<'PLAIN'
graph 1.0 6.0 2.0
node 1 0.5 1.0 1.2 0.5 t1 solid box black lightgrey
node 2 2.5 1.5 1.2 0.5 t2 solid box black lightgrey
node 3 2.5 0.5 1.2 0.5 t3 solid box black lightgrey
node 4 4.5 1.0 1.2 0.5 t4 solid box black lightgrey
stop
PLAIN
STUB
chmod +x "$slow/dot"
out=$(SPEC_WALKTHROUGH_DOT="$slow/dot" SPEC_WALKTHROUGH_DOT_TIMEOUT=1 "$script" "$bundle" 2>&1) \
  || fail "graphviz-slow run should still succeed (degrade)"
[ "$(field GRAPHMETA 4)" = builtin ] \
  || fail "a dot exceeding the time bound must degrade to layout=builtin (REQ-E1.3 timeout)"

# Restore the force-builtin override for the remaining cases.
SPEC_WALKTHROUGH_DOT=dot-not-installed-xyz
export SPEC_WALKTHROUGH_DOT

# ---------------------------------------------------------------------------
# 9. A bundle with no task graph degrades to an empty-graph note (exit 0).
# ---------------------------------------------------------------------------
notasks="$tmp/specs/notasks"
mkdir -p "$notasks"
cat >"$notasks/requirements.md" <<'EOF'
# Only requirements

**Status:** Draft
**Format-version:** 1

## REQ-A — group

- **REQ-A1.1** A thing SHALL exist. *(Cites: D-1.)*
EOF
run_dir 0 "$notasks"
[ "$(rec GRAPHNODE | wc -l | tr -d ' ')" -eq 0 ] || fail "empty-graph bundle emitted nodes"
[ -n "$(rec GRAPHNOTE)" ] || fail "empty-graph bundle should still emit a note"

# ---------------------------------------------------------------------------
# 10. Missing dir fails closed (exit 2); read-only.
# ---------------------------------------------------------------------------
run_dir 2 "$tmp/specs/does-not-exist"
if command -v git >/dev/null 2>&1; then
  gws="$tmp/gitws"
  mkdir -p "$gws/specs"
  make_bundle "$gws/specs/demo"
  (
    cd "$gws"
    git init -q
    git config user.email t@e.x
    git config user.name t
    git add -A
    git -c commit.gpgsign=false commit -qm init
  )
  (cd "$gws" && "$script" "specs/demo" >/dev/null)
  status_after=$(cd "$gws" && git status --porcelain)
  [ -z "$status_after" ] || fail "spec-graph was not read-only; git status: $status_after"
fi

# ---------------------------------------------------------------------------
# 11. Real bundle: the view runs and its critical path matches the selector.
# ---------------------------------------------------------------------------
out=$("$script" "$repo_root/specs/spec-comprehension" 2>&1) || fail "real bundle run failed"
real_crit=$(field GRAPHCRIT 2)
real_sel=$(/bin/sh "$sel" --critical-path "$repo_root/specs/spec-comprehension" \
  | awk '{printf (NR>1?" ":"") $0} END{print ""}')
[ "$real_crit" = "$real_sel" ] \
  || fail "real bundle: graph crit [$real_crit] != selector [$real_sel]"

echo "PASS: test-spec-graph.sh"
