# MLU image-buffer BRAM experiment — 2026-11-18

## Outcome: not accepted as a production replacement

The candidate maps the MLU image to real BRAM and passes the original unit
and integration regressions plus RTL/primitive cycle comparisons. It does
**not** satisfy the requested 100 MHz physical timing requirement. New BRAM
asynchronous-control DRC warnings also remain unqualified. The production
RTL and all original tests/reference material are unchanged.

All numbers below are complete, independently reopened **FPGA OOC post-route**
measurements on `xc7z020clg484-1`, Vivado 2022.2, with a 10.000 ns clock.
These are not board-level sign-off results. The BRAM columns use the same RTL
snapshot with different physical flows; neither meets 100 MHz.

| Metric | Fresh original, closure | BRAM, measured controls | BRAM, incremental refinement |
| --- | ---: | ---: | ---: |
| LUT | 29,405 | 26,573 | 26,320 |
| FF | 21,503 | 19,223 | 19,193 |
| RAMB36E1 | 0 | 18 | 18 |
| DSP48E1 | 128 | 128 | 128 |
| Setup WNS (ns) | +0.002 | -1.116 | -1.170 |
| Setup TNS (ns) | 0 | -3737.138 | -4560.447 |
| Hold WHS (ns) | +0.096 | +0.098 | +0.098 |
| Hold THS (ns) | 0 | 0 | 0 |
| Fully routed nets | 41,611 | 39,199 | 39,375 |
| Routing errors | 0 | 0 | 0 |
| Meets 100 MHz internal setup/hold | Yes | No | No |

The best completed candidate timing result saves 2,832 LUTs (9.63%) and
2,280 FFs (10.60%) versus the fresh passing baseline, using 18 RAMB36E1s
(12.86% of the device's 140 BRAM tiles). The incremental candidate saves
slightly more area but has worse setup slack. These later physical flows
are not identical: the paired fresh/default and fresh/refined comparisons
are separately preserved in `timing_resource_comparison.csv`.

The final evidence is `baseline/final_audit/`, `banked/final_audit/`, and
`banked/incremental_audit/`; the RTL review diff is `banked/rtl.patch`.
`result.json` records the assessment, exact checkpoint/source hashes,
verification counts, measured values, and incomplete optional stages.
The extra candidate closure reroute and baseline 9.750 ns margin search were
stopped, and their incomplete stages are not reported as completed results.
No frequency was relaxed, no pipeline stage was added, and no timing
exception or DRC waiver was introduced to obtain a pass.

## Scope and provenance

The requested acceptance criteria are unchanged external MLU behavior on every
cycle, unchanged full-system functionality, and 100 MHz internal FPGA timing.
Only the candidate `banked/src/mlu_sv/mlu.sv` is changed. The other ten source
files and all original C models, adapters, vectors, testbenches, assertions,
and seeds remain unchanged. Main production RTL is preserved.

`base_commit.txt` identifies the initial Git snapshot. `baseline/src/` is an
immutable copy of its eleven active source/package files. The original tree
was clean before experiment artifacts were added. `protected_initial.csv`
records the 76 protected file hashes verified by the regression runner.
No commit, merge, or push is part of this experiment.

The physical baseline uses Vivado 2022.2, `xc7z020clg484-1`, and the existing
out-of-context production recipe. The operating clock is 10.000 ns. The
existing recipe includes a 9.750 ns physical margin search and restores
10.000 ns before applying the original final timing gate. That search is not
a claim of 9.750 ns closure. Both source snapshots receive identical fresh
synthesis, placement, routing, and first-refinement steps. The candidate's
later driver selection must use its measured netlist names, as detailed below.

The fresh baseline reached 100 MHz after the closure refinement: 29,405 LUTs,
21,503 FFs, zero BRAM, 128 DSPs, WNS +0.002 ns, and WHS +0.096 ns. Its complete
checkpoint is `baseline/implementation/closure/routed.dcp`. The subsequent
optional 9.750 ns margin search was stopped after this required 100 MHz gate
was met; it is not presented as a completed result. `baseline/final_audit/`
contains an independent reopen of the accepted fresh baseline. The separately
reopened native production result (+0.016 ns) remains supplemental evidence.

## Candidate organization

An attribute alone cannot implement the old access/reset behavior in a
different physical memory. AMD's [UG912 RAM_STYLE reference](https://docs.amd.com/r/2022.2-English/ug912-vivado-properties/RAM_STYLE)
describes the attribute as directing RAM inference, while [UG901's RAM
comparison](https://docs.amd.com/r/2022.2-English/ug901-vivado-synthesis/Choosing-Between-Distributed-RAM-and-Dedicated-Block-RAM)
requires synchronous reads for dedicated block RAM. The original MLU image
is part of resettable packed state and is read combinationally by
`make_frame()`. It therefore needs an RTL storage/control restructuring,
not merely a change of inference preference. The restructured candidate
below is one cycle-compatible attempt; physical acceptance is separate.

The two 160-byte images are divided into five 256-bit beat banks. Each bank
contains two addresses, one per tile slot, and has a synchronous read port
and a synchronous write port. The read address is the head committed at the
current edge. All banks read in parallel; the original `make_frame()` selects
the current k and mode combinationally from the resulting image. This avoids
adding an externally visible output-register cycle or a packet bubble.

This first candidate deliberately trades BRAM capacity efficiency for a
small change to packet assembly. Standalone synthesis mapped the useful
image bits to 18 RAMB36E1 primitives, with READ_FIRST behavior and DO_REG=0.
Unused padding in the final bank is pruned. This is not a minimum-BRAM design.

Control, command metadata, and event state remain resettable registers. The
image RAM contents are not reset. `beats_received` identifies which beats
are valid in each slot, giving the same logical zero contents after reset
and command allocation. Retired slots retain their logical image until
reallocated. The simulation-only `state_q` observation reconstructs the
original packed state from the actual bank memories and control registers;
it does not keep an independent shadow copy of the payload or compute
expected data. The original full-state C-vector assertions are unchanged.

Hybrid group-0 mask legality is computed when beat 2 is accepted and saved
per slot. Errors remain visible only at the original final-beat edge, with
unchanged command/read-last/hybrid error priority. Every physical RAM write
is gated by reset, an actual read-data transfer, and `status == IO_OK`.

### Read-during-write and head transitions

A READY slot is never written while it is issuing packets. When a final
load beat makes a slot READY, the first visible packet is k=0. Its required
bytes are in already-written earlier beats for all three modes:

- Dense k=0 uses bytes 0..15; its final beat covers bytes 96..127.
- Hybrid k=0 uses bytes 0..8 and 72..95; its final beat covers 96..127.
- Dual k=0 uses bytes 0..17; its final beat covers 128..159.

Thus a READ_FIRST collision on that final bank does not affect the first
packet. The next read refreshes that bank before any later packet needs it.
The same argument applies when the old head's k=7 retires on the new head's
final load edge. The supplemental test explicitly exercises both slot
directions, all nine mode transitions, and output stalls around these edges.

## Verification status

- Fresh baseline: all five original unit regressions and integration passed.
- Candidate: all five original unit regressions and integration passed.
- Original MLU: 16,708 records, 145 resets, 128 rejected edges, with complete
  state and pre-edge output comparison against immutable C vectors.
- Integration: 316 completed tiles, 75 resets, seed `91e10da5`.
- All 46 integration summary/coverage lines match the baseline in order.
- All 76 protected file hashes remain unchanged.
- Supplemental RTL and post-synthesis primitive simulations both passed:
  16,708 immutable C records, 17,171 total checked steps, 18 directed head
  transitions, 234 total simultaneous final-load/final-packet edges, 5,347
  output-stall observations, and 155 reset edges. The directed scenarios
  cover all nine mode combinations and both physical slot directions.
  See `banked/equiv_rtl/result.log` and `banked/equiv_netlist_5/result.log`.

Standalone candidate synthesis reports 1,547 LUTs, 394 flip-flops, and 18
RAMB36E1s. These are **standalone post-synthesis** numbers, not integrated
post-route results and not a timing-closure claim.

The completed implementation results are summarized above and in
`timing_resource_comparison.csv`. Initial simulator
launch failures were runner/environment issues and are retained in their
logs: ModelSim required execution outside the sandbox, its `.do` script did
not supply a usable `info script`, and Vivado's emitted netlist separates
packed struct/array ports into individual escaped field ports. No original
test assertion or expected result was modified to resolve these issues.

## Reproduction

From the repository root, use new trial/output names to preserve evidence:

```powershell
& ./experiments/mlu_bram_20261118/prepare.ps1
& ./experiments/mlu_bram_20261118/regress.ps1 -Trial baseline -Test all
& ./experiments/mlu_bram_20261118/regress.ps1 -Trial banked -Test mlu
& ./experiments/mlu_bram_20261118/regress.ps1 -Trial banked -Test all
```

`prepare.ps1` refuses to replace existing source snapshots. The delivered
candidate is already under `banked/src/`; preparation alone copies the
baseline and does not implement the BRAM change.

Vivado entry points, with paths relative to the repository root:

```powershell
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log probe.log -source experiments/mlu_bram_20261118/probe_mlu.tcl -tclargs experiments/mlu_bram_20261118/banked/src NEW_PROBE_OUTPUT
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log equiv.log -source experiments/mlu_bram_20261118/equiv.tcl -tclargs experiments/mlu_bram_20261118/banked/src NEW_PROBE_OUTPUT/mlu_netlist.v NEW_EQUIV_OUTPUT
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log baseline_implementation.log -source experiments/mlu_bram_20261118/implement.tcl -tclargs experiments/mlu_bram_20261118/baseline/src NEW_BASELINE_OUTPUT
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log banked_implementation.log -source experiments/mlu_bram_20261118/implement.tcl -tclargs experiments/mlu_bram_20261118/banked/src NEW_BANKED_OUTPUT
```

The supplemental `equiv.tcl` also accepts `RTL` instead of a netlist path.
It compares all pins/events against the unchanged baseline and checks the
original C vectors. Its netlist wrapper only reconnects the emitted field
ports; the generated netlist is not edited.

Additional physical commands used after the candidate fresh/refined route
(use new output directories and log names when replaying):

```powershell
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log NEW_MEASURED.log -source experiments/mlu_bram_20261118/resume_measured.tcl -tclargs experiments/mlu_bram_20261118/banked/implementation/fresh/refined/routed.dcp experiments/mlu_bram_20261118/banked/implementation/fresh/refined/high_fanout.rpt NEW_MEASURED_OUTPUT
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log NEW_INCREMENTAL.log -source experiments/mlu_bram_20261118/incremental.tcl -tclargs experiments/mlu_bram_20261118/banked/implementation/fresh/default/synthesized.dcp project_integration/project_integration.runs/impl_10ns_margin_20261113/sparse_tensor_core_top_routed.dcp NEW_INCREMENTAL_OUTPUT
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log NEW_AUDIT.log -source experiments/mlu_bram_20261118/audit.tcl -tclargs NEW_INCREMENTAL_OUTPUT/refined/routed.dcp NEW_AUDIT_OUTPUT 18
```

To rerun functional tests without replacing any existing logs, copy the
delivered `banked/src/` directory into a new sibling trial's `src/` directory
and pass that new trial name to `regress.ps1 -Trial NAME -Test all`.
No original expected vectors, seeds, assertions, or golden models need editing.

## Measurement limits

The scope is internal FPGA OOC timing, with the same unconstrained external
I/O delays as the established production flow. Board timing, external HBM
operation, power measurements, and an ASIC implementation are outside this
experiment. Resource savings and 100 MHz acceptance require the final
integrated post-route comparison; standalone synthesis is insufficient.

## Additional physical trial and checkpoint discrepancy

The fresh candidate's default routed result has 26,401 LUTs, 19,223 FFs,
18 RAMB36E1s, setup WNS -1.632 ns, hold WHS +0.098 ns, and zero routing
errors. The worst path is Bridge metadata-count to FIFO payload clock
enable, with 11.343 ns data delay: 2.631 ns logic and 8.712 ns routing.
The default route therefore does not meet the requested 100 MHz target.
The first refinement completed with 26,407 LUTs, 19,223 FFs, 18 RAMB36E1s,
setup WNS -1.422 ns and hold WHS +0.098 ns. Its worst path is Bridge head
selection to a Tensor Core DSP clock enable, with 10.814 ns data delay:
1.324 ns logic and 9.490 ns routing (87.8%).

The next original replication step stopped before mutation because the old
driver `u_bridge/dense_q[b_delay][7][6][value][7]_i_1` does not exist in the
candidate netlist. This is a recorded script applicability failure, not a
functional regression. `resume_measured.tcl` resumes from the completed
candidate refinement with LUT drivers selected from its own high-fanout
report (fanout >= 128 and worst slack <= -0.500 ns), plus the inspected final
LUT on its worst DSP clock-enable path. `banked/measured/selection.tsv`
records each resolved driver. The nineteen-driver physical replication and
route completed with 26,573 LUTs, 19,223 FFs, 18 RAMB36E1s, 128 DSPs, setup
WNS -1.116 ns, setup TNS -3737.138 ns, hold WHS +0.098 ns, and hold THS 0.
All 39,199 routable nets are fully routed, with zero routing errors.
The worst path is Bridge head selection to a Tensor Core sparse accumulator
clock enable: 10.827 ns data delay, 1.820 ns logic and 9.007 ns routing (83.2%).
This is the best completed candidate setup result, but it does not meet 100 MHz.
`banked/final_audit/` independently reopens this completed checkpoint.

The follow-on closure reroute was stopped during routing. Its intermediate
slack estimates are not final measurements and are excluded from the tables.
No candidate margin search or final timing-gate pass is claimed. The full
continuation remains reproducible with `resume_measured.tcl`, but this
delivered experiment does not satisfy the original acceptance criteria.
This adapted physical trial is listed separately from the paired fresh flow.

A separate physical-only incremental trial uses the current native production
checkpoint as placement/routing guidance for the new candidate synthesis.
This is recorded separately from the paired fresh flow. It follows
[AMD UG904's non-project incremental flow](https://docs.amd.com/r/2022.2-English/ug904-vivado-implementation/Saving-Post-Reuse-Checkpoints):
`opt_design`, `read_checkpoint -incremental`, placement, and routing.
No RTL, clock period, interface, latency, or test expectation is changed.

The native checkpoint's current SHA256 is
`614FE4D28CBE21183B294B1D096C63480414169F2CA8E79EFCDDF92CE0AC31DF`,
which differs from the older result JSON's
`D3BB68943300BCA0E34EA2640293D69E15D7C3865BF0F0ED045596436F09CC8E`.
The cause of that binary-file difference is not established here; it is not
silently treated as the same archived file. `archived_checkpoint_hash.json`
records the discrepancy. A fresh read-only independent reopen completed at
17:54 on 2026-11-18 (UTC+08:00), confirming 10.000 ns, setup +0.016 ns,
hold +0.096 ns, 41,612 fully routed nets, zero routing errors, zero BRAM,
and the original 128-DSP pipeline configuration. See `archived_baseline_audit/`.
This checkpoint supplies physical reference information; the implemented
candidate logic comes from its newly synthesized immutable RTL snapshot.

The first incremental import matched 76.59% of cells, below Vivado's default
80% threshold, and automatically reverted to a normal flow. That redundant
trial was stopped during placement; its `banked/incremental.log` is retained
and is not presented as an incremental result. The explicit reuse trial in
`banked/incremental_forced/` uses `read_checkpoint -incremental -force_incr`.
This option requests physical reuse of matching cells; it does not relax
timing or alter behavioral acceptance criteria.

The explicit incremental trial completed both routing and refinement. Its
final result is 26,320 LUTs, 19,193 FFs, 18 RAMB36E1s, 128 DSPs, setup WNS
-1.170 ns, setup TNS -4560.447 ns, hold WHS +0.098 ns, and hold THS 0.
It does not meet 100 MHz. The worst path is Bridge head selection to the
Tensor Core sparse accumulator clock enable: 10.881 ns data delay,
1.649 ns logic and 9.232 ns routing (84.8%). Placement/routing reuse is
partial, not a claim that the old implementation was preserved wholesale.

The independent incremental reopen also identifies a failing MLU-local path:
`ctrl_q_reg[head]` to `g_image[3].memory_reg_2/WEBWE[3]`, WNS -1.007 ns,
10.391 ns data delay (2.048 ns logic, 8.343 ns routing). Therefore the timing
problem is not confined to unrelated system logic, even though the global
worst path ends in the Tensor Core.

The default DRC has no Error-severity findings, but introduces `REQP-1839`
warnings for BRAM control inputs whose fan-in includes asynchronously reset
registers. The report reaches that rule's 20-finding limit (`CHECK-3`), so 20
is a capped report count, not an exhaustive count. Vivado explicitly states
that reset-induced memory/read corruption is not covered by default STA.
The retained logical reset contract invalidates image contents and requires
complete reload before output, and all reset simulations pass. That does
not constitute physical qualification or an accepted DRC waiver for this
asynchronous-control warning. No warning was suppressed and no reset
latency/semantics were changed. This is an additional open hardware
qualification item; the candidate is an experiment, not a production-ready
replacement. See `banked/incremental_audit/drc.rpt` and `mlu.rpt`.
The best-timing measured-control candidate has the same warning categories.
Its MLU-local worst path is `ctrl_q_reg[count][1]` to
`g_image[4].memory_reg_0/WEBWE[3]`: WNS -0.411 ns, data delay 9.795 ns,
2.288 ns logic and 7.507 ns routing. Both global and MLU-local timing
therefore remain open in the selected candidate. See `banked/final_audit/`.

## Files and review scope

All added files are confined to `experiments/mlu_bram_20261118/`.

- Modified candidate RTL: `banked/src/mlu_sv/mlu.sv` only. The review diff is
  `banked/rtl.patch` (120 insertions, 47 deletions).
- Unchanged source copies: `baseline/src/` and the other ten `banked/src/`
  files. Source manifests record their hashes.
- New verification: `tb_mlu_bram_equiv.sv`, `equiv.tcl`, `run_tests.do`, and
  `regress.ps1`; original tests and expected vectors are read from the repo.
- New physical experiment scripts: `probe_mlu.tcl`, `implement.tcl`,
  `incremental.tcl`, `resume_measured.tcl`, and `audit.tcl`.
- New provenance/report helpers: `prepare.ps1`, `compare.ps1`,
  `check_integrity.ps1`, and `verify_logs.ps1`.
- Generated evidence: manifests, source diff, regression logs, simulator
  work directories, synthesis/route checkpoints and reports, the timing
  comparison CSV, and the archived-checkpoint hash/audit records.

Recheck the frozen sources, protected files, and completed simulation logs:

```powershell
& ./experiments/mlu_bram_20261118/verify_logs.ps1
& ./experiments/mlu_bram_20261118/compare.ps1
git diff --no-index --check experiments/mlu_bram_20261118/baseline/src/mlu_sv/mlu.sv experiments/mlu_bram_20261118/banked/src/mlu_sv/mlu.sv
```

The root production sources have no diff. No existing source or test was
deleted, and no commit, merge, push, or production project promotion occurred.
