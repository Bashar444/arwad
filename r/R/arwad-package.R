#' arwad: compile loop-heavy R functions to native code
#'
#' [aw_compile()] turns a function written in a statistical subset of R into
#' native code through the Goose language, keeping GNU R's results. Use
#' [aw_explain()] to see how a compiled function runs, [aw_source()] to read
#' the generated Goose, and [aw_toolchain()] to check the build tools.
#'
#' Options: `arwad.goose` (path to the `goose` executable), `arwad.cache_dir`
#' (where built libraries are cached; by default
#' `tools::R_user_dir("arwad", "cache")`), `arwad.verbose` (report each
#' native build).
#'
#' @keywords internal
"_PACKAGE"
