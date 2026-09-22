#!/usr/bin/env Rscript

# Build a 5 m, 10-minute FUNWAVE-TVD resolution sensitivity for Port Fairy
# from the Victorian DEM and the newest usable Spotter observation.
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

# An optional UTC timestamp makes this script reproducible for the historical
# report workflow.  The normal daily workflow leaves it unset and retains the
# newest-observation behaviour.
requested_observation_utc <- Sys.getenv("PORT_FAIRY_OBSERVATION_UTC", unset = "")
historical_run <- nzchar(requested_observation_utc)
if (historical_run) {
  requested_observation_utc <- as.POSIXct(
    requested_observation_utc, tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ"
  )
  if (is.na(requested_observation_utc)) {
    stop("PORT_FAIRY_OBSERVATION_UTC must be UTC ISO-8601, e.g. 2025-02-10T11:00:00Z")
  }
}

# For the normal run, try this month then the two preceding months.  For a
# historical run, fetch the requested observation's monthly archive.
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

month_starts <- if (!historical_run) {
  seq(as.Date(format(Sys.time(), "%Y-%m-01")), by = "-1 month", length.out = 3)
} else {
  as.Date(format(requested_observation_utc, "%Y-%m-01"))
}
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

# The grid is rebuilt daily with model +x aligned to the newest *mean* wave
# travel direction.  A fixed coast-normal grid forced with an oblique sea state
# lets much of the energy meet a lateral boundary before reaching the local
# coast; this is a geometry issue, not a reason to remove the source sponge.
dx <- 5                          # metres
total_time <- 600                # seconds = 10 minutes
plot_intv <- 15                  # seconds; 40 snapshots including the initial frame
mean_wave_interval <- 200        # seconds
steady_time <- 100               # seconds; leaves two complete mean-wave windows
grid_tag <- paste0(sprintf("%.0f", dx), "m")

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

# Use the mean direction and matching mean directional spread when available.
# IMOS calls these SSWMD and WMDS.  Retain the peak parameters as a per-record
# fallback and save both in the output provenance table.
dir_from_peak <- if ("WPDI" %in% names(nc$var)) {
  read_buoy("WPDI")
} else {
  rep(NA_real_, length(hs))
}
dir_from_mean <- if ("SSWMD" %in% names(nc$var)) {
  read_buoy("SSWMD")
} else {
  rep(NA_real_, length(hs))
}
spread_peak <- if ("WPDS" %in% names(nc$var)) {
  read_buoy("WPDS")
} else {
  rep(NA_real_, length(hs))
}
spread_mean <- if ("WMDS" %in% names(nc$var)) {
  read_buoy("WMDS")
} else {
  rep(NA_real_, length(hs))
}

use_mean_direction <- is.finite(dir_from_mean)
dir_from <- ifelse(use_mean_direction, dir_from_mean, dir_from_peak)
dir_spread <- ifelse(use_mean_direction & is.finite(spread_mean),
                     spread_mean, spread_peak)
direction_statistic <- ifelse(use_mean_direction, "mean", "peak fallback")
qc <- ncvar_get(nc, "WAVE_quality_control")

# QC 1 = good; 2 = not yet evaluated. Do not silently use questionable/bad.
usable <- qc %in% c(1, 2) & is.finite(hs) & is.finite(tp) & is.finite(dir_from) &
  hs > 0 & tp > 0
if (!any(usable)) stop("No usable (QC 1 or 2) buoy observation is available.")
if (historical_run) {
  # Use the latest valid record at or before the requested time: a historical
  # case can never accidentally use an observation from the future.
  candidate <- which(usable & time_utc <= requested_observation_utc)
  if (!length(candidate)) {
    stop("No usable buoy observation exists at or before the requested UTC time: ",
         format(requested_observation_utc, tz = "UTC"))
  }
  i <- tail(candidate, 1)
  message("Historical observation requested: ",
          format(requested_observation_utc, tz = "UTC"),
          "; using record: ", format(time_utc[i], tz = "UTC"))
} else {
  i <- tail(which(usable), 1)
}

# ----- Portland hourly water level -----------------------------------------
# UHSLC fast-delivery data are UTC hourly values in millimetres.  Portland's
# supplied tidal-datum sheet states that LAT is 0.597 m below AHD, so this
# workflow assumes the CSV values are LAT and uses: water level AHD (m) = water
# level LAT (m) - 0.597. It is a static still-water level for this short FUNWAVE run, applied
# throughout the domain (and therefore at the offshore boundary), not an
# additional wave-paddle signal.
download_portland_water_level <- function(data_dir) {
  url <- "https://uhslc.soest.hawaii.edu/data/csv/fast/hourly/h129.csv"
  destination <- file.path(data_dir, "UHSLC_h129_Portland_hourly.csv")
  if (file.exists(destination) && file.info(destination)$size > 1000) return(destination)
  temporary <- paste0(destination, ".download")
  old_timeout <- getOption("timeout")
  on.exit(options(timeout = old_timeout), add = TRUE)
  options(timeout = min(max(old_timeout, 30), 45))
  status <- tryCatch(
    suppressWarnings(utils::download.file(
      url, temporary, mode = "wb", method = "libcurl", quiet = TRUE
    )),
    error = function(e) 1L
  )
  if (isTRUE(status == 0) && file.exists(temporary) && file.info(temporary)$size > 1000) {
    if (file.exists(destination)) unlink(destination)
    if (file.rename(temporary, destination)) return(destination)
  }
  if (file.exists(temporary)) unlink(temporary)
  warning(
    "Could not download Portland hourly water levels from UHSLC; ",
    "continuing with a 0.000 m AHD still-water level."
  )
  NULL
}

portland_file <- download_portland_water_level(data_dir)
portland_to_ahd_offset_m <- -0.597
portland_reference_datum <- "LAT assumed; Portland observation unavailable"
portland_water_level_lat_m <- NA_real_
portland_water_level_ahd_m <- 0
portland_time_forcing <- as.POSIXct(NA, tz = "UTC")
if (!is.null(portland_file)) {
  portland <- utils::read.csv(
    portland_file, header = FALSE,
    col.names = c("year", "month", "day", "hour", "level_mm")
  )
  portland$time_utc <- as.POSIXct(
    sprintf("%04d-%02d-%02d %02d:00:00", portland$year, portland$month,
            portland$day, portland$hour), tz = "UTC"
  )
  portland$level_mm[portland$level_mm <= -9990] <- NA_real_
  target_time <- time_utc[i]
  portland_valid <- which(is.finite(portland$level_mm))
  nearest_portland <- if (length(portland_valid)) {
    portland_valid[which.min(abs(difftime(
      portland$time_utc[portland_valid], target_time, units = "secs"
    )))]
  } else {
    NA_integer_
  }
  portland_gap_minutes <- if (is.na(nearest_portland)) Inf else abs(as.numeric(difftime(
    portland$time_utc[nearest_portland], target_time, units = "mins"
  )))
  if (is.finite(portland_gap_minutes) && portland_gap_minutes <= 90) {
    portland_reference_datum <- "LAT (assumed from Portland tidal datum sheet)"
    portland_water_level_lat_m <- portland$level_mm[nearest_portland] / 1000
    portland_water_level_ahd_m <- portland_water_level_lat_m + portland_to_ahd_offset_m
    portland_time_forcing <- portland$time_utc[nearest_portland]
    message(sprintf("Portland water level: %.3f m LAT = %.3f m AHD",
                    portland_water_level_lat_m, portland_water_level_ahd_m))
  } else {
    warning(
      "No contemporaneous Portland water level is available; ",
      "continuing with a 0.000 m AHD still-water level."
    )
  }
}

# Map the measured directional spread (degrees) onto FUNWAVE WK_IRR's
# Sigma_Theta. Keep the documented 20-degree default only when the matching
# IMOS spread is absent or implausible.
spread_i <- dir_spread[i]
sigma_theta <- if (is.finite(spread_i) && spread_i > 0 && spread_i <= 90) spread_i else 20.0

# The Spotter direction is a compass FROM direction.  Align model +x with its
# physical travel direction so the daily source is nearly normal to the model
# boundary and does not immediately encounter a lateral sponge.
bearing_to <- (dir_from[i] + 180) %% 360
model_x_bearing_target <- bearing_to
# With this local Oblique Mercator convention, PROJ alpha is 90 degrees from
# the realised raster +x bearing.  The realised bearing is measured below and
# recorded as a run diagnostic rather than assumed.
model_x_bearing_guess <- (model_x_bearing_target + 90) %% 360

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
# positive water depth. Add Portland's observed AHD still-water level,
# uniformly across this short local-domain run.
depth_gis <- portland_water_level_ahd_m - elevation
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
  boundary_direction_statistic = direction_statistic[i],
  boundary_direction_from_deg_true = dir_from[i],
  boundary_directional_spread_deg = spread_i,
  mean_direction_from_deg_true = dir_from_mean[i],
  mean_directional_spread_deg = spread_mean[i],
  peak_direction_from_deg_true = dir_from_peak[i],
  peak_directional_spread_deg = spread_peak[i],
  funwave_sigma_theta_deg = sigma_theta,
  boundary_direction_to_deg_true = bearing_to,
  buoy_lon = crds(buoy_ll)[1, 1],
  buoy_lat = crds(buoy_ll)[1, 2],
  requested_model_x_bearing_deg_true = model_x_bearing_target,
  omerc_alpha_deg = model_x_bearing_guess,
  model_x_bearing_deg_true = model_x_bearing,
  model_y_bearing_deg_true = model_y_bearing,
  funwave_theta_peak_deg = theta_peak,
  inward_source_component = cos(theta_peak * pi / 180),
  portland_water_level_time_utc = format(portland_time_forcing, tz = "UTC", usetz = TRUE),
  portland_water_level_lat_m = portland_water_level_lat_m,
  portland_reference_datum = portland_reference_datum,
  portland_to_ahd_offset_m = portland_to_ahd_offset_m,
  portland_water_level_ahd_m_applied = portland_water_level_ahd_m
)
write.csv(forcing, file.path(out_dir, "latest_buoy_forcing.csv"), row.names = FALSE)

mglob <- nrow(depth_funwave)     # x: east -> west
nglob <- ncol(depth_funwave)     # y: south -> north
write.table(
  # FUNWAVE reads one y row at a time: Nglob text rows, each with Mglob values.
  t(depth_funwave), file.path(out_dir, "depth.txt"),
  row.names = FALSE, col.names = FALSE, quote = FALSE
)
writeRaster(depth_gis,
            file.path(out_dir, paste0("depth_", grid_tag, "_positive_water_depth.tif")),
            overwrite = TRUE)
writeRaster(elevation,
            file.path(out_dir, paste0("elevation_", grid_tag, "_warped.tif")),
            overwrite = TRUE)
# An internal wavemaker emits both shoreward and seaward energy. Keep its
# spatial envelope clear of the buoy-side sponge so the source itself is not
# numerically damped. `Delta_WK` is dimensionless, so describe this source by
# its physical active Gaussian envelope and derive the daily Delta value from
# the peak wavelength at the source depth.
source_sponge_width <- 100
source_gap_after_sponge <- 60
source_envelope_width_m <- 50        # full span from -2 to +2 e-folds
source_e_fold_half_width_m <- source_envelope_width_m / 4

# FUNWAVE defines Width_WK = Delta_WK * Lp / 2. For a 50 m active envelope,
# the corresponding FUNWAVE width parameter is 55.9 m. Its upstream edge is
# 60 m clear of the 100 m source-side sponge; the paddle centre is therefore
# ~215.9 m from the model source edge on every daily case.
funwave_width_wk_m <- source_e_fold_half_width_m * sqrt(80) / 2
x_wk <- source_sponge_width + source_gap_after_sponge + funwave_width_wk_m

# FUNWAVE WK_IRR is a TMA/JONSWAP-style irregular internal wavemaker. The
# monthly IMOS file provides integral Hs/Tp/direction, not a phase-resolved
# spectrum, so this is a parametric approximation -- not a replay of the buoy.
freq_peak <- 1 / tp[i]
freq_min <- max(0.04, freq_peak / 2.5)
freq_max <- min(0.50, freq_peak * 3)

# Match FUNWAVE-TVD's Boussinesq dispersion relation when calculating the
# peak wavelength at the wavemaker depth.
funwave_peak_wavelength <- function(depth_m, frequency_hz) {
  alpha <- -0.39
  alpha1 <- alpha + 1 / 3
  omega <- 2 * pi * frequency_hz
  tb <- omega^2 * depth_m / 9.81
  tc <- 1 + tb * alpha
  discriminant <- tc^2 - 4 * alpha1 * tb
  if (!is.finite(discriminant) || discriminant <= 0) {
    stop("Could not calculate the FUNWAVE peak wavelength at the wavemaker.")
  }
  wavenumber <- sqrt((tc - sqrt(discriminant)) / (2 * alpha1)) / depth_m
  if (!is.finite(wavenumber) || wavenumber <= 0) {
    stop("Could not calculate a positive FUNWAVE peak wavenumber at the wavemaker.")
  }
  2 * pi / wavenumber
}

# Use the median water depth at the actual wavemaker strip for DEP_WK. A source
# needs finite depth: if this strip is unexpectedly dry, stop rather than
# generating an invalid case.
# Sample the full physical 50 m source span when calculating DEP_WK, rather
# than a grid-cell-count-dependent portion of the source bathymetry.
n_source <- max(3, 2 * ceiling((source_envelope_width_m / 2) / dx) + 1)
source_depth_at_x <- function(x_position_m) {
  wk_i <- max(1, min(mglob, round(x_position_m / dx) + 1))
  wk_indices <- seq.int(max(1, wk_i - floor(n_source / 2)),
                        min(mglob, wk_i + floor(n_source / 2)))
  source_depth <- depth_funwave[wk_indices, , drop = FALSE]
  depth_m <- median(source_depth[source_depth > 0], na.rm = TRUE)
  if (!is.finite(depth_m) || depth_m <= 0) {
    stop("The buoy-side source strip is dry. Move the rotated model domain or inspect the DEM.")
  }
  depth_m
}

dep_wk <- source_depth_at_x(x_wk)
peak_wavelength_m <- funwave_peak_wavelength(dep_wk, freq_peak)
delta_wk <- 2 * funwave_width_wk_m / peak_wavelength_m
if (!is.finite(delta_wk) || delta_wk <= 0) {
  stop("Could not calculate a positive Delta_WK for the 50 m source envelope.")
}

source_envelope_cells <- source_envelope_width_m / dx
source_e_fold_cells <- source_e_fold_half_width_m / dx

# Five gauges follow the requested offshore-to-nearshore transect.  FUNWAVE
# station files are one-based Mglob/Nglob grid indices, so calculate these
# only after the final rotated grid and source-edge orientation are known.
transect_end_ll <- c(lon = 142.2456520235717, lat = -38.37890145894907)
station_lon <- seq(crds(buoy_ll)[1, 1], transect_end_ll["lon"], length.out = 5)
station_lat <- seq(crds(buoy_ll)[1, 2], transect_end_ll["lat"], length.out = 5)
station_ll <- vect(cbind(station_lon, station_lat), type = "points", crs = "EPSG:4326")
station_om <- project(station_ll, omerc_crs)
station_xy <- crds(station_om)
if (source_is_low_x) {
  station_i <- round((station_xy[, 1] - xmin(template)) / dx) + 1L
  station_j <- round((station_xy[, 2] - ymin(template)) / dx) + 1L
} else {
  station_i <- round((xmax(template) - station_xy[, 1]) / dx) + 1L
  station_j <- round((ymax(template) - station_xy[, 2]) / dx) + 1L
}
station_i <- pmax(1L, pmin(mglob, station_i))
station_j <- pmax(1L, pmin(nglob, station_j))
station_info <- data.frame(
  station_id = sprintf("Station %d", seq_along(station_i)),
  transect_fraction = seq(0, 1, length.out = length(station_i)),
  lon = station_lon, lat = station_lat,
  model_i = station_i, model_j = station_j,
  water_depth_m = depth_funwave[cbind(station_i, station_j)]
)
write.table(station_info[, c("model_i", "model_j")], file.path(out_dir, "stations.txt"),
            row.names = FALSE, col.names = FALSE, quote = FALSE)
write.csv(station_info, file.path(out_dir, "station_metadata.csv"), row.names = FALSE)
if (any(!is.finite(station_info$water_depth_m) | station_info$water_depth_m <= 0)) {
  warning("One or more requested transect stations are dry in the supplied DEM.")
}

# Warn when the recorded waves propagate away from the buoy-side source.
if (abs(theta_peak) > 60) {
  warning(sprintf(
    paste0("Latest waves are %.1f degrees from the inward source normal. ",
           "This is strongly oblique; inspect the forcing-geometry diagnostic ",
           "before interpreting this run."), theta_peak
  ))
}

# Model x is always re-ordered so x = 0 is the buoy-side source edge, whether
# the original rotated raster source was at low or high x.  The source sponge
# is therefore always west in FUNWAVE's model coordinates.
far_x_sponge <- max(5 * dx, 100)
sponge_west_width <- source_sponge_width
sponge_east_width <- far_x_sponge
# Preserve the prior 60 m physical lateral damping width across the resolution
# change. At 5 m this is twelve cells, not the former 3 * dx expression.
lateral_sponge_width <- 60
# State the full-span source explicitly rather than relying on FUNWAVE's very
# large default Ywidth_WK. This makes it clear that WK_IRR is a line source
# across the whole seaward side, not a point source at y = 0.
y_wk <- (nglob - 1) * dx / 2
ywidth_wk <- nglob * dx

input <- c(
  "! Port Fairy: 5 m, 10-minute FUNWAVE-TVD resolution sensitivity",
  "! Generated by port_fairy/setup_port_fairy_funwave.R",
  paste0("TITLE = Port_Fairy_latest_buoy_", sprintf("%.0f", total_time / 60), "min"),
  "PX = 2", "PY = 1",
  "DEPTH_TYPE = DATA", "DEPTH_FILE = depth.txt",
  "RESULT_FOLDER = results/",
  sprintf("Mglob = %.0f", mglob), sprintf("Nglob = %.0f", nglob),
  sprintf("TOTAL_TIME = %.1f", total_time),
  sprintf("PLOT_INTV = %.1f", plot_intv),
  "PLOT_INTV_STATION = 1.0", "SCREEN_INTV = 30.0",
  sprintf("T_INTV_mean = %.1f", mean_wave_interval),
  sprintf("STEADY_TIME = %.1f", steady_time),
  sprintf("DX = %.1f", dx), sprintf("DY = %.1f", dx),
  "WAVEMAKER = WK_IRR",
  sprintf("DEP_WK = %.3f", dep_wk),
  sprintf("Xc_WK = %.1f", x_wk),
  sprintf("Yc_WK = %.1f", y_wk),
  sprintf("Ywidth_WK = %.1f", ywidth_wk),
  "Time_ramp = 10.0",
  sprintf("Delta_WK = %.5f", delta_wk),
  sprintf("FreqPeak = %.5f", freq_peak),
  sprintf("FreqMin = %.5f", freq_min), sprintf("FreqMax = %.5f", freq_max),
  sprintf("Hmo = %.3f", hs[i]), "GammaTMA = 3.3",
  sprintf("ThetaPeak = %.2f", theta_peak),
  sprintf("Sigma_Theta = %.2f", sigma_theta),
  "PERIODIC = F",
  "DIFFUSION_SPONGE = F", "FRICTION_SPONGE = T", "DIRECT_SPONGE = T",
  "Csp = 0.0", "CDsponge = 1.0",
  sprintf("Sponge_west_width = %.1f", sponge_west_width),
  sprintf("Sponge_east_width = %.1f", sponge_east_width),
  sprintf("Sponge_south_width = %.1f", lateral_sponge_width),
  sprintf("Sponge_north_width = %.1f", lateral_sponge_width),
  "Cd = 0.002", "CFL = 0.5", "FroudeCap = 1.0", "MinDepth = 0.05",
  "VISCOSITY_BREAKING = T", "Cbrk1 = 0.65", "Cbrk2 = 0.35",
  "DEPTH_OUT = T", "U = T", "V = T", "ETA = T", "Hmax = T",
  "WaveHeight = T", "MASK = T",
  sprintf("NumberStations = %d", nrow(station_info)), "STATIONS_FILE = stations.txt"
)
writeLines(input, file.path(out_dir, "input.txt"))

# Record enough information to reproduce the grid spatially in an R report.
grid_info <- data.frame(
  bathy_file = normalizePath(bathy_file),
  buoy_file = normalizePath(buoy_file),
  omerc_crs = omerc_crs,
  requested_model_x_bearing_deg_true = model_x_bearing_target,
  omerc_alpha_deg = model_x_bearing_guess,
  model_x_bearing_deg_true = model_x_bearing,
  model_y_bearing_deg_true = model_y_bearing,
  source_edge = source_edge,
  x_wk_m = x_wk,
  y_wk_m = y_wk,
  ywidth_wk_m = ywidth_wk,
  source_sponge_width_m = source_sponge_width,
  source_gap_after_sponge_m = source_gap_after_sponge,
  source_envelope_width_m = source_envelope_width_m,
  source_e_fold_half_width_m = source_e_fold_half_width_m,
  source_envelope_width_cells = source_envelope_cells,
  source_e_fold_half_width_cells = source_e_fold_cells,
  funwave_width_wk_half_width_m = funwave_width_wk_m,
  peak_wavelength_m = peak_wavelength_m,
  delta_wk = delta_wk,
  far_sponge_width_m = far_x_sponge,
  lateral_sponge_width_m = lateral_sponge_width,
  funwave_theta_peak_deg = theta_peak,
  inward_source_component = cos(theta_peak * pi / 180),
  xmin_m = xmin(template), xmax_m = xmax(template),
  ymin_m = ymin(template), ymax_m = ymax(template),
  dx_m = dx, dy_m = dx, Mglob = mglob, Nglob = nglob,
  mpi_px = 2, mpi_py = 1, mpi_ranks = 2,
  station_count = nrow(station_info),
  total_time_s = total_time, plot_intv_s = plot_intv,
  mean_wave_interval_s = mean_wave_interval, steady_time_s = steady_time,
  x_axis = "buoy-side edge to coast", y_axis = "right-handed rotated y"
)
write.csv(grid_info, file.path(out_dir, "grid_metadata.csv"), row.names = FALSE)

message("Created FUNWAVE case in: ", out_dir)
message("Latest buoy forcing: Hs=", round(hs[i], 2), " m, Tp=", round(tp[i], 1),
        " s, from=", round(dir_from[i]), " degrees, at ", forcing$time_utc)
message("Grid: ", mglob, " x ", nglob, " at ", dx, " m")
message("Wavemaker: Xc_WK=", round(x_wk, 1), " m; ",
        round(source_envelope_width_m, 1), " m active Gaussian envelope (",
        round(source_envelope_cells, 1), " cells); Lp=", round(peak_wavelength_m, 1),
        " m; Delta_WK=", round(delta_wk, 3))
