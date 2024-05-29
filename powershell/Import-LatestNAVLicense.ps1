param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$serverInstance,
  [Parameter(Mandatory = $false)]
  [ValidateSet('flf', 'bclicense', '(flf|bclicense)')]
  [string]$fileEnding = '(flf|bclicense)',
  [Parameter(Mandatory = $true, Position = 1)]
  [ValidateScript(
    {
      $pattern = '.*\.' + $fileEnding
      (Test-Path -Path $_ -PathType 'Container') -or
      (
        (
          (Test-Path -Path $_ -PathType 'Leaf') -or
          ($_ -match '^https?://')
        ) -and
        ($_ -match $pattern)
      )
    }
  )]
  [string]$licensePath,
  [Parameter(Mandatory = $false)]
  [string]$bcVersion,
  [Parameter(Mandatory = $false)]
  [string]$modulePath,
  [Parameter(Mandatory = $false)]
  [bool]$runAsJob = $false
)

enum PathType {
  Container
  File
  URL
}

function Initialize-Modules() {
  param(
    [Parameter(Mandatory = $true)]
    [string] $bcVersion,
    [ValidateScript({ if (![string]::IsNullOrEmpty($_)) { Test-Path $_ -PathType Leaf } else { $true } })]
    [Parameter(Mandatory = $true)]
    [string] $modulePath,
    [Parameter(Mandatory = $true)]
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

function DeterminePathType() {
  param(
    [Parameter(Mandatory = $true)]
    [string]$path,
    [Parameter(Mandatory = $true)]
    [string]$fileEnding
  )
  $pattern = '.*\.' + $fileEnding
  if ($path -match $pattern) {
    if ($path -match '^https?://') {
      return [PathType]::URL
    }
    else {
      return [PathType]::File
    }
  }
  return [PathType]::Container
}

function DownloadLicenseFile() {
  param(
    [Parameter(Mandatory = $true)]
    [string]$licensePath,
    [string]$outputPath = "$PWD/_temp"
  )
  $licenseFileName = $licensePath.Substring($licensePath.LastIndexOf('/') + 1)
  $licenseFilePath = Join-Path -Path $outputPath -ChildPath $licenseFileName
  Invoke-WebRequest -Uri $licensePath -OutFile $licenseFilePath
  Write-Host "Downloaded license file to '$licenseFilePath'."
  return Get-Item -Path $licenseFilePath
}

function GetLicenseFiles() {
  param(
    [Parameter(Mandatory = $true)]
    $licensePath,
    [Parameter(Mandatory = $true)]
    [string]$fileEnding
  )
  [PathType]$pathType = DeterminePathType -path $licensePath -fileEnding $fileEnding
  switch ($pathType) {
    "File" {
      return Get-Item -Path $licensePath
    }
    "Container" {
      $pattern = '^[^_]*_BC\d{2}_[^_]*_Expires_\d{4}-\d{2}-\d{2}\.' + $fileEnding + '$'
      return Get-ChildItem -Path $licensePath | Where-Object {
        $_.Name -match $pattern
      }
    }
    "URL" {
      return DownloadLicenseFile -licensePath $licensePath
    }
  }
}

function GetLatestLicenseFile() {
  param(
    [Parameter(Mandatory = $true)]
    $licenseFiles
  )
  if (-not $licenseFiles) {
    Write-Host "No license files found in '$licensePath'."
    exit 1
  }
  if ($licenseFiles.Count -eq 1) {
    $latestFile = $licenseFiles[0].FullName
  }
  else {
    $latestExpiryDate = $null
    $latestFile = $null
    $licenseFiles | ForEach-Object {
      $licenseFileName = $_.Name
      $expiryDate = $licenseFileName.Substring($licenseFileName.LastIndexOf('_') + 1)
      if (-not $latestExpiryDate -or $expiryDate -gt $latestExpiryDate) {
        $latestExpiryDate = $expiryDate
        $latestFile = $_.FullName
      }
    }
    Write-Host "Latest license file: $latestFile"
  }
  return $latestFile
}

$ErrorActionPreference = 'Stop'

$licenseFiles = GetLicenseFiles -licensePath $licensePath -fileEnding $fileEnding
$latestFile = GetLatestLicenseFile -licenseFiles $licenseFiles

Initialize-Modules -runAsJob:$runAsJob -bcVersion $bcVersion -modulePath $modulePath
Write-Host "Importing license file '$latestFile' to '$serverInstance'..."
Import-NAVServerLicense -ServerInstance $serverInstance -LicenseFile $latestFile

if ((DeterminePathType -path $licensePath -fileEnding $fileEnding) -eq "URL") {
  Remove-Item -Path $latestFile
  if ((Get-ChildItem -Path (Split-Path -Path $latestFile) | Measure-Object).Count -eq 0) {
    Remove-Item -Path (Split-Path -Path $latestFile)
  }
}
