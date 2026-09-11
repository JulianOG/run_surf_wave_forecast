# Port Fairy 15-minute WGS84 and animation update, v2

Copy these files over the matching files in the root of the
run_surf_wave_forecast repository, then commit and use Actions > Daily FUNWAVE
test and report > Run workflow.

This v2 update fixes the failed image build by installing gifski from CRAN with
Cargo/rustc. It:
- changes the coarse 20 m simulation to 15 minutes;
- rebuilds raw FUNWAVE matrices as georeferenced rotated Omerc rasters, then
  projects them to WGS84 for the HTML maps;
- writes rotated and WGS84 GeoTIFFs for eta, maximum WaveHeight and Hmax;
- creates two looping six-second Rmd GIFs: the full 15-minute eta run and the
  final one-sixth (12:30--15:00);
- uses Docker image tag v5, which will be rebuilt automatically because the
  previous v5 build failed.

The magenta polygon is the requested pink envelope. The black outline is the
actual rectangular FUNWAVE domain: FUNWAVE requires a rectangle, so the two
outlines are not expected to coincide exactly.

