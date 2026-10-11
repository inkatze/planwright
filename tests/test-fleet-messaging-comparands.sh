#!/bin/bash
# The frozen comparands messaging must not move (REQ-A1.5): with messaging
# absent, the signal paths' one-shot outputs equal what the same scripts
# produced at the base commit fleet-messaging Task 2 recorded, and
# fleet-attention.sh's four signal write verbs are byte-identical to their text
# there. Each comparand's base commit is read from its own one-line file under
# tests/fixtures/fleet-messaging/, and the base content comes from git, never
# from a hand-kept copy.
#
# Comparands: the page `fleet-dashboard.sh write --out` writes; the stdout and
# signature file of `fleet-attention-watch.sh watch --once`; the commands
# `orchestrate-relay.sh` emits; and the commands `fleet-decision.sh answer`
# emits, over a store with no answered-undelivered case.
#
# Runs standalone under /bin/bash (bash 3.2). Needs the repository's history
# (CI checks out with full depth).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
fixtures="$here/fixtures/fleet-messaging"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# base_of <comparand> — the recorded base commit, validated as a full SHA that
# this checkout's history holds.
base_of() {
  bo_f="$fixtures/base-$1.sha"
  [ -r "$bo_f" ] || fail "$1: no base-SHA file at ${bo_f#"$root"/}"
  bo_sha=$(cat "$bo_f")
  case $bo_sha in
    *[!0-9a-f]* | "") fail "$1: the base-SHA file does not hold a hex SHA" ;;
  esac
  [ "${#bo_sha}" -eq 40 ] || fail "$1: the base-SHA file does not hold a full 40-hex SHA"
  git -C "$root" cat-file -e "$bo_sha^{commit}" 2>/dev/null \
    || fail "$1: base commit $bo_sha is not in this checkout's history (a shallow clone?)"
  printf '%s' "$bo_sha"
}

# tree_at <sha> <dir> — the scripts and config of <sha> under <dir>.
tree_at() {
  mkdir -p "$2"
  git -C "$root" archive "$1" scripts config | tar -x -C "$2"
}

cur="$tmp/trees/cur"
mkdir -p "$cur"
cp -R "$root/scripts" "$root/config" "$cur/"

# norm <file> — mask the per-tree and per-home paths so two runs compare.
norm() {
  sed -e "s|$tmp/trees/[a-z0-9-]*|<tree>|g" -e "s|$tmp/homes/[a-z0-9-]*|<home>|g" \
    -e "s|generated [0-9][0-9T:-]*Z|generated <stamp>|g" "$1"
}

henv() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME -u PLANWRIGHT_ROOT \
    -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT -u PLANWRIGHT_LOCAL_CONFIG \
    -u PLANWRIGHT_CONFIG_DEFAULTS -u CLAUDE_CODE_MESSAGING_SOCKET -u TMUX \
    PLANWRIGHT_FLEET_STATE_DIR="$1" "${@:2}"
}

# A fixed attention store: a working row, a park, and an unclaimed fork. Stamps
# are fixed so both trees read the same store.
seed_store() {
  mkdir -p "$1/attention"
  {
    printf 'w-work\tspec-a:1\tworking\t1700000000\t\t\t\t\n'
    printf 'w-park\tspec-a:2\tawaiting-input\t1700000100\tnormal\t\t\t\tnotification:idle_prompt\n'
    printf 'w-fork\tspec-b:3\tawaiting-input\t1700000200\tnormal\tWhich store?\tsqlite\tsqlite|postgres\tfork\tinst-1\n'
  } >"$1/attention/state"
}

# run_comparand <name> <scenario-fn> <primary-output> — run the scenario in the base tree and in
# this tree, each with its own home, and compare the normalized outputs.
run_comparand() {
  rc_name=$1
  rc_fn=$2
  rc_base=$(base_of "$rc_name")
  rc_btree="$tmp/trees/base-$rc_name"
  [ -d "$rc_btree" ] || tree_at "$rc_base" "$rc_btree"
  for side in base cur; do
    if [ "$side" = base ]; then rc_tree=$rc_btree; else rc_tree=$cur; fi
    rc_home="$tmp/homes/$rc_name-$side"
    rc_out="$tmp/out/$rc_name-$side"
    mkdir -p "$rc_home" "$rc_out"
    "$rc_fn" "$rc_tree" "$rc_home" "$rc_out" || fail "$rc_name: the $side scenario failed"
  done
  for f in "$tmp/out/$rc_name-base"/*; do
    g="$tmp/out/$rc_name-cur/${f##*/}"
    [ -f "$g" ] || fail "$rc_name: ${f##*/} produced at the base but not now"
    if [ "$(norm "$f")" != "$(norm "$g")" ]; then
      diff <(norm "$f") <(norm "$g") >&2 || :
      fail "$rc_name: ${f##*/} differs from base commit $rc_base"
    fi
  done
  [ -s "$tmp/out/$rc_name-cur/$3" ] || fail "$rc_name: $3 is empty, so the comparison proves nothing"
  if grep -q '^rc=[1-9]' "$tmp/out/$rc_name-cur/stdout"; then
    fail "$rc_name: a scenario command failed: $(grep '^rc=' "$tmp/out/$rc_name-cur/stdout" | tr '\n' ' ')"
  fi
  echo "ok: $rc_name equals its base-commit output"
}

dashboard_scenario() {
  {
    echo '#!/bin/sh'
    printf 'printf "source\\tattention\\tok\\t2-rows\\n"\n'
    printf 'printf "worker\\tw-alpha\\tspecs/a/task-1\\tattention\\tworking\\t12\\trunning\\t0\\tbusy\\n"\n'
    printf 'printf "worker\\tw-beta\\tspecs/b/task-2\\tattention\\tawaiting-input\\t400\\t-\\t-\\t-\\n"\n'
  } >"$1/scripts/fleet-status.sh"
  chmod +x "$1/scripts/fleet-status.sh"
  henv "$2" /bin/sh "$1/scripts/fleet-dashboard.sh" write --out "$3/page.html" >"$3/stdout" 2>"$3/stderr"
}

watch_scenario() {
  seed_store "$2"
  henv "$2" /bin/sh "$1/scripts/fleet-attention-watch.sh" watch --once >"$3/stdout" 2>"$3/stderr"
  cp "$2/attention/watch.sig" "$3/watch.sig"
}

relay_scenario() {
  printf 'steer: rebase onto main\n' >"$2/msg.txt"
  {
    henv "$2" /bin/sh "$1/scripts/orchestrate-relay.sh" relay-command tmux 'fleet:w-1' "$2/msg.txt"
    echo "rc=$?"
    henv "$2" /bin/sh "$1/scripts/orchestrate-relay.sh" relay-command stream-json w-sj "$2/msg.txt"
    echo "rc=$?"
    henv "$2" /bin/sh "$1/scripts/orchestrate-relay.sh" relay-command subagent agent-1 "$2/msg.txt"
    echo "rc=$?"
    henv "$2" /bin/sh "$1/scripts/orchestrate-relay.sh" observe-command tmux 'fleet:w-1'
    echo "rc=$?"
    henv "$2" /bin/sh "$1/scripts/orchestrate-relay.sh" observe-command stream-json w-sj
    echo "rc=$?"
  } >"$3/stdout" 2>"$3/stderr"
}

decision_scenario() {
  seed_store "$2"
  {
    henv "$2" /bin/sh "$1/scripts/fleet-decision.sh" answer tmux 'fleet:w-fork' w-fork inst-1 postgres
    echo "rc=$?"
  } >"$3/stdout" 2>"$3/stderr"
  cp "$2/attention/answers/w-fork" "$3/answer-artifact"
}

run_comparand dashboard-page dashboard_scenario page.html
run_comparand attention-watch-once watch_scenario stdout
run_comparand relay-commands relay_scenario stdout
run_comparand decision-commands decision_scenario stdout

# fleet-attention.sh's four signal write verbs, byte-identical to the base.
verbs_base=$(base_of fleet-attention-write-verbs)
verb_text() {
  awk -v v="$1" '
    $0 ~ "^  " v "\\)$" { on = 1 }
    on { print }
    on && /^    ;;$/ { exit }
  '
}
for v in heartbeat decide fork park; do
  now=$(verb_text "$v" <"$root/scripts/fleet-attention.sh")
  then_=$(git -C "$root" show "$verbs_base:scripts/fleet-attention.sh" | verb_text "$v")
  [ -n "$then_" ] || fail "fleet-attention.sh: no '$v' verb at base $verbs_base"
  [ "$now" = "$then_" ] || fail "fleet-attention.sh: the '$v' write verb changed since base $verbs_base"
done
echo "ok: fleet-attention.sh's heartbeat, decide, fork, and park verbs are byte-identical to the base"

echo "PASS: test-fleet-messaging-comparands.sh"
