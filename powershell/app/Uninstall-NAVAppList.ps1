param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$ServerInstance,
    [Parameter(Mandatory=$true, Position=1)]
    [array]$appsToUninstall
)

function Uninstall-NAVApps {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$ServerInstance,
        [Parameter(Mandatory=$true, Position=1)]
        [array]$appsToUninstall
    )

    if (-not $appsToUninstall -or $appsToUninstall.Count -eq 0) {
        throw "No apps to uninstall"
    }

    $uninstalledApps = 0

    foreach ($appinfo in $appsToUninstall) {
        try {
            Write-Host "Uninstalling app $($appinfo.Name) version $($appinfo.Version)..."
            Uninstall-NAVApp -ServerInstance $ServerInstance -AppName $appinfo.Name -Version $appinfo.Version
            $uninstalledApps++
        }
        catch {
            Write-Error "Failed to uninstall app $($appinfo.Name) version $($appinfo.Version): $_"
        }
    }

    return $uninstalledApps
}

Write-Host "Checking server instance $ServerInstance..."
$navServerInstance = Get-NAVServerInstance -ServerInstance $ServerInstance

if ($null -eq $navServerInstance) {
    throw "Server instance $ServerInstance not found"
}
if ($navServerInstance.State -ne "Running") {
    throw "Server instance $ServerInstance is not running"
}

$uninstalledApps = Uninstall-NAVApps -ServerInstance $ServerInstance -appsToUninstall $appsToUninstall
Write-Host "Uninstalled $uninstalledApps apps" -ForegroundColor Green
