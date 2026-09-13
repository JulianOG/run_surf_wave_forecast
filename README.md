# Port Fairy v12 correction patch

This is deliberately **not** a repository snapshot and contains no nested ZIP.

From the root of your local `run_surf_wave_forecast` checkout, copy the `fixes`
folder there and run:

```r
source("fixes/apply_port_fairy_v12.R")
```

Then inspect and commit the four changed files:

```sh
git diff -- port_fairy/setup_port_fairy_funwave.R report/port_fairy_report.Rmd scripts/render_social_assets.R scripts/write_latest_manifest.R
git add port_fairy/setup_port_fairy_funwave.R report/port_fairy_report.Rmd scripts/render_social_assets.R scripts/write_latest_manifest.R
git commit -m "Fix Port Fairy colour scales, Hs diagnostic and source forcing"
git push
```

Changes made:

- writes FUNWAVE outputs every 7.5 seconds (four times the former rate);
- uses `range=` for all `terra::plot()` colour scales;
- reads FUNWAVE's actual `Hrms_#####` output and maps the peak simulated
  significant-wave-height estimate (`sqrt(2) * Hrms`), rather than treating
  maximum surface elevation as a wave height;
- removes the sponge from the wavemaker edge, while retaining it at the far and
  lateral boundaries;
- reads the buoy's peak directional spread (`WPDS`) and uses it as the first-pass
  `Sigma_Theta` input for the `WK_IRR` source. A 20 degree default is retained
  only if `WPDS` is missing or invalid.
