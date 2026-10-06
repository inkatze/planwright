#!/bin/bash
# The core root chain lives in one place (custom-spec-location REQ-C1.1):
#   * no script under scripts/ but the resolver reads the chain's variables or
#     composes its writer-delivery directory, apart from the allowlisted sites
#     below;
#   * both command guards take the chain from the resolver, and each keeps its
#     own trust policy: the worker guard adds its own root and the installed
#     roots, the tower guard trusts the plugin-delivery arm alone.
set -u
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
WORKER="$REPO_ROOT/scripts/worker-command-guard.sh"
TOWER="$REPO_ROOT/scripts/tower-command-guard.sh"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

# --- the chain is implemented only in the resolver --------------------------

# <script> TAB <why it may read the chain's variables>. A row matching nothing
# fails as stale, so a site that moves onto the resolver deletes its row.
allowlist='fleet-dispatch-env.sh	publishes the operator'"'"'s own values into a worker'"'"'s environment; it picks no root
install.sh	it writes the writer-delivery copy, so it names that directory as a destination, not as an arm
inception-scaffold.sh	the venture hook it emits runs outside planwright and must locate a copy before it can ask that copy'"'"'s resolver'

# <script> TAB <the exact read, trimmed> TAB <why>: a single read a script may
# make, every other read in it still failing. Each row must match a read
# that exists, or it fails as stale.
# shellcheck disable=SC2016 # the reads are literal shell text
line_allowlist='worker-command-guard.sh	local r=${CLAUDE_PLUGIN_ROOT:-}	trust policy: it withholds a symlinked plugin-delivery arm from the resolver, which would canonicalize it into trusting the link target; the resolver still picks the roots
tower-command-guard.sh	local r=${CLAUDE_PLUGIN_ROOT:-}	trust policy: it withholds a symlinked plugin-delivery arm from the resolver, which would canonicalize it into trusting the link target; the resolver still picks the root'

# chain_reads <file>: the non-comment lines expanding either variable, or
# naming the writer-delivery directory itself (`<claude-dir>/planwright` with
# nothing below it). An escaped `\$NAME` is hook text being substituted, not
# an expansion.
chain_reads() {
  grep -nE '(^|[^\\])\$\{?(PLANWRIGHT_ROOT|CLAUDE_PLUGIN_ROOT)([^A-Za-z0-9_]|$)|(\.claude|claude_dir|CLAUDE_DIR)\}?/planwright(["}]|$)' "$1" \
    | grep -vE '^[0-9]+:[[:space:]]*#'
}

# unallowed_reads <file> <name>: chain_reads minus the reads line_allowlist
# grants <name>, matched on the whole trimmed line.
unallowed_reads() {
  local hit text allowed
  allowed=$(printf '%s\n' "$line_allowlist" | awk -F '\t' -v n="$2" '$1 == n { print $2 }')
  chain_reads "$1" | while IFS= read -r hit; do
    text=${hit#*:}
    text=${text#"${text%%[![:space:]]*}"}
    text=${text%"${text##*[![:space:]]}"}
    if [ -n "$allowed" ] && printf '%s\n' "$allowed" | grep -qxF -- "$text"; then
      continue
    fi
    printf '%s\n' "$hit"
  done
}

for f in "$REPO_ROOT"/scripts/*.sh; do
  name=${f##*/}
  [ "$name" = resolve-root.sh ] && continue
  hits=$(chain_reads "$f") || continue
  if printf '%s\n' "$allowlist" | cut -f1 | grep -qxF "$name"; then
    continue
  fi
  hits=$(unallowed_reads "$f" "$name")
  [ -n "$hits" ] || continue
  fail "scripts/$name reads the core root chain inline:
$hits"
done
[ "$failures" -eq 0 ] && ok "no script but the resolver reads the core root chain inline"

while IFS="$(printf '\t')" read -r name why; do
  [ -n "$name" ] || continue
  if chain_reads "$REPO_ROOT/scripts/$name" >/dev/null; then
    ok "allowlisted: scripts/$name ($why)"
  else
    fail "stale allowlist row: scripts/$name no longer reads the chain"
  fi
done <<EOF
$allowlist
EOF

while IFS="$(printf '\t')" read -r name line why; do
  [ -n "$name" ] || continue
  if chain_reads "$REPO_ROOT/scripts/$name" | grep -qF -- "$line"; then
    ok "allowlisted read: scripts/$name ($why)"
  else
    fail "stale line allowlist row: scripts/$name no longer makes the read '$line'"
  fi
done <<EOF
$line_allowlist
EOF

# The grep itself, on planted lines.
tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT
# shellcheck disable=SC2016 # planted lines are literal shell text
printf 'for r in "${PLANWRIGHT_ROOT:-}" x; do :; done\n' >"$tmp/inline.sh"
# shellcheck disable=SC2016
printf 'w="${CLAUDE_DIR:-$HOME/.claude}/planwright"\n' >"$tmp/writer.sh"
# shellcheck disable=SC2016
printf '# $PLANWRIGHT_ROOT in a comment\ns=${s//\\$CLAUDE_PLUGIN_ROOT/x}\nPLANWRIGHT_ROOT=/x cmd\n' >"$tmp/clean.sh"
if chain_reads "$tmp/inline.sh" >/dev/null; then ok "the grep flags an inline chain"; else fail "the grep missed an inline chain"; fi
if chain_reads "$tmp/writer.sh" >/dev/null; then ok "the grep flags a hand-rolled writer-delivery arm"; else fail "the grep missed a writer-delivery arm"; fi
if chain_reads "$tmp/clean.sh" >/dev/null; then fail "the grep flagged a comment, escaped text, or an assignment"; else ok "the grep passes comments, escaped text, and assignments"; fi
# A guard's line allowance covers its one read, never a second one.
# shellcheck disable=SC2016
printf '  local r=${CLAUDE_PLUGIN_ROOT:-}\nfor r in "${PLANWRIGHT_ROOT:-}" "${CLAUDE_PLUGIN_ROOT:-}"; do :; done\n' >"$tmp/guard.sh"
left=$(unallowed_reads "$tmp/guard.sh" worker-command-guard.sh)
if [ "$(printf '%s\n' "$left" | grep -c .)" = 1 ] && printf '%s' "$left" | grep -q '^2:'; then
  ok "a guard's allowed read passes and an added inline chain read still fails"
else
  fail "the line allowance let through more than the one read: '$left'"
fi

for g in "$WORKER" "$TOWER"; do
  if grep -vE '^[[:space:]]*#' "$g" | grep -q 'resolve-root\.sh" install'; then
    ok "${g##*/} takes the chain from the resolver"
  else
    fail "${g##*/} does not ask the resolver for the chain"
  fi
done

# --- each guard's trust policy ---------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
  fail "jq is required for the guard policy cases"
else
  mkdir -p "$tmp/home" "$tmp/repo/scripts" "$tmp/sibling/scripts"
  : >"$tmp/repo/.git"
  for t in pw plugin writer/planwright; do
    mkdir -p "$tmp/$t/scripts"
    : >"$tmp/$t/scripts/probe.sh"
  done
  : >"$tmp/sibling/scripts/probe.sh"

  # decision <guard> <script> <env...>: allow or defer for `bash <script>`,
  # run with every root variable cleared and HOME fenced, so the installed
  # roots are only what the fixture creates.
  decision() {
    dc_g=$1 dc_s=$2
    shift 2
    dc_p=$(jq -n --arg c "bash $dc_s" --arg w "$tmp/repo" \
      '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}')
    dc_out=$(printf '%s' "$dc_p" | env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
      HOME="$tmp/home" "$@" /bin/bash "$dc_g" 2>/dev/null)
    case $dc_out in
      *'"allow"'*) echo allow ;;
      *) echo defer ;;
    esac
  }
  expect() {
    # expect <label> <want> <got>
    if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected $2, got $3)"; fi
  }

  expect "worker: trusts the PLANWRIGHT_ROOT arm" allow \
    "$(decision "$WORKER" "$tmp/pw/scripts/probe.sh" PLANWRIGHT_ROOT="$tmp/pw")"
  expect "worker: trusts the CLAUDE_PLUGIN_ROOT arm" allow \
    "$(decision "$WORKER" "$tmp/plugin/scripts/probe.sh" CLAUDE_PLUGIN_ROOT="$tmp/plugin")"
  expect "worker: trusts the writer-mode arm" allow \
    "$(decision "$WORKER" "$tmp/writer/planwright/scripts/probe.sh" CLAUDE_DIR="$tmp/writer")"
  expect "worker: trusts its own root" allow \
    "$(decision "$WORKER" "$REPO_ROOT/scripts/resolve-root.sh")"
  expect "worker: a root no arm names is not trusted" defer \
    "$(decision "$WORKER" "$tmp/sibling/scripts/probe.sh" PLANWRIGHT_ROOT="$tmp/pw")"

  # The installed-roots arm is the worker's own policy: a cache version
  # directory Claude Code created is trusted with no variable naming it.
  mkdir -p "$tmp/home/.claude/plugins/cache/mkt/planwright/9.9.9/scripts"
  : >"$tmp/home/.claude/plugins/cache/mkt/planwright/9.9.9/scripts/probe.sh"
  expect "worker: trusts an installed root" allow \
    "$(decision "$WORKER" "$tmp/home/.claude/plugins/cache/mkt/planwright/9.9.9/scripts/probe.sh")"
  expect "tower: does not trust an installed root" defer \
    "$(decision "$TOWER" "$tmp/home/.claude/plugins/cache/mkt/planwright/9.9.9/scripts/probe.sh")"

  expect "tower: trusts the CLAUDE_PLUGIN_ROOT arm" allow \
    "$(decision "$TOWER" "$tmp/plugin/scripts/probe.sh" CLAUDE_PLUGIN_ROOT="$tmp/plugin")"
  expect "tower: does not trust the PLANWRIGHT_ROOT arm" defer \
    "$(decision "$TOWER" "$tmp/pw/scripts/probe.sh" PLANWRIGHT_ROOT="$tmp/pw")"
  # With both set, the chain lists PLANWRIGHT_ROOT first: the tower must pick
  # the plugin arm by its name, not the first line.
  expect "tower: with both arms set, still not the PLANWRIGHT_ROOT arm" defer \
    "$(decision "$TOWER" "$tmp/pw/scripts/probe.sh" PLANWRIGHT_ROOT="$tmp/pw" CLAUDE_PLUGIN_ROOT="$tmp/plugin")"
  expect "tower: with both arms set, the CLAUDE_PLUGIN_ROOT arm" allow \
    "$(decision "$TOWER" "$tmp/plugin/scripts/probe.sh" PLANWRIGHT_ROOT="$tmp/pw" CLAUDE_PLUGIN_ROOT="$tmp/plugin")"
  expect "tower: does not trust the writer-mode arm" defer \
    "$(decision "$TOWER" "$tmp/writer/planwright/scripts/probe.sh" CLAUDE_DIR="$tmp/writer")"
  expect "tower: does not trust its own root" defer \
    "$(decision "$TOWER" "$REPO_ROOT/scripts/resolve-root.sh")"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "all root-chain convergence tests passed"
  exit 0
fi
echo "$failures root-chain convergence test(s) failed" >&2
exit 1
