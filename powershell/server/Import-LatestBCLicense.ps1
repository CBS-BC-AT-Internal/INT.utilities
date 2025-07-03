param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$serverInstance,
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$licensePath,
    [ValidateSet("bclicense", "flf")]
    [string]$licenseType,
    [ValidateSet("Default", "Master", "NAVDatabase", "Tenant")]
    [string]$database = "Default",
    [switch]$restart,
    [switch]$DryRun,
    [switch]$Force
)

function Get-LicenseTypes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$serverInstance,
        [string]$licenseType
    )

    function Get-SupportedLicenseTypes {
        param(
            [Parameter(Mandatory = $true, Position = 0)]
            [string]$serverInstance
        )

        # Use Where-Object instead of -ServerInstance to support all versions
        $version = Get-NAVServerInstance | Where-Object { $_.ServerInstance -eq "MicrosoftDynamicsNavServer`$$ServerInstance" } | Select-Object -ExpandProperty Version
        $allowAll = $false
        if (($version -eq 0) -or ($null -eq $version)) {
            $allowAll = $true
            Write-Warning "Failed to determine version of server instance $serverInstance"
        }
        Write-Verbose "Server instance $serverInstance is version $version"
        $major = $version.Split(".")[0]
        $supportedLicenseTypes = @()
        if ($allowAll -or $major -lt 22) {
            $supportedLicenseTypes += @("flf")
        }
        if ($allowAll -or $major -gt 17) {
            $supportedLicenseTypes += @("bclicense")
        }

        return $supportedLicenseTypes
    }

    $supportedLicenseTypes = Get-SupportedLicenseTypes $serverInstance
    if ($licenseType) {
        if ($supportedLicenseTypes -notcontains $licenseType) {
            throw "License type $licenseType is not supported for server instance $serverInstance"
        }
        return @($licenseType)
    }
    else {
        return $supportedLicenseTypes
    }
}

function Get-NewestLicensePath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$licensePath,
        [string]$serverInstance,
        [Parameter(Mandatory = $true)]
        [string]$licenseTypes
    )

    if (Test-Path $licensePath -PathType Container) {
        $licensePaths = $licenseTypes | ForEach-Object { Join-Path $licensePath "*.$_" }
        Write-HostTimed "Looking for license files..."
    }
    elseif (Test-Path $licensePath -PathType Leaf) {
        Write-Verbose "License file specified: $licensePath"
        $fileExtension = [System.IO.Path]::GetExtension($licensePath).TrimStart(".")
        if ($licenseTypes -contains $fileExtension) {
            $licensePaths = @($licensePath)
        }
        else {
            $errorMsg = "License type $fileExtension is not supported for server instance"
            if ($serverInstance) {
                $errorMsg += " $serverInstance"
            }
            $errorMsg += "."
            throw $errorMsg
        }
    }
    else {
        throw "Path $licensePath not found"
    }

    Write-Verbose "License paths:`n$($licensePaths | Format-List | Out-String)"
    $licenseFiles = Get-Item -Path $licensePaths | Sort-Object -Property LastWriteTime -Descending
    Write-Verbose "License files found:`n$($licenseFiles.FullName | Format-List | Out-String)"
    $licenseFile = $licenseFiles | Select-Object -First 1
    if ($null -eq $licenseFile) {
        throw "No valid license file found under $licensePath"
    }
    else {
        return $licenseFile.FullName
    }
}

$ErrorActionPreference = "Stop"
if ($DryRun) {
    Write-HostTimed "Dry run mode enabled. No changes will be made." -ForegroundColor Yellow
}

Write-HostTimed "Determining supported license types for server instance $serverInstance..."
$licenseTypes = Get-LicenseTypes -serverInstance $serverInstance -licenseType $licenseType
Write-Verbose "License type(s) to select: $($licenseTypes -join ", ")"

$licenseFilePath = Get-NewestLicensePath -licensePath $licensePath -serverInstance $serverInstance -licenseTypes $licenseTypes
Write-HostTimed "Using $licenseFilePath"

if (-not $Force) {
    while ($true) {
        $response = Read-Host "Importing license file $licenseFilePath to server instance $serverInstance. Continue? [y/n]"

        if ($response -match '^[yY]$') {
            break
        }
        elseif ($response -match '^[nN]$') {
            exit
        }
    }
}

Write-HostTimed "Connecting to server instance $serverInstance..."
$serverInfo = Get-NAVServerInstance -ServerInstance $serverInstance
if ($null -eq $serverInfo) {
    Write-HostTimed "Server instance $serverInstance not found" -ForegroundColor Red
    exit
}

if ($serverInfo.State -ne "Running") {
    if (-not $Force) {
        while ($true) {
            $response = Read-Host "Server instance $serverInstance is not running. Start server instance and continue? [y/n]"

            if ($response -match '^[yY]$') {
                break
            }
            elseif ($response -match '^[nN]$') {
                exit
            }
        }
    }

    Write-HostTimed "Starting server instance..." -ForegroundColor Yellow
    Write-Verbose "Start-NAVServerInstance -ServerInstance $serverInstance"
    if (-not $DryRun) {
        Start-NAVServerInstance -ServerInstance $serverInstance | Out-Null
    }
}

$params = @{
    ServerInstance = $serverInstance
    LicenseFile    = $licenseFilePath
    Database       = $database
}
$paramString = Get-ParameterString $params
Write-HostTimed "Importing license file $licenseFilePath to server instance $serverInstance..."
Write-Verbose "Import-NAVServerLicense $paramString"
if (-not $DryRun) {
    Import-NAVServerLicense @params | Out-Null
}

if ($restart) {
    $params = @{
        ServerInstance = $serverInstance
    }
    $paramString = Get-ParameterString $params
    Write-HostTimed "Restarting server instance $serverInstance..."
    Write-Verbose "Restart-NAVServerInstance $paramString"
    if (-not $DryRun) {
        Restart-NAVServerInstance @params | Out-Null
    }
}

Write-HostTimed "License file successfully imported." -ForegroundColor Green
