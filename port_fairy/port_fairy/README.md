# Port Fairy: coarse latest-buoy FUNWAVE setup

This is a **first-pass 5-minute, 20 m resolution** case for the pink domain in
the supplied map. It uses a local Oblique Mercator projection, with model +x
running from the buoy-side pink edge toward the Port Fairy coast. It is small
enough to debug on a laptop or GitHub runner before using 10 m or 5 m
bathymetry.

## Input files

Commit this DEM into `port_fairy/data/`:

```text
VCDEM21_GDA2020_z54_Seamless_portFairy.tif
```

The script downloads the current month's IMOS monthly file automatically. If it
is not yet available, it falls back to either of the two preceding months.

## Build and run

From the repository root:

```r
source("port_fairy/setup_port_fairy_funwave.R")
```

This creates `port_fairy/output/depth.txt`, `input.txt`, 20 m positive-depth
and elevation GeoTIFFs, rotated pink-domain vertices, and CSV files recording
the selected latest buoy observation and grid.

Then run locally:

```bash
bash port_fairy/run_port_fairy.sh
```

Results are written to `port_fairy/output/results/`.

The repository's daily Action performs these same steps after the compact
upstream FUNWAVE test. It uploads both result sets as an artifact and publishes
the Port Fairy HTML report to GitHub Pages.

## What is and is not represented

FUNWAVE's `WK_IRR` is an *internal* irregular-wave source line placed 120 m
inside the buoy-side long pink edge, rather than a true open boundary. The available
monthly IMOS file contains only Hs, peak period and peak direction, so the
script creates a TMA/JONSWAP-style spectrum from those three quantities. It
does not reproduce the buoy's phase-resolved sea surface or directional
spectrum.

Before treating outputs as a forecast, inspect the generated
`depth_20m_positive_water_depth.tif` and check the warning about incident-wave
direction. If the latest waves enter principally from the south, a rotated or
south-boundary grid is the next improvement. For real boundary forcing, obtain
the Spotter directional spectrum (or a calibrated offshore WW3 spectrum), then
use FUNWAVE `WK_TIME_SERIES` / spectrum components.
