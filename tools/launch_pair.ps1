# Launch two isolated test instances of XCOM 2 WotC on one PC.
# A = test-install, B = test-install-b (hard-link clone with its own Config).
# The game refuses a 2nd instance while the 1st holds mutex "UnrealEngine3_<n>";
# we close that handle in instance A (same-user DuplicateHandle, no admin) before starting B.
# Env: COOP_WORKSPACE = folder holding test-install and test-install-b;
#      SYSINTERNALS_HANDLE = path to Sysinternals handle64.exe (not shipped here).
param(
  [string]$ExtraArgs = "",
  [int]$Width = 960, [int]$Height = 540
)
$ErrorActionPreference = "Stop"
$root = $env:COOP_WORKSPACE
if (-not $root) { throw "set COOP_WORKSPACE to the folder holding test-install and test-install-b" }
$handle = if ($env:SYSINTERNALS_HANDLE) { $env:SYSINTERNALS_HANDLE } else { "$root\tools\sysinternals\handle\handle64.exe" }
$common = "-allowconsole -nohomedir -log -windowed ResX=$Width ResY=$Height -nostartupmovies $ExtraArgs"

function Start-Instance($dir, $tag) {
  $bin = "$root\$dir\XCom2-WarOfTheChosen\Binaries\Win64"
  $p = Start-Process "$bin\XCom2.exe" -ArgumentList "$common -coopTag=$tag" -WorkingDirectory $bin -PassThru
  Write-Output "$tag pid=$($p.Id)"
  return $p
}

$a = Start-Instance "test-install" "A"
$mutex = $null
for ($i = 0; $i -lt 60 -and -not $mutex; $i++) {
  Start-Sleep 1
  $mutex = & $handle -accepteula -nobanner -a -p $a.Id 2>$null | Select-String 'Mutant.*UnrealEngine3_[0-9]+' | Select-Object -First 1
}
if (-not $mutex) { throw "UnrealEngine3 mutex not found in A" }
$hid = ($mutex.Line.Trim() -split ':')[0].Trim()
python -I "$PSScriptRoot\close_remote_handle.py" $a.Id $hid
$b = Start-Instance "test-install-b" "B"
