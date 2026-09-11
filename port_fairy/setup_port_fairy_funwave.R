#!/usr/bin/env Rscript

# Build a first, deliberately coarse (20 m) 5-minute FUNWAVE-TVD case for
# Port Fairy from the Victorian DEM and the newest usable Spotter observation.
#
# The model uses an Oblique Mercator grid. Its +x direction is perpendicular to
# the long buoy-side pink edge, pointing from that edge toward the coast. This
# makes the FUNWAVE internal irregular wavemaker span the offshore pink edge.
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

# Pink domain corners in clockwise order, read approximately from the supplied
# figure. These become an axis-aligned rectangle in the local rotated CRS.
pink_corners_ll <- rbind(
  c(142.2310, -38.3760),  # northwest / coastward corner
  c(142.2950, -38.3500),  # northeast corner
  c(142.3060, -38.3780),  # southeast / buoy-side corner
  c(142.2430, -38.3940),  # southwest corner
  c(142.2310, -38.3760)
)

# Compass bearing (degrees clockwise from north) across the domain, from the
# buoy-side long edge toward the coast. It is normal to the pink long edges.
model_x_bearing_guess <- 334
dx <- 20                         # metres; use 10 m only after this run works
total_time <- 300                # seconds = 5 minutes
plot_intv <- 30                  # seconds

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
qc <- ncvar_get(nc, "WAVE_quality_control")

# QC 1 = good; 2 = not yet evaluated. Do not silently use questionable/bad.
usable <- qc %in% c(1, 2) & is.finite(hs) & is.finite(tp) & is.finite(dir_from) &
  hs > 0 & tp > 0
if (!any(usable)) stop("No usable (QC 1 or 2) buoy observation is available.")
i <- tail(which(usable), 1)

# The Spotter direction is a compass FROM direction.
bearing_to <- (dir_from[i] + 180) %% 360

# ----- Crop and coarsen the DEM ---------------------------------------------
bathy <- rast(bathy_file)
if (is.na(crs(bathy))) stop("The bathymetry raster has no CRS.")

domain_poly_ll <- vect(pink_corners_ll, type = "polygons", crs = "EPSG:4326")
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

# Crop only the needed area in the native DEM CRS, then warp onto a rectangle
# in the rotated CRS. Do not mask to the original polygon: FUNWAVE requires a
# full rectangular grid and the pink quadrilateral is the visual guide for it.
domain_poly_native <- project(domain_poly_ll, crs(bathy))
bathy_crop <- crop(bathy, domain_poly_native, snap = "out")
template <- rast(ext(domain_poly_om), resolution = dx, crs = omerc_crs)
elevation <- project(bathy_crop, template, method = "bilinear")

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
  model_x_bearing <- model_x_bearing_guess
  model_y_bearing <- (model_x_bearing - 90) %% 360
} else {
  depth_funwave <- t(depth_matrix[, ncol(depth_matrix):1, drop = FALSE])
  model_x_bearing <- (model_x_bearing_guess + 180) %% 360
  model_y_bearing <- (model_x_bearing - 90) %% 360
}

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
  peak_direction_to_deg_true = bearing_to,
  model_x_bearing_deg_true = model_x_bearing,
  funwave_theta_peak_deg = theta_peak
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

# Use the median water depth in the first 100 m offshore as DEP_WK. A source
# needs finite depth: if this strip is unexpectedly dry, stop rather than
# generating an invalid case.
n_source <- max(2, min(5, floor(100 / dx)))
source_depth <- depth_funwave[seq_len(n_source), , drop = FALSE]
dep_wk <- median(source_depth[source_depth > 0], na.rm = TRUE)
if (!is.finite(dep_wk) || dep_wk <= 0) {
  stop("The buoy-side source strip is dry. Move the rotated pink domain or inspect the DEM.")
}

# Warn when the recorded waves propagate away from the buoy-side source.
if (abs(theta_peak) > 80) {
  warning(sprintf(
    paste0("Latest waves are %.1f degrees from the buoy-to-coast source normal. ",
           "Inspect the forcing direction before interpreting this run."), theta_peak
  ))
}

# FUNWAVE WK_IRR is a TMA/JONSWAP-style irregular internal wavemaker. The
# monthly IMOS file provides integral Hs/Tp/direction, not a phase-resolved
# spectrum, so this is a parametric approximation -- not a replay of the buoy.
freq_peak <- 1 / tp[i]
freq_min <- max(0.04, freq_peak / 2.5)
freq_max <- min(0.50, freq_peak * 3)
x_wk <- n_source * dx + 20       # 20 m inside the buoy-side source edge

input <- c(
  "! Port Fairy: coarse first-pass FUNWAVE-TVD simulation",
  "! Generated by port_fairy/setup_port_fairy_funwave.R",
  "TITLE = Port_Fairy_latest_buoy_5min",
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
  sprintf("ThetaPeak = %.2f", theta_peak), "Sigma_Theta = 20.0",
  "PERIODIC = F",
  "DIFFUSION_SPONGE = F", "FRICTION_SPONGE = T", "DIRECT_SPONGE = T",
  "Csp = 0.0", "CDsponge = 1.0",
  sprintf("Sponge_west_width = %.1f", 5 * dx),
  sprintf("Sponge_east_width = %.1f", 2 * dx),
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
  model_x_bearing_deg_true = model_x_bearing,
  source_edge = if (source_is_low_x) "minimum rotated x" else "maximum rotated x",
  xmin_m = xmin(template), xmax_m = xmax(template),
  ymin_m = ymin(template), ymax_m = ymax(template),
  dx_m = dx, dy_m = dx, Mglob = mglob, Nglob = nglob,
  x_axis = "buoy-side edge to coast", y_axis = "right-handed rotated y"
)
write.csv(grid_info, file.path(out_dir, "grid_metadata.csv"), row.names = FALSE)

message("Created FUNWAVE case in: ", out_dir)
message("Latest buoy forcing: Hs=", round(hs[i], 2), " m, Tp=", round(tp[i], 1),
        " s, from=", round(dir_from[i]), " degrees, at ", forcing$time_utc)
message("Grid: ", mglob, " x ", nglob, " at ", dx, " m")
