#Requires -Version 7.5
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) {
    throw 'テストは Windows の PowerShell で実行してください。'
}

$localManifest = Join-Path $PSScriptRoot '..\.tools\Pester\4.10.1\Pester.psd1'
if (Test-Path -LiteralPath $localManifest) {
    Import-Module $localManifest -Force
} else {
    Import-Module Pester -RequiredVersion 4.10.1 -Force
}

$result = Invoke-Pester -Script $PSScriptRoot -PassThru -Show All
if ($result.TotalCount -eq 0 -or $result.FailedCount -gt 0) {
    exit 1
}
exit 0
