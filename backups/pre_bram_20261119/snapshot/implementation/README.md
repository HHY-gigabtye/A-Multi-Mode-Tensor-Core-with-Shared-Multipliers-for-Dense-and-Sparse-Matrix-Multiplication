# Verified original FF implementation backup

`original_ff_routed.dcp` and the five reports are byte-identical copies of the
original-RTL baseline under `experiments/mlu_bram_20261118/baseline/`.
`manifest.csv` records exact source paths and SHA-256 hashes.

This implementation uses the original 11 RTL/package files, Vivado 2022.2,
`xc7z020clg484-1`, and a 10 ns clock. Its post-route result is 29,405 LUTs,
21,503 FFs, zero BRAM, 128 DSPs, WNS +0.002 ns, and WHS +0.096 ns.

This is a separately implemented original FF baseline, not the deleted
native GUI run, which had 29,406 LUTs and WNS +0.016 ns. The one-LUT difference
comes from different physical flows applied to the same original RTL.

Open the DCP in Vivado to inspect the archived FF result. Source/project
restoration instructions are in `../BACKUP.md`. This backup is not referenced
by the active BRAM project and is not used as an incremental checkpoint.
