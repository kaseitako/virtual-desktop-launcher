$projectPath = Split-Path $PSScriptRoot -Parent
$scriptPath = Join-Path $projectPath 'Startup-VirtualDesktop.ps1'
$samplePath = Join-Path $projectPath 'virtual-desktop-setting.sample.json'

function Invoke-EntryScriptProcess {
    param(
        [AllowEmptyString()]
        [string]$SettingsPath = '',

        [Parameter(Mandatory)]
        [string]$LogDirectory,

        [string]$EntryScriptPath = $script:scriptPath
    )

    # A child process can default to an OEM code page on non-Japanese Windows.
    # Set both ends to UTF-8 so Japanese assertions survive output redirection.
    $quotedScript = "'" + $EntryScriptPath.Replace("'", "''") + "'"
    $quotedLogDirectory = "'" + $LogDirectory.Replace("'", "''") + "'"
    $command = '[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); ' +
        "& $quotedScript -LogDirectory $quotedLogDirectory -ValidateOnly"
    if (-not [string]::IsNullOrWhiteSpace($SettingsPath)) {
        $quotedSettings = "'" + $SettingsPath.Replace("'", "''") + "'"
        $command += " -SettingsPath $quotedSettings"
    }
    $command += '; exit $LASTEXITCODE'
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = Join-Path $PSHOME 'pwsh.exe'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
    $startInfo.StandardErrorEncoding = [Text.Encoding]::UTF8
    foreach ($argument in @('-NoLogo', '-NoProfile', '-OutputFormat', 'Text', '-EncodedCommand', $encodedCommand)) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        $null = $process.Start()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()

        [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = $outputTask.GetAwaiter().GetResult() + $errorTask.GetAwaiter().GetResult()
        }
    } finally {
        $process.Dispose()
    }
}

Describe 'Startup-VirtualDesktop.ps1' {
    It 'has no PowerShell parser errors' {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)

        $errors.Count | Should Be 0
    }

    It 'validates settings from a different current directory' {
        $logDirectory = Join-Path $TestDrive 'logs'
        $result = Invoke-EntryScriptProcess -SettingsPath $samplePath -LogDirectory $logDirectory

        $result.ExitCode | Should Be 0
        $result.Output | Should Match '設定の検証に成功しました'
        $logFiles = @(Get-ChildItem -LiteralPath $logDirectory -Filter '*.jsonl')
        $logFiles.Count | Should Be 1
        foreach ($line in Get-Content -LiteralPath $logFiles[0].FullName) {
            { $line | ConvertFrom-Json -ErrorAction Stop } | Should Not Throw
        }
        $messages = @(Get-Content -LiteralPath $logFiles[0].FullName | ForEach-Object { ($_ | ConvertFrom-Json).message })
        ($messages -contains '起動環境を検出しました。') | Should Be $true
        ($messages -contains '設定の検証に成功しました。') | Should Be $true
    }

    It 'uses the default settings path when SettingsPath is omitted' {
        $logDirectory = Join-Path $TestDrive 'default-settings-logs'
        # Keep the caller's personal settings out of the test run.
        $fixturePath = Join-Path $TestDrive "standalone launcher's folder"
        $null = New-Item -ItemType Directory -Path $fixturePath
        Copy-Item -LiteralPath $scriptPath -Destination $fixturePath
        Copy-Item -LiteralPath (Join-Path $projectPath 'virtual-desktop-setting.schema.json') -Destination $fixturePath
        Copy-Item -LiteralPath (Join-Path $projectPath 'modules') -Destination $fixturePath -Recurse
        Set-Content -LiteralPath (Join-Path $fixturePath 'virtual-desktop-setting.json') -Value '{"desktops":[]}' -Encoding utf8

        Push-Location $TestDrive
        try {
            $result = Invoke-EntryScriptProcess -LogDirectory $logDirectory -EntryScriptPath (Join-Path $fixturePath 'Startup-VirtualDesktop.ps1')
        } finally {
            Pop-Location
        }

        $result.ExitCode | Should Be 0
        $result.Output | Should Match '設定の検証に成功しました'
    }

    It 'fails validation for a missing settings file' {
        $missingPath = Join-Path $TestDrive 'missing.json'
        $logDirectory = Join-Path $TestDrive 'missing-logs'

        $result = Invoke-EntryScriptProcess -SettingsPath $missingPath -LogDirectory $logDirectory

        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match '設定ファイル.*存在しません'
    }

    It 'rejects malformed configuration before coercing values: <Name>' -TestCases @(
        @{ Name = 'missing desktops'; Json = '{}' },
        @{ Name = 'null root'; Json = 'null' },
        @{ Name = 'array root'; Json = '[]' },
        @{ Name = 'non-array desktops'; Json = '{"desktops":{"name":"Main"}}' },
        @{ Name = 'string boolean'; Json = '{"desktops":[{"name":"Main","apps":[{"path":"notepad","maximized":"false"}]}]}' },
        @{ Name = 'fractional timeout'; Json = '{"desktops":[{"name":"Main","apps":[{"path":"notepad","timeoutSeconds":1.5}]}]}' },
        @{ Name = 'unknown property'; Json = '{"desktops":[{"name":"Main","apps":[{"path":"notepad","onExisitng":"Skip"}]}]}' },
        @{ Name = 'empty match'; Json = '{"desktops":[{"name":"Main","apps":[{"path":"notepad","windowMatch":{}}]}]}' },
        @{ Name = 'string arguments'; Json = '{"desktops":[{"name":"Main","apps":[{"path":"notepad","arguments":"a b"}]}]}' }
    ) {
        param($Name, $Json)
        $settingsPath = Join-Path $TestDrive 'invalid.json'
        Set-Content -LiteralPath $settingsPath -Value $Json -Encoding utf8

        $result = Invoke-EntryScriptProcess -SettingsPath $settingsPath -LogDirectory (Join-Path $TestDrive 'invalid-logs')

        $result.ExitCode | Should Be 2
    }

    It 'returns exit code 2 when the log directory cannot be created' {
        $filePath = Join-Path $TestDrive 'not-a-directory'
        Set-Content -LiteralPath $filePath -Value 'file'

        $result = Invoke-EntryScriptProcess -SettingsPath $samplePath -LogDirectory (Join-Path $filePath 'logs')

        $result.ExitCode | Should Be 2
    }

    It 'validates even while a layout run holds the mutex' {
        $mutexUser = [regex]::Replace([Environment]::UserName, '[^A-Za-z0-9_.-]', '_')
        $mutex = [System.Threading.Mutex]::new($false, "Local\StartupVirtualDesktop-$mutexUser")
        $ownsMutex = $mutex.WaitOne(0)
        try {
            $ownsMutex | Should Be $true
            $settingsPath = Join-Path $TestDrive 'invalid-with-mutex.json'
            Set-Content -LiteralPath $settingsPath -Value '{}'

            $result = Invoke-EntryScriptProcess -SettingsPath $settingsPath -LogDirectory (Join-Path $TestDrive 'mutex-logs')

            $result.ExitCode | Should Be 2
        } finally {
            if ($ownsMutex) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
        }
    }

}
