# Two-instance test suite: runs each scenario with run_pair_test.ps1 and checks both logs.
# Every scenario must: finish on both instances, end with equal fingerprints on A and B
# (last "@histinfo"), log no broken version link (@verchain bad=), no DESYNC / crash / duplicate crew ID / stale room / harness
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
  # resources and new units both ways; the grant goes out right after a frame (command/merge race).
  # The host crashed in 5 of 11 runs here before AlignHistory (Avenger map item walking back
  # through a merged HQ version); @walkback makes that lookup over the last 20 frames
  "baton-objects" = @{
    A = $hostA + @("60|GiveScientist", "0.01|@grant", "25|@batonreq", "1|@waitbaton", "1|@walkback 20", "1|GiveEngineer", "1|GiveResource Supplies 77", "8|@crewinfo 4", "1|@verchain", "1|@histinfo")
    B = $joinB + @("1|@waitbaton", "0.01|GiveEngineer", "0.01|GiveResource AlienAlloy 9", "40|@crewinfo 4", "1|@walkback 20", "1|@verchain", "1|@histinfo")
    ExpectA = @("baton granted epoch=1", "baton grant received epoch=2", "in sync", "walkback frames=20", "verchain objects=")
    ExpectB = @("baton grant received epoch=1", "baton=mine", "baton granted epoch=2", "in sync", "walkback frames=20", "verchain objects=")
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
  # the Geoscape clock: research finishes during a scan; the partner's memory clock follows,
  # and after the handoff time continues forward on both (the final fingerprints carry the hour)
  "clock" = @{
    A = $hostA + @("15|@close", "2|@research AlienBiotech", "1|@scan", "20|@pause", "1|@time", "3|@hud", "45|@time", "1|@histinfo")
    B = $joinB + @("45|@time", "1|@ask", "3|@waitbaton", "1|@geoscape", "3|@scan", "5|@pause", "1|@time", "2|@hud", "15|@time", "1|@histinfo")
    ExpectA = @("research started AlienBiotech", "clock set to t2035-3-")
    ExpectB = @("clock set to t2035-3-", "baton=mine")
  }
  # bursts of frames in one tick both ways (the network layer lost frames sent one by one)
  "burst" = @{
    A = $hostA + @("15|@close", "3|@hud", "5|@grant", "40|@batonreq", "1|@waitbaton", "3|@burst 10", "3|@burst 50", "15|@histinfo")
    B = $joinB + @("1|@waitbaton", "3|@burst 10", "3|@burst 50", "60|@histinfo")
    ExpectA = @("sent batch of 50 frames", "in sync")
    ExpectB = @("sent batch of 50 frames", "in sync")
  }
  # the client holding the baton saves while sending: this crashed it before saves were
  # disabled on the client (CoopAutosaveMgr); the host still saves while sending
  "client-save" = @{
    A = $hostA + @("15|@close", "3|@hud", "5|@grant", "45|@batonreq", "1|@waitbaton", "1|@autosave", "0.05|@burst 5", "15|@histinfo")
    B = $joinB + @("1|@waitbaton", "5|@autosave", "0.05|@burst 5", "5|@autosave", "0.05|@burst 5", "5|@autosave", "45|@histinfo")
    ExpectA = @("in sync")
    ExpectB = @("autosave skipped: co-op client", "sent batch", "in sync")
  }
  # manual saves on the client: the pause menu's Save item is disabled and the save screen
  # closes; the host's pause menu keeps Save
  "client-save-menu" = @{
    A = $hostA + @("15|@close", "3|@hud", "3|@pausemenu", "2|@screens", "1|@close", "40|@histinfo")
    B = $joinB + @("10|@close", "3|@hud", "3|@pausemenu", "2|@screens", "1|@savescreen", "2|@screens", "1|@close", "5|@histinfo")
    ExpectA = @("screens UIPauseMenu")
    ExpectB = @("pause menu: save disabled on co-op client", "save screen closed: co-op client", "screens UIPauseMenu")
  }
  # HUD panel button, holder's replies, Cancel in the wait dialog
  "panel-replies" = @{
    # A keeps its edit screen until well after B's Cancel: with 30 s the handover once came
    # 0.4 s before B's Cancel (the two instances' clocks differ by the launch offset)
    A = $hostA + @("20|@close", "40|@hud", "15|@histinfo")
    B = $joinB + @("15|@open research", "3|@cancelwait", "3|@ask", "15|@panel", "30|@nobaton", "1|@ask", "3|@panel", "5|@histinfo")
    ExpectA = @("baton request deferred: edit screen open", "baton request ignored: not mine")
    ExpectB = @("waiting for baton cancelled, closing UIChooseResearch", "baton request: already sent", "baton request queued by partner", "baton=mine", "baton request answered: partner does not hold it")
  }
}

# matched case-sensitively: the engine logs e.g. "MaxStaleCacheSize" at start
$forbidden = 'verchain .*bad=[1-9]|DESYNC|Crash Detected|duplicateIDs=[1-9]|STALE loaded=|wait \w+ TIMEOUT|appError'
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
  if ($fail.Count -gt 0) {
    # the next scenario deletes Launch.log: keep both logs of a failed run
    $keep = "$root\suite-failures\$(Get-Date -Format 'yyyyMMdd-HHmmss')-$name"
    New-Item -ItemType Directory -Force $keep | Out-Null
    foreach ($t in "A", "B") { if (Test-Path $logs[$t]) { Copy-Item $logs[$t] "$keep\Launch-$t.log" } }
    Write-Host "     logs kept in $keep"
  }
  $results += [pscustomobject]@{ Name = $name; Status = $status; Fp = $fp.A }
}
$passed = @($results | Where-Object Status -eq "PASS").Count
Write-Host "=== $passed/$($results.Count) passed $(Get-Date -Format 'yyyy-MM-dd HH:mm') ==="
