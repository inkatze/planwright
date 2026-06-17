#!/bin/sh
# Unit tests for scripts/spec-translate.sh — the plain-language translation
# layer (Task 3 of specs/spec-comprehension; D-2, REQ-C1.1, REQ-C1.7,
# REQ-D1.3): the lossless layered view over the bundle reader model. It reads
# the model record stream (scripts/spec-model.sh), passes the model records
# through unchanged, and appends, per text-bearing element, a translated record
# carrying the plain audience-neutral rendering, the verbatim source, and the
# element's back-pointer, plus a marker record per normative token.
#
#   TEXT  <ref>  <kind>  <plain>  <source>
#   NORM  <ref>  <ordinal>  <token>
#
# Properties verified, one numbered section per Task 3 behavior:
#   1.  Internal-vocabulary scrub (REQ-C1.1): the plain column carries no
#       identifier tokens (REQ-/D-/task-id) and no four-file names; the source
#       column retains them (the back-pointer is hidden, not destroyed — D-2).
#   2.  Four-file names map to plain audience-neutral phrases, never the bare
#       `.md` filename (REQ-C1.1).
#   3.  Precision preservation (REQ-C1.7): every normative token
#       (MUST/SHALL/SHALL NOT, a comparator threshold) survives verbatim in the
#       plain column and is marked by a NORM record; "SHALL NOT" is one token,
#       not "SHALL"; lowercase prose "shall/must" is not a normative token.
#   3b. Marking does not soften: the verbatim token is preserved even as the
#       surrounding identifiers are scrubbed.
#   4.  Reveal mapping (REQ-D1.3, Done-when #3): every TEXT record carries a ref
#       that resolves back to a model element; the source column restores the
#       precise wording the plain column rephrased.
#   5.  Decision and task fields are translated with structured refs
#       (`D-2#decision`, `task-3#deliverables`) — the substrate Tasks 4/8 render.
#   6.  Pass-through: the model records are emitted unchanged (lossless), so a
#       single `spec-model | spec-translate` carries structure plus the layer.
#   7.  Composition: a `<spec-dir>` argument runs the full model->translate
#       chain; the real bundle's default view leaks no internal vocabulary.
#   8.  Graceful degradation: empty input emits nothing and exits 0; a missing
#       spec directory fails closed (exit 2) like the model.
#   9.  Stream hygiene: every TEXT record has exactly five tab-separated fields
#       (the translation never injects a phantom column).
#   10. Determinism: two runs over the same input are byte-identical.
#
# Runs standalone: ./tests/test-spec-translate.sh
set -eu

# Pin the C locale: charset checks and awk/grep ranges must not vary by host
# locale collation (the threshold scan matches multibyte ≤/≥ byte-wise).
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into command substitutions,
# corrupting derived paths (house pattern, see sibling tests).
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/spec-translate.sh"
repo_root=$(cd "$here/.." && pwd)
tab=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$script" ] || fail "scripts/spec-translate.sh missing or not executable"

tmp=$(mktemp -d)
trap 'chmod -R u+rwx "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

# run_stdin <expected-exit> — pipe $IN (a model stream) into the translator,
# capture combined output in $out, and fail if the exit code differs.
out=
run_stdin() {
  rexp=$1
  rc=0
  out=$(printf '%s' "$IN" | "$script" 2>&1) || rc=$?
  [ "$rc" -eq "$rexp" ] \
    || fail "stdin mode: expected exit $rexp, got $rc — output: $out"
}

# run_dir <expected-exit> <spec-dir> — run the translator over a spec directory
# (full model->translate chain), capture in $out.
run_dir() {
  rexp=$1
  rc=0
  out=$("$script" "$2" 2>&1) || rc=$?
  [ "$rc" -eq "$rexp" ] \
    || fail "dir mode: expected exit $rexp, got $rc for $2 — output: $out"
}

has() {
  case $out in
    *"$1"*) ;;
    *) fail "output lacks \"$1\": $out" ;;
  esac
}

lacks() {
  case $out in
    *"$1"*) fail "output unexpectedly contains \"$1\": $out" ;;
  esac
}

# rec <field1> ... — assert a record whose leading fields match the given
# tab-separated values exists in $out (exact per column; trailing fields
# unconstrained). Up to five fields.
rec() {
  [ $# -le 5 ] || fail "rec helper supports at most 5 fields: $*"
  printf '%s\n' "$out" | awk -F"$tab" \
    -v n="$#" -v a1="${1:-}" -v a2="${2:-}" -v a3="${3:-}" \
    -v a4="${4:-}" -v a5="${5:-}" '
    {
      v[1] = a1; v[2] = a2; v[3] = a3; v[4] = a4; v[5] = a5
      ok = 1
      for (i = 1; i <= n; i++) if ($i != v[i]) { ok = 0; break }
      if (ok) { found = 1; exit }
    }
    END { exit(found ? 0 : 1) }
  ' || fail "no record matching [$*] in: $out"
}

count_tag() {
  printf '%s\n' "$out" | awk -F"$tab" -v t="$1" '$1 == t { n++ } END { print n + 0 }'
}

# field <tag> <ref> <col> — print column <col> of the first record whose tag and
# second column match. Used to inspect a specific TEXT/NORM record's columns.
field() {
  printf '%s\n' "$out" | awk -F"$tab" \
    -v t="$1" -v r="$2" -v c="$3" '$1 == t && $2 == r { print $c; exit }'
}

# A model-stream fixture: a requirement carrying inline identifiers, four-file
# names, and normative tokens; a decision with its four-beat fields; a task with
# its fields. Tab-separated, exactly as scripts/spec-model.sh emits.
t() { printf '%s' "$tab"; }
IN="BUNDLE$(t)demo$(t)Active
FILE$(t)requirements$(t)present
REQ$(t)REQ-A1.1$(t)A$(t)live$(t)The renderer SHALL NOT soften a token below a threshold of ≤ 64 characters, per the design (D-2) and tasks.md.
REQ$(t)REQ-A1.2$(t)A$(t)live$(t)The reader MAY restate a claim; the tool shall record it without judgement.
REQCITE$(t)REQ-A1.1$(t)D-2
DEC$(t)D-2$(t)N$(t)Plain language is a lossless layered view
DECFIELD$(t)D-2$(t)decision$(t)The plain rendering is a view over the substrate (REQ-C1.7).
DECFIELD$(t)D-2$(t)alternatives$(t)Rewrite the bundle. Rejected because: rewriting loses traceability.
DECFIELD$(t)D-2$(t)chosen$(t)Layering keeps the artifact readable and traceable.
TASK$(t)3$(t)In progress$(t)Plain-language translation layer
TASKFIELD$(t)3$(t)deliverables$(t)the translator, the guardrail, and the reveal mapping (D-2).
TASKFIELD$(t)3$(t)donewhen$(t)a bundle renders to plain text per REQ-C1.1 and REQ-C1.7.
TASKDEP$(t)3$(t)2
TEST$(t)REQ-A1.1"

run_stdin 0

# ---------------------------------------------------------------------------
# 1. Internal-vocabulary scrub: the plain column carries no identifier tokens
# and no four-file names; the source column retains them.
# ---------------------------------------------------------------------------
a11_plain=$(field TEXT REQ-A1.1 4)
a11_src=$(field TEXT REQ-A1.1 5)
[ -n "$a11_plain" ] || fail "no TEXT record for REQ-A1.1"
case $a11_plain in
  *D-2*) fail "plain text leaks the decision id D-2: $a11_plain" ;;
  *tasks.md*) fail "plain text leaks a four-file name: $a11_plain" ;;
esac
# The back-pointer is hidden, not destroyed: the source column keeps the id.
case $a11_src in
  *D-2*) ;;
  *) fail "source column dropped the back-pointer D-2: $a11_src" ;;
esac

# A global guard over every TEXT plain column: no REQ-/D-/task-id token and none
# of the four bundle file names (the REQ-C1.1 scope: the four-file structure and
# the identifier schemes; other filenames a spec names are content the [manual]
# readability half judges, not mechanical internal vocabulary).
plain_leaks=$(printf '%s\n' "$out" | awk -F"$tab" '$1 == "TEXT" { print $4 }' \
  | grep -oE 'REQ-[A-Z][0-9]+\.[0-9]+|REQ-[A-Z][^A-Za-z0-9]|D-[0-9]+|(requirements|design|tasks|test-spec)\.md|Task [0-9]+' || true)
[ -z "$plain_leaks" ] || fail "fixture plain columns leak internal vocabulary: $plain_leaks"

# ---------------------------------------------------------------------------
# 2. Four-file names map to plain phrases.
# ---------------------------------------------------------------------------
case $a11_plain in
  *"the design"*) ;;
  *) fail "design.md / tasks.md not mapped to a plain phrase: $a11_plain" ;;
esac

# ---------------------------------------------------------------------------
# 3. Precision preservation: normative tokens verbatim in plain + a NORM mark.
# ---------------------------------------------------------------------------
case $a11_plain in
  *"SHALL NOT"*) ;;
  *) fail "REQ-A1.1 plain lost the normative token SHALL NOT: $a11_plain" ;;
esac
case $a11_plain in
  *"≤ 64"*) ;;
  *) fail "REQ-A1.1 plain lost the threshold ≤ 64: $a11_plain" ;;
esac
# SHALL NOT is marked as one token, not split into "SHALL".
rec NORM REQ-A1.1 1 "SHALL NOT"
norm_a11=$(printf '%s\n' "$out" | awk -F"$tab" '$1 == "NORM" && $2 == "REQ-A1.1" { print $4 }')
case $norm_a11 in
  *"≤ 64"*) ;;
  *) fail "threshold ≤ 64 not marked as a normative token: $norm_a11" ;;
esac
# No bare "SHALL" NORM record where the source had "SHALL NOT".
printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "NORM" && $2 == "REQ-A1.1" && $4 == "SHALL" { f = 1 } END { exit(f ? 1 : 0) }' \
  || fail "SHALL NOT was wrongly split into a bare SHALL mark"
# MAY is normative; the lowercase prose "shall record" is not.
rec NORM REQ-A1.2 1 MAY
printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "NORM" && $2 == "REQ-A1.2" { n++ } END { exit(n == 1 ? 0 : 1) }' \
  || fail "REQ-A1.2 should mark exactly one normative token (MAY), not lowercase prose"

# ---------------------------------------------------------------------------
# 4. Reveal mapping: every TEXT ref resolves to a model element; the source
# column restores the precise wording the plain column rephrased.
# ---------------------------------------------------------------------------
# REQ-C1.7 was rephrased out of the decision field's plain text but survives in
# its source (restorable on reveal).
d2dec_plain=$(field TEXT "D-2#decision" 4)
d2dec_src=$(field TEXT "D-2#decision" 5)
case $d2dec_plain in
  *REQ-C1.7*) fail "decision plain leaks REQ-C1.7: $d2dec_plain" ;;
esac
case $d2dec_src in
  *REQ-C1.7*) ;;
  *) fail "decision source dropped the restorable wording REQ-C1.7: $d2dec_src" ;;
esac
# Each TEXT ref's base element (strip #field and task- prefix) is a model id.
printf '%s\n' "$out" | awk -F"$tab" -v RS_OK=0 '
  $1 == "TEXT" {
    base = $2
    sub(/#.*/, "", base)
    sub(/^task-/, "", base)
    refs[base] = 1
  }
  $1 == "REQ" { ids[$2] = 1 }
  $1 == "DEC" { ids[$2] = 1 }
  $1 == "TASK" { ids[$2] = 1 }
  END {
    for (r in refs) if (!(r in ids)) { print "unresolved ref: " r; bad = 1 }
    exit(bad ? 1 : 0)
  }
' | grep -q . && fail "a TEXT ref does not resolve to a model element" || true

# ---------------------------------------------------------------------------
# 5. Decision and task fields translated with structured refs.
# ---------------------------------------------------------------------------
rec TEXT D-2 decision-title
rec TEXT "D-2#decision" decision-decision
rec TEXT "D-2#alternatives" decision-alternatives
rec TEXT "D-2#chosen" decision-chosen
rec TEXT task-3 task-title
rec TEXT "task-3#deliverables" task-deliverables
rec TEXT "task-3#donewhen" task-donewhen
# The rejected alternative is preserved verbatim (substrate for the decision map).
d2alt=$(field TEXT "D-2#alternatives" 5)
case $d2alt in
  *"Rejected because"*) ;;
  *) fail "decision alternatives lost the rejected alternative: $d2alt" ;;
esac

# ---------------------------------------------------------------------------
# 6. Pass-through: model records emitted unchanged.
# ---------------------------------------------------------------------------
rec BUNDLE demo Active
rec REQ REQ-A1.1 A live
rec DEC D-2 N
rec TASKDEP 3 2
rec REQCITE REQ-A1.1 D-2
rec TEST REQ-A1.1

# ---------------------------------------------------------------------------
# 9. Stream hygiene: every TEXT record has exactly five fields.
# ---------------------------------------------------------------------------
printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "TEXT" && NF != 5 { bad = 1 } END { exit(bad ? 1 : 0) }' \
  || fail "a TEXT record does not have exactly five fields"

# ---------------------------------------------------------------------------
# 10. Determinism.
# ---------------------------------------------------------------------------
run1=$(printf '%s' "$IN" | "$script")
run2=$(printf '%s' "$IN" | "$script")
[ "$run1" = "$run2" ] || fail "translation output is not deterministic"

# ---------------------------------------------------------------------------
# 11. Identifier-parenthetical scrub is precise (regression): a parenthetical
# composed only of identifiers is removed, but a parenthetical carrying
# non-identifier uppercase/hyphenated content (e.g. (UTF-8), (SHA-256)) is
# content, not internal vocabulary, and survives verbatim (D-2 losslessness;
# the scrub must not delete what has no back-pointer). Plus normative-modal
# extension coverage (MUST NOT / SHOULD NOT as one token; a non-extended modal)
# and a normative token inside a decision field carrying the field ref.
# ---------------------------------------------------------------------------
IN="REQ$(t)REQ-A1.1$(t)A$(t)live$(t)Encode as (UTF-8) and (SHA-256); cite (REQ-C1.7) and (D-2 / REQ-D1.3).
REQ$(t)REQ-A1.3$(t)A$(t)live$(t)The system MUST NOT fail and SHOULD NOT stall; logging is OPTIONAL.
DEC$(t)D-2$(t)N$(t)Lossless layered view
DECFIELD$(t)D-2$(t)chosen$(t)The plain view SHALL remain lossless and traceable."
run_stdin 0

a11=$(field TEXT REQ-A1.1 4)
case $a11 in
  *"UTF-8"*) ;;
  *) fail "scrub wrongly removed the non-identifier parenthetical (UTF-8): $a11" ;;
esac
case $a11 in
  *"SHA-256"*) ;;
  *) fail "scrub wrongly removed the non-identifier parenthetical (SHA-256): $a11" ;;
esac
case $a11 in
  *REQ-C1.7*) fail "identifier parenthetical (REQ-C1.7) leaked into plain: $a11" ;;
  *REQ-D1.3*) fail "identifier parenthetical (REQ-D1.3) leaked into plain: $a11" ;;
  *D-2*) fail "identifier parenthetical (D-2) leaked into plain: $a11" ;;
esac
case $a11 in
  *"()"* | *"( )"* | *"( / )"*) fail "empty-paren residue left after id removal: $a11" ;;
esac

# Modal extension: MUST NOT and SHOULD NOT are single verbatim tokens, marked in
# source order; OPTIONAL is marked but not extended; no bare modal split.
rec NORM REQ-A1.3 1 "MUST NOT"
rec NORM REQ-A1.3 2 "SHOULD NOT"
rec NORM REQ-A1.3 3 OPTIONAL
printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "NORM" && $2 == "REQ-A1.3" && ($4 == "MUST" || $4 == "SHOULD") { f = 1 } END { exit(f ? 1 : 0) }' \
  || fail "MUST NOT / SHOULD NOT was wrongly split into a bare modal mark"
printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "NORM" && $2 == "REQ-A1.3" { n++ } END { exit(n == 3 ? 0 : 1) }' \
  || fail "REQ-A1.3 should mark exactly three normative tokens"

# A normative token inside a decision field is marked against the field ref
# (emit_norm runs for decision/task fields, not only requirements).
rec NORM "D-2#chosen" 1 SHALL

# ---------------------------------------------------------------------------
# 8. Graceful degradation.
# ---------------------------------------------------------------------------
IN=""
run_stdin 0
[ -z "$out" ] || fail "empty input should emit nothing, got: $out"
# A missing spec directory fails closed (mirrors the model).
run_dir 2 "$tmp/does-not-exist"

# ---------------------------------------------------------------------------
# 7. Composition over a real bundle: the default view leaks no internal
# vocabulary, and the reveal (source) layer retains identifiers.
# ---------------------------------------------------------------------------
for spec in spec-comprehension bootstrap; do
  bundle="$repo_root/specs/$spec"
  [ -d "$bundle" ] || continue
  run_dir 0 "$bundle"

  # No TEXT plain column leaks an identifier token or one of the four bundle
  # file names (the REQ-C1.1 scope).
  real_leaks=$(printf '%s\n' "$out" | awk -F"$tab" '$1 == "TEXT" { print $4 }' \
    | grep -oE 'REQ-[A-Z][0-9]+\.[0-9]+|D-[0-9]+|(requirements|design|tasks|test-spec)\.md|Task [0-9]+' || true)
  [ -z "$real_leaks" ] \
    || fail "$spec default view leaks internal vocabulary: $real_leaks"

  # The reveal layer is non-empty: at least one source column retains an id
  # (proving the back-pointer is preserved, not destroyed).
  has_id=$(printf '%s\n' "$out" | awk -F"$tab" '$1 == "TEXT" { print $5 }' \
    | grep -cE 'REQ-[A-Z][0-9]+\.[0-9]+|D-[0-9]+' || true)
  [ "${has_id:-0}" -gt 0 ] \
    || fail "$spec reveal layer retains no identifiers — back-pointers lost"

  # Every requirement's normative tokens survive verbatim in its plain column:
  # the count of SHALL/MUST occurrences in plain equals the count in source.
  mismatch=$(printf '%s\n' "$out" | awk -F"$tab" '
    $1 == "TEXT" {
      p = gsub(/SHALL|MUST/, "&", $4)
      s = gsub(/SHALL|MUST/, "&", $5)
      if (p != s) { print $2 ": plain " p " source " s; bad = 1 }
    }
    END { exit(bad ? 1 : 0) }
  ') || fail "$spec: a normative token was softened out of the plain view: $mismatch"
done

echo "PASS: test-spec-translate.sh"
