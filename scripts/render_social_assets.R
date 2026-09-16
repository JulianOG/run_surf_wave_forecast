#!/usr/bin/env Rscript

# Produce public social-media assets as real files.  R Markdown's animation
# hook embeds GIFs in its HTML, which is perfect for the report but leaves no
# standalone file for a bot to publish.  This script deliberately repeats the
# report's grid reconstruction pathway and writes stable assets under site/.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
  stop("Usage: render_social_assets.R CASE_DIR SITE_DIR")
}

suppressPackageStartupMessages({
  library(terra)
  library(gifski)
})
options(terra.progress = 0)

case_dir <- normalizePath(args[1], mustWork = TRUE)
site_dir <- normalizePath(args[2], mustWork = TRUE)
results_dir <- file.path(case_dir, "results")
assets_dir <- file.path(site_dir, "assets")
dir.create(assets_dir, recursive = TRUE, showWarnings = FALSE)

forcing <- read.csv(file.path(case_dir, "latest_buoy_forcing.csv"),
                    check.names = FALSE)
grid <- read.csv(file.path(case_dir, "grid_metadata.csv"), check.names = FALSE)
if (nrow(forcing) != 1 || nrow(grid) != 1) {
  stop("Expected one row in forcing and grid metadata files.")
}
if (!is.finite(grid$dx_m[1]) || !is.finite(grid$total_time_s[1]) ||
    !is.finite(grid$plot_intv_s[1]) || grid$dx_m[1] <= 0 ||
    grid$total_time_s[1] <= 0 || grid$plot_intv_s[1] <= 0) {
  stop("Grid metadata must contain positive dx_m, total_time_s and plot_intv_s values.")
}
grid_tag <- paste0(sprintf("%.0f", grid$dx_m[1]), "m")
simulation_minutes <- grid$total_time_s[1] / 60
final_sixth_start_s <- (5 / 6) * grid$total_time_s[1]
eta_limits <- c(-5, 5)
eta_max_limits <- c(0, 5)
hsig_limits <- c(0, 4)
ygnbu_palette <- RColorBrewer::brewer.pal(9, "YlGnBu")
eta_animation_palette <- grDevices::colorRampPalette(ygnbu_palette)(100)

buoy_time_utc <- as.POSIXct(
  sub(" UTC$", "", forcing$time_utc[1]),
  format = "%Y-%m-%d %H:%M:%S", tz = "UTC"
)
if (is.na(buoy_time_utc)) stop("Could not parse the buoy observation time.")
port_fairy_tz <- "Australia/Melbourne"

# FUNWAVE writes [model y, model x].  Internally we consistently use
# [model x, model y] so that every output uses the same inverse transform.
as_model_xy <- function(z, label = "model field") {
  z <- as.matrix(z)
  if (all(dim(z) == c(grid$Nglob, grid$Mglob))) return(t(z))
  if (all(dim(z) == c(grid$Mglob, grid$Nglob))) return(z)
  stop(sprintf("%s has %.0f x %.0f values; expected %.0f x %.0f (y x x).",
               label, nrow(z), ncol(z), grid$Nglob, grid$Mglob))
}

read_text_model <- function(path, label = basename(path)) {
  as_model_xy(utils::read.table(path, header = FALSE), label)
}

maximum_model_field <- function(fields) {
  if (!length(fields)) return(NULL)
  out <- fields[[1]]
  if (length(fields) > 1) {
    for (k in 2:length(fields)) out <- pmax(out, fields[[k]], na.rm = TRUE)
  }
  out[!is.finite(out)] <- NA_real_
  out
}

model_to_rotated_raster <- function(z, depth_raster, source_is_low_x,
                                    label = "model field") {
  z <- as.matrix(z)
  expected <- c(grid$Mglob, grid$Nglob)
  if (!identical(dim(z), expected)) {
    stop(sprintf("%s has %.0f x %.0f values; expected Mglob x Nglob = %.0f x %.0f.",
                 label, nrow(z), ncol(z), expected[1], expected[2]))
  }

  # Invert the two matrix operations used when writing depth.txt in the case
  # setup: terra rows run north-to-south; FUNWAVE y runs in the model sense.
  gis_rows <- t(z)
  if (source_is_low_x) {
    gis_rows <- gis_rows[nrow(gis_rows):1, , drop = FALSE]
  } else {
    gis_rows <- gis_rows[, ncol(gis_rows):1, drop = FALSE]
  }

  out <- rast(depth_raster)
  values(out) <- as.vector(t(gis_rows))
  out
}

outline_from_raster <- function(r) {
  vect(rbind(
    c(xmin(r), ymin(r)), c(xmax(r), ymin(r)),
    c(xmax(r), ymax(r)), c(xmin(r), ymax(r)),
    c(xmin(r), ymin(r))
  ), type = "polygons", crs = crs(r))
}

depth_raster <- rast(file.path(
  case_dir, paste0("depth_", grid_tag, "_positive_water_depth.tif")
))
depth_from_file <- read_text_model(file.path(case_dir, "depth.txt"), "depth.txt")
source_is_low_x <- identical(grid$source_edge, "minimum rotated x")

# Use the same DEM-derived water mask as the report. Apply it in model and
# rotated-grid coordinates before projection, then again after projection to
# prevent interpolation from colouring land pixels.
dem_water_model <- is.finite(depth_from_file) & depth_from_file > 0
dem_water_mask_om <- ifel(depth_raster > 0, 1, 0)
dem_water_mask_wgs84 <- project(dem_water_mask_om, "EPSG:4326", method = "near")

apply_dem_water_mask_model <- function(z) {
  z <- as.matrix(z)
  z[!dem_water_model] <- NA_real_
  z
}

apply_dem_water_mask_om <- function(r_om) {
  r_om[is.na(dem_water_mask_om) | dem_water_mask_om <= 0] <- NA_real_
  r_om
}

# The buoy-side side of the internal wavemaker is not a coastal forecast
# product. Mask it before projection and re-apply a nearest-neighbour version
# after projection so bilinear interpolation cannot bleed values across it.
shoreward_of_paddle_model <- outer(
  (seq_len(grid$Mglob[1]) - 1) * grid$dx_m[1], seq_len(grid$Nglob[1]),
  function(x, y) x >= grid$x_wk_m[1]
)
shoreward_of_paddle_om <- model_to_rotated_raster(
  ifelse(shoreward_of_paddle_model, 1, 0), depth_raster, source_is_low_x,
  "shoreward-of-wavemaker mask"
)
shoreward_of_paddle_wgs84 <- project(shoreward_of_paddle_om, "EPSG:4326", method = "near")

apply_output_visibility_mask_model <- function(z) {
  z <- apply_dem_water_mask_model(z)
  z[!shoreward_of_paddle_model] <- NA_real_
  z
}

apply_output_visibility_mask_om <- function(r_om) {
  r_om <- apply_dem_water_mask_om(r_om)
  r_om[is.na(shoreward_of_paddle_om) | shoreward_of_paddle_om <= 0] <- NA_real_
  r_om
}

buoy_ll <- vect(matrix(c(forcing$buoy_lon, forcing$buoy_lat), ncol = 2),
                type = "points", crs = "EPSG:4326")
model_outline_ll_xy <- crds(project(outline_from_raster(depth_raster), "EPSG:4326"))
source_x_om <- if (source_is_low_x) {
  xmin(depth_raster) + grid$x_wk_m
} else {
  xmax(depth_raster) - grid$x_wk_m
}
source_line_om <- vect(rbind(
  c(source_x_om, ymin(depth_raster)),
  c(source_x_om, ymax(depth_raster))
), type = "lines", crs = crs(depth_raster))
source_line_ll_xy <- crds(project(source_line_om, "EPSG:4326"))

plot_geographic <- function(r_ll, main, col, range, show_legend = TRUE) {
  # terra::plot uses range= to fix its colour scale; zlim= is for image().
  plot(r_ll, main = main, col = col, range = range,
       xlab = "Longitude (WGS84)", ylab = "Latitude (WGS84)")
  lines(model_outline_ll_xy[, 1], model_outline_ll_xy[, 2],
        col = "black", lwd = 2)
  lines(source_line_ll_xy[, 1], source_line_ll_xy[, 2],
        col = "dodgerblue3", lwd = 2, lty = 2)
  points(crds(buoy_ll)[1, 1], crds(buoy_ll)[1, 2],
         pch = 16, col = "red", cex = 1.25)
  if (show_legend) {
    legend("bottomleft", legend = c("FUNWAVE grid", "internal wavemaker", "buoy"),
           col = c("black", "dodgerblue3", "red"),
           lwd = c(2, 2, NA), lty = c(1, 2, NA), pch = c(NA, NA, 16),
           bty = "n", cex = 0.75)
  }
}

frame_local_time <- function(elapsed_s) {
  format(buoy_time_utc + elapsed_s, "%d %b %Y %H:%M %Z", tz = port_fairy_tz)
}

add_wave_frame_annotation <- function(r_ll, elapsed_s) {
  e <- ext(r_ll)
  x_span <- xmax(e) - xmin(e)
  y_span <- ymax(e) - ymin(e)
  bearing_to <- forcing$boundary_direction_to_deg_true[1]
  direction_statistic <- forcing$boundary_direction_statistic[1]
  angle <- bearing_to * pi / 180

  # Convert a true-north bearing to longitude/latitude drawing increments.
  arrow_y <- 0.13 * y_span
  arrow_x <- arrow_y * sin(angle) / cos(mean(c(ymin(e), ymax(e))) * pi / 180)
  arrow_dy <- arrow_y * cos(angle)
  arrow_x0 <- if (arrow_x >= 0) xmin(e) + 0.08 * x_span else xmax(e) - 0.08 * x_span
  arrow_y0 <- if (arrow_dy >= 0) ymin(e) + 0.10 * y_span else ymax(e) - 0.10 * y_span
  arrows(arrow_x0, arrow_y0, arrow_x0 + arrow_x, arrow_y0 + arrow_dy,
         col = "red", lwd = 3, length = 0.10)

  label <- c(
    paste("Local:", frame_local_time(elapsed_s)),
    sprintf("Model +%02.0f:%04.1f", floor(elapsed_s / 60), elapsed_s %% 60),
    sprintf("Buoy Hs %.2f m | Tp %.1f s", forcing$hs_m[1], forcing$tp_s[1]),
    sprintf("%s waves from %.0f° (arrow travels to %.0f°)",
            tools::toTitleCase(direction_statistic),
            forcing$boundary_direction_from_deg_true[1], bearing_to)
  )
  legend("topright", legend = label, bty = "o", bg = rgb(1, 1, 1, 0.82),
         cex = 0.74, text.col = "black")
}

mask_path <- file.path(results_dir, "mask_00000")
mask <- if (file.exists(mask_path)) read_text_model(mask_path, "mask") else NULL
mask_wgs84 <- NULL
if (!is.null(mask)) {
  mask_om <- model_to_rotated_raster(mask, depth_raster, source_is_low_x, "mask")
  mask_wgs84 <- project(mask_om, "EPSG:4326", method = "near")
}

apply_water_masks_wgs84 <- function(r_ll) {
  dem_mask <- dem_water_mask_wgs84
  if (!compareGeom(dem_mask, r_ll, stopOnError = FALSE)) {
    dem_mask <- resample(dem_mask, r_ll, method = "near")
  }
  r_ll[is.na(dem_mask) | dem_mask <= 0] <- NA_real_

  paddle_mask <- shoreward_of_paddle_wgs84
  if (!compareGeom(paddle_mask, r_ll, stopOnError = FALSE)) {
    paddle_mask <- resample(paddle_mask, r_ll, method = "near")
  }
  r_ll[is.na(paddle_mask) | paddle_mask <= 0] <- NA_real_

  if (is.null(mask_wgs84)) return(r_ll)
  wet_mask <- mask_wgs84
  if (!compareGeom(wet_mask, r_ll, stopOnError = FALSE)) {
    wet_mask <- resample(wet_mask, r_ll, method = "near")
  }
  r_ll[is.na(wet_mask) | wet_mask <= 0] <- NA_real_
  r_ll
}
eta_paths <- list.files(results_dir, pattern = "^eta_[0-9]{5}$", full.names = TRUE)
# The FUNWAVE suffix is an output-file number, not time in seconds.  Convert
# it with PLOT_INTV before selecting the final sixth or annotating a frame.
eta_file_number <- as.integer(sub("^eta_", "", basename(eta_paths)))
eta_order <- order(eta_file_number)
eta_paths <- eta_paths[eta_order]
eta_file_number <- eta_file_number[eta_order]
eta_time <- eta_file_number * grid$plot_intv_s
if (!length(eta_paths)) stop("No eta outputs exist; cannot make social GIFs.")
if (any(!is.finite(eta_time)) || any(eta_time < 0) ||
    max(eta_time) > grid$total_time_s[1] + grid$plot_intv_s[1] ||
    max(eta_time) < grid$total_time_s[1] - grid$plot_intv_s[1]) {
  stop("eta file numbers do not map to the configured simulation period.")
}

eta_frames <- lapply(eta_paths, function(path) {
  z <- read_text_model(path, basename(path))
  if (!is.null(mask)) z[mask <= 0] <- NA_real_
  apply_output_visibility_mask_model(z)
})
draw_eta_frame <- function(k) {
  r_om <- model_to_rotated_raster(eta_frames[[k]], depth_raster, source_is_low_x,
                                  basename(eta_paths[k]))
  r_om <- apply_output_visibility_mask_om(r_om)
  r_ll <- project(r_om, "EPSG:4326", method = "bilinear")
  r_ll <- apply_water_masks_wgs84(r_ll)
  plot_geographic(
    r_ll,
    main = sprintf("Port Fairy free-surface elevation: t = %.1f s", eta_time[k]),
    col = eta_animation_palette, range = eta_limits, show_legend = TRUE
  )
  add_wave_frame_annotation(r_ll, eta_time[k])
}

write_animation <- function(indices, output_file) {
  if (!length(indices)) stop("No model frames selected for ", basename(output_file))
  frame_dir <- tempfile("port-fairy-gif-frames-")
  dir.create(frame_dir)
  on.exit(unlink(frame_dir, recursive = TRUE, force = TRUE), add = TRUE)
  png_files <- file.path(frame_dir, sprintf("frame-%03d.png", seq_along(indices)))

  for (j in seq_along(indices)) {
    grDevices::png(png_files[j], width = 1000, height = 750, res = 125)
    tryCatch(
      draw_eta_frame(indices[j]),
      finally = grDevices::dev.off()
    )
  }

  # A six-second looping GIF, regardless of the number of saved model frames.
  gifski::gifski(png_files, gif_file = output_file,
                 delay = 6 / length(indices), loop = TRUE, progress = FALSE)
  if (!file.exists(output_file) || file.info(output_file)$size == 0) {
    stop("gifski did not create ", output_file)
  }
}

full_gif <- file.path(assets_dir, "port-fairy-full.gif")
final_sixth_gif <- file.path(assets_dir, "port-fairy-final-sixth.gif")
# eta_00000 is the zero-time initial condition, not an evolved model state.
# Deliberately exclude it from the full animation while retaining it for eta_max.
full_indices <- which(eta_time > 0)
write_animation(full_indices, full_gif)
final_sixth_indices <- which(eta_time >= final_sixth_start_s)
write_animation(final_sixth_indices, final_sixth_gif)

# Maximum positive free-surface elevation at each grid cell across all saved
# eta outputs. This is not individual wave height or significant wave height.
eta_max <- do.call(pmax, c(eta_frames, na.rm = TRUE))
eta_max[!is.finite(eta_max)] <- NA_real_

eta_max_om <- model_to_rotated_raster(eta_max, depth_raster, source_is_low_x,
                                      "maximum free-surface elevation")
eta_max_om <- apply_output_visibility_mask_om(eta_max_om)
eta_max_ll <- project(eta_max_om, "EPSG:4326", method = "bilinear")
eta_max_ll <- apply_water_masks_wgs84(eta_max_ll)
eta_max_file <- file.path(assets_dir, "port-fairy-maximum-eta.png")
grDevices::png(eta_max_file, width = 1000, height = 750, res = 125)
tryCatch(
  plot_geographic(
    eta_max_ll,
    main = sprintf("Maximum free-surface elevation across %.0f minutes", simulation_minutes),
    col = ygnbu_palette,
    range = eta_max_limits,
    show_legend = TRUE
  ),
  finally = grDevices::dev.off()
)
if (!file.exists(eta_max_file) || file.info(eta_max_file)$size == 0) {
  stop("Could not create ", eta_max_file)
}

# WaveHeight = T writes Hsig through FUNWAVE's mean-wave diagnostic.  It is
# the suitable public wave-height product; eta_max above remains a crest map.
hsig_paths <- list.files(results_dir, pattern = "^Hsig_[0-9]{5}$", full.names = TRUE)
if (!length(hsig_paths)) {
  stop("No Hsig outputs exist. Check that WaveHeight = T, STEADY_TIME and T_INTV_mean are in input.txt.")
}
hsig_number <- as.integer(sub("^Hsig_", "", basename(hsig_paths)))
hsig_paths <- hsig_paths[order(hsig_number)]
hsig_frames <- lapply(hsig_paths, function(path) {
  z <- read_text_model(path, basename(path))
  if (!is.null(mask)) z[mask <= 0] <- NA_real_
  apply_output_visibility_mask_model(z)
})
hsig_max <- maximum_model_field(hsig_frames)
hsig_max_om <- model_to_rotated_raster(hsig_max, depth_raster, source_is_low_x,
                                       "peak simulated significant wave height")
hsig_max_om <- apply_output_visibility_mask_om(hsig_max_om)
hsig_max_ll <- project(hsig_max_om, "EPSG:4326", method = "bilinear")
hsig_max_ll <- apply_water_masks_wgs84(hsig_max_ll)
hsig_max_file <- file.path(assets_dir, "port-fairy-maximum-hsig.png")
grDevices::png(hsig_max_file, width = 1000, height = 750, res = 125)
tryCatch(
  plot_geographic(
    hsig_max_ll,
    main = sprintf("Peak simulated significant wave height across %.0f minutes", simulation_minutes),
    col = ygnbu_palette,
    range = hsig_limits,
    show_legend = TRUE
  ),
  finally = grDevices::dev.off()
)
if (!file.exists(hsig_max_file) || file.info(hsig_max_file)$size == 0) {
  stop("Could not create ", hsig_max_file)
}

message("Created social assets:")
message("Animation timing: full run 0--", sprintf("%.1f", grid$total_time_s[1]),
        " s; full GIF skips 0.0 s and uses saved frames ",
        sprintf("%.1f", min(eta_time[full_indices])), "--",
        sprintf("%.1f", max(eta_time[full_indices])),
        " s; final-sixth saved frames ", sprintf("%.1f", min(eta_time[final_sixth_indices])),
        "--", sprintf("%.1f", max(eta_time[final_sixth_indices])), " s")
message("  ", full_gif)
message("  ", final_sixth_gif)
message("  ", eta_max_file)
message("  ", hsig_max_file)
