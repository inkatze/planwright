# turn-shape-grade.jq — the turn-shape invariants over a run's decision log
# (operator-dialogue REQ-M1.1, D-19). Driven by scripts/turn-shape-grade.sh,
# which owns the thresholds' presence and the expected-failure comparison.
#
# Input: the decision log as one array. Args: $cfg (the fixture's thresholds
# and invariant list), $artifacts (name, bytes, and table count of every file
# the run wrote besides the log and the run record), $delimiter_re (the table
# delimiter-row pattern, shared with the artifact table count).
#
# Only schema-v2 records are graded; the kickoff fixture's unversioned
# records (an integer `turn` field) are ignored rather than misread. A record
# carrying any other `v` is a schema error: no other version was ever written.
#
# Output: {schema_errors: [..], results: [{inv, ok, vacuous?, reason}, ..]}.

def rank: {decision: 0, question: 0, request: 0, state: 1, reasoning: 1, bookkeeping: 2};

# Projections that stand in for a larger record, so they must point at it.
def record_classes: ["handoff", "ci-failure", "drain-report", "resume-lead", "step-report", "halt-batch", "lens-pass"];

def projection_classes: record_classes + ["running-summary", "open-captures", "resume-confirmation", "selector", "capture-proposal"];

def capture_targets: ["awaiting-input", "deferred", "observation"];

# A markdown table has exactly one delimiter row, so delimiter rows count tables.
def is_delimiter: test("\\|") and test($delimiter_re);
def tables: [split("\n")[] | select(is_delimiter)] | length;

def id_count: [scan("\\bREQ-[A-Z][A-Z0-9]*\\.[0-9]+[a-z]?\\b|\\bD-[0-9]+\\b|\\bobs:[0-9a-f]{8}\\b")] | length;

def ok: {ok: true, reason: ""};
def bad($r): {ok: false, reason: $r};
# Nothing to grade: a failure that can never satisfy an expected failure, so a
# run that emitted nothing cannot pass as a planted wall.
def vacuous($r): {ok: false, vacuous: true, reason: $r};
def verdict: if length == 0 then ok else bad(.[0]) end;

def turn_ok:
  (.seq | type) == "number"
  and (.phase | type) == "string"
  and (.surface | type) == "string"
  and (.projection as $p | any(projection_classes[]; . == $p))
  and (.text | type) == "string"
  and (.sections | type) == "array" and (.sections | length) > 0
  and all(.sections[];
      (.role | type) == "string" and (.role as $r | rank | has($r))
      and (.text | type) == "string" and (.text | length) > 0)
  and ((.full_record == null) or ((.full_record | type) == "string"))
  and ((.selector == null) or ((.selector | type) == "object"))
  and ((.captures == null) or ((.captures | type) == "array"));

def states: [.sections[] | select(.role == "state") | .text];

# A trailing newline ends the last line rather than starting another.
def line_count: rtrimstr("\n") | split("\n") | length;

def no_table_dump($turns; $cfg):
  if ($turns | length) == 0 then vacuous("no turn records to grade")
  else [$turns[] | {seq, n: (.text | tables)} | select(.n > $cfg.max_tables)
        | "turn seq \(.seq) carries \(.n) tables (max \($cfg.max_tables))"] | verdict
  end;

def projection_present($turns; $cfg; $art):
  if ($turns | length) == 0 then vacuous("no turn records to grade")
  else
    ([$turns[] | select((.text | length) > $cfg.max_chars)
      | "turn seq \(.seq) is \(.text | length) chars (max \($cfg.max_chars))"]
    + (if $cfg.max_sections == null then []
       else [$turns[] | select((.sections | length) > $cfg.max_sections)
             | "turn seq \(.seq) carries \(.sections | length) sections (max \($cfg.max_sections))"] end)
    + [$turns[] | . as $t | select(any(record_classes[]; . == $t.projection))
       | ($t.full_record // "") as $f
       | if $f == "" then "turn seq \($t.seq) (\($t.projection)) names no artifact holding the full record"
         elif $art[$f] == null or $art[$f].bytes == 0 then "turn seq \($t.seq) points at \($f), which the run never wrote"
         elif ($t.text | contains($f) | not) then "turn seq \($t.seq) never shows the operator its pointer to \($f)"
         elif $art[$f].bytes <= ($t.text | length) then "turn seq \($t.seq): \($f) is no larger than the turn, so the turn is not a projection of it"
         elif $cfg.artifact_min_tables != null and $art[$f].tables < $cfg.artifact_min_tables then
           "turn seq \($t.seq): \($f) carries \($art[$f].tables) tables, short of the full record's \($cfg.artifact_min_tables)"
         else empty end])
    | verdict
  end;

def decisions_first($turns):
  if ($turns | length) == 0 then vacuous("no turn records to grade")
  else [$turns[] | . as $t
        | [$t.sections[] | .role as $r | rank[$r]] as $rk
        # split, not index: jq before 1.8 reports index/1 in bytes, and the
        # slice counts codepoints, so multibyte text would skew the offset.
        | (reduce $t.sections[] as $s ({at: 0, pos: []};
            ($t.text[.at:] | split($s.text)) as $parts
            | if ($parts | length) < 2 then .pos += [null]
              else ($parts[0] | length) as $i | .pos += [.at + $i] | .at += $i + ($s.text | length) end)) .pos as $pos
        | if any($pos[]; . == null) then "turn seq \($t.seq): a section's text is not in the emitted turn, in order"
          elif any(range(1; $rk | length); $rk[.] < $rk[. - 1]) then
            "turn seq \($t.seq) orders \([$t.sections[].role] | join(" > ")), so a decision trails supporting state or bookkeeping"
          else empty end] | verdict
  end;

def no_monotonic_growth($turns; $cfg):
  [("running-summary", "open-captures") as $c | [$turns[] | select(.projection == $c)] | select(length >= 2)] as $series
  | [$turns[] | select(.projection == "resume-confirmation")] as $resumes
  | if ($series | length) == 0 and ($resumes | length) == 0 then vacuous("no repeated summary or resume confirmation to grade")
    else
      ([$series[] | . as $s | range(1; $s | length)
        | ($s[. - 1] | states) as $prev | $s[.] as $cur
        | select(($prev | length) > 0 and all($prev[]; . as $x | $cur.text | contains($x)))
        | "\($cur.projection) seq \($cur.seq) replays every state line of the one before it"]
      + [$resumes[] | . as $t | $t.sections[] | select(.role == "state")
         | select((.text | line_count) > 1 or ((.text | rtrimstr("\n") | length) > $cfg.max_confirm_line_chars))
         | "resume confirmation seq \($t.seq) spends more than one line on a settled section"])
      | verdict
    end;

def identifier_density($turns; $cfg):
  [$turns[] | select(.selector != null)] as $sel
  | if ($sel | length) == 0 then vacuous("no selector turns to grade")
    else [$sel[] | . as $t | ($t.selector.options // []) as $o
          | ([$t.selector.question] + [$o[] | .label, .description] | map(select(type == "string")) | join(" ") | id_count) as $n
          | if ($o | length) < 2 then "selector seq \($t.seq) offers fewer than two options"
            elif any($o[]; (.label // "") == "" or (.description // "") == "") then "selector seq \($t.seq) has an option missing its action or consequence"
            elif $n > $cfg.max_selector_ids then "selector seq \($t.seq) carries \($n) identifiers (max \($cfg.max_selector_ids))"
            else empty end] | verdict
    end;

def capture_at_birth($v2; $turns; $cfg; $art):
  [$v2[] | select(.kind == "answer" and (.confirms // "") != "")] as $conf
  | [$v2[] | select(.kind == "answer" and (.declines // "") != "")] as $decl
  | [$v2[] | select(.kind == "decision" and .capture != null)] as $caps
  | [$decl[] | . as $d | select(any($caps[]; .capture.id == $d.declines)) | "\($d.declines) was declined yet tracked"] as $leaked
  | if ($leaked | length) > 0 then bad($leaked[0])
    elif any($conf[]; .confirms == $cfg.planted_capture) | not then
      vacuous("the planted item \($cfg.planted_capture) was never confirmed in the run")
    else
      [$conf[] | . as $a
        | [$turns[] | select(.seq < $a.seq and any(.captures[]?; .id == $a.confirms))] as $prop
        | [$caps[] | select(.capture.id == $a.confirms and .seq > $a.seq)] as $w
        | if ($prop | length) == 0 then "\($a.confirms) was confirmed without the skill first proposing its tracked form"
          elif ($w | length) == 0 then "\($a.confirms) was confirmed but never written to tracked state"
          elif any(capture_targets[]; . == $w[0].capture.target) | not then "\($a.confirms) went to \($w[0].capture.target), which is not a tracked-state target"
          elif ($art[$w[0].capture.ref // ""] // {bytes: 0}).bytes == 0 then "\($a.confirms)'s tracked record \($w[0].capture.ref) was never written"
          else empty end]
      | verdict
    end;

def step_report_slots($v2; $turns):
  [$turns[] | select(.projection == "step-report")] as $sr
  | [$v2[] | select(.kind == "decision") | .capture.id? // empty] as $ids
  | if ($sr | length) == 0 then vacuous("no step report to grade")
    else [$sr[] | . as $t | [$t.sections[].role] as $roles
          | [$t.sections[] | select(.role == "reasoning")] as $why
          | if any($roles[]; . != "state" and . != "reasoning" and . != "request") then
              "step report seq \($t.seq) carries a section outside the state, reasoning, and requests slots"
            elif any($roles[]; . == "state") | not then "step report seq \($t.seq) has no state slot"
            elif ($why | length) > 1 then "step report seq \($t.seq) has more than one reasoning slot"
            elif any($why[]; (.text | line_count) > 2) then "step report seq \($t.seq) runs its reasoning past two lines"
            elif any($t.sections[]; .role == "request" and ((.capture // "") as $c | any($ids[]; . == $c) | not)) then
              "step report seq \($t.seq) leaves a request in prose instead of a captured item"
            else empty end] | verdict
    end;

# Segments are runs of consecutive turns in one phase, so a phase that comes
# back is graded at each of its boundaries.
def open_captures_list($turns):
  ($turns | sort_by(.seq)
   | reduce .[] as $t ([]; if length > 0 and .[-1].phase == $t.phase then .[-1].turns += [$t]
                           else . + [{phase: $t.phase, turns: [$t]}] end)) as $segments
  | if ($segments | length) < 2 then vacuous("fewer than two phases, so no phase boundary to grade")
    else [$segments[:-1][]
          | select(any(.turns[]; .projection == "open-captures") | not)
          | "phase \(.phase) ended without showing the open-captures list"] | verdict
    end;

. as $log
| [$log[] | select(.v == 2)] as $v2
| [$v2[] | select(.kind == "turn")] as $turns
| ($artifacts | map({key: .name, value: .}) | from_entries) as $art
| {
    schema_errors: (
      [$log[] | select(.kind == "turn" and .v != 2) | "a turn record not on schema v2 (seq \(.seq // "?"))"]
      + [$log[] | select(.kind != "turn" and has("v") and .v != 2) | "a \(.kind // "kindless") record not on schema v2 (seq \(.seq // "?"))"]
      + [$turns[] | select(turn_ok | not) | "turn record seq \(.seq // "?") violates the v2 turn schema"]
      + (if ([$v2[].seq] | . == (unique)) then [] else ["v2 records do not carry strictly increasing seq values"] end)
    ),
    results: [$cfg.invariants[] as $inv | {inv: $inv} + (
      if $inv == "no-table-dump" then no_table_dump($turns; $cfg)
      elif $inv == "projection-present" then projection_present($turns; $cfg; $art)
      elif $inv == "decisions-first" then decisions_first($turns)
      elif $inv == "no-monotonic-growth" then no_monotonic_growth($turns; $cfg)
      elif $inv == "identifier-density" then identifier_density($turns; $cfg)
      elif $inv == "capture-at-birth" then capture_at_birth($v2; $turns; $cfg; $art)
      elif $inv == "step-report-slots" then step_report_slots($v2; $turns)
      elif $inv == "open-captures-list" then open_captures_list($turns)
      else bad("unknown invariant") end)
      | .reason |= gsub("[\t\n\r]"; " ")]
  }
