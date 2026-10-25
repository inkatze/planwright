#!/bin/bash
# Pin-checks for the tower acceptance demo script (tower-front-door Task 13;
# REQ-A1.1, REQ-A1.2, REQ-D1.2, REQ-F1.1).
#
# The demo drives the five acceptance scenarios against a live tower; each
# scenario names its own eval persona and types that persona's lines as
# written, in order, so the eval harness's operator-run fallback and the demo
# stay one script; every live `[manual]` or `[Gherkin]` test-spec entry has
# exactly one checklist row, every row belongs to such an entry, and every
# entry that names the demo is checked off against a scenario the script
# drives, the one it names when it names one. Both screens are run against
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
# <scenario>:<the eval persona it types>
PERSONA_OF="chat-only:chat-only split-screen:split-screen refusal:refusal-merge escalation:escalation walk-away:walk-away"

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

# driven <doc>: the scenarios the doc drives, space-separated: a
# `## Scenario:` section holding at least one typed line.
driven() {
  for s in $SCENARIOS; do
    if [ -n "$(scenario_section "$1" "$s" | typed_lines)" ]; then
      printf '%s ' "$s"
    fi
  done
}

# persona_missing <typed lines> <persona file>: prints each of the persona's
# lines the typed lines do not contain in order (its @event lines stand for
# evidence the operator waits on, so they are not typed); a persona with no
# typed line at all is reported, never passed.
persona_missing() {
  want=$(sed -n 's/^answer\.\([0-9]*\)=/\1 /p' "$2" | sort -n | cut -d ' ' -f 2- | grep -v '^@event:')
  if [ -z "$want" ]; then
    printf '(the persona has no line to type)\n'
    return
  fi
  {
    printf '%s\n' "$1" | sed 's/^/G	/'
    printf '%s\n' "$want" | sed 's/^/W	/'
  } | awk -F '\t' '
    $1 == "G" { g[++ng] = $2; next }
    {
      found = 0
      while (p < ng) { p++; if (g[p] == $2) { found = 1; break } }
      if (!found) print $2
    }
  '
}

# spec_entries <test-spec>: one line per live `[manual]` or `[Gherkin]` entry:
# `<REQ>\t<names-the-demo: yes|no>\t<scenarios it names, space-separated>`.
# The tag is the heading's last bracket group; a superseded entry is not live.
spec_entries() {
  S="$SCENARIOS" awk '
    function flush() {
      if (req == "" || !live) return
      b = tolower(body)
      gsub(/`/, "", b)
      gsub(/[ \t\n]+/, " ", b)
      demo = (b ~ /(^|[^a-z])demos?([^a-z]|$)/) ? "yes" : "no"
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
      sub(/.*\[/, "", tag)
      sub(/\].*$/, "", tag)
      live = (tolower(tag) ~ /manual|gherkin/) && ($0 !~ /\(superseded/)
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
# manual or Gherkin entry has exactly one row, every row belongs to such an
# entry and names only driven scenarios (or says it is checked outside the
# demo), and every entry naming the demo is checked off against a driven
# scenario, the one it names when it names one.
xref() {
  {
    spec_entries "$1" | sed 's/^/E	/'
    checklist_rows "$2" | sed 's/^/R	/'
  } | D="$(driven "$2")" awk -F '\t' '
    BEGIN { n = split(ENVIRON["D"], d, " "); for (i = 1; i <= n; i++) drv[d[i]] = 1 }
    $1 == "E" { order[++ne] = $2; demo[$2] = $3; named[$2] = $4; next }
    $1 == "R" {
      if ($2 in row) { printf "%s: more than one checklist row\n", $2; next }
      row[$2] = $3
      rorder[++nr] = $2
    }
    END {
      for (i = 1; i <= nr; i++) {
        r = rorder[i]
        if (!(r in demo)) printf "%s: checklist row for no live manual or Gherkin entry\n", r
        if (row[r] == "outside the demo") continue
        m = split(row[r], s, /, */)
        for (j = 1; j <= m; j++)
          if (!(s[j] in drv)) printf "%s: checklist row names %s, which the demo does not drive\n", r, s[j]
      }
      for (i = 1; i <= ne; i++) {
        e = order[i]
        if (!(e in row)) { printf "%s: no checklist row\n", e; continue }
        if (demo[e] != "yes") continue
        if (row[e] == "outside the demo") { printf "%s: names the demo but its row says outside the demo\n", e; continue }
        split("", has)
        m = split(row[e], s, /, */)
        for (j = 1; j <= m; j++) has[s[j]] = 1
        k = split(named[e], t, " ")
        for (j = 1; j <= k; j++)
          if (!(t[j] in has)) printf "%s: names the %s demo but its row does not\n", e, t[j]
      }
    }
  '
}

# Screens refuse known-bad input before they are trusted.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/spec.md" <<'EOF'
# T

## REQ-A

### REQ-A1.1 — One [Gherkin + manual]

Scenario (the `chat-only` demo): a small ask lands a draft PR.

### REQ-A1.2 — Two [Manual]

Reviewed during the demo runs.

### REQ-A1.3 — Three [test]

Guard tests, no demo row needed.

### REQ-A1.4 — Four [manual] (superseded by REQ-A1.5)

The escalation demo, superseded.

### REQ-A1.5 — Five [test + manual]

Pins the demotion placements; a manual read of the newcomer path.

### REQ-A1.6 — The [bracketed] case [manual]

The escalation demos show it.
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
- [ ] REQ-A1.6 · escalation: the case is shown.
EOF
expect_problem() {
  case "$(xref "$tmp/spec.md" "$tmp/$2")" in
    *"$3"*) ok "$1" ;;
    *) fail "$1 (no '$3' reported)" ;;
  esac
}
if [ -z "$(xref "$tmp/spec.md" "$tmp/good.md")" ]; then ok "the cross-reference screen passes a complete checklist"; else fail "the cross-reference screen refused a complete checklist: $(xref "$tmp/spec.md" "$tmp/good.md")"; fi
sed '/REQ-A1.2 ·/d' "$tmp/good.md" >"$tmp/missing.md"
expect_problem "the screen refuses a live entry with no row (a capitalized tag)" missing.md "REQ-A1.2: no checklist row"
sed '/REQ-A1.6 ·/d' "$tmp/good.md" >"$tmp/missing-bracket.md"
expect_problem "the screen reads the tag from the heading's last bracket group" missing-bracket.md "REQ-A1.6: no checklist row"
sed 's/REQ-A1.1 · chat-only/REQ-A1.1 · escalation/' "$tmp/good.md" >"$tmp/wrong.md"
expect_problem "the screen refuses a row missing the scenario its entry names (a backticked name)" wrong.md "REQ-A1.1: names the chat-only demo but its row does not"
sed 's/REQ-A1.6 · escalation/REQ-A1.6 · chat-only/' "$tmp/good.md" >"$tmp/wrong-plural.md"
expect_problem "the screen reads a plural demos as naming the scenario" wrong-plural.md "REQ-A1.6: names the escalation demo but its row does not"
sed 's/REQ-A1.2 · chat-only, escalation/REQ-A1.2 · walk-away/' "$tmp/good.md" >"$tmp/phantom.md"
expect_problem "the screen refuses a row naming an undriven scenario" phantom.md "REQ-A1.2: checklist row names walk-away, which the demo does not drive"
sed 's/REQ-A1.2 · chat-only, escalation/REQ-A1.2 · outside the demo/' "$tmp/good.md" >"$tmp/outside.md"
expect_problem "the screen refuses a demo entry checked outside the demo" outside.md "REQ-A1.2: names the demo but its row says outside the demo"
# shellcheck disable=SC2016 # literal markdown backticks, never expanded
sed '/^\*\*Type:\*\* `change the auth check`$/d' "$tmp/good.md" >"$tmp/untyped.md"
expect_problem "a scenario with no typed line is not driven" untyped.md "names escalation, which the demo does not drive"
{
  cat "$tmp/good.md"
  printf -- '- [ ] REQ-A1.4 · outside the demo: superseded.\n'
} >"$tmp/stale.md"
expect_problem "the screen refuses a row for a superseded entry" stale.md "REQ-A1.4: checklist row for no live manual or Gherkin entry"
{
  cat "$tmp/good.md"
  printf -- '- [ ] REQ-A1.1 · escalation: twice.\n'
} >"$tmp/dup.md"
expect_problem "the screen refuses a second row for one entry" dup.md "REQ-A1.1: more than one checklist row"

printf 'answer.1=fix it\nanswer.2=@event:landed\nanswer.3=done\n' >"$tmp/p.persona"
printf 'answer.1=@event:landed\n' >"$tmp/events-only.persona"
printf 'turn.1=fix it\n' >"$tmp/renamed.persona"
if [ -z "$(persona_missing "$(printf 'fix it\nextra\ndone')" "$tmp/p.persona")" ]; then ok "the persona screen passes its lines in order, extras allowed"; else fail "the persona screen refused its lines in order"; fi
if [ "$(persona_missing "$(printf 'done\nfix it')" "$tmp/p.persona")" = "done" ]; then ok "the persona screen refuses its lines out of order"; else fail "the persona screen passed its lines out of order"; fi
for p in events-only renamed; do
  if [ -n "$(persona_missing "fix it" "$tmp/$p.persona")" ]; then ok "the persona screen refuses a persona with no line to type ($p)"; else fail "the persona screen passed a persona with no line to type ($p)"; fi
done

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
drv=$(driven "$DEMO")
if [ "$drv" = "$SCENARIOS " ]; then ok "every scenario types at least one line"; else fail "driven scenarios are '$drv', want '$SCENARIOS '"; fi

# Each scenario names its own eval persona and types its lines as written.
for pair in $PERSONA_OF; do
  s=${pair%%:*}
  want_persona=${pair#*:}
  sect=$(scenario_section "$DEMO" "$s")
  # shellcheck disable=SC2016 # literal markdown backticks, never expanded
  persona=$(printf '%s\n' "$sect" | sed -n 's/^Eval persona: `\([a-z-]*\)`$/\1/p')
  if [ "$persona" != "$want_persona" ]; then
    fail "$s names eval persona '$persona', want '$want_persona'"
    continue
  fi
  if [ ! -f "$PERSONAS/$persona.persona" ]; then
    fail "$s names eval persona $persona, which does not exist"
    continue
  fi
  missing=$(persona_missing "$(printf '%s\n' "$sect" | typed_lines)" "$PERSONAS/$persona.persona")
  if [ -z "$missing" ]; then ok "$s types the $persona persona's lines in order"; else fail "$s does not type, in order: $missing"; fi
done

# The checklist covers the test spec.
problems=$(xref "$TEST_SPEC" "$DEMO")
if [ -z "$problems" ]; then ok "every live manual or Gherkin entry is checked off against a driven scenario"; else fail "checklist cross-reference: $problems"; fi
entries=$(spec_entries "$TEST_SPEC")
demo_entries=$(printf '%s\n' "$entries" | awk -F '\t' '$2 == "yes"' | wc -l | tr -d ' ')
if [ "$demo_entries" -gt 0 ]; then ok "the test spec has entries naming the demo ($demo_entries)"; else fail "found no test-spec entry naming the demo; the parse matched nothing"; fi
named_entries=$(printf '%s\n' "$entries" | awk -F '\t' '$3 != ""' | wc -l | tr -d ' ')
if [ "$named_entries" -gt 0 ]; then ok "the test spec has entries naming a scenario ($named_entries)"; else fail "found no test-spec entry naming a scenario; the parse matched nothing"; fi

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all tower acceptance demo checks passed\n'
