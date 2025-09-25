[CmdletBinding()]
param(
    [string]$AppFolder,
    [array]$AppInfos,
    [string]$ToFindAppId,
    [string]$ToFindName,
    [string]$ToFindPublisher,
    [string]$ToFindVersion
)

function Get-AllNAVAppInfos {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppFolder
    )

    $appFiles = Get-ChildItem -Path $AppFolder -Recurse -Filter "*.app" -File

    $appInfos = @()

    foreach ($appFile in $appFiles) {
        Write-Verbose "- Checking $appFile..."
        $appInfos += Get-NAVAppInfo -Path $appFile.FullName
    }

    return $appInfos
}

function Get-SortedAppList {
    param(
        [Parameter(Mandatory = $true)]
        [array]$AppInfos,
        $ToFindAppInfo
    )

    Set-Variable -Name 'sortedAppInfos' -Value @() -Scope Script -Force
    Set-Variable -Name 'addedAppInfoDict' -Value @{} -Scope Script -Force

    function Get-MatchingAppInfo {
        param(
            [Parameter(Mandatory = $true)]
            [array]$AppInfos,
            [Parameter(Mandatory = $true)]
            $dependencyInfo
        )

        if ($null -eq $AppInfos) {
            return $null
        }

        $filteredAppInfos = $AppInfos

        if ($dependencyInfo.AppId -ne [System.Guid]::Empty) {
            return $filteredAppInfos | Where-Object { $_.AppId.Value.Guid -eq $dependencyInfo.AppId.Guid } | Select-Object -First 1
        }

        if (-not [string]::IsNullOrEmpty($dependencyInfo.Name)) {
            $filteredAppInfos = $filteredAppInfos | Where-Object { $_.Name -eq $dependencyInfo.Name }
        }

        if (-not [string]::IsNullOrEmpty($dependencyInfo.Publisher)) {
            $filteredAppInfos = $filteredAppInfos | Where-Object { $_.Publisher -eq $dependencyInfo.Publisher }
        }

        if ($filteredAppInfos.Count -gt 1) {
            Write-Error "Multiple apps found for dependency: $dependencyInfo"
            return $null
        }

        return $filteredAppInfos | Select-Object -First 1
    }

    function Add-AppInfo {
        param(
            [Parameter(Mandatory = $true)]
            $AppInfo
        )

        Write-Verbose "- Checking app: $($AppInfo.Name) $($AppInfo.Version) ($($AppInfo.AppId.Value.Guid))"

        if ($script:addedAppInfoDict.ContainsKey($AppInfo.AppId.Value.Guid)) {
            Write-Verbose "  Already added, skipping..."
            return
        }
        $script:addedAppInfoDict[$AppInfo.AppId.Value.Guid] = $true

        foreach ($dependency in $AppInfo.Dependencies) {
            Write-Verbose "  Checking dependency: $($dependency.Name) $($dependency.Version) ($($dependency.AppId.Guid))"
            $matchingAppInfo = Get-MatchingAppInfo -AppInfos $AppInfos -dependencyInfo $dependency
            if ($matchingAppInfo) {
                Add-AppInfo -AppInfo $matchingAppInfo
            }
            else {
                Write-Verbose "  Dependency not found, skipping..."
            }
        }

        Write-Verbose "  Adding app: $($AppInfo.Name) $($AppInfo.Version) ($($AppInfo.AppId.Value.Guid))"
        $script:sortedAppInfos += @($AppInfo)
    }

    if ($ToFindAppInfo) {
        Add-AppInfo -AppInfo $ToFindAppInfo
    }
    else {
        foreach ($appInfo in $AppInfos) {
            Add-AppInfo -AppInfo $appInfo
        }
    }

    return $script:sortedAppInfos
}

$ErrorActionPreference = "Stop"

if ($AppInfos -and $AppFolder) {
    Write-Error "Cannot specify both AppFolder and AppInfos."
}

if ($AppFolder) {
    if (-not (Test-Path $AppFolder)) {
        Write-Error "App folder not found: $AppFolder"
    }

    Write-HostTimed "Finding apps in $AppFolder..."
    $AppInfos = Get-AllNAVAppInfos -AppFolder $AppFolder
}

if (-not $AppInfos) {
    return @()
}

Write-Verbose "All apps:`n$($AppInfos | Format-Table AppId, Name, Publisher, Version | Out-String)"

if ($ToFindAppId -or $ToFindName -or $ToFindPublisher -or $ToFindVersion) {
    Write-Verbose "Name: $ToFindName ($(-not $ToFindName)), Publisher: $ToFindPublisher ($(-not $ToFindPublisher)), Version: $ToFindVersion ($(-not $ToFindVersion)), AppId: $ToFindAppId ($(-not $ToFindAppId))"
    $ToFindAppInfo = $AppInfos | Where-Object {
        (-not $ToFindAppId -or $_.AppId.Value.Guid -eq $ToFindAppId) -and
        (-not $ToFindName -or $_.Name -eq $ToFindName) -and
        (-not $ToFindPublisher -or $_.Publisher -eq $ToFindPublisher) -and
        (-not $ToFindVersion -or $_.Version.ToString() -eq $ToFindVersion)
    }

    if ($null -eq $ToFindAppInfo) {
        Write-Error "App not found: $ToFindName $ToFindVersion $ToFindAppId"
    }

    Write-HostTimed "Building dependency list for $($ToFindAppInfo.Name) $($ToFindAppInfo.Version) ($($ToFindAppInfo.AppId.Value.Guid))..."
}
else {
    Write-HostTimed "Sorting all apps by dependencies..."
}
$finalAppInfos = Get-SortedAppList -AppInfos $AppInfos -ToFindAppInfo $ToFindAppInfo
Write-Verbose "Sorted apps:`n$($finalAppInfos | Format-Table AppId, Name, Publisher, Version | Out-String)"

$finalAppInfos