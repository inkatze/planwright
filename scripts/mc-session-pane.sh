# shellcheck shell=bash
# mc-session-pane.sh — finding a program's mission-control session in the
# process table, the tmux pane above it, and whether that pane shows an open
# dialog (sourced, never executed). Read by scripts/mc-escalate.sh, which
# watches for a mission control stuck on its own dialog, and by
# scripts/mc-pane-answer.sh, which delivers an operator's choice to it, so
# both judge the same pane the same way.
#
# The session is the claude process of this user whose last two arguments
# are `/planwright:mission-control <program>`; its pane is the tmux pane
# whose process is that one or an ancestor of it. The caller sources
# scripts/fleet-pane-vocabulary.sh first, and every value read from the
# pane is data: nothing here evaluates it.

MSP_PANE_LINES=20
MSP_ANCESTRY_MAX=32

# msp_ps: the process table as `<pid> <ppid> <uid> <args>` lines.
msp_ps() {
  ps -ww -A -o pid= -o ppid= -o uid= -o args= 2>/dev/null
}

# msp_find <program> <ps table>: the session's pid, or `absent` / `ambiguous`.
# Only this user's processes count, so another account's process cannot
# stand in for the session or make it ambiguous.
msp_find() {
  printf '%s\n' "$2" | P=$1 U=$(id -u) awk '
    {
      if ($1 !~ /^[0-9]+$/ || $3 != ENVIRON["U"] || NF < 6) next
      n = split($4, a, "/")
      if (a[n] != "claude") next
      if ($(NF - 1) != "/planwright:mission-control" || $NF != ENVIRON["P"]) next
      c++; pid = $1
    }
    END { if (c == 0) print "absent"; else if (c > 1) print "ambiguous"; else print pid }'
}

# msp_panes: the tmux panes as `<pane id><TAB><pane pid>` lines.
msp_panes() {
  tmux list-panes -a -F '#{pane_id}	#{pane_pid}' 2>/dev/null
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

# msp_trim: stdin's last MSP_PANE_LINES lines up to its last non-blank one,
# so a saved capture and a live one read the same.
msp_trim() {
  awk 'NF { last = NR } { l[NR] = $0 } END { for (i = 1; i <= last; i++) print l[i] }' | tail -n "$MSP_PANE_LINES"
}

# msp_options <pane text>: the open dialog's option lines as
# `<digit><TAB><label>`, the selection cursor dropped and each label cut at
# its first run of three blanks, where a pane's side panel begins.
msp_options() {
  printf '%s\n' "$1" | awk '
    {
      s = $0
      sub(/^[ \t]+/, "", s)
      sub(/^❯[ \t]*/, "", s)
      if (s !~ /^[1-9]\.[ \t]/) next
      d = substr(s, 1, 1)
      l = substr(s, 3)
      sub(/^[ \t]+/, "", l)
      i = index(l, "   ")
      if (i) l = substr(l, 1, i - 1)
      print d "\t" l
    }'
}

# msp_dialog <pane text>: 0 when the pane shows an open dialog, setting
# MSP_KIND (`auto-mode` for auto mode's own confirmation, `dialog` for any
# other) and MSP_PRINT (a digest of its options, which tells one dialog from
# the next). A dialog is open when a line carrying a dialog signature (the
# shared vocabulary's permission and select-menu needles, or the selection
# cursor on a numbered option) has no input prompt, idle-footer anchor or
# busy marker below it: one that does is an answered dialog left in the
# scrollback, or text that merely quotes one.
msp_dialog() {
  MSP_KIND=""
  MSP_PRINT=""
  md_lc=$(printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]')
  md_last=$(printf '%s\n' "$md_lc" | SIG="$(
    permission_prompt_signatures
    default_selection_prompt_signatures
  )" awk '
    BEGIN { n = split(ENVIRON["SIG"], s, "\n") }
    {
      for (i = 1; i <= n; i++) if (s[i] != "" && index($0, s[i])) { last = NR; next }
      if ($0 ~ /^[ \t]*❯[ \t]*[0-9]+\./) last = NR
    }
    END { print last + 0 }')
  [ "$md_last" -gt 0 ] || return 1
  md_after=$(printf '%s\n' "$md_lc" | tail -n "+$((md_last + 1))")
  if [ -n "$md_after" ]; then
    printf '%s\n' "$(
      busy_markers
      spinner_words
      prompt_anchors
    )" | { contains_any "$md_after"; } && return 1
    printf '%s\n' "$md_after" | awk '
      { s = $0; sub(/^[ \t]+/, "", s); sub(/^│[ \t]*/, "", s)
        if (s ~ /^❯/ && s !~ /^❯[ \t]*[0-9]+\./) f = 1
        if (s ~ /^> /) f = 1 }
      END { exit !f }' && return 1
  fi
  case $md_lc in
    *'consecutive actions were blocked'* | *'auto mode needs your confirmation'*) MSP_KIND=auto-mode ;;
    *) MSP_KIND=dialog ;;
  esac
  md_opts=$(msp_options "$1")
  # shellcheck disable=SC2034 # read by the scripts that source this file
  MSP_PRINT=$(printf '%s|%s\n' "$MSP_KIND" "$md_opts" | mc_sha256 | cut -c1-16) || MSP_PRINT=unhashed
  return 0
}

# msp_widening <label>: 0 when choosing the option would widen the
# session's permissions for later calls (an allow rule it adds), which no
# relayed answer may do.
msp_widening() {
  case $(printf '%s' "$1" | tr '[:upper:]' '[:lower:]') in
    *'ask again'* | *'always allow'* | *'allow all'* | *'for this session'*) return 0 ;;
  esac
  return 1
}
