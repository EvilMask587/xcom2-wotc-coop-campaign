# Run a scripted two-instance test.
#   -StepsA / -StepsB : lines "delay|command" (harness steps for instance A / B)
#   -Timeout          : seconds to wait for both "CoopHarness: done"
# Prints every CoopHarness / XCom_Net log line from both instances, then closes them.
# Env: COOP_WORKSPACE (see launch_pair.ps1). Build the mod into test-install first.
param(
  [Parameter(Mandatory)][string]$Name,
  [string[]]$StepsA = @(), [string[]]$StepsB = @(),
  [int]$Timeout = 180, [switch]$KeepOpen
)
$ErrorActionPreference = "Stop"
$root = $env:COOP_WORKSPACE; $mod = "WOTCCoopCampaign"
if (-not $root) { throw "set COOP_WORKSPACE to the folder holding test-install and test-install-b" }
$insts = @{ A = "$root\test-install\XCom2-WarOfTheChosen"; B = "$root\test-install-b\XCom2-WarOfTheChosen" }
Get-Process XCom2 -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root\*" } | Stop-Process -Force
Start-Sleep 2
foreach ($t in "A", "B") {
  $g = $insts[$t]
  if ($t -eq "B") { robocopy "$($insts.A)\XComGame\Mods\$mod" "$g\XComGame\Mods\$mod" /MIR /NFL /NDL /NJH /NJS | Out-Null }
  # the game regenerates XComModOptions.ini from DefaultModOptions.ini, so activate the mod there (test installs only)
  Set-Content "$g\XComGame\Config\DefaultModOptions.ini" "[Engine.XComModOptions]`r`nActiveMods=$mod" -Encoding ascii
  Remove-Item "$g\XComGame\Config\XComModOptions.ini" -ErrorAction SilentlyContinue
  $steps = if ($t -eq "A") { $StepsA } else { $StepsB }
  $ini = "[$mod.CoopHarness]`r`nInstanceTag=`"$t`"`r`n"
  foreach ($s in $steps) { $d, $c = $s -split '\|', 2; $ini += ".Steps=(Delay=$d,Cmd=`"$c`")`r`n" }
  Set-Content "$g\XComGame\Mods\$mod\Config\XComCoopHarness.ini" $ini -Encoding ascii
  Remove-Item "$g\XComGame\Config\XComCoopHarness.ini" -ErrorAction SilentlyContinue
  Remove-Item "$g\XComGame\Logs\Launch.log" -ErrorAction SilentlyContinue
}
& "$PSScriptRoot\launch_pair.ps1" | Write-Host
$deadline = (Get-Date).AddSeconds($Timeout)
$done = @{}
while ((Get-Date) -lt $deadline -and $done.Count -lt 2) {
  Start-Sleep 3
  foreach ($t in "A", "B") {
    $l = "$($insts[$t])\XComGame\Logs\Launch.log"
    if ((Test-Path $l) -and (Select-String -Path $l -Pattern 'CoopHarness: done' -Quiet)) { $done[$t] = $true }
  }
}
Write-Host "=== $Name : finished=$($done.Keys -join ',') ==="
foreach ($t in "A", "B") {
  Write-Host "--- $t"
  $l = "$($insts[$t])\XComGame\Logs\Launch.log"
  # "obj N none" lines from @objrange are noise; empty IDs show as gaps in the dump
  if (Test-Path $l) { Select-String -Path $l -Pattern 'CoopHarness:|CoopCampaign:|XCom_Net|XCom_Online|Critical|appError' | Where-Object { $_.Line -notmatch 'CoopHarness: obj \d+ none' } | ForEach-Object { $_.Line } | Select-Object -Last 200 }
  else { Write-Host "(no log)" }
}
if (-not $KeepOpen) { Get-Process XCom2 -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root\*" } | Stop-Process -Force }
