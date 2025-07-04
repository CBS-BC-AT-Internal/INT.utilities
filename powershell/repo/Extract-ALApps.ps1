[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$ConfigPath = ".\config\default.repo.json",
    [Parameter(Position = 1)]
    [string]$Repository,
    [Parameter(Position = 2)]
    [string]$Destination,
    [string]$Token,
    [string]$version,
    [string]$downloadScriptPath = "./Download-Asset.ps1"
)

if (-not (Get-Module -Name HelperFunctions -ErrorAction SilentlyContinue)) {
    try {
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath ".\..\modules\HelperFunctions.psm1"
        Import-Module -Name $modulePath
    } catch {
        Write-Error "Failed to import HelperFunctions module. Ensure the module is available."
        exit 1
    }
}

# Check if downloadScriptPath is a relative path and convert it to an absolute path
if (-not (Test-Path $downloadScriptPath -PathType Leaf)) {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath $downloadScriptPath
    if (-not (Test-Path $scriptPath -PathType Leaf)) {
        Write-Error "Download script not found at path: $scriptPath"
        exit 1
    }
} else {
    $scriptPath = $downloadScriptPath
}

$downloadPath = "${env:TEMP}\GitHubAssets"
Write-Verbose "Download path: $downloadPath"
if (-not (Test-Path $downloadPath -PathType Container)) {
    New-Item -Path $downloadPath -ItemType Directory | Out-Null
}

$downloadParams = @{
    ConfigPath = $ConfigPath
    Repository = $Repository
    Token = $Token
    DownloadPath = $downloadPath
    version = $version
}
$paramString = Get-ParameterString $downloadParams
Write-Verbose "& $scriptPath $paramString"
$assetPaths = & $scriptPath @downloadParams

if (-not $assetPaths) {
    Write-Warning "No assets found to download."
    exit 0
}

$appAssetPaths = $assetPaths | Where-Object { $_ -cmatch "-Apps-\d+\.\d+\.\d+\.\d+\.zip$" }

if (-not $appAssetPaths) {
    Write-Warning "No app asset paths found in the downloaded assets."
    exit 0
}

Write-Host "Extracting app assets to $Destination..."
$appAssetPaths | ForEach-Object {
    $assetPath = $_
    try {
        Write-Verbose "Extracting archive ${assetPath} ($($assetPath.GetType().FullName)) to ${Destination}"
        Expand-Archive -Path $assetPath -DestinationPath $Destination -Force
    } catch {
        Write-Warning "Failed to extract archive ${assetPath}: $_"
    }
}

Write-Host "App assets extracted to $Destination." -ForegroundColor Green
