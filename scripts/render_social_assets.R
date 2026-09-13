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
  stop(sprintf("%s has %d x %d values; expected %d x %d (y x x).",
               label, nrow(z), ncol(z), grid$Nglob, grid$Mglob))
}

read_text_model <- function(path, label = basename(path)) {
  as_model_xy(utils::read.table(path, header = FALSE), label)
}

maximum_model_field <- function(fields) {
  if (!length(fields)) return(NULL)
  out <- fields[[1]]
  if (length(fields) > 1) for (k in 2:length(fields)) out <- pmax(out, fields[[k]], na.rm = TRUE)
  out[!is.finite(out)] <- NA_real_
  out
}

model_to_rotated_raster <- function(z, depth_raster, source_is_low_x,
                                    label = "model field") {
  z <- as.matrix(z)
  expected <- c(grid$Mglob, grid$Nglob)
  if (!identical(dim(z), expected)) {
    stop(sprintf("%s has %d x %d values; expected Mglob x Nglob = %d x %d.",
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

depth_raster <- rast(file.path(case_dir, "depth_20m_positive_water_depth.tif"))
source_is_low_x <- identical(grid$source_edge, "minimum rotated x")
buoy_ll <- vect(matrix(c(forcing$buoy_lon, forcing$buoy_lat), ncol = 2),
                type = "points", crs = "EPSG:4326")
model_outline_ll_xy <- crds(project(outline_from_raster(depth_raster), "EPSG:4326"))

plot_geographic <- function(r_ll, main, col, range, show_legend = TRUE) {
  # terra::plot uses range= to fix its colour scale; zlim= is for image().
  plot(r_ll, main = main, col = col, range = range,
       xlab = "Longitude (WGS84)", ylab = "Latitude (WGS84)")
  lines(model_outline_ll_xy[, 1], model_outline_ll_xy[, 2],
        col = "black", lwd = 2)
  points(crds(buoy_ll)[1, 1], crds(buoy_ll)[1, 2],
         pch = 16, col = "red", cex = 1.25)
  if (show_legend) {
    legend("bottomleft", legend = c("FUNWAVE grid", "buoy"),
           col = c("black", "red"), lwd = c(2, NA), pch = c(NA, 16),
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
  bearing_to <- forcing$peak_direction_to_deg_true[1]
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
    sprintf("Model +%02d:%02d", elapsed_s %/% 60, elapsed_s %% 60),
    sprintf("Buoy Hs %.2f m | Tp %.1f s", forcing$hs_m[1], forcing$tp_s[1]),
    sprintf("Waves from %.0f° (arrow travels to %.0f°)",
            forcing$peak_direction_from_deg_true[1], bearing_to)
  )
  legend("topright", legend = label, bty = "o", bg = rgb(1, 1, 1, 0.82),
         cex = 0.74, text.col = "black")
}

mask_path <- file.path(results_dir, "mask_00000")
mask <- if (file.exists(mask_path)) read_text_model(mask_path, "mask") else NULL
eta_paths <- list.files(results_dir, pattern = "^eta_[0-9]{5}$", full.names = TRUE)
# The FUNWAVE suffix is an output-file number, not time in seconds.  Convert
# it with PLOT_INTV before selecting the final sixth or annotating a frame.
eta_file_number <- as.integer(sub("^eta_", "", basename(eta_paths)))
eta_order <- order(eta_file_number)
eta_paths <- eta_paths[eta_order]
eta_file_number <- eta_file_number[eta_order]
eta_time <- eta_file_number * grid$plot_intv_s
if (!length(eta_paths)) stop("No eta outputs exist; cannot make social GIFs.")

eta_frames <- lapply(eta_paths, function(path) {
  z <- read_text_model(path, basename(path))
  if (!is.null(mask)) z[mask <= 0] <- NA_real_
  z
})
eta_amplitude <- max(vapply(eta_frames, function(z) {
  value <- max(abs(z), na.rm = TRUE)
  if (is.finite(value)) value else 0
}, numeric(1)))
if (!is.finite(eta_amplitude) || eta_amplitude == 0) eta_amplitude <- 1e-8
eta_limits <- c(-eta_amplitude, eta_amplitude)

draw_eta_frame <- function(k) {
  r_om <- model_to_rotated_raster(eta_frames[[k]], depth_raster, source_is_low_x,
                                  basename(eta_paths[k]))
  r_ll <- project(r_om, "EPSG:4326", method = "bilinear")
  plot_geographic(
    r_ll,
    main = sprintf("Port Fairy free-surface elevation: t = %d s", eta_time[k]),
    col = hcl.colors(40, "Blue-Red 3"), range = eta_limits, show_legend = TRUE
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
write_animation(seq_along(eta_frames), full_gif)
final_sixth_indices <- which(eta_time >= (5 / 6) * grid$total_time_s)
write_animation(final_sixth_indices, final_sixth_gif)

# WaveHeight = T writes Hrms_##### and Havg_##### in this FUNWAVE revision.
# Hrms is converted to an Hs estimate using Hs ~= sqrt(2) * Hrms, as in
# the FUNWAVE example post-processing. This is not a maximum individual wave.
hrms_paths <- list.files(results_dir, pattern = "^Hrms_[0-9]{5}$", full.names = TRUE)
if (!length(hrms_paths)) stop("No Hrms outputs exist; WaveHeight = T should create Hrms_##### files.")
hrms_ids <- as.integer(sub("^Hrms_", "", basename(hrms_paths)))
hrms_paths <- hrms_paths[order(hrms_ids)]
hrms_max <- maximum_model_field(lapply(hrms_paths, read_text_model, label = "Hrms"))
hs_peak_estimate <- sqrt(2) * hrms_max
hs_peak_estimate[!is.finite(hs_peak_estimate)] <- NA_real_
if (!is.null(mask)) hs_peak_estimate[mask <= 0] <- NA_real_

hs_om <- model_to_rotated_raster(hs_peak_estimate, depth_raster, source_is_low_x,
                                  "peak significant wave-height estimate")
hs_ll <- project(hs_om, "EPSG:4326", method = "bilinear")
hs_file <- file.path(assets_dir, "port-fairy-maximum-hs-estimate.png")
hs_limit <- global(hs_ll, "max", na.rm = TRUE)[1, 1]
if (!is.finite(hs_limit) || hs_limit <= 0) hs_limit <- 1e-8
grDevices::png(hs_file, width = 1000, height = 750, res = 125)
tryCatch(
  plot_geographic(
    hs_ll, main = "Peak simulated significant wave-height estimate",
    col = hcl.colors(40, "YlOrRd", rev = TRUE),
    range = c(0, hs_limit), show_legend = TRUE
  ),
  finally = grDevices::dev.off()
)
if (!file.exists(hs_file) || file.info(hs_file)$size == 0) stop("Could not create ", hs_file)

message("Created social assets:")
message("  ", full_gif)
message("  ", final_sixth_gif)
message("  ", hs_file)
message("Created social assets:")
message("  ", full_gif)
message("  ", final_sixth_gif)
message("  ", wave_file)
