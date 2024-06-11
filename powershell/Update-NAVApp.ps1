##  ===  Developer  ============================
##  Andreas Hargassner
##  Florian Marek
##  Jakob Gillinger
##
##  ===  Abstract  ============================
##  This script will deploy a new app version.
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
    [ValidateNotNullOrEmpty()]
    [string] $srvInst,
    [parameter(mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string] $appPath,
    [switch] $ForceSync,
    [string] $bcVersion,
    [ValidateScript({ if (![string]::IsNullOrEmpty($_)) { Test-Path $_ -PathType Leaf } else { $true } })]
    [string] $modulePath,
    [switch] $showColorKey,
    [switch] $runAsJob
)

function CheckCommands() {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$commands
    )
    try {
        $commands | ForEach-Object {
            Get-Command -Name $_ -ErrorAction Stop | Out-Null
        }
    }
    catch {
        return $false
    }
    return $true
}

function Initialize-Modules() {
    param(
        [Parameter(Mandatory = $false)]
        [string] $bcVersion,
        [ValidateScript({ if (![string]::IsNullOrEmpty($_)) { Test-Path $_ -PathType Leaf } else { $true } })]
        [Parameter(Mandatory = $false)]
        [string] $modulePath,
        [Parameter(Mandatory = $false)]
        [switch] $runAsJob
    )

    if ([string]::IsNullOrEmpty($modulePath) -and ![string]::IsNullOrEmpty($bcVersion)) {
        $modulePath = "C:\Program Files\Microsoft Dynamics 365 Business Central\$bcVersion\Service\NavAdminTool.ps1"
    }

    if ([string]::IsNullOrEmpty($modulePath)) {
        if (!(Get-Module -ListAvailable -Name 'Cloud.Ready.Software.NAV')) {
            Write-Host 'Cloud.Ready.Sofware.NAV module is missing. Installing the module...' -ForegroundColor Yellow
            Install-Module -Name 'Cloud.Ready.Software.NAV' -Force -Scope CurrentUser
        }
        Import-NAVModules -WarningAction SilentlyContinue -RunAsJob:$runAsJob
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

    if (-not $appInfo.PSObject.Properties.Name -contains 'AppId') {
        throw "AppInfo is missing the parameter 'AppId' - type: $($appInfo.GetType().FullName)"
    }

    $appId = $appInfo.AppId

    switch ($true) {
        ($appId -is [System.Guid]) { return $appId }
        ($appId -is [Microsoft.Dynamics.Nav.Apps.Types.AppId]) { return $appId.Value }
        default { throw "AppId is not a valid type: $($appId.GetType().FullName)" }
    }
}

function Initialize-ColorStyle() {
    param (
        [bool] $showColorKey = $false
    )
    $style = @{
        Error    = "Red"
        Finished = "Green"
        Info     = "White"
        Success  = "Cyan"
        Warning  = "Magenta"
        Command  = "Gray"
    }

    if ($showColorKey) {
        Write-Host " "
        Write-Host "Color key used in this script:" -ForegroundColor Gray
        Write-Host "Info .. Information, what is happening" -ForegroundColor $style.Info
        Write-Host "Success .. step handled successfully" -ForegroundColor $style.Success
        Write-Host "Finished .. script finished or main step successfully" -ForegroundColor $style.Finished
        Write-Host "Warning .. something is not working as usual" -ForegroundColor $style.Warning
        Write-Host "Error .. script failure with break" -ForegroundColor $style.Error
        Write-Host "Command .. command & parameters sent to terminal" -ForegroundColor $style.Command
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
    [Int32] $count = $appArray.Count
    for ($i = 0; $i -lt $count; $i++) {
        $app = $appArray[$i]
        [System.Guid] $appId = Get-AppId $app
        $appList[$appId.Guid] = Get-NAVAppInfo -ServerInstance $srvInst -Id $appId -WarningAction SilentlyContinue
    }
    return $appList
}

function Get-NewestPublishedAppVersion() {
    param (
        [Parameter(Mandatory = $true)]
        [string] $srvInst,
        [Parameter(Mandatory = $true)]
        [System.Guid] $appId
    )
    $oldApps = Get-NAVAppInfo -ServerInstance $srvInst -Id $appId -WarningAction SilentlyContinue
    if ($null -eq $oldApps) {
        return $null
    }
    $oldApps = $oldApps | Sort-Object -Property Version -Descending
    return $oldApps[0].Version
}

function Remove-AppFromDependentList() {
    param(
        [System.Guid] $appId,
        [hashtable] $appList
    )

    $dependencies = $appList[$appId.Guid].Dependencies
    foreach ($dep in $dependencies) {
        [System.Guid] $depAppId = Get-AppId $dep
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
        [string] $appIdStr = $appId.Guid
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
        [System.Guid[]] $appDependencies = $appInfo.Dependencies | ForEach-Object { Get-AppId $_ }
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
    Write-Host "Install-NAVApp -ServerInstance $srvInst -Name $appName -Version $($appVersion -join '.')" -ForegroundColor $style.Command
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
    Write-Host "Unpublish-NAVApp -ServerInstance $srvInst -Name $appName -Version $appVersion" -ForegroundColor $style.Command
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
    [System.Guid] $appId = Get-AppId $appInfo
    [string] $appName = $appInfo.Name
    [System.Version] $appVersion = $appInfo.Version

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

    Write-Host $commandString -ForegroundColor $style.Command
    Sync-NAVApp @syncParams
}

# === End of functions ===

$ErrorActionPreference = "Stop"
$commands = @(
    'Install-NAVApp',
    'Uninstall-NAVApp',
    'Publish-NAVApp',
    'Sync-NAVApp',
    'Start-NAVAppDataUpgrade',
    'Unpublish-NAVApp'
)

if (-not (CheckCommands -commands $commands)) {
    Initialize-Modules -runAsJob:$runAsJob -bcVersion $bcVersion -modulePath $modulePath
}
$style = Initialize-ColorStyle -showColorKey $showColorKey

$appPath = Test-AppPath -appPath $appPath

$newAppInfo = Get-NAVAppInfo -Path $appPath

if ($null -eq $newAppInfo) {
    throw "File could not be read: $appPath"
}

[System.Guid] $newAppId = Get-AppId $newAppInfo
[string] $newAppName = $newAppInfo.Name
[System.Version] $newVersion = $newAppInfo.Version
[string] $newVersionString = $newVersion -join '.'

[System.Version] $oldVersion = Get-NewestPublishedAppVersion -srvInst $srvInst -appId $newAppId
[bool] $oldAppExists = ($null -ne $oldVersion)
[bool] $sameVersion = ($oldVersion -eq $newVersion)

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
    Write-Host "Publish-NAVApp -ServerInstance $srvInst -Path $appPath -SkipVerification -PackageType Extension" -ForegroundColor $style.Command
    Publish-NAVApp -ServerInstance $srvInst -Path $appPath -SkipVerification -PackageType Extension
    Sync-App -srvInst $srvInst -appInfo $newAppInfo -ForceSync $ForceSync

    if ($oldAppExists) {
        Write-Host "Start-NAVAppDataUpgrade -ServerInstance $srvInst -Name $newAppName -Version $newVersionString" -ForegroundColor $style.Command
        Start-NAVAppDataUpgrade -ServerInstance $srvInst -Name $newAppName -Version $newVersion
    }
    else {
        Install-App -srvInst $srvInst -appInfo $newAppInfo
    }
}

Write-Host "App $newAppName Version $newVersion installed!" -ForegroundColor $style.Success

if ($oldAppExists) {
    if ($dependentList.Count -gt 0) {
        Write-Host "Installing dependent apps..." -ForegroundColor $style.Info
        foreach ($depAppKey in $dependentList.Keys) {
            $depAppInfo = $dependentList[$depAppKey]
            Install-App -srvInst $srvInst -appInfo $depAppInfo
        }
    }
    Unpublish-OldVersions -srvInst $srvInst -appInfo $newAppInfo
}

Write-Host "App $newAppName Version $newVersionString DEPLOYED!!" -ForegroundColor $style.Finished
