# Запускает оба пример-приложения (из исходников пакета через pkgload) и прогоняет examples.py.
# Приложения: minimal-app на 8771, custom-permissions-app на 8772. Базы временные.
$pkg = (Resolve-Path "$PSScriptRoot\..\..").Path.Replace('\', '/')
$tmp = "$env:TEMP\aa_examples"
New-Item -ItemType Directory -Force $tmp | Out-Null
$rscript = "C:\Program Files\R\R-4.6.1\bin\Rscript.exe"

# прежние процессы примеров
Get-CimInstance Win32_Process -Filter "Name='Rscript.exe'" | Where-Object { $_.CommandLine -like "*aa_examples_run*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Seconds 1

$apps = @(@{ name = "minimal-app"; port = 8771 }, @{ name = "custom-permissions-app"; port = 8772 })
foreach ($a in $apps) {
  $env:APPAUTH_EXAMPLE_DB = "$tmp\$($a.name).db"
  if (Test-Path $env:APPAUTH_EXAMPLE_DB) { [System.IO.File]::Delete($env:APPAUTH_EXAMPLE_DB) }
  $code = "aa_examples_run <- 1; pkgload::load_all('$pkg', quiet = TRUE); shiny::runApp('$pkg/inst/examples/$($a.name)', port = $($a.port), host = '127.0.0.1', launch.browser = FALSE)"
  Start-Process -FilePath $rscript -ArgumentList "--vanilla -e `"$code`"" -RedirectStandardOutput "$tmp\$($a.name).out" -RedirectStandardError "$tmp\$($a.name).err" -WindowStyle Hidden | Out-Null
}

foreach ($a in $apps) {
  $up = $false
  for ($i = 0; $i -lt 50; $i++) {
    Start-Sleep -Milliseconds 800
    try { $r = Invoke-WebRequest -Uri "http://127.0.0.1:$($a.port)" -UseBasicParsing -TimeoutSec 3; if ($r.StatusCode -eq 200) { $up = $true; break } } catch {}
  }
  "$($a.name): запущено = $up"
}

$env:PYTHONIOENCODING = "utf-8"
python -I "$PSScriptRoot\examples.py" 2>&1 | ForEach-Object { "$_" }

Get-CimInstance Win32_Process -Filter "Name='Rscript.exe'" | Where-Object { $_.CommandLine -like "*aa_examples_run*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
