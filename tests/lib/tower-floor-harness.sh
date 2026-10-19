# shellcheck shell=bash
# tower-floor-harness.sh — the shared harness for the tower deny-floor suites
# (sourced, never executed): tests/test-tower-floor-map.sh,
# tests/test-tower-floor-worktree.sh, tests/test-tower-floor-push.sh, and
# tests/test-tower-floor-spellings.sh, split so each stays inside the
# per-file time ceiling. On top of tests/lib/policy-guard-harness.sh it adds
# a marked session in a sandbox fleet home, the git aliases the spelling rows
# use, and scripts/tower-session.sh run as the plugin hook runs it, with no
# tower profile in play.
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
# shellcheck disable=SC2034 # PROFILE and the decide globals are read by the sourcing suites and the shared expect
unset CDPATH
# Run from a git hook, these would point the alias setup and the guard's git
# reads at the outer repository instead of the sandbox.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/policy-guard-harness.sh"
# shellcheck source=tests/lib/permission-matcher.sh
. "$REPO_ROOT/tests/lib/permission-matcher.sh"

cp "$REAL_SCRIPTS/tower-session.sh" "$S/"
TS="$S/tower-session.sh"
FLEET="$SANDBOX/fleet"
MAP="$REPO_ROOT/tests/fixtures/tower-deny-acts.tsv"
PROFILE="$REPO_ROOT/config/tower-settings.json"
MARKED=11111111-2222-4333-8444-555555555555
TAB=$(printf '\t')

mkdir -p "$FLEET/tower-sessions"
chmod 700 "$FLEET" "$FLEET/tower-sessions"
printf 'tower\t%s\tprompt\n' "$(date +%s)" >"$FLEET/tower-sessions/$MARKED"
chmod 600 "$FLEET/tower-sessions/$MARKED"

for a in 'hr=reset --hard' 'bf=branch -f' 'ur=update-ref' 'wa=worktree add' 'pf=push --force' 'mg=merge' 'rb=rebase'; do
  git -C "$UNIT" config "alias.${a%%=*}" "${a#*=}"
done

ts_run() { # <surface>; the payload on stdin
  env -u CLAUDE_PLUGIN_DATA PATH="$BIN:$PATH" CLAUDE_PROJECT_DIR="$UNIT" \
    PLANWRIGHT_FLEET_STATE_DIR="$FLEET" \
    PLANWRIGHT_ADOPTER_OVERLAY="$SANDBOX/adopter" PLANWRIGHT_REPO_ROOT="$UNIT" \
    PLANWRIGHT_LOCAL_CONFIG="$LOCAL_CFG" /bin/bash "$TS" guard "$1" 2>/dev/null
}

decide() { # <surface> <payload> — sets OUT, CODE, DECISION, REASON
  OUT=$(printf '%s' "$2" | ts_run "$1")
  CODE=$?
  DECISION=defer
  REASON=''
  case $OUT in
    *[![:space:]]*)
      DECISION=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // "unparsed"' 2>/dev/null) || DECISION=unparsed
      REASON=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null) || REASON=''
      ;;
  esac
}

ts_bash() { # <command>
  decide bash "$(jq -nc --arg s "$MARKED" --arg c "$1" --arg w "$UNIT" '{session_id:$s, tool_name:"Bash", tool_input:{command:$c}, cwd:$w}')"
}

ts_mcp() { # <tool>
  decide mcp "$(jq -nc --arg s "$MARKED" --arg t "$1" --arg w "$UNIT" '{session_id:$s, tool_name:$t, tool_input:{pullNumber:1, owner:"o", repo:"r"}, cwd:$w}')"
}

# map_check <profile> — 0 when every deny entry of <profile> has an entry row
# in the map and every entry row names a deny entry of <profile>; prints each
# mismatch.
map_check() {
  local rc=0 e
  while IFS= read -r e; do
    awk -F'\t' -v e="$e" '$1 == "entry" && $2 == e { f = 1 } END { exit !f }' "$MAP" \
      || {
        printf '%s\n' "unmapped deny entry: $e"
        rc=1
      }
  done < <(jq -r '.permissions.deny[]' "$1")
  while IFS= read -r e; do
    jq -e --arg e "$e" '.permissions.deny | index($e) != null' "$1" >/dev/null \
      || {
        printf '%s\n' "map row names no deny entry: $e"
        rc=1
      }
  done < <(awk -F'\t' '$1 == "entry" { print $2 }' "$MAP")
  return "$rc"
}

# act_check <map> — 0 when every row names one of the acts the suites run
# (TOWER_ACTS) and every act has an entry row; prints each mismatch.
TOWER_ACTS='pr-merge flip base-merge rewrite ref-surgery mcp-write worktree push'
act_check() {
  local rc=0 kind a b act
  while IFS="$TAB" read -r kind a b _; do
    case $kind in
      entry) act=$b ;;
      spelling) act=$a ;;
      *) continue ;;
    esac
    case " $TOWER_ACTS " in
      *" $act "*) ;;
      *)
        printf '%s\n' "row names an act no suite runs: $act"
        rc=1
        ;;
    esac
  done <"$1"
  for act in $TOWER_ACTS; do
    awk -F'\t' -v a="$act" '$1 == "entry" && $3 == a { f = 1 } END { exit !f }' "$1" \
      || {
        printf '%s\n' "act with no entry row: $act"
        rc=1
      }
  done
  return "$rc"
}

# entry_rows <act ERE> — run every entry row whose act matches: its sample
# must be matched by its entry and refused in the marked session.
entry_rows() {
  local kind entry act sample
  while IFS="$TAB" read -r kind entry act sample; do
    [ "$kind" = entry ] || continue
    [[ $act =~ $1 ]] || continue
    case $entry in
      Bash\(*)
        pm_load_rules "$entry" '' ''
        [ "$(pm_decide "$sample")" = deny ] \
          || fail "the sample '$sample' is not matched by its entry $entry"
        ts_bash "$sample"
        ;;
      *)
        # shellcheck disable=SC2053 # the entry is the glob under test
        [[ $sample == $entry ]] || fail "the tool $sample is not matched by its entry $entry"
        ts_mcp "$sample"
        ;;
    esac
    expect deny "[$act] $entry: $sample"
  done <"$MAP"
}
