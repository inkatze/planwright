#!/usr/bin/env bash
# ready-guard.sh — deterministic, DENY-EMITTING PreToolUse hook that refuses a
# draft->ready pull-request transition unless the PR is provably current with
# its base branch and mergeable (merge-currency-guard Task 2; REQ-A1.1,
# REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.5, REQ-C1.6, REQ-C1.7, REQ-C1.8,
# REQ-C1.9, REQ-C1.10, REQ-K1.1, REQ-K1.3; D-2, D-3, D-5, D-7, D-8).
#
# THE MODALITY INVERSION (D-2, REQ-C1.2). The sibling guards
# (worker-command-guard.sh, tower-command-guard.sh) are ALLOW-ONLY: they emit
# `allow` or nothing, so a bug there is never worse than the status quo. This
# guard EMITS DENY. That inverts the risk model: a missed deny defeats the
# guard, and a FALSE deny blocks legitimate work. Both directions are failure
# modes, so the siblings' "allow-only, never worse than today" reasoning does
# NOT transfer here and is deliberately not borrowed. Every branch below is
# annotated with which way it fails and why that is the right way for it.
#
# JURISDICTION, THEN FAIL-CLOSED. The guard first decides whether the
# intercepted call is a gated draft->ready flip at all, and only then applies
# the fail-closed posture. This ordering is REQ-C1.3's own ("positively
# identify a gated ready-flip before issuing any network call, so a
# non-matching Bash command returns with zero network cost") and it is what
# keeps the false-deny surface bounded to actual flip attempts:
#
#   * OUTSIDE jurisdiction -> DEFER. A non-Bash, non-MCP tool; a Bash command
#     with no recognizable 'gh pr ready'; a '--undo'; an 'update_pull_request'
#     carrying no draft->ready transition. Nothing to confirm, so nothing to
#     refuse.
#   * INSIDE jurisdiction -> DENY on ANY doubt (REQ-C1.3, D-5). gh absent or
#     erroring, a query timing out, `mergeable` UNKNOWN after the bounded
#     re-query, the compare call failing, a malformed field, an invalid or
#     ambiguous selector, any internal error.
#
# The MCP surface establishes jurisdiction by TOOL NAME alone, so a malformed
# MCP payload denies (blast radius: one tool). The Bash surface cannot — its
# tool name is generic — so an unanalyzable Bash payload denies only when the
# raw bytes still evidence a ready-flip (see raw_evidences_ready_flip); with no
# such evidence it defers, because denying every unanalyzable Bash call would
# brick the session for a guard that had no business gating it.
#
# Security contract:
#   * No LLM and no model/API call in the decision path (REQ-C1.2, REQ-D1.4);
#     purely deterministic shell over two GitHub reads.
#   * The intercepted command / tool payload is strictly INERT DATA (REQ-C1.5):
#     never eval-ed, re-expanded, glob-expanded, or executed. Selectors are
#     grammar-validated and passed to gh as separate argv arguments, never
#     interpolated into a command string (REQ-C1.9).
#   * No local git state at all (D-5): no ref, no object, no `is-ancestor`, no
#     `git fetch`. Both signals are server-computed against the PR's real base,
#     so the decision is identical for every flipper and every base branch.
#   * Every remote call is wall-clock bounded (REQ-C1.3). No bounding binary on
#     PATH is itself a DENY: a hung PreToolUse hook that produces no output is a
#     silent fail-OPEN, which is the one outcome this guard may never have.
#   * Untrusted content echoed into a denial (branch names, selectors) is
#     stripped of non-printable bytes before emission (REQ-K1.3), and the
#     decision JSON is built by jq so no value can break out of its string.
#
# Predicate (D-3, REQ-C1.1). From ONE `gh pr view` of the target PR:
# `baseRefName`, `headRefOid`, `mergeable`, `isDraft`, `url`. From the compare
# endpoint `repos/<owner>/<repo>/compare/<baseRefName>...<headRefOid>`:
# `behind_by`. DEFER only when `behind_by == 0` AND `mergeable == MERGEABLE`.
# Currency is deliberately NOT keyed on `mergeStateStatus`, which reports
# `BEHIND` only under the base's "require up to date" branch protection — on an
# unprotected base (planwright's own `main`) a stale PR reads `CLEAN`, which is
# exactly the false-allow this bundle exists to prevent. This script therefore
# never requests `mergeStateStatus`; the suite pins that.
#
# Portable bash (3.2 floor / BSD tooling), matching the sibling guard family
# rather than the tree's POSIX-sh default: the Bash-surface tokenizer needs
# word arrays. jq is required to analyze a payload; its absence denies a
# payload that still evidences a flip and defers everything else.
set -u
unset CDPATH
# Pin the C locale so bracket expressions and character classes below mean
# exactly their ASCII range on every host (mirrors the sibling hooks).
LC_ALL=C
export LC_ALL

# Bounds (bounded runtime). MAX_PAYLOAD_BYTES caps the stdin read;
# MAX_CMD_LEN caps the tokenizer's O(n^2) substring scan at a fraction of a
# second. A command past the cap is not silently ignored: it falls to the
# raw-evidence screen, so an over-long ready-flip still denies.
readonly MAX_PAYLOAD_BYTES=2000000
readonly MAX_CMD_LEN=8192
readonly MCP_TOOL='mcp__github__update_pull_request'
readonly REASON_PREFIX='planwright ready-guard: '

# --------------------------------------------------------------------------
# Echo safety (REQ-K1.3). A byte-identical inline fallback is defined FIRST so
# the guard is never unable to sanitize, then the canonical
# scripts/echo-safety.sh overrides it when the sibling resolves. A security
# script that cannot strip control bytes must not silently emit raw ones.
sanitize_printable() {
  _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237' 2>/dev/null) || _sp=''
  if [ -z "$_sp" ] && [ $# -ge 2 ]; then
    _sp=$2
  fi
  printf '%s' "$_sp"
}
GUARD_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || GUARD_DIR=''
if [ -n "$GUARD_DIR" ] && [ -r "$GUARD_DIR/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$GUARD_DIR/echo-safety.sh"
fi

# --------------------------------------------------------------------------
# Emitters. Exactly one decision object is ever written, as the final action,
# so there is never a partially-written decision. Every exit is 0: the hook
# signals DENY through the decision object, never through a status code.

# emit_deny <reason> — the deny decision. jq builds the JSON so an untrusted
# fragment already folded into <reason> cannot break out of the string, and
# sanitize_printable has stripped its control bytes at the interpolation site.
emit_deny() {
  local reason
  reason="$REASON_PREFIX$(sanitize_printable "$1" 'refusing an unconfirmable draft->ready flip')"
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# emit_deny_nojq — the one deny that cannot use jq (jq is what is missing). The
# reason is a compile-time constant with no untrusted content, so hand-rolling
# the JSON here is safe in a way a general emitter would not be.
emit_deny_nojq() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"planwright ready-guard: jq is not on PATH, so this draft->ready flip could not be checked for base-branch currency and mergeability - refusing (fail closed). Install jq, or flip the PR ready outside a Claude Code session if you have verified it yourself."}}'
  exit 0
}

# --------------------------------------------------------------------------
# Grammars (REQ-C1.9). Each validates an identifier BEFORE it reaches any
# command line or URL. Failure is always a DENY at the call site, never a
# best-effort coercion.

# A PR number is digits, no leading zero run, bounded. Rejects `-R`, `--flag`,
# `$(...)`, and every other shape that could redirect or inject.
valid_pr_number() {
  case ${1:-} in
    "" | *[!0-9]* | 0*) return 1 ;;
  esac
  [ "${#1}" -le 12 ]
}

# GitHub's owner charset: alphanumerics and hyphens, no leading/trailing
# hyphen, <=39 chars.
valid_owner() {
  case ${1:-} in
    "" | *[!A-Za-z0-9-]* | -* | *-) return 1 ;;
  esac
  [ "${#1}" -le 39 ]
}

# GitHub's repo charset: alphanumerics, dot, underscore, hyphen; not `.` or
# `..`; <=100 chars.
valid_repo() {
  case ${1:-} in
    "" | *[!A-Za-z0-9._-]* | . | ..) return 1 ;;
  esac
  [ "${#1}" -le 100 ]
}

# `<owner>/<repo>`, split on the single slash.
valid_owner_repo() {
  local v=${1:-} o r
  case $v in
    */*/* | */ | /*) return 1 ;;
    */*) ;;
    *) return 1 ;;
  esac
  o=${v%%/*}
  r=${v#*/}
  valid_owner "$o" && valid_repo "$r"
}

# A branch name headed for a compare URL path. Git already forbids space, `?`,
# `*`, `[`, `~`, `^`, `:`, `\` and control bytes in a ref; this narrows further
# to a charset that is unambiguous in a URL path segment. Anything else denies
# rather than being percent-encoded on a guess.
valid_ref_name() {
  case ${1:-} in
    "" | *[!A-Za-z0-9._/-]* | -* | */ | /* | *..*) return 1 ;;
  esac
  [ "${#1}" -le 255 ]
}

# A commit OID as GitHub reports it: lowercase hex, sha-1 (40) or sha-256 (64).
valid_oid() {
  case ${1:-} in
    *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#1}" = 40 ] || [ "${#1}" = 64 ]
}

# A non-negative integer as the compare endpoint reports behind_by.
valid_count() {
  case ${1:-} in
    "" | *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 12 ]
}

# An absolute, control-free, backslash-free directory path (the `cd <path> &&`
# prefix target and the payload cwd). Shape mirrors fleet-liveness.sh's
# valid_oracle_cwd, this tree's sibling path grammar.
valid_dir_path() {
  local v=${1:-}
  case $v in
    /*) ;;
    *) return 1 ;;
  esac
  case $v in
    *[![:print:]]* | *\\*) return 1 ;;
  esac
  [ "${#v}" -le 512 ] && [ -d "$v" ]
}

# ASCII-lowercase, for the case-insensitive owner/repo cross-check GitHub's own
# case-insensitivity requires.
lower() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'; }

# --------------------------------------------------------------------------
# Wall-clock bounds (REQ-C1.3, D-5).

# gh_timeout — the per-call bound in seconds.
# PLANWRIGHT_READY_GUARD_GH_TIMEOUT overrides the default 10; a malformed,
# zero, or absurdly long value falls back to it (a zero bound would kill every
# query and deny every flip). Validation shape is deliberately byte-for-byte
# fleet-liveness.sh's oracle_timeout and fleet-cleanup.sh's gh_timeout, this
# tree's sibling wall-clock bounds, so all three behave identically on
# malformed input. The default is 10 rather than fleet-cleanup's 20 because
# this bound sits in the interactive tool-call path, where the worst case is
# three calls (view, UNKNOWN re-query, compare).
gh_timeout() {
  gt_v="${PLANWRIGHT_READY_GUARD_GH_TIMEOUT:-10}"
  case $gt_v in
    "" | *[!0-9]* | 0 | 0?*) gt_v=10 ;;
  esac
  [ "${#gt_v}" -le 4 ] || gt_v=10
  printf '%s' "$gt_v"
}

# retry_delay — the pause before the single UNKNOWN re-query (REQ-C1.3).
# GitHub recomputes mergeability asynchronously; an immediate re-query would
# almost always read the same UNKNOWN. Same validation shape as gh_timeout,
# except 0 IS accepted: a zero delay is meaningful (re-query at once) and,
# unlike a zero timeout, harmless.
retry_delay() {
  rd_v="${PLANWRIGHT_READY_GUARD_RETRY_DELAY:-2}"
  case $rd_v in
    "" | *[!0-9]*) rd_v=2 ;;
  esac
  [ "${#rd_v}" -le 2 ] || rd_v=2
  printf '%s' "$rd_v"
}

# timeout_bin — the bounding binary, or empty when none is on PATH. 'timeout'
# is coreutils and is NOT stock macOS, so gtimeout (the Homebrew coreutils
# name) is probed as well; this widens fleet-cleanup.sh's 'timeout'-only probe
# because a guard that denied every flip on a stock macOS box would be a
# false-deny surface far larger than the convention is worth. Neither present
# still fails closed at the call site.
timeout_bin() {
  if command -v timeout >/dev/null 2>&1; then
    printf 'timeout'
  elif command -v gtimeout >/dev/null 2>&1; then
    printf 'gtimeout'
  fi
}

# --------------------------------------------------------------------------
# Raw-evidence screen. The ONLY thing that establishes Bash-surface
# jurisdiction when the payload cannot be parsed structurally (jq absent, or
# stdin that is not JSON). Deliberately crude and deliberately over-inclusive
# in the DENY direction: it governs only paths where the precise analysis is
# unavailable, and there the fail-closed posture outranks precision. Uses the
# bash `[[ =~ ]]` builtin, not grep, because the jq-absent host may be missing
# other binaries too.
raw_evidences_ready_flip() {
  local raw=${1:-} re
  case $raw in
    *"$MCP_TOOL"*) return 0 ;;
  esac
  re='gh[^A-Za-z0-9]+pr[^A-Za-z0-9]+ready'
  [[ $raw =~ $re ]]
}

# --------------------------------------------------------------------------
# Bash-surface tokenizer. Splits the fully-expanded command (Claude Code
# expands variables before the hook sees it) into segments on the unquoted
# control operators `;` `&&` `||` `|` `&` and newlines, and each segment into
# words, honoring single quotes, double quotes, and backslash escapes. It never
# executes, evals, or expands anything it scans (REQ-C1.5).
#
# It returns non-zero the instant it meets a construct it will not analyze:
# command/process substitution, backticks, or ANSI-C `$'...'`. Callers treat an
# unanalyzable command as jurisdiction-by-raw-evidence, so `$(gh pr ready 5)`
# denies rather than slipping through — the opposite of what an allow-only
# guard would do with the same input.
#
# Redirect operators and their target word are skipped rather than refused:
# `gh pr ready 5 >/dev/null` is a legitimate conforming flip and must not eat a
# false deny.
#
# Results land in the caller's SEGS array (one NUL-free, newline-joined word
# list per segment) via dynamic scope.
tokenize_segments() {
  local s=$1
  local n=${#s}
  local i=0
  local c nc cur='' have=0
  local -a words=()
  SEGS=()

  flush_word() {
    if [ "$have" = 1 ]; then
      words[${#words[@]}]=$cur
      cur=''
      have=0
    fi
  }
  flush_seg() {
    flush_word
    if [ "${#words[@]}" -gt 0 ]; then
      local joined='' w
      for w in "${words[@]}"; do
        joined="$joined$w$NL"
      done
      SEGS[${#SEGS[@]}]=$joined
    fi
    words=()
  }

  while [ "$i" -lt "$n" ]; do
    c=${s:i:1}
    case $c in
      "'")
        # Single quotes: everything to the next `'` is literal.
        local j=$((i + 1)) lit=''
        while [ "$j" -lt "$n" ] && [ "${s:j:1}" != "'" ]; do
          lit="$lit${s:j:1}"
          j=$((j + 1))
        done
        [ "$j" -lt "$n" ] || return 1 # unbalanced quote
        cur="$cur$lit"
        have=1
        i=$((j + 1))
        ;;
      '"')
        # Double quotes: `\` escapes only `"`, `\`, `$` and backtick; a `$(` or
        # backtick inside still refuses.
        local j=$((i + 1)) lit='' ch
        while [ "$j" -lt "$n" ]; do
          ch=${s:j:1}
          if [ "$ch" = '"' ]; then break; fi
          if [ "$ch" = "\\" ]; then
            local esc=${s:j+1:1}
            case $esc in
              '"' | "\\" | '$' | '`')
                lit="$lit$esc"
                j=$((j + 2))
                continue
                ;;
            esac
            lit="$lit\\"
            j=$((j + 1))
            continue
          fi
          if [ "$ch" = '`' ]; then return 1; fi
          if [ "$ch" = '$' ] && [ "${s:j+1:1}" = '(' ]; then return 1; fi
          lit="$lit$ch"
          j=$((j + 1))
        done
        [ "$j" -lt "$n" ] || return 1 # unbalanced quote
        cur="$cur$lit"
        have=1
        i=$((j + 1))
        ;;
      "\\")
        nc=${s:i+1:1}
        [ -n "$nc" ] || return 1 # trailing backslash / line continuation
        cur="$cur$nc"
        have=1
        i=$((i + 2))
        ;;
      '`')
        return 1
        ;;
      '$')
        nc=${s:i+1:1}
        case $nc in
          '(' | "'") return 1 ;; # command substitution / ANSI-C quoting
        esac
        cur="$cur$c"
        have=1
        i=$((i + 1))
        ;;
      '<' | '>')
        # Process substitution refuses; a plain redirect skips the operator and
        # its target word.
        nc=${s:i+1:1}
        [ "$nc" != '(' ] || return 1
        flush_word
        i=$((i + 1))
        [ "${s:i:1}" != '>' ] || i=$((i + 1)) # `>>`
        [ "${s:i:1}" != '&' ] || i=$((i + 1)) # `>&`
        while [ "$i" -lt "$n" ] && [ "${s:i:1}" = ' ' ]; do i=$((i + 1)); done
        while [ "$i" -lt "$n" ]; do
          case ${s:i:1} in
            ' ' | "$TAB" | "$NL" | ';' | '&' | '|') break ;;
          esac
          i=$((i + 1))
        done
        ;;
      ';' | '&' | '|')
        nc=${s:i+1:1}
        flush_seg
        i=$((i + 1))
        if { [ "$c" = '&' ] || [ "$c" = '|' ]; } && [ "$nc" = "$c" ]; then
          i=$((i + 1))
        fi
        ;;
      ' ' | "$TAB" | "$NL")
        flush_word
        i=$((i + 1))
        ;;
      '(' | ')' | '{' | '}')
        # Subshell / brace grouping: not analyzed.
        return 1
        ;;
      *)
        cur="$cur$c"
        have=1
        i=$((i + 1))
        ;;
    esac
  done
  flush_seg
  return 0
}

# --------------------------------------------------------------------------
# main

main() {
  local input read_ok=1 tool

  input=$(head -c "$MAX_PAYLOAD_BYTES" 2>/dev/null) || read_ok=0

  # The stdin read itself failing (no `head` on PATH, a closed descriptor) is
  # NOT the same as an empty payload: it carries no evidence about what the
  # intercepted call was, and denying on it would refuse every tool call in the
  # session on a missing coreutil. Defer.
  [ "$read_ok" = 1 ] || return 0

  if ! command -v jq >/dev/null 2>&1; then
    # jq absent (REQ-C1.3). Deny only what still evidences a flip; a payload
    # with no such evidence was never this guard's to gate.
    raw_evidences_ready_flip "$input" && emit_deny_nojq
    return 0
  fi

  # An empty payload is a PreToolUse contract violation. REQ-C1.3 lists it
  # among the fail-closed causes, so it denies rather than silently standing
  # down a safety guard. The read-failure case above is what keeps a missing
  # coreutil from landing here.
  if [ -z "$input" ]; then
    emit_deny 'the PreToolUse payload was empty, so this call could not be checked for a non-current draft->ready flip - refusing (fail closed). This is a hook-contract violation; report it rather than working around it.'
  fi

  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || tool=''
  if [ -z "$tool" ]; then
    # Unparseable as JSON, or no tool_name. Same jurisdiction rule as the
    # jq-absent path: raw evidence decides.
    raw_evidences_ready_flip "$input" \
      && emit_deny 'the PreToolUse payload could not be parsed, and its raw content looks like a draft->ready flip - refusing (fail closed). Retry, or flip the PR ready outside a Claude Code session if you have verified its currency yourself.'
    return 0
  fi

  case $tool in
    Bash) handle_bash "$input" ;;
    "$MCP_TOOL") handle_mcp "$input" ;;
    *) return 0 ;; # every other tool defers: outside jurisdiction
  esac
  return 0
}

# --------------------------------------------------------------------------
# Bash surface (REQ-C1.6, REQ-C1.8, REQ-C1.9, REQ-C1.10).

handle_bash() {
  local input=$1 cmd cwd_type cwd
  local -a SEGS=()

  # `command` gets strict type discipline. A present non-string is a payload
  # that does not match the documented contract; raw evidence then decides.
  cmd=$(printf '%s' "$input" \
    | jq -r 'if (.tool_input.command | type) == "string" then .tool_input.command else empty end' \
      2>/dev/null) || cmd=''
  if [ -z "$cmd" ]; then
    raw_evidences_ready_flip "$input" \
      && emit_deny 'this Bash payload carries no readable command string, and its raw content looks like a draft->ready flip - refusing (fail closed).'
    return 0
  fi

  if [ "${#cmd}" -gt "$MAX_CMD_LEN" ]; then
    raw_evidences_ready_flip "$cmd" \
      && emit_deny 'this Bash command is too long to analyze and its text contains a ready-flip shape - refusing (fail closed). Issue the flip as its own short command.'
    return 0
  fi

  # cwd: same type discipline as the sibling guards. Absent/null falls back to
  # $PWD; a present non-string defers the payload as unanalyzable.
  cwd_type=$(printf '%s' "$input" \
    | jq -r 'if has("cwd") and .cwd != null then (.cwd | type) else "absent" end' 2>/dev/null) \
    || cwd_type='absent'
  case $cwd_type in
    absent) cwd=$PWD ;;
    string)
      cwd=$(printf '%s' "$input" | jq -r '.cwd' 2>/dev/null) || cwd=''
      [ -n "$cwd" ] || cwd=$PWD
      ;;
    *)
      raw_evidences_ready_flip "$input" \
        && emit_deny 'this Bash payload carries a malformed cwd, and its content looks like a draft->ready flip - refusing (fail closed).'
      return 0
      ;;
  esac

  if ! tokenize_segments "$cmd"; then
    # A construct the tokenizer will not analyze (command/process
    # substitution, backticks, grouping). An allow-only guard defers here; this
    # one denies when the text still evidences a flip, because `$(gh pr ready
    # 5)` must not be a bypass.
    raw_evidences_ready_flip "$cmd" \
      && emit_deny 'this Bash command uses a construct the guard will not analyze (command substitution, backticks, or grouping) and its text contains a ready-flip shape - refusing (fail closed). Issue gh pr ready <number> directly.'
    return 0
  fi

  analyze_segments "$cwd"
}

# analyze_segments <payload-cwd> — walk the tokenized segments, find the gated
# gh pr ready candidate, resolve its selector, and dispatch the predicate.
analyze_segments() {
  local payload_cwd=$1
  local seg w
  local cand_idx=-1 cand_count=0 idx=0
  local -a cand_words=()
  local cd_path='' cd_count=0

  for seg in "${SEGS[@]}"; do
    local -a words=()
    while IFS= read -r w; do
      words[${#words[@]}]=$w
    done <<EOF
$seg
EOF
    # The heredoc round-trip appends one trailing empty element; drop it.
    if [ "${#words[@]}" -gt 0 ] \
      && [ -z "${words[$((${#words[@]} - 1))]}" ]; then
      unset "words[$((${#words[@]} - 1))]"
    fi
    [ "${#words[@]}" -gt 0 ] || {
      idx=$((idx + 1))
      continue
    }

    if [ "${words[0]}" = cd ] && [ "${#words[@]}" = 2 ]; then
      cd_path=${words[1]}
      cd_count=$((cd_count + 1))
    fi

    if [ "${words[0]}" = gh ] && [ "${#words[@]}" -ge 3 ] \
      && [ "${words[1]}" = pr ] && [ "${words[2]}" = ready ]; then
      cand_count=$((cand_count + 1))
      cand_idx=$idx
      cand_words=("${words[@]}")
    fi
    idx=$((idx + 1))
  done

  # No gh pr ready anywhere: outside jurisdiction, zero network cost.
  [ "$cand_count" -gt 0 ] || return 0

  # Two flips in one command line: which one is being gated is ambiguous, and
  # a guard that picked one would let the other through. Deny.
  [ "$cand_count" = 1 ] \
    || emit_deny 'this command issues more than one gh pr ready - refusing (fail closed), because the guard cannot attribute a currency check to each. Issue them as separate commands.'

  parse_ready_flags "${cand_words[@]}" || return 0 # '--undo': never gated

  # Resolve the cwd the gh query must run from. It matters whenever the
  # selector is not fully self-describing: a bare command needs the branch's
  # PR, and any command without --repo needs the repo.
  local query_cwd=$payload_cwd
  if [ "${#SEGS[@]}" -gt 1 ]; then
    # A multi-segment command may have changed directory before the flip, so
    # the payload cwd is no longer the flip's cwd. The one supported form is
    # REQ-C1.10's `cd <path> && gh pr ready ...`: exactly two segments, the cd
    # first, an absolute existing path used as inert argv to `cd --`.
    if [ "$cd_count" = 1 ] && [ "${#SEGS[@]}" = 2 ] && [ "$cand_idx" = 1 ] \
      && valid_dir_path "$cd_path"; then
      query_cwd=$cd_path
    elif [ -n "$RG_REPO" ] && [ -n "$RG_PR" ]; then
      # Fully self-describing selector: cwd is irrelevant.
      query_cwd=$payload_cwd
    else
      emit_deny "this gh pr ready runs after other commands that may change directory, and its selector does not name both the repo and the PR number - refusing (fail closed), because the guard cannot tell which PR would be flipped. Re-issue it as gh pr ready <number> --repo <owner>/<repo>, or on its own."
    fi
  fi

  if [ -z "$RG_PR" ] && ! valid_dir_path "$query_cwd"; then
    emit_deny 'this bare gh pr ready has no PR number and no usable working directory to resolve the current branch'"'"'s PR from - refusing (fail closed). Re-issue it as gh pr ready <number>.'
  fi

  evaluate_predicate "$query_cwd"
}

# parse_ready_flags <words...> — validate the candidate segment's arguments
# against 'gh pr ready''s actual grammar. Sets RG_PR and RG_REPO. Returns
# non-zero (defer) for --undo. Every unrecognized flag DENIES: 'gh pr ready'
# takes only --undo and the global `-R/--repo`, so an unknown flag either
# redirects the target or is not the command the guard thinks it is.
parse_ready_flags() {
  shift 3 # gh `pr` `ready`
  RG_PR=''
  RG_REPO=''
  local a val positional=0 endopts=0

  # --undo anywhere means this is a ready->draft transition, never gated
  # (REQ-C1.8), regardless of currency or mergeability.
  for a in "$@"; do
    [ "$a" != --undo ] || return 1
  done

  while [ "$#" -gt 0 ]; do
    a=$1
    shift
    if [ "$endopts" = 0 ]; then
      case $a in
        --)
          endopts=1
          continue
          ;;
        -R | --repo)
          [ "$#" -gt 0 ] \
            || emit_deny 'this gh pr ready passes --repo with no value - refusing (fail closed).'
          val=$1
          shift
          set_repo "$val"
          continue
          ;;
        --repo=*)
          set_repo "${a#--repo=}"
          continue
          ;;
        -R?*)
          set_repo "${a#-R}"
          continue
          ;;
        -*)
          emit_deny "this gh pr ready carries an option the guard does not recognize ($(sanitize_printable "$a" 'an unprintable option')) - refusing (fail closed), because an unrecognized option could redirect the flip to another PR. gh pr ready accepts only \`--undo\` and \`--repo\`."
          ;;
      esac
    fi
    positional=$((positional + 1))
    [ "$positional" = 1 ] \
      || emit_deny 'this gh pr ready names more than one target - refusing (fail closed), because the PR it would flip is ambiguous.'
    valid_pr_number "$a" \
      || emit_deny "this gh pr ready target is not a plain PR number ($(sanitize_printable "$a" 'an unprintable selector')) - refusing (fail closed). The guard resolves a PR only by number or by the current branch; re-issue it as \`gh pr ready <number>\`."
    RG_PR=$a
  done
  return 0
}

set_repo() {
  valid_owner_repo "${1:-}" \
    || emit_deny "this gh pr ready names a repo that is not a valid <owner>/<repo> ($(sanitize_printable "${1:-}" 'an unprintable repo selector')) - refusing (fail closed)."
  RG_REPO=$1
}

# --------------------------------------------------------------------------
# MCP surface (REQ-C1.6, REQ-C1.8, REQ-C1.9). Jurisdiction is the tool name, so
# ANY malformed payload here denies: the blast radius is this one tool, and it
# is the ready-flip surface itself.

handle_mcp() {
  local input=$1 shape owner repo num
  shape=$(printf '%s' "$input" | jq -r '
    if (.tool_input | type) != "object" then "malformed"
    elif (.tool_input | has("draft") | not) then "no-draft"
    elif (.tool_input.draft | type) != "boolean" then "malformed"
    elif .tool_input.draft then "to-draft"
    else "to-ready" end' 2>/dev/null) || shape='malformed'

  case $shape in
    no-draft | to-draft)
      # Not a draft->ready transition: a title/body/base edit, or a re-draft.
      # Never gated (REQ-C1.8), symmetric with the Bash --undo case.
      return 0
      ;;
    to-ready) ;;
    *)
      emit_deny 'this update_pull_request payload is malformed, so the guard cannot tell whether it flips a PR from draft to ready - refusing (fail closed).'
      ;;
  esac

  owner=$(printf '%s' "$input" \
    | jq -r 'if (.tool_input.owner | type) == "string" then .tool_input.owner else empty end' 2>/dev/null) \
    || owner=''
  repo=$(printf '%s' "$input" \
    | jq -r 'if (.tool_input.repo | type) == "string" then .tool_input.repo else empty end' 2>/dev/null) \
    || repo=''
  # `pullNumber` is a JSON number in the tool schema. Require an integral,
  # non-negative one and render it without an exponent or fraction, so a
  # value like 1e3 or 42.5 cannot become a different PR.
  num=$(printf '%s' "$input" | jq -r '
    (.tool_input.pullNumber) as $n
    | if ($n | type) == "number" and ($n | floor) == $n and $n > 0
      then ($n | floor | tostring) else empty end' 2>/dev/null) || num=''

  valid_owner "$owner" \
    || emit_deny 'this update_pull_request draft->ready call names no valid repository owner - refusing (fail closed).'
  valid_repo "$repo" \
    || emit_deny 'this update_pull_request draft->ready call names no valid repository - refusing (fail closed).'
  valid_pr_number "$num" \
    || emit_deny 'this update_pull_request draft->ready call names no valid pull-request number - refusing (fail closed).'

  RG_PR=$num
  RG_REPO="$owner/$repo"
  # The MCP selector is fully self-describing, so the query needs no cwd; run
  # it from a directory that is guaranteed to exist and carries no repo of its
  # own influence over '--repo'-qualified gh calls.
  evaluate_predicate '/'
}

# --------------------------------------------------------------------------
# The predicate (D-3, REQ-C1.1, REQ-C1.3). Reads RG_PR (may be empty: resolve
# the cwd branch's PR) and RG_REPO (may be empty: resolve from cwd).

# gh_pr_view <cwd> — one `gh pr view` for every field the predicate needs.
# Selectors reach gh as separate argv arguments (REQ-C1.9); the command is
# never assembled as a string. Sets GH_VIEW_OUT / GH_VIEW_RC.
gh_pr_view() {
  local cwd=$1
  local -a argv=(pr view)
  [ -z "$RG_PR" ] || argv[${#argv[@]}]=$RG_PR
  if [ -n "$RG_REPO" ]; then
    argv[${#argv[@]}]='--repo'
    argv[${#argv[@]}]=$RG_REPO
  fi
  argv[${#argv[@]}]='--json'
  # Deliberately NOT mergeStateStatus: it reports BEHIND only under the base's
  # "require up to date" protection, so keying currency on it false-allows a
  # stale PR on an unprotected base (D-3). The suite pins this argv.
  argv[${#argv[@]}]='baseRefName,headRefOid,isDraft,mergeable,url'
  GH_VIEW_OUT=$(cd -- "$cwd" 2>/dev/null && "$RG_TIMEOUT_BIN" "$RG_GH_T" gh "${argv[@]}" 2>/dev/null)
  GH_VIEW_RC=$?
}

evaluate_predicate() {
  local cwd=$1

  command -v gh >/dev/null 2>&1 \
    || emit_deny 'the gh CLI is not on PATH, so this draft->ready flip could not be checked for base-branch currency and mergeability - refusing (fail closed). Install and authenticate gh, or verify the PR yourself outside a Claude Code session.'

  RG_TIMEOUT_BIN=$(timeout_bin)
  # No bounding binary means an unbounded network call inside a PreToolUse
  # hook, which can hang the tool call and produce no output at all - a silent
  # fail-OPEN, the single outcome this guard may never have. Refuse instead.
  [ -n "$RG_TIMEOUT_BIN" ] \
    || emit_deny 'no timeout (or gtimeout) binary is on PATH, so the guard cannot bound its GitHub queries and will not make an unbounded call from a PreToolUse hook - refusing (fail closed). Install coreutils.'
  RG_GH_T=$(gh_timeout)

  local base head_oid mergeable is_draft url

  gh_pr_view "$cwd"
  check_view_rc
  read_view_fields || return 0 # already ready: not a transition, never gated

  if [ "$mergeable" = UNKNOWN ]; then
    # GitHub recomputes mergeability asynchronously whenever the head or base
    # moves, so UNKNOWN is the EXPECTED reading right after a convergence push.
    # Re-query once (REQ-C1.3) before denying, and name wait-and-retry as the
    # remedy - never a fetch, which cannot advance a server-side computation.
    sleep "$(retry_delay)" 2>/dev/null || :
    gh_pr_view "$cwd"
    check_view_rc
    read_view_fields || return 0
    [ "$mergeable" != UNKNOWN ] \
      || emit_deny "GitHub has not finished computing mergeability for this pull request (mergeable is still UNKNOWN after a re-query), so its currency and conflict state could not be confirmed - refusing (fail closed). Wait a few seconds and retry; do not fetch, GitHub computes this server-side."
  fi

  case $mergeable in
    MERGEABLE) ;;
    CONFLICTING)
      emit_deny "this pull request conflicts with its base branch $(sanitize_printable "$base" 'its base') (mergeable is CONFLICTING) - refusing the draft->ready flip (a ready PR must be mergeable). Merge the base into the branch, resolve the conflict, re-verify, then retry."
      ;;
    *)
      emit_deny "this pull request's mergeability could not be confirmed (mergeable was $(sanitize_printable "$mergeable" 'unreadable'), not MERGEABLE) - refusing (fail closed)."
      ;;
  esac

  valid_ref_name "$base" \
    || emit_deny "this pull request's base branch name is not a shape the guard will put in a compare query ($(sanitize_printable "$base" 'unprintable')) - refusing (fail closed)."
  valid_oid "$head_oid" \
    || emit_deny 'this pull request'"'"'s head commit id could not be read as a plain hex object id - refusing (fail closed).'

  local owner repo
  parse_owner_repo_from_url "$url" # sets RG_URL_OWNER / RG_URL_REPO
  owner=$RG_URL_OWNER
  repo=$RG_URL_REPO

  # Cross-check the server's own answer against the selector the intercepted
  # call named (REQ-C1.9): if gh answered about a different repo than the
  # caller asked for, the target is not what the guard believes and it must not
  # certify it.
  if [ -n "$RG_REPO" ] \
    && [ "$(lower "$owner/$repo")" != "$(lower "$RG_REPO")" ]; then
    emit_deny 'the pull request gh resolved does not belong to the repository this call named - refusing (fail closed).'
  fi

  local behind rc=0
  behind=$("$RG_TIMEOUT_BIN" "$RG_GH_T" gh api \
    "repos/$owner/$repo/compare/$base...$head_oid?per_page=1" \
    --jq '.behind_by' 2>/dev/null) || rc=$?
  if [ "$rc" = 124 ]; then
    emit_deny "the GitHub compare query did not finish within ${RG_GH_T}s, so this pull request's currency with its base branch could not be confirmed - refusing (fail closed). Wait and retry."
  fi
  [ "$rc" = 0 ] \
    || emit_deny "GitHub's compare endpoint could not be reached for this pull request, so its currency with base branch $(sanitize_printable "$base" 'its base') could not be confirmed - refusing (fail closed). Wait and retry."
  valid_count "$behind" \
    || emit_deny "GitHub's compare endpoint returned no readable \`behind_by\` for this pull request, so its currency with its base branch could not be confirmed - refusing (fail closed). Wait and retry."

  if [ "$behind" != 0 ]; then
    emit_deny "this pull request is $behind commit(s) behind its base branch $(sanitize_printable "$base" 'its base'), so it has NOT been verified on a current head - refusing the draft->ready flip. Merge the base branch into it ('git fetch origin && git merge FETCH_HEAD'), let CI and review re-run, then retry."
  fi

  # behind_by == 0 AND mergeable == MERGEABLE: the only conforming outcome.
  # Emit nothing and let the flip proceed.
  return 0
}

# read_view_fields — pull the predicate's fields out of the query answer into
# the caller's locals (dynamic scope) and enforce the answer's shape.
#
# `isDraft` is read and discriminated FIRST, and it is the only field whose
# absence is not immediately fatal to the shape check, because REQ-C1.8 says an
# already-ready PR is never gated "regardless of currency/mergeability state":
# resolving that no-op must not depend on the rest of the answer being
# well-formed. But an isDraft that is neither `true` nor `false` means the
# answer itself is unreadable, and that DENIES rather than falling through to
# the defer arm — a malformed answer that read as "not a draft" would be a
# silent fail-OPEN, and was exactly the bug this function was extracted to fix.
#
# Returns 1 (defer, not a transition) when the PR is already ready.
read_view_fields() {
  is_draft=$(json_field "$GH_VIEW_OUT" isDraft)
  case $is_draft in
    true) ;;
    false) return 1 ;;
    *) emit_deny 'the GitHub query for this pull request returned an answer the guard could not read (its draft state is missing or malformed), so a draft->ready flip could not be ruled out - refusing (fail closed).' ;;
  esac
  base=$(json_field "$GH_VIEW_OUT" baseRefName)
  head_oid=$(json_field "$GH_VIEW_OUT" headRefOid)
  mergeable=$(json_field "$GH_VIEW_OUT" mergeable)
  url=$(json_field "$GH_VIEW_OUT" url)
  { [ -n "$base" ] && [ -n "$head_oid" ] && [ -n "$mergeable" ] && [ -n "$url" ]; } \
    || emit_deny 'the GitHub query for this pull request returned an incomplete answer, so its currency with its base branch and its mergeability could not be confirmed - refusing (fail closed).'
  return 0
}

# check_view_rc — map the query's exit status onto a denial, distinguishing a
# timeout from an error so the operator sees a stall as a stall (REQ-K1.1).
check_view_rc() {
  if [ "$GH_VIEW_RC" = 124 ]; then
    emit_deny "the GitHub query for this pull request did not finish within ${RG_GH_T}s, so its currency and mergeability could not be confirmed - refusing (fail closed). Wait and retry."
  fi
  [ "$GH_VIEW_RC" = 0 ] \
    || emit_deny 'the GitHub query for this pull request failed, so its currency with its base branch and its mergeability could not be confirmed - refusing (fail closed). Check that gh is authenticated and that the pull request exists, then retry.'
  [ -n "$GH_VIEW_OUT" ] \
    || emit_deny 'the GitHub query for this pull request returned nothing, so its currency and mergeability could not be confirmed - refusing (fail closed).'
}

# json_field <json> <key> — read one scalar. The response is DATA: read with
# jq, never eval-ed, and every value is re-validated by its grammar above
# before it reaches a command line or a URL (REQ-C1.5).
json_field() {
  printf '%s' "$1" | jq -r --arg k "$2" '
    if type == "object" and (.[$k] != null) and ((.[$k] | type) != "object") and ((.[$k] | type) != "array")
    then (.[$k] | tostring) else empty end' 2>/dev/null || printf ''
}

# parse_owner_repo_from_url <url> — the authoritative owner/repo for the
# compare call, taken from the server's own answer rather than re-derived from
# the caller's cwd, so it is correct for a bare command and for a
# '--repo'-qualified one alike. `gh pr view --json` exposes no baseRepository
# field; `url` is the base repository's PR URL.
parse_owner_repo_from_url() {
  local u=${1:-} tail_n rest
  case $u in
    *"/pull/"*) ;;
    *) emit_deny 'the pull-request URL GitHub returned could not be read, so the guard cannot identify the repository to compare against - refusing (fail closed).' ;;
  esac
  tail_n=${u##*/pull/}
  valid_pr_number "$tail_n" \
    || emit_deny 'the pull-request URL GitHub returned does not end in a pull-request number - refusing (fail closed).'
  rest=${u%/pull/*}
  RG_URL_REPO=${rest##*/}
  rest=${rest%/*}
  RG_URL_OWNER=${rest##*/}
  valid_owner "$RG_URL_OWNER" \
    || emit_deny 'the pull-request URL GitHub returned names no readable repository owner - refusing (fail closed).'
  valid_repo "$RG_URL_REPO" \
    || emit_deny 'the pull-request URL GitHub returned names no readable repository - refusing (fail closed).'
}

# Newline / tab constants used by the tokenizer (kept out of the case patterns
# themselves, which cannot carry a literal newline portably).
NL=$'\n'
TAB=$'\t'

RG_PR=''
RG_REPO=''
RG_TIMEOUT_BIN=''
RG_GH_T=''
RG_URL_OWNER=''
RG_URL_REPO=''
GH_VIEW_OUT=''
GH_VIEW_RC=0

# A signal mid-analysis leaves the guard unable to confirm anything. It cannot
# emit a decision it never computed, so it exits without one; the deny that
# matters (a hung query) is prevented by the mandatory timeout bound above,
# not by this trap.
trap 'exit 0' HUP INT TERM PIPE

main
exit 0
