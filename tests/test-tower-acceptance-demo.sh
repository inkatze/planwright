#!/bin/bash
# Pin-checks for the tower acceptance demo script (tower-front-door Task 13;
# REQ-A1.1, REQ-A1.2, REQ-D1.2, REQ-F1.1).
#
# The demo drives the five acceptance scenarios against a live tower; each
# scenario types its eval persona's lines as written, so the eval harness's
# operator-run fallback and the demo stay one script; every live `[manual]` or
# `[Gherkin]` test-spec entry has a checklist row, and every entry that names
# the demo is checked off against a scenario the script drives, the one it
# names when it names one. The cross-reference screen is run against
# known-bad fixtures first, so a screen that matches nothing cannot pass.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEMO="$REPO_ROOT/docs/tower-acceptance-demo.md"
TEST_SPEC="$REPO_ROOT/specs/tower-front-door/test-spec.md"
PERSONAS="$REPO_ROOT/tests/behavioral-evals/fixtures/tower/personas"
SCENARIOS="chat-only split-screen refusal escalation walk-away"

failures=0
ok() { printf 'ok: %s\n' "$1"; }
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

# scenario_section <doc> <name>: the body of `## Scenario: <name>`, up to the
# next `## ` heading.
scenario_section() {
  H="## Scenario: $2" awk '
    $0 == ENVIRON["H"] { on = 1; next }
    on && /^## / { exit }
    on { print }
  ' "$1"
}

# typed_lines: the backticked text of each `**Type:**` line on stdin.
typed_lines() {
  # shellcheck disable=SC2016 # literal markdown backticks, never expanded
  sed -n 's/^\*\*Type:\*\* `\(.*\)`$/\1/p'
}

# driven <doc>: the scenarios the doc drives, one per line: a `## Scenario:`
# section holding at least one typed line.
driven() {
  for s in $SCENARIOS; do
    if [ -n "$(scenario_section "$1" "$s" | typed_lines)" ]; then
      printf '%s\n' "$s"
    fi
  done
}

# spec_entries <test-spec>: one line per live `[manual]` or `[Gherkin]` entry:
# `<REQ>\t<names-the-demo: yes|no>\t<scenarios it names, space-separated>`.
# A superseded entry is not live.
spec_entries() {
  S="$SCENARIOS" awk '
    function flush() {
      if (req == "" || !live) return
      b = tolower(body)
      gsub(/[ \t\n]+/, " ", b)
      demo = (b ~ /(^|[^a-z])demo([^a-z]|$)/) ? "yes" : "no"
      named = ""
      n = split(ENVIRON["S"], sc, " ")
      for (i = 1; i <= n; i++)
        if (index(b, sc[i] " demo")) named = named (named == "" ? "" : " ") sc[i]
      printf "%s\t%s\t%s\n", req, demo, named
    }
    /^## / { flush(); req = ""; next }
    /^### REQ-/ {
      flush()
      req = $2
      tag = $0
      sub(/^[^[]*\[/, "", tag)
      sub(/\].*$/, "", tag)
      live = (tag ~ /manual|Gherkin/) && ($0 !~ /\(superseded/)
      body = ""
      next
    }
    req != "" { body = body "\n" $0 }
    END { flush() }
  ' "$1"
}

# checklist_rows <doc>: one line per checklist row, `<REQ>\t<scenario field>`,
# from rows shaped `- [ ] REQ-X1.1 · <scenarios>: <what to confirm>` under
# `## Checklist`.
checklist_rows() {
  awk '
    $0 == "## Checklist" { on = 1; next }
    on && /^## / { exit }
    on && /^- \[ \] REQ-[A-Z][0-9]+\.[0-9]+ · / {
      req = $4
      f = $0
      sub(/^- \[ \] REQ-[A-Z][0-9]+\.[0-9]+ · /, "", f)
      sub(/: .*$/, "", f)
      printf "%s\t%s\n", req, f
    }
  ' "$1"
}

# xref <test-spec> <doc>: prints one problem per line; silent when every live
# manual or Gherkin entry has a row, every row names only driven scenarios (or
# says it is checked outside the demo), and every entry naming the demo is
# checked off against a driven scenario, the one it names when it names one.
xref() {
  drv=" $(driven "$2" | tr '\n' ' ') "
  rows=$(checklist_rows "$2")
  printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r req field; do
    [ -n "$req" ] || continue
    [ "$field" = "outside the demo" ] && continue
    for s in $(printf '%s' "$field" | tr ',' ' '); do
      case "$drv" in
        *" $s "*) ;;
        *) printf '%s: checklist row names %s, which the demo does not drive\n' "$req" "$s" ;;
      esac
    done
  done
  spec_entries "$1" | while IFS="$(printf '\t')" read -r req demo named; do
    row=$(printf '%s\n' "$rows" | awk -F '\t' -v r="$req" '$1 == r { print $2; exit }')
    if [ -z "$row" ]; then
      printf '%s: no checklist row\n' "$req"
      continue
    fi
    [ "$demo" = yes ] || continue
    if [ "$row" = "outside the demo" ]; then
      printf '%s: names the demo but its row says outside the demo\n' "$req"
      continue
    fi
    for s in $named; do
      case " $(printf '%s' "$row" | tr ',' ' ') " in
        *" $s "*) ;;
        *) printf '%s: names the %s demo but its row does not\n' "$req" "$s" ;;
      esac
    done
  done
}

# Screens refuse known-bad input before they are trusted.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/spec.md" <<'EOF'
# T

## REQ-A

### REQ-A1.1 — One [Gherkin + manual]

Scenario (chat-only demo): a small ask lands a draft PR.

### REQ-A1.2 — Two [manual]

Reviewed during the demo runs.

### REQ-A1.3 — Three [test]

Guard tests, no demo row needed.

### REQ-A1.4 — Four [manual] (superseded by REQ-A1.5)

The escalation demo, superseded.

### REQ-A1.5 — Five [test + manual]

Pins the demotion placements; a manual read of the newcomer path.
EOF
cat >"$tmp/good.md" <<'EOF'
# Demo

## Scenario: chat-only

**Type:** `fix the typo`

## Scenario: escalation

**Type:** `change the auth check`

## Checklist

- [ ] REQ-A1.1 · chat-only: the PR link is the next interaction.
- [ ] REQ-A1.2 · chat-only, escalation: work offloads.
- [ ] REQ-A1.5 · outside the demo: read the newcomer path.
EOF
if [ -z "$(xref "$tmp/spec.md" "$tmp/good.md")" ]; then ok "the cross-reference screen passes a complete checklist"; else fail "the cross-reference screen refused a complete checklist: $(xref "$tmp/spec.md" "$tmp/good.md")"; fi
sed '/REQ-A1.2 ·/d' "$tmp/good.md" >"$tmp/missing.md"
case "$(xref "$tmp/spec.md" "$tmp/missing.md")" in
  *"REQ-A1.2: no checklist row"*) ok "the screen refuses a live entry with no row" ;;
  *) fail "the screen passed a live entry with no row" ;;
esac
sed 's/REQ-A1.1 · chat-only/REQ-A1.1 · escalation/' "$tmp/good.md" >"$tmp/wrong.md"
case "$(xref "$tmp/spec.md" "$tmp/wrong.md")" in
  *"REQ-A1.1: names the chat-only demo but its row does not"*) ok "the screen refuses a row missing the scenario its entry names" ;;
  *) fail "the screen passed a row missing the scenario its entry names" ;;
esac
sed 's/REQ-A1.2 · chat-only, escalation/REQ-A1.2 · walk-away/' "$tmp/good.md" >"$tmp/phantom.md"
case "$(xref "$tmp/spec.md" "$tmp/phantom.md")" in
  *"REQ-A1.2: checklist row names walk-away, which the demo does not drive"*) ok "the screen refuses a row naming an undriven scenario" ;;
  *) fail "the screen passed a row naming an undriven scenario" ;;
esac
sed 's/REQ-A1.2 · chat-only, escalation/REQ-A1.2 · outside the demo/' "$tmp/good.md" >"$tmp/outside.md"
case "$(xref "$tmp/spec.md" "$tmp/outside.md")" in
  *"REQ-A1.2: names the demo but its row says outside the demo"*) ok "the screen refuses a demo entry checked outside the demo" ;;
  *) fail "the screen passed a demo entry checked outside the demo" ;;
esac
# shellcheck disable=SC2016 # literal markdown backticks, never expanded
sed '/^\*\*Type:\*\* `change the auth check`$/d' "$tmp/good.md" >"$tmp/untyped.md"
case "$(xref "$tmp/spec.md" "$tmp/untyped.md")" in
  *"names escalation, which the demo does not drive"*) ok "a scenario with no typed line is not driven" ;;
  *) fail "a scenario with no typed line counted as driven" ;;
esac

for f in "$DEMO" "$TEST_SPEC"; do
  if [ ! -f "$f" ]; then
    printf 'FAIL: missing %s\n' "$f" >&2
    exit 1
  fi
done

# The demo drives all five acceptance scenarios.
for s in $SCENARIOS; do
  n=$(grep -c -x "## Scenario: $s" "$DEMO")
  if [ "$n" -eq 1 ]; then ok "the demo has one $s scenario"; else fail "the demo has $n '## Scenario: $s' headings, want 1"; fi
done
drv=$(driven "$DEMO" | tr '\n' ' ')
if [ "$drv" = "$SCENARIOS " ]; then ok "every scenario types at least one line"; else fail "driven scenarios are '$drv', want '$SCENARIOS '"; fi

# Each scenario types its eval persona's lines as written, in order; the
# persona's @event lines stand for evidence the operator waits on instead.
for s in $SCENARIOS; do
  sect=$(scenario_section "$DEMO" "$s")
  # shellcheck disable=SC2016 # literal markdown backticks, never expanded
  persona=$(printf '%s\n' "$sect" | sed -n 's/^Eval persona: `\([a-z-]*\)`$/\1/p')
  if [ -z "$persona" ] || [ ! -f "$PERSONAS/$persona.persona" ]; then
    fail "$s names no eval persona that exists ('$persona')"
    continue
  fi
  want=$(sed -n 's/^answer\.\([0-9]*\)=/\1 /p' "$PERSONAS/$persona.persona" | sort -n | cut -d ' ' -f 2- | grep -v '^@event:')
  got=$(printf '%s\n' "$sect" | typed_lines)
  missing=$(
    printf '%s\n' "$want" | {
      rest=$got
      while IFS= read -r line; do
        found=0
        remaining=""
        while IFS= read -r g; do
          if [ "$found" -eq 1 ]; then
            remaining="$remaining$g
"
          elif [ "$g" = "$line" ]; then
            found=1
          fi
        done <<EOF
$rest
EOF
        if [ "$found" -eq 1 ]; then rest=$remaining; else printf '%s\n' "$line"; fi
      done
    }
  )
  if [ -z "$missing" ]; then ok "$s types the $persona persona's lines in order"; else fail "$s does not type, in order: $missing"; fi
done

# The checklist covers the test spec.
problems=$(xref "$TEST_SPEC" "$DEMO")
if [ -z "$problems" ]; then ok "every live manual or Gherkin entry is checked off against a driven scenario"; else fail "checklist cross-reference: $problems"; fi
demo_entries=$(spec_entries "$TEST_SPEC" | awk -F '\t' '$2 == "yes"' | wc -l | tr -d ' ')
if [ "$demo_entries" -gt 0 ]; then ok "the test spec has entries naming the demo ($demo_entries)"; else fail "found no test-spec entry naming the demo; the parse matched nothing"; fi

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all tower acceptance demo checks passed\n'
