# token-spend-report.awk: the report stage of token-spend.sh, run after
# token-spend-lib.awk over rows sorted by row type, session and time.
# Variables: idle and cap (seconds and tokens), top (rows per ranking).

BEGIN {
  CACHE_5M = 300; CACHE_1H = 3600
  WARM_TURNS = 10
  CHARS_PER_TOKEN = 4
}

function session_kind(head, rules) {
  if (head ~ /planwright:mission-control/) return "mission-control"
  if (head ~ /planwright:tower/) return "tower"
  if (rules > 0 || head ~ /launched by planwright.s mission control/) return "mc-launched"
  if (head ~ /planwright:(execute-task|orchestrate)/) return "fleet-worker"
  if (head ~ /(polish|self-review|panel-review|bot-review|peer-review|code-review)/) return "review"
  if (head == "") return "unknown"
  return "interactive"
}

function subagent_kind(h) {
  if (h ~ /([Rr]eview|[Ll]ens|[Vv]erif|[Ff]inding|[Pp]olish|[Aa]udit)/) return "review-or-verify"
  if (h ~ /([Ee]xplor|[Ss]earch|[Ll]ocate|[Ss]urvey)/) return "explore"
  if (h == "") return "unknown"
  return "other"
}

function mtok(x) { return sprintf("%.1fM", x / 1e6) }
function dollars(x) { return sprintf("$%.2f", x) }

$1 == "s" {
  if ($3 == "main" && !($2 in head)) { head[$2] = $7; pchars[$2] = $5 + 0; rchars[$2] = $6 + 0 }
  if ($3 == "sub" && !(($2, $4) in subhead)) subhead[$2, $4] = $7
  next
}

$1 == "m" {
  mid = $2; s = $3; chain = $4; ts = $5; t = epoch(ts); model = $6; branch_name = $14; agent = $15
  if (mid != "-") {
    if (mid in seen) next
    seen[mid] = 1
  }
  i = $7 + 0; c5 = $8 + 0; c1 = $9 + 0; ct = $10 + 0; cr = $11 + 0; o = $12 + 0
  if (ct < c5 + c1) ct = c5 + c1
  if (i + ct + cr + o == 0) next
  use_model(model)
  cost = usd(i, c5, c1, ct, cr, o)
  wcost = usd(0, c5, c1, ct, 0, 0)
  T["in"] += i; T["cw"] += ct; T["cr"] += cr; T["out"] += o; T["usd"] += cost; T["msgs"]++
  Tusd["in"] += i * Pin / 1e6; Tusd["cw"] += wcost
  Tusd["cr"] += cr * Pcr / 1e6; Tusd["out"] += o * Pout / 1e6
  M[model] += cost; Mtok[model] += i + ct + cr + o
  if (!(s in sess)) { sess[s] = 1; ns++ }
  if (t > 0) {
    if (!(s in first) || t < first[s]) first[s] = t
    if (t > last[s]) last[s] = t
    day = substr(ts, 1, 10); D[day] += cost; Dturn[day]++
  } else undated++
  S[s] += cost; Scr[s] += cr
  if (branch_name != "") {
    bc[s, branch_name]++
    if (bc[s, branch_name] > bbest[s]) { bbest[s] = bc[s, branch_name]; branch[s] = branch_name }
  }
  ctx = i + ct + cr
  if (chain == "sub") {
    if (!((s, agent) in SubA)) subs[++nsub] = s SUBSEP agent
    SubA[s, agent] += cost; SubAw[s, agent] += wcost; SubAo[s, agent] += o * Pout / 1e6
    SubS[s] += cost; sub_tok += i + ct + cr + o
    next
  }
  turns[s]++
  if (ctx > maxctx[s]) maxctx[s] = ctx
  if (cr > 0) cr_price[s] = Pcr
  gap = (t > 0 && lastmain[s] > 0) ? t - lastmain[s] : 0
  if (turns[s] == 1) {
    cold_n++; cold_tok += ct; cold_usd += wcost; ColdS[s] = wcost; FirstCtx[s] = ctx
  } else if (gap > idle && ct > 0) {
    idle_n++; idle_tok += ct; idle_usd += wcost; IdleS[s] += wcost
  } else if (turns[s] <= WARM_TURNS) {
    warm_tok += ct; warm_usd += wcost; WarmS[s] += wcost
  }
  if (turns[s] > 1 && gap > CACHE_5M && gap <= CACHE_1H) { ttl_n++; ttl_extra += cr * (Pw5 - Pcr) / 1e6 }
  ttl_saved += c1 * (Pw1 - Pw5) / 1e6
  if (t > 0) lastmain[s] = t
  if (cr > cap) { over_n++; over_tok += cr - cap; oc = (cr - cap) * Pcr / 1e6; over_usd += oc; OverS[s] += oc }
}

END {
  if (bad_prices) exit 2
  if (undated) printf "%s: %d messages carry no timestamp; counted, but not in times, gaps or days\n", prog, undated > "/dev/stderr"
  printf "== totals\n"
  printf "messages %d  sessions %d  dollars %s\n", T["msgs"], ns, dollars(T["usd"])
  printf "input %s (%s)  cache-write %s (%s)  cache-read %s (%s)  output %s (%s)\n", \
    mtok(T["in"]), dollars(Tusd["in"]), mtok(T["cw"]), dollars(Tusd["cw"]), mtok(T["cr"]), dollars(Tusd["cr"]), mtok(T["out"]), dollars(Tusd["out"])

  printf "\n== by model (dollars, tokens, model)\n"
  cmd = "sort -t'\t' -k1.2,1nr"
  for (k in M) printf "%s\t%s\t%s\n", dollars(M[k]), mtok(Mtok[k]), k | cmd
  close(cmd)

  printf "\n== by day, UTC (last 14)\n"
  cmd = "sort | tail -n 14"
  for (k in D) printf "%s\t%s\t%d msgs\n", k, dollars(D[k]), Dturn[k] | cmd
  close(cmd)

  for (s in sess) {
    k = session_kind(head[s], rchars[s]); kind[s] = k
    K[k] += S[s]; Kn[k]++; Kt[k] += turns[s]
    Kcold[k] += ColdS[s]; Kidle[k] += IdleS[s]; Kwarm[k] += WarmS[s]; Kover[k] += OverS[s]
    Ksub[k] += SubS[s]; Kfirst[k] += FirstCtx[s]
    b = (s in branch) ? branch[s] : "-"
    B[b] += S[s]; Bn[b]++
    fs = (s in first) ? first[s] : 0
    if (!(b in Bfirst) || fs < Bfirst[b]) { Bfirst[b] = fs; Bfirst_usd[b] = S[s] }
    if (pchars[s] > 0) {
      brief_tok += pchars[s] / CHARS_PER_TOKEN * turns[s]; brief_usd += pchars[s] / CHARS_PER_TOKEN * turns[s] * cr_price[s] / 1e6
      rule_tok += rchars[s] / CHARS_PER_TOKEN * turns[s]; rule_usd += rchars[s] / CHARS_PER_TOKEN * turns[s] * cr_price[s] / 1e6
      if (rchars[s] > 0) rule_n++
    }
  }
  for (b in B) if (Bn[b] > 1 && b !~ /^(main|HEAD|-)$/) { rep_n += Bn[b] - 1; rep_usd += B[b] - Bfirst_usd[b] }
  for (n = 1; n <= nsub; n++) {
    split(subs[n], sa, SUBSEP)
    sk = subagent_kind(subhead[sa[1], sa[2]])
    SK[sk] += SubA[sa[1], sa[2]]; SKn[sk]++; sub_usd += SubA[sa[1], sa[2]]
    SKw[sk] += SubAw[sa[1], sa[2]]; SKo[sk] += SubAo[sa[1], sa[2]]
  }

  printf "\n== by session kind (kind, sessions, turns, dollars, mean first-turn context, cold-start, warm-up, idle-rebuild, context-over-cap, sub-agents)\n"
  cmd = "sort -t'\t' -k4.2,4nr"
  for (k in K)
    printf "%s\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", k, Kn[k], Kt[k], dollars(K[k]), mtok(Kfirst[k] / Kn[k]), dollars(Kcold[k]), dollars(Kwarm[k]), dollars(Kidle[k]), dollars(Kover[k]), dollars(Ksub[k]) | cmd
  close(cmd)

  printf "\n== sub-agents by prompt (kind, agents, dollars, of which cache-write, of which output)\n"
  cmd = "sort -t'\t' -k3.2,3nr"
  for (k in SK) printf "%s\t%d\t%s\t%s\t%s\n", k, SKn[k], dollars(SK[k]), dollars(SKw[k]), dollars(SKo[k]) | cmd
  close(cmd)

  printf "\n== dearest sessions (dollars, session, kind, turns, days, peak context, cache-read, branch, head)\n"
  cmd = "sort -t'\t' -k1.2,1nr | head -n " top
  for (s in sess)
    printf "%s\t%s\t%s\t%d\t%.1f\t%s\t%s\t%s\t%s\n", dollars(S[s]), s, kind[s], turns[s], (s in first) ? (last[s] - first[s]) / 86400 : 0, mtok(maxctx[s]), mtok(Scr[s]), ((s in branch) ? branch[s] : "-"), substr(head[s], 1, 70) | cmd
  close(cmd)

  printf "\n== dearest branches (dollars, sessions, branch)\n"
  cmd = "sort -t'\t' -k1.2,1nr | head -n " top
  for (b in B) printf "%s\t%d\t%s\n", dollars(B[b]), Bn[b], b | cmd
  close(cmd)

  printf "\n== drivers (what, count, tokens, dollars)\n"
  printf "cold-start cache writes\t%d sessions\t%s\t%s\n", cold_n, mtok(cold_tok), dollars(cold_usd)
  printf "warm-up cache writes, main turns 2-%d\t-\t%s\t%s\n", WARM_TURNS, mtok(warm_tok), dollars(warm_usd)
  printf "idle-gap cache rebuilds (gap > %ds)\t%d rebuilds\t%s\t%s\n", idle, idle_n, mtok(idle_tok), dollars(idle_usd)
  printf "context above %d, cache-read\t%d turns\t%s\t%s\n", cap, over_n, mtok(over_tok), dollars(over_usd)
  printf "sub-agents\t%d agents\t%s\t%s\n", nsub, mtok(sub_tok), dollars(sub_usd)
  printf "repeat sessions on one branch, beyond the first\t%d sessions\t-\t%s\n", rep_n, dollars(rep_usd)
  printf "first prompt re-read every turn, est. chars/%d\t-\t%s\t%s\n", CHARS_PER_TOKEN, mtok(brief_tok), dollars(brief_usd)
  printf "mc-rules block re-read every turn, est.\t%d sessions\t%s\t%s\n", rule_n, mtok(rule_tok), dollars(rule_usd)
  printf "output\t-\t%s\t%s\n", mtok(T["out"]), dollars(Tusd["out"])
  printf "main-session cache writes at 5 minutes instead of 1 hour, net\t%d gaps of 5-60 min\t-\t%s\n", ttl_n, dollars(ttl_saved - ttl_extra)
}
