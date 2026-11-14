#!/bin/bash
# The mission-control tier's own stores in scripts/policy-guard.sh: a literal
# path under a program home (resolved by scripts/mc-program.sh) is data that a
# mission-control session may write and read inside a substitution, while a
# settings file, a configuration overlay layer, CLAUDE.md and anything a link
# or a dot-dot component leads to stay refused, and no other tier gains an
# allowance.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"

FIXHOME="$SANDBOX/fixhome"
export HOME="$FIXHOME"
# The homes sit outside the harness scratch (/tmp/planwright-*), a data place
# where the guard already lets expanding targets through.
OUTSIDE=$(mktemp -d /var/tmp/pg-mc-store.XXXXXX) || exit 1
trap 'rm -rf "$SANDBOX" "$OUTSIDE"' EXIT
ROOT="$OUTSIDE/mchome"
H="$ROOT/tecpan"
OTHER="$OUTSIDE/elsewhere/beta-home"
FLEET="$FIXHOME/.claude/plugins/data/planwright/fleet"
MCLOG="$SANDBOX/mcprog.log"
mkdir -p "$H/kb/briefs" "$H/streamjson/w" "$OTHER/kb" "$FLEET/streamjson/w" \
  "$FIXHOME/.claude/plugins/data/planwright" "$UNIT/.claude/worktrees/flight-x/specs"
: >"$FIXHOME/.claude/settings.json"
: >"$FIXHOME/.claude/plugins/data/planwright/planwright.yml"
: >"$UNIT/CLAUDE.md"
: >"$H/kb/real.md"
ln -s "$FIXHOME/.claude/settings.json" "$H/kb/link-settings.md"
ln -s "$FIXHOME/.claude" "$H/kb/link-dir"
ln -s "$UNIT/CLAUDE.md" "$H/kb/link-claude.md"
ln -s "$FIXHOME/.claude/plugins/data/planwright/planwright.yml" "$H/kb/link-overlay.md"
printf '/some/cwd\n' >"$H/streamjson/w/cwd"
printf '/some/cwd\n' >"$FLEET/streamjson/w/cwd"

cat >"$S/mc-program.sh" <<EOS
#!/bin/sh
printf '%s\n' "\$*" >>"$MCLOG"
case "\$1 \$2 \$3" in
  "default home "*) printf '%s\n' "$ROOT" ;;
  "list  ") printf 'tecpan\nbeta\n' ;;
  "get beta home") printf '%s\n' "$OTHER" ;;
  "get tecpan home") printf '%s\n' "$H" ;;
  *) exit 2 ;;
esac
EOS
chmod +x "$S/mc-program.sh"
: >"$MCLOG"

# pg_file <tier> <tool> <path> — run the guard on a file-tool payload.
pg_file() {
  local payload
  payload=$(jq -n --arg t "$2" --arg p "$3" --arg w "$UNIT" \
    '{tool_name:$t, tool_input:{file_path:$p, content:"x"}, cwd:$w}')
  pg_payload "$1" file "$payload"
}

allow() { # <command> — defers at the mission-control tier
  pg mission-control "$1"
  expect defer "[mission-control] passes: ${1//$'\n'/ | }"
}
refuse() { # <command>
  pg mission-control "$1"
  expect deny "[mission-control] refused: ${1//$'\n'/ | }"
  reason_has 'settings or configuration file' "[mission-control] the refusal is the settings rule: ${1//$'\n'/ | }"
}

echo "# writes into a program home"
allow "cat >> $H/kb/brief-cp-task-1-r2.md <<'EOF'
note: the settings.json and .claude/settings.local.json files stay the operator's
EOF"
allow "cat >> $H/kb/briefs/README.md <<'EOF'
ready_flip_policy lives in planwright.local.yml
EOF"
allow "cat <<'EOF' >> $OTHER/kb/note.md
mentions CLAUDE.md and settings.json
EOF"
allow "cat >> $H/kb/brief.md <<'EOF'
planwright.yml
EOF
tail -1 $H/kb/brief.md"
allow "echo hi >> $H/kb/log.md"
allow "echo hi > $H/handover.md"

echo "# a compound brief write: scratch sed, a group with a heredoc, an append, a tail"
# shellcheck disable=SC2016 # the scratch directory is made by the command under test
SCR='D=$(mktemp -d)'
# shellcheck disable=SC2016 # the command text is the fixture
BODY=$SCR'; sed -n 1,5p '$H'/kb/real.md > "$D/seed.md"
{
  cat <<'"'EOF'"'
# a brief naming settings.json and CLAUDE.md
EOF
  cat "$D/seed.md"
} > '
TAIL="
echo '- brief-x' >> $H/kb/briefs/README.md
tail -3 $H/kb/briefs/README.md"
allow "$BODY$H/kb/briefs/brief-x.md$TAIL"
refuse "$BODY$FIXHOME/.claude/settings.json$TAIL"
refuse "$BODY$UNIT/CLAUDE.md$TAIL"
refuse "$BODY$H/kb/link-settings.md$TAIL"

echo "# plain reads inside a substitution"
allow "W=\$(cat $H/streamjson/w/cwd); git -C \"\$W\" status"
allow "echo \"\$(cat $H/kb/real.md)\""
allow "W=\$(cat $FLEET/streamjson/w/cwd); git -C \"\$W\" status"
allow "grep -c foo $UNIT/.claude/worktrees/flight-x/specs/a.md; echo \$(cat $FLEET/streamjson/w/cwd)"
# shellcheck disable=SC2016 # the loop is the command under test
allow 'for p in /proc/[0-9]*; do c=$(readlink "$p/cwd"); case "$c" in *"/.claude/worktrees/flight-x"*) echo "$p $c" ;; esac; done'

echo "# quoted text is data, not a write"
allow 'fleet-streamjson.sh answer --name w --deny --message "do not run echo x >> CLAUDE.md or cat >> settings.json; hand it to the operator"'
allow 'mc-kb.sh append --text "never append >> CLAUDE.md or planwright.local.yml"'

echo "# the same forms naming posture stay refused"
refuse "echo x >> $UNIT/CLAUDE.md"
refuse "echo x >> $UNIT/CLAUDE.local.md"
refuse "printf x >> $FIXHOME/.claude/CLAUDE.md"
refuse "tee -a $UNIT/CLAUDE.md"
refuse "cat >> $FIXHOME/.claude/settings.json <<'EOF'
x
EOF"
refuse "cat >> $UNIT/CLAUDE.md <<'EOF'
x
EOF"
refuse "cat >> $UNIT/.claude/planwright.local.yml <<'EOF'
x
EOF"
refuse "cat >> $FIXHOME/.claude/plugins/data/planwright/planwright.yml <<'EOF'
x
EOF"
refuse "cat >> $H/kb/../../../.claude/settings.json <<'EOF'
x
EOF"
refuse "cat >> $H/../.claude/settings.json <<'EOF'
settings.json
EOF"
refuse "W=\$(cat $FIXHOME/.claude/settings.json); echo \"\$W\""
refuse "W=\$(cat $H/kb/../../../.claude/settings.json); echo \"\$W\""
refuse "echo \$(cat $UNIT/.claude/worktrees/x/.claude/settings.json)"
refuse "echo \$(cat $FIXHOME/.claude/plugins/data/planwright/planwright.yml)"
refuse "echo \$(cat $FIXHOME/.claude/plugins/data/planwright/fleet/../planwright.yml)"
refuse "echo \$(cat $UNIT/CLAUDE.md); echo hi >> $UNIT/.claude/settings.json"
refuse "echo \$(cat $H/kb/x) >> $FIXHOME/.claude/settings.json"
refuse "cat <<EOF >> $H/kb/x.md
\$(echo hi >> $FIXHOME/.claude/settings.json)
EOF"

echo "# a link or a dot-dot component into posture stays refused"
for l in link-settings.md link-dir/settings.json link-claude.md link-overlay.md; do
  refuse "echo x >> $H/kb/$l"
  refuse "cat >> $H/kb/$l <<'EOF'
settings.json
EOF"
done
refuse "cp /dev/null $H/kb/link-settings.md"
refuse "echo x >> $H/kb/sub/../../../.claude/settings.json"
refuse "echo x >> $H/\$NAME"

echo "# a path no home resolves to earns nothing"
mkdir -p "$OUTSIDE/stray"
refuse "cat >> $OUTSIDE/stray/x.md <<'EOF'
settings.json
EOF"
refuse "W=\$(cat $OUTSIDE/stray/.claude/x); echo \$W"
refuse "cat >> $H/kb/brief.md <<EOF
settings.json \$(id)
EOF"

echo "# a stored or piped body is never run: the screen keeps the body in view"
EXEC="cat <<'EOF'
echo x > $FIXHOME/.claude/settings.json
EOF"
refuse "$EXEC | ash"
refuse "$EXEC | tclsh"
refuse "$EXEC | make -f -"
refuse "cat >> $H/kb/x.md <<'EOF'
echo x > $FIXHOME/.claude/settings.json
EOF
. $H/kb/x.md"
refuse "cat >> $H/kb/x.md <<'EOF'
echo x > $FIXHOME/.claude/settings.json
EOF
ash $H/kb/x.md"
refuse "cat >> $H/kb/x.md <<'EOF'
echo x > $FIXHOME/.claude/settings.json
EOF
echo \$(. $H/kb/x.md)"
refuse "cat >> $H/kb/x.md <<'EOF'
echo x > $FIXHOME/.claude/settings.json
EOF
cat $H/kb/x.md | ash"
refuse "cat >> $H/kb/x.md <<'EOF'
echo x > $FIXHOME/.claude/settings.json
EOF
BASH_ENV=$H/kb/x.md ls"
refuse "cat >> $H/kb/x.md <<'EOF'
settings.json
EOF
cat >| $H/kb/link-settings.md <<'EOF'
settings.json
EOF"
refuse "echo x >| $H/kb/link-settings.md"

echo "# instruction files: the file tools and a name inside a home"
pg_file mission-control Write "$UNIT/CLAUDE.md"
expect deny "[mission-control] the file tool refuses CLAUDE.md"
pg_file mission-control Edit "$FIXHOME/.claude/CLAUDE.local.md"
expect deny "[mission-control] the file tool refuses CLAUDE.local.md"
refuse "echo x >> $H/kb/CLAUDE.md"
allow "cat $UNIT/CLAUDE.md"
allow "echo \$(cat $H/kb/settings-notes.md)"

echo "# no other tier gains an allowance"
: >"$MCLOG"
for tier in worker tower; do
  pg "$tier" "cat >> $H/kb/x.md <<'EOF'
settings.json
EOF"
  expect defer "[$tier] a heredoc into a home path behaves as before"
  pg "$tier" "echo hi >> $FIXHOME/.claude/settings.json"
  expect defer "[$tier] the guard's settings screen is the mission-control tier's alone"
done
if [ -s "$MCLOG" ]; then
  fail "a tier other than mission-control read the program reader: $(head -3 "$MCLOG")"
else
  pass "no other tier reads the program reader"
fi

echo "# an unreadable program reader leaves no allowance"
rm -f "$S/mc-program.sh"
refuse "echo \$(cat $H/kb/settings-notes.md)"
refuse "cat >> $H/kb/brief.md <<'EOF'
settings.json
EOF"

finish
