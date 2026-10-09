#!/bin/bash
# Tests for scripts/flight-dispatch.sh's paths and its brief sweep, the second
# half of tests/test-flight-dispatch.sh's suite (the fixture,
# tests/lib/flight-dispatch-fixture.sh, says why it is split).
#
# Properties verified:
#   9b. A repo root or fleet home whose path, canonical or given, would break
#       the TAB-separated report or the brief path is refused before the lock
#       and the mint; a print launch that cannot be built ends the report on a
#       failed line; the brief directory and the fleet home must be private to
#       their owner; invisible and bidi-control code points are stripped from
#       the ask and the grounds until stable, and flagged, with the size cap
#       read from the copy; the grounds file is read as a file whatever its
#       name; an unreadable worktree list after a failed placement keeps the
#       brief and reports the worktree unknown.
#   9c. `retire`, and every dispatch, removes the brief directories of this
#       checkout's retired flights only, past a grace and once no dispatch is
#       placing them, keyed on the worktree path; it fails closed on a busy
#       lock, an unreadable worktree list, or an unsafe flights directory.
#   10. The report names an installed worker root, its version, and any skew,
#       with escape text in a version kept inert; CRLF grounds are one line.
#   11. A dispatch from a linked worktree reads the primary's config and
#       places the flight beside the primary.
#   12. A spec root outside the checkout refuses a file home before anything
#       is minted or placed.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
unset CDPATH
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib/flight-dispatch-fixture.sh
. "$here/lib/flight-dispatch-fixture.sh"

# --- 9b. report paths, the grounds read, an unreadable worktree list ---------
# A path carrying a control byte would break the TAB-separated report: it is
# refused before anything is placed.
new_case
git clone -q "$c/origin.git" "$c/pri${TAB}mary" 2>/dev/null
run dispatch readme-typo --backend print --ask-file "$c/ask.txt" --grounds-file "$c/grounds.txt" \
  --repo-root "$c/pri${TAB}mary"
[ "$RC" -eq 2 ] || fail "a repo root carrying a control byte must be refused (rc $RC: $ERR)"
case $ERR in *"control"*) ;; *) fail "the control-byte refusal must say why: $ERR" ;; esac
PLANWRIGHT_FLEET_STATE_DIR="$c/fl${TAB}eet" run dispatch readme-typo --backend print \
  --ask-file "$c/ask.txt" --grounds-file "$c/grounds.txt" --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "a fleet home carrying a control byte must be refused (rc $RC: $ERR)"
case $ERR in *"fleet home"*"control"*) ;; *) fail "the fleet-home control-byte refusal must say why: $ERR" ;; esac
git clone -q "$c/origin.git" "$c/pri
mary" 2>/dev/null
run dispatch readme-typo --backend print --ask-file "$c/ask.txt" --grounds-file "$c/grounds.txt" \
  --repo-root "$c/pri
mary"
[ "$RC" -eq 2 ] || fail "a repo root carrying a newline must be refused (rc $RC: $ERR)"
run retire --repo-root "$c/pri${TAB}mary"
[ "$RC" -eq 2 ] || fail "retire must refuse a repo root carrying a control byte (rc $RC)"
PLANWRIGHT_FLEET_STATE_DIR="$c/fl${TAB}eet" run retire --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "retire must refuse a fleet home carrying a control byte (rc $RC)"
[ "$(flight_branches)" -eq 0 ] || fail "a control-byte path placed a flight branch"
[ ! -e "$c/fl${TAB}eet/flights" ] || fail "a control-byte fleet home received a brief"

# The fleet home is screened at its canonical path, the one the brief uses,
# and before the lock and the mint: a busy lock would otherwise answer first.
new_case
mkdir -p "$c/fl${TAB}eet"
ln -s "$c/fl${TAB}eet" "$c/fleet-ctl"
PLANWRIGHT_FLEET_STATE_DIR="$c/fleet-ctl" run dispatch readme-typo --backend print \
  --ask-file "$c/ask.txt" --grounds-file "$c/grounds.txt" --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "a fleet home whose canonical path carries a control byte must be refused (rc $RC: $ERR)"
case $ERR in *"fleet home"*"control"*) ;; *) fail "the canonical control-byte refusal must say why: $ERR" ;; esac
PLANWRIGHT_FLEET_STATE_DIR="$c/fleet-ctl" run retire --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "retire must refuse a fleet home whose canonical path carries a control byte (rc $RC)"
[ -z "$(ls -A "$c/fl${TAB}eet")" ] || fail "a control-byte canonical fleet home received a brief"
lockhome="$c/primary/.git/planwright-flight"
PLANWRIGHT_FLEET_STATE_DIR=$lockhome "$STATE" lock || fail "fixture: could not take the flight lock"
mkdir -p "$c/fl eet"
PLANWRIGHT_FLIGHT_LOCK_WAIT=0 PLANWRIGHT_FLEET_STATE_DIR="$c/fl eet" run dispatch readme-typo --backend tmux \
  --ask-file "$c/ask.txt" --grounds-file "$c/grounds.txt" --repo-root "$c/primary" --attach-dry-run
[ "$RC" -eq 2 ] || fail "a fleet home outside the brief path charset must be refused before the lock (rc $RC: $ERR)"
case $ERR in *"charset"*) ;; *) fail "the brief-charset refusal must say why: $ERR" ;; esac
mkdir -p "$c/fleet"
chmod 775 "$c/fleet"
PLANWRIGHT_FLIGHT_LOCK_WAIT=0 run dispatch readme-typo --backend print \
  --ask-file "$c/ask.txt" --grounds-file "$c/grounds.txt" --repo-root "$c/primary"
[ "$RC" -eq 4 ] || fail "a group-writable fleet home must be refused before the lock (rc $RC: $ERR)"
case $ERR in *"chmod go-w"*) ;; *) fail "the group-writable fleet-home refusal must name chmod go-w: $ERR" ;; esac
case $ERR in *"holds this checkout's lock"*) fail "the fleet-home refusal must come before the lock: $ERR" ;; esac
PLANWRIGHT_FLIGHT_LOCK_WAIT=0 run retire --repo-root "$c/primary"
[ "$RC" -eq 4 ] || fail "retire must refuse a group-writable fleet home (rc $RC)"
case $ERR in *"chmod go-w"*) ;; *) fail "retire must refuse a group-writable fleet home first, naming chmod go-w: $ERR" ;; esac
chmod 700 "$c/fleet"
PLANWRIGHT_FLEET_STATE_DIR=$lockhome "$STATE" unlock
[ "$(flight_branches)" -eq 0 ] || fail "an early fleet-home refusal placed a flight branch"

# A print launch that cannot be built ends the report on a failed line.
elroot="$tmp/elroot"
mkdir -p "$elroot"
cp -R "$ROOT/scripts" "$ROOT/skills" "$ROOT/config" "$ROOT/doctrine" "$ROOT/.claude-plugin" "$elroot/"
printf '#!/bin/sh\nexit 1\n' >"$elroot/scripts/fleet-dispatch-env.sh"
new_case
OUT=$("$elroot/scripts/flight-dispatch.sh" dispatch readme-typo --backend print --ask-file "$c/ask.txt" \
  --grounds-file "$c/grounds.txt" --repo-root "$c/primary" </dev/null 2>"$tmp/err")
RC=$?
[ "$RC" -eq 5 ] || fail "a print launch that cannot be built must exit 5 (rc $RC: $(cat "$tmp/err"))"
case $(cat "$tmp/err") in *"could not construct the pinned print launch"*) ;; *) fail "the launch failure must be the one reported: $(cat "$tmp/err")" ;; esac
[ "$(printf '%s\n' "$OUT" | tail -n 2 | head -n 1 | cut -f1)" = failed ] \
  || fail "the failed print launch's failed line must follow the report it cut short (out: $OUT)"
[ "$(printf '%s\n' "$OUT" | grep -c "^failed${TAB}")" -eq 1 ] \
  || fail "a print launch that cannot be built must report one failed line (out: $OUT)"
case $(field "$OUT" reask) in *"holds a slot"*) ;; *) fail "the failed print launch must say the placed worktree holds a slot (out: $OUT)" ;; esac
[ -z "$(field "$OUT" launch)" ] || fail "a failed print launch must report no launch line"

# The brief directory is checked before the brief is written: a symlinked
# flights directory, or one group or others can write, is refused, and so is
# a fleet home others can write.
new_case
mkdir -p "$c/fleet" "$c/redirected"
ln -s "$c/redirected" "$c/fleet/flights"
dispatch_print
[ "$RC" -eq 4 ] || fail "a symlinked flights directory must be refused (rc $RC: $ERR)"
case $ERR in *"is a symlink"*) ;; *) fail "the symlinked flights refusal must say why: $ERR" ;; esac
[ -z "$(ls -A "$c/redirected")" ] || fail "a brief was written through a symlinked flights directory"
rm "$c/fleet/flights"
mkdir -p "$c/fleet/flights"
chmod 777 "$c/fleet/flights"
dispatch_print
[ "$RC" -eq 4 ] || fail "a world-writable flights directory must be refused (rc $RC: $ERR)"
case $ERR in *"flights is not a directory owned by you"*) ;; *) fail "the writable flights refusal must say why: $ERR" ;; esac
for m in 770 702; do
  chmod "$m" "$c/fleet/flights"
  dispatch_print
  [ "$RC" -eq 4 ] || fail "a flights directory at mode $m must be refused (rc $RC: $ERR)"
done
chmod 700 "$c/fleet/flights"
chmod 777 "$c/fleet"
dispatch_print
[ "$RC" -eq 4 ] || fail "a world-writable fleet home must be refused (rc $RC: $ERR)"
case $ERR in *"the fleet home is not a directory owned by you"*) ;; *) fail "the writable fleet-home refusal must say why: $ERR" ;; esac
chmod 755 "$c/fleet"
[ "$(flight_branches)" -eq 0 ] || fail "a refused brief directory placed a flight branch"
[ "$(briefs)" -eq 0 ] || fail "a refused brief directory left a brief"
dispatch_print
[ "$RC" -eq 0 ] || fail "a private flights directory must be accepted (rc $RC: $ERR)"
bdir=$(dirname "$(field "$OUT" brief)")
[ -n "$(find "$bdir" -maxdepth 0 ! -perm -0001 ! -perm -0002 ! -perm -0004 ! -perm -0010 ! -perm -0020 ! -perm -0040 2>/dev/null)" ] \
  || fail "the brief directory must be private to its owner"

# Invisible and bidi-control code points are stripped from the ask and the
# grounds before either reaches the brief, and the strip is flagged; ordinary
# UTF-8 (an accent, an em dash sharing the bidi controls' lead bytes) stays.
new_case
invis_codes='\302\255 \330\234 \341\240\216 \342\200\213 \342\200\214 \342\200\215 \342\200\217 \342\200\250 \342\200\251 \342\200\255 \342\200\256 \342\201\240 \342\201\244 \342\201\246 \342\201\251 \342\201\252 \342\201\257 \357\273\277 \363\240\200\201 \363\240\201\201 \363\240\201\277 \357\270\200 \357\270\217 \363\240\204\200 \363\240\206\277 \363\240\207\200 \363\240\207\257 \357\277\271 \357\277\273 \341\205\237 \341\205\240 \343\205\244 \357\276\240 \341\236\264 \341\236\265 \302\205'
invis=''
for b in $invis_codes; do
  # shellcheck disable=SC2059 # each octal escape is the format
  invis="$invis$(printf "$b")"
done
# Each range's outside neighbour, which must survive.
keep=$(printf '\342\200\220\342\200\247\342\200\257\342\201\245\342\201\260\341\240\215\357\270\220\363\240\207\260\357\277\270\357\277\274\341\205\236\341\205\241\343\205\243\357\276\241\341\236\263\341\236\266')
printf 'Fix the caf\303\251 heading \342\200\224 %sreversed%s now. %s\n' "$invis" "$invis" "$keep" >"$c/ask-u.txt"
run dispatch readme-typo --backend print --ask-file "$c/ask-u.txt" \
  --grounds-file "$(grounds "visual flight: one ${invis}wording change")" --repo-root "$c/primary"
[ "$RC" -eq 0 ] || fail "an ask carrying invisible Unicode must be sanitized, not refused (rc $RC: $ERR)"
ubrief=$(field "$OUT" brief)
[ -f "$ubrief" ] || fail "the sanitized dispatch reported no brief (out: $OUT)"
for b in $invis_codes; do
  # shellcheck disable=SC2059 # each octal escape is the format
  ! grep -q "$(printf "$b")" "$ubrief" 2>/dev/null || fail "the brief kept an invisible or bidi code point ($b)"
done
grep -q "$(printf 'caf\303\251 heading \342\200\224 reversed now. ')$keep" "$ubrief" 2>/dev/null \
  || fail "sanitizing the ask must keep ordinary UTF-8, the ranges' neighbours included"
grep -q '^> visual flight: one wording change$' "$ubrief" 2>/dev/null || fail "the grounds must reach the brief sanitized"
grep -q 'were stripped from the ask at dispatch' "$ubrief" 2>/dev/null || fail "the brief must note the ask was sanitized"
printf '%s\n' "$OUT" | grep -q "^sanitized${TAB}ask$" || fail "a sanitized ask must be flagged in the report (out: $OUT)"
printf '%s\n' "$OUT" | grep -q "^sanitized${TAB}grounds$" || fail "sanitized grounds must be flagged in the report"
case $ERR in *"invisible or bidi"*) ;; *) fail "the strip must be flagged on stderr: $ERR" ;; esac
dispatch_print
case $OUT in *"sanitized${TAB}"*) fail "a clean ask must not be flagged as sanitized" ;; esac
! grep -q 'were stripped' "$(field "$OUT" brief)" || fail "a clean ask's brief must carry no strip note"
run dispatch readme-typo --backend print --ask-file "$c/ask-u.txt" --grounds-file "$c/grounds.txt" \
  --repo-root "$c/primary"
printf '%s\n' "$OUT" | grep -q "^sanitized${TAB}ask$" || fail "a dirty ask must be flagged (out: $OUT)"
! printf '%s\n' "$OUT" | grep -q "^sanitized${TAB}grounds$" || fail "clean grounds must not be flagged (out: $OUT)"
gitc "$c/primary" worktree remove --force "$(field "$OUT" worktree)"
run dispatch readme-typo --backend print --ask-file "$c/ask.txt" \
  --grounds-file "$(grounds "visual flight: ${invis}grounds only")" --repo-root "$c/primary"
printf '%s\n' "$OUT" | grep -q "^sanitized${TAB}grounds$" || fail "dirty grounds must be flagged (out: $OUT)"
! printf '%s\n' "$OUT" | grep -q "^sanitized${TAB}ask$" || fail "a clean ask must not be flagged (out: $OUT)"
gitc "$c/primary" worktree remove --force "$(field "$OUT" worktree)"
run dispatch readme-typo --backend print --ask-file "$c/ask.txt" \
  --grounds-file "$(grounds "$(printf '\342\200\213\342\200\213')")" --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "grounds that are empty once stripped must be refused (rc $RC)"
case $ERR in *"empty once invisible"*) ;; *) fail "the emptied grounds refusal must say why: $ERR" ;; esac

# The strip runs until the text is stable, so a code point split around
# another, or around a control byte, cannot survive it; the flag reads the
# same pipeline the brief does.
new_case
zw=$(printf '\342\200\213')
printf 'nested \342\200\342\200\213\213 and \342\200\001\213 split\n' >"$c/ask-n.txt"
run dispatch readme-typo --backend print --ask-file "$c/ask-n.txt" --grounds-file "$c/grounds.txt" \
  --repo-root "$c/primary"
[ "$RC" -eq 0 ] || fail "a nested invisible code point must be sanitized, not refused (rc $RC: $ERR)"
! grep -q "$zw" "$(field "$OUT" brief)" 2>/dev/null || fail "a code point nested inside a broken one survived the strip"
grep -q '^> nested  and  split$' "$(field "$OUT" brief)" 2>/dev/null || fail "the nested strip must keep the text around it"
printf '%s\n' "$OUT" | grep -q "^sanitized${TAB}ask$" || fail "a nested strip must be flagged (out: $OUT)"
gitc "$c/primary" worktree remove --force "$(field "$OUT" worktree)"
printf 'only \342\200\001\213 here\n' >"$c/ask-n.txt"
run dispatch readme-typo --backend print --ask-file "$c/ask-n.txt" --grounds-file "$c/grounds.txt" \
  --repo-root "$c/primary"
[ "$RC" -eq 0 ] && [ -f "$(field "$OUT" brief)" ] || fail "a control-split code point must be sanitized (rc $RC: $ERR)"
! grep -q "$zw" "$(field "$OUT" brief)" 2>/dev/null || fail "a code point joined by the control-byte drop survived"
printf '%s\n' "$OUT" | grep -q "^sanitized${TAB}ask$" \
  || fail "a code point the control-byte drop joined must be flagged (out: $OUT)"
gitc "$c/primary" worktree remove --force "$(field "$OUT" worktree)"
printf 'no final newline \342\200\213' >"$c/ask-n.txt"
run dispatch readme-typo --backend print --ask-file "$c/ask-n.txt" --grounds-file "$c/grounds.txt" \
  --repo-root "$c/primary"
[ "$RC" -eq 0 ] || fail "an ask without a final newline must dispatch (rc $RC: $ERR)"
grep -q '^> no final newline $' "$(field "$OUT" brief)" 2>/dev/null || fail "an ask without a final newline must reach the brief"
gitc "$c/primary" worktree remove --force "$(field "$OUT" worktree)"
printf 'no final newline, clean' >"$c/ask-n.txt"
run dispatch readme-typo --backend print --ask-file "$c/ask-n.txt" --grounds-file "$c/grounds.txt" \
  --repo-root "$c/primary"
[ "$RC" -eq 0 ] || fail "a clean ask without a final newline must dispatch (rc $RC: $ERR)"
gitc "$c/primary" worktree remove --force "$(field "$OUT" worktree)"
# The size cap reads the copy: one byte over is refused, the cap itself is not.
head -c 65537 /dev/zero | tr '\0' 'a' >"$c/ask-n.txt"
run dispatch readme-typo --backend print --ask-file "$c/ask-n.txt" --grounds-file "$c/grounds.txt" \
  --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "an ask one byte over the cap must be refused (rc $RC)"
case $ERR in *"larger than"*) ;; *) fail "the over-cap refusal must say why: $ERR" ;; esac
head -c 65536 /dev/zero | tr '\0' 'a' >"$c/ask-n.txt"
run dispatch readme-typo --backend print --ask-file "$c/ask-n.txt" --grounds-file "$c/grounds.txt" \
  --repo-root "$c/primary"
[ "$RC" -eq 0 ] || fail "an ask at exactly the cap must dispatch (rc $RC: $ERR)"
case $OUT in *"sanitized${TAB}"*) fail "a clean ask without a final newline must not be flagged (out: $OUT)" ;; esac
# An ask that is nothing but hidden characters is refused, as the grounds are.
printf '\342\200\213\342\200\213\n' >"$c/ask-n.txt"
run dispatch readme-typo --backend print --ask-file "$c/ask-n.txt" --grounds-file "$c/grounds.txt" \
  --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "an ask that is empty once stripped must be refused (rc $RC)"
case $ERR in *"ask is empty once invisible"*) ;; *) fail "the emptied-ask refusal must say why: $ERR" ;; esac
# A whitespace-only ask is refused too: the record could never quote it.
printf '  \n\t\n' >"$c/ask-w.txt"
run dispatch readme-typo --backend print --ask-file "$c/ask-w.txt" --grounds-file "$c/grounds.txt" \
  --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "a whitespace-only ask must be refused (rc $RC)"
case $ERR in *"ask is blank"*) ;; *) fail "the blank-ask refusal must say why: $ERR" ;; esac
printf '   \n' >"$c/g-blank.txt"
run dispatch readme-typo --backend print --ask-file "$c/ask.txt" --grounds-file "$c/g-blank.txt" \
  --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "whitespace-only grounds must be refused (rc $RC)"
printf ' \342\200\213 \n' >"$c/g-hidden.txt"
run dispatch readme-typo --backend print --ask-file "$c/ask.txt" --grounds-file "$c/g-hidden.txt" \
  --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "grounds blank once stripped must be refused (rc $RC)"
# The ask is read once, so a file changed mid-dispatch cannot slip past the
# size cap or the flag.
# shellcheck disable=SC2016 # a literal redirect from the variable is the pattern
[ "$(grep -v '^[[:space:]]*#' "$SCRIPT" | grep -c '<"$ask_file"')" -eq 1 ] \
  || fail "flight-dispatch.sh must read the ask file exactly once"
# shellcheck disable=SC2016
[ "$(grep -v '^[[:space:]]*#' "$SCRIPT" | grep -c '<"$grounds_file"')" -eq 1 ] \
  || fail "flight-dispatch.sh must read the grounds file exactly once"

# A grounds file named like an option is read as a file, never as `cat`'s
# option or stdin.
new_case
printf 'visual flight: grounds from a dash-named file\n' >"$c/-n"
OUT=$(cd "$c" && "$SCRIPT" dispatch readme-typo --backend print --ask-file "$c/ask.txt" \
  --grounds-file -n --repo-root "$c/primary" </dev/null 2>"$tmp/err")
RC=$?
[ "$RC" -eq 0 ] || fail "a grounds file named -n must be read as a file (rc $RC: $(cat "$tmp/err"))"
[ "$RC" -ne 0 ] || grep -q 'grounds from a dash-named file' "$(field "$OUT" brief)" \
  || fail "the brief must carry the grounds read from the file named -n"

# A worktree list that fails after a failed placement is not "no worktree":
# the brief stays and the worktree state is reported unknown.
wlroot="$tmp/wlroot"
mkdir -p "$wlroot"
cp -R "$ROOT/scripts" "$ROOT/skills" "$ROOT/config" "$ROOT/doctrine" "$ROOT/.claude-plugin" "$wlroot/"
cat >"$wlroot/scripts/fleet-dispatch-worktree.sh" <<'EOF'
#!/bin/sh
: >"$WTLIST_FAIL_FLAG"
echo "stub: placement failed" >&2
exit 5
EOF
new_case
OUT=$(WTLIST_FAIL_FLAG="$c/wl.flag" PATH="$tmp/wlbin:$PATH" "$wlroot/scripts/flight-dispatch.sh" dispatch \
  readme-typo --backend print --ask-file "$c/ask.txt" --grounds-file "$c/grounds.txt" \
  --repo-root "$c/primary" </dev/null 2>"$tmp/err")
RC=$?
[ "$RC" -eq 5 ] || fail "a failed placement with an unreadable worktree list must exit 5 (rc $RC: $(cat "$tmp/err"))"
[ "$(field "$OUT" worktree)" = unknown ] || fail "an unreadable worktree list must report the worktree unknown (out: $OUT)"
[ -n "$(field "$OUT" brief)" ] && [ -f "$(field "$OUT" brief)" ] \
  || fail "an unreadable worktree list must keep and report the brief (out: $OUT)"
case $(field "$OUT" reask) in *"could not be read"*) ;; *) fail "an unknown worktree state must say the list could not be read (out: $OUT)" ;; esac
[ -s "$c/wl.flag.log" ] || fail "fixture: the unreadable-list path was never taken"

# --- 9c. a retired flight's brief directory is cleaned -----------------------
# A flight retires when its worktree is removed. `retire`, and every dispatch,
# removes the brief directories of this checkout's retired flights, and only
# those: a live flight's brief, another checkout's, and anything when the
# worktree list cannot be read all stay.
new_case
dispatch_print
fa=$(field "$OUT" flight)
dispatch_print
fb=$(field "$OUT" flight)
[ -n "$(awk -F "$TAB" -v w="print-flight-$fa" '$1 == w' "$c/fleet/attention/state" 2>/dev/null)" ] \
  || fail "fixture: the dispatch must leave the flight's lifecycle row for retire to clear"
mkdir -p "$c/fleet/flights/other-0123abcd"
printf '%s\n' "$c/elsewhere" >"$c/fleet/flights/other-0123abcd/checkout"
gitc "$c/primary" worktree remove --force "$c/primary/.claude/worktrees/flight-$fa"
age "$c/fleet/flights/$fa" "$c/fleet/flights/other-0123abcd"
WTLIST_FAIL_FLAG="$c/wl.flag"
: >"$WTLIST_FAIL_FLAG"
OUT=$(WTLIST_FAIL_FLAG="$WTLIST_FAIL_FLAG" PATH="$tmp/wlbin:$PATH" "$SCRIPT" retire --repo-root "$c/primary" </dev/null 2>"$tmp/err")
RC=$?
[ "$RC" -eq 4 ] || fail "retire with an unreadable worktree list must fail closed with exit 4 (rc $RC)"
case $(cat "$tmp/err") in *"cannot list worktrees"*) ;; *) fail "retire's unreadable-list refusal must say why: $(cat "$tmp/err")" ;; esac
[ -d "$c/fleet/flights/$fa" ] || fail "retire removed a brief while the worktree list was unreadable"
rm -f "$WTLIST_FAIL_FLAG"
run retire --repo-root "$c/primary"
[ "$RC" -eq 0 ] || fail "retire exited $RC: $ERR"
[ ! -e "$c/fleet/flights/$fa" ] || fail "retire must remove a retired flight's brief directory"
printf '%s\n' "$OUT" | grep -q "^retired${TAB}$fa$" || fail "retire must report what it removed (out: $OUT)"
[ -z "$(awk -F "$TAB" -v w="print-flight-$fa" '$1 == w' "$c/fleet/attention/state" 2>/dev/null)" ] \
  || fail "retire must clear a retired flight's lifecycle row from the attention store"
[ -f "$c/fleet/flights/$fb/brief.md" ] || fail "retire must keep a live flight's brief"
[ -d "$c/fleet/flights/other-0123abcd" ] || fail "retire must keep another checkout's brief directory"
# No checkout record, a symlinked one, or an off-grammar name: never swept.
mkdir -p "$c/fleet/flights/nock-0123abcd" "$c/fleet/flights/lnk-0123abcd" "$c/fleet/flights/NotAnId"
printf '%s\n' "$c/primary" >"$c/ck"
ln -s "$c/ck" "$c/fleet/flights/lnk-0123abcd/checkout"
printf '%s\n' "$c/primary" >"$c/fleet/flights/NotAnId/checkout"
age "$c/fleet/flights/nock-0123abcd" "$c/fleet/flights/lnk-0123abcd" "$c/fleet/flights/NotAnId"
run retire --repo-root "$c/primary"
for d in nock-0123abcd lnk-0123abcd NotAnId; do
  [ -d "$c/fleet/flights/$d" ] || fail "retire must keep $d (no checkout record, a symlinked one, or an off-grammar name)"
done
# A worktree deleted by hand (prunable) is retired too.
rm -rf "$c/primary/.claude/worktrees/flight-$fb"
age "$c/fleet/flights/$fb"
chmod 500 "$c/fleet/attention"
run retire --repo-root "$c/primary"
chmod 700 "$c/fleet/attention"
if [ "$RC" -eq 0 ] || ! printf '%s\n' "$ERR" | grep -q "could not clear the attention row"; then
  fail "a lifecycle row retire could not clear must fail the retire, not pass silently (rc $RC: $ERR)"
fi
# The brief stays until its row is cleared, so the next retire retries it.
[ -f "$c/fleet/flights/$fb/brief.md" ] || fail "a retire whose row clear failed must keep the brief for the next retire"
printf '%s\n' "$OUT" | grep -q "^retired${TAB}$fb$" && fail "a retire whose row clear failed must not report the flight retired (out: $OUT)"
run retire --repo-root "$c/primary"
[ "$RC" -eq 0 ] || fail "the retry retire exited $RC: $ERR"
printf '%s\n' "$OUT" | grep -q "^retired${TAB}$fb$" || fail "retire must retire a prunable flight (out: $OUT)"
[ -z "$(awk -F "$TAB" -v w="print-flight-$fb" '$1 == w' "$c/fleet/attention/state" 2>/dev/null)" ] \
  || fail "the retry retire must clear the row the failed one left"
gitc "$c/primary" worktree prune
dispatch_print
fb=$(field "$OUT" flight)
# A busy checkout lock fails closed and removes nothing.
lockhome="$c/primary/.git/planwright-flight"
PLANWRIGHT_FLEET_STATE_DIR=$lockhome "$STATE" lock || fail "fixture: could not take the flight lock"
gitc "$c/primary" worktree remove --force "$c/primary/.claude/worktrees/flight-$fb"
age "$c/fleet/flights/$fb"
PLANWRIGHT_FLIGHT_LOCK_WAIT=0 run retire --repo-root "$c/primary"
[ "$RC" -eq 4 ] || fail "retire under a busy lock must fail closed with exit 4 (rc $RC)"
case $ERR in *"holds this checkout's lock"*) ;; *) fail "retire's busy-lock refusal must say why: $ERR" ;; esac
[ -d "$c/fleet/flights/$fb" ] || fail "retire under a busy lock removed a brief"
# Where no brief names the checkout there is nothing to retire, so retire
# answers without touching the lock, busy or not.
(umask 077 && mkdir -p "$c/fleet-unflown/flights/other-0123abcd")
printf '%s\n' "$c/elsewhere" >"$c/fleet-unflown/flights/other-0123abcd/checkout"
PLANWRIGHT_FLEET_STATE_DIR="$c/fleet-unflown" PLANWRIGHT_FLIGHT_LOCK_WAIT=0 run retire --repo-root "$c/primary"
[ "$RC" -eq 0 ] && [ -z "$OUT" ] \
  || fail "retire where no brief names the checkout must exit 0 without the lock (rc $RC: $ERR)"
PLANWRIGHT_FLEET_STATE_DIR=$lockhome "$STATE" unlock
dispatch_print
[ "$RC" -eq 0 ] || fail "dispatch after a retirement exited $RC: $ERR"
[ ! -e "$c/fleet/flights/$fb" ] || fail "a dispatch must clean a retired flight's brief directory"
printf '%s\n' "$OUT" | grep -q "^retired${TAB}$fb$" || fail "a dispatch must report the brief it swept (out: $OUT)"

# A retired flight's brief younger than the sweep's grace stays: a lock an
# operator cleared by hand could otherwise let a sweep take a concurrent
# dispatch's just-written brief.
new_case
dispatch_print
fy=$(field "$OUT" flight)
gitc "$c/primary" worktree remove --force "$c/primary/.claude/worktrees/flight-$fy"
run retire --repo-root "$c/primary"
[ "$RC" -eq 0 ] || fail "retire with a young retired brief exited $RC: $ERR"
[ -d "$c/fleet/flights/$fy" ] || fail "retire must keep a retired brief younger than the grace"
age "$c/fleet/flights/$fy"
run retire --repo-root "$c/primary"
[ ! -e "$c/fleet/flights/$fy" ] || fail "retire must remove the same brief once it is past the grace"

# A brief its dispatch is still placing stays however old it is: the marker
# names the placing process, and only that process being gone frees the brief.
# A dispatch held up past the grace is not a retired flight.
dispatch_print
fp=$(field "$OUT" flight)
gitc "$c/primary" worktree remove --force "$c/primary/.claude/worktrees/flight-$fp"
printf '%s\n' "$$" >"$c/fleet/flights/$fp/placing"
age "$c/fleet/flights/$fp"
run retire --repo-root "$c/primary"
[ "$RC" -eq 0 ] || fail "retire with a brief still being placed exited $RC: $ERR"
[ -d "$c/fleet/flights/$fp" ] || fail "retire must keep a brief whose dispatch is still placing it, past the grace"
printf '%s\n' 999999999 >"$c/fleet/flights/$fp/placing"
run retire --repo-root "$c/primary"
[ ! -e "$c/fleet/flights/$fp" ] || fail "retire must remove a brief whose placing dispatch is gone"

# An age check that fails keeps the brief.
dispatch_print
fy=$(field "$OUT" flight)
gitc "$c/primary" worktree remove --force "$c/primary/.claude/worktrees/flight-$fy"
real_find=$(command -v find)
mkdir -p "$tmp/findbin"
cat >"$tmp/findbin/find" <<EOF
#!/bin/sh
for a in "\$@"; do
  [ "\$a" != -mmin ] || { echo refused >>"$tmp/find.log"; exit 1; }
done
exec '$real_find' "\$@"
EOF
chmod +x "$tmp/findbin/find"
printf 'flight_pr_hosts: [github.com]\n' >"$c/adopter/planwright.yml"
age "$c/fleet/flights/$fy"
PATH="$tmp/findbin:$PATH" run retire --repo-root "$c/primary"
[ -s "$tmp/find.log" ] || fail "fixture: the failing age check was never reached"
[ -d "$c/fleet/flights/$fy" ] || fail "a brief whose age check failed must be kept"

# A flight worktree switched onto a retired flight's branch still keeps its
# own brief: the path and the branch each name a live flight.
new_case
dispatch_print
fa=$(field "$OUT" flight)
dispatch_print
fb=$(field "$OUT" flight)
gitc "$c/primary" worktree remove --force "$c/primary/.claude/worktrees/flight-$fb"
git -C "$c/primary/.claude/worktrees/flight-$fa" switch -q "planwright/flight/$fb"
age "$c/fleet/flights/$fa"
run retire --repo-root "$c/primary"
[ "$RC" -eq 0 ] || fail "retire with a switched flight exited $RC: $ERR"
[ -d "$c/fleet/flights/$fa" ] || fail "a flight switched onto another flight's branch lost its own brief"

# Liveness keys on the worktree path, not the branch: a detached or
# mid-rebase flight keeps its brief and its slot.
new_case
mkdir -p "$c/primary/.claude"
printf 'max_parallel_units: 1\n' >"$c/primary/.claude/planwright.local.yml"
dispatch_print
fd=$(field "$OUT" flight)
git -C "$c/primary/.claude/worktrees/flight-$fd" checkout -q --detach
age "$c/fleet/flights/$fd"
run retire --repo-root "$c/primary"
[ "$RC" -eq 0 ] || fail "retire beside a detached flight exited $RC: $ERR"
[ -d "$c/fleet/flights/$fd" ] || fail "retire must keep a detached flight's brief"
dispatch_print
[ "$RC" -eq 3 ] || fail "a detached flight must still hold its slot (rc $RC: $OUT)"

# The sweep checks the flights directory before deleting anything under it,
# refuses a name carrying a newline, and reports what it could not do.
new_case
dispatch_print
fr=$(field "$OUT" flight)
gitc "$c/primary" worktree remove --force "$c/primary/.claude/worktrees/flight-$fr"
age "$c/fleet/flights/$fr"
chmod 777 "$c/fleet/flights"
run retire --repo-root "$c/primary"
[ "$RC" -eq 4 ] || fail "retire must refuse a flights directory others can write (rc $RC)"
case $ERR in *"chmod go-w"*) ;; *) fail "the writable flights refusal must name the remedy: $ERR" ;; esac
[ -d "$c/fleet/flights/$fr" ] || fail "retire deleted under a flights directory others can write"
chmod 700 "$c/fleet/flights"
mkdir "$c/fleet/flights/x
$fr"
run retire --repo-root "$c/primary"
[ "$RC" -eq 4 ] || fail "retire must refuse an entry name carrying a newline (rc $RC)"
case $ERR in *"newline"*) ;; *) fail "the newline refusal must say why: $ERR" ;; esac
[ -d "$c/fleet/flights/$fr" ] || fail "retire deleted a brief beside a newline-named entry"
rmdir "$c/fleet/flights/x
$fr"
chmod 300 "$c/fleet/flights"
run retire --repo-root "$c/primary"
[ "$RC" -eq 4 ] || fail "retire must fail when the flights directory cannot be listed (rc $RC)"
case $ERR in *"cannot list"*) ;; *) fail "the unlistable flights refusal must say why: $ERR" ;; esac
chmod 700 "$c/fleet/flights"
chmod 500 "$c/fleet/flights/$fr"
run retire --repo-root "$c/primary"
[ "$RC" -eq 4 ] || fail "retire must fail when a retired brief cannot be removed (rc $RC)"
case $ERR in *"could not remove"*"$fr"*) ;; *) fail "a failed removal must be named: $ERR" ;; esac
chmod 700 "$c/fleet/flights/$fr"
age "$c/fleet/flights/$fr"
run retire --repo-root "$c/primary"
[ "$RC" -eq 0 ] && [ ! -e "$c/fleet/flights/$fr" ] || fail "retire must remove the brief once it can (rc $RC: $ERR)"

# --- plugin-root pair with an installed plugin -------------------------------
tower_v=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/.claude-plugin/plugin.json" | head -n 1)
for want in same skewed; do
  new_case
  if [ "$want" = same ]; then v=$tower_v; else v=0.0.1-skew; fi
  inst="$c/claude/plugins/cache/mk/planwright/$v"
  mkdir -p "$inst/.claude-plugin"
  printf '{"name":"planwright","version":"%s"}\n' "$v" >"$inst/.claude-plugin/plugin.json"
  dispatch_print
  printf '%s\n' "$OUT" | grep -q "^root${TAB}worker${TAB}$inst${TAB}$v$" \
    || fail "report must name the installed worker root and version (out: $OUT)"
  grep -q "at dispatch: \`$inst\`" "$(field "$OUT" brief)" || fail "the brief must name the worker's resolved root"
  if [ "$want" = same ]; then
    [ "$(field "$OUT" root-skew)" = no ] || fail "equal versions must read no skew"
  else
    [ "$(field "$OUT" root-skew)" = yes ] || fail "differing versions must read skew yes"
  fi
done

# A version string carrying escape TEXT must not become a live escape in the
# report: /bin/sh's echo expands backslash sequences.
new_case
inst="$c/claude/plugins/cache/mk/planwright/9.9.9"
mkdir -p "$inst/.claude-plugin"
printf '{"name":"planwright","version":"9.9\\033[31m"}\n' >"$inst/.claude-plugin/plugin.json"
dispatch_print
[ "$RC" -eq 0 ] || fail "escape-text version fixture did not dispatch (rc $RC: $ERR)"
case $OUT in *"$ESC"*) fail "escape text in a plugin version became a live escape in the report" ;; esac

# CRLF grounds are one line: the line ending is not a control character.
new_case
printf 'Fix the typo in the README heading.\n' >"$c/ask.txt"
printf 'visual flight: a CRLF line\r\n' >"$c/g-crlf.txt"
run dispatch readme-typo --backend print --ask-file "$c/ask.txt" --grounds-file "$c/g-crlf.txt" \
  --repo-root "$c/primary"
[ "$RC" -eq 0 ] || fail "CRLF grounds are one line and must be accepted (rc $RC: $ERR)"
case $(cat "$(field "$OUT" brief)") in *"$(printf '\r')"*) fail "a CRLF grounds line must reach the brief without its CR" ;; esac

# --- dispatch from a linked worktree ------------------------------------------
# The primary's config layers govern, and the flight is placed beside the
# primary, never nested in the worktree it was dispatched from.
new_case
gitc "$c/primary" worktree add -q --detach "$c/primary/.claude/worktrees/tower"
twt="$c/primary/.claude/worktrees/tower"
mkdir -p "$c/primary/.claude"
printf 'max_parallel_units: 0\n' >"$c/primary/.claude/planwright.local.yml"
run dispatch readme-typo --backend print --ask-file "$c/ask.txt" \
  --grounds-file "$c/grounds.txt" --repo-root "$twt"
[ "$RC" -eq 3 ] || fail "a worktree dispatch must read the primary's max_parallel_units 0 (rc $RC: $ERR)"
printf 'max_parallel_units: 2\n' >"$c/primary/.claude/planwright.local.yml"
run dispatch readme-typo --backend print --ask-file "$c/ask.txt" \
  --grounds-file "$c/grounds.txt" --repo-root "$twt"
[ "$RC" -eq 0 ] || fail "a worktree dispatch under the primary's bound exited $RC: $ERR"
wfid=$(field "$OUT" flight)
primary_phys=$(cd "$c/primary" && pwd -P)
[ "$(field "$OUT" worktree)" = "$primary_phys/.claude/worktrees/flight-$wfid" ] \
  || fail "a worktree dispatch placed the flight at '$(field "$OUT" worktree)', not under the primary"
echo "ok: a flight dispatched from a linked worktree reads the primary's config and lands beside it"

# --- a spec root outside the checkout ------------------------------------------
# A file-home record is committed on the flight's branch, so it cannot live in
# a spec root outside the checkout. When the PR home is unavailable too, the
# refusal says so, and comes before anything is minted or placed.
new_case
oroot="$c/outside-specs"
mkdir -p "$oroot" "$c/primary/.claude"
printf 'project: fixture\nlayout: 1\n' >"$oroot/planwright-spec-root.yml"
printf 'spec_root: %s\n' "$oroot" >"$c/primary/.claude/planwright.local.yml"
GH_STUB_AUTH=1 run dispatch readme-typo --backend print --ask-file "$c/ask.txt" \
  --grounds-file "$c/grounds.txt" --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "a file-home dispatch with the spec root outside the checkout must be refused (rc $RC: $ERR)"
case $ERR in
  *"outside this checkout"*"gh is not authenticated to github.com"*) ;;
  *) fail "the outside-root refusal must name why the PR home is unavailable too: $ERR" ;;
esac
[ "$(flight_branches)" -eq 0 ] || fail "an outside-root refusal must mint no flight branch"
[ "$(briefs)" -eq 0 ] || fail "an outside-root refusal must leave no brief"
run dispatch readme-typo --backend print --ask-file "$c/ask.txt" \
  --grounds-file "$c/grounds.txt" --home file --repo-root "$c/primary"
[ "$RC" -eq 2 ] || fail "--home file with the spec root outside the checkout must be refused (rc $RC: $ERR)"
case $ERR in *"outside this checkout"*) ;; *) fail "the --home file outside-root refusal must say why: $ERR" ;; esac
[ "$(flight_branches)" -eq 0 ] || fail "an outside-root --home file refusal must mint no flight branch"
run dispatch readme-typo --backend print --ask-file "$c/ask.txt" \
  --grounds-file "$c/grounds.txt" --repo-root "$c/primary"
[ "$RC" -eq 0 ] && [ "$(field "$OUT" home)" = pr ] \
  || fail "with the PR home available, an outside-root dispatch must take it (rc $RC, home $(field "$OUT" home): $ERR)"
echo "ok: a spec root outside the checkout refuses a file home before placing anything"

finish test-flight-dispatch-paths
