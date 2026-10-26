#!/bin/sh
# inception-gate.sh — the mechanical half of the /inception gate move and of
# graduation (inception REQ-E1.1–E1.6, REQ-F1.1–F1.3, REQ-J1.5, REQ-J1.6 ·
# D-14, D-15).
#
#   evaluate [--track <label>] <venture>
#                         the minimum-core evaluation, the completeness check,
#                         and the kill-criteria states, plus the record lines a
#                         gate run would write
#   record --outcome <Graduate|Hold|Recycle|Kill> --decider <name>
#          --rationale <text> [--tracks <label>=<outcome>,...] <venture>
#                         write the gate record, the status it implies, track
#                         annotations, and the changelog entries
#   seed --dest <spec-root> [--track <label>] <venture>
#                         package a graduated scope as a /spec-draft seed under
#                         <spec-root>/_pending/ and record its lineage;
#                         <spec-root> is the destination repository's
#                         resolved spec root (scripts/resolve-root.sh)
#   link --spec <spec-dir> [--track <label>] <venture>
#                         name the spec a seed spawned, once that spec cites
#                         the venture back
#   lineage [--spec <spec-dir>]... <venture>
#                         check both lineage directions for every graduated
#                         scope
#   archive --note <text> [--abandon] <venture>
#                         the post-mortem of a killed venture, or the
#                         operator's abandonment of a live one; refreshes the
#                         registry row and drops the post-mortem as an
#                         observation
#
# The outcome is always the caller's: nothing here picks one, a tripped kill
# criterion only prints a `prompt` line, and Graduate is refused while the
# evaluation names a gap. Nothing here invokes /spec-draft or any other skill,
# commits, or pushes: the skill saves through inception-venture.sh save, and
# the human takes the seed to /spec-draft (REQ-J1.6).
#
# <venture> is a directory (any argument holding a `/`, or `.`) or a venture
# identifier under ventures_root. A scope is `venture` in an untracked venture
# and a track label in a tracked one; its lineage key, which the spawned spec
# cites in its Sources, is `inception:<id>` or `inception:<id>/<label>`.
# Locations recorded in the bundle are relative to the venture when inside it
# and `<repo>:<path>` otherwise (<repo> being the destination repository's
# directory name), never a machine path.
#
# Output lines (key<TAB>fields):
#   status <status> · scope venture|track <label> · decider <name>
#   next-gate <n> · core met|unmet · gap <kind> [<id>|<count> [<detail>]]
#   fork <DEC-n> open <door> · complete yes|no · unmapped <A-n>
#   orphan <T-n> · kill <KC-n> <date> clear|approaching|tripped
#   prompt kill-or-rescope <KC-n> · admissible <outcome> yes|no
#   evidence|thresholds|kill-criteria <record line>
#   track <label> live|done                                      evaluate
#   recorded <n> <outcome> · status <old> <new> · track <label> graduated|ended
#                                                                record
#   seed <path> · lineage <scope> pending · cite <Sources entry>  seed
#   lineage <scope> pending|linked|unchecked|spec-missing|spec-side-missing|
#     venture-side-missing|refused (an in-venture location that is absolute,
#     climbs with `..`, or resolves outside the venture)         lineage, link
#   archived <status> · registry refreshed · observation dropped
#   degraded <why>                                               archive
# Gap kinds: elicitation-pending, bundle-findings, metric-missing,
#   kill-criteria-missing, blocking-unresolved, blocking-invalidated,
#   synthetic-desirability, fork-open-one-way. Bundle text loses tabs and its
#   C0 and encoded C1 controls before it is printed or written to a seed.
#
# Every write stages the five files, applies the change, validates the staged
# bundle, and moves only the changed files in, under the venture's bundle
# lock; a change that would add a validator finding writes nothing. A gate
# record also needs the bundle clean beforehand.
#
# Exit: 0 success · 1 refused (an inadmissible outcome, a decider who is not
#   the gate decider, an uncovered or unknown track, a closed venture, a scope
#   not graduated or already seeded, a refused path, a lineage finding, a
#   validator finding the change would add) · 2 usage or environment error ·
#   3 the validator refuses to read the bundle (passed through).
#
# Environment: PLANWRIGHT_INCEPTION_TODAY (YYYY-MM-DD) pins today's date.
#
# Portable POSIX sh + awk; bash 3.2 / BSD tooling floor (REQ-K1.5).
set -u

LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
unset GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_NAMESPACE

self_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
VALIDATE="$self_dir/inception-validate.sh"
RENDER="$self_dir/inception-render.sh"
VENTURE="$self_dir/inception-venture.sh"
REGISTRY="$self_dir/inception-registry.sh"

for lib in echo-safety.sh spec-parse.sh lock-lib.sh; do
  if [ ! -f "$self_dir/$lib" ] || [ ! -r "$self_dir/$lib" ]; then
    printf '%s\n' "inception-gate: required helper $self_dir/$lib missing or not readable" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$self_dir/echo-safety.sh"
# shellcheck source=scripts/spec-parse.sh
. "$self_dir/spec-parse.sh" || exit 2
# shellcheck source=scripts/lock-lib.sh
. "$self_dir/lock-lib.sh" || exit 2

FILES='brief.md disciplines.md assumptions.md decisions.md plan.md'
OUTCOMES='Graduate Hold Recycle Kill'
MAXLEN=1000

usage() {
  cat >&2 <<'EOF'
usage: inception-gate.sh evaluate [--track <label>] <venture>
       inception-gate.sh record --outcome <Graduate|Hold|Recycle|Kill> --decider <name>
                                --rationale <text> [--tracks <label>=<outcome>,...] <venture>
       inception-gate.sh seed --dest <spec-root> [--track <label>] <venture>
       inception-gate.sh link --spec <spec-dir> [--track <label>] <venture>
       inception-gate.sh lineage [--spec <spec-dir>]... <venture>
       inception-gate.sh archive --note <text> [--abandon] <venture>
EOF
  exit 2
}

die() {
  _code=$1
  shift
  printf 'inception-gate: %s\n' "$*" >&2
  exit "$_code"
}

work=
moving=
seed_tmp=
seed_placed=
made_pdir=
made_droot=
cleanup() {
  # An exit in the middle of an install puts back what it had moved.
  [ -z "$moving" ] || restore_moved
  if [ -n "$work" ] && [ -f "$work/tmps" ]; then
    cut -f2 "$work/tmps" | while IFS= read -r _t; do rm -f "$_t"; done
  fi
  [ -z "$seed_tmp" ] || rm -f "$seed_tmp"
  [ -z "$seed_placed" ] || rm -f "$seed_placed"
  # Only directories this run created, and only while still empty.
  [ -z "$made_pdir" ] || rmdir "$made_pdir" 2>/dev/null
  [ -z "$made_droot" ] || rmdir "$made_droot" 2>/dev/null
  [ -z "$work" ] || rm -rf "$work"
  pw_lock_release_all
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

work=$(mktemp -d "${TMPDIR:-/tmp}/inception-gate.XXXXXX") || die 2 "cannot create a scratch directory"

# strip_eval — bundle text on its way out: NUL, C0 controls but tab and newline,
# DEL, and the UTF-8 encodings of the C1 controls go (the fan-out's rule).
# Raw 0x80-0x9F bytes stay, being the continuation bytes of ordinary UTF-8
# text, the em dash among them.
# shellcheck disable=SC2016 # awk source, not a shell expansion
strip_eval() { tr -d '\000' | awk '{ gsub(/[\001-\010\013-\037\177]/, ""); gsub(/\302[\200-\237]/, ""); print }'; }

today() {
  case ${PLANWRIGHT_INCEPTION_TODAY:-} in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) printf '%s\n' "$PLANWRIGHT_INCEPTION_TODAY" ;;
    '') date +%Y-%m-%d ;;
    *) die 2 "PLANWRIGHT_INCEPTION_TODAY must be YYYY-MM-DD" ;;
  esac
}

TODAY=$(today) || exit 2

# clean_value <value> <label> — a value that can sit on one line of the bundle.
clean_value() {
  case $1 in
    *[![:space:]]*) ;;
    *) die 2 "$2 is empty" ;;
  esac
  case $1 in
    *[[:cntrl:]]*) die 1 "$2 carries a control character" ;;
  esac
  [ "${#1}" -le "$MAXLEN" ] || die 1 "$2 is longer than $MAXLEN characters"
}

check_label() {
  printf '%s\n' "$1" | grep -Eq '^[a-z0-9][a-z0-9-]{0,31}$' \
    || die 2 "a track label must match ^[a-z0-9][a-z0-9-]*\$ (max 32): $(sanitize_printable "$1" '?')"
}

# resolve_venture <arg> — set vdir (canonical) and vid (its identifier).
resolve_venture() {
  case $1 in
    -*) die 2 "venture must be a directory or an identifier: $(sanitize_printable "$1" '?')" ;;
    . | */*) _vd=$1 ;;
    *)
      "$VENTURE" check-id "$1" >/dev/null 2>&1 \
        || die 2 "not a venture identifier: $(sanitize_printable "$1" '?')"
      _root=$("$VENTURE" root 2>/dev/null) || die 2 "cannot resolve ventures_root"
      _vd="$_root/$1"
      ;;
  esac
  [ -d "$_vd" ] || die 2 "no venture directory at $(sanitize_printable "$_vd" '?')"
  # The argument is checked too: command substitution drops a trailing
  # newline, so a path ending in one would resolve to its sibling.
  case $_vd in
    *[[:cntrl:]]*) die 2 "the venture path holds a control character, which this helper cannot carry" ;;
  esac
  vdir=$(cd -P "$_vd" && pwd -P) || die 2 "cannot enter the venture directory"
  for _f in $FILES; do
    [ ! -L "$vdir/$_f" ] || die 1 "$_f is a symbolic link; refusing to read or write through it"
  done
  # Paths are kept in tab-separated scratch lists, so no control character,
  # tab or newline included, may appear in the venture's path.
  case $vdir in
    *[[:cntrl:]]*) die 2 "the venture path holds a control character, which this helper cannot carry" ;;
  esac
  vid=$(basename "$vdir")
  "$VENTURE" check-id "$vid" >/dev/null 2>&1 \
    || die 2 "the venture directory is not named for a venture identifier: $(sanitize_printable "$vid" '?')"
}

# validate_live — validate the venture once per run: a fail-closed refusal
# (an unsupported or unparseable format-version) is passed through, and the
# findings are kept for the gap count and the staged comparison.
validate_live() {
  "$VALIDATE" "$vdir" >"$work/vlive" 2>&1
  vlive_rc=$?
  case $vlive_rc in
    0 | 1) ;;
    3)
      strip_eval <"$work/vlive" >&2
      exit 3
      ;;
    *) die 2 "the validator could not check the bundle (exit $vlive_rc)" ;;
  esac
  grep ' ERROR ' "$work/vlive" | sort >"$work/v.before"
}

bundle_lock() {
  if [ -d "$vdir/.git" ]; then _bl="$vdir/.git/planwright-bundle.lock"; else _bl="$vdir/.planwright-bundle.lock"; fi
  pw_lock_acquire "$_bl" "${PLANWRIGHT_BUNDLE_LOCK_TRIES:-500}"
  case $? in
    0) ;;
    1) die 2 "the bundle is busy (another writer holds its lock); try again" ;;
    *) die 2 "cannot take the bundle lock" ;;
  esac
}

# --- readers -----------------------------------------------------------------

# Register entries: `E id title`, `F id field value` (continuation lines
# joined), `O id option` for each Options sub-bullet.
# shellcheck disable=SC2016 # awk source, not a shell expansion
REG_AWK='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function flush() { if (fld != "") { gsub(/\t/, " ", val); print "F\t" id "\t" fld "\t" val }; fld = "" }
/^#/ {
  flush(); in_e = 0
  if ($0 ~ /^### /) {
    h = substr($0, 5); id = h; sub(/ .*$/, "", id)
    t = h; sub(/^[^ ]+ — /, "", t); gsub(/\t/, " ", t)
    if (id ~ /^(A|DEC|T)-[1-9][0-9]*$/) { in_e = 1; print "E\t" id "\t" trim(t) }
  }
  next
}
!in_e { next }
/^- \*\*[^*]+:\*\*/ {
  flush()
  fld = $0; sub(/^- \*\*/, "", fld); sub(/:\*\*.*$/, "", fld)
  val = $0; sub(/^- \*\*[^*]+:\*\*[ ]*/, "", val); val = trim(val)
  next
}
fld == "Options" && /^  +- / { s = $0; sub(/^ +- /, "", s); gsub(/\t/, " ", s); print "O\t" id "\t" trim(s); next }
/^  / && fld != "" { val = val " " trim($0); next }
{ flush() }
END { flush() }
'

# brief.md: TITLE, S <section>, OPP <field> <value>, TXT <section>
# <line>, DECIDER, KC <id> <superseded 0|1>, TRACK <label> <done 0|1> <text>,
# SRC <raw line>, G <n> <key> <value>, LIN <scope> <gate> <seed> <spec>.
# shellcheck disable=SC2016 # awk source, not a shell expansion
BRIEF_AWK='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function out(s) { gsub(/\t/, " ", s); return s }
function flusho() { if (of != "") print "OPP\t" of "\t" out(ov); of = "" }
function flushg() { if (gk != "") print "G\t" gn "\t" gk "\t" out(gv); gk = "" }
NR == 1 && /^# / { t = substr($0, 3); sub(/ — Brief[ \t]*$/, "", t); print "TITLE\t" out(trim(t)) }
/^## / { flusho(); flushg(); gn = ""; sect = trim(substr($0, 4)); print "S\t" out(sect); next }
sect == "Opportunity" && /^- \*\*[^*]+:\*\*/ {
  flusho(); of = $0; sub(/^- \*\*/, "", of); sub(/:\*\*.*$/, "", of)
  ov = $0; sub(/^- \*\*[^*]+:\*\*[ ]*/, "", ov); ov = trim(ov); next
}
sect == "Opportunity" && /^  / && of != "" { ov = ov " " trim($0); next }
sect == "Opportunity" { flusho(); next }
(sect == "Success metric" || sect == "Appetite") && /[^ \t]/ { print "TXT\t" sect "\t" out(trim($0)); next }
sect == "Kill criteria" && /^\*\*Gate decider:\*\* / { v = $0; sub(/^\*\*Gate decider:\*\* */, "", v); print "DECIDER\t" out(trim(v)); next }
sect == "Kill criteria" && /^- \*\*KC-[1-9][0-9]*:\*\*/ {
  id = $0; sub(/^- \*\*/, "", id); sub(/:\*\*.*$/, "", id)
  print "KC\t" id "\t" ($0 ~ /\*\*Superseded-by:\*\*/ ? 1 : 0); next
}
sect == "Tracks" && /^- \*\*[^*]+\*\*/ {
  lb = $0; sub(/^- \*\*/, "", lb); sub(/\*\*.*$/, "", lb)
  rest = $0; sub(/^- \*\*[^*]+\*\*[ ]*(— )?/, "", rest)
  print "TRACK\t" lb "\t" ((rest ~ / — graduated [0-9]/ || rest ~ / — ended [0-9]/) ? 1 : 0) "\t" out(rest); next
}
sect == "Sources" && /[^ \t]/ { print "SRC\t" out($0); next }
sect == "Gate log" && /^### Gate [1-9][0-9]* / { flushg(); gn = $3; next }
sect == "Gate log" && gn != "" && gk == "Rationale" && /[^ \t]/ { gv = gv " " trim($0); next }
sect == "Gate log" && gn != "" && /^[A-Z][A-Za-z-]*: / {
  flushg(); gk = substr($0, 1, index($0, ":") - 1); gv = trim(substr($0, index($0, ":") + 1))
  if (gk != "Rationale") flushg()
  next
}
sect == "Lineage" && /^- \*\*[^*]+\*\* — Gate / {
  n = split($0, P, " — ")
  sc = P[1]; sub(/^- \*\*/, "", sc); sub(/\*\*$/, "", sc)
  g = P[2]; sub(/^Gate /, "", g)
  sd = P[3]; sub(/^seed: `/, "", sd); sub(/`$/, "", sd)
  sp = P[4]; sub(/^spec: /, "", sp); gsub(/`/, "", sp)
  print "LIN\t" sc "\t" g "\t" out(sd) "\t" out(sp); next
}
sect == "Changelog" && /^- [0-9-]+ — post-mortem: / { print "POSTMORTEM\t1"; next }
END { flusho(); flushg() }
'

read_brief() { awk "$spec_parse_awk_fence$BRIEF_AWK" "$1/brief.md"; }
read_regs() {
  for _f in assumptions.md decisions.md plan.md; do
    awk "$spec_parse_awk_fence$REG_AWK" "$1/$_f" || return 1
  done
}

# gather — the validated bundle's reader output in $work/all.
gather() {
  validate_live
  _st=$(spec_parse_header_value "$vdir/brief.md" Status) || die 2 "cannot read the venture status"
  {
    printf 'STATUS\t%s\n' "$_st" && read_brief "$vdir" && read_regs "$vdir"
  } >"$work/all" || die 2 "cannot read the bundle"
}

# gather_gate — what only an evaluation reads, added to $work/all: the
# renderer's kill-criteria states, the validator's finding count, and the
# elicitation's leftover pending markers.
gather_gate() {
  if ! "$RENDER" --mode status "$vdir" >"$work/render" 2>"$work/render.err"; then
    printf 'inception-gate: the renderer could not read the kill criteria:\n' >&2
    strip_eval <"$work/render.err" >&2
    exit 2
  fi
  grep '^kill	' "$work/render" >>"$work/all"
  printf 'BADN\t%s\n' "$(grep -c . "$work/v.before")" >>"$work/all"
  _pend=0
  for _f in $FILES; do
    _n=$(grep -c '_Pending: not yet elicited\._' "$vdir/$_f")
    _pend=$((_pend + _n))
  done
  printf 'PEND\t%s\n' "$_pend" >>"$work/all"
}

# The evaluation over $work/all. scope is a track label or empty; the record
# lines (evidence, thresholds, kill-criteria) always cover the whole venture,
# which is what the validator's coverage rules read.
# shellcheck disable=SC2016 # awk source, not a shell expansion
EVAL_AWK='
BEGIN { FS = "\t"; split("synthetic opinion stated-intent costly-signal behavior", GL, " "); for (i in GL) GR[GL[i]] = 1 }
$1 == "E" { EO[++ne] = $2; ET[$2] = $3; next }
$1 == "F" { V[$2 SUBSEP $3] = $4; H[$2 SUBSEP $3] = 1; next }
$1 == "STATUS" { status = $2; next }
$1 == "TXT" && $2 == "Success metric" { metric = metric $3; next }
$1 == "KC" { if ($3 == 0) kclive++; next }
$1 == "DECIDER" { decider = $2; next }
$1 == "TRACK" { TL[++nt] = $2; TD[$2] = $3; next }
$1 == "G" { if ($2 + 0 > maxg) maxg = $2 + 0; next }
$1 == "kill" { nk++; KI[nk] = $2; KDT[nk] = $3; KS[nk] = $4; next }
$1 == "PEND" { pend = $2 + 0; next }
$1 == "BADN" { badn = $2 + 0; next }
function live(id) { return (id in ET) && !((id SUBSEP "Superseded-by") in H) }
function inscope(id) { return scope == "" || !((id SUBSEP "Track") in H) || V[id SUBSEP "Track"] == scope }
function st(id,   w) { split(V[id SUBSEP "Status"], w, " "); return w[1] }
function grade(id,   w) { split(V[id SUBSEP "Evidence"], w, " "); return (w[1] in GR) ? w[1] : "none" }
function has_item(list, x,   n, a, i) {
  n = split(list, a, ",")
  for (i = 1; i <= n; i++) { gsub(/^ +| +$/, "", a[i]); if (a[i] == x) return 1 }
  return 0
}
function usable(t) { return live(t) && st(t) != "dropped" }
function verdict(s) { return s == "validated" ? "pass" : s == "invalidated" ? "fail" : s == "waived" ? "waived" : "open" }
function join(s, x) { return s == "" ? x : s ", " x }
END {
  print "status\t" status
  print "scope\t" (scope == "" ? "venture" : "track " scope)
  print "decider\t" decider
  print "next-gate\t" (maxg + 1)

  if (pend > 0) GAP[++ng] = "elicitation-pending\t" pend
  if (badn > 0) GAP[++ng] = "bundle-findings\t" badn
  if (metric == "" || metric ~ /^_(Pending|Skipped):/) GAP[++ng] = "metric-missing"
  if (kclive == 0) GAP[++ng] = "kill-criteria-missing"
  for (i = 1; i <= ne; i++) {
    id = EO[i]
    if (id !~ /^A-/ || !live(id) || !inscope(id)) continue
    s = st(id); tag = V[id SUBSEP "Risk-tag"]
    if (V[id SUBSEP "Blocking"] == "yes") {
      if (s == "open" || s == "testing") GAP[++ng] = "blocking-unresolved\t" id "\t" s
      else if (s == "invalidated") GAP[++ng] = "blocking-invalidated\t" id
    }
    if (s == "validated" && grade(id) == "synthetic" && (tag == "value" || tag == "usability"))
      GAP[++ng] = "synthetic-desirability\t" id
  }
  for (i = 1; i <= ne; i++) {
    id = EO[i]
    if (id !~ /^DEC-/ || !live(id) || !inscope(id) || st(id) != "open") continue
    if (V[id SUBSEP "Door"] == "one-way") GAP[++ng] = "fork-open-one-way\t" id
    else FORK[++nf] = id "\topen\t" V[id SUBSEP "Door"]
  }
  for (i = 1; i <= ng; i++) print "gap\t" GAP[i]
  print "core\t" (ng ? "unmet" : "met")
  for (i = 1; i <= nf; i++) print "fork\t" FORK[i]

  complete = 1
  for (i = 1; i <= ne; i++) {
    a = EO[i]
    if (a !~ /^A-/ || !live(a) || !inscope(a) || V[a SUBSEP "Blocking"] != "yes" || st(a) == "waived") continue
    mapped = 0
    for (j = 1; j <= ne; j++) {
      t = EO[j]
      if (t !~ /^T-/ || !usable(t)) continue
      if (has_item(V[t SUBSEP "Tests"], a) || has_item(V[a SUBSEP "Tasks"], t)) { mapped = 1; break }
    }
    if (!mapped) { print "unmapped\t" a; complete = 0 }
  }
  for (i = 1; i <= ne; i++) {
    t = EO[i]
    if (t !~ /^T-/ || !usable(t) || !inscope(t)) continue
    traced = 0
    n = split(V[t SUBSEP "Tests"], TT, ",")
    for (k = 1; k <= n; k++) { x = TT[k]; gsub(/^ +| +$/, "", x); if (x ~ /^(A|DEC)-/ && live(x)) traced = 1 }
    if (!traced) { print "orphan\t" t; complete = 0 }
  }
  print "complete\t" (complete ? "yes" : "no")

  kc = ""
  for (i = 1; i <= nk; i++) {
    print "kill\t" KI[i] "\t" KDT[i] "\t" KS[i]
    kc = join(kc, KI[i] " " KS[i])
  }
  for (i = 1; i <= nk; i++) if (KS[i] == "tripped") print "prompt\tkill-or-rescope\t" KI[i]

  print "admissible\tGraduate\t" ((ng == 0 && complete) ? "yes" : "no")
  print "admissible\tHold\tyes"
  print "admissible\tRecycle\tyes"
  print "admissible\tKill\tyes"

  ev = ""; th = ""
  for (i = 1; i <= ne; i++) {
    a = EO[i]
    if (a !~ /^A-/ || !live(a)) continue
    g = grade(a)
    if (g != "none") ev = join(ev, a " (" g ")")
    if (g != "none" || V[a SUBSEP "Blocking"] == "yes") th = join(th, a " " verdict(st(a)))
  }
  print "evidence\t" (ev == "" ? "none" : ev)
  print "thresholds\t" (th == "" ? "none" : th)
  print "kill-criteria\t" (kc == "" ? "none" : kc)
  for (i = 1; i <= nt; i++) print "track\t" TL[i] "\t" (TD[TL[i]] ? "done" : "live")
}
'

# evaluate_into <scope> <out> — gather the venture, then evaluate it; scope is
# a track label, or empty for the whole venture (`venture` is a legal label).
evaluate_into() {
  gather
  gather_gate
  awk -v scope="$1" "$EVAL_AWK" "$work/all" >"$2" || die 2 "cannot evaluate the bundle"
}

ev() { awk -F'\t' -v k="$1" '$1 == k { sub(/^[^\t]*\t/, ""); print; exit }' "$2"; }

tracked() { grep -q '^TRACK	' "$work/all"; }

# --- writers -----------------------------------------------------------------

stage() {
  rm -rf "$work/stage" "$work/orig"
  mkdir -p "$work/stage" "$work/orig" || die 2 "cannot stage the bundle"
  for _f in $FILES; do
    if ! cp -p "$vdir/$_f" "$work/stage/$_f" || ! cp -p "$vdir/$_f" "$work/orig/$_f"; then
      die 2 "cannot stage $_f"
    fi
  done
}

# Where to write is decided by the shared fence lexer, so a fenced example
# of a heading or bullet is never mistaken for the real one; the writers below
# then edit by line number and copy every other line through untouched.
#
# locate <file> heading <section> — `<heading line> <next H2 line, or 0>`;
# locate <file> bullet <section> <prefix> — the first section line that starts
# with <prefix>, or 0.
# shellcheck disable=SC2016 # awk source, not a shell expansion
LOCATE_AWK='
/^## / {
  h = substr($0, 4); sub(/[ \t]+$/, "", h)
  if (insec && !endn) endn = NR
  insec = (h == sec)
  if (insec && !startn) startn = NR
  next
}
mode == "bullet" && insec && !hit && index($0, prefix) == 1 { hit = NR }
END { if (mode == "heading") print (startn + 0) " " (endn + 0); else print hit + 0 }
'
locate() {
  awk -v mode="$2" -v sec="$3" -v prefix="${4:-}" "$spec_parse_awk_fence$LOCATE_AWK" "$1" \
    || die 2 "cannot read $(basename "$1")"
}

# edit <file> <awk-program> [awk -v args...] — run a raw line program over a
# staged file in place.
edit() {
  _ef=$1
  _ep=$2
  shift 2
  if ! awk "$@" "$_ep" "$_ef" >"$_ef.new" || ! cat "$_ef.new" >"$_ef"; then
    die 2 "cannot rewrite $(basename "$_ef")"
  fi
  rm -f "$_ef.new"
}

# replace_line <file> <n> <text> — the text travels by the environment, since
# awk -v would rewrite its backslash escapes.
replace_line() {
  # shellcheck disable=SC2016 # awk source, not a shell expansion
  GATE_EDIT_TEXT=$3 edit "$1" 'NR == n { print ENVIRON["GATE_EDIT_TEXT"]; next } { print }' -v n="$2"
}

# insert_before <file> <n> <text-file>
insert_before() {
  # shellcheck disable=SC2016 # awk source, not a shell expansion
  edit "$1" 'NR == n { while ((getline l < tf) > 0) print l; close(tf) } { print }' -v n="$2" -v tf="$3"
}

# append_section <file> <section> <text-file> — add the text at the end of an
# H2 section, before its trailing blank lines.
append_section() {
  _at=$(locate "$1" heading "$2")
  [ "${_at% *}" -gt 0 ] || die 2 "$(basename "$1") has no ## $2 section"
  # shellcheck disable=SC2016 # awk source, not a shell expansion
  edit "$1" '
    { L[NR] = $0 }
    END {
      k = (end ? end - 1 : NR)
      while (k > start && L[k] ~ /^[ \t]*$/) k--
      for (i = 1; i <= k; i++) print L[i]
      while ((getline l < tf) > 0) print l
      if (end) { print ""; for (i = end; i <= NR; i++) print L[i] }
    }
  ' -v start="${_at% *}" -v end="${_at#* }" -v tf="$3"
}

set_status() {
  _sn=$(spec_parse_header_status_line "$1") || die 2 "cannot read the status of $(basename "$1")"
  [ "$_sn" -gt 0 ] || die 2 "$(basename "$1") declares no status"
  replace_line "$1" "$_sn" "**Status:** $2"
}

bump_reviewed() {
  # shellcheck disable=SC2016 # awk source, not a shell expansion
  edit "$1" '!done && /^\*\*Last reviewed:\*\* / { print "**Last reviewed:** " d; done = 1; next } { print }' -v d="$TODAY"
}

changelog() {
  printf '%s\n' "$2" >"$work/cl"
  append_section "$1" Changelog "$work/cl"
}

# validated_stage — refuse when the staged bundle carries a validator finding
# the live one does not.
validated_stage() {
  "$VALIDATE" "$work/stage" >"$work/vstage" 2>&1
  _vr=$?
  case $_vr in
    0 | 1) ;;
    *) die 2 "the validator could not check the changed bundle (exit $_vr); nothing was written" ;;
  esac
  grep ' ERROR ' "$work/vstage" | sort >"$work/v.after"
  comm -13 "$work/v.before" "$work/v.after" >"$work/v.added"
  if [ -s "$work/v.added" ]; then
    printf 'inception-gate: the change would add bundle findings; nothing was written:\n' >&2
    strip_eval <"$work/v.added" >&2
    exit 1
  fi
}

# install_files <file>... — move the named staged files into the venture,
# all of them or none.
install_files() {
  # Scratch names come from mktemp, never the pid: a predictable name in a
  # directory a commit can populate is one a planted symbolic link can claim.
  : >"$work/tmps"
  : >"$work/moved"
  for _f in "$@"; do
    _t=$(mktemp "$vdir/.inception-gate.XXXXXX") || die 2 "cannot write $_f; nothing was changed"
    printf '%s\t%s\n' "$_f" "$_t" >>"$work/tmps"
    cp -p "$work/stage/$_f" "$_t" || die 2 "cannot write $_f; nothing was changed"
  done
  # brief.md carries the gate record or the post-mortem, so it moves last: a
  # failure before it leaves the bundle as it was once the others are restored.
  moving=1
  for _f in $(printf '%s\n' "$@" | grep -v '^brief\.md$') $(printf '%s\n' "$@" | grep '^brief\.md$'); do
    _t=$(awk -F'\t' -v f="$_f" '$1 == f { print $2; exit }' "$work/tmps")
    # Recorded before the move, so an exit right after it restores this file
    # too; restoring one that never moved copies back the same bytes.
    printf '%s\n' "$_f" >>"$work/moved"
    if ! mv -f "$_t" "$vdir/$_f"; then
      restore_moved || die 2 "cannot write $_f, and the files already written could not all be restored"
      die 2 "cannot write $_f; the files already written were restored"
    fi
  done
  moving=
  : >"$work/tmps"
}

# restore_moved — put back every file an interrupted install had moved in;
# false, naming them, when one cannot be restored.
restore_moved() {
  moving=
  _rf=
  while IFS= read -r _m; do
    cp -p "$work/orig/$_m" "$vdir/$_m" || _rf="$_rf $_m"
  done <"$work/moved"
  [ -z "$_rf" ] && return 0
  printf 'inception-gate: could not restore%s; repair it from git or by hand\n' "$_rf" >&2
  return 1
}

# loc_of <dir> — the dir's location as the bundle records it: relative inside
# the venture, `<repo>:<path>` in another repository; false outside both.
loc_of() {
  case $1 in
    "$vdir") printf '.\n' ;;
    "$vdir"/*) printf '%s\n' "${1#"$vdir"/}" ;;
    *)
      if _top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) && _top=$(cd -P "$_top" && pwd -P); then
        case $1 in
          "$_top") printf '%s:.\n' "$(basename "$_top")" ;;
          *) printf '%s:%s\n' "$(basename "$_top")" "${1#"$_top"/}" ;;
        esac
      else
        return 1
      fi
      ;;
  esac
}

# loc_join <location> <relative path> — a path below a recorded location.
loc_join() {
  case $1 in
    .) printf '%s\n' "$2" ;;
    *:.) printf '%s%s\n' "${1%.}" "$2" ;;
    *) printf '%s/%s\n' "$1" "$2" ;;
  esac
}

# trim_slashes <path> — the path without trailing slashes, which would make a
# symbolic-link test follow the link it is meant to refuse, and with `./`
# before a leading dash, which cd would read as an option or as $OLDPWD.
trim_slashes() {
  _p=$1
  case $_p in
    -*) _p=./$_p ;;
  esac
  while :; do
    case $_p in
      ?*/) _p=${_p%/} ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$_p"
}

# check_dir_arg <path> <label> — a directory argument named directly: a
# final `.` or `..` would let the symbolic-link test look past the link.
check_dir_arg() {
  case $1 in
    . | .. | */. | */..) die 1 "$2 ends in a . or .. component; name the directory itself" ;;
  esac
}

check_path() {
  case $1 in
    *[[:cntrl:]\`\\]* | *' — '*) die 1 "$2 holds a control character, a backtick, a backslash, or a spaced em dash, which the lineage record cannot carry" ;;
  esac
}

# cites <spec-dir> <key> — the spec's requirements.md Sources names the key.
cites() {
  [ -f "$1/requirements.md" ] && [ ! -L "$1/requirements.md" ] || return 2
  # The key can be bundle text, so it travels by the environment: awk -v
  # would rewrite its backslash escapes.
  GATE_CITE_KEY=$2 awk '
    BEGIN { key = ENVIRON["GATE_CITE_KEY"] }
    /^## / { on = ($0 ~ /^## Sources[ \t]*$/); next }
    on {
      s = $0; o = 0
      while ((p = index(s, key)) > 0) {
        pv = o + p > 1 ? substr($0, o + p - 1, 1) : ""
        nx = substr(s, p + length(key), 1)
        if (pv !~ /[A-Za-z0-9_-]/ && nx !~ /[a-z0-9\/-]/) { found = 1; exit }
        o += p + length(key) - 1
        s = substr(s, p + length(key))
      }
    }
    END { exit found ? 0 : 1 }
  ' "$1/requirements.md"
}

# lineage_key <scope> — in a tracked venture every scope is a track, one
# labelled `venture` included.
lineage_key() {
  if tracked; then printf 'inception:%s/%s\n' "$vid" "$1"; else printf 'inception:%s\n' "$vid"; fi
}

# graduated_scopes — `scope<TAB>gate` for every scope a gate record graduated.
graduated_scopes() {
  awk -F'\t' '
    $1 == "G" && $3 == "Outcome" && $4 == "Graduate" { if (!tr) print "venture\t" $2 }
    $1 == "TRACK" { tr = 1 }
    $1 == "G" && $3 == "Tracks" {
      n = split($4, a, ",")
      for (i = 1; i <= n; i++) { x = a[i]; gsub(/^ +| +$/, "", x); if (x ~ /=Graduate$/) { sub(/=Graduate$/, "", x); print x "\t" $2 } }
    }
  ' "$work/all"
}

# --- evaluate ----------------------------------------------------------------

cmd_evaluate() {
  _track=
  while [ $# -gt 1 ]; do
    case $1 in
      --track)
        [ $# -ge 3 ] || usage
        check_label "$2"
        _track=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  [ $# -eq 1 ] || usage
  resolve_venture "$1"
  evaluate_into "$_track" "$work/eval"
  if [ -n "$_track" ]; then
    grep -q "^TRACK	$_track	" "$work/all" || die 1 "the brief declares no track $_track"
  fi
  strip_eval <"$work/eval"
}

# --- record ------------------------------------------------------------------

cmd_record() {
  _out='' _dec='' _rat='' _tracks='' _seen_tracks=''
  while [ $# -gt 1 ]; do
    case $1 in
      --outcome)
        [ $# -ge 3 ] || usage
        _out=$2
        shift 2
        ;;
      --decider)
        [ $# -ge 3 ] || usage
        _dec=$2
        shift 2
        ;;
      --rationale)
        [ $# -ge 3 ] || usage
        _rat=$2
        shift 2
        ;;
      --tracks)
        [ $# -ge 3 ] || usage
        _tracks=$2
        _seen_tracks=1
        shift 2
        ;;
      *) usage ;;
    esac
  done
  [ $# -eq 1 ] || usage
  case " $OUTCOMES " in
    *" $_out "*) ;;
    *) die 2 "the outcome must be one of: $OUTCOMES" ;;
  esac
  [ -n "$_dec" ] || die 2 "a gate record names its decider (--decider)"
  [ -n "$_rat" ] || die 2 "a gate record carries its rationale (--rationale)"
  clean_value "$_dec" "the decider"
  clean_value "$_rat" "the rationale"

  resolve_venture "$1"
  bundle_lock
  evaluate_into '' "$work/eval"
  if [ "$vlive_rc" -ne 0 ]; then
    printf 'inception-gate: the bundle has validator findings; a gate runs on a clean bundle:\n' >&2
    strip_eval <"$work/v.before" >&2
    exit 1
  fi
  _old=$(ev status "$work/eval")
  case $_old in
    Graduated | Killed | Abandoned) die 1 "the venture is $_old; a closed venture takes no further gate run" ;;
  esac
  _gd=$(ev decider "$work/eval")
  [ "$_dec" = "$_gd" ] \
    || die 1 "the decider must be the venture's gate decider, $(sanitize_printable "$_gd" '?'); record the call that person made"
  if [ "$_out" = Graduate ] && [ "$(awk -F'\t' '$1 == "admissible" && $2 == "Graduate" { print $3 }' "$work/eval")" != yes ]; then
    printf 'inception-gate: Graduate is not admissible; the evaluation names:\n' >&2
    grep -E '^(gap|unmapped|orphan)	' "$work/eval" | strip_eval >&2
    exit 1
  fi

  # Tracks: every live track exactly once, a valid outcome each.
  _tline=
  : >"$work/tr"
  awk -F'\t' '$1 == "track" && $3 == "live" { print $2 }' "$work/eval" >"$work/tr.live"
  if tracked && [ ! -s "$work/tr.live" ]; then
    # Every track has graduated or ended: the record closing the venture has
    # no track left to cover.
    [ -z "$_tracks" ] || die 1 "no track is live, so the record covers none; pass no --tracks"
    _tline=none
  elif tracked; then
    [ -n "$_seen_tracks" ] || die 1 "a tracked venture's record covers every live track (--tracks <label>=<outcome>,...)"
    printf '%s\n' "$_tracks" | tr ',' '\n' | sed 's/^ *//; s/ *$//' >"$work/tr.in"
    while IFS= read -r _it; do
      [ -n "$_it" ] || continue
      _lb=${_it%%=*}
      _to=${_it#*=}
      [ "$_lb" != "$_it" ] || die 2 "a tracks item is <label>=<outcome>: $(sanitize_printable "$_it" '?')"
      check_label "$_lb"
      case " $OUTCOMES " in
        *" $_to "*) ;;
        *) die 2 "track $_lb: the outcome must be one of: $OUTCOMES" ;;
      esac
      _state=$(awk -F'\t' -v l="$_lb" '$1 == "track" && $2 == l { print $3 }' "$work/eval")
      [ -n "$_state" ] || die 1 "the brief declares no track $_lb"
      [ "$_state" = live ] || die 1 "track $_lb is already graduated or ended; a record covers only live tracks"
      ! grep -q "^$_lb	" "$work/tr" || die 1 "track $_lb is named twice"
      printf '%s\t%s\n' "$_lb" "$_to" >>"$work/tr"
    done <"$work/tr.in"
    while IFS= read -r _lb; do
      grep -q "^$_lb	" "$work/tr" || die 1 "the record does not cover live track $_lb"
    done <"$work/tr.live"
    case $_out in
      Graduate | Kill)
        if awk -F'\t' '$2 != "Graduate" && $2 != "Kill" { f = 1 } END { exit !f }' "$work/tr"; then
          die 1 "a top-level $_out closes the venture, so every live track must graduate or end in the same record"
        fi
        ;;
    esac
    while IFS='	' read -r _lb _to; do
      [ "$_to" = Graduate ] || continue
      awk -v scope="$_lb" "$EVAL_AWK" "$work/all" >"$work/eval.$_lb" || die 2 "cannot evaluate track $_lb"
      if [ "$(awk -F'\t' '$1 == "admissible" && $2 == "Graduate" { print $3 }' "$work/eval.$_lb")" != yes ]; then
        printf 'inception-gate: track %s cannot graduate; the evaluation names:\n' "$_lb" >&2
        grep -E '^(gap|unmapped|orphan)	' "$work/eval.$_lb" | strip_eval >&2
        exit 1
      fi
    done <"$work/tr"
    _tline=$(awk -F'\t' '{ s = s (NR > 1 ? ", " : "") $1 "=" $2 } END { print s }' "$work/tr")
  elif [ -n "$_seen_tracks" ]; then
    die 1 "the venture declares no tracks, so its record carries no tracks line"
  fi

  _d=$TODAY
  _n=$(ev next-gate "$work/eval")
  {
    printf '\n### Gate %s — %s\n\n' "$_n" "$_d"
    printf 'Outcome: %s\nDate: %s\nDecider: %s\n' "$_out" "$_d" "$_dec"
    printf 'Evidence: %s\n' "$(ev evidence "$work/eval")"
    printf 'Thresholds: %s\n' "$(ev thresholds "$work/eval")"
    printf 'Kill-criteria: %s\n' "$(ev kill-criteria "$work/eval")"
    [ -z "$_tline" ] || printf 'Tracks: %s\n' "$_tline"
    printf 'Rationale: %s\n' "$_rat"
  } >"$work/block"

  case $_out in
    Graduate) _new=Graduated ;;
    Hold) _new=On-hold ;;
    Recycle) _new=Exploring ;;
    Kill) _new=Killed ;;
  esac

  stage
  append_section "$work/stage/brief.md" "Gate log" "$work/block"
  while IFS='	' read -r _lb _to; do
    case $_to in
      Graduate) _suf=" — graduated $_d" ;;
      Kill) _suf=" — ended $_d (killed at Gate $_n)" ;;
      *) continue ;;
    esac
    _tn=$(locate "$work/stage/brief.md" bullet Tracks "- **$_lb**")
    [ "$_tn" -gt 0 ] || die 2 "the brief declares no track bullet for $_lb"
    replace_line "$work/stage/brief.md" "$_tn" "$(sed -n "${_tn}p" "$work/stage/brief.md")$_suf"
  done <"$work/tr"
  changelog "$work/stage/brief.md" "- $_d — Gate $_n recorded ($_out)."
  _changed=brief.md
  if [ "$_new" != "$_old" ]; then
    changelog "$work/stage/brief.md" "- $_d — status $_old → $_new (Gate $_n)."
    for _f in $FILES; do
      set_status "$work/stage/$_f" "$_new"
      [ "$_f" = brief.md ] || bump_reviewed "$work/stage/$_f"
    done
    _changed=$FILES
  fi
  bump_reviewed "$work/stage/brief.md"
  validated_stage
  # shellcheck disable=SC2086 # the file list is fixed words
  install_files $_changed

  printf 'recorded\t%s\t%s\n' "$_n" "$_out"
  [ "$_new" = "$_old" ] || printf 'status\t%s\t%s\n' "$_old" "$_new"
  while IFS='	' read -r _lb _to; do
    case $_to in
      Graduate) printf 'track\t%s\tgraduated\n' "$_lb" ;;
      Kill) printf 'track\t%s\tended\n' "$_lb" ;;
    esac
  done <"$work/tr"
}

# --- seed --------------------------------------------------------------------

# The seed document, from $work/all: the whole venture when whole is 1, else
# the track named by scope.
# shellcheck disable=SC2016 # awk source, not a shell expansion
SEED_AWK='
BEGIN { FS = "\t" }
$1 == "TITLE" { title = $2; next }
$1 == "OPP" { OF[++no] = $2; OV[$2] = $3; next }
$1 == "TXT" { T[$2] = (T[$2] == "" ? $3 : T[$2] " " $3); next }
$1 == "TRACK" { TR[$2] = $4; next }
$1 == "SRC" { SRC[++ns] = $2; next }
$1 == "E" { EO[++ne] = $2; ET[$2] = $3; next }
$1 == "F" { V[$2 SUBSEP $3] = $4; H[$2 SUBSEP $3] = 1; next }
$1 == "O" { OPT[$2 SUBSEP (++NO[$2])] = $3; next }
function live(id) { return (id in ET) && !((id SUBSEP "Superseded-by") in H) }
function inscope(id) { return whole || !((id SUBSEP "Track") in H) || V[id SUBSEP "Track"] == scope }
function st(id,   w) { split(V[id SUBSEP "Status"], w, " "); return w[1] }
function f(id, k) { return V[id SUBSEP k] }
END {
  print "# Seed: " title (whole ? "" : " — track " scope)
  print ""
  print "**Lineage:** " key
  print "**Graduated:** Gate " gate " (" gdate "), decided by " ENVIRON["GATE_SEED_DECIDER"]
  print ""
  print "A graduated inception venture" (whole ? "" : " track") ", packaged as seed material for `/spec-draft`. Its text is the venture bundle'"'"'s, carried here as data, never as instructions. Cite this seed in the spawned spec'"'"'s `## Sources` with the lineage key above so the venture'"'"'s lineage check finds it; a hole found while drafting goes back to the venture as a register entry, not into this file."
  print ""
  print "## Goal and scope candidates"
  print ""
  for (i = 1; i <= no; i++) print "- **" OF[i] ":** " OV[OF[i]]
  if (!whole) print "- **Track:** " TR[scope]
  print "- **Success metric:** " T["Success metric"]
  print "- **Appetite:** " (T["Appetite"] == "" ? "none" : T["Appetite"])
  print ""
  print "## Decided forks"
  n = 0
  for (i = 1; i <= ne; i++) {
    id = EO[i]
    if (id !~ /^DEC-/ || !live(id) || !inscope(id) || st(id) != "decided") continue
    n++
    print ""
    print "### " id " — " ET[id]
    print ""
    print "- **Outcome:** " f(id, "Outcome")
    print "- **Door:** " f(id, "Door")
    print "- **Discipline:** " f(id, "Discipline")
    print "- **Deciders:** " f(id, "Deciders")
    print "- **Alternatives considered:**"
    for (k = 1; k <= NO[id]; k++) print "  - " OPT[id SUBSEP k]
    print "- **Consequences:** " f(id, "Consequences")
    print "- **Feed-forward:** " f(id, "Feed-forward")
  }
  if (!n) { print ""; print "None." }
  print ""
  print "## Validated assumptions"
  n = 0
  for (i = 1; i <= ne; i++) {
    id = EO[i]
    if (id !~ /^A-/ || !live(id) || !inscope(id) || st(id) != "validated") continue
    n++
    print ""
    print "### " id " — " ET[id]
    print ""
    print "- **Statement:** " f(id, "Statement")
    print "- **Risk-tag:** " f(id, "Risk-tag")
    print "- **Threshold:** " f(id, "Threshold")
    print "- **Evidence:** " f(id, "Evidence")
  }
  if (!n) { print ""; print "None." }
  print ""
  print "## Invalidated and waived assumptions"
  print ""
  n = 0
  for (i = 1; i <= ne; i++) {
    id = EO[i]
    if (id !~ /^A-/ || !live(id) || !inscope(id)) continue
    s = st(id)
    if (s == "invalidated") { n++; print "- **" id "** — " ET[id] ": invalidated (" f(id, "Evidence") ")" }
    else if (s == "waived") { n++; print "- **" id "** — " ET[id] ": " f(id, "Status") }
  }
  if (!n) print "None."
  print ""
  print "## Open questions"
  print ""
  n = 0
  for (i = 1; i <= ne; i++) {
    id = EO[i]
    if (id !~ /^DEC-/ || !live(id) || !inscope(id)) continue
    s = st(id)
    if (s == "open" || s == "deferred") { n++; print "- **" id " (" s ")** — " ET[id] ": " f(id, "Outcome") }
  }
  for (i = 1; i <= ne; i++) {
    id = EO[i]
    if (id !~ /^A-/ || !live(id) || !inscope(id)) continue
    s = st(id)
    if (s == "open" || s == "testing") { n++; print "- **" id " (" s ")** — " ET[id] ": " f(id, "Statement") }
  }
  if (!n) print "None."
  print ""
  print "## Sources"
  print ""
  for (i = 1; i <= ns; i++) print SRC[i]
  if (!ns) print "None."
  print ""
  print "## Suggested citation"
  print ""
  print "- **Venture " vid (whole ? "" : ", track " scope) "** — graduated inception seed (" key ", Gate " gate ", " gdate ") — `" sloc "`"
}
'

cmd_seed() {
  _dest='' _track=''
  while [ $# -gt 1 ]; do
    case $1 in
      --dest)
        [ $# -ge 3 ] || usage
        _dest=$2
        shift 2
        ;;
      --track)
        [ $# -ge 3 ] || usage
        check_label "$2"
        _track=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  [ $# -eq 1 ] && [ -n "$_dest" ] || usage
  resolve_venture "$1"
  bundle_lock
  gather
  if tracked; then
    [ -n "$_track" ] || die 1 "a tracked venture graduates by track; name it with --track"
    grep -q "^TRACK	$_track	" "$work/all" || die 1 "the brief declares no track $_track"
    _scope=$_track
  else
    [ -z "$_track" ] || die 1 "the venture declares no tracks"
    _scope=venture
  fi
  _gate=$(graduated_scopes | awk -F'\t' -v s="$_scope" '$1 == s { g = $2 } END { print g }')
  [ -n "$_gate" ] || die 1 "no gate record graduates $_scope; the seed follows a Graduate outcome"
  ! awk -F'\t' -v s="$_scope" '$1 == "LIN" && $2 == s { f = 1 } END { exit !f }' "$work/all" \
    || die 1 "$_scope already has a seed and lineage record"
  # Gate fields are bundle text: the first of each is the record's, and a
  # date that is not one never reaches the seed.
  _gdate=$(awk -F'\t' -v g="$_gate" '$1 == "G" && $2 == g && $3 == "Date" { print $4; exit }' "$work/all")
  _gdec=$(awk -F'\t' -v g="$_gate" '$1 == "G" && $2 == g && $3 == "Decider" { print $4; exit }' "$work/all")
  printf '%s\n' "$_gdate" | grep -Eqx '[0-9]{4}-[0-9]{2}-[0-9]{2}' \
    || die 1 "Gate $_gate carries no readable date"
  [ "$vlive_rc" -eq 0 ] || {
    printf 'inception-gate: the bundle has validator findings; a seed is packaged from a clean bundle:\n' >&2
    strip_eval <"$work/v.before" >&2
    exit 1
  }

  _dest=$(trim_slashes "$_dest")
  check_dir_arg "$_dest" "the destination"
  check_path "$_dest" "the destination"
  [ ! -L "$_dest" ] || die 1 "the destination is a symbolic link; name the directory itself"
  if [ -d "$_dest" ]; then
    # cd -P: a logical cd would collapse `link/..` textually and enter a
    # directory other than the one the symbolic-link test looked at.
    _droot=$(cd -P "$_dest" && pwd -P) || die 2 "cannot enter the destination"
  else
    [ ! -e "$_dest" ] || die 1 "the destination exists and is not a directory"
    [ -d "$(dirname "$_dest")" ] || die 1 "the destination's parent directory does not exist"
    _dp=$(cd -P "$(dirname "$_dest")" && pwd -P) || die 2 "cannot enter the destination's parent"
    _droot="$_dp/$(basename "$_dest")"
  fi
  check_path "$_droot" "the destination"
  # /spec-draft resolves a spec root only inside a repository, so a seed
  # anywhere else could not be gathered, nor its location recorded.
  _probe=$_droot
  [ -d "$_probe" ] || _probe=$(dirname "$_droot")
  git -C "$_probe" rev-parse --show-toplevel >/dev/null 2>&1 \
    || die 1 "the destination is not inside a git repository, so no spec can be drafted there"
  _pdir="$_droot/_pending"
  [ ! -L "$_pdir" ] || die 1 "the destination's _pending is a symbolic link; refusing to write through it"
  # A dot cannot appear in an identifier or a label, so no venture-and-track
  # pair can name another pair's seed.
  if tracked; then _name="inception-$vid.$_scope.md"; else _name="inception-$vid.md"; fi
  _seed="$_pdir/$_name"
  [ ! -e "$_seed" ] && [ ! -L "$_seed" ] || die 1 "a seed already exists at _pending/$_name"
  _ploc=$(loc_of "$_probe") || die 2 "cannot record the destination's location"
  [ "$_probe" = "$_droot" ] || _ploc=$(loc_join "$_ploc" "$(basename "$_droot")")
  _sloc=$(loc_join "$_ploc" "_pending/$_name")
  case $_sloc in
    *:*) _rel=${_sloc#*:} ;;
    *) _rel=$_sloc ;;
  esac
  _key=$(lineage_key "$_scope")

  # The decider is bundle text, so it travels by the environment: awk -v
  # would rewrite its backslash escapes.
  if tracked; then _whole=0; else _whole=1; fi
  GATE_SEED_DECIDER=$_gdec awk -v scope="$_scope" -v whole="$_whole" -v key="$_key" -v gate="$_gate" -v gdate="$_gdate" \
    -v vid="$vid" -v sloc="$_rel" "$SEED_AWK" "$work/all" >"$work/seed.raw" \
    || die 2 "cannot compose the seed"
  strip_eval <"$work/seed.raw" >"$work/seed" || die 2 "cannot compose the seed"

  stage
  _d=$TODAY
  # shellcheck disable=SC2016 # literal backticks in the bullet, not an expansion
  printf -- '- **%s** — Gate %s — seed: `%s` — spec: pending\n' "$_scope" "$_gate" "$_sloc" >"$work/lin"
  _at=$(locate "$work/stage/brief.md" heading Lineage)
  if [ "${_at% *}" -gt 0 ]; then
    append_section "$work/stage/brief.md" Lineage "$work/lin"
  else
    _at=$(locate "$work/stage/brief.md" heading Changelog)
    [ "${_at% *}" -gt 0 ] || die 2 "brief.md has no ## Changelog section"
    { printf '## Lineage\n\n' && cat "$work/lin" && printf '\n'; } >"$work/lin.sec" || die 2 "cannot stage the lineage section"
    insert_before "$work/stage/brief.md" "${_at% *}" "$work/lin.sec"
  fi
  changelog "$work/stage/brief.md" "- $_d — seed prepared for $_scope (Gate $_gate)."
  bump_reviewed "$work/stage/brief.md"
  validated_stage

  # Nothing is created in the destination until the bundle change has passed.
  [ -d "$_droot" ] || made_droot=$_droot
  [ -d "$_pdir" ] || made_pdir=$_pdir
  mkdir -p "$_pdir" || die 2 "cannot create the destination's _pending directory"
  [ ! -L "$_droot" ] && [ ! -L "$_pdir" ] || die 1 "the destination became a symbolic link; refusing to write through it"
  seed_tmp=$(mktemp "$_pdir/.inception-gate.XXXXXX") || die 2 "cannot write the seed"
  cp -p "$work/seed" "$seed_tmp" || die 2 "cannot write the seed"
  if ! ln "$seed_tmp" "$_seed" 2>/dev/null; then
    [ ! -e "$_seed" ] && [ ! -L "$_seed" ] || die 1 "a seed already exists at _pending/$_name"
    die 2 "cannot place the seed (the destination may not support hard links)"
  fi
  rm -f "$seed_tmp"
  seed_tmp=
  # Until the lineage is recorded, an exit removes the seed again.
  seed_placed=$_seed
  install_files brief.md
  seed_placed=
  made_pdir=
  made_droot=
  printf 'seed\t%s\n' "$_seed" | strip_eval
  printf 'lineage\t%s\tpending\n' "$_scope"
  printf 'cite\t%s\n' "$(tail -n 1 "$work/seed")" | strip_eval
}

# --- link / lineage ----------------------------------------------------------

spec_dir() {
  set -- "$(trim_slashes "$1")"
  check_dir_arg "$1" "the spec directory"
  check_path "$1" "the spec directory"
  [ ! -L "$1" ] || die 1 "the spec directory is a symbolic link; name the directory itself"
  [ -d "$1" ] || die 1 "no spec directory at $(sanitize_printable "$1" '?')"
  (cd -P "$1" && pwd -P) || die 2 "cannot enter the spec directory"
}

cmd_link() {
  _spec='' _track=''
  while [ $# -gt 1 ]; do
    case $1 in
      --spec)
        [ $# -ge 3 ] || usage
        _spec=$2
        shift 2
        ;;
      --track)
        [ $# -ge 3 ] || usage
        check_label "$2"
        _track=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  [ $# -eq 1 ] && [ -n "$_spec" ] || usage
  resolve_venture "$1"
  bundle_lock
  _sd=$(spec_dir "$_spec") || exit $?
  gather
  _scope=${_track:-venture}
  _cur=$(awk -F'\t' -v s="$_scope" '$1 == "LIN" && $2 == s { print $5 }' "$work/all")
  [ -n "$_cur" ] || die 1 "$_scope has no lineage record; seed it first"
  _loc=$(loc_of "$_sd") || die 1 "the spec directory is not inside a git repository"
  check_path "$_loc" "the spec location"
  _key=$(lineage_key "$_scope")
  cites "$_sd" "$_key"
  case $? in
    0) ;;
    2)
      printf 'lineage\t%s\tspec-missing\n' "$_scope"
      die 1 "spec-missing: no requirements.md in the spec directory"
      ;;
    *)
      printf 'lineage\t%s\tspec-side-missing\n' "$_scope"
      die 1 "spec-side-missing: the spec's Sources do not cite $_key"
      ;;
  esac
  if [ "$_cur" = "$_loc" ]; then
    printf 'lineage\t%s\tlinked\n' "$_scope"
    return 0
  fi
  [ "$_cur" = pending ] || die 1 "$_scope is already linked to another spec"
  stage
  _ln=$(locate "$work/stage/brief.md" bullet Lineage "- **$_scope** — ")
  [ "$_ln" -gt 0 ] || die 2 "brief.md holds no lineage bullet for $_scope"
  _line=$(sed -n "${_ln}p" "$work/stage/brief.md")
  case $_line in
    *' — spec: pending') ;;
    *) die 2 "the $_scope lineage bullet does not end in a pending spec" ;;
  esac
  replace_line "$work/stage/brief.md" "$_ln" "${_line% — spec: pending} — spec: \`$_loc\`"
  changelog "$work/stage/brief.md" "- $TODAY — the $_scope seed's spec recorded as \`$_loc\`."
  bump_reviewed "$work/stage/brief.md"
  validated_stage
  install_files brief.md
  printf 'lineage\t%s\tlinked\n' "$_scope"
}

cmd_lineage() {
  : >"$work/speclist"
  while [ $# -gt 1 ]; do
    case $1 in
      --spec)
        [ $# -ge 3 ] || usage
        printf '%s\n' "$2" >>"$work/speclist"
        shift 2
        ;;
      *) usage ;;
    esac
  done
  [ $# -eq 1 ] || usage
  resolve_venture "$1"
  gather
  : >"$work/specmap"
  while IFS= read -r _s; do
    _sd=$(spec_dir "$_s") || exit $?
    _sl=$(loc_of "$_sd") || die 1 "a --spec directory is not inside a git repository"
    cut -f2 "$work/specmap" | grep -qxF "$_sd" && continue
    ! cut -f1 "$work/specmap" | grep -qxF "$_sl" \
      || die 2 "two --spec directories share the location $(sanitize_printable "$_sl" '?'); check them one at a time"
    printf '%s\t%s\n' "$_sl" "$_sd" >>"$work/specmap"
  done <"$work/speclist"
  _bad=0
  graduated_scopes >"$work/grad"
  while IFS='	' read -r _sc _g; do
    GATE_SCOPE=$_sc awk -F'\t' '$1 == "LIN" && $2 == ENVIRON["GATE_SCOPE"] { f = 1 } END { exit !f }' "$work/all" && continue
    printf 'lineage\t%s\tventure-side-missing\n' "$(sanitize_printable "$_sc" '?')"
    _bad=1
  done <"$work/grad"
  awk -F'\t' '$1 == "LIN" { print $2 "\t" $5 }' "$work/all" >"$work/lins"
  while IFS='	' read -r _sc _sp; do
    if [ "$_sp" = pending ]; then
      printf 'lineage\t%s\tpending\n' "$(sanitize_printable "$_sc" '?')"
      continue
    fi
    case $_sp in
      *:*) _sd=$(GATE_LOC=$_sp awk -F'\t' '$1 == ENVIRON["GATE_LOC"] { print $2; exit }' "$work/specmap") ;;
      *)
        # The recorded location is bundle text: it is read only once it
        # resolves to a directory inside the venture.
        _sd=
        case /$_sp/ in
          //* | */../*) ;;
          *)
            if _sd=$(cd -P "$vdir/$_sp" 2>/dev/null && pwd -P); then
              case $_sd in
                "$vdir" | "$vdir"/*) ;;
                *) _sd= ;;
              esac
            else
              # It resolves nowhere: missing when its nearest existing
              # ancestor lies inside the venture, refused otherwise.
              _pp=$(dirname "$vdir/$_sp")
              while [ ! -d "$_pp" ]; do _pp=$(dirname "$_pp"); done
              _pp=$(cd -P "$_pp" 2>/dev/null && pwd -P)
              case $_pp in
                "$vdir" | "$vdir"/*)
                  printf 'lineage\t%s\tspec-missing\n' "$(sanitize_printable "$_sc" '?')"
                  _bad=1
                  continue
                  ;;
              esac
              _sd=
            fi
            ;;
        esac
        if [ -z "$_sd" ]; then
          printf 'lineage\t%s\trefused\n' "$(sanitize_printable "$_sc" '?')"
          _bad=1
          continue
        fi
        ;;
    esac
    if [ -z "$_sd" ]; then
      printf 'lineage\t%s\tunchecked\n' "$(sanitize_printable "$_sc" '?')"
      continue
    fi
    cites "$_sd" "$(lineage_key "$_sc")"
    case $? in
      0) printf 'lineage\t%s\tlinked\n' "$(sanitize_printable "$_sc" '?')" ;;
      2)
        printf 'lineage\t%s\tspec-missing\n' "$(sanitize_printable "$_sc" '?')"
        _bad=1
        ;;
      *)
        printf 'lineage\t%s\tspec-side-missing\n' "$(sanitize_printable "$_sc" '?')"
        _bad=1
        ;;
    esac
  done <"$work/lins"
  return "$_bad"
}

# --- archive -----------------------------------------------------------------

# first_reason <file> — a helper's first output line, as one plain reason.
first_reason() {
  sed -n '1{s/^degraded	//;s/^inception-registry: //;p;}' "$1" | tr '\t' ' ' | strip_eval
}

cmd_archive() {
  _note='' _abandon=''
  while [ $# -gt 1 ]; do
    case $1 in
      --note)
        [ $# -ge 3 ] || usage
        _note=$2
        shift 2
        ;;
      --abandon)
        _abandon=1
        shift
        ;;
      *) usage ;;
    esac
  done
  [ $# -eq 1 ] && [ -n "$_note" ] || usage
  clean_value "$_note" "the post-mortem note"
  resolve_venture "$1"
  bundle_lock
  gather
  _old=$(awk -F'\t' '$1 == "STATUS" { print $2; exit }' "$work/all")
  ! grep -q '^POSTMORTEM	' "$work/all" || die 1 "the venture already carries a post-mortem"
  _d=$TODAY
  stage
  if [ -n "$_abandon" ]; then
    case $_old in
      Exploring | On-hold) ;;
      *) die 1 "only a live venture is abandoned; this one is $(sanitize_printable "$_old" '?')" ;;
    esac
    _new=Abandoned
    changelog "$work/stage/brief.md" "- $_d — status $_old → Abandoned (operator declaration)."
    for _f in $FILES; do
      set_status "$work/stage/$_f" Abandoned
      bump_reviewed "$work/stage/$_f"
    done
    _changed=$FILES
  else
    [ "$_old" = Killed ] \
      || die 1 "the venture is $(sanitize_printable "$_old" '?'): a killed venture is archived after its Kill record, and a live one only by an abandonment (--abandon)"
    _new=Killed
    bump_reviewed "$work/stage/brief.md"
    _changed=brief.md
  fi
  changelog "$work/stage/brief.md" "- $_d — post-mortem: $_note"
  validated_stage
  # shellcheck disable=SC2086 # the file list is fixed words
  install_files $_changed
  printf 'archived\t%s\n' "$_new"

  # The registry and the drop are machine-local and losable: either failing
  # leaves the archive standing and says so (REQ-H1.6).
  if "$REGISTRY" get "$vid" >"$work/reg" 2>&1 && "$REGISTRY" add "$vid" "$vdir" >"$work/reg" 2>&1; then
    printf 'registry\trefreshed\n'
  else
    printf 'degraded\tthe venture registry was not updated: %s\n' "$(first_reason "$work/reg")"
  fi
  if "$REGISTRY" drop "$vid" "$_new venture post-mortem: $_note" >"$work/drop" 2>&1; then
    printf 'observation\tdropped\n'
  else
    printf 'degraded\tthe post-mortem was not dropped as an observation: %s\n' "$(first_reason "$work/drop")"
  fi
}

[ $# -ge 1 ] || usage
cmd=$1
shift
case $cmd in
  evaluate) cmd_evaluate "$@" ;;
  record) cmd_record "$@" ;;
  seed) cmd_seed "$@" ;;
  link) cmd_link "$@" ;;
  lineage) cmd_lineage "$@" ;;
  archive) cmd_archive "$@" ;;
  *) usage ;;
esac
