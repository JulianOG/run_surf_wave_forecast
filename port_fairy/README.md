# Port Fairy FUNWAVE-TVD case

This directory contains the case preparation for the Port Fairy nearshore-wave
diagnostic. It turns the latest usable offshore buoy observation and a local
digital elevation model into a 10 m FUNWAVE-TVD simulation and supporting
geospatial diagnostics.

## Domain and grid

The model domain is a rectangular local Oblique Mercator grid spanning the
offshore Port Fairy buoy-side boundary and the adjacent coast. The model x-axis
is oriented from the source edge toward the coast. The current demonstration
configuration uses 10 m cells and a 15-minute simulation, producing outputs at
7.5-second intervals. The full animation therefore has 120 frames. The
final-one-sixth animation is selected from 12:30 onward; its last saved frame
is 14:52.5 because FUNWAVE writes the final pre-end-time snapshot at this
output cadence.

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
than being a distance in metres. This case fixes the *physical* active Gaussian
envelope at 100 m, measured from -2 to +2 e-folds (ten 10 m grid cells). The
script derives the daily `Delta_WK` from the peak wavelength at the actual
source depth. For a 200--300 m peak wavelength it is about 0.75--1.12.

The corresponding FUNWAVE `Width_WK` is 111.8 m and the paddle centre is
271.8 m from the source edge: 100 m source-side sponge, 60 m clear gap, then
the 111.8 m FUNWAVE width. This keeps the source outside the damping zone but
does not increase the buoy-derived `Hmo`. Source width is therefore not a
substitute for calibration or a finer surf-zone grid.

The Norfolk and Saco cases are useful published configurations, but are not
one-to-one calibrations for Port Fairy: they use much finer grids and Saco Bay
uses `WK_NEW_IRR` rather than `WK_IRR`.

| Setting | Port Fairy | [Norfolk, Virginia field case](https://github.com/fengyanshi/Norfolk/blob/245e6d7bd082927f6a03921933db8b22f8263436/FUNWAVE/Work/input_mac.txt) | [Saco Bay field calibration](https://github.com/fengyanshi/BENCHMARK_FUNWAVE/blob/86ef91cfe2eec841ba2ba2776db058d8a08a95e4/SacoBay/saco_1/input.txt) |
| --- | --- | --- | --- |
| Grid spacing | 10 m | 1.5 m | 2 m |
| Wavemaker | `WK_IRR` | `WK_IRR` | `WK_NEW_IRR` |
| `Delta_WK` | Derived daily; typically 0.75–1.12 | 2.0 | 2.0 |
| Active source envelope | 100 m (10 cells) | About 67 m (45 cells) | About 162 m (81 cells) |
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

Restoring the 100 m source envelope is a baseline change only. If widening the
paddle did not improve coastward waves, source width is not the dominant loss
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
5. **Resolution and side losses:** this 10 m grid is still 5–7 times coarser
   than the comparison studies. It is the next physical sensitivity after the
   20 m case; a 5 m nearshore nest is the subsequent test if feasible. Also
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
Interactive maps are restricted to the local model extent and shown at a
compact height. The maximum-elevation diagnostic is the cellwise maximum of
all saved `eta` fields, not an estimate of individual-wave height.

## Interpretation limits

This case is an experimental model diagnostic. Its 10 m grid improves the
representation of nearshore bathymetry and breaking relative to the earlier
20 m case, but it remains too coarse for detailed surf-zone processes,
individual structures, navigation or safety decisions. A higher-resolution,
calibrated configuration and full directional spectral boundary forcing would
be required for those applications.
