# Port Fairy nearshore-wave diagnostics

This repository runs an experimental nearshore-wave model for Port Fairy,
Victoria. It combines the latest usable Port Fairy wave-buoy observation,
Portland water level and local Victorian bathymetry to generate a
FUNWAVE-TVD diagnostic and publish it at
<https://julianog.github.io/run_surf_wave_forecast/>.

The site is a research and workflow demonstration. It is not an operational
forecast, navigation aid, public-safety product or emergency-warning service.

## Products

The live GitHub Pages report provides:

- selected buoy forcing and Portland still-water level;
- 6-second animations of simulated free-surface elevation for the full run and
  its final sixth;
- interactive local WGS84 maps of latest elevation, maximum positive elevation
  and peak simulated significant wave height;
- five exact FUNWAVE grid-point elevation records from the buoy-to-nearshore
  transect;
- diagnostic current pages based on smoothed FUNWAVE Umean/Vmean fields,
  including streamlines, particle trails, Earth-style particles and
  Leaflet.Velocity;
- provenance, forcing geometry and interpretation information.

Stable social assets are written below the Pages assets directory, alongside
latest.json for a separate posting bot. The normal report remains the source of
truth for interpretation.

## Workflows

| Workflow | Purpose | Configuration |
| --- | --- | --- |
| Daily FUNWAVE test and report | Scheduled daily at 03:17 UTC, with manual dispatch available | 5 m × 5 m grid; 10-minute run; output every 15 s |
| Historical Port Fairy reports | Manual workflow for one or more Port Fairy local dates | 2.5 m cross-shore × 10 m alongshore grid; public fields aggregated to 10 m; separate timestamped artifacts |
| Compact upstream test | Runs as part of the daily workflow | Confirms the pinned FUNWAVE executable before the Port Fairy case |

Both Port Fairy workflows run FUNWAVE with two MPI ranks. The daily workflow
publishes the Pages report; historical runs publish downloadable artifacts and
do not replace the live forecast.

## Model method

The case is built in a local Oblique Mercator projection. The model x-axis is
reordered on every run to point from the buoy-side source edge toward the
coast. FUNWAVE fields are reconstructed in that native rotated grid before
being projected to WGS84 for maps and animations.

The model uses the internal irregular wavemaker, WK_IRR. Significant wave
height, peak period, wave direction and directional spread form a parametric
TMA/JONSWAP-style sea state. This is not a replay of the observed surface
elevation, a full directional-spectrum boundary condition or an externally
validated operational forecast.

The case uses:

| Control | Value |
| --- | --- |
| Bottom drag, Cd | 0.002 |
| CFL | 0.5 |
| Wet/dry and numerical minimum depth | 0.10 m |
| Breaking | Eddy-viscosity scheme; Cbrk1 = 0.65, Cbrk2 = 0.35 |
| Wavemaker cross-shore envelope | 50 m, clear of the source-side sponge |
| Wavemaker ramp | 10 peak periods; 20 peak periods when Hs is 4 m or greater |
| Output interval | 15 s |
| Mean-current averaging window | 480 s after a 100 s spin-up |

In the pinned FUNWAVE-TVD revision, `MinDepth` and `MinDepthFrc` are merged to
their smaller value during input parsing. They therefore have to be equal. The
case uses a 10 cm wet/dry and numerical floor; it does not reduce the imposed
wave height. For severe observed seas (`Hs >= 4 m`), the 20-peak-period ramp
delays source start-up without reducing the observed forcing. In the 10-minute
case, the 5.29 m, 20.5 s historical sea state reaches 99.98% of its requested
amplitude by the end of the simulation.

## Data

The required bathymetry is
port_fairy/data/VCDEM21_GDA2020_z54_Seamless_portFairy.tif. It is not included
in generated update archives.

Wave parameters are obtained from IMOS Port Fairy NetCDF records. The daily
workflow checks the current month and preceding monthly files. Historical
runs discover the public AODN delayed-mode archive and use realtime data only
when delayed data are not yet available.

Portland hourly water levels use UHSLC station h129. The workflow refreshes
h129_current.csv, then falls back to the committed h129.csv. Values are
assumed to be LAT and converted as AHD = LAT − 0.597 m. A run records the
selected tide time and value; it does not extrapolate a stale tide record.

See the detailed [Port Fairy case documentation](port_fairy/README.md) for the
domain, files, masks, historical workflow and interpretation limits.

## Repository layout

| Location | Role |
| --- | --- |
| .github/workflows/daily-forecast.yml | Scheduled live forecast, render and Pages deployment |
| .github/workflows/historical-port-fairy.yml | Date-specific historical reporting |
| Dockerfile | Pinned FUNWAVE-TVD/MPI image only |
| port_fairy/setup_port_fairy_funwave.R | Builds bathymetry, forcing, tide level, grid, stations and input.txt |
| port_fairy/data/ | Committed tide data and required local DEM |
| report/port_fairy_report.Rmd | Main Pages and historical report |
| scripts/render_social_assets.R | Writes standalone GIF and PNG assets |
| scripts/write_latest_manifest.R | Writes latest.json |

R packages are installed on the GitHub Actions runner. The Docker image is
intentionally limited to FUNWAVE and MPI.

## Data acknowledgement

Wave data are sourced from Australia’s Integrated Marine Observing System
(IMOS), enabled by the National Collaborative Research Infrastructure Strategy
(NCRIS). The Port Fairy wave data are collected and quality controlled by the
University of Western Australia and are an output of the Catching Oz Waves
project, supported by the Australian Research Data Commons (ARDC):
<https://doi.org/10.47486/DP748>. ARDC is funded by NCRIS.

Suggested citation: Deakin University [year of data downloaded], *Wave buoys
Observations – Australia – near real-time*, downloaded from the relevant IMOS
URL on the date of download.
