# Port Fairy GIF timing fix

This is a **two-file patch only**. It contains no starter ZIP, no DEM and no
other repository files.

Overlay the contents of this folder onto the root of
`JulianOG/run_surf_wave_forecast`, replacing:

- `scripts/render_social_assets.R`
- `report/port_fairy_report.Rmd`

Then commit, push and run **Daily FUNWAVE test and report**.

## What it fixes

FUNWAVE names fields `eta_00000`, `eta_00001`, … using sequential output-file
numbers. With `PLOT_INTV = 30`, file `eta_00050` represents model time
1500 seconds, not 50 seconds. The previous code compared the file number with
1500 seconds, so it selected no frames for the final one-sixth GIF.

The corrected code calculates model time as:

```r
eta_time <- eta_file_number * grid$plot_intv_s
```

For the 30-minute run this selects files 50--59 for the final 5-minute GIF.
It also corrects the elapsed-time labels in both animations and in the report.
