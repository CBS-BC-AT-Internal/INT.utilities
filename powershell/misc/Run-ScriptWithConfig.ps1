[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position=0)]
    [string]$scriptPath,
    [Parameter(Position=1)]
    [string]$configPath = './config/scripts',
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Test-AndRootPath {
    param (
        [Parameter(Mandatory = $true, Position=0)]
        [string]$Path
    )

    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path $PWD $Path
    }

    Test-Path $Path -ErrorAction Stop | Out-Null

    return $Path
}

$scriptPath = Test-AndRootPath $scriptPath
Write-Verbose "Script path: $scriptPath"
$configPath = Test-AndRootPath $configPath
Write-Verbose "Config path: $configPath"

# Check if $configPath is a directory
if ((Get-Item $configPath).PSIsContainer) {
    Write-Verbose "Config path is a directory, looking for config file"
    $FileName = "$((Get-Item $scriptPath).Name).json"
    $configPath = Join-Path $configPath $FileName
    if (-not (Test-Path $configPath)) {
        throw "Config file not found: $configPath"
    }
}

$configJson = Get-Content $configPath | ConvertFrom-Json

$scriptParams = @{}
foreach ($key in $configJson.PSObject.Properties) {
    $scriptParams += @{ $key.Name = $key.Value }
}

if ($DryRun) {
    $scriptParams += @{ DryRun = $true }
}
if ($Force) {
    $scriptParams += @{ Force = $true }
}

Write-Verbose "Script parameters:`n$($scriptParams | Format-List | Out-String)"

& $scriptPath @scriptParams
