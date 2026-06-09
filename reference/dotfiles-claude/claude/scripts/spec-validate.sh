#!/usr/bin/env bash
# Structural validator for spec bundles.
#
# Checks the four-file bundle format and the per-task structural requirements
# from D-15/D-45 in specs/pair-flow/design.md. Status-aware: Draft status
# emits warnings (exit 0); Active status emits errors (exit 1).
#
# Usage: spec-validate.sh <path-to-spec-bundle>
#
# This is the mechanical structural pass, not the deep semantic validator.
# Semantic validation lives in tecpan/specs/VALIDATING.md as a paste-into-
# agent prompt; the two are complementary.
#
# Compatible with bash 3.2 (macOS default) and BSD awk.

set -u

# --- argument and path ----------------------------------------------------

if [ $# -lt 1 ]; then
    printf 'usage: %s <path-to-spec-bundle>\n' "$(basename "$0")" >&2
    exit 2
fi

bundle="$1"

if [ ! -d "$bundle" ]; then
    printf 'spec-validate: %s is not a directory\n' "$bundle" >&2
    exit 2
fi

bundle="${bundle%/}"

errors=0
warnings=0
status=""

hard_error() {
    printf '[ERROR] %s: %s\n' "$1" "$2"
    errors=$((errors + 1))
}

# --- four-file presence check --------------------------------------------

for f in requirements.md design.md tasks.md test-spec.md; do
    if [ ! -f "$bundle/$f" ]; then
        hard_error "$bundle" "missing required file: $f"
    fi
done

if [ "$errors" -gt 0 ]; then
    printf '\nspec-validate: %d error(s), %d warning(s)\n' "$errors" "$warnings"
    exit 1
fi

# --- status detection ----------------------------------------------------

status_line=$(grep -E '^(\*\*Status:\*\*|Status:) +(Draft|Active|Done)([[:space:]]|$)' "$bundle/requirements.md" | head -n 1 || true)

if [ -z "$status_line" ]; then
    # Treat missing Status as Draft. Per D-33, /orchestrate refuses to act
    # on non-Active specs anyway, so a missing declaration is recoverable.
    # Warn so the gap is visible during authoring.
    printf '[WARN]  requirements.md: missing Status: declaration (defaulting to Draft; expected one of: Draft, Active, Done)\n'
    warnings=$((warnings + 1))
    status="Draft"
else
    status=$(printf '%s' "$status_line" | sed -E 's/.*(Draft|Active|Done).*/\1/')
fi

printf 'spec-validate: %s (status: %s)\n' "$bundle" "$status"

# --- per-task structural checks (delegated to awk) -----------------------
#
# awk produces a finding per missing field plus a task-count line. Output
# format from awk:
#   F\tLINE\tLEVEL\tMSG     -- per-finding (LEVEL = ERROR or WARN)
#   COUNT\tN                -- task count
#
# We pass STATUS in via -v so awk can choose ERROR vs WARN per finding.

tasks_md="$bundle/tasks.md"

awk_output=$(awk -v status="$status" '
function emit_finding(line, msg,    level) {
    level = (status == "Active") ? "ERROR" : "WARN"
    # tab-separated for easy bash parsing
    printf "F\t%d\t%s\t%s\n", line, level, msg
}
function check_task(    msg) {
    if (current_heading == "") return
    # Stable ID check.
    if (current_heading !~ /^### (Task )?[0-9]+(\.[0-9]+)?([^[:alnum:]_]|$)/ && \
        current_heading !~ /^### (Task )?[0-9]+(\.[0-9]+)?[[:space:]]/ && \
        current_heading !~ /^### (Task )?[0-9]+(\.[0-9]+)?\./) {
        emit_finding(current_line, "task heading lacks a stable numeric ID: " current_heading)
    }
    if (current_body !~ /\*\*Done when:\*\*/) {
        emit_finding(current_line, "task missing `Done when:` field: " current_heading)
    }
    if (current_body !~ /\*\*Dependencies:\*\*/) {
        emit_finding(current_line, "task missing `Dependencies:` field: " current_heading)
    }
    if (current_body !~ /\*\*Citations:\*\*/) {
        emit_finding(current_line, "task missing `Citations:` field: " current_heading)
    }
    task_count++
}
BEGIN {
    in_section = 0
    current_heading = ""
    current_line = 0
    current_body = ""
    task_count = 0
}
/^## / {
    check_task(); current_heading = ""; current_body = ""
    if ($0 ~ /^## (Task order|Forward plan|Forward Plan|Plan)$/) {
        in_section = 1
    } else {
        in_section = 0
    }
    next
}
/^### / {
    if (in_section) {
        check_task()
        current_heading = $0
        current_line = NR
        current_body = ""
    }
    next
}
{
    if (in_section && current_heading != "") {
        current_body = current_body "\n" $0
    }
}
END {
    check_task()
    printf "COUNT\t%d\n", task_count
}
' "$tasks_md")

# Parse awk output line by line.
task_count=0
while IFS=$'\t' read -r kind a b c; do
    case "$kind" in
        F)
            level="$b"
            line="$a"
            msg="$c"
            if [ "$level" = "ERROR" ]; then
                printf '[ERROR] tasks.md:%s: %s\n' "$line" "$msg"
                errors=$((errors + 1))
            else
                printf '[WARN]  tasks.md:%s: %s\n' "$line" "$msg"
                warnings=$((warnings + 1))
            fi
            ;;
        COUNT)
            task_count="$a"
            ;;
    esac
done <<< "$awk_output"

if [ "$task_count" -eq 0 ]; then
    if [ "$status" = "Active" ]; then
        printf '[ERROR] tasks.md: no tasks found under "## Task order" or "## Forward plan"\n'
        errors=$((errors + 1))
    else
        printf '[WARN]  tasks.md: no tasks found under "## Task order" or "## Forward plan"\n'
        warnings=$((warnings + 1))
    fi
fi

# --- requirements.md REQ-ID convention check -----------------------------
#
# Per the tecpan README, REQs use stable IDs like REQ-A1.2. When the spec
# uses prose REQs ("- The system shall ...") without any REQ-IDs, that is
# the org/ counter-example pattern.

req_with_id=$(grep -cE 'REQ-[A-Z]+[0-9]+(\.[0-9]+)*' "$bundle/requirements.md" || true)
req_prose=$(grep -cE '^[-*]\s+The (system|module|service) (shall|must) ' "$bundle/requirements.md" || true)

if [ "$req_with_id" -eq 0 ] && [ "$req_prose" -gt 0 ]; then
    msg="REQs are prose-only (no REQ-ID convention). Found $req_prose prose REQs; D-15 expects REQ-IDs"
    if [ "$status" = "Active" ]; then
        printf '[ERROR] requirements.md: %s\n' "$msg"
        errors=$((errors + 1))
    else
        printf '[WARN]  requirements.md: %s\n' "$msg"
        warnings=$((warnings + 1))
    fi
fi

# --- tasks.md section completeness (warn only, never error) --------------
#
# Section presence is a convention, not load-bearing for orchestration.

if ! grep -qE '^## Completed([[:space:]]|$)' "$tasks_md"; then
    printf '[WARN]  tasks.md: missing section "## Completed"\n'
    warnings=$((warnings + 1))
fi

# --- summary -------------------------------------------------------------

printf '\nspec-validate: %d error(s), %d warning(s)\n' "$errors" "$warnings"

if [ "$errors" -gt 0 ]; then
    exit 1
fi
exit 0
