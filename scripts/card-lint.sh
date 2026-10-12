#!/bin/sh
# card-lint.sh — the discipline-card linter (inception Task 4; REQ-P1.1,
# REQ-P1.2 · D-3, D-4).
#
# doctrine/discipline-cards.md is the normative source for every rule below;
# this script is its mechanical shadow. It checks one or more card files
# against the card format: the fail-closed `Card-format:` gate first, then the
# closed header key set, the closed section set and its order, and the per-section
# shapes (one-sentence role, three to seven frame-anchored mandate questions, a
# numbered framework sequence with misuse caveats, a refuse-without grounding
# gate, a fenced artifact template ending in `Decisions I cannot make`, the
# capability boundary, the typed escalation contract, the bench rule), plus the
# identity-styling phrases it can recognize.
#
# Deliberately NOT enforced, so the boundary is on the record:
#   - Whether a mandate question is a GOOD question. The frame-anchor check is
#     the structural floor (a question that never names the frame or the
#     venture is generic by construction); judging the rest is the authoring
#     recipe's review, not a lint.
#   - Whether a cited source says what the card claims, or is current. That is
#     the recipe's re-verification step, dated in `Reviewed:`.
#   - Identity styling the phrase list does not know. The list catches the
#     common shapes; the recipe's styling pass is the real gate.
#
# Finding ORDER is part of the contract: checks run and emit in a fixed order,
# never `for (k in arr)`, so the same card yields the same bytes on any awk.
#
# Usage:
#   card-lint.sh <card.md>...
#   card-lint.sh --rules
#
# Exit: 0 clean · 1 findings · 2 usage or environment error (including an
#   unreadable file) · 3 fail-closed refusal (missing, unparseable, or
#   unsupported `Card-format:`, or an unbalanced code fence) — the card was not
#   linted at all. With several files every file is linted and the exit is the
#   worst outcome, refusal ranking above findings.
#
# Portable POSIX sh + awk; bash 3.2 / BSD tooling floor (REQ-K1.5).
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# Card content is repo- or overlay-controlled input and reaches the terminal
# only stripped (doctrine/security-posture.md, echo discipline).
if [ ! -f "$script_dir/echo-safety.sh" ] || [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "card-lint.sh: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

SUPPORTED_MAJOR=1

usage() {
  echo "usage: card-lint.sh <card.md>..." >&2
  echo "       card-lint.sh --rules" >&2
  exit 2
}

# The advertised rule set: one `<code> <description>` line per enforced rule.
# The test suite fails if any code here lacks a seeded-violation fixture, or a
# fixture expects a code that is not here.
print_rules() {
  cat <<'RULES'
FMT-MISSING the card declares no single parseable Card-format
FMT-UNSUPPORTED the declared Card-format major is not supported by this linter
FENCE-UNBALANCED a column-0 code fence is left open at end of file
HDR-ID Card-id is missing, outside the identifier charset, or not the file name's stem
HDR-REVIEWED Reviewed is missing or not a real calendar date
HDR-ROT Rot-rate is missing or not slow, medium, or fast
HDR-TIER Default-tier is missing or not a capability tier
HDR-RAPID RAPID is missing, names a letter outside R, A, P, I, or names D
HDR-BENCH Bench is missing or not yes or no
HDR-STANCE Stance-axis is present but neither none nor <pole>-<pole>
HDR-MODEL Model-override is present but neither none nor a single model token
HDR-UNKNOWN a header key outside the card key set, or one given twice
SEC-MISSING a required section is absent
SEC-UNKNOWN a section outside the closed card section set, or content outside any section
SEC-ORDER sections are out of the schema order, or one appears twice
SEC-EMPTY a present section has no content
ROLE-FORM the role is not exactly one sentence
MANDATE-SIZE the mandate is not three to seven numbered questions
MANDATE-FORM a mandate item is not phrased as a question, or a mandate line sits outside the numbered questions
MANDATE-GENERIC a mandate question does not anchor on the frame or the venture
FRAMEWORK-SEQUENCE the frameworks are not a numbered working sequence
FRAMEWORK-MISUSE a framework carries no Misuse caveat
GROUNDING-REFUSE the grounding names no Refuse-without gate
TEMPLATE-FORM the artifact template is not fenced or does not end in Decisions I cannot make
TEMPLATE-DONE the artifact template has no Done-when line
BOUNDARY-EXCEPTIONS per-activity exceptions are absent or name an unknown tier
BOUNDARY-ONEWAY the one-way-doors line is absent or not human-authority
BOUNDARY-OUTSCOPE the out-of-scope line is absent or empty
ESC-TYPED an escalation line is not a typed trigger with known powers
ESC-COVERAGE a trigger class of the escalation taxonomy is not declared
BENCH-TRIGGERS a bench card lacks pull-in triggers, or a non-bench card has them
STYLE-IDENTITY a line carries identity or authority styling
RULES
}

if [ "$#" -eq 0 ]; then
  usage
fi
if [ "$1" = "--rules" ]; then
  [ "$#" -eq 1 ] || usage
  print_rules
  exit 0
fi
case $1 in
  -*) usage ;;
esac

# The lint program. Emits `<code><TAB><detail>` lines in check order; a
# refusal emits exactly its own line and stops.
# shellcheck disable=SC2016
lint_awk='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function emit(code, msg) { printf "%s\t%s\n", code, msg }
function real_date(s,    y, m, d, dim) {
  if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
  y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
  if (m < 1 || m > 12 || d < 1) return 0
  dim = 31
  if (m == 4 || m == 6 || m == 9 || m == 11) dim = 30
  if (m == 2) dim = ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) ? 29 : 28
  return d <= dim
}
# body(name): the section text as one string, items newline-joined.
{ L[NR] = $0 }
END {
  n = NR

  # --- Header block: the leading run of the H1, key lines, and blanks ------
  nh = 0
  for (i = 1; i <= n; i++) {
    if (L[i] ~ /^# / && i == 1) continue
    if (L[i] ~ /^[ \t]*$/) continue
    if (L[i] ~ /^\*\*[A-Za-z][A-Za-z-]*:\*\*/) {
      k = L[i]; sub(/^\*\*/, "", k); sub(/:\*\*.*$/, "", k)
      v = L[i]; sub(/^\*\*[A-Za-z][A-Za-z-]*:\*\*/, "", v); v = trim(v)
      if (!(k in H)) H[k] = v
      KN[k]++; nh++; HK[nh] = k; HL[nh] = i
      continue
    }
    break
  }
  header_end = i

  if (!("Card-format" in H) || H["Card-format"] !~ /^[0-9]+$/ || KN["Card-format"] > 1) {
    emit("FMT-MISSING", "no single parseable Card-format: line in the header block"); exit
  }
  if (H["Card-format"] + 0 != major) {
    emit("FMT-UNSUPPORTED", "Card-format: " H["Card-format"] " is not supported (this linter reads " major ")"); exit
  }

  # --- Fence map (column-0 backtick fences, doctrine/spec-format.md) -------
  # Not the spec-parse.sh lexer: that one drops fenced lines, and the
  # artifact-template check reads them (a named exemption in
  # tests/test-spec-parse-corpus.sh).
  open = 0
  for (i = 1; i <= n; i++) {
    if (L[i] ~ /^```/) { F[i] = 1; open = !open } else F[i] = open
  }
  if (open) { emit("FENCE-UNBALANCED", "a code fence opened in this card is never closed"); exit }

  # --- Header keys ---------------------------------------------------------
  id = ("Card-id" in H) ? H["Card-id"] : ""
  if (id == "") emit("HDR-ID", "Card-id: is missing")
  else if (id !~ /^[a-z0-9][a-z0-9-]*$/ || length(id) > 64)
    emit("HDR-ID", "Card-id: " id " is outside ^[a-z0-9][a-z0-9-]*$ (max 64)")
  else if (id != stem)
    emit("HDR-ID", "Card-id: " id " does not match the file name stem " stem)

  if (!("Reviewed" in H) || !real_date(H["Reviewed"]))
    emit("HDR-REVIEWED", "Reviewed: must be a real <YYYY-MM-DD> date")
  if (!("Rot-rate" in H) || H["Rot-rate"] !~ /^(slow|medium|fast)$/)
    emit("HDR-ROT", "Rot-rate: must be slow, medium, or fast")
  if (!("Default-tier" in H) || H["Default-tier"] !~ /^(agent-senior|structure-only|human-authority)$/)
    emit("HDR-TIER", "Default-tier: must be agent-senior, structure-only, or human-authority")

  if (!("RAPID" in H) || H["RAPID"] == "") emit("HDR-RAPID", "RAPID: is missing")
  else {
    m = split(H["RAPID"], parts, ",")
    for (j = 1; j <= m; j++) {
      p = trim(parts[j])
      if (p == "D") { emit("HDR-RAPID", "RAPID: names D; the human always holds the decision"); continue }
      if (p !~ /^[RAPI]$/) { emit("HDR-RAPID", "RAPID: letter \"" p "\" is not one of R, A, P, I"); continue }
      if (p in seen_rapid) emit("HDR-RAPID", "RAPID: letter " p " is repeated")
      seen_rapid[p] = 1
    }
  }
  if (!("Bench" in H) || H["Bench"] !~ /^(yes|no)$/)
    emit("HDR-BENCH", "Bench: must be yes or no")
  if (("Stance-axis" in H) && H["Stance-axis"] != "none" && H["Stance-axis"] !~ /^[a-z]+-[a-z]+$/)
    emit("HDR-STANCE", "Stance-axis: must be none or <pole>-<pole>")
  if (("Model-override" in H) && H["Model-override"] != "none" &&
      H["Model-override"] !~ /^[A-Za-z0-9][A-Za-z0-9._-]*(\/[a-z]+)?$/)
    emit("HDR-MODEL", "Model-override: must be none or one model or model/effort token")
  nk = split("Card-format Card-id Reviewed Rot-rate Default-tier RAPID Bench Stance-axis Model-override", KS, " ")
  for (j = 1; j <= nk; j++) is_key[KS[j]] = 1
  for (j = 1; j <= nh; j++) {
    k = HK[j]
    if (!(k in is_key)) emit("HDR-UNKNOWN", "line " HL[j] ": header key " k " is outside the card key set")
    else if ((k in key_seen) && k != "Card-format") emit("HDR-UNKNOWN", "line " HL[j] ": header key " k " is given more than once")
    key_seen[k] = 1
  }

  # --- Section set, order, and bodies --------------------------------------
  ns = split("Role|Mandate|Frameworks|Grounding|Input subscription|Artifact template|Capability boundary|Escalation contract|Register rules|Anti-patterns|Blind spots|Conflict and deference|Independence|Pull-in triggers|Sources", S, "|")
  for (j = 1; j <= ns; j++) rank[S[j]] = j
  last_rank = 0; order_bad = 0; cur = ""; any_sec = 0; preamble = 0
  for (i = header_end; i <= n; i++) {
    # Identity content most often arrives outside the closed section set:
    # prose before the first section, an extra H1, or a setext heading.
    if (!any_sec && !preamble && L[i] !~ /^[ \t]*$/ && (F[i] || L[i] !~ /^## /)) {
      emit("SEC-UNKNOWN", "line " i ": content before the first section; only blank lines may follow the header block"); preamble = 1
    }
    if (any_sec && !F[i] && L[i] ~ /^# /)
      emit("SEC-UNKNOWN", "line " i ": an H1 after the title; card sections are ## headings")
    if (!F[i] && i > header_end && L[i] ~ /^(=+|-+)[ \t]*$/ && !F[i - 1] &&
        L[i - 1] !~ /^[ \t]*$/ && L[i - 1] !~ /^([-*+][ \t]|[0-9]+\.[ \t]|[|#>])/)
      emit("SEC-UNKNOWN", "line " i ": a setext heading; card sections are ## headings")
    if (!F[i] && L[i] ~ /^## /) {
      any_sec = 1
      name = trim(substr(L[i], 4))
      cur = ""
      if (!(name in rank)) { emit("SEC-UNKNOWN", "section \"" name "\" is outside the card section set"); continue }
      if (name in start) { emit("SEC-ORDER", "section \"" name "\" appears twice"); continue }
      start[name] = i
      if (rank[name] < last_rank && !order_bad) {
        emit("SEC-ORDER", "section \"" name "\" is out of the schema order"); order_bad = 1
      }
      last_rank = rank[name]; cur = name
      continue
    }
    if (cur != "" && !(F[i] == 0 && L[i] ~ /^# /)) {
      if (L[i] !~ /^[ \t]*$/) filled[cur] = 1
      # A fenced line is illustration, never structure: only the artifact
      # template, which IS a fence, reads one.
      if (F[i] && cur != "Artifact template") continue
      body_n[cur]++; B[cur, body_n[cur]] = L[i]; BF[cur, body_n[cur]] = F[i]
    }
  }
  for (j = 1; j <= ns; j++) {
    s = S[j]
    if (s == "Pull-in triggers") continue
    if (!(s in start)) emit("SEC-MISSING", "required section \"" s "\" is absent")
    else if (!(s in filled)) emit("SEC-EMPTY", "section \"" s "\" has no content")
  }

  # --- Role: exactly one sentence ------------------------------------------
  if ("Role" in filled) {
    t = ""
    for (j = 1; j <= body_n["Role"]; j++) if (B["Role", j] !~ /^[ \t]*$/) t = t " " trim(B["Role", j])
    t = trim(t); c = t
    sentences = gsub(/[.!?]( |$)/, "", c)
    if (sentences != 1 || t !~ /\.$/) emit("ROLE-FORM", "the role must be exactly one sentence ending in a period")
  }

  # --- Mandate: 3-7 numbered, frame-anchored questions ---------------------
  if ("Mandate" in filled) {
    mi = 0; stray = 0
    for (j = 1; j <= body_n["Mandate"]; j++) {
      line = B["Mandate", j]
      if (line ~ /^[0-9]+\. /) { mi++; Q[mi] = line; continue }
      if (mi > 0 && line ~ /^[ \t]+[^ \t]/) { Q[mi] = Q[mi] " " trim(line); continue }
      if (line !~ /^[ \t]*$/) stray++
    }
    if (mi < 3 || mi > 7) emit("MANDATE-SIZE", "the mandate has " mi " numbered questions; it needs three to seven")
    # Unnumbered lines would otherwise escape both the size cap and the
    # frame anchor.
    if (stray) emit("MANDATE-FORM", "the mandate has " stray " line(s) outside its numbered questions; indent a continuation line")
    for (j = 1; j <= mi; j++) {
      q = trim(Q[j]); num = q; sub(/\..*$/, "", num)
      if (q !~ /\?$/) emit("MANDATE-FORM", "mandate item " num " is not a question ending in ?")
      lq = tolower(q)
      # "the frame" must end at a word boundary, or "the frameworks" would
      # anchor; the typographic apostrophe is the same possessive.
      if (index(lq, "this venture") == 0 && index(lq, "the venture'"'"'s") == 0 &&
          index(lq, "the venture\342\200\231s") == 0 && lq !~ /the frame([^a-z]|$)/)
        emit("MANDATE-GENERIC", "mandate question " num " names neither the frame nor this venture, so it is answerable generically")
    }
  }

  # --- Frameworks: a numbered sequence, each with a Misuse caveat ----------
  if ("Frameworks" in filled) {
    fi_n = 0; bulleted = 0
    for (j = 1; j <= body_n["Frameworks"]; j++) {
      line = B["Frameworks", j]
      if (line ~ /^[0-9]+\. /) { fi_n++; FW[fi_n] = line; continue }
      if (line ~ /^[-*+] /) { bulleted = 1; continue }
      if (fi_n > 0 && line ~ /^[ \t]+[^ \t]/) FW[fi_n] = FW[fi_n] " " trim(line)
    }
    if (fi_n == 0 || bulleted) emit("FRAMEWORK-SEQUENCE", "the frameworks must be a numbered list, its order the working sequence")
    for (j = 1; j <= fi_n; j++) {
      if (index(FW[j], "Misuse:") == 0) {
        num = trim(FW[j]); sub(/\..*$/, "", num)
        emit("FRAMEWORK-MISUSE", "framework " num " carries no Misuse: caveat")
      }
    }
  }

  # --- Grounding: a Refuse-without gate ------------------------------------
  if ("Grounding" in start) {
    ok = 0
    for (j = 1; j <= body_n["Grounding"]; j++)
      if (B["Grounding", j] ~ /^- \*\*Refuse without:\*\* *[^ ]/) ok = 1
    if (!ok) emit("GROUNDING-REFUSE", "the grounding names no **Refuse without:** gate")
  }

  # --- Artifact template: fenced, ends in Decisions I cannot make ----------
  if ("Artifact template" in start) {
    fenced = 0; lasth = ""; done_ok = 0
    for (j = 1; j <= body_n["Artifact template"]; j++) {
      line = B["Artifact template", j]
      if (BF["Artifact template", j]) {
        fenced = 1
        if (line ~ /^#+ /) { h = line; sub(/^#+ /, "", h); lasth = trim(h) }
        continue
      }
      if (fenced && line ~ /^\*\*Done when:\*\* *[^ ]/) done_ok = 1
    }
    if (!fenced) emit("TEMPLATE-FORM", "the artifact template is not a fenced block")
    else if (lasth != "Decisions I cannot make")
      emit("TEMPLATE-FORM", "the artifact template must end with a Decisions I cannot make section")
    if (!done_ok) emit("TEMPLATE-DONE", "no **Done when:** line follows the artifact template")
  }

  # --- Capability boundary --------------------------------------------------
  if ("Capability boundary" in start) {
    in_exc = 0; exc_head = 0; exc = 0; exc_bad = 0; oneway = ""; outscope = 0
    for (j = 1; j <= body_n["Capability boundary"]; j++) {
      line = B["Capability boundary", j]
      if (line ~ /^- /) {
        in_exc = 0
        if (line ~ /^- \*\*Per-activity exceptions:\*\*/) { exc_head = 1; in_exc = 1 }
        else if (line ~ /^- \*\*One-way doors:\*\*/) { oneway = line; sub(/^- \*\*One-way doors:\*\* */, "", oneway); if (oneway == "") oneway = "-" }
        else if (line ~ /^- \*\*Out of scope:\*\* *[^ ]/) outscope = 1
        continue
      }
      if (in_exc && line ~ /^[ \t]+- /) {
        exc++
        if (line !~ /^[ \t]+- (agent-senior|structure-only|human-authority): [^ ]/) {
          exc_bad = 1
          emit("BOUNDARY-EXCEPTIONS", "exception \"" trim(line) "\" is not <tier>: <activity> with a known tier")
        }
      }
    }
    if (!exc_head || exc == 0) emit("BOUNDARY-EXCEPTIONS", "no **Per-activity exceptions:** with at least one <tier>: <activity> sub-bullet")
    if (oneway !~ /^human-authority/) emit("BOUNDARY-ONEWAY", "the **One-way doors:** line must state human-authority")
    if (!outscope) emit("BOUNDARY-OUTSCOPE", "no non-empty **Out of scope:** line")
  }

  # --- Escalation contract: typed triggers, known powers, full coverage ----
  if ("Escalation contract" in start) {
    nt = split("irreversibility missing-domain-authority confidence-floor contract-policy-change", T, " ")
    for (j = 1; j <= nt; j++) is_trigger[T[j]] = 1
    split("disregard override reverse halt", PW, " ")
    for (j = 1; j <= 4; j++) is_power[PW[j]] = 1
    for (j = 1; j <= body_n["Escalation contract"]; j++) {
      line = B["Escalation contract", j]
      if (line !~ /^- /) continue
      if (line !~ /^- \*\*[a-z-]+\*\* \(powers: [a-z, ]+\): [^ ]/) {
        emit("ESC-TYPED", "escalation line \"" substr(trim(line), 1, 60) "\" is not **<trigger>** (powers: <power>, ...): <when>")
        continue
      }
      tr = line; sub(/^- \*\*/, "", tr); sub(/\*\*.*$/, "", tr)
      pw = line; sub(/^[^(]*\(powers: /, "", pw); sub(/\).*$/, "", pw)
      if (!(tr in is_trigger)) { emit("ESC-TYPED", "escalation trigger \"" tr "\" is not in the taxonomy"); continue }
      declared[tr] = 1
      m = split(pw, pp, ",")
      for (k = 1; k <= m; k++) {
        p = trim(pp[k])
        if (!(p in is_power)) emit("ESC-TYPED", "escalation trigger " tr " names unknown power \"" p "\"")
      }
    }
    for (j = 1; j <= nt; j++)
      if (!(T[j] in declared)) emit("ESC-COVERAGE", "trigger class " T[j] " is not declared")
  }

  # --- Bench and pull-in triggers ------------------------------------------
  if (H["Bench"] == "yes" && !("Pull-in triggers" in filled))
    emit("BENCH-TRIGGERS", "Bench: yes needs a non-empty Pull-in triggers section")
  if (H["Bench"] == "no" && ("Pull-in triggers" in start))
    emit("BENCH-TRIGGERS", "a Pull-in triggers section belongs only on a Bench: yes card")

  # --- Identity and authority styling --------------------------------------
  for (i = 1; i <= n; i++) {
    l = " " tolower(L[i]) " "
    if (l ~ /[^a-z](you are an?|i am an?) / || l ~ /years of experience/ ||
        l ~ /[^a-z](world-class|renowned|seasoned|veteran|award-winning)[^a-z]/ ||
        l ~ /[^a-z]as an? (senior|expert|seasoned|veteran)[^a-z]/ ||
        l ~ /[^a-z]ph\.?d[^a-z]/)
      emit("STYLE-IDENTITY", "line " i " carries identity or authority styling")
  }
}
'

rc=0
tab=$(printf '\t')
for file in "$@"; do
  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    printf 'card-lint: %s: not a readable file\n' \
      "$(sanitize_printable "$file" '(unprintable path)')" >&2
    [ "$rc" -lt 2 ] && rc=2
    continue
  fi
  base=${file##*/}
  stem=${base%.md}
  [ "$stem" = "$base" ] && stem=
  findings=$(awk -v stem="$stem" -v major="$SUPPORTED_MAJOR" "$lint_awk" "$file") || {
    printf 'card-lint: %s: awk failed\n' "$(sanitize_printable "$file" '(unprintable path)')" >&2
    [ "$rc" -lt 2 ] && rc=2
    continue
  }
  [ -n "$findings" ] || continue
  file_rc=1
  while IFS="$tab" read -r code detail; do
    case $code in
      FMT-MISSING | FMT-UNSUPPORTED | FENCE-UNBALANCED) file_rc=3 ;;
    esac
    printf 'card-lint: ERROR %s: [%s] %s\n' \
      "$(sanitize_printable "$file" '(unprintable path)')" "$code" \
      "$(sanitize_printable "$detail" '(unprintable detail)')"
  done <<EOF
$findings
EOF
  [ "$file_rc" -gt "$rc" ] && rc=$file_rc
done
exit "$rc"
