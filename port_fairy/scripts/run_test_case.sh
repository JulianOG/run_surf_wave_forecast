#!/usr/bin/env bash
set -euo pipefail

case_dir="/work/run_case"
results_dir="/work/results"
rm -rf "$case_dir" "$results_dir"
mkdir -p "$case_dir" "$results_dir"
cp -a /opt/funwave-test-case/. "$case_dir/"

# Run long enough to pass STEADY_TIME (180 s) and produce the 80 s averaged
# radiation and momentum-balance diagnostics used by the MATLAB plots.
sed -i \
  -e 's|^RESULT_FOLDER.*|RESULT_FOLDER = /work/results/|' \
  -e 's/^ *PX *=.*/PX = 2/' \
  -e 's/^ *PY *=.*/PY = 1/' \
  -e 's/^ *TOTAL_TIME *=.*/TOTAL_TIME = 300.0/' \
  -e 's/^ *PLOT_INTV *=.*/PLOT_INTV = 60.0/' \
  -e 's/^ *SCREEN_INTV *=.*/SCREEN_INTV = 60.0/' \
  "$case_dir/input.txt"

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
pushd "$case_dir" >/dev/null
mpirun --allow-run-as-root --oversubscribe -np 2 funwave | tee "$results_dir/funwave-console.log"
popd >/dev/null
finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - <<PY
import json
from pathlib import Path
output = Path("$results_dir")
json.dump({
  "started_at_utc": "$started_at",
  "finished_at_utc": "$finished_at",
  "model": "FUNWAVE-TVD",
  "test_case": "beach_2d_radiation (300 s diagnostic run)",
  "mpi_processes": 2,
  "result_files": sorted(p.name for p in output.iterdir())
}, open(output / "run-metadata.json", "w"), indent=2)
PY
