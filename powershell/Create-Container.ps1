Param(
    [string] $containerName = 'bcserver',
    [string] $version,
    [string] $auth = 'UserPassword',
    [string] $licensePath,
    [string] $shortCutPath = (Join-Path [Environment]::GetFolderPath("Desktop") $containerName),
    [boolean] $includeTestToolkit
)

## === Get admin permissions

Check-BcContainerHelperPermissions -Fix

## === Build parameters

$params = @{
    "country" = 'at'
    'select' = 'Latest'
    'type' = 'onprem'
}

if ([string]::IsNullOrEmpty($version)) {
    params += @{ 'version' = $version }
}

## === Fetch artifact URL

Write-Host Get URL ArtiFact ...
$artifactUrl = Get-BCArtifactUrl @params
Write-Host Artifact URL = $artifactUrl -ForegroundColor DarkYellow

## === Build parameters

$params = @{
    "accept_eula" = $true
    "artifactUrl" = $artifactUrl
    "auth" = $auth
    "updateHosts" = $true
    'includeTestToolkit' = $includeTestToolkit
}

if ([string]::IsNullOrEmpty($containerName)) {
    $params += @{ "containerName" = $containerName }
}
if ([string]::IsNullOrEmpty($licensePath)) {
    $params += @{ "licenseFile" = $licensePath }
}
if ([string]::IsNullOrEmpty($shortcutPath)) {
    $params += @{ "shortcuts" = $shortcutPath }
}

## === Create Container

Write-Host Creating Container ...

New-BCContainer @params
