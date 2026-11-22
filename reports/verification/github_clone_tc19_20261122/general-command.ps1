# Restore the exact TC vectors from the small gzip distribution.
pwsh -NoProfile -File tools/restore_vectors.ps1

# Runs the five isolated units and the old/new TC benchmark, then the top.
pwsh -NoProfile -File integration_sv/sim/run_regression.ps1

