# Two-instance test where instance B drops and comes back.
#   -StepsA  : steps for A for the whole test (use @waitjoins 2 to wait for B's return)
#   -StepsB1 : steps for B before the drop; when B logs "CoopHarness: done" its process is
#              killed (no clean disconnect, like a crash or a lost connection)
#   -StepsB2 : steps for the new B process (connect again, wait for the history, ...)
# Prints both logs (B's first log as "B1"), then closes the instances.
# Env: COOP_WORKSPACE (see launch_pair.ps1). Build the mod into test-install first.
param(
  [Parameter(Mandatory)][string]$Name,
  [string[]]$StepsA = @(), [string[]]$StepsB1 = @(), [string[]]$StepsB2 = @(),
  [int]$Timeout = 400, [int]$Width = 960, [int]$Height = 540
)
$ErrorActionPreference = "Stop"
$root = $env:COOP_WORKSPACE; $mod = "WOTCCoopCampaign"
if (-not $root) { throw "set COOP_WORKSPACE to the folder holding test-install and test-install-b" }
$insts = @{ A = "$root\test-install\XCom2-WarOfTheChosen"; B = "$root\test-install-b\XCom2-WarOfTheChosen" }
$logs = @{ A = "$($insts.A)\XComGame\Logs\Launch.log"; B = "$($insts.B)\XComGame\Logs\Launch.log" }
$b1Log = "$($insts.B)\XComGame\Logs\Launch-B1.log"

function Write-Steps($t, $steps) {
  $ini = "[$mod.CoopHarness]`r`nInstanceTag=`"$t`"`r`n"
  foreach ($s in $steps) { $d, $c = $s -split '\|', 2; $ini += ".Steps=(Delay=$d,Cmd=`"$c`")`r`n" }
  Set-Content "$($insts[$t])\XComGame\Mods\$mod\Config\XComCoopHarness.ini" $ini -Encoding ascii
  Remove-Item "$($insts[$t])\XComGame\Config\XComCoopHarness.ini" -ErrorAction SilentlyContinue
}
function Wait-Line($t, $pattern, $seconds) {
  $by = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $by) {
    if ((Test-Path $logs[$t]) -and (Select-String -Path $logs[$t] -Pattern $pattern -Quiet)) { return $true }
    Start-Sleep 2
  }
  return $false
}

Get-Process XCom2 -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root\*" } | Stop-Process -Force
Start-Sleep 2
foreach ($t in "A", "B") {
  $g = $insts[$t]
  if ($t -eq "B") { robocopy "$($insts.A)\XComGame\Mods\$mod" "$g\XComGame\Mods\$mod" /MIR /NFL /NDL /NJH /NJS | Out-Null }
  Set-Content "$g\XComGame\Config\DefaultModOptions.ini" "[Engine.XComModOptions]`r`nActiveMods=$mod" -Encoding ascii
  Remove-Item "$g\XComGame\Config\XComModOptions.ini" -ErrorAction SilentlyContinue
  Write-Steps $t $(if ($t -eq "A") { $StepsA } else { $StepsB1 })
  Remove-Item $logs[$t] -ErrorAction SilentlyContinue
}
Remove-Item $b1Log -ErrorAction SilentlyContinue
& "$PSScriptRoot\launch_pair.ps1" -Width $Width -Height $Height | Write-Host
foreach ($t in "A", "B") { if (-not (Wait-Line $t 'CoopHarness: ready' 60)) { Write-Host "$t not ready (engine start hang?)" } }

$deadline = (Get-Date).AddSeconds($Timeout)
if (-not (Wait-Line "B" 'CoopHarness: done' $Timeout)) { Write-Host "B1 did not finish" }
# the drop: B's process dies without disconnecting
Get-Process XCom2 -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$($insts.B)\*" } | Stop-Process -Force
Start-Sleep 3
Copy-Item $logs.B $b1Log
Write-Host "B killed at $(Get-Date -Format HH:mm:ss)"
Write-Steps "B" $StepsB2
Remove-Item $logs.B -ErrorAction SilentlyContinue
# A no longer holds the engine's single-instance mutex (launch_pair.ps1 closed it), so B starts alone
$bin = "$($insts.B)\Binaries\Win64"
Start-Process "$bin\XCom2.exe" -ArgumentList "-allowconsole -nohomedir -log -windowed ResX=$Width ResY=$Height -nostartupmovies -coopTag=B" -WorkingDirectory $bin | Out-Null

$left = [int][Math]::Max(60, ($deadline - (Get-Date)).TotalSeconds + 200)
foreach ($t in "A", "B") { if (-not (Wait-Line $t 'CoopHarness: done' $left)) { Write-Host "$t did not finish" } }
Write-Host "=== $Name ==="
foreach ($p in @(@("A", $logs.A), @("B1", $b1Log), @("B2", $logs.B))) {
  Write-Host "--- $($p[0])"
  if (Test-Path $p[1]) { Select-String -Path $p[1] -Pattern 'CoopHarness:|CoopCampaign:|Critical|appError' | Where-Object { $_.Line -notmatch 'CoopHarness: obj \d+ none' } | ForEach-Object { $_.Line } | Select-Object -Last 250 }
  else { Write-Host "(no log)" }
}
Get-Process XCom2 -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root\*" } | Stop-Process -Force
