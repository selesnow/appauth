$d = "$env:TEMP\aa_e2e"
$dd = $d.Replace('\', '/')
if (Test-Path "$d\app.pid") {
  $pidApp = [int](Get-Content "$d\app.pid")
  $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$pidApp" -ErrorAction SilentlyContinue
  if ($proc -and $proc.CommandLine -like "*aa_e2e*") { Stop-Process -Id $pidApp -Force; "остановлен старый $pidApp" }
}
Start-Sleep -Seconds 1
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" --vanilla "$d\prepare_db.R" | Out-Null
$env:AA_DB = "$d\e2e.db"; $env:AA_LOG = "$d\events.log"
if (Test-Path $env:AA_LOG) { [System.IO.File]::Delete($env:AA_LOG) }
$app = Start-Process -FilePath "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" -ArgumentList "--vanilla -e `"shiny::runApp('$dd/app', port = 8765, host = '127.0.0.1', launch.browser = FALSE)`"" -RedirectStandardOutput "$d\app.out" -RedirectStandardError "$d\app.err" -WindowStyle Hidden -PassThru
$app.Id | Out-File "$d\app.pid"
$up = $false
for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Milliseconds 750; try { $r = Invoke-WebRequest -Uri "http://127.0.0.1:8765" -UseBasicParsing -TimeoutSec 3; if ($r.StatusCode -eq 200) { $up = $true; break } } catch {} }
"новое приложение запущено: $up (PID $($app.Id))"
$env:PYTHONIOENCODING = "utf-8"
python -I "$d\e2e.py" 2>&1 | ForEach-Object { "$_" } | Select-Object -Last 40
"--- события приложения:"
Get-Content "$d\events.log" -Encoding UTF8
