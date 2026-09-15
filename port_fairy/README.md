# Port Fairy FUNWAVE-TVD case

This directory contains the case preparation for the Port Fairy nearshore-wave
diagnostic. It turns the latest usable offshore buoy observation and a local
digital elevation model into a 20 m FUNWAVE-TVD simulation and supporting
geospatial diagnostics.

## Domain and grid

The model domain is a rectangular local Oblique Mercator grid spanning the
offshore Port Fairy buoy-side boundary and the adjacent coast. The model x-axis
is oriented from the source edge toward the coast. The current demonstration
configuration uses 20 m cells and a 30-minute simulation, producing outputs at
7.5-second intervals.

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
than being a distance in metres. This case fixes it at `2.0`, a moderate value
used by the published Norfolk and Saco Bay FUNWAVE field examples. The script
calculates the peak wavelength at the wavemaker depth, then sets
`Width_WK = Delta_WK * Lp / 2` and moves the paddle far enough from the
source-side sponge that the full source half-width is outside the damping zone.

The reported active Gaussian width is the distance from -2 to +2 e-folds. For
the usual 200--300 m peak wavelength on this 20 m grid, it is roughly
180--270 m (9--14 cells). This is deliberately wide enough to resolve the
source without making the `WK_IRR` source normalisation unstable. It does not
increase the buoy-derived `Hmo` and is not a substitute for calibration or a
finer surf-zone grid.

| Case | Grid spacing | `Delta_WK` | Active Gaussian source width | Width in cells |
| --- | ---: | ---: | ---: | ---: |
| Port Fairy `WK_IRR` configuration | 20 m | 2.0 | About 180–270 m for 200–300 m peak wavelengths | 9–14 |
| [Norfolk, Virginia field case](https://github.com/fengyanshi/Norfolk/blob/245e6d7bd082927f6a03921933db8b22f8263436/FUNWAVE/Work/input_mac.txt) | 1.5 m | 2.0 | 67 m | 45 |
| [Saco Bay field calibration](https://github.com/fengyanshi/BENCHMARK_FUNWAVE/blob/86ef91cfe2eec841ba2ba2776db058d8a08a95e4/SacoBay/saco_1/input.txt) | 2 m | 2.0 | 162 m | 81 |

The active width is the full distance from -2 to +2 Gaussian e-folds. The
Norfolk case uses `WK_IRR`; Saco Bay uses the newer `WK_NEW_IRR`, so it is a
source-resolution comparison rather than an identical configuration. See the
[FUNWAVE-TVD examples and benchmarks](https://github.com/fengyanshi/FUNWAVE-TVD/tree/master/benchmarks)
and the [FUNWAVE internal-wavemaker formulation](https://github.com/fengyanshi/FUNWAVE-TVD/blob/b4c322e7582035ee19df8e6409a3dfedaff1cb96/src/wavemaker.F)
for further cases and implementation details.

## Outputs

`output/input.txt` and `output/depth.txt` are the FUNWAVE inputs. Model fields
are written to `output/results/`. The report reads these fields, applies both
the DEM-derived water mask and the FUNWAVE wet/dry mask before geographic
reprojection, and reapplies nearest-neighbour versions of those masks in WGS84.
Interactive maps are restricted to the local model extent and shown at a
compact height. The maximum-elevation diagnostic is the cellwise maximum of
all saved `eta` fields, not an estimate of individual-wave height.

## Interpretation limits

This case is an experimental model diagnostic. Its 20 m grid is suitable for
workflow development and broad nearshore patterns, but it is too coarse for
detailed surf-zone processes, individual structures, navigation or safety
decisions. A higher-resolution, calibrated configuration and full directional
spectral boundary forcing would be required for those applications.
