# Port Fairy nearshore-wave forecast

This repository runs a daily experimental nearshore-wave simulation for Port
Fairy, Victoria using FUNWAVE-TVD. It combines the latest available Port Fairy
wave-buoy observation with a local bathymetry grid and publishes model
diagnostics as a GitHub Pages report.

The project is intended to demonstrate a reproducible workflow for turning
near-real-time offshore wave observations into a high-resolution nearshore
model diagnostic. It is not a navigation, public-safety, or emergency-warning
service.

## What the workflow does

Each daily run:

1. Builds and runs a compact upstream FUNWAVE-TVD test case.
2. Downloads the newest usable IMOS Port Fairy buoy record, with fallback to
   the two preceding monthly files.
3. Builds a 20 m rotated-grid Port Fairy case from the Victorian DEM.
4. Runs a 30-minute FUNWAVE-TVD simulation forced with a parametric irregular
   wave spectrum.
5. Publishes a report with bathymetry checks, forcing geometry, free-surface
   animations, interactive maps of the latest elevation and maximum elevation,
   and model provenance.
6. Writes stable GIF, PNG and `latest.json` assets for an optional separate
   social-media bot.

## Repository layout

| Location | Purpose |
| --- | --- |
| `.github/workflows/daily-forecast.yml` | Scheduled model, render and publishing workflow. |
| `Dockerfile` | Reproducible FUNWAVE-TVD and R environment. |
| `port_fairy/` | Port Fairy case preparation, local data and model outputs. |
| `report/port_fairy_report.Rmd` | Published Port Fairy diagnostic report. |
| `scripts/render_social_assets.R` | Standalone GIF and PNG renderer. |
| `scripts/write_latest_manifest.R` | Public metadata manifest writer. |
| `report/beach_2d_radiation_plots.Rmd` | Compact upstream FUNWAVE test diagnostic. |

## Published products

The GitHub Pages site contains the current Port Fairy report and the compact
test result. It also exposes stable social assets under `assets/` and a
machine-readable `latest.json` manifest. The manifest identifies the buoy
observation, model configuration, public asset URLs and whether the buoy QC
status permits an automated public post.

## Data and method

The Port Fairy case uses the Victorian seamless bathymetry/elevation DEM and
near-real-time Port Fairy wave-buoy observations from IMOS. The model uses a
local Oblique Mercator grid so the model x-axis runs from the offshore source
edge toward the coast. Raw FUNWAVE fields are reconstructed on that grid before
being transformed to WGS84 for maps and animations.

FUNWAVE's `WK_IRR` wavemaker is parameterised from observed significant wave
height, peak period, peak direction and directional spread. It represents a
parametric TMA/JONSWAP sea state, not a phase-resolved replay of the buoy or a
full directional spectrum.

See [the Port Fairy case documentation](port_fairy/README.md) for the model
domain, forcing, files and interpretation limits.

## Data acknowledgement

Data were sourced from Australia's Integrated Marine Observing System (IMOS),
which is enabled by the National Collaborative Research Infrastructure Strategy
(NCRIS). The Port Fairy wave data are collected and quality controlled by the
University of Western Australia and are an output of the Catching Oz Waves
project, supported by the Australian Research Data Commons (ARDC):
<https://doi.org/10.47486/DP748>. ARDC is funded by NCRIS.

Suggested data citation: *Deakin University (year of data downloaded), Wave
buoys Observations -- Australia -- near real-time, downloaded from the IMOS URL
on the date of download.*
