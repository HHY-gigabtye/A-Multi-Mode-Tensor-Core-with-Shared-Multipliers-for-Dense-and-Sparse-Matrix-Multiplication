# Verification evidence — 2026-10-29

This directory contains full textual evidence from the portfolio preparation
rerun, not newly invented test results. See
[reproduction details](../../../docs/verification-and-reproduction.md).

| File | Provenance |
|---|---|
| `units.log` | Fresh execution of `integration_sv/sim/run_units.do`, exit 0 |
| `top.log` | Fresh execution of `integration_sv/sim/run_top.do`, exit 0 |
| `c_tests.log` | Final fresh execution of `tools/run_c_tests.bat`, exit 0 |
| `c_tests_initial_encoding_failure.log` | Earlier attempt without `/utf-8`, exit 1; superseded by final launcher |
| `tool_versions.txt` | Observed simulator and C compiler version output |
| `source-sha256.csv` | Working-tree source/script/vector hashes for audit provenance |

Published log copies replace the local workspace prefix with `<repo>` and the
Visual Studio installation prefix with `<VisualStudio>`. No test output, result
counts, warnings or errors are removed. Original logs remain in the local
ignored `build/portfolio-audit/` directory. Existing historical logs elsewhere
are not overwritten. The source hashes cover the audited working tree, which
included the author's existing uncommitted whitespace/Tcl edits; they do not
claim the run corresponds exactly to an earlier commit.

Observed SV unit PASS totals: MLU 16,708 records; DU/TIA 3,292 packets; Bridge
19,147 records; TC 136,136 records; MSU 8,683 cycles. Expected rejection cases
are intentional negative tests. Each suite has six existing compilation
warnings about default struct input port kinds; there are no fatal/error
messages. Functional simulation success does not establish timing closure.

The full-system result is:

```text
TOP INTEGRATION PASS: completed_tiles=316 issued_packets=3124 write_beats=2563 resets=75 seed=91e10da5
```

316 completions comprise 208 main-stream tiles and 108 post-reset recovery
tiles. Packet/beat counters also include checked partial work discarded on
reset. Coverage counters are observations/events, not distinct completed tiles.
Targeted reset occupancy masks are FIFO `1ff`, in-flight `1f`, metadata/MSU/TC/
MLU `7`, write rows `ff`, outstanding read `1`, and stalled last beat `1`.
