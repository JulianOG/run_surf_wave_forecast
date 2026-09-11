# Daily FUNWAVE-TVD test forecast

This starter repository runs a small FUNWAVE-TVD test each day, renders an R
Markdown results page, and deploys only the HTML report to GitHub Pages.

## What the workflow does

1. At 03:17 UTC each day, it checks for `ghcr.io/julianog/funwave-tvd:v1`.
2. If absent (or if **Run workflow** is used with **rebuild image**), it builds
   the Docker image and pushes it to GitHub Container Registry.
3. It runs a 30-second, two-MPI-process version of FUNWAVE's bundled
   `beach_2d_radiation` case.
4. R Markdown reads the final `eta_*` field, makes a plot and records basic
   run metadata.
5. It retains all model output as a private seven-day Actions artifact and
   publishes just `site/index.html` to GitHub Pages.

## Install

Copy all files in this folder to the root of
[`JulianOG/run_surf_wave_forecast`](https://github.com/JulianOG/run_surf_wave_forecast).
Commit and push them to `main`.

Then open **Settings → Pages** and set **Build and deployment → Source** to
**GitHub Actions**. Open **Actions → Daily FUNWAVE test and report → Run
workflow** to perform the first build and test immediately.

The live report will be at:

`https://julianog.github.io/run_surf_wave_forecast/`

## Before using real forecast forcing

- Replace `scripts/run_test_case.sh` with logic that downloads/prepares the
  forecast bathymetry and boundary conditions.
- Change the `FUNWAVE_REF` commit SHA only after validating it, then update the
  image tag (for example `v2`) to force a new image build.
- GitHub-hosted runners are CPU-only. Use a self-hosted GPU or HPC runner for
  GPU FUNWAVE-TVD and larger operational domains.

## Notes

- Scheduled GitHub Actions workflows run from the default branch and can be
  delayed at busy times.
- Public GitHub Pages deployment is governed by the repository's Pages and
  Actions permissions; this workflow contains the permissions it requires.
