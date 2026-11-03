Import-Module (Join-Path $PSScriptRoot '..\modules\Request-NamedDesktop.psm1') -Force

InModuleScope Request-NamedDesktop {
    # CI does not install VirtualDesktop. These stubs make every shell call mockable.
    function Get-DesktopList { [CmdletBinding()] param() }
    function Get-Desktop { [CmdletBinding()] param($Index) }
    function New-Desktop { [CmdletBinding()] param() }
    function Set-DesktopName { [CmdletBinding()] param($Desktop, $Name) }

    Describe 'Request-NamedDesktop' {
        It 'processes each piped name and returns one desktop for each' {
            Mock Get-DesktopList { [pscustomobject]@{ Name = 'Main'; Number = 0 } }
            Mock Get-Desktop { [pscustomobject]@{ Name = 'Main'; Number = 0 } }
            Mock New-Desktop { [pscustomobject]@{ Name = ''; Number = 1 } }
            Mock Set-DesktopName { param($Desktop, $Name) $Desktop.Name = $Name }

            $desktops = @('Main', 'Music' | Request-NamedDesktop)

            $desktops.Count | Should Be 2
            $desktops[0].Name | Should Be 'Main'
            $desktops[1].Name | Should Be 'Music'
            Assert-MockCalled New-Desktop -Times 1 -Exactly
        }

        It 'propagates a desktop naming failure to the layout caller' {
            Mock Get-DesktopList {}
            Mock New-Desktop { [pscustomobject]@{ Number = 1 } }
            Mock Set-DesktopName { Write-Error 'naming failed' }

            { Request-NamedDesktop -Name 'Music' } | Should Throw 'naming failed'
        }
    }
}
