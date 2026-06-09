#!/usr/bin/env bash
# pair-flow-config.sh — read and update pair-flow configuration.
#
# Subcommands (the calling agent invokes these; the script never prompts
# directly so it stays composable from inside skills and slash commands):
#
#   repo                            Print current repo as owner/name.
#   defaults                        Print the defaults file as YAML.
#   repo-class                      Print the effective repo-class for the current repo.
#                                   If no entry exists in ~/.claude/pair-flow.local.yml,
#                                   print `needs-confirmation:<inferred-value>` and exit 2.
#                                   The caller is expected to ask the user, then call
#                                   `confirm-repo-class <value>`.
#   confirm-repo-class <value>      Write/update the current repo's repo-class to
#                                   ~/.claude/pair-flow.local.yml. Creates the file
#                                   if missing.
#   show                            Print the effective config for the current repo
#                                   (defaults merged with the local override) as YAML.
#
# Files:
#   ~/.claude/pair-flow.yml         (tracked defaults; symlinked from dotfiles)
#   ~/.claude/pair-flow.local.yml   (per-host, agent-maintained, never tracked)
#
# Per D-19, D-20 in specs/pair-flow/design.md.

set -u

DEFAULTS="${PAIR_FLOW_DEFAULTS:-$HOME/.claude/pair-flow.yml}"
LOCAL="${PAIR_FLOW_LOCAL:-$HOME/.claude/pair-flow.local.yml}"

# --- helpers --------------------------------------------------------------

die() {
    printf 'pair-flow-config: %s\n' "$1" >&2
    exit 1
}

# Ensure python3 + PyYAML are present before any YAML read/write. Without this
# guard a fresh machine fails mid-run with a cryptic ModuleNotFoundError,
# breaking repo-class detection and every skill that depends on it.
require_pyyaml() {
    command -v python3 >/dev/null 2>&1 \
        || die "python3 not found; required for YAML config parsing"
    python3 -c 'import yaml' >/dev/null 2>&1 \
        || die "Python module 'yaml' (PyYAML) not found; install it (e.g. pip install pyyaml) — required for pair-flow config parsing"
}

current_repo() {
    # Prefer gh repo view; fall back to parsing git remote.
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        local r
        r=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
        if [ -n "$r" ]; then
            printf '%s\n' "$r"
            return 0
        fi
    fi
    # Fallback: extract owner/repo from origin URL. Handles git@host:owner/repo.git
    # and https://host/owner/repo[.git].
    local url
    url=$(git remote get-url origin 2>/dev/null || true)
    [ -z "$url" ] && die "could not determine current repo (no gh, no git remote)"
    # Strip .git suffix, then take the last two path components.
    url="${url%.git}"
    # SSH: git@host:owner/repo
    if [[ "$url" =~ ^[^@]+@[^:]+:(.+)$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    # HTTPS / https://host/owner/repo or git://host/owner/repo
    if [[ "$url" =~ ([^/]+/[^/]+)$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    die "could not parse repo from git remote: $url"
}

# Infer repo-class: scan recent merged + open PRs, look for any non-author
# human reviewer in the last 30. Bots are excluded (their login type is "Bot"
# in the GraphQL schema; gh exposes it via .reviews[].author.is_bot or via
# searching for "[bot]" in the login).
infer_repo_class() {
    if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
        # No gh, no signal. Suggest solo (the common case for these repos:
        # dotfiles, tecpan). This is only a suggestion: `repo-class` returns it
        # as needs-confirmation:<value> (exit 2) and the human confirms before
        # it takes effect, so the autonomy gate is never set from inference
        # alone. (solo enables Agent-resolvable auto-apply; multi-reviewer is
        # the one that surfaces for review.)
        printf 'solo\n'
        return 0
    fi
    local out
    # Use --json for stable structure; PRs with no reviews still have an empty list.
    out=$(gh pr list --state all --limit 30 --json author,reviews 2>/dev/null || true)
    if [ -z "$out" ] || [ "$out" = "null" ] || [ "$out" = "[]" ]; then
        printf 'solo\n'
        return 0
    fi
    # Look for any PR where reviews[].author.login is a non-bot human and
    # not equal to the PR author. Bots are filtered by login pattern: gh's
    # reviews object exposes only the bare login (no is_bot flag), so we
    # match the known automation accounts that appear in this dotfiles +
    # tecpan corpus and the GitHub App suffix convention.
    local has_peer
    has_peer=$(printf '%s' "$out" | jq -r '
        [.[] | . as $pr | (.reviews // [])[] |
            select(.author.login != null) |
            select((.author.login | endswith("[bot]")) | not) |
            select((.author.login | startswith("copilot-")) | not) |
            select((.author.login | startswith("dependabot")) | not) |
            select((.author.login | startswith("renovate")) | not) |
            select((.author.login | startswith("github-actions")) | not) |
            select(.author.login != $pr.author.login) |
            .author.login] | length' 2>/dev/null || echo 0)
    if [ "${has_peer:-0}" -gt 0 ]; then
        printf 'multi-reviewer\n'
    else
        printf 'solo\n'
    fi
}

# Read repo-class from local file, if present. Empty output if no entry.
read_local_repo_class() {
    local repo="$1"
    [ ! -f "$LOCAL" ] && return 0
    require_pyyaml
    python3 - "$LOCAL" "$repo" <<'PY'
import sys, yaml
path, repo = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)
entry = (data.get('repos') or {}).get(repo)
if entry and entry.get('repo-class'):
    print(entry['repo-class'])
PY
}

write_local_repo_class() {
    local repo="$1"
    local value="$2"
    local today
    today=$(date +%Y-%m-%d)
    require_pyyaml
    python3 - "$LOCAL" "$repo" "$value" "$today" <<'PY'
import sys, yaml, os
path, repo, value, today = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        data = {}
data.setdefault('repos', {})
data['repos'][repo] = {'repo-class': value, 'last-confirmed': today}
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'w') as f:
    yaml.safe_dump(data, f, sort_keys=True)
PY
}

# --- subcommands ----------------------------------------------------------

if [ $# -lt 1 ]; then
    printf 'usage: %s <repo|defaults|repo-class|confirm-repo-class <value>|show>\n' "$(basename "$0")" >&2
    exit 2
fi

cmd="$1"; shift || true

case "$cmd" in
    repo)
        current_repo
        ;;
    defaults)
        [ -f "$DEFAULTS" ] || die "defaults file not found: $DEFAULTS"
        cat "$DEFAULTS"
        ;;
    repo-class)
        repo=$(current_repo) || exit $?
        existing=$(read_local_repo_class "$repo")
        if [ -n "$existing" ]; then
            printf '%s\n' "$existing"
            exit 0
        fi
        inferred=$(infer_repo_class)
        printf 'needs-confirmation:%s\n' "$inferred"
        exit 2
        ;;
    confirm-repo-class)
        [ $# -lt 1 ] && die "usage: confirm-repo-class <solo|multi-reviewer>"
        value="$1"
        case "$value" in
            solo|multi-reviewer) ;;
            *) die "repo-class must be 'solo' or 'multi-reviewer' (got: $value)" ;;
        esac
        repo=$(current_repo) || exit $?
        write_local_repo_class "$repo" "$value"
        printf 'confirmed: %s repo-class=%s\n' "$repo" "$value"
        ;;
    show)
        repo=$(current_repo) || exit $?
        [ -f "$DEFAULTS" ] || die "defaults file not found: $DEFAULTS"
        require_pyyaml
        local_class=$(read_local_repo_class "$repo")
        local_path=""
        [ -f "$LOCAL" ] && local_path="$LOCAL"
        python3 - "$DEFAULTS" "$local_path" "$repo" "$local_class" <<'PY'
import sys, yaml
defaults_path, local_path, repo, local_class = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(defaults_path) as f:
    defaults = yaml.safe_load(f) or {}
out = dict(defaults)
if local_path:
    with open(local_path) as f:
        local = yaml.safe_load(f) or {}
    # Top-level overrides per D-6 amendment: any scalar / list / dict key
    # at the local file's top level (except `repos`, which is per-repo
    # state, not a default override) wins over the tracked default.
    for key, value in local.items():
        if key == 'repos':
            continue
        out[key] = value
out['repo'] = repo
if local_class:
    out['repo-class'] = local_class
print(yaml.safe_dump(out, sort_keys=True), end='')
PY
        ;;
    *)
        printf 'pair-flow-config: unknown subcommand: %s\n' "$cmd" >&2
        exit 2
        ;;
esac
