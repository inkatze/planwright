# shellcheck shell=sh
# verdict-scan.sh — the verdict reader check-verdict-figures.sh and
# check-verdict-effort.sh share (sourced, never executed). It defines two awk
# programs; the verdict, rationale, citation and effort forms they read are
# documented in docs/substrate-bakeoff-report.md under "Citing a report in a
# verdict".
#
# verdict_scan_awk, run after spec-parse.sh's fence lexer and grammar over a
# design.md (so nothing inside a column-0 fence counts), prints one record
# per line, tab-separated:
#   V <dec> <line>          the decision is a verdict
#   P <dec> <line> <path>   a report path its **Report:** line names
#   S <dec> <kind> <line> <text>
#                           a rationale or effort span, its lines joined
#
# verdict_cite_awk holds the functions both guards evaluate spans with:
# cites() splits a span into figures and their citations, report_load()
# reads a committed report, and report_find() picks the report a verdict
# names that carries a candidate.

# shellcheck disable=SC2034,SC2016 # consumed by the sourcing guard; awk, not shell, expands it
verdict_scan_awk='
function vs_clean(s) { gsub(/[^[:print:]]/, "", s); return s }
function vs_flush() {
  if (span != "") printf "S\t%s\t%s\t%d\t%s\n", dec, kind, sline, vs_clean(span)
  span = ""; blank = 0
}
function vs_indent(s) { match(s, /^[ \t]*/); return RLENGTH }
FNR == 1 { dec = ""; span = "" }
/^#/ { vs_flush(); dec = ""; if (spec_parse_dec_attempt($0)) dec = spec_parse_dec_id($0); next }
dec == "" { next }
/^[ \t]*$/ { if (span != "") blank = 1; next }
span != "" {
  ind = vs_indent($0)
  if (($0 ~ /^[ \t]*(- )?\*\*[^*]+:\*\*/ && ind <= sindent) || (blank && ind == 0 && $0 !~ /^- /)) vs_flush()
  else { span = span " " $0; blank = 0 }
}
/^[ \t]*(- )?\*\*(Report|Measurements?|Cost-benefit):\*\*/ && !(dec in verdict) { verdict[dec] = 1; printf "V\t%s\t%d\n", dec, FNR }
/^[ \t]*(- )?\*\*Report:\*\*/ {
  rest = $0
  while (match(rest, /`[^`]*`/)) { printf "P\t%s\t%d\t%s\n", dec, FNR, vs_clean(substr(rest, RSTART + 1, RLENGTH - 2)); rest = substr(rest, RSTART + RLENGTH) }
}
span == "" && /^[ \t]*(- )?\*\*(Chosen because|Measurements?):\*\*/ { kind = "rationale"; span = $0; sline = FNR; sindent = vs_indent($0); blank = 0; next }
index($0, "**Migration effort:**") { vs_flush(); kind = "effort"; span = substr($0, index($0, "**Migration effort:**")); sline = FNR; sindent = vs_indent($0); blank = 0 }
END { spec_parse__fence_eof(); vs_flush() }
'

# shellcheck disable=SC2034,SC2016 # consumed by the sourcing guard; awk, not shell, expands it
verdict_cite_awk='
function vc_norm(tok) {
  gsub(/,/, "", tok)
  if (tok ~ /\./) { sub(/0+$/, "", tok); sub(/\.$/, "", tok) }
  sub(/^0+/, "", tok)
  if (tok == "" || tok ~ /^\./) tok = "0" tok
  return tok
}
# cites(s, fig, ref, cref): fill fig[1..n] with the figures span s holds and
# ref[i] with the citation following fig[i] ("" when none); cref[1..m] with
# every citation in s. Returns n; the citation count lands in vc_nref.
function cites(s, fig, ref, cref,   n, k, t, rest, pos, tok, pre, post, prefix, after) {
  k = 0; t = ""; rest = s
  while (match(rest, /\(`[a-z0-9][a-z0-9-]*\.[a-z0-9_]+`\)/)) {
    cref[++k] = substr(rest, RSTART + 2, RLENGTH - 4)
    t = t substr(rest, 1, RSTART - 1) "(@" k "@)"
    rest = substr(rest, RSTART + RLENGTH)
  }
  vc_nref = k
  s = t rest; t = s; n = 0; pos = 0
  while (match(t, /[0-9]+(,[0-9][0-9][0-9])*(\.[0-9]+)?/)) {
    tok = substr(t, RSTART, RLENGTH)
    pre = (pos + RSTART > 1) ? substr(s, pos + RSTART - 1, 1) : ""
    post = substr(s, pos + RSTART + RLENGTH, 2)
    prefix = substr(s, 1, pos + RSTART - 1)
    after = substr(s, pos + RSTART + RLENGTH)
    pos += RSTART + RLENGTH - 1
    t = substr(t, RSTART + RLENGTH)
    if (pre ~ /[A-Za-z0-9_\/#@:.,`-]/) continue
    # A unit glued to a figure (`14ms`, `3x`) keeps it a figure.
    if (substr(post, 1, 1) ~ /[A-Za-z0-9_\/`-]/ && after !~ /^(ms|s|min|h|x|B|KiB|MiB|GiB|kB|KB|MB|GB)([^A-Za-z0-9_]|$)/) continue
    if (post ~ /^[.:,][0-9]/) continue
    if (prefix ~ /(^|[^A-Za-z])([Tt]ask|[Ss]ection|[Ss]tep|[Ww]ave)[ ]+$/) continue
    if (prefix ~ /(^|[^A-Za-z])([Tt]asks|[Ss]ections|[Ss]teps|[Ww]aves)[ ]+([0-9.]+(, | and | or | to | through |, and |, or |–|-))*$/) continue
    if (prefix ~ /(^|[^A-Za-z])([Tt]ask|[Ss]ection|[Ss]tep|[Ww]ave)[ ]+[0-9.]+(–|-| to | through )$/) continue
    fig[++n] = tok; ref[n] = ""
    if (match(after, /^[A-Za-z\/%]*( [A-Za-z\/%]+)? \(@[0-9]+@\)/)) {
      tok = substr(after, 1, RLENGTH); sub(/^.*\(@/, "", tok); sub(/@\)$/, "", tok)
      ref[n] = cref[tok + 0]
    }
  }
  return n
}
# report_load(p): read the report at repository-relative path p under
# VS_ROOT; returns 1, or 0 with vc_err set.
function report_load(p,   f, line, r, nf, a, i, c, ncol) {
  if (p in vc_loaded) { vc_err = vc_lerr[p]; return vc_loaded[p] }
  vc_loaded[p] = 0
  if (p !~ /^[A-Za-z0-9._][A-Za-z0-9._\/-]*$/ || p ~ /(^|\/)\.\.(\/|$)/) { vc_lerr[p] = "report " p " is not a plain repository-relative path"; vc_err = vc_lerr[p]; return 0 }
  f = ENVIRON["VS_ROOT"] "/" p
  r = (getline line < f)
  if (r <= 0) { vc_lerr[p] = "report " p " is missing or empty"; vc_err = vc_lerr[p]; return 0 }
  ncol = split(line, a, "\t"); c = 0
  for (i = 1; i <= ncol; i++) { vc_col[p, i] = a[i]; vc_hasf[p, a[i]] = 1; if (a[i] == "candidate") c = i }
  if (!c) { close(f); vc_lerr[p] = "report " p " has no candidate column"; vc_err = vc_lerr[p]; return 0 }
  while ((r = (getline line < f)) > 0) {
    nf = split(line, a, "\t")
    vc_row[p, a[c]] = 1
    for (i = 1; i <= ncol; i++) vc_val[p, a[c], vc_col[p, i]] = (i <= nf ? a[i] : "")
  }
  close(f)
  if (r < 0) { vc_lerr[p] = "report " p " could not be read"; vc_err = vc_lerr[p]; return 0 }
  vc_loaded[p] = 1
  return 1
}
# vs_record(): file a scan record; V and P land in vs_verdict and vs_path,
# S in vs_s_*. Run on every record before END.
function vs_record() {
  if ($1 == "V") { vs_verdict[$2] = $3; return }
  if ($1 == "P") { vs_np[$2]++; vs_path[$2, vs_np[$2]] = $4; return }
  if ($1 == "S") { vs_ns++; vs_s_dec[vs_ns] = $2; vs_s_kind[vs_ns] = $3; vs_s_line[vs_ns] = $4; vs_s_text[vs_ns] = $5 }
}
# report_find(dec, cand): the first report dec names that carries a row for
# cand; "" when none does, "!" when one could not be read (vc_err says why).
function report_find(dec, cand,   k, p) {
  for (k = 1; k <= vs_np[dec]; k++) {
    p = vs_path[dec, k]
    if (!report_load(p)) return "!"
    if ((p, cand) in vc_row) return p
  }
  return ""
}
'
