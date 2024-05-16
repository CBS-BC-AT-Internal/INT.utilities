param(
  [Parameter(Mandatory = $true)]
  [string]$serverInstance,
  [Parameter(Mandatory = $true)]
  [string]$licensePath
)

function Get-LatestLicenseFile() {
  param(
    [Parameter(Mandatory = $true)]
    $licenseFiles
  )
  if (-not $licenseFiles) {
    Write-Host "No license files found in '$licensePath'."
    exit 1
  }
  if ($licenseFiles.Count -eq 1) {
    return $licenseFiles[0].FullName
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
  }
  return $latestFile
}

if (-not (Test-Path -Path $licensePath)) {
  Write-Host "License folder '$licensePath' does not exist."
  exit 1
}

$licenseFiles = Get-ChildItem -Path $licensePath | Where-Object { $_.Name -match '^[^_]*_BC\d{2}_[^_]*_Expires_\d{4}-\d{2}-\d{2}\.flf$' }
$latestFile = Get-LatestLicenseFile -licenseFiles $licenseFiles

Write-Host "Latest license file: $latestFile"

Import-NAVServerLicense -ServerInstance $serverInstance -LicenseFile $latestFile
Restart-NAVServerInstance -ServerInstance $serverInstance
