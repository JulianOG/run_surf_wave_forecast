#!/usr/bin/env Rscript

# Create the small, stable public contract used by an independent social bot.
# It is deliberately generated only after the report, GIFs and map PNG exist.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3) {
  stop("Usage: write_latest_manifest.R CASE_DIR SITE_DIR SITE_URL")
}

case_dir <- normalizePath(args[1], mustWork = TRUE)
site_dir <- normalizePath(args[2], mustWork = TRUE)
site_url <- sub("/+$", "", args[3])

asset_rel <- c(
  full_animation = "assets/port-fairy-full.gif",
  final_sixth_animation = "assets/port-fairy-final-sixth.gif",
  maximum_significant_wave_height_estimate_map = "assets/port-fairy-maximum-hs-estimate.png"
)
asset_paths <- file.path(site_dir, asset_rel)
if (!all(file.exists(asset_paths))) {
  stop("Cannot write latest.json because one or more social assets are missing: ",
       paste(asset_rel[!file.exists(asset_paths)], collapse = ", "))
}

forcing <- read.csv(file.path(case_dir, "latest_buoy_forcing.csv"),
                    check.names = FALSE)
grid <- read.csv(file.path(case_dir, "grid_metadata.csv"), check.names = FALSE)
if (nrow(forcing) != 1 || nrow(grid) != 1) {
  stop("Expected one row in both forcing and grid metadata files.")
}

buoy_time_utc <- as.POSIXct(
  sub(" UTC$", "", forcing$time_utc[1]),
  format = "%Y-%m-%d %H:%M:%S", tz = "UTC"
)
if (is.na(buoy_time_utc)) stop("Could not parse the buoy observation time.")

run_id <- paste0(
  "port-fairy-",
  format(buoy_time_utc, "%Y%m%dT%H%M%SZ", tz = "UTC")
)
qc <- as.integer(forcing$qc[1])
post_eligible <- identical(qc, 1L)

manifest <- list(
  schema_version = 1,
  run_id = run_id,
  generated_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  report_url = paste0(site_url, "/"),
  assets = list(
    animation_full_gif_url = paste0(site_url, "/", asset_rel[["full_animation"]]),
    animation_final_sixth_gif_url = paste0(site_url, "/", asset_rel[["final_sixth_animation"]]),
    maximum_significant_wave_height_estimate_map_url = paste0(site_url, "/", asset_rel[["maximum_significant_wave_height_estimate_map"]])
  ),
  buoy = list(
    observation_time_utc = format(buoy_time_utc, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    observation_time_local = format(
      buoy_time_utc, "%Y-%m-%d %H:%M:%S %Z", tz = "Australia/Melbourne"
    ),
    time_zone = "Australia/Melbourne",
    qc = qc,
    hs_m = as.numeric(forcing$hs_m[1]),
    tp_s = as.numeric(forcing$tp_s[1]),
    peak_direction_from_deg_true = as.numeric(forcing$peak_direction_from_deg_true[1]),
    peak_direction_to_deg_true = as.numeric(forcing$peak_direction_to_deg_true[1])
  ),
  model = list(
    duration_minutes = as.numeric(grid$total_time_s[1]) / 60,
    grid_resolution_m = as.numeric(grid$dx_m[1]),
    source_edge = as.character(grid$source_edge[1]),
    status = "success"
  ),
  social = list(
    post_eligible = post_eligible,
    reason = if (post_eligible) "buoy_qc_good" else "buoy_qc_not_good"
  )
)

jsonlite::write_json(
  manifest, file.path(site_dir, "latest.json"),
  auto_unbox = TRUE, pretty = TRUE, na = "null"
)

