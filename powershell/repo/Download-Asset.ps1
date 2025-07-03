[CmdletBinding()]
Param(
    [Parameter(Position = 0)]
    [string]$ConfigPath = ".\config\default.repo.json",
    [Parameter(Position = 1)]
    [string]$Repository,
    [Parameter(Position = 2)]
    [string]$DownloadPath = ".",
    [string]$Token,
    [string]$version
)

if ($ConfigPath -and (Test-Path $ConfigPath)) {
    try {
        if (Test-Path $ConfigPath -PathType Container) {
            if ($Repository) {
                Write-Error "ConfigPath is a directory, but Repository is provided. Please provide either a config file or remove the Repository parameter."
                exit 1
            }
            Write-Verbose "ConfigPath is a directory. Iterating through *.repo.json files."
            $ConfigFiles = Get-ChildItem -Path $ConfigPath -Filter "*.repo.json"
            $downloadedFiles = @()
            foreach ($ConfigFile in $ConfigFiles) {
                $Config = Get-Content $ConfigFile.FullName | ConvertFrom-Json
                $params = $PSBoundParameters
                $params.ConfigPath = $ConfigFile.FullName
                try {
                    $downloadedFiles += & $MyInvocation.MyCommand.Path @params
                }
                catch {
                    Write-Warning "Failed to process config file ${ConfigFile.FullName}: $_"
                }
            }
            Write-Host "$($downloadedFiles.Count) assets have been downloaded across $($ConfigFiles.Count) config files."
            return $downloadedFiles
        } else {
            Write-Verbose "Reading config file ${ConfigPath}"
            $Config = Get-Content $ConfigPath | ConvertFrom-Json
            Write-Host "Using config file ${ConfigPath}"
        }
    }
    catch {
        Write-Error "Failed to read config file(s) in ${ConfigPath}: $_"
        exit 1
    }
}
if (-not $Token) {
    if ($Config) {
        $Token = $Config.token

        if (-not $Token) {
            Write-Error "Property 'token' not found in config file ${ConfigPath}"
            exit 1
        }

        Write-Host "Using token from config file"
    }
    else {
        Write-Verbose "Token not provided. Proceeding without authentication."
    }
}
elseif (Test-Path $Token -PathType Leaf) {
    try {
        $Token = Get-Content $Token -Raw
        $Token = $Token.Trim()
    } catch {
        Write-Error "Failed to read token file ${Token}: $_"
        exit 1
    }
}

if(-not $Repository) {
    if ($Config) {
        $owner = $Config.owner
        $repo = $Config.repository

        if (-not $owner) {
            Write-Error "Property 'owner' not found in config file ${ConfigPath}"
            exit 1
        }
        elseif ( $owner -match '[\/\s]') {
            Write-Error "Invalid owner name ${owner}. Owner name cannot contain '/' or whitespace."
            exit 1
        }

        if (-not $repo) {
            Write-Error "Property 'repository' not found in config file ${ConfigPath}"
            exit 1
        }
        elseif ( $repo -match '[\/\s]') {
            Write-Error "Invalid repo name ${repo}. Repo name cannot contain '/' or whitespace."
            exit 1
        }

        $Repository = "${owner}/${repo}"

        Write-Host "Using repository ${Repository}"
    }
    else {
        Write-Error "Repository not provided."
        exit 1
    }
}
elseif ($Repository -notmatch "^([^\s/]+)\/([^\s/]+?)$") {
    Write-Error "Invalid repository name ${Repository}. Expected format: owner/repo"
    exit 1
}

if (-not $Version) {
    if ($Config) {
        $Version = $Config.release

        if (-not $Version) {
            Write-Error "Property 'release' not found in config file ${ConfigPath}"
            exit 1
        }

        Write-Host "Using version from config file"
    }
    else {
        $Version = "latest"
        Write-Verbose "Version not provided. Downloading the latest release."
    }
}

# Set API URLs
$BaseUrl = "https://api.github.com/repos/$Repository"
$LatestReleaseUrl = "${BaseUrl}/releases/${Version}"

# Set headers for authentication
$Headers = @{
    Accept        = "application/vnd.github+json"
    "User-Agent"    = "PowerShell-Script"
    "X-GitHub-Api-Version" = "2022-11-28"
}

if ($Token) {
    $Headers.Authorization = "Bearer $Token"
}

# Get the latest release data
try {
    if ($Version -eq 'latest') {
        Write-Host "Fetching the latest release..."
    }
    else {
        Write-Host "Fetching release ${Version}..."
    }
    $LatestRelease = Invoke-RestMethod -Uri $LatestReleaseUrl -Headers $Headers -Method Get
} catch {
    Write-Error "Failed to fetch release:`n$_"
    exit
}

# Extract assets
$Assets = $LatestRelease.assets
if ($Assets.Count -eq 0) {
    Write-Output "No assets found."
    exit
}

# Ensure download directory exists
$DownloadPath = Convert-Path $DownloadPath
if (!(Test-Path -Path $DownloadPath)) {
    New-Item -ItemType Directory -Path $DownloadPath | Out-Null
}
$DownloadPath = Join-Path -Path $DownloadPath -ChildPath $Repository
if (!(Test-Path -Path $DownloadPath)) {
    New-Item -ItemType Directory -Path $DownloadPath | Out-Null
}

$downloadedFiles = @()

# Download each asset
foreach ($Asset in $Assets) {
    $AssetUrl = "${BaseUrl}/releases/assets/$($Asset.id)"
    $FileName = $Asset.name
    $FilePath = Join-Path -Path $DownloadPath -ChildPath $FileName

    Write-Host "Downloading $FileName..."

    try {
        $WebClient = New-Object System.Net.WebClient
        $WebClient.Headers.Add("User-Agent", "PowerShell-Script")
        $WebClient.Headers.Add("Accept", "application/octet-stream")
        $WebClient.Headers.Add("X-GitHub-Api-Version", "2022-11-28")
        if ($Token) {
            $WebClient.Headers.Add("Authorization", "Bearer $Token")
        }
        $WebClient.DownloadFile($AssetUrl, $FilePath)
        $downloadedFiles += $FilePath
        Write-Host "Saved to $DownloadPath"
    } catch {
        Write-Error "Failed to download ${FileName}: $_"
    }
}

switch ($downloadedFiles.Count) {
    0 { Write-Host "No assets have been downloaded." }
    1 { Write-Host "1 asset has been downloaded." }
    default { Write-Host "$($downloadedFiles.Count) assets have been downloaded." }
}

return $downloadedFiles
