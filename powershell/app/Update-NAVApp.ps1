[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ServerInstance, # Business Central server instance name
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$AppFilePath,    # Path to the app file
    [Parameter(Mandatory = $false, Position = 2)]
    [string]$Tenant = "default",
    [ValidateSet("Add", "Clean", "Development", "ForceSync", "None")]
    [string]$SyncMode = "Add",
    $installedApps,
    [string]$getAppsScriptPath = (Join-Path $PSScriptRoot "Get-NAVAppUninstallList.ps1"),
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
        $appInfos += Get-NAVAppInfo -ServerInstance $ServerInstance -AppId $_.AppId.Value -Version $_.Version -Tenant $Tenant -TenantSpecificProperties
    }
    if (-not $appInfos) {
        Write-Error "No apps are installed on the server instance: $ServerInstance"
        exit 1
    }

    $installedAppInfos = $appInfos | Where-Object { $_.IsInstalled }

    return $installedAppInfos
}

function Get-AppFileFromPath {
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

function Get-AppIdFromAppFile {
    param(
        [Parameter(Mandatory = $true)]
        [object]$appInfo
    )

    return $appInfo.AppId.Value.Guid
}

$ErrorActionPreference = "Stop"
try {
    $modulePath = Resolve-Path "$PSScriptRoot\..\modules\HelperFunctions.psm1"
    Import-Module $modulePath -Force -ErrorAction Stop
}
catch {
    throw "Failed to import HelperFunctions module. Ensure the module exists in the specified path."
}
$AppFilePath = Convert-Path $AppFilePath

# Step 1: Get the list of installed apps on the server instance
Write-HostTimed "Retrieving installed apps from server instance: $ServerInstance..."
if (-not $installedApps) {
    $installedApps = Get-InstalledApps -ServerInstance $ServerInstance -Tenant $Tenant
    Write-Output $installedApps
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

# Step 2: Get the AppId of the app file
$appToInstall = Get-AppFileFromPath -AppFilePath $AppFilePath
$AppIdToUninstall = Get-AppIdFromAppFile -Appinfo $appToInstall

# TODO: Exit if the version is already installed
# TODO: Use BcContainerHelper to generate sorted list & add support for multiple apps to install

# Step 3: Use Get-NAVAppUninstallList.ps1 to get the uninstall list
Write-HostTimed "Generating uninstall list for AppId: $AppIdToUninstall..."
$getAppsScriptPath = Convert-Path $getAppsScriptPath
Write-Verbose "& $getAppsScriptPath -AppInfos [array] -ToUninstallAppId $AppIdToUninstall"
[array]$uninstallList = & $getAppsScriptPath -AppInfos $installedApps -ToUninstallAppId $AppIdToUninstall -Verbose

# Step 4: Output the uninstall list
Write-Host "Successfully generated uninstall list with $($uninstallList.Count) apps:"
$uninstallList | ForEach-Object {
    Write-Host (Get-PrettyAppInfo -AppInfo $_ -bullet)
}

if (-not $DryRun) {
    if ($uninstallList.Count -gt 0) {
        Write-Verbose "$uninstallScriptPath -ServerInstance $ServerInstance -appsToUninstall [Array]"
        & $uninstallScriptPath -ServerInstance $ServerInstance -appsToUninstall $uninstallList
    }

    Write-Host "Installing app $($appToInstall.Name) version $($appToInstall.Version)..."
    Write-Verbose "Publish-NAVApp -ServerInstance $ServerInstance -Path $AppFilePath -SkipVerification"
    if(-not $DryRun) {
        Publish-NAVApp -ServerInstance $ServerInstance -Path $AppFilePath -SkipVerification
    }
    if($ForceSync) {
        $SyncMode = "ForceSync"
    }
    Write-Verbose "Sync-NAVApp -ServerInstance $ServerInstance -AppId $AppIdToUninstall -Version $($appToInstall.Version)"
    if(-not $DryRun) {
        Sync-NAVApp -ServerInstance $ServerInstance -AppId $AppIdToUninstall -Version $appToInstall.Version -Mode $SyncMode
    }
    Write-Verbose "Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -AppId $AppIdToUninstall -Version $($appToInstall.Version)"
    if(-not $DryRun) {
        Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -AppId $AppIdToUninstall -Version $appToInstall.Version
    }
}

if ($uninstallList.Count -gt 1) {
    # Step 5: Prepare the install list
    $installList = $uninstallList
    [array]::Reverse($installList)
    $installList = $installList[1..($installList.Count - 1)]
    Write-Host "Successfully generated install list with $($installList.Count) apps:"
    $installList | ForEach-Object {
        Write-Host (Get-PrettyAppInfo -AppInfo $_ -bullet)
    }

    # Step 6: Install the apps in the list
    foreach ($appInfo in $installList) {
        Write-HostTimed "Installing app $($appInfo.Name) version $($appInfo.Version)..."
        if (-not $DryRun) {
            Install-NAVApp -ServerInstance $ServerInstance -AppId $appInfo.AppId.Value.Guid -Version $appInfo.Version
        }
    }
}

Write-Host "Successfully installed $($appToInstall.Name) version $($appToInstall.Version) and its dependencies." -ForegroundColor Green
