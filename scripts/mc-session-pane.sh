# shellcheck shell=bash
# mc-session-pane.sh — a program's mission-control session in the process
# table, the tmux pane above it, and the dialog that pane shows (sourced,
# never executed), shared by scripts/mc-escalate.sh and
# scripts/mc-pane-answer.sh so both judge one pane the same way. The caller
# sources scripts/mc-lib.sh and scripts/fleet-pane-vocabulary.sh first.
# The auto-mode phrases, the footers and rule glyphs that bound a dialog,
# and the answerable labels are this file's, beyond the reach of the
# vocabulary's overrides; every other dialog string is the vocabulary's. Pane text is data throughout:
# nothing here evaluates it.

MSP_PANE_LINES=40
MSP_ANCESTRY_MAX=32

# The process-table read, for `sh -c`: `<pid> <ppid> <uid or user> <args>`
# lines. busybox ps knows neither -ww nor the uid column, so its form names
# the user.
# shellcheck disable=SC2034 # read by the scripts that source this file
MSP_PS_CMD='ps -ww -A -o pid= -o ppid= -o uid= -o args= 2>/dev/null || ps -o pid,ppid,user,args'

# msp_find <program> <ps table>: the session's pid, or `absent` / `ambiguous`.
# Only this user's processes count, so another account's process can neither
# stand in for the session nor make it ambiguous.
msp_find() {
  printf '%s\n' "$2" | P=$1 U=$(id -u) N=$(id -un 2>/dev/null) awk '
    {
      if ($1 !~ /^[0-9]+$/ || NF < 6) next
      if ($3 != ENVIRON["U"] && (ENVIRON["N"] == "" || $3 != ENVIRON["N"])) next
      n = split($4, a, "/")
      if (a[n] != "claude") next
      if ($(NF - 1) != "/planwright:mission-control" || $NF != ENVIRON["P"]) next
      c++; pid = $1
    }
    END { if (c == 0) print "absent"; else if (c > 1) print "ambiguous"; else print pid }'
}

# msp_pane_of <pid> <ps table> <panes>: the pane whose process is <pid> or an
# ancestor of it; fails when none is.
msp_pane_of() {
  {
    printf '%s\n' "$3" | awk -F '\t' 'NF == 2 && $1 ~ /^%[0-9]+$/ && $2 ~ /^[0-9]+$/ { print "pane\t" $1 "\t" $2 }'
    printf '%s\n' "$2" | awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { print "proc\t" $1 "\t" $2 }'
  } | S=$1 M=$MSP_ANCESTRY_MAX awk -F '\t' '
    $1 == "pane" { pane[$3] = $2 }
    $1 == "proc" { parent[$2] = $3 }
    END {
      p = ENVIRON["S"]
      for (i = 0; i < ENVIRON["M"] + 0 && p != "" && p + 0 > 1; i++) {
        if (p in pane) { print pane[p]; exit 0 }
        p = parent[p]
      }
      exit 1
    }'
}

# msp_ancestor <pid> <of> <ps table>: 0 when <pid> is <of> or an ancestor of it.
msp_ancestor() {
  printf '%s\n' "$3" | T=$1 S=$2 M=$MSP_ANCESTRY_MAX awk '
    $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { parent[$1] = $2 }
    END {
      p = ENVIRON["S"]
      for (i = 0; i < ENVIRON["M"] + 0 && p + 0 > 1; i++) { if (p == ENVIRON["T"]) exit 0; p = parent[p] }
      exit 1
    }'
}

# msp_trim: stdin with the mission-control side panel cut off each line (the
# text after a last `│` past column 40 that follows a blank or a rule) and
# trailing blanks dropped, keeping the last MSP_PANE_LINES lines up to the
# last non-blank one, so a saved capture and a live one read the same.
msp_trim() {
  awk '{
      s = $0; cut = 0; rest = s; off = 0
      while ((i = index(rest, "│")) > 0) {
        p = off + i
        if (p > 40 && (substr(s, p - 1, 1) == " " || substr(s, p - length("─"), length("─")) == "─")) cut = p
        off = p + length("│") - 1; rest = substr(s, off + 1)
      }
      if (cut) s = substr(s, 1, cut - 1)
      sub(/[ \t]+$/, "", s)
      l[NR] = s; if (s != "") last = NR
    }
    END { for (i = 1; i <= last; i++) print l[i] }' | tail -n "$MSP_PANE_LINES"
}

# msp_dialog <trimmed pane text>: 0 when the pane shows an open dialog,
# setting MSP_KIND (`auto-mode` for auto mode's own confirmation, `dialog`
# otherwise), MSP_OPTIONS (the dialog's own option run as
# `<digit><TAB><label>`, empty unless it runs 1, 2, 3 in order, as a label
# that wraps or a repeated digit breaks it) and
# MSP_PRINT (a digest of the dialog's text). The last line carrying a
# signature of the shared vocabulary, or the selection cursor on a numbered
# option, ends the dialog; an input prompt, idle anchor or busy marker below
# that line means it is not open, being scrollback or a quotation. Options
# are read only from the run just above that line, never from scrollback.
msp_dialog() {
  MSP_KIND="" MSP_OPTIONS="" MSP_PRINT=""
  md_sig=$(
    permission_prompt_signatures
    default_selection_prompt_signatures
  )
  md_tail=$(
    busy_markers
    spinner_words
    prompt_anchors
  )
  md_in=$(input_prompt_prefixes)
  md_out=$(printf '%s\n' "$1" | SIG=$md_sig TAIL=$md_tail IN=$md_in awk '
    BEGIN {
      ns = split(tolower(ENVIRON["SIG"]), sig, "\n")
      nt = split(tolower(ENVIRON["TAIL"]), tl, "\n")
      ni = split(ENVIRON["IN"], inp, "\n")
    }
    { line[NR] = $0; lc[NR] = tolower($0) }
    function option(i,   s) { s = line[i]; sub(/^[ \t]+/, "", s); sub(/^❯[ \t]*/, "", s); return (s ~ /^[1-9]\.[ \t]/) ? s : "" }
    function signed(i,   k, s) {
      for (k = 1; k <= ns; k++) if (sig[k] != "" && index(lc[i], sig[k])) return 1
      s = line[i]; sub(/^[ \t]+/, "", s); return s ~ /^❯[ \t]*[1-9]\./
    }
    function closes(i,   k, s) {
      for (k = 1; k <= nt; k++) if (tl[k] != "" && index(lc[i], tl[k])) return 1
      s = line[i]; sub(/^[ \t]+/, "", s)
      for (k = 1; k <= ni; k++) {
        if (inp[k] == "") continue
        if (s == inp[k]) return 1
        if (index(s, inp[k] " ") == 1 && !(inp[k] == "❯" && option(i) != "")) return 1
      }
      return 0
    }
    function footer(i) { return lc[i] ~ /esc to cancel|to navigate|enter to select|tab to amend/ }
    END {
      for (i = NR; i >= 1; i--) if (signed(i)) { end = i; break }
      if (!end) exit 1
      for (i = end + 1; i <= NR; i++) if (closes(i)) exit 1
      for (i = end; i >= 1; i--) if (option(i) != "") { olast = i; break }
      bad = 0
      if (olast) {
        ofirst = olast
        while (ofirst > 1 && option(ofirst - 1) != "") ofirst--
        for (i = olast + 1; i < end; i++) if (line[i] ~ /[^ \t]/ && !footer(i)) bad = 1
        for (i = ofirst; i <= olast; i++) {
          s = option(i); d = substr(s, 1, 1); l = substr(s, 3); sub(/^[ \t]+/, "", l)
          if (d + 0 != no + 1) bad = 1
          opt[++no] = d "\t" l
        }
      }
      start = olast ? ofirst : end
      # The dialog reaches up to the rule that opens it, at most a dozen lines.
      top = start
      while (top > 1 && top > start - 12 && !index(line[top - 1], "────────") && !index(line[top - 1], "╌╌╌╌╌╌╌╌")) top--
      kind = "dialog"
      for (i = top; i <= end; i++) if (lc[i] ~ /consecutive actions were blocked|auto mode needs your confirmation/) kind = "auto-mode"
      print "kind\t" kind
      if (!bad) for (i = 1; i <= no; i++) print "option\t" opt[i]
      for (i = top; i <= end; i++) { s = line[i]; sub(/^[ \t]+/, "", s); sub(/^❯[ \t]*/, "", s); print "block\t" s }
    }') || return 1
  # shellcheck disable=SC2034 # these three are read by the scripts that source this file
  MSP_KIND=$(printf '%s\n' "$md_out" | awk -F '\t' '$1 == "kind" { print $2; exit }')
  # shellcheck disable=SC2034
  MSP_OPTIONS=$(printf '%s\n' "$md_out" | awk -F '\t' '$1 == "option" { print $2 "\t" $3 }')
  md_h=$(printf '%s\n' "$md_out" | grep -v '^option' | mc_sha256) || md_h=""
  # shellcheck disable=SC2034
  MSP_PRINT=${md_h%"${md_h#????????????????}"}
  [ -n "$MSP_PRINT" ] || MSP_PRINT=unhashed
  return 0
}

# msp_answerable <label>: 0 for an option that answers this one dialog and
# nothing more. Anything else (a rule for later calls, a mode switch, a
# directory or trust grant, a wording this list has not met) is refused.
msp_answerable() {
  ma_l=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed "s/’/'/g; s/[[:space:]]*(esc)\$//; s/[[:space:]]*\$//")
  case $ma_l in
    yes | no | 'no, and tell claude what to do differently' | 'yes, but ask again next time') return 0 ;;
  esac
  return 1
}
