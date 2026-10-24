# Build the mod into the TEST install (never into the game you play).
# Env: XCOM2_SDK = "...\XCOM 2 War of the Chosen SDK"; COOP_WORKSPACE (see launch_pair.ps1).
param([string]$Config = "default")
$ErrorActionPreference = "Stop"
if (-not $env:XCOM2_SDK -or -not $env:COOP_WORKSPACE) { throw "set XCOM2_SDK and COOP_WORKSPACE" }
$repo = Split-Path $PSScriptRoot -Parent
& "$repo\.scripts\build.ps1" -srcDirectory $repo -sdkPath $env:XCOM2_SDK `
  -gamePath "$env:COOP_WORKSPACE\test-install\XCom2-WarOfTheChosen" -config $Config
