# grade.jq — the structural (invariant) grade over the kickoff fixture's durable
# artifacts (operator-dialogue Task 6; REQ-H1.2, REQ-C1.1, REQ-D1.1, REQ-B1.5,
# REQ-E1.1, REQ-F1.2). It reads the artifacts the run WROTE — never a scraped
# pane (REQ-G1.3) — merged by the harness into one object:
#
#   { persona, decision_log: [ {turn, kind, ...}, ... ], sign_off: {...} }
#
# It yields a single boolean: the UNIVERSAL assertable invariants that must hold
# on EVERY kickoff run (novice, expert, malformed, undefined, reopen). The
# experiential qualities — was the pitch appropriate, is a marked recommendation
# genuinely grounded — are NOT graded here; that is the independent grader's and
# the human's job (REQ-G1.4, REQ-H1.3). This is only the mechanical floor.
#
# The invariants (REQ-H1.2's named set + the Task-6 additions):
#   - eval-only: the sign-off is eval_only && !authoritative (REQ-G1.6).
#   - completeness: ready is declared IFF no required decision is left undefined
#     (ready == (blocked_on == []))  (REQ-C1.1).
#   - normative-token preservation: every normative token an explanation records
#     conveying appears VERBATIM in that explanation's rendered text (REQ-B1.5).
#   - no verdict: the durable text corpus carries no self-verdict phrase — the
#     skill presents information, never a quality verdict on the spec (REQ-D1.1).
#   - on a READY run: a self-contained confirmation was reached, and a
#     shared-understanding summary was emitted STRICTLY BEFORE it (REQ-F1.2).
#
# jq is a pure data transform: artifact values are inspected, never executed.
(.sign_off // {}) as $s
| (.decision_log // []) as $log
| ([$log[] | select(.kind == "explanation")]) as $expl
| ([$log[] | select(.kind == "confirmation")]) as $conf
| ([$log[] | select(.kind == "summary")]) as $summ
| ([$expl[].text] + [$summ[].text] + [$conf[].question]
   + [$conf[].options[]?.description] + [$conf[].options[]?.label]
   | map(select(. != null)) | join(" ") | ascii_downcase) as $corpus
| (["this spec is good", "ready-quality", "i recommend approv", "looks good to me",
    "quality score", "strong spec", "i would approve", "i'd approve"]) as $verdicts
| ($s.eval_only == true and $s.authoritative == false) as $p_evalonly
| (($s.blocked_on | type) == "array") as $p_blockarr
| (($s.calibration | type) == "number" and $s.calibration >= 1) as $p_cal
| (if $s.ready == true then ($s.blocked_on | length) == 0 else ($s.blocked_on | length) > 0 end) as $p_complete
| ([$expl[] | . as $e | ($e.normative_tokens // []) | all(. as $tok | ($e.text | contains($tok)))] | all) as $p_norm
| ([$verdicts[] | . as $v | ($corpus | contains($v)) | not] | all) as $p_noverdict
| (if $s.ready == true then
      ($conf | length) > 0
      and ($summ | length) > 0
      and ($s.summary_before_confirmation == true)
      and (($conf | map(.turn) | min) as $ct | ($summ | map(.turn) | min) < $ct)
      and (($s.approved | type) == "boolean")
      and (($s.decision // "") | length > 0)
      # Self-contained-confirmation STRUCTURE, not just existence (REQ-E1.1,
      # REQ-E1.2, REQ-H1.2): every reached confirmation carries >=2 options, an
      # explicit reject, a non-empty label + consequence on each, and no
      # pre-selected default. This makes grade.jq a genuine floor for the
      # invariant even on a real harness run where the independent grader is
      # unavailable.
      and ($conf | all(
            ((.options | type) == "array") and ((.options | length) >= 2)
            and ((.options | map(select(.reject == true)) | length) >= 1)
            and (.options | all(
                  ((.label | type) == "string") and ((.label | length) > 0)
                  and ((.description | type) == "string") and ((.description | length) > 0)
                  and (.default != true) and (.preselected != true) and (.selected != true)))))
    else
      ($s.approved == false)
    end) as $p_ready
| ($p_evalonly and $p_blockarr and $p_cal and $p_complete and $p_norm and $p_noverdict and $p_ready)
