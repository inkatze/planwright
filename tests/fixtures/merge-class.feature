# The policy-class predicates of scripts/merge-class.sh, one scenario per
# predicate (human-gates REQ-D1.3, REQ-D1.8, REQ-D1.9). tests/test-merge-class.sh
# runs a case under each scenario's exact title and fails a title it does not
# run.

Feature: A PR merges under policy-class only inside the declared class

  Background:
    Given merge_policy is policy-class
    And merge_class_max_lines is 100
    And the host allows only the squash method
    And the unit PR is on planwright/demo/task-1 from the base repository
    And its checks are green, its review converged on its head, and no Awaiting-input entry is live

  Scenario: every predicate holds
    When the class evaluator runs
    Then the PR is admitted and every predicate row reads pass

  Scenario: branch - the head is not a task branch
    Given the PR head is release-please--branches--main, a dependabot/ branch, or planwright/flight/<id>
    When the class evaluator runs
    Then the branch predicate fails and the PR falls to on-approval

  Scenario: branch - a task-shaped branch from a fork
    Given the PR head is planwright/demo/task-1 from another repository
    When the class evaluator runs
    Then the branch predicate fails and the PR falls to on-approval

  Scenario: sign-off - a trailer in the range, reverted
    Given a commit carrying a Planwright-Sign-Off trailer and a later commit reverting it
    When the class evaluator runs
    Then the sign-off predicate fails under every bound

  Scenario: sign-off - a legacy suffixed commit
    Given a commit whose subject ends with " [pending-sign-off]"
    When the class evaluator runs
    Then the sign-off predicate fails

  Scenario: core-zone - a path the core zone holds
    Given a commit changing a path a core-zone glob matches
    And merge_class_exclude_paths is empty
    When the class evaluator runs
    Then the core-zone predicate fails

  Scenario: excluded-paths - a path the adopter excludes
    Given merge_class_exclude_paths is "docs/*"
    And a commit changing docs/x.md
    When the class evaluator runs
    Then the excluded-paths predicate fails

  Scenario: max-lines - over the bound, or the bound at 0
    Given a change of more lines than merge_class_max_lines
    When the class evaluator runs
    Then the max-lines predicate fails

  Scenario: strategy - no single allowed method
    Given the host allows several methods under sole-allowed, disallows the named method, or cannot be queried
    When the class evaluator runs
    Then the strategy predicate fails naming the reason

  Scenario: awaiting-input - a human park on the base
    Given a live Awaiting-input bullet for the unit on the fetched base ref and none in the checkout
    When the class evaluator runs
    Then the awaiting-input predicate fails

  Scenario: awaiting-input - only the ready-flip parking lead
    Given the unit's only Awaiting-input segment opens with "pending ready-flip:"
    When the class evaluator runs
    Then the awaiting-input predicate holds

  Scenario: ci-rollup - the head is not green
    Given the head's check rollup is failing
    When the class evaluator runs
    Then the ci-rollup predicate fails

  Scenario: review-converged - commits after the reviewed head
    Given a commit landed after the convergence record's head
    When the class evaluator runs
    Then the review-converged predicate fails

  Scenario: ready-guard - the head is behind its base
    Given the ready-guard's currency check refuses the head
    When the class evaluator runs
    Then the ready-guard predicate fails
