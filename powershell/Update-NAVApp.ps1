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
##
##  ===  Abstract  ============================
##  This script will deploy a new app version. There must be a new version otherwise there will be an error.
##  These steps are processed:
##  +) All dependant apps will be uninstalled (if not so far)
##  +) The new app will be published
##  +) The Sync-NavApp is executed
##  +) The Sync-NavDataUpgrade is executed
##  +) All dependant apps will be installed again.
##
##  ===  Example usage  ============================
##  Update-NAVApp BC14-DEV -appPath "apps\Cronus_MyApp_1.0.1.3.app"
##  Update-NAVApp -srvInst "BC14-DEV" -appPath "C:\\BC\apps\Cronus_MyApp_1.0.1.3.app" -ForceSync

param(
    [parameter(mandatory = $true, position = 0)]
    [string]$srvInst,
    [parameter(mandatory = $true)]
    [string]$appPath,
    [switch]$ForceSync
)

##  ===  Prepare PowerShell vor default BC18 installation

Set-ExecutionPolicy unrestricted -Force
Import-Module 'C:\Program Files\Microsoft Dynamics 365 Business Central\200\Service\NavAdminTool.ps1'

## ===  Color description  ======================

$showColorDescription = 0
$styleInfo = "White"
$styleSuccess = "Cyan"
$styleFinished = "Green"
$styleError = "Red"
$styleWarning = "Magenta"

if ($showColorDescription) {
    Write-Host " "
    Write-Host Colour description used in this script: -ForegroundColor Gray
    Write-Host Info .. Information, what is happpening -ForegroundColor $styleInfo
    Write-Host Success .. step handled successfully -ForegroundColor $styleSuccess
    Write-Host Finished .. script finished or main step successfully -ForegroundColor $styleFinished
    Write-Host Warning .. attention, some is not working as usual -ForegroundColor $styleWarning
    Write-Host Error .. script failure with break  -ForegroundColor $styleError
}

##  ===  function "AddAppToDependentList"  ======================================

function AddAppToDependentList() {
    ## this function will append a list of all apps which are depened from the $appName parameter
    param(
        $appName,
        [PSObject[]] $depList,
        [int] $level
    )

    $Apps = Get-NAVAppInfo -ServerInstance $srvInst  # get a list of all apps of the installation
    foreach ($App in $Apps) {
        $appInfo = Get-NAVAppInfo -ServerInstance $srvInst -Name $App.Name
        foreach ($dep in $appInfo.Dependencies) {
            # go through all dependencies of one app, whether this is the given app
            #Write-Host $dep.Name $appName $appInfo.Name
            if ($dep.Name -eq $appName) {
                Write-Host Dependent: $appInfo.Name Version $appInfo.Version Level $level
                ## there are dependent apps, first handle these
                $depList = AddAppToDependentList -appName $appInfo.Name -depList $depList -level $level + 1
                $depList += [PSCustomObject]@{
                    Name    = $appInfo.Name
                    Version = $appInfo.Version
                    Level   = $level
                }
            }
        } # all dependencies in one app

    } # all apps
    return $depList

} ## end of function "AddAppToDependentList"

##  ===  Check parameters and app version  ==================================================

$error.Clear();

if (Test-Path -Path $appPath -PathType Leaf) {
    $appAbsPath = $appPath
}
else {
    $cwd = Get-Location
    $appAbsPath = Join-Path -Path $cwd -ChildPath $appPath
}

$appInfo = Get-NAVAppInfo -Path $appAbsPath # get and check existing appInfo
if ($error) {
    Write-Host 'File could not be found: ' $appAbsPath -ForegroundColor $styleError
    break ;
}

$newAppName = $appInfo.Name

$appOld = Get-NAVAppInfo -ServerInstance $srvInst -Name $newAppName
if ($appOld.Version -eq $appInfo.Version) {
    Write-Host 'Version' $appInfo.Version of $newAppName is allready published -ForegroundColor $styleWarning
    Write-Host 'To publish you have to take an app version, which has not published so far.' -ForegroundColor $styleInfo
    Write-Host 'In this case, there will only be a Sync-NAVApp and a Start-NAVDataUpgrade.' -ForegroundColor $styleInfo
    Write-Host 'All dependend Apps will be istalled before.' -ForegroundColor $styleInfo
}

##  ===  Get list of apps which have to be uninstalled  ======================================

$dependentList = @();
$dependentList = AddAppToDependentList -appName $newAppName -depList $dependentList
$cnt = $dependentList.Count
$onlyOneDep = 0
if (($null -ne $dependentList) -and ($cnt -lt 1)) {
    #  Special handling of only one dependency, because dependentList is not a list
    $onlyOneDep = 1;
    $cnt = 1
}

Write-Host Sum of Dependent Apps: $cnt -ForegroundColor $styleSuccess

##  ===  uninstall dependent apps   ====================================================

for ($i = 0; $i -lt $cnt; $i++) {
    $error.Clear();
    if ($onlyOneDep)   #  Special handling of only one dependency, because dependentList is not a list
    { $depAppInfo = $dependentList; }
    else
    { $depAppInfo = $dependentList.Get($i); }

    Write-Host Uninstall AppName: $depAppInfo.Name -ForegroundColor $styleInfo
    UnInstall-NAVApp -ServerInstance $srvInst -Name $depAppInfo.Name
    if ($error) {
        Write-Host 'Error on uninstalling dependent apps :' -ForegroundColor $styleError
        Write-Host $error -ForegroundColor $styleError
        break ;
    }
}

##  ===  publish new app  =========================

$error.clear()
if ($appOld.Version -ne $appInfo.Version) {
    ## new version publish
    Write-Host Publishing NAVApp $srvInst $appAbsPath ... -ForegroundColor $styleInfo
    Publish-NAVApp -ServerInstance $srvInst `
        -Path $appAbsPath `
        -SkipVerification `
        -PackageType Extension
}
if ($error) {
    Write-Host 'Error on publishing app' $appInfo.Name -ForegroundColor $styleError
    Write-Host $error -ForegroundColor $styleError
    break
}

##  ===  Sync and Upgrade new app  =========================

$error.clear()
if ($appOld.Version -ne $appInfo.Version) {
    ## new version Sync
    Write-Host Sync-NavApp $srvInst $appInfo.Name ... -ForegroundColor $styleInfo
    switch ($ForceSync) {
        $true { Sync-NavApp -ServerInstance $srvInst -Name $appInfo.Name -Version $appInfo.Version -Mode ForceSync }
        $false { Sync-NavApp -ServerInstance $srvInst -Name $appInfo.Name -Version $appInfo.Version }
    }
}
else {
    ## Same Version
    Install-NAVApp -ServerInstance $srvInst -Name $appInfo.Name -Version $appInfo.Version
}

if ($error) {
    Write-Host 'Error on sync app' $appName -ForegroundColor $styleError
    Write-Host $error -ForegroundColor $styleError
    break;
}

# data upgrade only if there is a previous version and the new version is higher

if ( ($appOld.Version -ne $appInfo.Version) -and ($null -ne $appOld.Version) ) {
    ## new version DataUpgrade
    Write-Host Start-NAVAppDataUpgrade $srvInst $appName ... -ForegroundColor $styleInfo
    Start-NAVAppDataUpgrade -ServerInstance $srvInst -Name $appInfo.Name -Version $appInfo.Version
}
else {
    Install-NAVApp -ServerInstance $srvInst -Name $appInfo.Name #-Version $appInfo.Version
    Write-Host Install-NAVApp -ServerInstance $srvInst -Name $appInfo.Name -ForegroundColor $styleInfo
}

if ($error) {
    Write-Host 'Error on data upgrade app' $appName -ForegroundColor $styleError
    Write-Host $error -ForegroundColor $styleError
    break;
}

Write-Host App $appInfo.Name Version $appInfo.Version installed  -ForegroundColor $styleSuccess

##  ===  Install dependent apps

for ($i = $cnt - 1; $i -ge 0; $i--) {
    $error.Clear();

    if ($onlyOneDep)
    { $depAppInfo = $dependentList; }
    else
    { $depAppInfo = $dependentList.Get($i); }

    if ($cnt -eq 0) { $depAppInfo = $dependentList; }
    Write-Host Install App $depAppInfo.Name Version $depAppInfo.Version -ForegroundColor $styleInfo
    Install-NAVApp -ServerInstance $srvInst -Name $depAppInfo.Name -Version $depAppInfo.Version
    if ($error) {
        Write-Host 'Error on installing dependent apps :' -ForegroundColor $styleError
        Write-Host $error -ForegroundColor $styleError
        break ;
    }
}

##  ===  Unpublish all previous app versions

$currVersions = Get-NAVAppInfo -ServerInstance $srvInst -Name $appInfo.Name

ForEach ($element in $currVersions) {
    if ( ($element.Scope -eq 'Global') -and ($element.Version -ne $appInfo.Version) ) {
        Unpublish-NAVApp -ServerInstance $srvInst -Name $element.Name -Version $element.Version

        if ($error) {
            Write-Host $error -ForegroundColor $styleError
        }
        else {
            Write-Host Unpublished : $element.Version -ForegroundColor $styleInfo
        }
    }
}

Write-Host App $appInfo.Name Version $appInfo.Version DEPLOYED  !! -ForegroundColor $styleFinished

return;
break;

##  ===  END of SCRIPT  ======================================

##  ===  Code snippets  ======================================

# Write-Host DO NOT Execeute -ForegroundColor Cyan
# $depApp = $list.DependentApps.Get(0)

# UnInstall-NAVApp -ServerInstance $srvInst -Name 'App-A'
# Write-Host 'App "Teamcenter Interface Connector"' uninstalled ! -ForegroundColor $styleSuccess

# Publish-NAVApp -ServerInstance $srvInst `
# -Path "I:\Cegeka\AH\AH_app-C-B_1.0.0.1.app" `
# -SkipVerification `
# -PackageType Extension

# $dependentList = @()
# $dependentList += [PSCustomObject]@{
#               Name     = 'Empty'
#               Version  = '1.0.0.0'
#               Level    = 0
#           }

# $cnt = $dependentList.Count
# write-host $cnt $dependentList

# $dependentList = AddAppToDependentList -AppName app-B-A -DependentList $dependentList
# Write-Host Dependent Apps from $appInfo.Name Summary: $dependentList -ForegroundColor $styleSuccess
# $cnt = $dependentList.Count
# write-host $cnt $dependentList

# UnPublish-NAVApp -ServerInstance $srvInst -Name 'App-B-A' -Version 1.0.0.1
# Get-NAVAppInfo -Name App-B-A
# UnInstall-NAVApp -ServerInstance $srvInst -Name App-B-A
