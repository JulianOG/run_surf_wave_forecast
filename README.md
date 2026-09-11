# Port Fairy 30-minute animation and maximum-wave-height update

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

The internal model-grid geometry is unchanged; only the report’s magenta
display polygon has been removed.
