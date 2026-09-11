#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root after setup_port_fairy_funwave.R has completed.
# This uses the image built by the existing Dockerfile; change the image name
# to match the package image if you publish a new tag.
case_dir="$(pwd)/port_fairy/output"
mkdir -p "$case_dir/results"

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$case_dir:/work" \
  ghcr.io/julianog/funwave-tvd:v3 \
  mpirun --allow-run-as-root -np 2 funwave input.txt
