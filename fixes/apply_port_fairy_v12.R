#!/usr/bin/env Rscript

# Apply the v12 Port Fairy corrections to a checkout of
# JulianOG/run_surf_wave_forecast. Run this script from the repository root.

block <- function(...) paste(c(...), collapse = "\n")

replace_once <- function(text, old, new, label) {
  n <- length(regmatches(text, gregexpr(old, text, fixed = TRUE))[[1]])
  if (n != 1L) stop(sprintf("%s: expected one match, found %d.", label, n))
  sub(old, new, text, fixed = TRUE)
}

replace_section <- function(text, start, end, replacement, label) {
  start_at <- regexpr(start, text, fixed = TRUE)[1]
  if (start_at < 1L) stop(label, ": start marker was not found.")
  after_start <- substr(text, start_at + nchar(start), nchar(text))
  end_rel <- regexpr(end, after_start, fixed = TRUE)[1]
  if (end_rel < 1L) stop(label, ": end marker was not found.")
  end_at <- start_at + nchar(start) + end_rel - 1L
  paste0(substr(text, 1L, start_at - 1L), replacement, substr(text, end_at, nchar(text)))
}

patch_file <- function(path, patch_fun) {
  if (!file.exists(path)) stop("Missing file: ", path)
  old <- paste(readLines(path, warn = FALSE), collapse = "\n")
  new <- patch_fun(old)
  writeLines(new, path, useBytes = TRUE)
  message("Updated ", path)
}

patch_file("port_fairy/setup_port_fairy_funwave.R", function(x) {
  x <- replace_once(
    x,
    "plot_intv <- 30                  # seconds",
    "plot_intv <- 7.5                 # seconds; four times the previous output rate",
    "output interval"
  )
  x <- replace_once(
    x,
    block(
      "dir_from <- read_buoy(\"WPDI\")",
      "qc <- ncvar_get(nc, \"WAVE_quality_control\")"
    ),
    block(
      "dir_from <- read_buoy(\"WPDI\")",
      "# WPDS is the directional spread at the peak of the buoy spectrum.",
      "dir_spread <- if (\"WPDS\" %in% names(nc$var)) read_buoy(\"WPDS\") else rep(NA_real_, length(hs))",
      "qc <- ncvar_get(nc, \"WAVE_quality_control\")"
    ),
    "WPDS reader"
  )
  x <- replace_once(
    x,
    block(
      "i <- tail(which(usable), 1)",
      "",
      "# The Spotter direction is a compass FROM direction."
    ),
    block(
      "i <- tail(which(usable), 1)",
      "",
      "# First-pass directional forcing: map the measured peak directional",
      "# spread (degrees) onto FUNWAVE WK_IRR's Sigma_Theta. Keep the documented",
      "# 20-degree default only when WPDS is absent or implausible.",
      "spread_i <- dir_spread[i]",
      "sigma_theta <- if (is.finite(spread_i) && spread_i > 0 && spread_i <= 90) spread_i else 20.0",
      "",
      "# The Spotter direction is a compass FROM direction."
    ),
    "directional spread"
  )
  x <- replace_once(
    x,
    block(
      "  time_utc = format(time_utc[i], tz = \"UTC\", usetz = TRUE),",
      "  qc = qc[i], hs_m = hs[i], tp_s = tp[i],",
      "  peak_direction_from_deg_true = dir_from[i],"
    ),
    block(
      "  time_utc = format(time_utc[i], tz = \"UTC\", usetz = TRUE),",
      "  qc = qc[i], hs_m = hs[i], tp_s = tp[i],",
      "  peak_direction_from_deg_true = dir_from[i],",
      "  peak_directional_spread_deg = spread_i,",
      "  funwave_sigma_theta_deg = sigma_theta"
    ),
    "forcing metadata"
  )
  x <- replace_once(
    x,
    block(
      "freq_max <- min(0.50, freq_peak * 3)",
      "x_wk <- n_source * dx + 20       # 20 m inside the buoy-side source edge",
      "",
      "input <- c("
    ),
    block(
      "freq_max <- min(0.50, freq_peak * 3)",
      "x_wk <- n_source * dx + 20       # 20 m inside the buoy-side source edge",
      "",
      "# Do not place a sponge on the source edge: in the previous setup the",
      "# 100 m sponge overlapped the internal wavemaker and could damp generated",
      "# wave energy before it crossed the domain. Keep damping only at the far",
      "# x edge and the two lateral edges to limit reflected energy.",
      "far_x_sponge <- 5 * dx",
      "sponge_west_width <- if (source_is_low_x) 0 else far_x_sponge",
      "sponge_east_width <- if (source_is_low_x) far_x_sponge else 0",
      "",
      "input <- c("
    ),
    "source sponge"
  )
  x <- replace_once(
    x,
    block(
      "  sprintf(\"Hmo = %.3f\", hs[i]), \"GammaTMA = 3.3\",",
      "  sprintf(\"ThetaPeak = %.2f\", theta_peak), \"Sigma_Theta = 20.0\","
    ),
    block(
      "  sprintf(\"Hmo = %.3f\", hs[i]), \"GammaTMA = 3.3\",",
      "  sprintf(\"ThetaPeak = %.2f\", theta_peak),",
      "  sprintf(\"Sigma_Theta = %.2f\", sigma_theta)"
    ),
    "Sigma_Theta"
  )
  x <- replace_once(
    x,
    block(
      "  sprintf(\"Sponge_west_width = %.1f\", 5 * dx),",
      "  sprintf(\"Sponge_east_width = %.1f\", 2 * dx),"
    ),
    block(
      "  sprintf(\"Sponge_west_width = %.1f\", sponge_west_width),",
      "  sprintf(\"Sponge_east_width = %.1f\", sponge_east_width),"
    ),
    "sponge widths"
  )
  x
})

patch_file("report/port_fairy_report.Rmd", function(x) {
  x <- replace_once(
    x,
    block(
      "plot_geographic <- function(r_ll, ..., show_legend = FALSE) {",
      "  plot(r_ll, ...)"
    ),
    block(
      "plot_geographic <- function(r_ll, ..., show_legend = FALSE, range = NULL) {",
      "  # terra::plot uses range= to fix its colour scale; zlim= is for image().",
      "  if (is.null(range)) plot(r_ll, ...) else plot(r_ll, ..., range = range)"
    ),
    "geographic colour range"
  )
  x <- replace_once(
    x,
    block(
      "symmetric_limits <- function(z) {",
      "  m <- max(abs(z), na.rm = TRUE)",
      "  if (!is.finite(m) || m == 0) m <- 1e-8",
      "  c(-m, m)",
      "}",
      "",
      "depth_raster <-"
    ),
    block(
      "symmetric_limits <- function(z) {",
      "  m <- max(abs(z), na.rm = TRUE)",
      "  if (!is.finite(m) || m == 0) m <- 1e-8",
      "  c(-m, m)",
      "}",
      "",
      "positive_limits <- function(z) {",
      "  m <- max(z, na.rm = TRUE)",
      "  if (!is.finite(m) || m <= 0) m <- 1e-8",
      "  c(0, m)",
      "}",
      "",
      "depth_raster <-"
    ),
    "positive colour limits"
  )
  x <- replace_once(
    x,
    "waveheight_max <- maximum_model_field(read_all_fields(\"WaveHeight\"))",
    block(
      "# WaveHeight = T writes Hrms_##### and Havg_##### files in this FUNWAVE",
      "# revision; it does not write WaveHeight_##### files.",
      "hrms_max <- maximum_model_field(read_all_fields(\"Hrms\"))",
      "hs_peak_estimate <- if (is.null(hrms_max)) NULL else sqrt(2) * hrms_max"
    ),
    "Hrms output names"
  )
  x <- gsub("zlim = symmetric_raster_limits(depth_delta_wgs84)",
            "range = symmetric_raster_limits(depth_delta_wgs84)", x, fixed = TRUE)
  x <- gsub("zlim = eta_animation_limits", "range = eta_animation_limits", x, fixed = TRUE)
  old_section <- "## Maximum wave height over the 30-minute run"
  new_section <- block(
    "## Peak simulated significant wave-height estimate",
    "",
    "`WaveHeight = T` makes FUNWAVE write `Hrms_#####` (root-mean-square wave",
    "height) and `Havg_#####`, rather than files named `WaveHeight_#####`. The",
    "map below is the largest saved local estimate of $H_s ≈ \\sqrt{2} H_{rms}$.",
    "It is a significant-wave-height estimate, **not** the height of the single",
    "largest individual wave.",
    "",
    "```{r peak-hs, fig.cap='Largest saved simulated significant wave-height estimate (sqrt(2) times Hrms), reconstructed on the rotated grid and mapped in WGS84.'}",
    "if (is.null(hs_peak_estimate)) {",
    "  plot.new(); text(0.5, 0.5, \"No Hrms output was produced.\")",
    "} else {",
    "  if (!is.null(mask)) hs_peak_estimate[mask <= 0] <- NA_real_",
    "  hs_rotated <- model_to_rotated_raster(hs_peak_estimate, \"peak Hs estimate\")",
    "  hs_wgs84 <- write_model_output_rasters(hs_rotated, \"hs_peak_estimate_30min\")",
    "  plot_geographic(hs_wgs84, main = \"Peak simulated significant wave-height estimate (WGS84)\",",
    "                  col = hcl.colors(40, \"YlOrRd\", rev = TRUE),",
    "                  range = positive_limits(hs_peak_estimate), show_legend = TRUE)",
    "}",
    "```",
    ""
  )
  x <- replace_section(x, old_section, "## Maximum free-surface elevation", new_section,
                       "peak Hs report section")
  x <- replace_once(
    x,
    block(
      "  plot_geographic(hmax_wgs84, main = \"Maximum free-surface elevation, Hmax (WGS84)\",",
      "                  col = hcl.colors(40, \"Blue-Red 3\"),",
      "                  zlim = symmetric_limits(hmax), show_legend = TRUE)"
    ),
    block(
      "  plot_geographic(hmax_wgs84, main = \"Maximum free-surface elevation, Hmax (WGS84)\",",
      "                  col = hcl.colors(40, \"YlOrRd\", rev = TRUE),",
      "                  range = positive_limits(hmax), show_legend = TRUE)"
    ),
    "Hmax colour scale"
  )
  x
})

patch_file("scripts/render_social_assets.R", function(x) {
  x <- replace_once(
    x,
    block(
      "plot_geographic <- function(r_ll, main, col, zlim, show_legend = TRUE) {",
      "  plot(r_ll, main = main, col = col, zlim = zlim,"
    ),
    block(
      "plot_geographic <- function(r_ll, main, col, range, show_legend = TRUE) {",
      "  # terra::plot uses range= to fix its colour scale; zlim= is for image().",
      "  plot(r_ll, main = main, col = col, range = range,"
    ),
    "social geographic colour range"
  )
  x <- replace_once(
    x,
    block(
      "read_text_model <- function(path, label = basename(path)) {",
      "  as_model_xy(utils::read.table(path, header = FALSE), label)",
      "}",
      "",
      "model_to_rotated_raster <-"
    ),
    block(
      "read_text_model <- function(path, label = basename(path)) {",
      "  as_model_xy(utils::read.table(path, header = FALSE), label)",
      "}",
      "",
      "maximum_model_field <- function(fields) {",
      "  if (!length(fields)) return(NULL)",
      "  out <- fields[[1]]",
      "  if (length(fields) > 1) for (k in 2:length(fields)) out <- pmax(out, fields[[k]], na.rm = TRUE)",
      "  out[!is.finite(out)] <- NA_real_",
      "  out",
      "}",
      "",
      "model_to_rotated_raster <-"
    ),
    "maximum Hrms helper"
  )
  x <- replace_once(x, "col = hcl.colors(40, \"Blue-Red 3\"), zlim = eta_limits, show_legend = TRUE",
                    "col = hcl.colors(40, \"Blue-Red 3\"), range = eta_limits, show_legend = TRUE",
                    "social eta colour scale")
  old_start <- "# This FUNWAVE-TVD revision supports Hmax (maximum positive free-surface"
  new_block <- block(
    "# WaveHeight = T writes Hrms_##### and Havg_##### in this FUNWAVE revision.",
    "# Hrms is converted to an Hs estimate using Hs ~= sqrt(2) * Hrms, as in",
    "# the FUNWAVE example post-processing. This is not a maximum individual wave.",
    "hrms_paths <- list.files(results_dir, pattern = \"^Hrms_[0-9]{5}$\", full.names = TRUE)",
    "if (!length(hrms_paths)) stop(\"No Hrms outputs exist; WaveHeight = T should create Hrms_##### files.\")",
    "hrms_ids <- as.integer(sub(\"^Hrms_\", \"\", basename(hrms_paths)))",
    "hrms_paths <- hrms_paths[order(hrms_ids)]",
    "hrms_max <- maximum_model_field(lapply(hrms_paths, read_text_model, label = \"Hrms\"))",
    "hs_peak_estimate <- sqrt(2) * hrms_max",
    "hs_peak_estimate[!is.finite(hs_peak_estimate)] <- NA_real_",
    "if (!is.null(mask)) hs_peak_estimate[mask <= 0] <- NA_real_",
    "",
    "hs_om <- model_to_rotated_raster(hs_peak_estimate, depth_raster, source_is_low_x,",
    "                                  \"peak significant wave-height estimate\")",
    "hs_ll <- project(hs_om, \"EPSG:4326\", method = \"bilinear\")",
    "hs_file <- file.path(assets_dir, \"port-fairy-maximum-hs-estimate.png\")",
    "hs_limit <- global(hs_ll, \"max\", na.rm = TRUE)[1, 1]",
    "if (!is.finite(hs_limit) || hs_limit <= 0) hs_limit <- 1e-8",
    "grDevices::png(hs_file, width = 1000, height = 750, res = 125)",
    "tryCatch(",
    "  plot_geographic(",
    "    hs_ll, main = \"Peak simulated significant wave-height estimate\",",
    "    col = hcl.colors(40, \"YlOrRd\", rev = TRUE),",
    "    range = c(0, hs_limit), show_legend = TRUE",
    "  ),",
    "  finally = grDevices::dev.off()",
    ")",
    "if (!file.exists(hs_file) || file.info(hs_file)$size == 0) stop(\"Could not create \", hs_file)",
    "",
    "message(\"Created social assets:\")",
    "message(\"  \", full_gif)",
    "message(\"  \", final_sixth_gif)",
    "message(\"  \", hs_file)",
    ""
  )
  x <- replace_section(x, old_start, "message(\"Created social assets:\")", new_block,
                       "social peak Hs asset")
  x
})

patch_file("scripts/write_latest_manifest.R", function(x) {
  x <- replace_once(
    x,
    "maximum_wave_height_map = \"assets/port-fairy-maximum-waveheight.png\"",
    "maximum_significant_wave_height_estimate_map = \"assets/port-fairy-maximum-hs-estimate.png\"",
    "manifest asset name"
  )
  x <- replace_once(
    x,
    "maximum_wave_height_map_url = paste0(site_url, \"/\", asset_rel[[\"maximum_wave_height_map\"]])",
    "maximum_significant_wave_height_estimate_map_url = paste0(site_url, \"/\", asset_rel[[\"maximum_significant_wave_height_estimate_map\"]])",
    "manifest asset URL"
  )
  x
})

message("Done. Review with: git diff -- port_fairy/setup_port_fairy_funwave.R report/port_fairy_report.Rmd scripts/render_social_assets.R scripts/write_latest_manifest.R")
