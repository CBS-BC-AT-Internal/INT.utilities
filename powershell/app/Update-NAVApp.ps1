[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ServerInstance, # Business Central server instance name
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$AppFilePath,    # Path to the app file
    [Parameter(Mandatory = $false, Position = 2)]
    [string]$Tenant = "default",
    [switch]$UninstallDependents,
    [ValidateSet("Add", "Clean", "Development", "ForceSync", "None")]
    [string]$SyncMode = "Add",
    $installedApps,
    [string]$sortScriptPath = (Join-Path $PSScriptRoot "Get-NAVAppUninstallList.ps1"),
    [string]$uninstallScriptPath = (Join-Path $PSScriptRoot "Uninstall-NAVAppList.ps1"),
    [switch]$DryRun
)

function Get-InstalledApps {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerInstance,
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    # Retrieve the list of installed apps from the Business Central server instance
    $appInfosSimple = Get-NAVAppInfo -ServerInstance $ServerInstance

    $appInfos = @()
    $appInfosSimple | ForEach-Object {
        Write-Verbose "Retrieving data for app: $($_.Name) $($_.Version) ($($_.AppId.Value.Guid))..."
        $appInfos += Get-NAVAppInfo -ServerInstance $ServerInstance -AppId $_.AppId.Value -Version $_.Version -Tenant $Tenant -TenantSpecificProperties
    }
    if (-not $appInfos) {
        Write-Error "No apps are installed on the server instance: $ServerInstance"
        exit 1
    }

    $installedAppInfos = $appInfos | Where-Object { $_.IsInstalled }

    return $installedAppInfos
}

function Get-AppInfoFromPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppFilePath
    )

    $AppFilePath = Convert-Path $AppFilePath
    if (-not (Test-Path $AppFilePath)) {
        Write-Error "The app file does not exist: $AppFilePath"
        exit 1
    }
    Write-HostTimed "Reading app file: $AppFilePath..."
    try {
        $appInfo = Get-NAVAppInfo -Path $AppFilePath
    }
    catch {
        Write-Error "Failed to read app file: $AppFilePath"
        exit 1
    }
    if (-not $appInfo) {
        Write-Error "Failed to retrieve app information from the file: $AppFilePath"
        exit 1
    }

    return $appInfo
}

function Get-AppIdFromAppInfo {
    param(
        [Parameter(Mandatory = $true)]
        [object]$appInfo
    )

    return $appInfo.AppId.Value.Guid
}

function Compare-NAVApps {
    param(
        [Parameter(Mandatory = $true)]
        $newApp,
        [Parameter(Mandatory = $true)]
        $currentApp
    )

    $result = @{
        success = $true
        failCase = ''
    }

    if ($newApp.AppId.Value.Guid -ne $currentApp.AppId.Value.Guid) {
        $result.success = $false
        $result.failCase = 'The AppId of the provided apps does not match.'
        return $result
    }

    if ($newApp.Version -gt $currentApp.ExtensionDataVersion) {
        return $result
    } elseif ($newApp.Version -eq $currentApp.ExtensionDataVersion) {
        $result.success = $false
        $result.failCase = "$($newApp.Name) $($newApp.Version) is already installed."
        return $result
    } else {
        $result.success = $false
        $result.failCase = "A newer version of $($newApp.Name) is already installed.`nApp file: $($newApp.Version) Installed: $($currentApp.Version)"
        return $result
    }
}

$ErrorActionPreference = "Stop"
try {
    $modulePath = Resolve-Path "$PSScriptRoot\..\modules\HelperFunctions.psm1"
    Import-Module $modulePath -Force -ErrorAction Stop
}
catch {
    throw "Failed to import HelperFunctions module. Ensure the module exists in the specified path."
}

# Step 1: Check if the app file is an upgrade
$AppFilePath = Convert-Path $AppFilePath
$appToInstall = Get-AppInfoFromPath -AppFilePath $AppFilePath
$AppIdToInstall = Get-AppIdFromAppInfo -Appinfo $appToInstall

Write-HostTimed "Looking for existing installations of app with AppId: ${AppIdToInstall}..."

$navInfoParams = @{
    ServerInstance = $ServerInstance
    AppId          = $AppIdToInstall
    Tenant         = $Tenant
    TenantSpecificProperties = $true
}

$currentApps = Get-NAVAppInfo @navInfoParams

if ($currentApps) {
    Write-Verbose "Found existing installation(s)."
    $compareResult = Compare-NAVApps -newApp $appToInstall -currentApp $currentApps[0]
    if (-not $compareResult.success) {
        Write-Host "Won't update app: $($compareResult.failCase)" -ForegroundColor Yellow
        exit 0
    }
    $isUpgrade = $true
} else {
    Write-Verbose "No existing installation found."
    $isUpgrade = $false
}

if ($UninstallDependents) {
    # Step 2: Get the list of installed apps on the server instance
    Write-HostTimed "Retrieving installed apps from server instance: $ServerInstance..."
    if (-not $installedApps) {
        $installedApps = Get-InstalledApps -ServerInstance $ServerInstance -Tenant $Tenant
    }
    else {
        Write-Host "Using provided installed apps list."
    }

    if ($installedAppInfos.Count -gt 0) {
        Write-Verbose "Installed apps on server instance ${ServerInstance}:"
        $installedAppInfos | ForEach-Object { Write-Verbose (Get-PrettyAppInfo -AppInfo $_ -bullet) }
    }
    else {
        Write-Verbose "No installed apps found on server instance ${ServerInstance}."
    }

    # TODO: Use BcContainerHelper to generate sorted list & add support for multiple apps to install

    # Step 3: Use Get-NAVAppUninstallList.ps1 to get the uninstall list
    Write-HostTimed "Generating uninstall list for AppId: $AppIdToInstall..."
    $sortScriptPath = Convert-Path $sortScriptPath
    Write-Verbose "& $sortScriptPath -AppInfos [array] -ToUninstallAppId $AppIdToInstall"
    [array]$uninstallList = & $sortScriptPath -AppInfos $installedApps -ToUninstallAppId $AppIdToInstall -Verbose

    # Step 4: Output the uninstall list
    Write-Host "Successfully generated uninstall list with $($uninstallList.Count) apps:"
    $uninstallList | ForEach-Object {
        Write-Host (Get-PrettyAppInfo -AppInfo $_ -bullet)
    }

    if ($uninstallList.Count -gt 0) {
        if ($DryRun) {
            Write-Host "$uninstallScriptPath -ServerInstance $ServerInstance -appsToUninstall [Array]" -ForegroundColor DarkGray
        } else {
            Write-Verbose "$uninstallScriptPath -ServerInstance $ServerInstance -appsToUninstall [Array]"
            & $uninstallScriptPath -ServerInstance $ServerInstance -appsToUninstall $uninstallList
        }
    }
}

# Step 5: Install the new app version
Write-HostTimed "Installing app $($appToInstall.Name) version $($appToInstall.Version)..."
if($DryRun) {
    Write-Host "Publish-NAVApp -ServerInstance $ServerInstance -Path $AppFilePath -SkipVerification" -ForegroundColor DarkGray
} else {
    Write-Verbose "Publish-NAVApp -ServerInstance $ServerInstance -Path $AppFilePath -SkipVerification"
    Publish-NAVApp -ServerInstance $ServerInstance -Path $AppFilePath -SkipVerification
}
if($DryRun) {
    Write-Host "Sync-NAVApp -ServerInstance $ServerInstance -AppId $AppIdToInstall -Version $($appToInstall.Version) -Mode $SyncMode" -ForegroundColor DarkGray
} else {
    Write-Verbose "Sync-NAVApp -ServerInstance $ServerInstance -AppId $AppIdToInstall -Version $($appToInstall.Version)"
    Sync-NAVApp -ServerInstance $ServerInstance -AppId $AppIdToInstall -Version $appToInstall.Version -Mode $SyncMode
}
if ($isUpgrade) {
    if($DryRun) {
        Write-Host "Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -AppId $AppIdToInstall -Version $($appToInstall.Version)" -ForegroundColor DarkGray
    } else {
        Write-Verbose "Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -AppId $AppIdToInstall -Version $($appToInstall.Version)"
        Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -AppId $AppIdToInstall -Version $appToInstall.Version
    }
} else {
    if($DryRun) {
        Write-Host "Install-NAVApp -ServerInstance $ServerInstance -AppId $AppIdToInstall -Version $($appToInstall.Version)" -ForegroundColor DarkGray
    } else {
        Write-Verbose "Install-NAVApp -ServerInstance $ServerInstance -AppId $AppIdToInstall -Version $($appToInstall.Version)"
        Install-NAVApp -ServerInstance $ServerInstance -AppId $AppIdToInstall -Version $appToInstall.Version
    }
}

if ($uninstallList -and $uninstallList.Count -gt 1) {
    # Step 5: Prepare the install list
    $installList = $uninstallList
    [array]::Reverse($installList)
    $installList = $installList[1..($installList.Count - 1)]
    Write-Host "Successfully generated install list with $($installList.Count) apps:" -ForegroundColor DarkGray
    $installList | ForEach-Object {
        Write-Host (Get-PrettyAppInfo -AppInfo $_ -bullet)
    }

    # Step 6: Install the apps in the list
    foreach ($appInfo in $installList) {
        Write-HostTimed "Installing app $($appInfo.Name) version $($appInfo.Version)..."
        if ($DryRun) {
            Write-Host "Install-NAVApp -ServerInstance $ServerInstance -AppId $($appInfo.AppId.Value.Guid) -Version $($appInfo.Version)" -ForegroundColor DarkGray
        } else {
            Install-NAVApp -ServerInstance $ServerInstance -AppId $appInfo.AppId.Value.Guid -Version $appInfo.Version

            # Add the app info to the installedApps array
            if ($installedApps) {
                $tenantAppInfo = Get-NAVAppInfo -ServerInstance $ServerInstance -AppId $appInfo.AppId.Value -Version $appInfo.Version -Tenant $Tenant -TenantSpecificProperties
                $installedApps += $tenantAppInfo
            }
        }
    }
}

# Step 7: Unpublish the old version of the app
foreach ($currentApp in $currentApps) {
    Write-HostTimed "Unpublishing old version of the app $($currentApp.Name) version $($currentApp.Version)..."
    if ($DryRun) {
        Write-Host "Unpublish-NAVApp -ServerInstance $ServerInstance -AppId $AppIdToInstall -Version $($currentApp.Version)" -ForegroundColor DarkGray
    } else {
        Write-Verbose "Unpublish-NAVApp -ServerInstance $ServerInstance -AppId $AppIdToInstall -Version $($currentApp.Version)"
        Unpublish-NAVApp -ServerInstance $ServerInstance -AppId $AppIdToInstall -Version $($currentApp.Version)
    }
    # Remove the old app info from the installedApps array
    if ($installedApps) {
        $installedApps = $installedApps | Where-Object {
            -not ($_.AppId.Value.Guid -eq $AppIdToInstall -and $_.Version -eq $currentApp.Version)
        }
    }
}

Write-Output $installedApps

Write-HostTimed "Successfully installed $($appToInstall.Name) version $($appToInstall.Version) and its dependencies." -ForegroundColor Green
