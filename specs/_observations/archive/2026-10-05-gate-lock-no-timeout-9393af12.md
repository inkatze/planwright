- 2026-10-05 [planwright] A full gate held the host gate lock for over 40 minutes on 2026-10-05 while test-run-tests-pool.sh in another worktree sat in its overlap fixture; flock -o waiters have no timeout and the gate itself has no per-file test deadline, so one hung test file stalls every queued gate on the host.
Consumed-by: specs/test-throughput (2026-10-09)
