# token-spend-report.awk: the report stage of token-spend.sh. Input one is the
# price table, input two the rows sorted by kind, session and time. Portable
# awk only: no gawk sort or time functions.

# epoch(<ISO-8601 UTC>): seconds since 1970, by the days-from-civil formula.
function epoch(iso,    y, m, d, era, yoe, doy, doe) {
  if (iso !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/) return 0
  y = substr(iso, 1, 4) + 0; m = substr(iso, 6, 2) + 0; d = substr(iso, 9, 2) + 0
  if (m <= 2) y--
  era = int(y / 400)
  yoe = y - era * 400
  doy = int((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return ((era * 146097 + doe - 719468) * 86400) + substr(iso, 12, 2) * 3600 + substr(iso, 15, 2) * 60 + substr(iso, 18, 2)
}

function price(model, k,    base) {
  if ((model, k) in P) return P[model, k]
  base = model
  sub(/\[.*$/, "", base)
  if ((base, k) in P) return P[base, k]
  if (!(model in unpriced)) {
    unpriced[model] = 1
    printf "token-spend: no price for model %s, priced at zero\n", model > "/dev/stderr"
  }
  return 0
}

function usd(model, i, c5, c1, ct, cr, o,    rest) {
  rest = ct - c5 - c1
  if (rest < 0) rest = 0
  return (i * price(model, "in") + (c5 + rest) * price(model, "w5") + c1 * price(model, "w1") + cr * price(model, "cr") + o * price(model, "out")) / 1e6
}

function kind_of(head, rules) {
  if (head ~ /planwright:mission-control/) return "mission-control"
  if (head ~ /planwright:tower/) return "tower"
  if (rules > 0 || head ~ /launched by planwright.s mission control/) return "mc-launched"
  if (head ~ /planwright:(execute-task|orchestrate)/) return "fleet-worker"
  if (head ~ /(polish|self-review|panel-review|bot-review|peer-review|code-review)/) return "review"
  if (head == "") return "unknown"
  return "interactive"
}

function m_(x) { return sprintf("%.1fM", x / 1e6) }
function d_(x) { return sprintf("$%.2f", x) }

FNR == NR {
  if ($0 ~ /^#/ || $1 == "model" || NF < 6) next
  P[$1, "in"] = $2; P[$1, "out"] = $3; P[$1, "cr"] = $4; P[$1, "w5"] = $5; P[$1, "w1"] = $6
  next
}

function sub_kind(h) {
  if (h ~ /([Rr]eview|[Ll]ens|[Vv]erif|[Ff]inding|[Pp]olish|[Aa]udit)/) return "review-or-verify"
  if (h ~ /([Ee]xplor|[Ss]earch|[Ll]ocate|[Ss]urvey)/) return "explore"
  if (h == "") return "unknown"
  return "other"
}

$1 == "s" {
  if ($3 == "main" && !($2 in head)) { head[$2] = $7; pchars[$2] = $5 + 0; rchars[$2] = $6 + 0 }
  if ($3 == "sub" && !(($2, $4) in subhead)) subhead[$2, $4] = $7
  next
}

$1 == "m" {
  mid = $2; s = $3; ag = $4; t = epoch($5); model = $6
  if (mid != "" && (mid in seen)) next
  if (mid != "") seen[mid] = 1
  i = $7 + 0; c5 = $8 + 0; c1 = $9 + 0; ct = $10 + 0; cr = $11 + 0; o = $12 + 0
  if (ct < c5 + c1) ct = c5 + c1
  if (i + ct + cr + o == 0) next
  cost = usd(model, i, c5, c1, ct, cr, o)
  wcost = usd(model, 0, c5, c1, ct, 0, 0)
  T["in"] += i; T["cw"] += ct; T["cr"] += cr; T["out"] += o; T["usd"] += cost; T["msgs"]++
  Tusd["in"] += usd(model, i, 0, 0, 0, 0, 0); Tusd["cw"] += wcost
  Tusd["cr"] += usd(model, 0, 0, 0, 0, cr, 0); Tusd["out"] += usd(model, 0, 0, 0, 0, 0, o)
  M[model] += cost; Mtok[model] += i + ct + cr + o
  if (!(s in sess)) { sess[s] = 1; ns++; first[s] = t }
  if (t > last[s]) last[s] = t
  S[s] += cost; Scr[s] += cr
  if ($14 != "") { bc[s, $14]++; if (bc[s, $14] > bbest[s]) { bbest[s] = bc[s, $14]; branch[s] = $14 } }
  day = substr($5, 1, 10); D[day] += cost; Dturn[day]++
  ctx = i + ct + cr
  if (ctx > maxctx[s]) maxctx[s] = ctx
  if (ag == "sub") {
    a = $15; if (!((s, a) in SubA)) { subs[++nsub] = s SUBSEP a }
    SubA[s, a] += cost; SubAw[s, a] += wcost; SubAo[s, a] += usd(model, 0, 0, 0, 0, 0, o)
    SubS[s] += cost; sub_tok += i + ct + cr + o; next
  }
  turns[s]++
  mcr[s] = (cr > 0) ? price(model, "cr") : mcr[s]
  if (turns[s] == 1) { cold_n++; cold_tok += ct; cold_usd += wcost; ColdS[s] = wcost; FirstCtx[s] = ctx }
  else if (t - lastmain[s] > idle) { idle_n++; idle_tok += ct; idle_usd += wcost; IdleS[s] += wcost }
  else if (turns[s] <= 10) { warm_tok += ct; WarmS[s] += wcost }
  if (turns[s] > 1 && t - lastmain[s] > 300 && t - lastmain[s] <= idle) { ttl_n++; ttl_extra += cr * (price(model, "w5") - price(model, "cr")) / 1e6 }
  lastmain[s] = t
  ttl_saved += c1 * (price(model, "w1") - price(model, "w5")) / 1e6
  if (cr > cap) { over_n++; over_tok += cr - cap; oc = usd(model, 0, 0, 0, 0, cr - cap, 0); over_usd += oc; OverS[s] += oc }
}

END {
  printf "== totals\n"
  printf "messages %d  sessions %d  dollars %s\n", T["msgs"], ns, d_(T["usd"])
  printf "input %s (%s)  cache-write %s (%s)  cache-read %s (%s)  output %s (%s)\n", \
    m_(T["in"]), d_(Tusd["in"]), m_(T["cw"]), d_(Tusd["cw"]), m_(T["cr"]), d_(Tusd["cr"]), m_(T["out"]), d_(Tusd["out"])

  printf "\n== by model (dollars, tokens, model)\n"
  cmd = "sort -t'\t' -k1.2,1nr"
  for (k in M) printf "%s\t%s\t%s\n", d_(M[k]), m_(Mtok[k]), k | cmd
  close(cmd)

  printf "\n== by day, UTC (last 14)\n"
  cmd = "sort | tail -n 14"
  for (k in D) printf "%s\t%s\t%d msgs\n", k, d_(D[k]), Dturn[k] | cmd
  close(cmd)

  for (s in sess) {
    k = kind_of(head[s], rchars[s]); K[k] += S[s]; Kn[k]++; Kt[k] += turns[s]
    Kcold[k] += ColdS[s]; Kidle[k] += IdleS[s]; Kwarm[k] += WarmS[s]; Kover[k] += OverS[s]
    Ksub[k] += SubS[s]; Kfirst[k] += FirstCtx[s]
    b = (s in branch) ? branch[s] : "-"
    B[b] += S[s]; Bn[b]++
    if (!(b in Bfirst) || first[s] < Bfirst[b]) { Bfirst[b] = first[s]; Bfs[b] = S[s] }
    if (pchars[s] > 0) {
      brief_tok += pchars[s] / 4 * turns[s]; brief_usd += pchars[s] / 4 * turns[s] * mcr[s] / 1e6
      rule_tok += rchars[s] / 4 * turns[s]; rule_usd += rchars[s] / 4 * turns[s] * mcr[s] / 1e6
      if (rchars[s] > 0) rule_n++
    }
  }
  for (b in B) if (Bn[b] > 1 && b !~ /^(main|HEAD|-)$/) { rep_n += Bn[b] - 1; rep_usd += B[b] - Bfs[b] }
  for (n = 1; n <= nsub; n++) {
    split(subs[n], sa, SUBSEP)
    sk = sub_kind(subhead[sa[1], sa[2]]); SK[sk] += SubA[sa[1], sa[2]]; SKn[sk]++; sub_usd += SubA[sa[1], sa[2]]
    SKw[sk] += SubAw[sa[1], sa[2]]; SKo[sk] += SubAo[sa[1], sa[2]]
  }

  printf "\n== by session kind (kind, sessions, turns, dollars, mean first-turn context, cold-start, warm-up, idle-rebuild, context-over-cap, sub-agents)\n"
  cmd = "sort -t'\t' -k4.2,4nr"
  for (k in K)
    printf "%s\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", k, Kn[k], Kt[k], d_(K[k]), m_(Kfirst[k] / Kn[k]), d_(Kcold[k]), d_(Kwarm[k]), d_(Kidle[k]), d_(Kover[k]), d_(Ksub[k]) | cmd
  close(cmd)

  printf "\n== sub-agents by prompt (kind, agents, dollars, of which cache-write, of which output)\n"
  cmd = "sort -t'\t' -k3.2,3nr"
  for (k in SK) printf "%s\t%d\t%s\t%s\t%s\n", k, SKn[k], d_(SK[k]), d_(SKw[k]), d_(SKo[k]) | cmd
  close(cmd)

  printf "\n== dearest sessions (dollars, session, kind, turns, days, peak context, cache-read, branch, head)\n"
  cmd = "sort -t'\t' -k1.2,1nr | head -n " top
  for (s in sess)
    printf "%s\t%s\t%s\t%d\t%.1f\t%s\t%s\t%s\t%s\n", d_(S[s]), s, kind_of(head[s], rchars[s]), turns[s], (last[s] - first[s]) / 86400, m_(maxctx[s]), m_(Scr[s]), ((s in branch) ? branch[s] : "-"), substr(head[s], 1, 70) | cmd
  close(cmd)

  printf "\n== dearest branches (dollars, sessions, branch)\n"
  cmd = "sort -t'\t' -k1.2,1nr | head -n " top
  for (b in B) printf "%s\t%d\t%s\n", d_(B[b]), Bn[b], b | cmd
  close(cmd)

  printf "\n== drivers (what, count, tokens, dollars)\n"
  printf "cold-start cache writes\t%d sessions\t%s\t%s\n", cold_n, m_(cold_tok), d_(cold_usd)
  printf "warm-up cache writes, main turns 2-10\t-\t%s\t%s\n", m_(warm_tok), d_(warm_usd_total())
  printf "idle-gap cache rebuilds (gap > %ds)\t%d rebuilds\t%s\t%s\n", idle, idle_n, m_(idle_tok), d_(idle_usd)
  printf "context above %d, cache-read\t%d turns\t%s\t%s\n", cap, over_n, m_(over_tok), d_(over_usd)
  printf "sub-agents\t%d agents\t%s\t%s\n", nsub, m_(sub_tok), d_(sub_usd)
  printf "repeat sessions on one branch, beyond the first\t%d sessions\t-\t%s\n", rep_n, d_(rep_usd)
  printf "first prompt re-read every turn, est. chars/4\t-\t%s\t%s\n", m_(brief_tok), d_(brief_usd)
  printf "mc-rules block re-read every turn, est.\t%d sessions\t%s\t%s\n", rule_n, m_(rule_tok), d_(rule_usd)
  printf "output\t-\t%s\t%s\n", m_(T["out"]), d_(Tusd["out"])
  printf "main-session cache writes at 5 minutes instead of 1 hour, net\t%d gaps of 5-60 min\t-\t%s\n", ttl_n, d_(ttl_saved - ttl_extra)
}

function warm_usd_total(    s, x) { for (s in WarmS) x += WarmS[s]; return x }
