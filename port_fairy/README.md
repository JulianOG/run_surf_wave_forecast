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

## Inputs

`data/VCDEM21_GDA2020_z54_Seamless_portFairy.tif` is the required local
bathymetry/elevation input.

The case preparation script downloads the current IMOS monthly Port Fairy
wave-parameter NetCDF file. If it is unavailable, it tries the two preceding
months. It selects the latest record with buoy quality-control status 1 or 2
and finite wave parameters.

The selected forcing fields are:

| Buoy quantity | Use in the model |
| --- | --- |
| Significant wave height | `Hmo` |
| Peak period | `FreqPeak` |
| Peak wave direction (from) | Converted to model travel direction for `ThetaPeak` |
| Peak directional spread | `Sigma_Theta`, with a 20° fallback |

## Wave forcing

The model uses FUNWAVE's `WK_IRR` internal irregular wavemaker. It generates a
TMA/JONSWAP-style sea state a short distance inside the offshore source edge.
This is a practical first-pass representation based on integral buoy
parameters; it is not an open-boundary spectral forcing or a time-series replay
of the sea surface.

The generated forcing, grid geometry, bathymetry and source-direction checks
are written to `output/` for the report. A strongly oblique incident direction
is flagged because it requires careful interpretation.

## Outputs

`output/input.txt` and `output/depth.txt` are the FUNWAVE inputs. Model fields
are written to `output/results/`. The report reads these fields, applies the
FUNWAVE wet/dry mask before and after geographic reprojection, and produces
maps in WGS84. The maximum-elevation diagnostic is the cellwise maximum of all
saved `eta` fields, not an estimate of individual-wave height.

## Interpretation limits

This case is an experimental model diagnostic. Its 20 m grid is suitable for
workflow development and broad nearshore patterns, but it is too coarse for
detailed surf-zone processes, individual structures, navigation or safety
decisions. A higher-resolution, calibrated configuration and full directional
spectral boundary forcing would be required for those applications.
