$projectPath = Split-Path $PSScriptRoot -Parent
$coreModulePath = Join-Path $projectPath 'modules\StartupVirtualDesktop.Core.psm1'
$samplePath = Join-Path $projectPath 'virtual-desktop-setting.sample.json'
$schemaPath = Join-Path $projectPath 'virtual-desktop-setting.schema.json'
Import-Module $coreModulePath -Force

Describe 'configuration artifacts' {
    It 'normalizes and validates the sample without deprecation warnings' {
        $raw = Get-Content -LiteralPath $samplePath -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100

        $settings = ConvertTo-DesktopLayoutSettings -InputObject $raw

        $null = Test-DesktopLayoutSettings -Settings $settings
        $settings.warnings.Count | Should Be 0
        $settings.desktops.Count | Should BeGreaterThan 1
    }

    It 'validates the public sample against the schema used by the entry script' {
        $sampleJson = Get-Content -LiteralPath $samplePath -Raw -Encoding utf8

        Test-Json -Json $sampleJson -SchemaFile $schemaPath -ErrorAction Stop | Should Be $true
    }
}
