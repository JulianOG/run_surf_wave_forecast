# Daily FUNWAVE-TVD test forecast

This starter repository runs a small FUNWAVE-TVD test each day, renders an R
Markdown results page, and deploys only the HTML report to GitHub Pages.

## What the workflow does

1. At 03:17 UTC each day, it checks for `ghcr.io/julianog/funwave-tvd:v1`.
2. If absent (or if **Run workflow** is used with **rebuild image**), it builds
   the Docker image and pushes it to GitHub Container Registry.
3. It runs a 30-second, two-MPI-process version of FUNWAVE's bundled
   `beach_2d_radiation` case.
4. R Markdown uses base R and `terra` to reproduce the FUNWAVE
   `beach_2d_radiation` elevation, breaking-stress and friction-stress plots.
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
  image tag (for example `v4`) to force a new image build.
- GitHub-hosted runners are CPU-only. Use a self-hosted GPU or HPC runner for
  GPU FUNWAVE-TVD and larger operational domains.

## Plot translation

`report/beach_2d_radiation_plots.Rmd` is an R translation of the MATLAB
diagnostic scripts in `reference/`. It renders the instantaneous three-panel
plot from the fields produced by the workflow. The averaged momentum-balance
and vertical-profile sections are activated when the corresponding optional
FUNWAVE outputs are requested.

The workflow's `v3` image compiles FUNWAVE with `AB_OUTPUT`, which writes
`Ax`, `Ay`, `Bx` and `By`, and runs for 300 seconds. This passes the bundled
case's 180-second steady-state threshold and produces the radiation and
momentum-balance fields required by the translated MATLAB diagnostic plots.

`example_results/` in the delivery ZIP contains one compact test run so that
the Rmd can be rendered locally. It is ignored by Git and is not intended for
commit to the repository.

## Render an Actions result locally

Download and unzip a `funwave-results-<run-id>` artifact beside the repository.
In `report/forecast_report.Rmd`, point `results_dir` to that folder, for
example:

```r
results_dir <- normalizePath("../funwave-results-34550796372", mustWork = TRUE)
```

Then render it locally with:

```r
rmarkdown::render("report/forecast_report.Rmd")
```

## Notes

- Scheduled GitHub Actions workflows run from the default branch and can be
  delayed at busy times.
- Public GitHub Pages deployment is governed by the repository's Pages and
  Actions permissions; this workflow contains the permissions it requires.
