# Daily FUNWAVE-TVD test forecast

This starter repository runs a small FUNWAVE-TVD test each day, renders an R
Markdown results page, and deploys only the HTML report to GitHub Pages.

## What the workflow does

1. At 03:17 UTC each day, it checks for `ghcr.io/julianog/funwave-tvd:v1`.
2. If absent (or if **Run workflow** is used with **rebuild image**), it builds
   the Docker image and pushes it to GitHub Container Registry.
3. It runs the compact bundled `beach_2d_radiation` diagnostic, then a
   five-minute Port Fairy case using the committed DEM and current IMOS buoy
   forcing.
4. R Markdown publishes the Port Fairy report as `index.html`; the compact
   test diagnostic is also published as `beach_test.html`.
5. It retains model output as a private seven-day Actions artifact and
   publishes only the HTML pages to GitHub Pages.

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

## Port Fairy coarse latest-buoy case

`port_fairy/` contains a 20 m, five-minute first-pass setup for the supplied
pink Port Fairy domain. It crops the local Victorian DEM, reads the newest
usable IMOS Spotter observation, writes `DEPTH_TYPE = DATA` input and runs a
FUNWAVE `WK_IRR` irregular-wave source along the buoy-side edge of a rotated
local grid. See
[`port_fairy/README.md`](port_fairy/README.md) for the two local files to copy
into `port_fairy/data/`, build/run commands, and important forcing limitations.

The DEM must be committed at:

```text
port_fairy/data/VCDEM21_GDA2020_z54_Seamless_portFairy.tif
```

The Action downloads the latest available IMOS monthly Port Fairy buoy file
(falling back two months when necessary), so buoy NetCDF files are not stored in
the repository.

## Plot translation

`report/beach_2d_radiation_plots.Rmd` is an R translation of the MATLAB
diagnostic scripts in `reference/`. It renders the instantaneous three-panel
plot from the fields produced by the workflow. The averaged momentum-balance
and vertical-profile sections are activated when the corresponding optional
FUNWAVE outputs are requested.

The workflow's `v4` image compiles FUNWAVE with `AB_OUTPUT`, which writes
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
