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
    "https://raw.githubusercontent.com/CBS-BC-AT-Internal/INT.utilities/main/powershell/Install-NAVApp.ps1".

.PARAMETER ForceSync
    Switch parameter to force synchronization during the update process.

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
    [string]$scriptURI = "https://raw.githubusercontent.com/CBS-BC-AT-Internal/INT.utilities/v0.2.0/powershell/Install-NAVApp.ps1",
    [switch]$ForceSync
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

function Get-ConfigValue {
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$key,
        [string]$prompt = $key
    )

    if ($config.$key) {
        return $config.$key
    }

    return Read-Input -prompt $prompt
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
        $filePath = [System.IO.Path]::GetFullPath($fileURI)
    }

    if (-not (Test-Path -Path $filePath)) {
        Write-Error "The specified file `"${filePath}`" does not exist."
        Exit
    }

    return $filePath
}

$tempFolder = "${PSScriptRoot}\Helper_Temp"

# Load the config.json file
$configPath = Get-OrDownloadFile -fileURI $configURI -tempFolder $tempFolder
$config = Get-Content -Path $configPath | ConvertFrom-Json -AsHashtable

# Get the app folder path
if (-not $appFolder) {
    $appFolder = Get-ConfigValue "appFolder"
}

# Get the name of the app
if (-not $appName) {
    $appName = Get-ConfigValue "appName"
}

# Get the server instance
if (-not $server) {
    $servers = $config.servers
    $serverKeys = $servers.Keys
    if (-not $servers -or -not $serverKeys) {
        Write-Error "JSON object `"servers`" must have at least one child."
        Exit
    }

    if ($serverKeys.Count -eq 1) {
        $selection = $serverKeys[0]
    }
    else {
        $selection = Read-Input -prompt "Please select a server" -options $serverKeys
    }

    $server = $servers.$selection
}

# Get the application file path
if (-not $appPath) {
    $appFilename = "${appName}_${appVersion}.app"
    $appFiles = Get-ChildItem -Path $appFolder -Filter $appFilename -Recurse |
    Select-Object -ExpandProperty FullName

    if (-not $appFiles) {
        Write-Error "No application files found in the specified application folder."
        Exit
    }

    # Get the highest version number
    $mostRecentVersion = $appFiles |
    ForEach-Object { $_.Split("_")[-1].Trim(".app") } |
    ForEach-Object { [version]$_ } |
    Sort-Object -Descending |
    Select-Object -First 1

    $appFilename = "${appName}_${mostRecentVersion}.app"
    $appPath = $appFiles | Where-Object { $_ -like "*$mostRecentVersion*" }
}
else {
    if (-not (Test-Path -Path $appPath)) {
        Write-Error "The specified application file does not exist."
        Exit
    }
}

# Download the install script if necessary
$scriptPath = Get-OrDownloadFile -fileURI $scriptURI -tempFolder $tempFolder

Write-Host "Server: $server"
Write-Host "Application: $appPath"
Write-Host "Script: $scriptPath"

# Execute the script
& $scriptPath $server -appPath $appPath -ForceSync:$ForceSync

# Remove the temporary files
if (Test-Path -Path $tempFolder) {
    Write-Host "Removing temporary files"
    Remove-Item -Path $scriptPath

    if (-not (Get-ChildItem -Path $tempFolder)) {
        Remove-Item -Path $tempFolder
    }
}

Write-Host "Done"
