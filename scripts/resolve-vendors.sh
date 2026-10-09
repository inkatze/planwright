#!/usr/bin/env bash
# resolve-vendors.sh — the vendors catalog, merged, validated, and grouped by
# vendor. docs/quota.md is the reference for the adapter contract; this header
# pins the output shape and the field grammars it enforces.
#
# The catalog merges through scripts/resolve-catalog.sh, unchanged: the core
# seed config/vendors.yaml, then the adopter, repo-tracked, and machine-local
# `vendors.yaml` overlays (append/union, supersede-by-id). Every merged entry
# is validated here; a malformed one follows the by-layer policy: core is a
# broken install (exit 5), repo-tracked hard-fails (exit 4), and an adopter
# or machine-local entry is dropped with a warning naming its reason. A part
# that depends on a dropped entry (its vendor entry, or a choice's control)
# is dropped with it, whatever its own layer.
#
# Two entries that conflict (a second vendor entry for one vendor, or two
# choice pairs at one position of one rule) are an override when they come
# from different layers: the higher-precedence layer's entry wins and the
# other is dropped, with a warning naming both entries and their layers.
# Only a conflict within one layer is malformed, the later entry in merged
# order taking that layer's policy.
#
# Usage:
#   resolve-vendors.sh [--vendor <id>] [--explain]
#     (no flag)    one line per resolved part, grouped by vendor (vendors in
#                  the merged order of their vendor entries; within one, the
#                  vendor line, then recognizers and controls in merged
#                  order, then choice pairs by rule and position):
#                    vendor<TAB><vendor><TAB><evidence><TAB><bot-login|->
#                    recognizer<TAB><vendor><TAB><name><TAB><match><TAB><reset-after|->
#                    control<TAB><vendor><TAB><name><TAB>comment-body|args<TAB><value>
#                    choice<TAB><vendor><TAB><rule><TAB><position><TAB><condition><TAB><control>
#     --explain    the same order, one `<vendor><TAB><part><TAB><id><TAB><layer>`
#                  line per part, naming the layer that supplied it.
#     --vendor     only that vendor's lines; the id is checked against the
#                  step-id grammar before any use.
#
# Entry grammar (every value a single-line scalar the catalog reader keeps; a
# control byte, a C1 control, an invisible or bidi code point (the set
# scripts/flight-text.sh's INVIS_SED names), invalid UTF-8, an empty declared
# field, or a block-scalar indicator is malformed):
#   id            <vendor>.<name>, both halves ^[a-z][a-z0-9-]*$ (at most 64
#                 bytes each), the first equal to the entry's `vendor`
#   vendor        the step-id grammar above
#   part          vendor | recognizer | control | choice
#   vendor part   evidence (claude-frames | none); bot-login, optional, the
#                 REST form <login>[bot], the login [A-Za-z0-9] runs joined by
#                 single hyphens, at most 39 bytes; exactly one per vendor
#   recognizer    match, a fixed case-sensitive string of at most 256 bytes;
#                 reset-after, optional, the fixed prefix a stated reset time
#                 follows, at most 256 bytes and never `-`
#   control       exactly one of comment-body (at most 1024 bytes, needing the
#                 vendor's bot-login; it mentions no handle but `@<login>`,
#                 and carries no `#<digit>`, `GH-<digit>`, `://`, or `www.`,
#                 and no `//`, `](`, or `<`, the link and HTML forms, nor an
#                 HTML entity, which could spell a mention or reference)
#                 and args (blank-separated words in custom-steps' plain-word
#                 args charset [A-Za-z0-9._/:=@%,+-]; a word opening with `@`,
#                 a word opening with `-` that is not `-<alnum>`,
#                 `--<name>`, or `--<name>=<value>` whose value opens with
#                 neither `-` nor `@`, is an option injection)
#   choice        rule (the step-id grammar), position (a positive integer of
#                 at most six digits, unique within the vendor's rule),
#                 condition (no-prior-review | prior-review), control (the
#                 name of a control the same vendor declares)
#
# Exit: 0 resolved (a degraded overlay entry warned and dropped included) ·
# 2 usage · 3 --vendor names no resolved vendor · 4 a malformed repo-tracked
# catalog or entry · 5 a broken install (a malformed core seed or entry, an
# unusable catalog resolver) · 6 the resolution could not be printed.
#
# Portable bash 3.2 / BSD tooling; POSIX awk without interval expressions.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

TAB=$(printf '\t')
prog=resolve-vendors

usage() {
  printf '%s\n' "usage: resolve-vendors.sh [--vendor <id>] [--explain]" >&2
  exit 2
}

# valid_id <token>: the step-id grammar ^[a-z][a-z0-9-]*$, at most 64 bytes.
valid_id() {
  case "$1" in
    "" | [!a-z]* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

mode=plain
want=""
want_set=0
while [ $# -gt 0 ]; do
  case "$1" in
    --explain) mode=explain ;;
    --vendor)
      [ $# -ge 2 ] || usage
      want=$2
      want_set=1
      shift
      ;;
    -h | --help)
      awk 'NR>=2 { if ($0 ~ /^#/) { sub(/^# ?/, ""); print } else exit }' "$0"
      exit 0
      ;;
    *) usage ;;
  esac
  shift
done
if [ "$want_set" -eq 1 ] && ! valid_id "$want"; then
  printf '%s\n' "$prog: --vendor is outside the step-id grammar" >&2
  exit 2
fi

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 5
catalog="$script_dir/resolve-catalog.sh"
[ -r "$catalog" ] || {
  printf '%s\n' "$prog: the catalog resolver is missing (broken install)" >&2
  exit 5
}

work=$(mktemp -d "${TMPDIR:-/tmp}/resolve-vendors.XXXXXX") || exit 5
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

# diag: forward diagnostics with control bytes dropped, newlines kept, each
# distinct line once.
diag() { awk '!seen[$0]++' | tr -d '\000-\011\013-\037\177\200-\237' >&2; }

rc=0
/bin/bash "$catalog" vendors >"$work/merged" 2>"$work/err" || rc=$?
rc2=0
/bin/bash "$catalog" vendors --explain >"$work/layers" 2>>"$work/err" || rc2=$?
[ "$rc" -ne 0 ] || rc=$rc2
if [ "$rc" -ne 0 ]; then
  diag <"$work/err"
  if grep -q '^resolve-catalog: vendors: repo-tracked ' "$work/err"; then
    printf '%s\n' "$prog: the repo-tracked vendors catalog is malformed; refusing to degrade a shared team catalog" >&2
    exit 4
  fi
  printf '%s\n' "$prog: the vendors catalog is unusable (resolve-catalog exit $rc) (broken install)" >&2
  exit 5
fi
# An entry or line the catalog reader skipped: core is a broken install,
# repo-tracked hard-fails, anything else degrades (the warning stands, and
# an entry that lost a line is malformed below).
if grep -q '^resolve-catalog: vendors: core ' "$work/err"; then
  diag <"$work/err"
  printf '%s\n' "$prog: the core vendors catalog is malformed (an entry or line the catalog reader skipped) (broken install)" >&2
  exit 5
fi
if grep -q '^resolve-catalog: vendors: repo-tracked ' "$work/err"; then
  diag <"$work/err"
  printf '%s\n' "$prog: the repo-tracked vendors catalog is malformed (an entry or line the catalog reader skipped); refusing to degrade a shared team catalog" >&2
  exit 4
fi
# Keyed by layer and id: a lost line in an entry a later layer supersedes
# never taints the entry that replaced it.
awk '
  !/" carries an indented line that is not a field; skipping the line$/ { next }
  sub(/^resolve-catalog: vendors: adopter entry "/, "") { l = "adopter" }
  sub(/^resolve-catalog: vendors: machine-local entry "/, "") { l = "machine-local" }
  l != "" {
    sub(/" carries an indented line that is not a field; skipping the line$/, "")
    print l "\t" $0
    l = ""
  }
' "$work/err" >"$work/lost"
grep -q '[^[:space:]]' "$work/merged" || {
  printf '%s\n' "$prog: the core vendors seed contributed no entry (broken install)" >&2
  exit 5
}

# A line that loses bytes to the cleaning step-record and flight-text apply
# (invalid UTF-8, C1 controls, invisible and bidi code points) carries a
# character a terminal or a posted comment would act on.
if [ -r "$script_dir/flight-text.sh" ] && command -v iconv >/dev/null 2>&1; then
  # shellcheck source=scripts/flight-text.sh
  . "$script_dir/flight-text.sh"
else
  printf '%s\n' "$prog: flight-text.sh or iconv is missing (broken install)" >&2
  exit 5
fi
c1_sed=$(printf 's/\302[\200-\237]//g')
iconv -c -f UTF-8 -t UTF-8 <"$work/merged" 2>/dev/null \
  | sed -e ':a' -e "$INVIS_SED" -e "$c1_sed" -e 't a' >"$work/clean" || {
  printf '%s\n' "$prog: cannot clean the merged catalog (broken install)" >&2
  exit 5
}

awk -v mode="$mode" -v want="$want" '
  BEGIN { UNCLEAN = "a C1, invisible, or bidi character, or invalid UTF-8, in a field" }
  function sid(s) { return s ~ /^[a-z][a-z0-9-]*$/ && length(s) <= 64 }
  function has(n, k) { return ((n, k) in fset) }
  function val(n, k) { return has(n, k) ? fval[n, k] : "" }

  # bad <n> <reason>: the by-layer policy for a malformed entry.
  function bad(n, reason,   l) {
    l = layer[id[n]]
    if (l == "core") {
      print "F\t5\tcore vendors catalog entry " id[n] " is malformed (" reason ") (broken install)"
      fatal = 1
      exit 5
    }
    if (l == "repo-tracked") {
      print "F\t4\trepo-tracked vendors catalog entry " id[n] " is malformed (" reason "); refusing to degrade a shared team catalog"
      fatal = 1
      exit 4
    }
    print "W\twarning: " l " vendors catalog entry " id[n] " is malformed (" reason "); dropped"
    drop[n] = 1
  }
  # override <a> <b>: two conflicting entries from different layers; the
  # higher-precedence layer wins, the other is dropped with a warning naming
  # both. Returns the winner.
  function override(a, b,   w, l) {
    if (rank(layer[id[b]]) > rank(layer[id[a]])) { w = b; l = a } else { w = a; l = b }
    print "W\twarning: vendors catalog entry " id[w] " from the " layer[id[w]] " layer shadows " id[l] " from the " layer[id[l]] " layer"
    drop[l] = 1
    return w
  }
  function rank(l) {
    return (l == "core") ? 1 : (l == "adopter") ? 2 : (l == "repo-tracked") ? 3 : 4
  }
  # cascade <n> <why>: dropped because an entry it depends on was.
  function cascade(n, why) {
    print "W\twarning: " layer[id[n]] " vendors catalog entry " id[n] " is dropped (" why ")"
    drop[n] = 1
  }

  # args_fault <args>: "" when every word passes, else the reason. The word
  # charset is the one resolve-steps.sh command_word_ok checks; they change
  # together.
  function args_fault(a,   w, m, i, v) {
    m = split(a, w, /[ ]+/)
    for (i = 1; i <= m; i++) {
      if (w[i] == "") continue
      if (w[i] !~ /^[A-Za-z0-9._\/:=@%,+-]+$/) return "args outside the plain-word grammar"
    }
    for (i = 1; i <= m; i++) {
      if (w[i] == "") continue
      if (w[i] ~ /^@/) return "args carry an option injection"
      if (w[i] !~ /^-/) continue
      if (w[i] ~ /^-[A-Za-z0-9]$/ || w[i] ~ /^--[A-Za-z0-9][A-Za-z0-9-]*$/) continue
      if (w[i] ~ /^--[A-Za-z0-9][A-Za-z0-9-]*=/) {
        v = w[i]
        sub(/^[^=]*=/, "", v)
        if (v != "" && v !~ /^[-@]/) continue
      }
      return "args carry an option injection"
    }
    return ""
  }

  # mention_fault <body> <login>: "" when every @-mention is the bot.
  function mention_fault(b, login,   bot, i, c, h, j) {
    bot = login
    sub(/\[bot\]$/, "", bot)
    for (i = 1; i <= length(b); i++) {
      if (substr(b, i, 1) != "@") continue
      c = substr(b, i + 1, 1)
      if (c !~ /[A-Za-z0-9]/) continue
      j = i + 1
      while (j <= length(b) && substr(b, j, 1) ~ /[A-Za-z0-9-]/) j++
      h = substr(b, i + 1, j - i - 1)
      if (h != bot || substr(b, j, 1) == "/") return "comment-body mentions a handle other than the bot login"
    }
    return ""
  }

  # check <n>: the entry-level rules; "" when well-formed.
  function check(n,   i, p, k, v, ks, nk, allowed, req, r) {
    if (mark[n] != "") return mark[n]
    if (sec[n] != "vendors") return "entry outside the vendors: section"
    if ((layer[id[n]] "\t" id[n]) in lost) return "an indented line the catalog reader skipped"
    p = index(id[n], ".")
    if (p == 0 || !sid(substr(id[n], 1, p - 1)) || !sid(substr(id[n], p + 1))) return "id is not <vendor>.<name>"
    if (!has(n, "vendor")) return "missing required field '\''vendor'\''"
    if (!sid(val(n, "vendor"))) return "vendor outside the step-id grammar"
    if (substr(id[n], 1, p - 1) != val(n, "vendor")) return "id prefix is not the entry'\''s vendor"
    if (!has(n, "part")) return "missing required field '\''part'\''"
    p = val(n, "part")
    if (p == "vendor") { allowed = "|evidence|bot-login|"; req = "evidence" }
    else if (p == "recognizer") { allowed = "|match|reset-after|"; req = "match" }
    else if (p == "control") { allowed = "|comment-body|args|"; req = "" }
    else if (p == "choice") { allowed = "|rule|position|condition|control|"; req = "rule position condition control" }
    else return "unknown part"
    nk = split(keys[n], ks, "|")
    for (i = 1; i <= nk; i++) {
      k = ks[i]
      if (k == "" || k == "vendor" || k == "part") continue
      if (index(allowed, "|" k "|") == 0) return "unknown field '\''" k "'\'' for a " p
    }
    for (i = 1; i <= nk; i++) {
      k = ks[i]
      if (k == "") continue
      v = fval[n, k]
      if (v ~ /^[|>][0-9+-]?[0-9+-]?$/) return "a block scalar (the catalog reader takes single-line scalars only)"
      if (v == "") return "empty " k
    }
    r = split(req, ks, " ")
    for (i = 1; i <= r; i++) if (!has(n, ks[i])) return "missing required field '\''" ks[i] "'\''"
    if (p == "vendor") {
      v = val(n, "evidence")
      if (v != "claude-frames" && v != "none") return "unknown evidence kind"
      if (has(n, "bot-login")) {
        v = val(n, "bot-login")
        if (v !~ /^[A-Za-z0-9]+(-[A-Za-z0-9]+)*\[bot\]$/ || length(v) > 44) return "bot-login is not a GitHub bot login (<login>[bot])"
      }
    } else if (p == "recognizer") {
      if (length(val(n, "match")) > 256) return "match exceeds 256 bytes"
      if (has(n, "reset-after")) {
        if (val(n, "reset-after") == "-") return "reset-after of exactly '\''-'\'' (the empty-field sentinel)"
        if (length(val(n, "reset-after")) > 256) return "reset-after exceeds 256 bytes"
      }
    } else if (p == "control") {
      if (has(n, "comment-body") == has(n, "args")) return "a control declares exactly one of '\''comment-body'\'' and '\''args'\''"
      if (has(n, "comment-body")) {
        v = val(n, "comment-body")
        if (length(v) > 1024) return "comment-body exceeds 1024 bytes"
        v = tolower(v)
        if (v ~ /&(#[0-9]+|#x[0-9a-f]+|[a-z][a-z0-9]*);/) return "comment-body carries an HTML entity"
        if (v ~ /#[0-9]/ || v ~ /gh-[0-9]/ || index(v, "://") || index(v, "www.")) return "comment-body carries an issue or URL reference"
        if (index(v, "//") || index(v, "](") || index(v, "<")) return "comment-body carries a link or HTML markup"
      } else {
        v = args_fault(val(n, "args"))
        if (v != "") return v
      }
    } else {
      if (!sid(val(n, "rule"))) return "rule outside the step-id grammar"
      v = val(n, "position")
      if (v !~ /^[1-9][0-9]*$/ || length(v) > 6) return "position is not a positive integer"
      v = val(n, "condition")
      if (v != "no-prior-review" && v != "prior-review") return "unknown condition"
      if (!sid(val(n, "control"))) return "control outside the step-id grammar"
    }
    return ""
  }

  FILENAME == ARGV[1] { lost[$0] = 1; next }
  FILENAME == ARGV[2] {
    l = $0
    sub(/.*\t/, "", l)
    layer[substr($0, 1, length($0) - length(l) - 1)] = l
    next
  }
  FILENAME == ARGV[3] { clean[FNR] = $0; next }
  { dirty = ($0 != clean[FNR]) }
  /^[ \t]*#/ { next }
  /^[^ \t]/ {
    have = 0
    section = ($0 ~ /^[A-Za-z][A-Za-z0-9_-]*:[ \t]*$/) ? $0 : ""
    sub(/:[ \t]*$/, "", section)
    next
  }
  /^[ \t]*$/ { next }
  section != "" && /^  -[ \t]+id:/ {
    raw = $0
    sub(/^  -[ \t]+id:[ \t]*/, "", raw)
    sub(/[ \t]*$/, "", raw)
    if (raw ~ /^".*"$/ && length(raw) >= 2) raw = substr(raw, 2, length(raw) - 2)
    n++
    have = 1
    id[n] = raw
    sec[n] = section
    keys[n] = "|"
    mark[n] = (raw ~ /[[:cntrl:]]/) ? "a control byte in a field" : ""
    if (dirty) mark[n] = UNCLEAN
    next
  }
  have && /^    [A-Za-z]/ {
    raw = $0
    sub(/^    /, "", raw)
    if (raw ~ /:/) { key = raw; sub(/:.*/, "", key); v = raw; sub(/^[^:]*:[ \t]*/, "", v) }
    else { key = raw; v = "" }
    sub(/[ \t]*$/, "", v)
    if (v ~ /^".*"$/ && length(v) >= 2) v = substr(v, 2, length(v) - 2)
    if (dirty) { if (mark[n] == "") mark[n] = UNCLEAN; next }
    if (key ~ /[[:cntrl:]]/ || v ~ /[[:cntrl:]]/) { if (mark[n] == "") mark[n] = "a control byte in a field"; next }
    if (key == "supersede") next
    if ((n, key) in fset) { if (mark[n] == "") mark[n] = "a repeated field '\''" key "'\''"; next }
    if (key !~ /^[a-z][a-z-]*$/) { if (mark[n] == "") mark[n] = "a field name outside [a-z-]"; next }
    fset[n, key] = 1
    fval[n, key] = v
    keys[n] = keys[n] key "|"
    next
  }
  have { if (mark[n] == "") mark[n] = "an indented line that is not a field"; next }

  END {
    if (fatal) exit
    for (i = 1; i <= n; i++) {
      if (!(id[i] in layer)) { print "F\t5\tresolve-catalog'\''s two views disagree on entry " id[i] " (broken install)"; exit 5 }
      r = check(i)
      if (r != "") bad(i, r)
      if (fatal) exit
    }
    # One vendor entry per vendor; across layers the higher one overrides.
    for (i = 1; i <= n; i++) {
      if (drop[i] || val(i, "part") != "vendor") continue
      v = val(i, "vendor")
      # Same-layer duplicates are tracked apart from the winner, which may be
      # an entry from a higher layer visited first.
      if ((v, layer[id[i]]) in vlay) { bad(i, "a second vendor entry for vendor '\''" v "'\''"); if (fatal) exit; continue }
      vlay[v, layer[id[i]]] = i
      if (v in vent) {
        if (override(vent[v], i) == i) vent[v] = i
        continue
      }
      vent[v] = i
      vorder[++nv] = v
    }
    for (i = 1; i <= n; i++) if (drop[i] && val(i, "part") == "vendor") vdropped[val(i, "vendor")] = 1
    # Every other part needs its vendor entry.
    for (i = 1; i <= n; i++) {
      if (drop[i] || val(i, "part") == "vendor") continue
      v = val(i, "vendor")
      if (v in vent) continue
      if (v in vdropped) cascade(i, "its vendor entry for '\''" v "'\'' was dropped")
      else { bad(i, "vendor '\''" v "'\'' has no vendor entry"); if (fatal) exit }
    }
    # Controls: a comment body needs the bot login and mentions only it.
    for (i = 1; i <= n; i++) {
      if (drop[i] || val(i, "part") != "control") continue
      v = val(i, "vendor")
      if (has(i, "comment-body")) {
        if (!has(vent[v], "bot-login")) { bad(i, "a comment-body control on a vendor with no bot-login"); if (fatal) exit; continue }
        r = mention_fault(val(i, "comment-body"), val(vent[v], "bot-login"))
        if (r != "") { bad(i, r); if (fatal) exit; continue }
      }
    }
    for (i = 1; i <= n; i++) {
      if (val(i, "part") != "control") continue
      k = substr(id[i], index(id[i], ".") + 1)
      if (drop[i]) cdropped[val(i, "vendor"), k] = 1
      else ctl[val(i, "vendor"), k] = 1
    }
    # Choices: the control exists on the same vendor; a position is unique.
    for (i = 1; i <= n; i++) {
      if (drop[i] || val(i, "part") != "choice") continue
      v = val(i, "vendor")
      k = val(i, "control")
      if (!((v, k) in ctl)) {
        if ((v, k) in cdropped) cascade(i, "its control '\''" k "'\'' was dropped")
        else { bad(i, "choice names control '\''" k "'\'', which vendor '\''" v "'\'' does not declare"); if (fatal) exit }
        continue
      }
      if ((v, val(i, "rule"), val(i, "position") + 0, layer[id[i]]) in play) {
        bad(i, "rule '\''" val(i, "rule") "'\'' already has a pair at position " val(i, "position")); if (fatal) exit
        continue
      }
      play[v, val(i, "rule"), val(i, "position") + 0, layer[id[i]]] = i
      if ((v, val(i, "rule"), val(i, "position") + 0) in pos) {
        if (override(pos[v, val(i, "rule"), val(i, "position") + 0], i) != i) continue
      }
      pos[v, val(i, "rule"), val(i, "position") + 0] = i
    }

    found = 0
    for (q = 1; q <= nv; q++) {
      v = vorder[q]
      if (want != "" && v != want) continue
      found = 1
      vi = vent[v]
      emit(vi, "vendor\t" v "\t" val(vi, "evidence") "\t" (has(vi, "bot-login") ? val(vi, "bot-login") : "-"))
      for (i = 1; i <= n; i++) {
        if (drop[i] || val(i, "vendor") != v) continue
        k = substr(id[i], index(id[i], ".") + 1)
        if (val(i, "part") == "recognizer")
          emit(i, "recognizer\t" v "\t" k "\t" val(i, "match") "\t" (has(i, "reset-after") ? val(i, "reset-after") : "-"))
        else if (val(i, "part") == "control")
          emit(i, "control\t" v "\t" k "\t" (has(i, "args") ? "args\t" val(i, "args") : "comment-body\t" val(i, "comment-body")))
      }
      # Choice pairs: rules in first-seen order, positions ascending.
      nr = 0
      for (i = 1; i <= n; i++) {
        if (drop[i] || val(i, "vendor") != v || val(i, "part") != "choice") continue
        rl = val(i, "rule")
        if (!((v, rl) in rseen)) { rseen[v, rl] = 1; rules[++nr] = rl }
      }
      for (t = 1; t <= nr; t++) {
        last = 0
        while (1) {
          best = 0
          for (i = 1; i <= n; i++) {
            if (drop[i] || val(i, "vendor") != v || val(i, "part") != "choice" || val(i, "rule") != rules[t]) continue
            p = val(i, "position") + 0
            if (p > last && (best == 0 || p < val(best, "position") + 0)) best = i
          }
          if (best == 0) break
          last = val(best, "position") + 0
          emit(best, "choice\t" v "\t" rules[t] "\t" val(best, "position") "\t" val(best, "condition") "\t" val(best, "control"))
        }
      }
    }
    if (want != "" && !found) print "N"
  }
  function emit(i, line) {
    if (mode == "explain") print "O\t" val(i, "vendor") "\t" val(i, "part") "\t" id[i] "\t" layer[id[i]]
    else print "O\t" line
  }
' "$work/lost" "$work/layers" "$work/clean" "$work/merged" >"$work/result"
awk_rc=$?

# The reader's degraded-layer warnings, then this validator's.
[ ! -s "$work/err" ] || diag <"$work/err"
sed -n "s/^W$TAB//p" "$work/result" | sed "s/^/$prog: /" | diag
fatal_line=$(sed -n "s/^F$TAB//p" "$work/result" | head -n 1)
if [ -n "$fatal_line" ]; then
  code=${fatal_line%%"$TAB"*}
  printf '%s\n' "$prog: ${fatal_line#*"$TAB"}" | diag
  exit "$code"
fi
[ "$awk_rc" -eq 0 ] || {
  printf '%s\n' "$prog: the vendors validator failed (awk exit $awk_rc) (broken install)" >&2
  exit 5
}
if grep -qx 'N' "$work/result"; then
  printf '%s\n' "$prog: no resolved adapter declares the requested vendor" >&2
  exit 3
fi
sed -n "s/^O$TAB//p" "$work/result" || {
  printf '%s\n' "$prog: cannot print the resolution" >&2
  exit 6
}
