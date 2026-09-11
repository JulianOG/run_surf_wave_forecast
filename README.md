# Port Fairy social-manifest and annotated-animation update

Copy these files over the matching files in the root of the
run_surf_wave_forecast repository, then commit and use Actions > Daily FUNWAVE
test and report > Run workflow.

This update keeps the verified GIF Docker image and:
- changes the coarse 20 m simulation to 30 minutes;
- rebuilds raw FUNWAVE matrices as georeferenced rotated Omerc rasters, then
  projects them to WGS84 for the HTML maps;
- writes rotated and WGS84 GeoTIFFs for eta, maximum WaveHeight and Hmax;
- uses one fixed elevation colour scale for all frames in both looping
  six-second Rmd GIFs: the full 30-minute eta run and the final one-sixth
  (25:00--30:00);
- maps the cellwise maximum of every `WaveHeight` output over the 30-minute
  run (rather than using FUNWAVE `Hmax`, which is elevation);
- removes the magenta polygon from the report maps while retaining the black
  FUNWAVE grid outline and the buoy marker;
- uses the verified Docker image tag v6.

It also makes a separate social-feed bot possible without granting it access to
this modelling repository. After a successful render, the workflow publishes:

- `latest.json` at the GitHub Pages root, containing the buoy, model and QC
  metadata plus stable public asset URLs;
- `assets/port-fairy-full.gif` and `assets/port-fairy-final-sixth.gif`;
- `assets/port-fairy-maximum-waveheight.png`.

The GIF frames show Port Fairy local date/time, model elapsed time, buoy Hs,
Tp, observed *from* direction, and a red arrow in the corresponding wave
travel direction. `latest.json` marks only QC 1 observations as eligible for
automatic public posting.

The internal model-grid geometry is unchanged; only the report’s magenta
display polygon has been removed.
