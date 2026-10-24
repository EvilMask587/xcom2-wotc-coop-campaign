# Two-instance test suite: runs each scenario with run_pair_test.ps1 and checks both logs.
# Every scenario must: finish on both instances, end with equal fingerprints on A and B
# (last "@histinfo"), log no DESYNC / crash / duplicate crew ID / stale room / harness
# timeout, and log every line in its Expect lists. Prints PASS/FAIL per scenario.
# Usage: tools\test_suite.ps1 [-Only name1,name2]   (env as for run_pair_test.ps1)
param([string[]]$Only = @())
$ErrorActionPreference = "Stop"
$root = $env:COOP_WORKSPACE
if (-not $root) { throw "set COOP_WORKSPACE" }
$logs = @{ A = "$root\test-install\XCom2-WarOfTheChosen\XComGame\Logs\Launch.log"; B = "$root\test-install-b\XCom2-WarOfTheChosen\XComGame\Logs\Launch.log" }

# A hosts a cheat-start campaign and holds the baton; B joins and enters the Avenger as mirror.
$hostA = @("2|@newcampaign", "20|@histinfo", "1|MPCreateServer 7778", "1|@waitconn", "1|@baton", "2|MPSendHistory")
$joinB = @("45|@connect 127.0.0.1 7778", "1|@waitconn", "1|@waithist 100", "1|@mirror")

$scenarios = [ordered]@{
  # resources and new units both ways; the grant goes out right after a frame (command/merge race)
  "baton-objects" = @{
    A = $hostA + @("60|GiveScientist", "0.01|@grant", "25|@batonreq", "1|@waitbaton", "1|GiveEngineer", "1|GiveResource Supplies 77", "8|@crewinfo 4", "1|@histinfo")
    B = $joinB + @("1|@waitbaton", "0.01|GiveEngineer", "0.01|GiveResource AlienAlloy 9", "40|@crewinfo 4", "1|@histinfo")
    ExpectA = @("baton granted epoch=1", "baton grant received epoch=2", "in sync")
    ExpectB = @("baton grant received epoch=1", "baton=mine", "baton granted epoch=2", "in sync")
  }
  # a facility is removed and built again; B swaps the room map both times
  "facility" = @{
    A = $hostA + @("30|@hud", "8|@clearroom 3", "10|@buildroom 3 Laboratory", "8|@rooms", "5|@histinfo")
    B = $joinB + @("20|@hud", "40|@rooms", "1|@histinfo")
    ExpectA = @("clearroom 3 removed facility", "buildroom 3 facility")
    ExpectB = @("room 3 swap AVG_Laboratory_A -> AVG_ER_A", "room 3 swap AVG_ER_A -> AVG_Laboratory_A", "in sync")
  }
  # the player without the baton cannot create objects
  "blocked-without-baton" = @{
    A = $hostA + @("70|GiveEngineer", "15|@crewinfo 3", "1|@histinfo")
    B = $joinB + @("40|GiveScientist", "35|@crewinfo 3", "1|@histinfo")
    ExpectA = @()
    ExpectB = @("blocked frame without baton", "in sync")
  }
  # edit screens: requests wait while the holder has an edit screen (Geoscape) open
  "edit-gate" = @{
    A = $hostA + @("25|@screens", "3|@hud", "12|@open research", "16|@screens", "10|@close", "5|@histinfo")
    B = $joinB + @("15|@open research", "15|@screens", "15|@close", "15|@histinfo")
    ExpectA = @("baton request deferred: edit screen open", "last edit screen closed, handing over the requested baton", "edit screen UIChooseResearch opened without baton")
    ExpectB = @("edit screen UIChooseResearch opened without baton", "baton=mine", "baton request deferred: edit screen open", "last edit screen closed, handing over the requested baton")
  }
  # HUD panel button, holder's replies, Cancel in the wait dialog
  "panel-replies" = @{
    A = $hostA + @("20|@close", "30|@hud", "25|@histinfo")
    B = $joinB + @("15|@open research", "3|@cancelwait", "3|@ask", "15|@panel", "30|@nobaton", "1|@ask", "3|@panel", "5|@histinfo")
    ExpectA = @("baton request deferred: edit screen open", "baton request ignored: not mine")
    ExpectB = @("waiting for baton cancelled, closing UIChooseResearch", "baton request: already sent", "baton request queued by partner", "baton=mine", "baton request answered: partner does not hold it")
  }
}

# matched case-sensitively: the engine logs e.g. "MaxStaleCacheSize" at start
$forbidden = 'DESYNC|Crash Detected|duplicateIDs=[1-9]|STALE loaded=|wait \w+ TIMEOUT|appError'
$results = @()
foreach ($name in $scenarios.Keys) {
  if ($Only.Count -gt 0 -and $Only -notcontains $name) { continue }
  $s = $scenarios[$name]
  & "$PSScriptRoot\run_pair_test.ps1" -Name $name -StepsA $s.A -StepsB $s.B -Timeout 300 | Out-Null
  $fail = @()
  foreach ($t in "A", "B") {
    if (-not (Test-Path $logs[$t])) { $fail += "$t no log"; continue }
    $text = Get-Content $logs[$t] -Raw
    if ($text -notmatch 'CoopHarness: done') { $fail += "$t did not finish" }
    $bad = Select-String -Path $logs[$t] -Pattern $forbidden -CaseSensitive | Select-Object -First 3
    foreach ($b in $bad) { $fail += "$t forbidden: $($b.Line.Trim())" }
    foreach ($e in $s["Expect$t"]) {
      if (-not $text.Contains($e)) { $fail += "$t missing: $e" }
    }
  }
  $fp = @{}
  foreach ($t in "A", "B") {
    $last = Select-String -Path $logs[$t] -Pattern 'CoopHarness: hist frames=\d+ index=\d+ fp=(\S+)' -ErrorAction SilentlyContinue | Select-Object -Last 1
    $fp[$t] = if ($last) { $last.Matches[0].Groups[1].Value } else { "" }
  }
  if (-not $fp.A -or $fp.A -ne $fp.B) { $fail += "final fingerprints differ: A=$($fp.A) B=$($fp.B)" }
  $status = if ($fail.Count -eq 0) { "PASS" } else { "FAIL" }
  Write-Host ("{0} {1}" -f $status, $name)
  foreach ($f in $fail) { Write-Host "     $f" }
  $results += [pscustomobject]@{ Name = $name; Status = $status; Fp = $fp.A }
}
$passed = ($results | Where-Object Status -eq "PASS").Count
Write-Host "=== $passed/$($results.Count) passed $(Get-Date -Format 'yyyy-MM-dd HH:mm') ==="
