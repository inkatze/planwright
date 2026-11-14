#!/bin/sh
# run-record.sh — the harness-rebaseline measurement kit: turn one worker run
# into one machine-readable record from the fleet's shipped logs, compare two
# records, and write the report every experiment shares.
#
# Usage:
#   run-record.sh record --events <events.jsonl> --audit <allow-audit.log>
#                        --gate <gate-output> --result <result-row>
#                        --identity-file <file> [--out <file>]
#                        [--token-env <VAR>]
#   run-record.sh compare <record-a> <record-b> --variable <field>
#   run-record.sh report --title <text> [--note <text>]... <record>...
#
# record reads only what the fleet writes, never a worker's account of itself:
#   --events    the stream-json event capture (streamjson/<worker>/events.jsonl)
#   --audit     the guard's allow-audit log (one line per approval)
#   --gate      the local gate output; its verdict is the last GATE_EXIT=<n> line
#   --result    the supervisor's result row (the streamjson `result` file)
#   --identity-file  key=value lines naming the harness under test (the runner
#                    writes it): planwright_commit, plugin_build,
#                    claude_cli_version, model_map, worker_brief_variant,
#                    permission_arm, known_bad_set_hash, candidate_diff_hash,
#                    changed_knobs. Values are plain tokens (letters, digits
#                    and . _ : = , @ + -), so a command or path never rides in.
# A source that is absent or unreadable is named on stderr and nothing is
# written (exit 3), never zeros. --out defaults to stdout. The OAuth token's
# value (named by --token-env) and any token-shaped value are scrubbed.
#
# Counting rules: tool calls are the distinct tool_use ids, subagents included;
# tokens sum the usage of every assistant message once by message id, so a
# message split across frames counts once and subagent turns count in the
# session total; prompts are can_use_tool control_requests other than
# AskUserQuestion; denials are error tool results reporting a denial; polish
# rounds are self-review Skill calls; lens agents are Agent or Task calls whose
# description or type names a lens.
#
# compare refuses a pair that differs in more than --variable, and any pair
# whose known_bad_set_hash differs (never a comparable variable). --variable is
# a harness field, or `candidate` for the diff hash and the knobs together.
#
# report writes markdown of counts and harness identities, never a recorded
# command, absolute home path or token; text that would carry one is refused
# and nothing is written.
#
# Exit: 0 ok, 1 refused (compare, report), 2 usage, 3 missing source.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

prog=run-record.sh
ID_KEYS="planwright_commit plugin_build claude_cli_version model_map worker_brief_variant permission_arm known_bad_set_hash candidate_diff_hash changed_knobs"

die() {
  printf '%s: %s\n' "$prog" "$1" >&2
  exit "${2:-2}"
}

need_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required" 2
}

# A value is a plain token when it holds only these characters.
plain() {
  case $1 in
    *[!A-Za-z0-9._:=,@+-]*) return 1 ;;
  esac
  return 0
}

# unsafe_text <text>: success when the text carries a home path, a token
# shape, the named token's value, or command syntax.
unsafe_text() {
  case $1 in
    */home/* | */Users/* | */root/* | *sk-ant-* | *\$\(* | *\`*) return 0 ;;
  esac
  if [ -n "${RR_TOKEN_VALUE:-}" ]; then
    case $1 in *"$RR_TOKEN_VALUE"*) return 0 ;; esac
  fi
  return 1
}

load_token() {
  RR_TOKEN_VALUE=''
  [ -n "$1" ] || return 0
  case $1 in
    *[!A-Za-z0-9_]*) die "--token-env must name an environment variable" 2 ;;
  esac
  RR_TOKEN_VALUE=$(printenv "$1" 2>/dev/null) || RR_TOKEN_VALUE=''
}

# ---------------------------------------------------------------- record

cmd_record() {
  events='' audit='' gate='' result='' idfile='' out='' tokenv=''
  while [ $# -gt 0 ]; do
    case $1 in
      --events | --audit | --gate | --result | --identity-file | --out | --token-env)
        [ $# -ge 2 ] || die "$1 needs a value" 2
        case $1 in
          --events) events=$2 ;;
          --audit) audit=$2 ;;
          --gate) gate=$2 ;;
          --result) result=$2 ;;
          --identity-file) idfile=$2 ;;
          --out) out=$2 ;;
          --token-env) tokenv=$2 ;;
        esac
        shift 2
        ;;
      *) die "record: unknown argument" 2 ;;
    esac
  done
  need_jq
  load_token "$tokenv"

  missing=''
  for pair in "events:$events" "audit:$audit" "gate:$gate" "result:$result" "identity:$idfile"; do
    role=${pair%%:*}
    path=${pair#*:}
    if [ -z "$path" ] || [ ! -f "$path" ] || [ ! -r "$path" ]; then
      missing="$missing $role"
    fi
  done
  if [ -n "$missing" ]; then
    die "missing source:$missing" 3
  fi

  # Gate verdict: the last GATE_EXIT=<n> line.
  gate_line=$(grep -E '^GATE_EXIT=[0-9]+$' "$gate" | tail -n 1)
  [ -n "$gate_line" ] || die "missing source: gate (no GATE_EXIT line in the gate output)" 3
  gate_exit=${gate_line#GATE_EXIT=}

  # Outcome from the supervisor's result row.
  row=$(sed -n '1p' "$result")
  kind=$(printf '%s' "$row" | cut -f1)
  second=$(printf '%s' "$row" | cut -f2)
  iserr=$(printf '%s' "$row" | cut -f4)
  cause=$(printf '%s' "$row" | cut -f5)
  case $kind in
    result)
      if [ "$iserr" = true ]; then
        case $cause in
          limited=*) outcome=rate-limited ;;
          *) outcome=crashed ;;
        esac
      else
        outcome=completed
      fi
      ;;
    exit)
      case $second in
        0) outcome=completed ;;
        124) outcome=timed-out ;;
        *)
          case $cause in
            limited=*) outcome=rate-limited ;;
            *) outcome=crashed ;;
          esac
          ;;
      esac
      ;;
    *) die "missing source: result (unrecognised result row)" 3 ;;
  esac

  # Identity: every key present, each a plain token.
  ident='{}'
  for k in $ID_KEYS; do
    v=$(grep "^$k=" "$idfile" | tail -n 1)
    [ -n "$v" ] || die "missing source: identity (no $k)" 3
    v=${v#"$k="}
    [ -n "$v" ] || die "identity field $k is empty" 2
    plain "$v" || die "identity field $k is not a plain token (letters, digits and . _ : = , @ + - only)" 2
    ident=$(printf '%s' "$ident" | jq -c --arg k "$k" --arg v "$v" '. + {($k): $v}') || die "jq failed" 2
  done

  approvals=$(grep -c 'cmd_sha256=' "$audit")
  [ -n "$approvals" ] || approvals=0

  rec=$(jq -nR -c --argjson ident "$ident" --arg outcome "$outcome" \
    --argjson gexit "$gate_exit" --argjson approvals "$approvals" '
    def text: if type == "array" then map(.text? // "") | join(" ") else (. // "") end;
    [inputs | fromjson?] as $ev
    | [$ev[] | select(.type == "assistant") | .message | select(. != null)] as $msgs
    | [$msgs[] | .content[]? | select(.type == "tool_use")] as $uses
    | ($msgs | map(select(.id != null)) | group_by(.id) | map(last | .usage // {})) as $usage
    | def tok(f): ($usage | map(.[f] // 0) | add // 0);
    {
      schema_version: 1,
      tool_calls: ($uses | unique_by(.id) | length),
      permission_prompts: ([$ev[] | select(.type == "control_request"
          and .request.subtype == "can_use_tool"
          and .request.tool_name != "AskUserQuestion")] | unique_by(.request_id) | length),
      denials: ([$ev[] | select(.type == "user") | .message.content[]?
          | select(.type == "tool_result" and .is_error == true
            and ((.content | text) | test("denied|doesn.t want to proceed|was blocked"; "i")))]
          | length),
      audited_approvals: $approvals,
      tokens: {
        input: tok("input_tokens"),
        output: tok("output_tokens"),
        cache_creation: tok("cache_creation_input_tokens"),
        cache_read: tok("cache_read_input_tokens")
      },
      wall_time_seconds: ([$ev[] | select(.type == "result") | .duration_ms] | last
          | if . == null then null else ((. / 1000) | floor) end),
      polish_rounds: ([$uses[] | select(.name == "Skill"
          and ((.input.skill // "") | test("self-review")))] | unique_by(.id) | length),
      lens_agents: ([$uses[] | select((.name == "Agent" or .name == "Task")
          and (((.input.description // "") + " " + (.input.subagent_type // "")) | test("lens"; "i")))]
          | unique_by(.id) | length),
      outcome: $outcome,
      gate: {exit: $gexit, passed: ($gexit == 0)},
      harness: $ident
    }
    | .tokens.total = (.tokens | add)' <"$events") || die "events: not a readable stream-json log" 3

  tok_for_jq=$RR_TOKEN_VALUE
  rec=$(printf '%s' "$rec" | RR_TOK=$tok_for_jq jq -c '
    ($ENV.RR_TOK // "") as $t
    | walk(if type == "string"
        then ((if $t != "" then split($t) | join("[scrubbed]") else . end)
              | gsub("sk-ant-[A-Za-z0-9_-]+"; "[scrubbed]"))
        else . end)') || die "scrub failed" 2

  if [ -n "$out" ]; then
    printf '%s\n' "$rec" >"$out" || die "cannot write the record" 2
  else
    printf '%s\n' "$rec"
  fi
}

# ---------------------------------------------------------------- compare

cmd_compare() {
  a='' b='' var=''
  while [ $# -gt 0 ]; do
    case $1 in
      --variable)
        [ $# -ge 2 ] || die "--variable needs a value" 2
        var=$2
        shift 2
        ;;
      -*) die "compare: unknown argument" 2 ;;
      *)
        if [ -z "$a" ]; then a=$1; elif [ -z "$b" ]; then b=$1; else die "compare takes two records" 2; fi
        shift
        ;;
    esac
  done
  [ -n "$a" ] && [ -n "$b" ] || die "compare takes two records" 2
  [ -n "$var" ] || die "compare needs --variable <field>" 2
  need_jq
  [ -f "$a" ] && [ -f "$b" ] || die "compare: a record is missing" 2

  case $var in
    candidate) allowed='candidate_diff_hash changed_knobs' ;;
    known_bad_set_hash) allowed='' ;;
    *)
      ok=0
      for k in $ID_KEYS; do [ "$k" != "$var" ] || ok=1; done
      [ "$ok" -eq 1 ] || die "compare: --variable is not a harness field" 2
      allowed=$var
      ;;
  esac

  diffs=''
  for k in $ID_KEYS; do
    va=$(jq -r --arg k "$k" '.harness[$k] // ""' "$a") || die "compare: unreadable record" 2
    vb=$(jq -r --arg k "$k" '.harness[$k] // ""' "$b") || die "compare: unreadable record" 2
    if [ -z "$va" ] || [ -z "$vb" ]; then
      die "compare refused: a record is missing harness field $k" 1
    fi
    [ "$va" = "$vb" ] || diffs="$diffs $k"
  done

  case " $diffs " in
    *' known_bad_set_hash '*)
      die "compare refused: records were made under different known-bad sets (known_bad_set_hash differs; re-run under one set)" 1
      ;;
  esac

  extra=0
  for k in $diffs; do
    inallowed=0
    for al in $allowed; do [ "$al" != "$k" ] || inallowed=1; done
    [ "$inallowed" -eq 1 ] || extra=1
  done
  if [ "$extra" -eq 1 ]; then
    names=$(printf '%s' "$diffs" | sed 's/^ //; s/ /, /g')
    die "compare refused: records differ in more than $var: $names" 1
  fi
  printf 'compare ok: records differ only in %s\n' "$var"
}

# ---------------------------------------------------------------- report

cmd_report() {
  title='' notes='' tokenv=''
  recs=''
  while [ $# -gt 0 ]; do
    case $1 in
      --title)
        [ $# -ge 2 ] || die "--title needs a value" 2
        title=$2
        shift 2
        ;;
      --note)
        [ $# -ge 2 ] || die "--note needs a value" 2
        notes="$notes
$2"
        shift 2
        ;;
      --token-env)
        [ $# -ge 2 ] || die "--token-env needs a value" 2
        tokenv=$2
        shift 2
        ;;
      -*) die "report: unknown argument" 2 ;;
      *)
        recs="$recs
$1"
        shift
        ;;
    esac
  done
  [ -n "$title" ] || die "report needs --title" 2
  [ -n "$recs" ] || die "report needs at least one record" 2
  need_jq
  load_token "$tokenv"

  unsafe_text "$title" && die "report refused: the title carries a command, home path or token" 1
  oldifs=$IFS
  IFS='
'
  for n in $notes; do
    unsafe_text "$n" && die "report refused: a note carries a command, home path or token" 1
  done

  body="# $title
"
  for n in $notes; do
    body="$body
$n
"
  done
  body="$body
| run | arm | outcome | tool calls | prompts | denials | tokens | wall s | polish | lens | gate |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"
  idx=0
  ident_md=''
  for r in $recs; do
    idx=$((idx + 1))
    [ -f "$r" ] || die "report: a record is missing" 2
    IFS=$oldifs
    for k in $ID_KEYS; do
      v=$(jq -r --arg k "$k" '.harness[$k] // ""' "$r") || die "report: unreadable record" 2
      [ -n "$v" ] || die "report refused: record $idx lacks harness field $k" 1
      plain "$v" || die "report refused: record $idx field $k is not a plain token" 1
    done
    IFS='
'
    row=$(jq -r --argjson i "$idx" '
      def num: if type == "number" then . else error("not a number") end;
      "| \($i) | \(.harness.permission_arm) | \(.outcome) | \(.tool_calls | num) | \(.permission_prompts | num) | \(.denials | num) | \(.tokens.total | num) | \(.wall_time_seconds // "n/a") | \(.polish_rounds | num) | \(.lens_agents | num) | \(if .gate.passed then "pass" else "fail" end) |"' "$r") \
      || die "report refused: record $idx is not a run record" 1
    body="$body
$row"
    id_row=$(jq -r --argjson i "$idx" '
      "- run \($i): " + ([.harness | to_entries[] | "\(.key)=\(.value)"] | join(" "))' "$r") \
      || die "report refused: record $idx is not a run record" 1
    ident_md="$ident_md
$id_row"
  done
  IFS=$oldifs
  body="$body

## Harness identities
$ident_md"

  unsafe_text "$body" && die "report refused: the report would carry a command, home path or token" 1
  printf '%s\n' "$body"
}

[ $# -ge 1 ] || die "usage: run-record.sh record|compare|report ..." 2
sub=$1
shift
case $sub in
  record) cmd_record "$@" ;;
  compare) cmd_compare "$@" ;;
  report) cmd_report "$@" ;;
  *) die "unknown subcommand" 2 ;;
esac
