param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ServerInstance,
    [string]$Tenant = "default",
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Get-AppsToUnpublish {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerInstance,
        [string]$Tenant
    )

    Write-HostTimed "Looking for outdated apps to unpublish on $ServerInstance..."
    $serverAppInfos = Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties
    return $serverAppInfos | Where-Object {
        -not $_.IsInstalled -and
        $_.IsPublished -and
        $_.SyncState -eq "Synced" -and
        $_.ExtensionDataVersion -gt $_.Version
    }
}

function Unpublish-Apps {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerInstance,
        [Parameter(Mandatory = $true)]
        $AppsToUnpublish
    )

    foreach ($AppInfo in $AppsToUnpublish) {
        $appName = $AppInfo.Name
        $appId = $AppInfo.AppId.ToString()
        $appVersion = $AppInfo.Version

        $params = @{
            ServerInstance = $ServerInstance
            AppId          = $appId
            Version        = $appVersion
        }
        $paramString = Get-ParameterString $params

        Write-HostTimed "Unpublishing $appName $appVersion..."
        Write-Verbose "Unpublish-NAVApp $paramString"
        $appStart = Get-Date
        if (-not $DryRun) {
            Unpublish-NAVApp @params
        }
        Write-ElapsedTime -startTime $appStart -command "  $appName" -Silent
    }
}

if ($DryRun) {
    Write-Warning "Running in dry-run mode. No changes will be made."
}

$AppsToUnpublish = Get-AppsToUnpublish -ServerInstance $ServerInstance -Tenant $Tenant

if ($AppsToUnpublish.Count -eq 0) {
    Write-Warning "Found no apps on server instance '$ServerInstance' to Unpublish."
    return
}
Write-HostTimed "Found $($AppsToUnpublish.Count) apps to unpublish." -ForegroundColor Cyan
Write-Debug "Apps to unpublish:`n$(Get-PrettyAppInfo $AppsToUnpublish -bullet | Format-List)"

$unpublishStart = Get-Date
Unpublish-Apps -ServerInstance $ServerInstance -AppsToUnpublish $AppsToUnpublish
Write-ElapsedTime -startTime $unpublishStart -command "Unpublish-NAVApp"
Write-HostTimed "Successfully unpublished $($AppsToUnpublish.Count) apps." -ForegroundColor Green
