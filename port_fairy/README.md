# Port Fairy FUNWAVE-TVD case

This directory contains the input preparation for the Port Fairy experimental
nearshore-wave diagnostics. The main report is published at
<https://julianog.github.io/run_surf_wave_forecast/>.

The case converts an observed offshore sea state, a Portland still-water level
and a Victorian elevation/bathymetry DEM into a short, phase-resolving
FUNWAVE-TVD simulation. It is a research diagnostic, not a navigation,
public-safety or emergency-warning product.

## Directory contents

| Path | Purpose |
| --- | --- |
| setup_port_fairy_funwave.R | Creates the rotated grid, depth.txt, input.txt, stations and run metadata |
| data/VCDEM21_GDA2020_z54_Seamless_portFairy.tif | Required local Victorian DEM |
| data/h129.csv | Committed Portland hourly UHSLC record |
| data/h129.nc | UHSLC NetCDF copy retained for reference |
| output/ | Generated FUNWAVE input, fields, reports and metadata; not a source-data directory |

The setup script is run by GitHub Actions from the repository root. It writes
all model inputs to output/ and never modifies the source DEM.

## Grid and simulation modes

The grid is a complete rectangular local Oblique Mercator domain. Its x-axis is
always oriented from the buoy-side wavemaker edge toward the coast. The
rectangular FUNWAVE fields are reconstructed in this rotated grid, then
reprojected to WGS84 only for maps and published rasters.

| Run type | Numerical grid | Public report grid | Duration | Fields |
| --- | --- | --- | --- | --- |
| Daily | 5 m × 5 m | 5 m | 600 s | 15 s snapshots |
| Historical | 2.5 m cross-shore × 10 m alongshore | 10 m × 10 m | 600 s | 15 s snapshots |

Historical aggregation only affects report products. FUNWAVE always calculates
on its native grid. A historical log label of “2.5 m × 1 m” was formatting
only: the 10 m alongshore spacing is retained numerically and is now labelled
correctly.

FUNWAVE uses two MPI ranks with a 2 × 1 decomposition in both workflows.

## Wave forcing and wavemaker

The selected IMOS buoy record supplies significant wave height, peak period,
direction and directional spread. The model creates an irregular WK_IRR
TMA/JONSWAP-style wave field:

| Observation | FUNWAVE use |
| --- | --- |
| Significant wave height | Hmo |
| Peak period | FreqPeak |
| Mean direction-from | Converted to model travel direction for ThetaPeak; peak direction is fallback |
| Mean directional spread | Sigma_Theta; peak spread, then 20°, are fallbacks |

The numerical source is a line wavemaker across the buoy-side model boundary.
Its cross-shore Gaussian envelope is 50 m wide, located beyond a 100 m
source-side sponge and a 60 m clear gap. Delta_WK is derived from the selected
peak wavelength, rather than treated as a fixed distance. This source
parameterisation represents the integral buoy sea state; it is not a
phase-resolved buoy replay or a full two-dimensional spectrum.

Strongly oblique source directions are retained but flagged in metadata and
should be interpreted cautiously because lateral sponges can absorb part of
the directional wave field.

## Water level and bathymetry

The DEM is resampled directly to the full model rectangle. Elevation is
converted to positive water depth after adding the selected still-water level.
Land, missing DEM cells and negative depths are written as zero for FUNWAVE
wet/dry handling.

The workflow refreshes the Portland UHSLC h129 CSV before preparation. The
script then checks h129_current.csv, h129.csv and the legacy filename in that
order, selecting the closest valid hourly record within 90 minutes of the
buoy observation. CSV millimetres are assumed to be relative to LAT:

AHD water level (m) = CSV water level (mm) / 1000 − 0.597

The applied record time, LAT value, AHD value and datum assumption are written
to output/latest_buoy_forcing.csv. If no contemporaneous record exists, the
case explicitly warns and uses a 0.000 m AHD fallback; it does not substitute
an unrelated tide observation.

## Shallow-water treatment

| Control | Value | Role |
| --- | --- | --- |
| MinDepth | 0.10 m | Wet/dry threshold |
| MinDepthFrc | 0.10 m | Numerical depth floor in momentum, CFL and friction terms |
| Cd | 0.002 | Quadratic bottom drag |
| CFL | 0.5 | Adaptive time-step control |
| FroudeCap | 1.0 | Limits unrealistically fast shallow flow |
| VISCOSITY_BREAKING | T | Eddy-viscosity breaking option |
| Cbrk1, Cbrk2 | 0.65, 0.35 | Breaking coefficients |

`MinDepth` and `MinDepthFrc` have different conceptual roles, but this pinned
FUNWAVE-TVD revision merges them to their smaller value during input parsing.
They must therefore be set identically. The case uses 0.10 m for both, so
thin-water momentum, CFL and wet/dry calculations share a real numerical
floor. Severe observed seas (`Hs >= 4 m`) use a 20-peak-period source ramp
rather than the normal 10 peak periods; this reduces only the start-up
transient and does not cap the requested Hs.

## Outputs and display rules

FUNWAVE writes depth.txt, input.txt, eta, Hsig, Umean, Vmean, MASK and station
files under output/. The report:

- reconstructs raw model matrices on the native rotated grid;
- applies both DEM and FUNWAVE wet/dry masks before WGS84 projection;
- masks seaward-of-wavemaker values in public coastal products;
- shows latest eta, maximum positive eta and maximum Hsig as separate
  diagnostics;
- uses a fixed −5 to 5 m eta scale and 0 to 4 m Hsig scale;
- writes 6-second full-run and final-one-sixth GIFs, excluding the 00:00
  initial frame from the full animation;
- defaults interactive maps to satellite imagery, with OpenStreetMap available
  through the layer control;
- limits interactive maps to the local model area.

Maximum eta is the cellwise maximum positive elevation across saved eta frames.
It is not individual wave height. The Hsig product comes from FUNWAVE’s
mean-wave diagnostic and is the appropriate public wave-height map.

Five stations follow the requested buoy-to-nearshore transect ending at
142.2456520° E, −38.3789015° S. Each is snapped once to an integer FUNWAVE
grid cell and written directly to a station file every second. The report does
not interpolate these time series.

Current pages use Umean/Vmean, not phase-resolved U/V. The vector components
are smoothed spatially before visualisation, and the wavemaker neighbourhood
is excluded from current particle seeding so numerical-source circulation is
not presented as nearshore flow.

## Historical reports

Use **Actions → Historical Port Fairy reports → Run workflow**. Enter one or
more Port Fairy local times separated by commas or new lines, for example
2025-02-10 22:00. Each time is converted using the Australia/Melbourne zone,
matched to a buoy observation at or before that time, and rendered into an
independent timestamped artifact.

Historical reports contain seven-day observed Hs, peak period, direction and
Portland water-level context around the requested time. They do not overwrite
the daily GitHub Pages report.

## Reference configurations

The Port Fairy configuration is deliberately not a direct copy of another
site. These useful FUNWAVE cases provide benchmarks for parameter
sensitivities, not Port Fairy calibration:

| Setting | Port Fairy daily | [Norfolk field case](https://github.com/fengyanshi/Norfolk/blob/245e6d7bd082927f6a03921933db8b22f8263436/FUNWAVE/Work/input_mac.txt) | [Saco Bay calibration](https://github.com/fengyanshi/BENCHMARK_FUNWAVE/blob/86ef91cfe2eec841ba2ba2776db058d8a08a95e4/SacoBay/saco_1/input.txt) |
| --- | --- | --- | --- |
| Grid spacing | 5 m × 5 m | 1.5 m | 2 m |
| Wavemaker | WK_IRR | WK_IRR | WK_NEW_IRR |
| Cd | 0.002 | 0.002 | 0.002 |
| CFL | 0.5 | 0.15 | 0.05 |
| MinDepth | 0.10 m | 0.001 m | 0.001 m |
| Breaking viscosity | T | T | F |

The [FUNWAVE-TVD examples and benchmarks](https://github.com/fengyanshi/FUNWAVE-TVD/tree/master/benchmarks)
and [AusWaves Victorian waves](https://auswaves.org/vic-waves/) are useful
context for testing and interpreting this demonstration case.

## Interpretation limits

The 5 m daily grid is a substantial improvement over the earlier 20 m
experiments, but it remains a demonstration of nearshore wave propagation,
breaking and wave-driven circulation. It is not calibrated for detailed
surf-zone processes, infrastructure impacts, navigation or life-safety
decisions. Those uses require local validation, sensitivity testing and a
higher-resolution, spectrally forced model configuration.
