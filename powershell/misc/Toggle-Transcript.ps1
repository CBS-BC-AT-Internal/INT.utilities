param (
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$LogFolder = "D:\Install\Upgrade\logs\"
)

function Get-LogFileName {
    param (
        [string]$LogFolder
    )

    $logFileName = "Upgrade_" + (Get-Date -Format "yyyyMMdd") + ".log"
    return Join-Path -Path $LogFolder -ChildPath $logFileName
}

function Get-LogFile {
    param (
        [string]$LogFolder
    )
    # Ensure the log folder is an absolute path
    if (-not [System.IO.Path]::IsPathRooted($LogFolder)) {
        $LogFolder = Join-Path -Path $PSScriptRoot -ChildPath $LogFolder
    }

    # Ensure the log folder exists
    if (-not (Test-Path -Path $LogFolder)) {
        New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
    }

    $LogFile = Get-LogFileName -LogFolder $LogFolder
    # Ensure the log file exists
    if (-not (Test-Path $LogFile)) {
        New-Item -ItemType File -Path $LogFile -Force | Out-Null
    }

    return $LogFile
}

$LogFile = Get-LogFile -LogFolder $LogFolder

try {
    Start-Transcript -Path $LogFile -Append
}
catch [System.InvalidOperationException] {
    Stop-Transcript
}
