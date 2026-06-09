#!/usr/bin/env bash
# tasks-pr-sync.sh — PostToolUse hook. Updates the matching spec's tasks.md
# when the user (or any skill) runs `gh pr create` or `gh pr merge` for a
# pair-flow branch. Wired from roles/osx/files/claude/settings.json under
# hooks.PostToolUse with matcher "Bash" (see specs/pair-flow Task 4, REQ-E1.1,
# REQ-E1.2, REQ-E3.1, D-9).
#
# The hook is intentionally silent on no-op cases (wrong tool, non-matching
# command, branch not in D-32 format, no matching task block). Diagnostics go
# to stderr so Claude Code surfaces them without confusing the LLM.

set -euo pipefail

log() { printf 'tasks-pr-sync: %s\n' "$*" >&2; }

input=$(cat || true)
[ -n "$input" ] || exit 0

if ! command -v jq >/dev/null 2>&1; then
    log "jq missing; skipping"
    exit 0
fi

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || printf '')
[ "$tool" = "Bash" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || printf '')
out=$(printf '%s' "$input" | jq -r '.tool_response.stdout // empty' 2>/dev/null || printf '')
[ -n "$cmd" ] || exit 0

# Match an actual `gh pr create` / `gh pr merge` invocation (at command start
# or after a shell separator), not a mere substring mention. PostToolUse fires
# after every Bash call, so a loose substring match (e.g. an echo/grep that
# quotes the string) would rewrite tasks.md on unrelated commands.
gh_pr() { printf '%s' "$cmd" | grep -qE "(^|[;&|(]|&&|\\|\\|)[[:space:]]*gh[[:space:]]+pr[[:space:]]+$1([[:space:]]|\$)"; }
if gh_pr create; then
    action="open"
elif gh_pr merge; then
    action="merge"
else
    exit 0
fi

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

spec=""
ids=""
case "$branch" in
    pair-flow/*/task-*)
        rest="${branch#pair-flow/}"
        spec="${rest%%/*}"
        ids="${rest#*/task-}"
        ;;
    *)
        exit 0
        ;;
esac

[ -n "$spec" ] && [ -n "$ids" ] || exit 0

tasks_md="$repo_root/specs/$spec/tasks.md"
if [ ! -f "$tasks_md" ]; then
    log "no tasks.md at $tasks_md; skipping"
    exit 0
fi

pr_url=$(printf '%s' "$out" | grep -oE 'https://github\.com/[^/[:space:]]+/[^/[:space:]]+/pull/[0-9]+' | head -1 || printf '')
pr_num=""
if [ -n "$pr_url" ]; then
    pr_num="${pr_url##*/}"
fi
# Fallback 1: extract #NUMBER from response stdout (gh pr merge prints "merged pull request #N").
if [ -z "$pr_num" ]; then
    pr_num=$(printf '%s' "$out" | grep -oE '#[0-9]+' | head -1 | tr -d '#' || printf '')
fi
# Fallback 2: parse explicit number arg from the command (e.g., `gh pr merge 42`).
if [ -z "$pr_num" ]; then
    pr_num=$(printf '%s' "$cmd" | grep -oE 'gh pr (create|merge)[[:space:]]+[0-9]+([[:space:]]|$)' | grep -oE '[0-9]+' | head -1 || printf '')
fi
# Fallback 3: ask gh for the current branch's PR.
if [ -z "$pr_num" ] && command -v gh >/dev/null 2>&1; then
    pr_num=$(gh pr view --json number --jq .number 2>/dev/null || printf '')
fi
if [ -z "$pr_url" ] && [ -n "$pr_num" ] && command -v gh >/dev/null 2>&1; then
    pr_url=$(gh pr view "$pr_num" --json url --jq .url 2>/dev/null || printf '')
fi
if [ -z "$pr_num" ]; then
    log "could not determine PR number; skipping update"
    exit 0
fi

today=$(date -u +%Y-%m-%d)
ids_csv=$(printf '%s' "$ids" | tr '-' ',')

if ! command -v python3 >/dev/null 2>&1; then
    log "python3 missing; skipping"
    exit 0
fi

python3 - "$tasks_md" "$action" "$pr_num" "$pr_url" "$today" "$ids_csv" <<'PY' || log "python helper failed; tasks.md unchanged"
import re
import sys
from pathlib import Path

tasks_md, action, pr_num, pr_url, today, ids_csv = sys.argv[1:]
ids = [i.strip() for i in ids_csv.split(',') if i.strip()]
if not ids:
    sys.exit(0)

path = Path(tasks_md)
content = path.read_text()
lines = content.splitlines(keepends=True)

H2 = re.compile(r'^## (.+?)\s*$')
H3 = re.compile(r'^### (.+?)\s*$')
TASK_HEADER = re.compile(r'^### Task (\S+) — (.+?)\s*$')


def index_sections():
    out = {}
    name = None
    start = None
    for i, line in enumerate(lines):
        m = H2.match(line)
        if m:
            if name is not None:
                out[name] = (start, i)
            name = m.group(1).strip()
            start = i
    if name is not None:
        out[name] = (start, len(lines))
    return out


def find_task(task_id):
    pat = re.compile(rf'^### Task {re.escape(task_id)} —')
    for i, line in enumerate(lines):
        if pat.match(line):
            end = len(lines)
            for j in range(i + 1, len(lines)):
                if H2.match(lines[j]) or H3.match(lines[j]):
                    end = j
                    break
            section = None
            for sname, (s_start, s_end) in index_sections().items():
                if s_start < i < s_end:
                    section = sname
                    break
            return i, end, section
    return None


def strip_existing_status_lines(block):
    out = []
    for ln in block:
        if re.match(r'^[-*] \*\*(?:Status|Last activity):\*\*', ln.lstrip()):
            continue
        out.append(ln)
    return out


def insert_into_section(section_name, payload):
    sections = index_sections()
    if section_name in sections:
        s_start, _ = sections[section_name]
        insert_at = s_start + 1
        # Skip the blank line right after the header.
        while insert_at < len(lines) and lines[insert_at].strip() == "":
            insert_at += 1
        # If a "(none yet)" placeholder is present, replace it.
        if insert_at < len(lines) and lines[insert_at].strip() == "(none yet)":
            del lines[insert_at]
            # Also drop a trailing blank if any.
            if insert_at < len(lines) and lines[insert_at].strip() == "":
                del lines[insert_at]
        lines[insert_at:insert_at] = payload
    else:
        # Create the section after Forward plan (or at file end).
        target = None
        for i, ln in enumerate(lines):
            if H2.match(ln) and ln.strip() == "## Forward plan":
                # Find end of Forward plan section.
                for j in range(i + 1, len(lines)):
                    if H2.match(lines[j]):
                        target = j
                        break
                if target is None:
                    target = len(lines)
                break
        if target is None:
            target = len(lines)
        lines[target:target] = [f"## {section_name}\n", "\n"] + payload + ["\n"]


for tid in reversed(ids):
    found = find_task(tid)
    if not found:
        continue
    start, end, _section = found
    block = lines[start:end]
    title_match = TASK_HEADER.match(block[0])
    title_text = title_match.group(2) if title_match else f"Task {tid}"

    if action == "open":
        block = strip_existing_status_lines(block)
        # Insert annotation lines right after the H3 header.
        annotation = [
            f"\n- **Status:** PR #{pr_num} draft\n",
            f"- **Last activity:** {today}\n",
        ]
        # Trim any leading blank line in the block so the annotation reads cleanly.
        if len(block) > 1 and block[1].strip() == "":
            new_block = [block[0]] + annotation + block[2:]
        else:
            new_block = [block[0]] + annotation + block[1:]
        del lines[start:end]
        # Refresh: insert into "In progress".
        if not new_block[-1].endswith("\n"):
            new_block[-1] += "\n"
        if new_block[-1].strip() != "":
            new_block.append("\n")
        insert_into_section("In progress", new_block)
    elif action == "merge":
        del lines[start:end]
        if pr_url:
            bullet = (
                f"- **Task {tid} — {title_text}.** Completed in PR #{pr_num} "
                f"({pr_url}). See PR description for details.\n"
            )
        else:
            bullet = (
                f"- **Task {tid} — {title_text}.** Completed in PR #{pr_num}. "
                f"See PR description for details.\n"
            )
        insert_into_section("Completed", [bullet, "\n"])

path.write_text("".join(lines))
PY
