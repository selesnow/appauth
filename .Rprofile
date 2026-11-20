
delete_desktop_ini <- function(path = ".") {
  ps_command <- sprintf(
    "Get-ChildItem -LiteralPath %s -Filter 'desktop.ini' -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue",
    shQuote(normalizePath(path))
  )
  
  system2("powershell", args = c("-Command", ps_command))
}

delete_desktop_ini()
