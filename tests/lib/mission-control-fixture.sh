# shellcheck shell=bash
# Shared fixture for the mission-control program and duty tests: a fixture
# core root, a fixture repository carrying the repo-tracked layer, an empty
# adopter overlay, and a runner that points every layer at them.
#
# The sourcing test sets `repo_root` (the checkout under test) and `tmp` (a
# canonical scratch directory it cleans up) before sourcing, and defines
# fail() and ok(). After sourcing:
#   $core      fixture core root (config/defaults.yml, config/duties.yaml)
#   $repo      fixture git repository; $tracked its .claude/planwright.yml
#   $adopter   the adopter overlay root
#   $fixhome   HOME for the scripts under test
#   mc_run <script> [args...]   run scripts/<script> against the fixture;
#                               sets RC, OUT (stdout) and ERR (stderr)

# The runner resolves paths through a cd in a command substitution.
unset CDPATH

: "${tmp:?set tmp before sourcing}" "${repo_root:?set repo_root before sourcing}"

core="$tmp/core"
repo="$tmp/repo"
adopter="$tmp/adopter"
fixhome="$tmp/home"
tracked="$repo/.claude/planwright.yml"
mkdir -p "$core/config" "$core/doctrine" "$repo/.claude/catalogs" "$adopter/catalogs" "$fixhome" "$tmp/claude"
git -C "$repo" init -q

# write_core_defaults: the mission-control knobs as the shipped defaults set
# them, plus any extra lines on stdin.
write_core_defaults() {
  {
    grep '^mission_control_' "$repo_root/config/defaults.yml"
    cat
  } >"$core/config/defaults.yml"
}

# write_core_duties: a fixture seed of two duties, one live with watchers and
# one off.
write_core_duties() {
  cat >"$core/config/duties.yaml" <<'EOF'
---
duties:
  - id: alpha-duty
    summary: "A shipped live duty"
    triggers: [pr-opened]
    watchers: [scripts/alpha-watch.sh@5m/low, scripts/alpha-sweep.sh@1h/medium]
    wake: alpha-due
    rules: [alpha-rule]
    kinds: [alpha-item]
    files: alpha
    lifecycle: live
    never-propose: false
  - id: beta-duty
    summary: "A shipped duty that is off"
    triggers: []
    watchers: [scripts/beta-watch.sh@10m/high]
    wake: none
    rules: []
    kinds: []
    files: beta
    lifecycle: off
    never-propose: true
EOF
}

reset_mc_fixture() {
  write_core_defaults </dev/null
  write_core_duties
  : >"$tracked"
  rm -f "$repo/.claude/catalogs/duties.yaml" "$adopter/catalogs/duties.yaml"
}

mc_run() {
  mc_script=$1
  shift
  OUT=$(cd "$repo" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_SKILLS_ROOT \
    -u PLANWRIGHT_CONFIG_DEFAULTS -u PLANWRIGHT_REPO_ROOT_CHECKED -u PLANWRIGHT_CONFIG_STRICT_OVERLAYS \
    -u XDG_CONFIG_HOME \
    PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_LOCAL_CONFIG="$tmp/absent.yml" CLAUDE_DIR="$tmp/claude" HOME="$fixhome" \
    /bin/bash "$repo_root/scripts/$mc_script" "$@" 2>"$tmp/stderr")
  RC=$?
  ERR=$(cat "$tmp/stderr")
}

expect_rc() { # expect_rc <label> <want>
  if [ "$RC" -eq "$2" ]; then
    ok "$1 (exit $2)"
  else
    fail "$1: expected exit $2, got $RC"
    printf '%s\n' "----- stdout -----" "$OUT" "----- stderr -----" "$ERR" "------------------" >&2
  fi
}
expect_out() { # expect_out <label> <needle>: stdout carries the needle
  case "$OUT" in
    *"$2"*) ok "$1" ;;
    *)
      fail "$1: stdout lacks '$2'"
      printf '%s\n' "----- stdout -----" "$OUT" "----- stderr -----" "$ERR" "------------------" >&2
      ;;
  esac
}
expect_no_out() { # expect_no_out <label> <needle>
  case "$OUT" in
    *"$2"*)
      fail "$1: stdout carries '$2'"
      printf '%s\n' "----- stdout -----" "$OUT" "------------------" >&2
      ;;
    *) ok "$1" ;;
  esac
}
expect_err() { # expect_err <label> <needle>: stderr carries the needle
  case "$ERR" in
    *"$2"*) ok "$1" ;;
    *)
      fail "$1: stderr lacks '$2'"
      printf '%s\n' "----- stdout -----" "$OUT" "----- stderr -----" "$ERR" "------------------" >&2
      ;;
  esac
}
expect_eq() { # expect_eq <label> <want>: stdout is exactly the value
  if [ "$OUT" = "$2" ]; then
    ok "$1"
  else
    fail "$1: stdout differs"
    printf '%s\n' "----- want -----" "$2" "----- got -----" "$OUT" "----- stderr -----" "$ERR" "---------------" >&2
  fi
}
