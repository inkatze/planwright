#!/bin/sh
# inception-render.sh — the dashboard-fields-only stub renderer (inception
# Task 2; REQ-G1.1, REQ-G1.2, REQ-C1.7 · D-9, D-12).
#
# SCOPE: this is a stub, and deliberately so. Task 2 needs the scaffolded
# pre-commit export-regeneration step to have a real renderer to call from the
# day a venture repo is created; Task 12 owns the actual renderer (dashboard
# and pitch-narrative modes, the shared escaper helper, the offered Artifact
# publish step) and REPLACES this file. What is here is the REQ-G1.2 status
# dashboard and nothing else: no mode selection, no narrative, no publish.
#
# What the stub does honor, because the scaffold depends on it:
#   - Deterministic output. Same bundle, same bytes. There is no render
#     timestamp; "today" enters only through the kill-date classification and
#     is overridable (PLANWRIGHT_INCEPTION_TODAY) so a run that straddles
#     midnight is reproducible.
#   - Self-contained HTML. One file, inline style, no network fetch.
#   - Escaped content. Bundle text is data, never markup.
#   - Version gating by DEFERRAL (REQ-C1.7): it calls the validator, which
#     owns the check, rather than re-implementing it. On an unsupported version
#     it refuses and leaves any existing export untouched, so a stale-but-valid
#     export is never replaced by a misparse.
#
# Usage:
#   inception-render.sh [--output <file>] <venture-dir>
#
# Exit: 0 rendered · 2 usage or environment error · 3 the validator failed
#   closed and the bundle was not validated at all (a missing file, an
#   unbalanced fence, or an unsupported format-version — its refusal, passed
#   through unchanged).
#
# Environment:
#   PLANWRIGHT_INCEPTION_TODAY   YYYY-MM-DD; defaults to the system date.
#
# Portable POSIX sh + awk; bash 3.2 / BSD tooling floor (REQ-K1.5).
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# The shared spec-parse grammar lib: the venture status declaration and the
# column-0 fence rule are the meta-spec's grammar, which the inception format
# inherits, so they come from the lib rather than from a private copy here (see
# the same note in inception-validate.sh). Sourced, never executed; fail closed
# when missing or unreadable (REQ-B1.6a).
spec_parse_sh="$script_dir/spec-parse.sh"
if [ ! -f "$spec_parse_sh" ] || [ ! -r "$spec_parse_sh" ]; then
  printf '%s\n' "inception-render: required helper $spec_parse_sh missing or not readable" >&2
  exit 2
fi
# shellcheck source=scripts/spec-parse.sh
. "$spec_parse_sh" || exit 2

usage() {
  echo "usage: inception-render.sh [--output <file>] <venture-dir>" >&2
  exit 2
}

output=
target=
while [ $# -gt 0 ]; do
  case $1 in
    --output)
      [ $# -ge 2 ] || usage
      output=$2
      shift 2
      ;;
    -*) usage ;;
    *)
      [ -z "$target" ] || usage
      target=$1
      shift
      ;;
  esac
done

[ -n "$target" ] || usage
while [ "$target" != "${target%/}" ]; do target=${target%/}; done
[ -n "$target" ] || target=/
[ -d "$target" ] || {
  echo "inception-render: not a directory: $target" >&2
  exit 2
}

# Readable, not executable, and run through /bin/sh: whatever copies a plugin
# tree onto a venture host may drop the +x bit without dropping the file, and
# refusing to render because of a file mode would take the export regeneration
# down with it. The validator declares #!/bin/sh, so this is what the kernel
# would have done with the bit set.
validator="$script_dir/inception-validate.sh"
[ -r "$validator" ] || {
  echo "inception-render: the validator is missing at $validator; refusing to render unchecked" >&2
  exit 2
}

# REQ-C1.7: the renderer refuses an unsupported version rather than parsing it,
# and defers to the validator's check instead of carrying its own copy.
vrc=0
/bin/sh "$validator" --version-check "$target" || vrc=$?
if [ "$vrc" -eq 3 ]; then
  # The validator fails closed for a missing file, an unbalanced fence, OR an
  # unsupported version, and hands all three back as exit 3. Point at its output
  # rather than naming one of the three: telling an operator their version is
  # unsupported when a file is simply absent sends them to the wrong line.
  echo "inception-render: refusing to render this bundle; the validator failed closed above and the export is unchanged" >&2
  exit 3
elif [ "$vrc" -ne 0 ]; then
  exit 2
fi

[ -n "$output" ] || output="$target/exports/venture.html"
outdir=$(dirname "$output")
mkdir -p "$outdir" || exit 2

today=${PLANWRIGHT_INCEPTION_TODAY:-$(date +%Y-%m-%d)}
case $today in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *)
    echo "inception-render: PLANWRIGHT_INCEPTION_TODAY must be YYYY-MM-DD" >&2
    exit 2
    ;;
esac

# Beside the destination, not in $TMPDIR: the rename below is only atomic
# within one filesystem, and /tmp is routinely a separate one (tmpfs), which
# turns the "never leave a truncated export" guarantee into a copy. Landing the
# temp file in $outdir also keeps mktemp's 0600 from becoming the mode of the
# published export — stakeholders read this file, so it gets the same explicit
# mode the scaffolded files get.
tmpout=$(mktemp "$outdir/.venture.html.XXXXXX") || exit 2
trap 'rm -f "$tmpout"' EXIT

# The status declaration comes from the lib and reaches awk through the
# environment, not through `-v`: awk expands backslash escapes in a `-v` value,
# and a bundle value is raw content that must reach the page verbatim.
INC_STATUS=$(spec_parse_header_value "$target/brief.md" Status 2>/dev/null) || INC_STATUS=
export INC_STATUS

awk -v today="$today" '
function esc(s) {
  gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s)
  gsub(/"/, "\\&quot;", s); gsub(/\047/, "\\&#39;", s)
  return s
}
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }

# A date that EXISTS, not merely one shaped like a date. days() below is happy
# to difference 2026-02-30 and hand back a state, and "tripped" is the state
# that tells a venture to kill or re-scope itself — so the calendar is checked
# here rather than trusted to have been checked upstream.
function date_ok(d,   y, m, dd, dim) {
  if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
  y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
  if (m < 1 || m > 12 || dd < 1) return 0
  dim = 31
  if (m == 4 || m == 6 || m == 9 || m == 11) dim = 30
  else if (m == 2) dim = ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) ? 29 : 28
  return (dd <= dim)
}

# Days since the civil epoch, so two ISO dates can be compared and differenced
# without a date(1) whose flags differ between GNU and BSD.
function days(d,   y, m, dd, era, yoe, doy, doe) {
  y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
  y -= (m <= 2)
  era = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + dd - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}

function flush_field(   key) {
  if (kind == "" || fld == "") { fld = ""; return }
  key = kind SUBSEP id SUBSEP fld
  F[key] = val; SEEN[key] = 1
  fld = ""
}

BEGIN { STATUS = ENVIRON["INC_STATUS"] }

FNR == 1 {
  flush_field()
  n = split(FILENAME, p, "/"); file = p[n]
  sect = ""; kind = ""; id = ""; fld = ""; seen_title = 0
}
'"$spec_parse_awk_fence"'

!seen_title && /^# / {
  seen_title = 1
  if (file == "brief.md") { t = $0; sub(/^# /, "", t); sub(/ — [A-Za-z]+$/, "", t); TITLE = trim(t) }
  next
}

/^## / { flush_field(); kind = ""; sect = $0; sub(/^## /, "", sect); sect = trim(sect); next }
/^### / {
  flush_field()
  h = $0; sub(/^### /, "", h); h = trim(h)
  id = h; sub(/ —.*$/, "", id); id = trim(id)
  nm = h; sub(/^[^—]*— */, "", nm)
  if (file == "assumptions.md") { kind = "A"; AN[++na] = id; NAME[id] = nm }
  else if (file == "decisions.md") { kind = "DEC"; DN[++nd] = id; NAME[id] = nm }
  else { kind = "" }
  next
}

file == "brief.md" && sect == "Kill criteria" && /^- \*\*KC-[^:*]*:\*\* / {
  k = $0; sub(/^- \*\*/, "", k); sub(/:\*\*.*$/, "", k)
  rest = $0; sub(/^- \*\*KC-[^:*]*:\*\*[ \t]*/, "", rest)
  if (rest ~ / — \*\*Superseded-by:\*\* /) next
  d = rest; sub(/^.* — by /, "", d); d = trim(d)
  sub(/ — by .*$/, "", rest)
  KCN[++nk] = k; KCTEXT[k] = trim(rest); KCDATE[k] = d
  next
}
file == "brief.md" && sect == "Success metric" && /[^ \t]/ && !/^_Skipped:/ {
  if (METRIC == "") METRIC = trim($0)
  next
}

/^- \*\*[^*]+:\*\*/ {
  flush_field()
  if (kind == "") next
  name = $0; sub(/^- \*\*/, "", name); sub(/:\*\*.*$/, "", name)
  v = $0; sub(/^- \*\*[^*]+:\*\*[ \t]?/, "", v)
  fld = name; val = trim(v)
  next
}
/^  [^ ]/ { if (kind != "" && fld != "") val = val " " trim($0); next }

END {
  flush_field()

  print "<!DOCTYPE html>"
  print "<html lang=\"en\"><head><meta charset=\"utf-8\">"
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
  print "<title>" esc(TITLE) " — venture dashboard</title>"
  print "<style>"
  print "body{font:16px/1.5 system-ui,sans-serif;margin:2rem auto;max-width:52rem;padding:0 1rem;color:#1a1a1a}"
  print "h1{margin-bottom:.25rem} h2{margin-top:2rem;font-size:1.15rem}"
  print ".meta{color:#555} ul{padding-left:1.25rem} li{margin:.35rem 0}"
  print ".tag{font:13px ui-monospace,monospace;background:#eee;border-radius:3px;padding:1px 5px}"
  print ".note{color:#666;font-size:.9rem;border-top:1px solid #ddd;margin-top:2.5rem;padding-top:.75rem}"
  print "</style></head><body>"
  print "<h1>" esc(TITLE) "</h1>"
  print "<p class=\"meta\">Status: <span class=\"tag\">" esc(STATUS) "</span></p>"

  print "<h2>Success metric</h2>"
  print "<p>" esc(METRIC == "" ? "not named" : METRIC) "</p>"

  # Blocking assumptions: live entries flagged Blocking: yes. A blocking
  # assumption is resolved once its status leaves the open/testing pair.
  print "<h2>Blocking assumptions</h2><ul>"
  nblock = 0; nunresolved = 0
  for (i = 1; i <= na; i++) {
    a = AN[i]
    if (SEEN["A" SUBSEP a SUBSEP "Superseded-by"]) continue
    if (F["A" SUBSEP a SUBSEP "Blocking"] != "yes") continue
    nblock++
    st = F["A" SUBSEP a SUBSEP "Status"]; sub(/ —.*$/, "", st)
    ev = F["A" SUBSEP a SUBSEP "Evidence"]; sub(/ —.*$/, "", ev)
    if (st == "open" || st == "testing") { nunresolved++; UNRES[nunresolved] = a }
    print "<li><span class=\"tag\">" esc(a) "</span> " esc(NAME[a]) \
      " — " esc(st) ", evidence " esc(ev) "</li>"
  }
  if (nblock == 0) print "<li>none</li>"
  print "</ul>"

  print "<h2>Kill criteria</h2><ul>"
  ntripped = 0; napproaching = 0; nundated = 0
  for (i = 1; i <= nk; i++) {
    k = KCN[i]
    # Only version-gating happens before this point, so a bundle the validator
    # would reject on KC-FORM still arrives intact. Date arithmetic over the
    # prose of a criterion produces a state rather than an error, and "tripped"
    # is the state that tells a venture to kill or re-scope itself — so an
    # unreadable date is said out loud, never computed on. That has to include a
    # date that is well-SHAPED but impossible: deferring the calendar check to
    # the validator only works for bundles the validator has passed, and this
    # renderer runs on ones it has not.
    if (!date_ok(KCDATE[k])) {
      state = "date unreadable"; nundated++; UNDATED[nundated] = k
      print "<li><span class=\"tag\">" esc(k) "</span> — " state \
        " — " esc(KCTEXT[k]) "</li>"
      continue
    }
    delta = days(KCDATE[k]) - days(today)
    if (delta < 0) { state = "tripped"; ntripped++; TRIP[ntripped] = k }
    else if (delta <= 30) { state = "approaching"; napproaching++ }
    else state = "clear"
    print "<li><span class=\"tag\">" esc(k) "</span> — " state \
      " — by " esc(KCDATE[k]) " — " esc(KCTEXT[k]) "</li>"
  }
  if (nk == 0) print "<li>none set</li>"
  print "</ul>"

  print "<h2>Open forks</h2><ul>"
  nopen = 0
  for (i = 1; i <= nd; i++) {
    d = DN[i]
    if (SEEN["DEC" SUBSEP d SUBSEP "Superseded-by"]) continue
    st = F["DEC" SUBSEP d SUBSEP "Status"]
    if (st != "open" && st != "deferred") continue
    nopen++
    print "<li><span class=\"tag\">" esc(d) "</span> " esc(NAME[d]) \
      " — " esc(st) ", " esc(F["DEC" SUBSEP d SUBSEP "Door"]) " door</li>"
  }
  if (nopen == 0) print "<li>none</li>"
  print "</ul>"

  print "<h2>Gate readiness</h2>"
  # Two separate facts, said separately. Minimum core is structural: whether the
  # bundle carries the pieces a gate needs. A tripped criterion is an OUTCOME
  # the gate will reach, not a piece that is missing — a venture can be complete
  # and still be one the gate kills. Collapsing them into one ready/not-ready
  # line made the page assert readiness while listing blockers underneath it.
  ready = (nunresolved == 0 && nopen == 0 && nk > 0 && METRIC != "")
  print "<p>" (ready ? "Minimum core is structurally met; the gate decider judges completeness." \
    : "Minimum core is not met yet; see the blockers below.") "</p>"
  if (ntripped > 0)
    print "<p>Separately, a kill criterion has tripped: the gate prompts kill-or-re-scope regardless of the core.</p>"

  print "<h2>Blockers</h2><ul>"
  nb = 0
  for (i = 1; i <= nunresolved; i++) {
    nb++
    print "<li><span class=\"tag\">" esc(UNRES[i]) "</span> blocking assumption is unresolved</li>"
  }
  for (i = 1; i <= ntripped; i++) {
    nb++
    print "<li><span class=\"tag\">" esc(TRIP[i]) "</span> kill criterion is tripped; the gate prompts kill-or-re-scope</li>"
  }
  for (i = 1; i <= nundated; i++) {
    nb++
    print "<li><span class=\"tag\">" esc(UNDATED[i]) "</span> has no readable date, so it cannot be classified; the validator names the format</li>"
  }
  if (nopen > 0) { nb++; print "<li>" nopen " open fork(s) still to decide</li>" }
  if (nk == 0) { nb++; print "<li>no kill criterion is set (minimum core)</li>" }
  if (METRIC == "") { nb++; print "<li>no success metric is named (minimum core)</li>" }
  if (nb == 0) print "<li>none</li>"
  print "</ul>"

  print "<p class=\"note\">Derived content, regenerated from the bundle on every"
  print "bundle-changing commit. Never hand-edit; never cite as evidence.</p>"
  print "</body></html>"
}
' "$target/brief.md" "$target/assumptions.md" "$target/decisions.md" >"$tmpout" || exit 2

# Write through a temp file so a mid-render failure never leaves a truncated
# export where a whole one used to be.
chmod 644 "$tmpout" || exit 2
mv "$tmpout" "$output" || exit 2
trap - EXIT
printf 'inception-render: wrote %s\n' "$output"
