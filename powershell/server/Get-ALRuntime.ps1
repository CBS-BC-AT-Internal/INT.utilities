[CmdletBinding()]
param (
    [Parameter(ValueFromPipeline=$true)]
    [string]$ServerInstance,
    $Version
)

function Get-NAVVersion {
    param (
        [string]$ServerInstance
    )

    $navServerInstance = Get-NAVServerInstance -ServerInstance $ServerInstance

    if (-not $navServerInstance) {
        throw "Server instance $ServerInstance not found"
    }

    return $navServerInstance.Version
}

function Get-ALRuntimeFromVersion {
    param (
        [string]$Version
    )

    $VersionString = $Version.ToString()
    $Major = [int]$VersionString.Split('.')[0]
    $RuntimeInt = ($Major - 11) # BC 12 = Runtime 1.0 etc.
    return "${RuntimeInt}.0"
}

if (-not $Version) {
    if (-not $ServerInstance) {
        throw "Either ServerInstance or Version must be specified"
    }

    $Version = Get-NAVVersion -ServerInstance $ServerInstance
}

Write-Output (Get-ALRuntimeFromVersion -Version $Version)
