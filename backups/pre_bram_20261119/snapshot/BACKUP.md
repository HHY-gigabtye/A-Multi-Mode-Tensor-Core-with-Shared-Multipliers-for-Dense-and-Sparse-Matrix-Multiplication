# Original RTL backup before BRAM promotion

This byte-verified backup was made before applying the accepted BRAM version
to the `main` working tree on 2026-11-19. `base_commit.txt` records the original
Git commit; `manifest.csv` records SHA-256 hashes of 22 original source,
project, build-script, and README files. `protected_initial.csv` records the
unchanged reference/test inputs.

The original 11 RTL/package files are stored under their repository-relative
paths. Only `mlu_sv/mlu.sv` and `fifo_sv/du_tc_bridge.sv` differ in the BRAM
version. The original project configuration and its scripts are also saved.
The promotion scripts did not delete or reset historical runs. During the
subsequent GUI handoff, the GUI transcript recorded deletion of the old
`synth_10ns_margin_20261113` run and its dependent implementation. Their
original configuration remains in this backup. A separately verified original
FF implementation and reports were additionally copied into `implementation/`
with their own manifest. Historical experiment checkpoints remain unchanged.

To restore the original RTL deliberately, copy the two SV files from this
backup to the matching repository paths and verify their manifest hashes.
The original project configuration is available at
`project_integration/project_integration.xpr` within this backup. Restore
that file to its original location if the historical active-run configuration
is also needed; reset/rebuild those runs because their generated directories
were removed during handoff. Alternatively, open the archived FF checkpoint
to inspect its already-routed result. Back up later work before restoring files.

This directory is an archival backup, not the active Vivado source tree.
