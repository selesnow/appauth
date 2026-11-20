# Check a numeric settings parameter
#
# @param x Value.
# @param name Parameter name for the error message.
# @param whole Require a whole number.
# @param call Environment for the error message.
#
# @returns The value (invisibly), or an error of class
# `appauth_error_settings`.
# @noRd
aa_check_positive <- function(
  x,
  name,
  whole = TRUE,
  call = rlang::caller_env()
) {
  ok <- is.numeric(x) &&
    length(x) == 1 &&
    is.finite(x) &&
    x > 0 &&
    (!whole || x == round(x))

  if (!ok) {
    rlang::abort(
      paste0(
        "`",
        name,
        "` must be a positive ",
        if (whole) "whole " else "",
        "number."
      ),
      class = "appauth_error_settings",
      call = call
    )
  }

  invisible(x)
}

# Check a logical settings parameter
#
# @inheritParams aa_check_positive
#
# @returns The value (invisibly), or an error of class
# `appauth_error_settings`.
# @noRd
aa_check_flag <- function(x, name, call = rlang::caller_env()) {
  if (!(is.logical(x) && length(x) == 1 && !is.na(x))) {
    rlang::abort(
      paste0("`", name, "` must be TRUE or FALSE."),
      class = "appauth_error_settings",
      call = call
    )
  }

  invisible(x)
}

# Database date in local time for display
#
# Dates are stored in the database in UTC as text `"YYYY-MM-DD HH:MM:SS"`.
#
# @param x Vector of dates from the database (text or `NA`).
# @param missing Text for empty values.
#
# @returns A character vector `"YYYY-MM-DD HH:MM"` in the server time zone.
# @noRd
aa_format_db_time <- function(x, missing = "") {
  x <- as.character(x)
  parsed <- as.POSIXct(x, tz = "UTC", format = "%Y-%m-%d %H:%M:%S")
  tz <- Sys.timezone()
  out <- format(parsed, "%Y-%m-%d %H:%M", tz = if (is.na(tz)) "" else tz)
  out[is.na(parsed)] <- missing
  out
}

# Whether this is a single non-empty string
#
# @param x Value.
#
# @returns `TRUE` or `FALSE`.
# @noRd
aa_is_string <- function(x) {
  is.character(x) && length(x) == 1 && !is.na(x) && nzchar(x)
}
