<#
.SYNOPSIS
    This is a PowerShell script used to automatically install the latest version
    of a given extension in a Business Central environment.

.DESCRIPTION
    This script checks if the a server instance is provided, and if not, it
    assigns a default server instance based on the server parameter.
    If a path to a specific application file is not provided, it searches for
    the application file with the highest version number in the specified
    application folder. Finally, it executes the Update-NAVApp.ps1 script with
    the provided parameters.

.PARAMETER configURI
    Specifies the path to the configuration file. Accepts filepaths and
    URLs. Default value is "\NAVInstall.config.json".

.PARAMETER server
    Specifies the server instance. If not provided, the user can choose between
    the server instances defined in the configuration file.

.PARAMETER appFolder
    Specifies the path to the application folder. If not provided, the script
    will use the default application folder defined in the configuration file.

.PARAMETER appName
    Specifies the name of the application defined in the configuration file. If
    not provided, the script will use the default application name defined in
    the configuration file.

.PARAMETER appVersion
    Specifies the version of the application. Accepts wildcards such as 1.3.*.
    Default value is "*".

.PARAMETER appPath
    Specifies the path to the application file. If not provided, the script will
    search for the application file with the highest version number in the
    specified application folder.

.PARAMETER scriptURI
    Specifies the path to the update script. May be a path to a local file or a
    URL. Default value is
    "https://raw.githubusercontent.com/CBS-BC-AT-Internal/INT.utilities/v0.2.18/powershell/Update-NAVApp.ps1".

.PARAMETER ForceSync
    Switch parameter to force synchronization during the update process.

.PARAMETER dryRun
    Specifies whether to run the script without writing any changes to the system.
    Used for testing purposes. Default value is "$False".

.EXAMPLE
    .\UpdateHelper.ps1 -server "BC-DEV1"
    Updates the default application on the server named "BC-DEV1"
    using the latest version in the default application folder and without
    forcing synchronization.

.EXAMPLE
    .\UpdateHelper.ps1 -server "LIVE" -server "BC-LIVE" -appName "Cegeka_Helper App"
    Updates the application "Cegeka_Helper App" on the server named "BC-LIVE"
    using the latest version in the default application folder and without
    forcing synchronization.

.EXAMPLE
    .\UpdateHelper.ps1 -server "TEST" -appFolder "E:\bccontent\apps" -version 1.0.3.0 -ForceSync
    Updates the default application with the version "1.0.3.0" in the
    "E:\bccontent\apps" folder on the "TEST" server, and forces synchronization.

#>
param (
    [Parameter(Position = 0)]
    [string]$configURI = "NAVInstall.config.json",
    [string]$server,
    [string]$appFolder,
    [string]$appName,
    [string]$appVersion = "*",
    [string]$appPath,
    [string]$scriptURI = "https://raw.githubusercontent.com/CBS-BC-AT-Internal/INT.utilities/v0.2.18/powershell/Update-NAVApp.ps1",
    [switch]$ForceSync,
    [switch]$dryRun = $False
)

function Read-Input {
    param (
        [Parameter(Mandatory = $true)]
        [string]$prompt,
        [string[]]$options
    )

    Write-Host "${prompt}:"
    if ($options) {
        Write-Host $options -Separator ", "
    }
    return Read-Host
}

function Read-Option {
    param (
        [Parameter(Mandatory = $true)]
        [string]$prompt,
        [string[]]$options
    )
    Write-Host "${prompt}:"
    $options | ForEach-Object { $index = [Array]::IndexOf($options, $_); Write-Host "[$index] $_" }

    while ($true) {
        $selection = Read-Host "[0-$($options.Length)] or [q]uit"
        $selection = $selection.Trim()
        if ($selection -eq 'q' -or $selection -eq 'Q') {
            Write-Error "User cancelled the operation."
        }
        elseif ($selection -match '^\d+$' -and $selection -ge 0 -and $selection -le $options.Length) {
            return $selection
        }
        else {
            Write-Host "Invalid selection. Please select a number between 0 and $($options.Length)."
        }
    }
}

function Select-Apps {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        $apps
    )
    $options = @("All")
    $apps | ForEach-Object { $options += $_.name }

    $selection = Read-Option -prompt "Please select an application to install" -options $options
    if ($selection -eq 0) {
        return $apps
    }
    else {
        return $apps[$selection - 1]
    }
}

function Get-Server {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        $config
    )

    if ($PSVersionTable.PSVersion.Major -le 5) {
        $servers = @{}
        $config.servers.PSObject.Properties | ForEach-Object { $servers[$_.Name] = $_.Value }
    }
    else {
        $servers = $config.servers
    }
    $serverKeys = $servers.Keys
    if (-not $servers -or -not $serverKeys) {
        return Read-Host "Please specify a server instance"
    }

    if ($serverKeys.Count -eq 1) {
        $selection = $serverKeys[0]
    }
    else {
        $selection = Read-Input -prompt "Please select a server" -options $serverKeys
    }

    return [string]$servers[$selection]
}

function Get-AppFiles {
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$name,
        [Parameter(Position = 1, Mandatory = $true)]
        [string]$folder,
        [string]$version
    )

    if (-not $version) {
        $version = "*"
    }
    $appFilename = "${name}_${version}.app"
    $appFiles = Get-ChildItem -Path $folder -Filter $appFilename -Recurse -File |
    Select-Object -ExpandProperty FullName

    return $appFiles
}

function Get-NewestAppPath {
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        $appFiles,
        [Parameter(Position = 1, Mandatory = $true)]
        [string]$appName
    )

    $mostRecentVersion = $appFiles |
    ForEach-Object { $_.Split("_")[-1].Trim(".app") } |
    ForEach-Object { [version]$_ } |
    Sort-Object -Descending |
    Select-Object -First 1

    $appFilename = "${appName}_${mostRecentVersion}.app"
    return $appFiles | Where-Object { $_ -like "*$appFilename" }
}

function Get-AppPath {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        $app
    )
    $appFiles = Get-AppFiles $app.name $app.folder -version $app.version
    if (-not $appFiles) {
        Write-Error "No application files found in the specified application folder."
    }
    if ($appFiles.Count -eq 1) {
        return $appFiles[0]
    }
    else {
        return Get-NewestAppPath $appFiles $app.name
    }
}

function Get-AppsToInstall {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        $config
    )
    $apps = @()
    if ($config.apps) {
        $config.apps | ForEach-Object { $apps += @{"name" = $_.name; "folder" = $_.folder; "version" = $_.version } }
    }
    else {
        return Read-Host "Please specify the application file path"
    }

    if ($apps.Count -gt 1) {
        $appsToInstall = Select-Apps $apps
    }
    else {
        $appsToInstall = $apps
    }

    return $appsToInstall | ForEach-Object { Get-AppPath $_ }
}

function Get-OrDownloadFile {
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$fileURI,
        [string]$tempFolder = "${PSScriptRoot}\Helper_Temp"
    )

    if ($fileURI -match "^(http|https)://") {
        if (-not (Test-Path -Path $tempFolder)) {
            New-Item -ItemType Directory -Path $tempFolder | Out-Null
        }

        $scriptFilename = $scriptURI.Split("/")[-1]
        $filePath = Join-Path -Path $tempFolder -ChildPath $scriptFilename
        Write-Host "Downloading script from $scriptURI"
        Invoke-WebRequest -Uri $scriptURI -OutFile $filePath
    }
    else {
        if (-not [System.IO.Path]::IsPathRooted($fileURI)) {
            $fileURI = Join-Path $PSScriptRoot $fileURI -Resolve
        }
        $filePath = $fileURI
    }

    if (-not (Test-Path -Path $filePath)) {
        Write-Error "The specified file `"${filePath}`" does not exist."
        Exit
    }

    return $filePath
}

function Remove-TempFiles {
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$tempFolder
    )

    if (Test-Path -Path $tempFolder) {
        Write-Host "Removing temporary files"
        Remove-Item -Path $scriptPath

        if (-not (Get-ChildItem -Path $tempFolder)) {
            Remove-Item -Path $tempFolder
        }
    }
}

# === End of functions ===

$ErrorActionPreference = "Stop"

$tempFolder = "${PSScriptRoot}\Helper_Temp"

# Load the config.json file
$configPath = Get-OrDownloadFile $configURI -tempFolder $tempFolder
$configFile = Get-Content -Path $configPath -Raw

# ConvertFrom-Json -AsHashtable is not available in PowerShell 5
if ($PSVersionTable.PSVersion.Major -le 5) {
    $config = @{}
    (ConvertFrom-Json $configFile).PSObject.Properties | ForEach-Object { $config[$_.Name] = $_.Value }
}
else {
    $config = ConvertFrom-Json -AsHashtable $configFile
}

# Print configuration
Write-Host "Configuration:"
$config | Format-List

$bcVersion = $config["bcVersion"]

# Get the server instance
if (-not $server) {
    $server = Get-Server $config
}

if (-not $appPath) {
    $appsToInstall = Get-AppsToInstall $config
}
else {
    $appsToInstall = $appPath
}

$appsToInstall | ForEach-Object {
    if (-not (Test-Path -Path $_)) {
        Write-Error "The specified application file '$_' does not exist."
    }
}

# Download the install script if necessary
$scriptPath = Get-OrDownloadFile $scriptURI -tempFolder $tempFolder
Write-Host "Script: $scriptPath"
Write-Host "Server: $server"

$parameters = @{
    srvInst   = $server
    ForceSync = $ForceSync
    bcVersion = $bcVersion
    dryRun    = $dryRun
}

# Execute the script
$appsToInstall | ForEach-Object {
    $parameters["appPath"] = $_
    Write-Host "Installing application '$_':"
    Write-Host $scriptPath @parameters
    & $scriptPath @parameters
}

Remove-TempFiles $tempFolder

Write-Host "Installation completed."
