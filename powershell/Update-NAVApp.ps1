##  ===  Developer  ============================
##  Andreas Hargassner (AH)
##  Florian Marek (FM)
##
##  ===  Release Notes  ============================
##  2022-05-13 AH: Add function "AddAppToDependentList"
##  2022-08-09 AH: Fix bug on deploy new app, there have been an error for new apps
##  2022-08-12 FM: Add section "uninstall dependent apps", so no previous versions will stay as published
##  2022-09-07 JG: Add switch parameter "ForceSync" to toggle
##  2023-10-09 JG: Add parameter properties, cleanup, allow relative app paths
##  2024-05-06 JG: Update execution policy, remove superfluous lines
##  2024-05-16 JG: Major refactoring, use app ids, add option for NavAdminTool for module setup
##
##  ===  Abstract  ============================
##  This script will deploy a new app version. There must be a new version otherwise there will be an error.
##  These steps are processed:
##  +) All dependent apps will be uninstalled (if not so far)
##  +) The new app will be published
##  +) The Sync-NavApp is executed
##  +) The Sync-NavDataUpgrade is executed
##  +) All dependent apps will be installed again.
##
##  ===  Example usage  ============================
##  For terminal use:
##  Install-NAVApp.ps1 BC14-DEV -appPath "apps\Cronus_MyApp_1.0.1.3.app"
##  For .ps1 use:
##  & Install-NAVApp.ps1 -srvInst "BC14-DEV" -appPath "C:\BC\apps\Cronus_MyApp_1.0.1.3.app" #-ForceSync

param(
    [parameter(mandatory = $true, position = 0)]
    [string] $srvInst,
    [parameter(mandatory = $true)]
    [string] $appPath,
    [switch] $ForceSync,
    [string] $bcVersion,
    [string] $modulePath,
    [switch] $showColorKey
)

function Initialize-Modules() {
    param(
        [string] $bcVersion,
        [string] $modulePath
    )

    if ($modulePath -eq '' -and $bcVersion -ne '') {
        $modulePath = "C:\Program Files\Microsoft Dynamics 365 Business Central\$bcVersion\Service\NavAdminTool.ps1"
    }

    if ($modulePath -eq '') {
        if (!(Get-Module -ListAvailable -Name 'Cloud.Ready.Software.NAV')) {
            Write-Host 'Cloud.Ready.Sofware.NAV module is missing. Installing the module...' -ForegroundColor Yellow
            Install-Module -Name 'Cloud.Ready.Software.NAV' -Force -Scope CurrentUser
        }
        Import-NAVModules -RunAsJob -WarningAction SilentlyContinue
    }
    else {
        Import-Module $modulePath
    }
}

function Get-AppId() {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        $appInfo
    )
    return $appInfo.AppId.Value.Guid
}

function Initialize-ColorStyle() {
    param (
        $showColorKey
    )
    $style = @{
        Error    = "Red"
        Finished = "Green"
        Info     = "White"
        Success  = "Cyan"
        Warning  = "Magenta"
    }

    if ($showColorKey) {
        Write-Host " "
        Write-Host "Color key used in this script:" -ForegroundColor Gray
        Write-Host "Info .. Information, what is happening" -ForegroundColor $style.Info
        Write-Host "Success .. step handled successfully" -ForegroundColor $style.Success
        Write-Host "Finished .. script finished or main step successfully" -ForegroundColor $style.Finished
        Write-Host "Warning .. something is not working as usual" -ForegroundColor $style.Warning
        Write-Host "Error .. script failure with break" -ForegroundColor $style.Error
    }

    return $style
}

function Test-AppPath() {
    param(
        [string] $appPath
    )

    if (![System.IO.Path]::IsPathRooted($appPath)) {
        $appPath = Join-Path $PWD.Path $appPath
    }
    if (![System.IO.File]::Exists($appPath)) {
        throw "App could not be found: $appPath"
    }

    return $appPath
}

function Initialize-AppList() {
    param (
        [string] $srvInst
    )
    $appList = @{}
    $appArray = Get-NAVAppInfo -ServerInstance $srvInst -WarningAction SilentlyContinue
    $count = $appArray.Count
    for ($i = 0; $i -lt $count; $i++) {
        $app = $appArray[$i]
        $appId = Get-AppId $app
        $appList[$appId.ToString()] = Get-NAVAppInfo -ServerInstance $srvInst -Id $appId -WarningAction SilentlyContinue
    }
    return $appList
}

function Remove-AppFromDependentList() {
    param(
        [System.Guid] $appId,
        [hashtable] $appList
    )

    $appIdStr = $appId.ToString()
    $dependencies = $appList[$appIdStr].Dependencies
    foreach ($dep in $dependencies) {
        $depAppId = Get-AppId $dep
        $appList = Remove-AppFromDependentList -appId $depAppId -appList $appList
    }

    if ($appList.ContainsKey($appId)) {
        $appList.Remove($appId)
    }
    return $appList
}

function Get-DependentAppList() {
    param(
        [Parameter(Mandatory = $true)]
        [System.Guid] $appId,
        [Parameter(Mandatory = $true)]
        [string] $srvInst,
        [hashtable] $appList
    )
    $depList = @{}
    if ($null -eq $appList) {
        $appList = Initialize-AppList -srvInst $srvInst
        $appIdStr = $appId.ToString()
        if ($null -eq $appList[$appIdStr]) {
            Write-Host "Warning: App [$appIdStr] not found on server instance $srvInst" -ForegroundColor $style.Warning
            return $depList
        }
        $appList = Remove-AppFromDependentList -appId $appId -appList $appList
    }

    foreach ($appKey in $appList.Keys) {
        if ($depList.ContainsKey($appKey)) { continue }
        if (!($appList.ContainsKey($appKey))) { continue }

        $appInfo = $appList[$appKey]
        $appName = $appInfo.Name
        Write-Verbose "Checking dependencies of $appName..."
        foreach ($dep in $appInfo.Dependencies) {
            Write-Verbose "- $dep"
        }
        if ($null -eq $appInfo.Dependencies) { continue }
        $appDependencies = $appInfo.Dependencies | ForEach-Object { Get-AppId $_ } # TODO: Replace with Get-AppId $appInfo.Dependencies
        if ($appDependencies -contains $appId) {
            $appList.Remove($appKey)
            Write-Host "Dependent found: $appName Version ${appInfo.Version}"
            $depList[$appKey] = $appInfo
            $depList += Get-DependentAppList -appId $appKey -appList $appList
        }
    }
    return $depList
}

function Install-App() {
    param (
        [Parameter(Mandatory = $true)]
        $appInfo,
        [string] $srvInst
    )
    if ($null -eq $appInfo) {
        throw "AppInfo is missing."
    }
    $appName = $appInfo.Name
    $appVersion = $appInfo.Version
    Write-Host "Install-NAVApp -ServerInstance $srvInst -Name $appName -Version $($appVersion -join '.')" -ForegroundColor $style.Info
    Install-NAVApp -ServerInstance $srvInst -Name $appName -Version $appVersion
}

function Uninstall-App() {
    param (
        [string] $srvInst,
        $appInfo
    )
    $appName = $appInfo.Name
    $appVersion = $appInfo.Version
    Write-Verbose "Uninstall-NAVApp -ServerInstance $srvInst -Name $appName -Version $($appVersion -join '.')"
    Uninstall-NAVApp -ServerInstance $srvInst -Name $appName -Version $appVersion
}

function Unpublish-OldNAVApp() {
    param(
        [Parameter(Mandatory = $true)]
        $appInfo,
        [string] $srvInst
    )
    if ($null -eq $appInfo) {
        throw "AppInfo is missing."
    }
    $appName = $appInfo.Name
    $appVersion = $appInfo.Version -join '.'
    Write-Host "Unpublish-NAVApp -ServerInstance $srvInst -Name $appName -Version $appVersion" -ForegroundColor $style.Info
    Unpublish-NAVApp -ServerInstance $srvInst -Name $appName -Version $appVersion
    Write-Host "Unpublished $appName $appVersion." -ForegroundColor $style.Info
}

function Unpublish-NAVApps() {
    param(
        [string] $srvInst,
        [array] $apps
    )
    Write-Verbose "Unpublishing the following apps:"
    Write-Verbose ($apps | Format-Table -AutoSize | Out-String)

    foreach ($appInfo in $apps) {
        Unpublish-OldNAVApp -srvInst $srvInst -appInfo $appInfo
    }
}

function Unpublish-OldVersions() {
    param(
        [Parameter(Mandatory = $true)]
        $appInfo,
        [string] $srvInst
    )
    if ($null -eq $appInfo) {
        throw "AppInfo is missing."
    }
    $appId = Get-AppId $appInfo
    $appName = $appInfo.Name
    $appVersion = $appInfo.Version

    $currVersions = Get-NAVAppInfo -ServerInstance $srvInst -Id $appId -WarningAction SilentlyContinue
    $currVersions = $currVersions | Where-Object { ($_.Version -ne $appVersion) -and ($_.Scope -eq 'Global') }
    if ($null -ne $currVersions) {
        Write-Host "Unpublishing previous versions of $appName..." -ForegroundColor $style.Info
        Unpublish-NAVApps -srvInst $srvInst -apps $currVersions
    }
}

function Sync-App() {
    param (
        [Parameter(Mandatory = $true)]
        $appInfo,
        [string] $srvInst,
        [bool] $ForceSync
    )
    if ($null -eq $appInfo) {
        throw "AppInfo is missing."
    }
    $appName = $appInfo.Name
    $appVersion = $appInfo.Version
    $commandString = "Sync-NAVApp -ServerInstance $srvInst -Name $appName -Version $appVersion"

    $syncParams = @{
        ServerInstance = $srvInst
        Name           = $appName
        Version        = $appVersion
    }
    if ($ForceSync) {
        $commandString += " -Mode ForceSync"
        $syncParams.Add('Mode', 'ForceSync')
    }

    Write-Host $commandString -ForegroundColor $style.Info
    Sync-NAVApp @syncParams
}

# === End of functions ===

$ErrorActionPreference = "Stop"
Initialize-Modules -bcVersion $bcVersion -modulePath $modulePath
$style = Initialize-ColorStyle -showColorKey $showColorKey

$appPath = Test-AppPath -appPath $appPath

$newAppInfo = Get-NAVAppInfo -Path $appPath

if ($null -eq $newAppInfo) {
    throw "File could not be read: $appPath"
}

$newAppId = $newAppInfo.AppId
$newAppName = $newAppInfo.Name
$newVersion = $newAppInfo.Version
$newVersionString = $newVersion -join '.'

$oldAppInfo = Get-NAVAppInfo -ServerInstance $srvInst -Id $newAppId -WarningAction SilentlyContinue
$oldAppExists = ($null -ne $oldAppInfo)
$sameVersion = $oldAppExists -and ($oldAppInfo.Version -eq $newVersion)
$oldVersion = if ($oldAppExists) { $oldAppInfo.Version } else { $null }

if ($sameVersion) {
    Write-Host "$newAppName $newVersionString has already been published - only 'Sync-NAVApp' and 'Start-NAVDataUpgrade' will be performed." -ForegroundColor $style.Warning
    Write-Host 'All dependent Apps will be installed beforehand.' -ForegroundColor $style.Info
    Write-Host "Publishing requires an app with a version greater than $($oldVersion -join '.')." -ForegroundColor $style.Info
}

[hashtable] $dependentList = @{}

if ($oldAppExists) {
    Write-Host "Searching for apps depending on $newAppName..." -ForegroundColor $style.Info
    $dependentList = Get-DependentAppList -appId $newAppId -srvInst $srvInst

    if ($dependentList.Count -gt 0) {
        Write-Host "Found a total of ${dependentList.Count} dependent apps." -ForegroundColor $style.Success
        foreach ($depAppKey in $dependentList.Keys) {
            $depAppInfo = $dependentList[$depAppKey]
            Write-Host "Uninstalling dependent app ${depAppInfo.Name}..." -ForegroundColor $style.Info
            Uninstall-App -srvInst $srvInst -appInfo $depAppInfo
        }
    }
    else {
        Write-Host "No dependent apps found." -ForegroundColor $style.Success
    }
}

if ($sameVersion) {
    Install-App -srvInst $srvInst -appInfo $newAppInfo
}
else {
    Write-Host "Publish-NAVApp -ServerInstance $srvInst -Path $appPath -SkipVerification -PackageType Extension" -ForegroundColor $style.Info
    Publish-NAVApp -ServerInstance $srvInst -Path $appPath -SkipVerification -PackageType Extension
    Sync-App -srvInst $srvInst -appInfo $newAppInfo -ForceSync $ForceSync

    if ($oldAppExists) {
        Write-Host "Start-NAVAppDataUpgrade -ServerInstance $srvInst -Name $newAppName -Version $newVersionString" -ForegroundColor $style.Info
        Start-NAVAppDataUpgrade -ServerInstance $srvInst -Name $newAppName -Version $newVersion
    }
}

Write-Host "App $newAppName Version $newVersion installed!" -ForegroundColor $style.Success

if ($oldAppExists -and $dependentList.Count -gt 0) {
    Write-Host "Installing dependent apps..." -ForegroundColor $style.Info
    foreach ($depAppKey in $dependentList.Keys) {
        $depAppInfo = $dependentList[$depAppKey]
        Install-App -srvInst $srvInst -appInfo $depAppInfo
    }
}

if ($oldAppExists) {
    Unpublish-OldVersions -srvInst $srvInst -appInfo $newAppInfo
}

Write-Host "App $newAppName Version $newVersionString DEPLOYED!!" -ForegroundColor $style.Finished
