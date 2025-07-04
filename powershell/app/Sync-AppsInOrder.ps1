param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ServerInstance,
    [string]$Tenant = "default",
    [string]$migrationAppId,
    [string]$AppFolder,
    $CustomApps = "config/default.blankapps.json",
    $groupedApps,
    [Parameter(Mandatory = $true)]
    $sortingOrder,
    [ValidateSet("Add", "Clean", "Development", "ForceSync", "None")]
    [string]$Mode = "Add",
    [ValidateSet("Add", "Clean", "Development", "ForceSync", "None")]
    [string]$MigrationAppMode = $Mode,
    [switch]$CommitPerTable,
    [switch]$AllowMissingApps,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Get-AppsToSync {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerInstance,
        [string]$Tenant,
        [Parameter(Mandatory = $true)]
        $sortedApps
    )

    Write-HostTimed "Looking for apps to synchronize on $ServerInstance..."

    $serverAppInfos = Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties

    $appsToSync = @()

    foreach ($AppInfo in $sortedApps) {
        $appName = $AppInfo.Name
        $appId = $AppInfo.AppId.ToString()
        $appVersion = $AppInfo.Version

        $matchingServerApps = $serverAppInfos | Where-Object { $_.AppId.ToString() -eq $appId }

        if ($matchingServerApps.Count -eq 0) {
            $message = "App `"$appName`" with the AppID $appId not found on server `"$ServerInstance`"."
            if ($AllowMissingApps) {
                Write-Warning $message
                continue
            }
            else {
                throw $message
            }
        }

        $matchingServerApps = $matchingServerApps | Where-Object { $_.Version -eq $appVersion }

        if ($matchingServerApps.Count -eq 0) {
            $message = "The app `"$appName`" with the AppID $appId does not match the version $appVersion on server `"$ServerInstance`"."
            if ($AllowMissingApps) {
                Write-Warning $message
                continue
            }
            else {
                throw $message
            }
        }

        $matchingServerApps = $matchingServerApps | Where-Object { $_.SyncState -ne "Synced" }

        if ($matchingServerApps.Count -eq 0) {
            Write-Verbose "`"$appName`" is already synchronized on server `"$ServerInstance`", tenant `"$Tenant`"."
            continue
        }

        $appsToSync += $AppInfo
    }

    return $appsToSync
}

function Sync-Apps {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerInstance,
        [Parameter(Mandatory = $true)]
        [array]$AppsToSync,
        [string]$Mode = 'Add',
        [Object]$ModeSchema,
        [bool]$CommitPerTable
    )

    foreach ($AppInfo in $AppsToSync) {
        $appName = $AppInfo.Name
        $appId = $AppInfo.AppId.ToString()
        $appVersion = $AppInfo.Version

        if ($ModeSchema -and $ModeSchema.ContainsKey($appId)) {
            $CurrMode = $ModeSchema[$appId]
        }
        else {
            $CurrMode = $Mode
        }

        $params = @{
            ServerInstance = $ServerInstance
            AppId          = $appId
            Version        = $appVersion
            Mode           = $CurrMode
            CommitPerTable = $CommitPerTable
            Force          = $Force
        }
        $paramString = Get-ParameterString $params

        Write-HostTimed "Synchronizing $appName $appVersion..."
        Write-Verbose "Sync-NAVApp $paramString"
        $appStart = Get-Date
        if (-not $DryRun) {
            Sync-NAVApp @params # FIXME: Doesn't exit on error (e.g. missing field without ForceSync)
        }
        Write-ElapsedTime -startTime $appStart -command "  $appName" -Silent
    }
}

if ($DryRun) {
    Write-Warning "Running in dry-run mode. No changes will be made."
}

if (-not $groupedApps) {
    if (-not $AppFolder) {
        throw "AppFolder is required when groupedApps is not provided."
    }
    $groupAppsParams = @{
        AppFolder              = $AppFolder
        MigrationAppId         = $MigrationAppId
        CustomApps             = $CustomApps
        SkipDependencySort     = $SkipDependencySort
        AllowMissingSortScript = $AllowMissingSortScript
        AllowMissingCustomApps = $AllowMissingCustomApps
        Force                  = $Force
    }
    $groupedApps = Invoke-GetNAVAppGroups @groupAppsParams
}

$sortedAppInfos = Get-SortedAppInfos -AppGroups $groupedApps -sortingOrder $sortingOrder -WarningAction Stop
Write-Verbose "Sorted app list:`n$(Get-PrettyAppInfo $sortedAppInfos -bullet | Format-List | Out-String)"
$AppsToSync = Get-AppsToSync -ServerInstance $ServerInstance -Tenant $Tenant -sortedApps $sortedAppInfos

if ($AppsToSync.Count -eq 0) {
    Write-Warning "Found no apps on server instance '$ServerInstance' to sync."
    return
}
# FIXME: AppsToSync.Count returns null
Write-HostTimed "Found $($AppsToSync.Count) apps to synchronize." -ForegroundColor Cyan
Write-Debug "Apps to sync:`n$(Get-PrettyAppInfo $AppsToSync -bullet | Format-List)"

$baseAppIds = $groupedApps.BaseApps | ForEach-Object { $_.AppId.ToString() }
$modeSchema = @{}
foreach($appInfo in $AppsToSync) {
    if ($groupedApps.MigrationApp -and $appInfo.AppId.ToString() -eq $groupedApps.MigrationApp.AppId.ToString()) {
        $modeSchema[$appInfo.AppId.ToString()] = $MigrationAppMode
    }
    elseif ($baseAppIds -contains $appInfo.AppId.ToString()) {
        $modeSchema[$appInfo.AppId.ToString()] = "Add"
    }
    else {
        $modeSchema[$appInfo.AppId.ToString()] = $Mode
    }
}
Write-Verbose "Mode schema:`n$($modeSchema | Format-Table -AutoSize | Out-String)"

if (-not $Force) {
    Read-BackupConfirmFromServer $ServerInstance
}

$syncStart = Get-Date
Sync-Apps -ServerInstance $ServerInstance -AppsToSync $AppsToSync -ModeSchema $modeSchema
Write-ElapsedTime -startTime $syncStart -command "Sync-NAVApp"
Write-HostTimed "Successfully synchronized $($AppsToSync.Count) apps." -ForegroundColor Green
