# Derived from PSVirtualDesktop/Example.ps1. See ../THIRD_PARTY_NOTICES.md.
function Request-NamedDesktop {
    <#
    .SYNOPSIS
        Retrieves or creates a virtual desktop with the given name.
    .EXAMPLE
        'Main', 'Music' | Request-NamedDesktop
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    process {
        $desktop = Get-DesktopList -ErrorAction Stop | Where-Object Name -eq $Name | Select-Object -First 1
        if ($null -ne $desktop) {
            Get-Desktop -Index $desktop.Number -ErrorAction Stop
        } else {
            $desktop = New-Desktop -ErrorAction Stop
            $null = Set-DesktopName -Desktop $desktop -Name $Name -ErrorAction Stop
            $desktop
        }
    }
}

Export-ModuleMember -Function Request-NamedDesktop
