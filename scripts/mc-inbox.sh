#!/usr/bin/env bash
# mc-inbox.sh — the inbox duty's mechanics: the one status form, the shape
# every delivered item carries, and drafts for people put on the clipboard,
# never sent.
#
# `mc-inbox.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-inbox
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2

help_text() {
  cat <<'HELP'
mc-inbox.sh — the inbox duty's mechanics: the one status form, the shape
every delivered item carries, and drafts for people put on the clipboard,
never sent.

Delivery itself (presence, one item or one coupled cluster per turn,
ranking, batching) is the operator queue's; the wording is the session's,
in the operator's domain words.

Usage:
  mc-inbox.sh status
      stdin: <section><TAB><text> lines, section decision, landed or
      moving; stdout: the status form, always in this order and never with
      history:
        Decisions / Landed / Moving
      each a heading and its `- <text>` lines, `- none` when empty. A line
      of any other section is dropped and counted on stderr.
  mc-inbox.sh item --link <url> --does <text> --asked <text> --right <text>
                   --option <label>=<effect>... --recommend <text>
                   --checked <text>
      the item, answerable alone: the full link (http or https), what the
      thing does, what is asked, whether it is right, each option and what
      it would do (at least two), the recommendation and what was checked
      to ground it. A missing or empty field is refused, named.
  mc-inbox.sh draft --program <p> --to <recipient> --file <body>
      put the draft on the clipboard (mission_control_clipboard: `auto`
      takes the first of pbcopy, wl-copy, xclip and xsel found; otherwise
      the absolute path of a command that reads the text on stdin; read
      from the core, adopter and machine-local layers only, a repo-tracked
      value ignored with a warning; the machine-local file is the gitignored
      planwright.local.yml, so a repository that commits one anyway is
      choosing it) and log it to the program home's
      kb/inbox/drafts.tsv ("# format: 1", then
      <UTC time><TAB><recipient><TAB><bytes><TAB><SHA-256>, never the
      text). Nothing is sent: this script has no sending path; sending
      waits for the operator's yes on the exact text and recipient.
        clipboard<TAB><recipient><TAB><bytes>

Exit codes: 0 done; 1 a refused item, no clipboard tool, or a store that
cannot be written; 2 usage; 3 the program is not configured.

Portable bash 3.2 / BSD tooling.
HELP
}

usage() {
  mc_usage_fail "usage: mc-inbox.sh status | item --link <url> ... | draft --program <p> --to <recipient> --file <body>"
}

case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac
[ $# -ge 1 ] || usage
verb=$1
shift

case $verb in
  status)
    [ $# -eq 0 ] || usage
    awk -F '\t' '
      $1 == "decision" { d[++nd] = substr($0, 10); next }
      $1 == "landed" { l[++nl] = substr($0, 8); next }
      $1 == "moving" { m[++nm] = substr($0, 8); next }
      NF { dropped++ }
      END {
        print "Decisions"; if (!nd) print "- none"; for (i = 1; i <= nd; i++) print "- " d[i]
        print ""; print "Landed"; if (!nl) print "- none"; for (i = 1; i <= nl; i++) print "- " l[i]
        print ""; print "Moving"; if (!nm) print "- none"; for (i = 1; i <= nm; i++) print "- " m[i]
        if (dropped) printf "mc-inbox: %d line(s) outside decision, landed and moving dropped; status carries no history\n", dropped > "/dev/stderr"
      }' | mc_clean_text
    ;;
  item)
    link=""
    does=""
    asked=""
    right=""
    recommend=""
    checked=""
    options=()
    while [ $# -gt 0 ]; do
      case $1 in
        --link | --does | --asked | --right | --recommend | --checked | --option)
          [ $# -ge 2 ] || usage
          mc_valid_text "$2" || mc_usage_fail "$1 takes text with no control byte"
          case $1 in
            --link) link=$2 ;;
            --does) does=$2 ;;
            --asked) asked=$2 ;;
            --right) right=$2 ;;
            --recommend) recommend=$2 ;;
            --checked) checked=$2 ;;
            --option) options+=("$2") ;;
          esac
          shift 2
          ;;
        *) usage ;;
      esac
    done
    missing=""
    [ -n "$link" ] || missing="$missing --link"
    [ -n "$does" ] || missing="$missing --does"
    [ -n "$asked" ] || missing="$missing --asked"
    [ -n "$right" ] || missing="$missing --right"
    [ -n "$recommend" ] || missing="$missing --recommend"
    [ -n "$checked" ] || missing="$missing --checked"
    [ -z "$missing" ] || mc_fail "the item lacks$missing; an item must be answerable alone"
    case $link in
      http://?* | https://?*) ;;
      *) mc_fail "the item's --link is not a full link: $(sanitize_printable "$link")" ;;
    esac
    [ "${#options[@]}" -ge 2 ] || mc_fail "the item needs at least two --option <label>=<effect>"
    for o in "${options[@]}"; do
      case $o in
        ?*=?*) ;;
        *) mc_fail "an option takes <label>=<effect>: $(sanitize_printable "$o")" ;;
      esac
    done
    {
      printf '%s\n' "$link" "What it does: $does" "Asked: $asked" "Is it right: $right" "Options:"
      for o in "${options[@]}"; do printf -- '- %s: %s\n' "${o%%=*}" "${o#*=}"; done
      printf '%s\n' "Recommendation: $recommend" "Checked: $checked"
    } | mc_clean_text
    ;;
  draft)
    program=""
    to=""
    file=""
    while [ $# -gt 0 ]; do
      case $1 in
        --program | --to | --file)
          [ $# -ge 2 ] || usage
          mc_valid_text "$2" || mc_usage_fail "$1 takes text with no control byte"
          case $1 in
            --program) program=$2 ;;
            --to) to=$2 ;;
            --file) file=$2 ;;
          esac
          shift 2
          ;;
        *) usage ;;
      esac
    done
    [ -n "$program" ] && [ -n "$to" ] && [ -n "$file" ] || usage
    [ -f "$file" ] && [ -r "$file" ] || mc_fail "the draft is unreadable: $(sanitize_printable "$file")"
    mc_require_program "$program"
    parse_clip() {
      case $1 in
        auto) printf 'auto\n' ;;
        /*)
          case $1 in *[!A-Za-z0-9._/-]*) return 1 ;; esac
          printf '%s\n' "$1"
          ;;
        *) return 1 ;;
      esac
    }
    # The knob names a command this script runs, so the repo-tracked layer,
    # the one a repository commits, is not read for it.
    layers=$(/bin/sh "$script_dir/config-get.sh" --layers mission_control_clipboard 2>/dev/null) \
      || mc_fail "mission_control_clipboard cannot be read"
    clip=""
    while IFS='	' read -r layer raw; do
      [ -n "$layer" ] || continue
      case $layer in
        repo-tracked)
          printf '%s\n' "$prog: warning: the repo-tracked value of mission_control_clipboard is ignored; set it in the adopter or machine-local layer" >&2
          continue
          ;;
      esac
      if clip=$(parse_clip "$raw"); then
        break
      fi
      case $layer in
        adopter | machine-local)
          printf '%s\n' "$prog: warning: the $layer value of mission_control_clipboard is invalid ('$(sanitize_printable "$raw")'); degrading to the next lower layer" >&2
          clip=""
          ;;
        *) mc_fail "mission_control_clipboard: invalid $layer value '$(sanitize_printable "$raw")'" ;;
      esac
    done <<EOF
$(printf '%s\n' "$layers" | awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }')
EOF
    [ -n "$clip" ] || mc_fail "mission_control_clipboard is not set (broken install)"
    set --
    if [ "$clip" = auto ]; then
      if command -v pbcopy >/dev/null 2>&1; then
        set -- pbcopy
      elif command -v wl-copy >/dev/null 2>&1; then
        set -- wl-copy
      elif command -v xclip >/dev/null 2>&1; then
        set -- xclip -selection clipboard
      elif command -v xsel >/dev/null 2>&1; then
        set -- xsel --clipboard --input
      else
        mc_fail "no clipboard tool found (pbcopy, wl-copy, xclip or xsel); set mission_control_clipboard"
      fi
    else
      [ -x "$clip" ] || mc_fail "mission_control_clipboard names no executable: $clip"
      set -- "$clip"
    fi
    home=$(mc_program_home "$program") || exit 1
    store="$home/kb/inbox/drafts.tsv"
    trap 'mc_kb_unlock; [ -z "${snap:-}" ] || rm -f "$snap"' EXIT
    mkdir -p "${store%/*}" || mc_fail "cannot create ${store%/*}"
    mc_kb_lock "$program" inbox/drafts.tsv
    mc_store_init "$store"
    # One snapshot feeds the clipboard, the size and the hash, so the log
    # describes exactly what went on the clipboard.
    snap=$(mktemp) || mc_fail "cannot create a scratch file"
    cat "$file" >"$snap" || mc_fail "the draft cannot be read"
    bytes=$(wc -c <"$snap" | tr -d ' ')
    sum=$(mc_sha256 <"$snap") || mc_fail "no SHA-256 tool"
    "$@" <"$snap" >/dev/null 2>&1 || mc_fail "the clipboard command failed"
    printf '%s\t%s\t%s\t%s\n' "$(mc_iso "$(mc_now)")" "$to" "$bytes" "$sum" >>"$store" || mc_fail "the draft is on the clipboard, but the drafts log cannot be appended: $store"
    printf 'clipboard\t%s\t%s\n' "$to" "$bytes"
    ;;
  *) usage ;;
esac
