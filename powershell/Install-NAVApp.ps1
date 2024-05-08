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
##  2034-05-06 JG: Update execution policy, remove superfluous lines
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
    [string]$srvInst,
    [parameter(mandatory = $true)]
    [string]$appPath,
    [switch]$ForceSync,
    [switch]$showColorKey
)

##  ===  Prepare PowerShell for default BC18 installation

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
$ErrorActionPreference = "Stop"
Import-Module 'C:\Program Files\Microsoft Dynamics 365 Business Central\140\Service\NavAdminTool.ps1'

## ===  Color description  ======================

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

function Initialize-AppList() {
    param (
        [string] $srvInst
    )
    $appList = @{}
    $appArray = Get-NAVAppInfo -ServerInstance $srvInst -WarningAction SilentlyContinue
    $count = $appArray.Count
    for ($i = 0; $i -lt $count; $i++) {
        $appName = $appArray[$i].Name
        $appList[$appName] = Get-NAVAppInfo -ServerInstance $srvInst -Name $app.Name -WarningAction SilentlyContinue
    }
    return $appList
}

function Remove-AppFromDependentList() {
    param(
        [string] $appName,
        [hashtable] $appList
    )

    $dependencies = $appList[$appName].Dependencies
    foreach ($dep in $dependencies) {
        $appList = Remove-AppFromDependentList -appName $dep.Name -appList $appList
    }

    if ($appList.ContainsKey($appName)) {
        $appList.Remove($appName)
    }
    return $appList
}

function Get-DependentAppList() {
    ## Returns a list of apps dependent on the given app
    param(
        [Parameter(Mandatory = $true)]
        [string] $appName,
        [Parameter(Mandatory = $true)]
        [string] $srvInst,
        [hashtable] $appList
    )
    $depList = @{}
    if($null -eq $appList) {
        $appList = Initialize-AppList -srvInst $srvInst
        if ($null -eq $appList[$appName]) {
            Write-Host "Warning: App $appName not found on server instance $srvInst" -ForegroundColor $style.Warning
            return $depList
        }
        $appList = Remove-AppFromDependentList -appName $appName -appList $appList
    }

    foreach ($appKey in $appList.Keys) {
        if ($depList.ContainsKey($appKey)) { continue }
        $appInfo = $appList[$appKey]
        Write-Verbose "Checking dependencies of $appKey..."
        foreach ($dep in $appInfo.Dependencies) {
            Write-Verbose "- $dep"
        }
        if($null -eq $appInfo.Dependencies) { continue }
        if($appInfo.Dependencies -contains $appName) {
            $appList.Remove($appKey)
            Write-Host "Dependent found: $appKey Version ${appInfo.Version}"
            $depList[$appKey] = $appInfo
            $depList += AddAppToDependentList -appName $appKey -appList $appList
        }
    }
    return $depList
}

##  ===  Check parameters and app version  ==================================================


##  ===  Check parameters and app version  ==================================================

if (![System.IO.Path]::IsPathRooted($appPath)) {
    $appPath = Join-Path $PWD.Path $appPath
}

if (![System.IO.File]::Exists($appPath)) {
    throw "App could not be found: $appPath"
}

$appInfo = Get-NAVAppInfo -Path $appPath

$newAppName = $appInfo.Name
$oldVersion = $null

$appOld = Get-NAVAppInfo -ServerInstance $srvInst -Name $newAppName
if ($null -ne $appOld) {
    $oldVersion = $appOld.Version
}
$newVersionString = $appInfo.Version -join '.'
$oldVersionString = $oldVersion -join '.'

if ($oldVersion -eq $appInfo.Version) {
    Write-Host "Version ${appInfo.Version} of $newAppName has already been published - only "Sync-NAVApp" and "Start-NAVDataUpgrade" will be performed." -ForegroundColor $style.Warning
    Write-Host 'All dependent Apps will be installed before.' -ForegroundColor $style.Info
    Write-Host "Publishing requires an app with a version greater than $oldVersionString." -ForegroundColor $style.Info
}

##  ===  Uninstall dependent apps  ======================================

if ($null -ne $oldVersion) {
    Write-Host "Searching for dependent apps of $newAppName..." -ForegroundColor $style.Info
    [hashtable]$dependentList = Get-DependentAppList -appName $newAppName -srvInst $srvInst

    if ($dependentList.Count -eq 0) {
        Write-Host "No dependent apps found." -ForegroundColor $style.Success
    }
    else {
        Write-Host "Found a total of ${dependentList.Count} dependent apps" -ForegroundColor $style.Success
        foreach ($depAppName in $dependentList.Keys) {
            Write-Host "Uninstalling dependent app $depAppName" -ForegroundColor $style.Info
            Write-Verbose "Uninstall-NAVApp -ServerInstance $srvInst -Name $depAppName"
            UnInstall-NAVApp -ServerInstance $srvInst -Name $depAppName
        }
    }
}

##  ===  Publish new app  =========================

if ($oldVersion -eq $appInfo.Version) {
    Write-Host "Install-NAVApp -ServerInstance $srvInst -Name ${appInfo.Name} -Version $newVersionString" -ForegroundColor $style.Info
    Install-NAVApp -ServerInstance $srvInst -Name $appInfo.Name -Version $appInfo.Version
}
else {
    Write-Host "Publish-NAVApp -ServerInstance $srvInst -Path $appAbsPath -SkipVerification -PackageType Extension" -ForegroundColor $style.Info
    Publish-NAVApp -ServerInstance $srvInst `
        -Path $appAbsPath `
        -SkipVerification `
        -PackageType Extension

    switch ($ForceSync) {
        $true {
            Write-Host "Sync-NavApp -ServerInstance $srvInst -Name ${appInfo.Name} -Version $newVersionString -Mode ForceSync" -ForegroundColor $style.Info
            Sync-NavApp -ServerInstance $srvInst -Name $appInfo.Name -Version $appInfo.Version -Mode ForceSync
        }
        $false {
            Write-Host "Sync-NavApp -ServerInstance $srvInst -Name ${appInfo.Name} -Version $newVersionString" -ForegroundColor $style.Info
            Sync-NavApp -ServerInstance $srvInst -Name $appInfo.Name -Version $appInfo.Version
        }
    }

    if ($null -ne $oldVersion) {
        Write-Host "Start-NAVAppDataUpgrade -ServerInstance $srvInst -Name ${appInfo.Name} -Version $newVersionString" -ForegroundColor $style.Info
        Start-NAVAppDataUpgrade -ServerInstance $srvInst -Name $appInfo.Name -Version $appInfo.Version
    }
}

Write-Host App $appInfo.Name Version $appInfo.Version installed  -ForegroundColor $style.Success

##  ===  Install dependent apps ==================

foreach ($depAppName in $dependentList.Keys) {
    $depAppInfo = $dependentList[$depAppName]
    Write-Host "Install-NAVApp -ServerInstance $srvInst -Name $depAppName -Version $newVersionString" -ForegroundColor $style.Info
    Install-NAVApp -ServerInstance $srvInst -Name $depAppName -Version $depAppInfo.Version
}

##  ===  Unpublish all previous app versions =====

$currVersions = Get-NAVAppInfo -ServerInstance $srvInst -Name $appInfo.Name
$currVersions = $currVersions | Where-Object { ($_.Version -ne $appInfo.Version) -and ($_.Scope -eq 'Global') }

foreach ($element in $currVersions) {
    Write-Host "Unpublish-NAVApp -ServerInstance $srvInst -Name $element.Name -Version $element.Version" -ForegroundColor $style.Info
    Unpublish-NAVApp -ServerInstance $srvInst -Name $element.Name -Version $element.Version
    Write-Host "Unpublished ${element.Name} ${element.Version}" -ForegroundColor $style.Info
}

Write-Host "App ${appInfo.Name} Version ${appInfo.Version} DEPLOYED!!" -ForegroundColor $style.Finished
