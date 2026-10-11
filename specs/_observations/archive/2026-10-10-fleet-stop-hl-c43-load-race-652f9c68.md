- 2026-10-10 [planwright] tests/test-fleet-stop-hl.sh case c43 ("the worker never reached its hold loop") failed the same way as test-fleet-stop-sj.sh c20 in test-throughput task-4's full gate on 2026-10-11 under host load. The race sits in the shared hold-loop wait; fix both files together (see fleet-stop-sj-c20-load-race).
Consumed-by: specs/fleet-lifecycle-closure (2026-10-11)
