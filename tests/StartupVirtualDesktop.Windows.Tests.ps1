$modulePath = Join-Path $PSScriptRoot '..\modules\StartupVirtualDesktop.Windows.psm1'
Import-Module $modulePath -Force

function New-WindowsTestApp {
    param(
        [string]$Path,
        [string[]]$Arguments = @()
    )

    [pscustomobject]@{
        path = $Path
        arguments = $Arguments
        workingDirectory = ''
        timeoutSeconds = 30
        onExisting = 'Move'
        maximized = $false
        windowMatch = $null
    }
}

Describe 'New-WindowsDesktopAdapter' {
    It 'provides every operation required by the core' {
        $adapter = New-WindowsDesktopAdapter
        $requiredOperations = @(
            'GetOrCreateDesktop',
            'SetWallpaper',
            'ResolveApplication',
            'GetWindows',
            'StartApplication',
            'MoveWindow',
            'TestWindow',
            'MaximizeWindow',
            'GetUtcNow',
            'Wait'
        )

        foreach ($operation in $requiredOperations) {
            ($adapter.PSObject.Properties.Name -contains $operation) | Should Be $true
            $adapter.$operation.GetType().FullName | Should Be 'System.Management.Automation.ScriptBlock'
        }
    }

    It 'resolves an application command to an inferred process name' {
        $adapter = New-WindowsDesktopAdapter
        $resolveApplication = $adapter.ResolveApplication

        $resolved = & $resolveApplication (New-WindowsTestApp -Path 'cmd')

        $resolved.inferredProcessName | Should Be 'cmd'
        (Test-Path -LiteralPath $resolved.launchPath -PathType Leaf) | Should Be $true
    }

    It 'resolves a shortcut target and preferred title' {
        $shortcutPath = Join-Path $TestDrive 'My App.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "$env:WINDIR\System32\notepad.exe"
        $shortcut.Save()
        $adapter = New-WindowsDesktopAdapter
        $resolveApplication = $adapter.ResolveApplication

        $resolved = & $resolveApplication (New-WindowsTestApp -Path $shortcutPath)

        $resolved.inferredProcessName | Should Be 'notepad'
        $resolved.preferredTitle | Should Be 'My App'
        $resolved.launchPath | Should Be $shortcutPath
        $resolved.trackStartedProcess | Should Be $true
    }

    It 'does not track a shell shortcut without a target path' {
        $shortcutPath = Join-Path $TestDrive 'Spotify.lnk'
        $null = New-Item -ItemType File -Path $shortcutPath
        Mock Get-DesktopShortcutMetadata -ModuleName StartupVirtualDesktop.Windows {
            [pscustomobject]@{
                targetPath = ''
                preferredTitle = 'Spotify'
                trackStartedProcess = $false
            }
        } -ParameterFilter { $Path -eq $shortcutPath }
        $adapter = New-WindowsDesktopAdapter
        $resolveApplication = $adapter.ResolveApplication

        $resolved = & $resolveApplication (New-WindowsTestApp -Path $shortcutPath)

        $resolved.inferredProcessName | Should Be 'Spotify'
        $resolved.preferredTitle | Should Be 'Spotify'
        $resolved.trackStartedProcess | Should Be $false
    }

    It 'enumerates visible top-level windows without mutating them' {
        $adapter = New-WindowsDesktopAdapter
        $getWindows = $adapter.GetWindows

        $windows = @(& $getWindows)

        $windows.Count | Should BeGreaterThan -1
        if ($windows.Count -gt 0) {
            ($windows[0].PSObject.Properties.Name -contains 'Handle') | Should Be $true
            ($windows[0].PSObject.Properties.Name -contains 'ProcessName') | Should Be $true
            ($windows[0].PSObject.Properties.Name -contains 'Title') | Should Be $true
            ($windows[0].PSObject.Properties.Name -contains 'ClassName') | Should Be $true
        }
    }
}

Describe 'Start-DesktopApplication process tracking' {
    It 'defaults to PassThru and returns the process id when the tracking flag is omitted' {
        Mock Start-Process -ModuleName StartupVirtualDesktop.Windows {
            [pscustomobject]@{ Id = 4321 }
        }
        $adapter = New-WindowsDesktopAdapter
        $startApplication = $adapter.StartApplication
        $app = [pscustomobject]@{
            launchPath = 'notepad.exe'
            arguments = @()
            workingDirectory = ''
        }

        $result = & $startApplication $app

        $result.ProcessId | Should Be 4321
        Assert-MockCalled Start-Process -ModuleName StartupVirtualDesktop.Windows -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'notepad.exe' -and $PassThru -eq $true
        }
    }

    It 'omits PassThru and returns zero for an untracked shell launch' {
        Mock Start-Process -ModuleName StartupVirtualDesktop.Windows
        $adapter = New-WindowsDesktopAdapter
        $startApplication = $adapter.StartApplication
        $app = [pscustomobject]@{
            launchPath = 'C:\StoreApp.lnk'
            arguments = @()
            workingDirectory = ''
            trackStartedProcess = $false
        }

        $result = & $startApplication $app

        $result.ProcessId | Should Be 0
        Assert-MockCalled Start-Process -ModuleName StartupVirtualDesktop.Windows -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'C:\StoreApp.lnk' -and -not $PassThru
        }
    }
}

Describe 'Get-StartupEnvironmentDiagnostics' {
    It 'reports the runtime and module versions' {
        $diagnostics = Get-StartupEnvironmentDiagnostics

        [string]::IsNullOrWhiteSpace($diagnostics.OSVersion) | Should Be $false
        [string]::IsNullOrWhiteSpace($diagnostics.OSBuild) | Should Be $false
        [string]::IsNullOrWhiteSpace($diagnostics.PowerShellVersion) | Should Be $false
        ($diagnostics.PSObject.Properties.Name -contains 'VirtualDesktopModuleVersion') | Should Be $true
    }
}

Describe 'application paths and arguments' {
    It 'resolves relative application and working paths independently of the current directory' {
        $projectPath = Split-Path $PSScriptRoot -Parent
        $app = New-WindowsTestApp -Path '.\Startup-VirtualDesktop.ps1'
        $app.workingDirectory = '.\tests'
        $adapter = New-WindowsDesktopAdapter
        Push-Location $TestDrive
        try {
            $resolved = & $adapter.ResolveApplication $app
        } finally {
            Pop-Location
        }

        $resolved.launchPath | Should Be (Join-Path $projectPath 'Startup-VirtualDesktop.ps1')
        $resolved.workingDirectory | Should Be (Join-Path $projectPath 'tests')
    }

    It 'expands environment variables in the working directory' {
        $app = New-WindowsTestApp -Path 'cmd'
        $app.workingDirectory = '%TEMP%'
        $adapter = New-WindowsDesktopAdapter

        $resolved = & $adapter.ResolveApplication $app

        $resolved.workingDirectory | Should Be $env:TEMP
    }

    It 'preserves spaces empty strings quotes and trailing backslashes in child process arguments' {
        $childPath = Join-Path $TestDrive 'argument receiver.ps1'
        $outputPath = Join-Path $TestDrive 'received arguments.json'
        Set-Content -LiteralPath $childPath -Value 'param([string]$OutputPath); ConvertTo-Json -InputObject @($args) -Compress | Set-Content -LiteralPath $OutputPath -Encoding utf8'
        $expected = @('plain', 'two words', '', 'say "hello"', 'C:\space dir\', 'backslash\"quote', '日本語')
        # Run only a hidden argument receiver; never open a configured user application.
        Mock Start-Process -ModuleName StartupVirtualDesktop.Windows {
            param($FilePath, $ArgumentList)
            $startInfo = [Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $FilePath
            $startInfo.Arguments = $ArgumentList -join ' '
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $process = [Diagnostics.Process]::Start($startInfo)
            try {
                if (-not $process.WaitForExit(10000)) {
                    $process.Kill($true)
                    throw 'Argument receiver timed out.'
                }
                if ($process.ExitCode -ne 0) { throw 'Argument receiver failed.' }
                [pscustomobject]@{ Id = $process.Id }
            } finally {
                $process.Dispose()
            }
        }
        $app = [pscustomobject]@{
            launchPath = Join-Path $PSHOME 'pwsh.exe'
            arguments = @('-NoProfile', '-NonInteractive', '-File', $childPath, $outputPath) + $expected
            workingDirectory = ''
        }
        $adapter = New-WindowsDesktopAdapter

        $null = & $adapter.StartApplication $app

        $actual = @(Get-Content -LiteralPath $outputPath -Raw -Encoding utf8 | ConvertFrom-Json)
        $actual.Count | Should Be $expected.Count
        for ($i = 0; $i -lt $expected.Count; $i++) {
            $actual[$i] | Should BeExactly $expected[$i]
        }
    }

    It 'excludes the desktop and taskbars from application window candidates' {
        $adapter = New-WindowsDesktopAdapter

        $windows = @(& $adapter.GetWindows)

        @($windows | Where-Object ClassName -in @('Progman', 'WorkerW', 'Shell_TrayWnd', 'Shell_SecondaryTrayWnd')).Count | Should Be 0
    }
}
