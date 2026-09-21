# Port Fairy FUNWAVE-TVD case

This directory contains the case preparation for the Port Fairy nearshore-wave
diagnostic. It turns the latest usable offshore buoy observation and a local
digital elevation model into a 5 m FUNWAVE-TVD simulation and supporting
geospatial diagnostics.

The published report is at <https://julianog.github.io/run_surf_wave_forecast/>.

## Domain and grid

The model domain is a rectangular local Oblique Mercator grid spanning the
offshore Port Fairy buoy-side boundary and the adjacent coast. The model x-axis
is oriented from the source edge toward the coast. The current demonstration
configuration uses 5 m cells and a 10-minute simulation, producing outputs at
15-second intervals. FUNWAVE saves 40 snapshots from 00:00 to 09:45; the full
animation deliberately skips the 00:00 initial condition, so it has 39 frames
from 00:15 to 09:45. The final-one-sixth animation is configured from 08:20
onward and therefore uses the available 08:30--09:45 snapshots.

FUNWAVE is decomposed into a 2 × 1 domain and launched with two MPI ranks,
matching the slots exposed inside the GitHub Actions container.

The DEM is resampled directly onto the complete rotated rectangle. FUNWAVE is
given positive water depth, with land and missing DEM cells set to zero so its
wet/dry treatment can keep them dry.

## Inputs and links

`data/VCDEM21_GDA2020_z54_Seamless_portFairy.tif` is the required local
bathymetry/elevation input.

The case preparation script downloads the current IMOS monthly Port Fairy
wave-parameter NetCDF file. If it is unavailable, it tries the two preceding
months. It selects the latest record with buoy quality-control status 1 or 2
and finite wave parameters. [AusWaves: Victorian waves](https://auswaves.org/vic-waves/)
is a useful public companion viewer for the regional wave conditions.

The selected forcing fields are:

| Buoy quantity | Use in the model |
| --- | --- |
| Significant wave height | `Hmo` |
| Peak period | `FreqPeak` |
| Mean wave direction (from) | Converted to model travel direction for `ThetaPeak`; peak direction is the fallback |
| Mean directional spread | `Sigma_Theta`; peak spread then 20° are fallbacks |

For each run, the script also reads hourly Portland water levels from the
[UHSLC fast-delivery archive](https://uhslc.soest.hawaii.edu/data/csv/fast/hourly/h129.csv).
The companion NetCDF metadata is checked to confirm the reference datum is
LAT. Portland's supplied tidal-datum information places LAT 0.597 m below AHD,
so the still water level applied to the depth grid is `CSV_mm / 1000 - 0.597`.
It is uniform over this small domain during a 10-minute simulation, including
the offshore boundary. The exact UTC record, datum and AHD value are retained
in `output/latest_buoy_forcing.csv`.

## Historical reports

Run **Actions → Historical Port Fairy reports → Run workflow** to produce one
or more reproducible cases. Enter Port Fairy local times separated by commas
or new lines, for example `2025-02-10 22:00`. The workflow converts each to
UTC, chooses the latest usable buoy record at or before that time, and writes a
separate downloadable artifact named `port-fairy-report-YYYYMMDDTHHMM-TZ`.
Each artifact contains its timestamped HTML report and its own map assets; it
does not overwrite the normal Pages forecast.

The currently published archives overlap from **September 2022 to July 2026**:
the Port Fairy IMOS monthly wave files start in September 2022 and the Portland
UHSLC hourly record presently extends through July 2026.

## Wave forcing

The model uses FUNWAVE's `WK_IRR` internal irregular wavemaker. It generates a
TMA/JONSWAP-style sea state a short distance inside the offshore source edge.
This is a practical first-pass representation based on integral buoy
parameters; it is not an open-boundary spectral forcing or a time-series replay
of the sea surface.

The generated forcing, grid geometry, bathymetry and source-direction checks
are written to `output/` for the report. A strongly oblique incident direction
is flagged because it requires careful interpretation.

## Wavemaker source width

`Delta_WK` is dimensionless: it scales with the daily peak wavelength rather
than being a distance in metres. This case fixes the *physical* active Gaussian
envelope at 50 m, measured from -2 to +2 e-folds (ten 5 m grid cells). The
script derives the daily `Delta_WK` from the peak wavelength at the actual
source depth. For a 200--300 m peak wavelength it is about 0.37--0.56.

The corresponding FUNWAVE `Width_WK` is 55.9 m and the paddle centre is
215.9 m from the source edge: 100 m source-side sponge, 60 m clear gap, then
the 55.9 m FUNWAVE width. This moves the narrower paddle 55.9 m seaward while
keeping the source outside the damping zone. It does not increase the
buoy-derived `Hmo`. Source width is therefore not a
substitute for calibration or a finer surf-zone grid.

The Norfolk and Saco cases are useful published configurations, but are not
one-to-one calibrations for Port Fairy: they use much finer grids and Saco Bay
uses `WK_NEW_IRR` rather than `WK_IRR`.

| Setting | Port Fairy | [Norfolk, Virginia field case](https://github.com/fengyanshi/Norfolk/blob/245e6d7bd082927f6a03921933db8b22f8263436/FUNWAVE/Work/input_mac.txt) | [Saco Bay field calibration](https://github.com/fengyanshi/BENCHMARK_FUNWAVE/blob/86ef91cfe2eec841ba2ba2776db058d8a08a95e4/SacoBay/saco_1/input.txt) |
| --- | --- | --- | --- |
| Grid spacing | 5 m | 1.5 m | 2 m |
| Wavemaker | `WK_IRR` | `WK_IRR` | `WK_NEW_IRR` |
| `Delta_WK` | Derived daily; typically 0.37–0.56 | 2.0 | 2.0 |
| Active source envelope | 50 m (10 cells) | About 67 m (45 cells) | About 162 m (81 cells) |
| `CFL` | 0.5 | 0.15 | 0.05 |
| Bottom drag `Cd` | 0.002 | 0.002 | 0.002 |
| `VISCOSITY_BREAKING` | `T` | `T` | `F` |
| `Cbrk1`, `Cbrk2` | 0.65, 0.35 | 0.45, 0.35 | 0.45, 0.35 |
| `FroudeCap` | 1.0 | 1.5 | 1.5 |
| `MinDepth` | 0.05 m | 0.001 m | 0.001 m |
| Lateral treatment | Non-periodic; 60 m north/south sponges | Periodic; south 0 m, north 200 m | Periodic; no north/south sponge |

The active envelope is the full distance from -2 to +2 Gaussian e-folds. See
the [FUNWAVE-TVD examples and benchmarks](https://github.com/fengyanshi/FUNWAVE-TVD/tree/master/benchmarks)
and the [internal-wavemaker implementation](https://github.com/fengyanshi/FUNWAVE-TVD/blob/b4c322e7582035ee19df8e6409a3dfedaff1cb96/src/wavemaker.F)
for further cases and implementation details.

## Propagation and controlled sensitivities

Halving the paddle is a controlled source-geometry change only. If widening or
narrowing the paddle does not improve coastward waves, source width is not the dominant loss
mechanism. Test one of the following at a time against the same buoy record,
and compare a cross-shore transect of `eta` or `Hrms` before choosing a daily
configuration.

1. **Numerical convergence:** test `CFL = 0.15` alone. It matches Norfolk and
   gives a smaller time step, but does not physically add energy. A material
   change from the current `CFL = 0.5` identifies a time-step sensitivity;
   it will take roughly three times longer to run.
2. **Bottom friction:** this configuration uses `Cd = 0.002`, matching both
   comparison cases and 20% lower than the preceding Port Fairy sensitivity.
   It may retain more wave energy, particularly in shallow water, but should
   be chosen against data rather than set to zero.
3. **Breaking model:** do not set `VISCOSITY_BREAKING = F` merely to make
   waves bigger. In FUNWAVE this switches from eddy-viscosity breaking to the
   shock-capturing option; it does **not** turn breaking off. It is a useful
   separate sensitivity because Saco Bay uses it, but it changes where and how
   waves dissipate. The [official example comments](https://github.com/fengyanshi/FUNWAVE-TVD/blob/b4c322e7582035ee19df8e6409a3dfedaff1cb96/simple_cases/tide_frf_abc_data/work/input.txt)
   describe the two alternatives.
4. **Breaking thresholds:** leave `Cbrk1 = 0.65` as the initial value. In the
   [breaker source](https://github.com/fengyanshi/FUNWAVE-TVD/blob/b4c322e7582035ee19df8e6409a3dfedaff1cb96/src/breaker.F), it sets the
   threshold for starting breaking, so lowering it toward 0.45 tends to start
   breaking earlier rather than preserve larger nearshore elevations.
5. **Resolution and side losses:** this 5 m grid is still 2.5–3.3 times coarser
   than the comparison studies. It is the next physical sensitivity after the
   10 m case; a finer nearshore nest is the subsequent test if feasible. Also
   inspect energy near the north/south sponges: oblique components from
   directional spreading can be absorbed there. FUNWAVE author Jim Kirby notes
   that 1–2 m grids are normally used for comparable nearshore work in a
   [field-case discussion](https://groups.google.com/g/funwave-tvd/c/DmQelxOu5kw).

Do not combine a smaller `CFL`, lower `Cd`, and a different breaking model in
the same first rerun: that would not identify which setting altered the
coastward wave field.

## Outputs

`output/input.txt` and `output/depth.txt` are the FUNWAVE inputs. Model fields
are written to `output/results/`. The report reads these fields, applies both
the DEM-derived water mask and the FUNWAVE wet/dry mask before geographic
reprojection, and reapplies nearest-neighbour versions of those masks in WGS84.
For public wave products it also sets all cells seaward of the internal
wavemaker to `NA`; this is a display mask and does not change the simulation.
Interactive maps are restricted to the local model extent and shown at a
compact height. The maximum-elevation diagnostic is the cellwise maximum of
all saved `eta` fields, not an estimate of individual-wave height.

The public maps and animations use the ColorBrewer Yellow–Green–Blue palette.
Eta products have a fixed -5 to 5 m range and peak simulated significant-wave
height uses a fixed 0 to 4 m range. The latest-eta map has OpenStreetMap and
satellite-imagery base layers. A standalone interactive eta time series shows
five FUNWAVE stations along the buoy-to-nearshore transect ending at
142.2456520° E, 38.3789015° S.

Each transect station is an integer FUNWAVE grid cell written directly to a
native `sta_####` file every second; the report neither samples map rasters nor
interpolates the station time series. The offshore/buoy end is dark blue and
the nearshore end is yellow. The interactive station plot is shown as its own
final report section.

The report also includes an interactive local-domain mean-current map. It
averages the final 60 seconds of native FUNWAVE `u`/`v` output, traces animated
streamlines, and provides OpenStreetMap, satellite imagery, and a streamline
layer toggle.

## Interpretation limits

This case is an experimental model diagnostic. Its 5 m grid improves the
representation of nearshore bathymetry and breaking relative to the earlier
20 m case, but it remains too coarse for detailed surf-zone processes,
individual structures, navigation or safety decisions. A higher-resolution,
calibrated configuration and full directional spectral boundary forcing would
be required for those applications.
