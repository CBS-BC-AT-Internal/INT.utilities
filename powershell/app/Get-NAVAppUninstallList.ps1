[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [array]$AppInfos,
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$ToUninstallAppId,
    [Parameter(Mandatory = $false, Position = 2)]
    $version
)

function Add-AppInfoToUninstallList {
    param(
        [Parameter(Mandatory = $true)]
        $AppInfo
    )

    function Get-DependentAppInfo {
        param(
            [Parameter(Mandatory = $true)]
            [array]$AppInfos,
            [Parameter(Mandatory = $true)]
            $AppId
        )

        return $AppInfos | Where-Object {
            $_.Dependencies | Where-Object {
                $_.AppId.Guid -eq $AppId
            }
        }
    }

    Write-Verbose "- Checking app: $($AppInfo.Name) $($AppInfo.Version) ($($AppInfo.AppId.Value.Guid))"

    if ($script:addedAppInfoDict.ContainsKey($AppInfo.AppId.Value.Guid)) {
        Write-Verbose "  Already added, skipping..."
        return
    }
    $script:addedAppInfoDict[$AppInfo.AppId.Value.Guid] = $true

    # Find all apps that depend on this app
    $dependentApps = Get-DependentAppInfo -AppInfos $installedAppInfos -AppId $AppInfo.AppId.Value.Guid
    foreach ($dependentApp in $dependentApps) {
        Add-AppInfoToUninstallList -AppInfo $dependentApp
    }

    Write-Verbose "  Adding app to uninstall list: $($AppInfo.Name) $($AppInfo.Version) ($($AppInfo.AppId.Value.Guid))"
    $script:uninstallAppInfos = $script:uninstallAppInfos + @($AppInfo)
}

$ErrorActionPreference = "Stop"

$script:uninstallAppInfos = @()
$script:addedAppInfoDict = @{}

$installedAppInfos = $AppInfos | Where-Object { $_.IsInstalled }

# Find the app to uninstall
$ToUninstallAppInfo = $installedAppInfos | Where-Object {
    $_.AppId.Value.Guid -eq $ToUninstallAppId -and
    ($version -eq $null -or $_.Version -eq $version)
}
if ($ToUninstallAppInfo.Count -gt 1) {
    Write-Host "Multiple apps found for app ID ${ToUninstallAppId}. Please specify a version:"
    $index = 1
    $ToUninstallAppInfo | ForEach-Object { Write-Host "$index. $($_.Name) $($_.Version)"; $index++ }
    Write-Host "0. Cancel"
    while ($true) {
        $selection = Read-Host "Enter the number of the app to uninstall"
        if ($selection -eq "0") {
            Write-Host "Cancelling..."
            exit
        }
        if ($selection -ge 1 -and $selection -le $ToUninstallAppInfo.Count) {
            $ToUninstallAppInfo = $ToUninstallAppInfo[$selection - 1]
            break
        }
        Write-Host "Invalid selection: $selection"
    }
}
if (-not $ToUninstallAppInfo) {
    if ($version) {
        Write-Error "No installed app found with ID $ToUninstallAppId and version $version"
        exit 1
    }
    else {
        Write-Error "No installed app found with ID $ToUninstallAppId"
        exit 1
    }
}

Write-HostTimed "Building uninstall list for $($ToUninstallAppInfo.Name) $($ToUninstallAppInfo.Version) ($($ToUninstallAppInfo.AppId.Value.Guid))..."
Add-AppInfoToUninstallList -AppInfo $ToUninstallAppInfo

Write-Verbose "Uninstall list:`n$($script:uninstallAppInfos | Format-Table AppId, Name, Publisher, Version | Out-String)"

$script:uninstallAppInfos
