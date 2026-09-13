#!/usr/bin/env Rscript

# Build a first, deliberately coarse (20 m) 30-minute FUNWAVE-TVD case for
# Port Fairy from the Victorian DEM and the newest usable Spotter observation.
#
# The model uses an Oblique Mercator grid. Its +x direction is perpendicular to
# the long buoy-side model boundary, pointing from that edge toward the coast.
# This makes the FUNWAVE internal irregular wavemaker span the offshore boundary.
# FUNWAVE's depth file is written as [model x, model y], not GIS row/column
# order.

suppressPackageStartupMessages({
  library(ncdf4)
  library(terra)
})

root <- normalizePath(file.path(getwd(), "port_fairy"), mustWork = TRUE)
data_dir <- file.path(root, "data")
out_dir <- file.path(root, "output")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Commit the DEM using this name. The monthly IMOS buoy file is downloaded at
# runtime and deliberately remains outside Git.
bathy_file <- file.path(data_dir, "VCDEM21_GDA2020_z54_Seamless_portFairy.tif")
if (!file.exists(bathy_file)) {
  stop("Bathymetry is missing: ", bathy_file)
}

# Try this month, then the two preceding months. This avoids failing on the
# first day of a month before the newest near-real-time file is available.
download_buoy_month <- function(month_start, data_dir) {
  # `for (x in Date_vector)` drops the Date class in R, so coerce defensively.
  month_start <- as.Date(month_start, origin = "1970-01-01")
  ymd <- format(month_start, "%Y%m01")
  yyyy <- format(month_start, "%Y")
  url <- paste0(
    "https://imos-data.s3-ap-southeast-2.amazonaws.com/",
    "Deakin_University/WAVE-BUOYS/REALTIME/WAVE-PARAMETERS/PORT-FAIRY/",
    yyyy, "/VIC-DEAKIN-UNI_", ymd,
    "_PORT-FAIRY_RT_WAVE-PARAMETERS_monthly.nc"
  )
  destination <- file.path(data_dir, basename(url))
  temporary <- paste0(destination, ".download")

  if (file.exists(destination) && file.info(destination)$size > 1000) {
    return(destination)
  }

  status <- tryCatch(
    utils::download.file(url, temporary, mode = "wb", quiet = TRUE),
    error = function(e) 1L
  )
  if (isTRUE(status == 0) && file.exists(temporary) &&
      file.info(temporary)$size > 1000) {
    if (file.exists(destination)) unlink(destination)
    if (file.rename(temporary, destination)) return(destination)
  }
  if (file.exists(temporary)) unlink(temporary)
  NULL
}

month_starts <- seq(
  as.Date(format(Sys.time(), "%Y-%m-01")),
  by = "-1 month", length.out = 3
)
buoy_file <- NULL
for (month_index in seq_along(month_starts)) {
  buoy_file <- download_buoy_month(month_starts[month_index], data_dir)
  if (!is.null(buoy_file)) break
}
if (is.null(buoy_file)) {
  stop("Could not download a current or previous Port Fairy IMOS monthly file.")
}
message("Using buoy data: ", basename(buoy_file))

# Model-domain corners in clockwise order, read approximately from the supplied
# figure. These become an axis-aligned rectangle in the local rotated CRS.
domain_corners_ll <- rbind(
  c(142.2310, -38.3760),  # northwest / coastward corner
  c(142.2950, -38.3500),  # northeast corner
  c(142.3060, -38.3780),  # southeast / buoy-side corner
  c(142.2430, -38.3940),  # southwest corner
  c(142.2310, -38.3760)
)

# Compass bearing (degrees clockwise from north) across the domain, from the
# buoy-side long edge toward the coast. It is normal to the long domain edges.
model_x_bearing_guess <- 64  # 334 + 90, modulo 360
dx <- 20                         # metres; use 10 m only after this run works
total_time <- 1800               # seconds = 30 minutes
plot_intv <- 7.5                 # seconds; four times the previous output rate

# ----- Latest good / not-yet-evaluated buoy observation --------------------
nc <- nc_open(buoy_file)
on.exit(nc_close(nc), add = TRUE)

read_buoy <- function(name) {
  x <- ncvar_get(nc, name)
  x[x <= -9990] <- NA_real_
  x
}

# In this IMOS file TIME is a dimension coordinate, not a variable, so it is
# exposed by ncdf4 through nc$dim rather than ncvar_get().
time_days <- nc$dim[["TIME"]]$vals
time_utc <- as.POSIXct("1950-01-01 00:00:00", tz = "UTC") + time_days * 86400
hs <- read_buoy("WSSH")
tp <- read_buoy("WPPE")
dir_from <- read_buoy("WPDI")
# WPDS is the directional spread at the peak of the buoy spectrum.
dir_spread <- if ("WPDS" %in% names(nc$var)) read_buoy("WPDS") else rep(NA_real_, length(hs))
qc <- ncvar_get(nc, "WAVE_quality_control")

# QC 1 = good; 2 = not yet evaluated. Do not silently use questionable/bad.
usable <- qc %in% c(1, 2) & is.finite(hs) & is.finite(tp) & is.finite(dir_from) &
  hs > 0 & tp > 0
if (!any(usable)) stop("No usable (QC 1 or 2) buoy observation is available.")
i <- tail(which(usable), 1)

# First-pass directional forcing: map the measured peak directional
# spread (degrees) onto FUNWAVE WK_IRR's Sigma_Theta. Keep the documented
# 20-degree default only when WPDS is absent or implausible.
spread_i <- dir_spread[i]
sigma_theta <- if (is.finite(spread_i) && spread_i > 0 && spread_i <= 90) spread_i else 20.0

# The Spotter direction is a compass FROM direction.
bearing_to <- (dir_from[i] + 180) %% 360

# ----- Warp and coarsen the DEM ---------------------------------------------
bathy <- rast(bathy_file)
if (is.na(crs(bathy))) stop("The bathymetry raster has no CRS.")

domain_poly_ll <- vect(domain_corners_ll, type = "polygons", crs = "EPSG:4326")
domain_centroid <- project(centroids(domain_poly_ll), "EPSG:4326")
centre_xy <- crds(domain_centroid)[1, ]

# A local Oblique Mercator CRS with its central x line pointing cross-shore.
omerc_crs <- paste0(
  "+proj=omerc +lat_0=", centre_xy[2], " +lonc=", centre_xy[1],
  " +alpha=", model_x_bearing_guess,
  " +k=1 +x_0=0 +y_0=0 +gamma=0 +datum=WGS84 +units=m +no_defs"
)
domain_poly_om <- project(domain_poly_ll, omerc_crs)
buoy_ll <- vect(matrix(c(ncvar_get(nc, "LONGITUDE")[i],
                          ncvar_get(nc, "LATITUDE")[i]), ncol = 2),
                crs = "EPSG:4326")
buoy_om <- project(buoy_ll, omerc_crs)

# Warp the complete 50 MB DEM directly onto the rotated rectangular template.
# Cropping to the oblique non-rectangular envelope first creates NoData triangular corners
# after reprojection; FUNWAVE instead needs a complete rectangular depth grid.
template <- rast(ext(domain_poly_om), resolution = dx, crs = omerc_crs)
elevation <- project(bathy, template, method = "bilinear")

# DEM elevations are positive on land and negative below datum. FUNWAVE uses
# positive water depth.  Land/NA cells are retained as 0 m so its wet-dry mask
# makes them dry; this should be checked visually before a finer production run.
depth_gis <- -elevation
depth_gis[is.na(depth_gis)] <- 0
depth_gis[depth_gis < 0] <- 0

# terra matrices are [high-y to low-y row, low-x to high-x column]. Find which
# rotated x edge is nearest to the buoy. That is the wavemaker edge, and make it
# model x = 0. Reverse y at the same time when needed to retain a right-handed
# model coordinate system.
depth_matrix <- as.matrix(depth_gis, wide = TRUE)
buoy_x <- crds(buoy_om)[1, 1]
source_is_low_x <- abs(buoy_x - xmin(template)) < abs(buoy_x - xmax(template))

if (source_is_low_x) {
  depth_funwave <- t(depth_matrix[nrow(depth_matrix):1, , drop = FALSE])
  source_edge <- "minimum rotated x"
} else {
  depth_funwave <- t(depth_matrix[, ncol(depth_matrix):1, drop = FALSE])
  source_edge <- "maximum rotated x"
}

# Measure the bearings of the *actual* model axes after the oblique projection
# and matrix re-ordering.  Do not assume that a PROJ `alpha` is automatically
# the bearing of the final raster x axis: `gamma`, the chosen source edge and
# matrix reversals all matter.  This makes ThetaPeak reproducible and provides
# an explicit diagnostic of the rotated grid.
compass_bearing <- function(from_ll, to_ll) {
  lon1 <- from_ll[1] * pi / 180
  lat1 <- from_ll[2] * pi / 180
  lon2 <- to_ll[1] * pi / 180
  lat2 <- to_ll[2] * pi / 180
  dlon <- lon2 - lon1
  (atan2(sin(dlon) * cos(lat2),
         cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon)) *
     180 / pi + 360) %% 360
}

rotated_point_to_ll <- function(x, y) {
  p <- vect(matrix(c(x, y), ncol = 2), type = "points", crs = omerc_crs)
  crds(project(p, "EPSG:4326"))[1, ]
}

axis_step <- min(200, 10 * dx, (xmax(template) - xmin(template)) / 4,
                 (ymax(template) - ymin(template)) / 4)
mid_x <- (xmin(template) + xmax(template)) / 2
mid_y <- (ymin(template) + ymax(template)) / 2

if (source_is_low_x) {
  x0 <- c(xmin(template) + dx / 2, mid_y)
  x1 <- c(x0[1] + axis_step, x0[2])
  y0 <- c(mid_x, ymin(template) + dx / 2)
  y1 <- c(y0[1], y0[2] + axis_step)
} else {
  x0 <- c(xmax(template) - dx / 2, mid_y)
  x1 <- c(x0[1] - axis_step, x0[2])
  y0 <- c(mid_x, ymax(template) - dx / 2)
  y1 <- c(y0[1], y0[2] - axis_step)
}

model_x_bearing <- compass_bearing(rotated_point_to_ll(x0[1], x0[2]),
                                   rotated_point_to_ll(x1[1], x1[2]))
model_y_bearing <- compass_bearing(rotated_point_to_ll(y0[1], y0[2]),
                                   rotated_point_to_ll(y1[1], y1[2]))

# FUNWAVE's ThetaPeak is the direction the wave travels, measured from +x.
dot_bearing <- function(a, b) cos((a - b) * pi / 180)
theta_peak <- atan2(
  dot_bearing(bearing_to, model_y_bearing),
  dot_bearing(bearing_to, model_x_bearing)
) * 180 / pi

forcing <- data.frame(
  time_utc = format(time_utc[i], tz = "UTC", usetz = TRUE),
  qc = qc[i], hs_m = hs[i], tp_s = tp[i],
  peak_direction_from_deg_true = dir_from[i],
  peak_directional_spread_deg = spread_i,
  funwave_sigma_theta_deg = sigma_theta,
  peak_direction_to_deg_true = bearing_to,
  buoy_lon = crds(buoy_ll)[1, 1],
  buoy_lat = crds(buoy_ll)[1, 2],
  requested_cross_shore_bearing_deg_true = model_x_bearing_guess,
  model_x_bearing_deg_true = model_x_bearing,
  model_y_bearing_deg_true = model_y_bearing,
  funwave_theta_peak_deg = theta_peak,
  inward_source_component = cos(theta_peak * pi / 180)
)
write.csv(forcing, file.path(out_dir, "latest_buoy_forcing.csv"), row.names = FALSE)

mglob <- nrow(depth_funwave)     # x: east -> west
nglob <- ncol(depth_funwave)     # y: south -> north
write.table(
  # FUNWAVE reads one y row at a time: Nglob text rows, each with Mglob values.
  t(depth_funwave), file.path(out_dir, "depth.txt"),
  row.names = FALSE, col.names = FALSE, quote = FALSE
)
writeRaster(depth_gis, file.path(out_dir, "depth_20m_positive_water_depth.tif"),
            overwrite = TRUE)
writeRaster(elevation, file.path(out_dir, "elevation_20m_warped.tif"),
            overwrite = TRUE)
# Use the median water depth in the first 100 m offshore as DEP_WK. A source
# needs finite depth: if this strip is unexpectedly dry, stop rather than
# generating an invalid case.
n_source <- max(2, min(5, floor(100 / dx)))
source_depth <- depth_funwave[seq_len(n_source), , drop = FALSE]
dep_wk <- median(source_depth[source_depth > 0], na.rm = TRUE)
if (!is.finite(dep_wk) || dep_wk <= 0) {
  stop("The buoy-side source strip is dry. Move the rotated model domain or inspect the DEM.")
}

# Warn when the recorded waves propagate away from the buoy-side source.
if (abs(theta_peak) > 60) {
  warning(sprintf(
    paste0("Latest waves are %.1f degrees from the inward source normal. ",
           "This is strongly oblique; inspect the forcing-geometry diagnostic ",
           "before interpreting this run."), theta_peak
  ))
}

# FUNWAVE WK_IRR is a TMA/JONSWAP-style irregular internal wavemaker. The
# monthly IMOS file provides integral Hs/Tp/direction, not a phase-resolved
# spectrum, so this is a parametric approximation -- not a replay of the buoy.
freq_peak <- 1 / tp[i]
freq_min <- max(0.04, freq_peak / 2.5)
freq_max <- min(0.50, freq_peak * 3)
x_wk <- n_source * dx + 20       # 20 m inside the buoy-side source edge

# Do not place a sponge on the source edge: in the previous setup the
# 100 m sponge overlapped the internal wavemaker and could damp generated
# wave energy before it crossed the domain. Keep damping only at the far
# x edge and the two lateral edges to limit reflected energy.
far_x_sponge <- 5 * dx
sponge_west_width <- if (source_is_low_x) 0 else far_x_sponge
sponge_east_width <- if (source_is_low_x) far_x_sponge else 0

input <- c(
  "! Port Fairy: coarse first-pass FUNWAVE-TVD simulation",
  "! Generated by port_fairy/setup_port_fairy_funwave.R",
  "TITLE = Port_Fairy_latest_buoy_30min",
  "PX = 2", "PY = 1",
  "DEPTH_TYPE = DATA", "DEPTH_FILE = depth.txt",
  "RESULT_FOLDER = results/",
  sprintf("Mglob = %d", mglob), sprintf("Nglob = %d", nglob),
  sprintf("TOTAL_TIME = %.1f", total_time),
  sprintf("PLOT_INTV = %.1f", plot_intv),
  "PLOT_INTV_STATION = 1.0", "SCREEN_INTV = 30.0",
  sprintf("DX = %.1f", dx), sprintf("DY = %.1f", dx),
  "WAVEMAKER = WK_IRR",
  sprintf("DEP_WK = %.3f", dep_wk),
  sprintf("Xc_WK = %.1f", x_wk), "Yc_WK = 0.0",
  sprintf("FreqPeak = %.5f", freq_peak),
  sprintf("FreqMin = %.5f", freq_min), sprintf("FreqMax = %.5f", freq_max),
  sprintf("Hmo = %.3f", hs[i]), "GammaTMA = 3.3",
  sprintf("ThetaPeak = %.2f", theta_peak),
  sprintf("Sigma_Theta = %.2f", sigma_theta)
  "PERIODIC = F",
  "DIFFUSION_SPONGE = F", "FRICTION_SPONGE = T", "DIRECT_SPONGE = T",
  "Csp = 0.0", "CDsponge = 1.0",
  sprintf("Sponge_west_width = %.1f", sponge_west_width),
  sprintf("Sponge_east_width = %.1f", sponge_east_width),
  sprintf("Sponge_south_width = %.1f", 3 * dx),
  sprintf("Sponge_north_width = %.1f", 3 * dx),
  "Cd = 0.0025", "CFL = 0.5", "FroudeCap = 1.0", "MinDepth = 0.05",
  "VISCOSITY_BREAKING = T", "Cbrk1 = 0.65", "Cbrk2 = 0.35",
  "DEPTH_OUT = T", "U = T", "V = T", "ETA = T", "Hmax = T",
  "WaveHeight = T", "MASK = T", "NumberStations = 0"
)
writeLines(input, file.path(out_dir, "input.txt"))

# Record enough information to reproduce the grid spatially in an R report.
grid_info <- data.frame(
  bathy_file = normalizePath(bathy_file),
  buoy_file = normalizePath(buoy_file),
  omerc_crs = omerc_crs,
  requested_cross_shore_bearing_deg_true = model_x_bearing_guess,
  model_x_bearing_deg_true = model_x_bearing,
  model_y_bearing_deg_true = model_y_bearing,
  source_edge = source_edge,
  x_wk_m = x_wk,
  funwave_theta_peak_deg = theta_peak,
  inward_source_component = cos(theta_peak * pi / 180),
  xmin_m = xmin(template), xmax_m = xmax(template),
  ymin_m = ymin(template), ymax_m = ymax(template),
  dx_m = dx, dy_m = dx, Mglob = mglob, Nglob = nglob,
  total_time_s = total_time, plot_intv_s = plot_intv,
  x_axis = "buoy-side edge to coast", y_axis = "right-handed rotated y"
)
write.csv(grid_info, file.path(out_dir, "grid_metadata.csv"), row.names = FALSE)

message("Created FUNWAVE case in: ", out_dir)
message("Latest buoy forcing: Hs=", round(hs[i], 2), " m, Tp=", round(tp[i], 1),
        " s, from=", round(dir_from[i]), " degrees, at ", forcing$time_utc)
message("Grid: ", mglob, " x ", nglob, " at ", dx, " m")

