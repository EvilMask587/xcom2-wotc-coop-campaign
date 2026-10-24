Param(
    [string] $srcDirectory, # the path that contains the mod's .XCOM_sln
    [string] $sdkPath,      # ...\XCOM 2 War of the Chosen SDK
    [string] $gamePath,     # ...\XCom2-WarOfTheChosen (use a TEST install)
    [string] $config        # build configuration
)

$ScriptDirectory = Split-Path $MyInvocation.MyCommand.Path
$common = Join-Path -Path $ScriptDirectory "X2ModBuildCommon\build_common.ps1"
Write-Host "Sourcing $common"
. ($common)

$builder = [BuildProject]::new("WOTCCoopCampaign", $srcDirectory, $sdkPath, $gamePath)

switch ($config)
{
    "debug" { $builder.EnableDebug() }
    "default" { }
    "" { ThrowFailure "Missing build configuration" }
    default { ThrowFailure "Unknown build configuration $config" }
}

$builder.InvokeBuild()
