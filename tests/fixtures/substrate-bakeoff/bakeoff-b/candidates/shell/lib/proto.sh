# shellcheck shell=bash
# proto.sh — the hardened-shell candidate's seam for bake-off B (sourced).
#
# Prototype scope: it serves this bake-off's two entry points and nothing
# else. It loads the production hook code rather than copying it, so the
# shell candidate is measured on what the hooks run: the tokenizer of
# scripts/worker-command-guard.sh and the predicate of scripts/ready-guard.sh.
# Neither hook can be sourced (each runs its main on load), so proto_take
# lifts the named functions and constants out of the file in one awk pass and
# evaluates them; only the network and clock seams are replaced (proto_ready).
#
# The caller sets proto_lib to this file's directory before sourcing it. The
# production scripts are found from there, seven levels up, so a delivery
# copy must keep the same relative layout.
#
# bash, as the hooks are; nothing outside this file runs at load time.

# shellcheck disable=SC2154 # the sourcing entry point sets proto_lib
proto_scripts=$proto_lib/../../../../../../../scripts

# proto_take <script> <name>... — define each named function of <script>
# (from its `name() {` line to the next `}` at the left margin, or the one
# line of a `name() { …; }` definition) and each
# named `readonly NAME=` constant, failing closed (2) when the script is
# unreadable or any name is not found in it.
proto_take() {
  local file=$proto_scripts/$1 defs
  shift
  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    printf '%s\n' "proto: $file is missing or unreadable" >&2
    return 2
  fi
  defs=$(PROTO_NAMES="$*" awk '
    BEGIN { n = split(ENVIRON["PROTO_NAMES"], a, " "); for (i = 1; i <= n; i++) want[a[i]] = 1 }
    inside { print; if ($0 == "}") inside = 0; next }
    /^[A-Za-z_][A-Za-z0-9_]*\(\) \{( .*; \})?$/ {
      f = substr($0, 1, index($0, "(") - 1)
      if (f in want) { got[f] = 1; print; if ($0 !~ /; \}$/) inside = 1 }
      next
    }
    /^readonly [A-Za-z_][A-Za-z0-9_]*=/ {
      c = substr($0, 10, index($0, "=") - 10)
      if (c in want) { got[c] = 1; print }
    }
    END {
      for (k in want) if (!(k in got)) { print "proto: " k " not found" > "/dev/stderr"; bad = 1 }
      exit bad
    }
  ' "$file") || {
    printf '%s\n' "proto: could not take every name from $file" >&2
    return 2
  }
  eval "$defs" || return 2
}

# proto_esc <text> — sets PROTO_ESC to the text with backslash, newline and
# tab written as \\, \n and \t, so one token or substitution is one line.
proto_esc() {
  local v=$1
  v=${v//\\/\\\\}
  v=${v//$'\n'/\\n}
  v=${v//$'\t'/\\t}
  PROTO_ESC=$v
}

# proto_tokenize — the tokenizer contract. Reads the whole command from
# stdin, as the hook receives it, and on success prints one line per token,
# then one per command substitution, exit 0:
#   W <quoted> <noexp> <qpos> <dyn> <glob> <zopt> <qmix> <subs> <value>
#   O <operator>      R <redirect operator>      S <index> <text>
# tab-separated, <subs> the comma-joined substitution indexes or `-`, values
# escaped by proto_esc. A command the tokenizer refuses, one longer than the
# hook's length cap, or one holding a NUL byte prints nothing and exits 3,
# so no partial token stream is ever emitted. A usage error exits 2.
proto_tokenize() {
  if [ $# -ne 0 ]; then
    printf '%s\n' 'usage: tokenize <command-on-stdin>' >&2
    return 2
  fi
  proto_take worker-command-guard.sh tok_push dollar_expands dollar_form_ok \
    subst_scan tokenize MAX_CMD_LEN || return 2
  local s out='' i subs
  # A NUL ends the read with status 0; end of input without one returns 1.
  if IFS= read -r -d '' s; then
    return 3
  fi
  [ "${#s}" -le "$MAX_CMD_LEN" ] || return 3
  NL=$'\n'
  TAB=$'\t'
  HOOK_DEPTH=0
  TOK_N=0
  SUBST_N=0
  tokenize "$s" || return 3
  i=0
  while [ "$i" -lt "$TOK_N" ]; do
    proto_esc "${TOK_VAL[i]}"
    case ${TOK_TYPE[i]} in
      W)
        subs=${TOK_SUBS[i]# }
        subs=${subs// /,}
        out="$out${out:+$NL}W$TAB${TOK_QUOTED[i]}$TAB${TOK_NOEXP[i]}$TAB${TOK_QPOS[i]}$TAB${TOK_DYN[i]}$TAB${TOK_GLOB[i]}$TAB${TOK_ZOPT[i]}$TAB${TOK_QMIX[i]}$TAB${subs:--}$TAB$PROTO_ESC"
        ;;
      *) out="$out${out:+$NL}${TOK_TYPE[i]}$TAB$PROTO_ESC" ;;
    esac
    i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "$SUBST_N" ]; do
    proto_esc "${SUBST_TXT[i]}"
    out="$out${out:+$NL}S$TAB$i$TAB$PROTO_ESC"
    i=$((i + 1))
  done
  [ -z "$out" ] || printf '%s\n' "$out"
  return 0
}

# proto_ready <pr|-> <owner/repo|-> <refuse|conflict-only> — the ready-guard
# predicate contract: the decision ready-guard.sh reaches for a draft->ready
# flip of PR <pr> (or the current branch's, `-`) in <owner/repo> (or the
# working directory's, `-`) under ready_guard_behind_base <policy>. The
# GitHub answers are files in the working directory: `view` and, for the
# re-query after an UNKNOWN, `requery` (the `gh pr view --json` output),
# `compare` (the compare call's `.behind_by`), each absent meaning empty
# output, and `view.rc`, `requery.rc`, `compare.rc` holding the call's exit
# status (absent: 0). A deny prints the hook's decision object, exit 0; a
# flip that may proceed prints nothing, exit 0. A usage error exits 2.
#
# Replaced seams, every one an input the fixtures supply: gh reads those
# files, the timeout wrapper runs its command directly, the re-query does not
# sleep, and the policy is the argument rather than the resolved knob.
proto_ready() {
  if [ $# -ne 3 ]; then
    printf '%s\n' 'usage: ready <pr|-> <owner/repo|-> <refuse|conflict-only>' >&2
    return 2
  fi
  proto_take ready-guard.sh REASON_PREFIX emit_deny emit_deny_constant \
    valid_pr_number valid_owner valid_repo valid_owner_repo valid_ref_name \
    valid_oid valid_count lower gh_timeout gh_pr_view evaluate_predicate \
    read_view_fields check_view_rc json_field parse_owner_repo_from_url || return 2
  if [ ! -f "$proto_scripts/echo-safety.sh" ] || [ ! -r "$proto_scripts/echo-safety.sh" ]; then
    printf '%s\n' "proto: echo-safety.sh is missing or unreadable under $proto_scripts" >&2
    return 2
  fi
  # shellcheck source=/dev/null
  . "$proto_scripts/echo-safety.sh" || return 2
  RG_PR=$1
  RG_REPO=$2
  PROTO_POLICY=$3
  [ "$RG_PR" != - ] || RG_PR=''
  [ "$RG_REPO" != - ] || RG_REPO=''
  if { [ -n "$RG_PR" ] && ! valid_pr_number "$RG_PR"; } \
    || { [ -n "$RG_REPO" ] && ! valid_owner_repo "$RG_REPO"; }; then
    printf '%s\n' 'ready: the pr must be a pull-request number and the repo owner/repo, or -' >&2
    return 2
  fi
  case $PROTO_POLICY in
    refuse | conflict-only) ;;
    *)
      printf '%s\n' 'ready: the policy must be refuse or conflict-only' >&2
      return 2
      ;;
  esac
  RG_TIMEOUT_BIN=''
  RG_GH_T=''
  RG_URL_OWNER=''
  RG_URL_REPO=''
  GH_VIEW_OUT=''
  GH_VIEW_RC=0
  evaluate_predicate .
  return 0
}

# The replaced seams. Each is called by name from the production code.
# shellcheck disable=SC2329
timeout_bin() { printf 'proto_unbounded'; }
# shellcheck disable=SC2329
proto_unbounded() {
  shift
  "$@"
}
# shellcheck disable=SC2329
retry_delay() { printf '0'; }
# shellcheck disable=SC2329
behind_base_policy() { printf '%s' "$PROTO_POLICY"; }
# gh_pr_view runs gh in a subshell, so the stub cannot count its calls; the
# first answer has not been stored yet when the first call runs.
# shellcheck disable=SC2329
gh() {
  local f=view
  case $1 in
    api) f=compare ;;
    *) [ -z "$GH_VIEW_OUT" ] || f=requery ;;
  esac
  [ ! -f "$f" ] || printf '%s' "$(<"$f")"
  [ ! -f "$f.rc" ] || return "$(<"$f.rc")"
  return 0
}
