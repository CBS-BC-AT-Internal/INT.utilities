function Get-ReadableValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $Value
    )

    if (-not $value) {
        return
    }

    switch ($true) {
        ($value -is [string]) { "'$value'" }
        ($value -is [array]) { "@($($value -join ','))" }
        default { "$value" }
    }
}

function Get-ParameterString {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Params
    )

    return ($params.GetEnumerator() | ForEach-Object {
        $key = $_.Key
        $value = $_.Value

        if (-not $value) {
            return
        }

        switch ($true) {
            ($value -is [bool]) { "-$key" }
            ($value -is [System.Management.Automation.SwitchParameter]) { "-$key" }
            default {
                $readableValue = Get-ReadableValue -Value $value
                "-$key $readableValue"
            }
        }
    } | Where-Object { $_ }) -join " "
}

function ConvertTo-Hashtable2 {
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        $object
    )

    if ($object -is [hashtable]) {
        return $object
    }

    [hashtable]$output = @{ }

    if ($object -is [System.Management.Automation.PSObject]) {
        foreach ($key in $object.PSObject.Properties.Name) {
            $output[$key] = $object.$key
        }
    }

    return $output
}

function Get-FilteredParameters {
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [hashtable] $params
    )

    [hashtable]$filteredParams = @{}

    $params.GetEnumerator() | ForEach-Object {
        $name = $_.Name
        $value = $_.Value

        switch ($true) {
            { $null -eq $value } { continue }
            { $value -is [string] } { if (-not [string]::IsNullOrWhiteSpace($value)) { $filteredParams[$name] = $value } }
            { $value -is [bool] } { if ($value) { $filteredParams[$name] = $value } }
            default { $filteredParams[$name] = $value }
        }
    }

    return $filteredParams
}

function Write-HostTimed {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Text')]
        [string]$Message,

        [Parameter(Position = 1)]
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Gray
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formattedMessage = "[$timestamp] $Message"
    Write-Host -Object $formattedMessage -ForegroundColor $ForegroundColor
}

function Write-ElapsedTime {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [datetime]$startTime,
        [string]$command = "Command",
        [switch]$Silent
    )
    $endTime = Get-Date
    $elapsedTime = $endTime - $startTime
    $minutes = [math]::Floor($elapsedTime.TotalMinutes)
    $seconds = $elapsedTime.Seconds
    if (-not $Silent) {
        Write-HostTimed "$command took $minutes minutes and $seconds seconds." -ForegroundColor DarkGray
    }

    Write-Information (New-Object PSObject -Property @{
            Command     = $command
            StartTime   = $startTime
            EndTime     = $endTime
            ElapsedTime = $elapsedTime
        }) -Tags 'ElapsedTime'
}

function Read-BackupConfirmFromServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ServerInstance
    )

    $databaseName = Get-NAVServerConfiguration -ServerInstance $ServerInstance -KeyName "DatabaseName"

    while ($true) {
        $response = Read-Host "Before continuing, ensure that the database '$databaseName' is backed up. Press 'y' to continue or 'n' to cancel."

        if ($response -match '^[yY]$') {
            break
        }
        elseif ($response -match '^[nN]$') {
            exit
        }
    }
}

function Get-PrettyAppInfo {
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        $AppInfos,
        [switch]$bullet
    )

    foreach ($AppInfo in $AppInfos) {
        $buffer = ""
        if ($bullet) {
            $buffer += "- "
        }
        $buffer += "'$($AppInfo.Name)' $($AppInfo.Version) ($($AppInfo.AppId.ToString()))"
        Write-Output $buffer
    }
}

function Import-Configuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$configPath,
        [string]$outConfigPath = ($configPath -replace "\.json$", ".output.json")
    )

    function Get-HashtableFromJSONFile {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)]
            [string]$jsonPath
        )

        $json = Get-Content $jsonPath -ErrorAction Stop | ConvertFrom-Json

        if (-not $json) {
            throw "Failed to load JSON from $jsonPath."
        }

        return ConvertTo-Hashtable2 -object $json
    }

    if (-not $configPath -or -not (Test-Path -Path $configPath)) {
        throw "Configuration file not found at $configPath."
    }
    if ($configPath -notlike "*.json") {
        throw "Configuration must be a JSON file."
    }
    $config = Get-HashtableFromJSONFile -jsonPath $configPath

    try {
        $outputConfig = Get-HashtableFromJSONFile -jsonPath $outConfigPath
    }
    catch {
        Write-Verbose "Failed to load additional configuration from $outConfigPath. Using empty configuration."
        $outputConfig = @{ }
    }
    if ($outputConfig.Count -gt 0) {
        Write-Verbose "Additional configuration loaded from $outConfigPath"
    }
    else {
        Write-Verbose "No additional configuration found at $outConfigPath"
    }

    return @{ Config = $config; OutputConfig = $outputConfig }
}

function Get-CustomApps {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        $customApps
    )

    # Undefined or empty customApps
    if (-not $customApps) {
        return @()
    }

    # CustomApps is already an array
    if ($customApps -is [array]) {
        return $customApps
    }

    # CustomApps isn't a string
    if ($customApps -isnot [string]) {
        throw "CustomApps must be a string or string array."
    }

    # CustomApps is a comma-separated string
    if ($customApps -like "*,*") {
        return $customApps -split ","
    }

    # CustomApps is a valid path to a JSON file
    if (-not (Test-Path $customApps)) {
        throw "The path to the configuration file '$customApps' does not exist. If you want to specify multiple apps, separate them with a comma."
    }

    $result = Import-Configuration -configPath $customApps

    $customApps = @()

    $customApps += [array]$result.Config.Apps
    if ($result.OutputConfig.Apps) {
        $customApps += [array]$result.OutputConfig.Apps
    }
    Write-Verbose "Found $($customApps.Count) custom apps."

    return $customApps
}

function Invoke-GetNAVAppGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppFolder,
        $MigrationAppId,
        $CustomApps,
        [switch]$SkipDependencySort,
        [switch]$AllowMissingSortScript,
        [switch]$AllowMissingCustomApps,
        [string]$appGroupScript = (Join-Path $PSScriptRoot "..\app\Get-NAVAppGroups.ps1"),
        [switch]$Force
    )

    if (-not (Test-Path $appGroupScript -PathType Leaf)) {
        Write-Error "Unable to retrieve apps to publish due to missing script '$appGroupScript'. Ensure the script exists."
    }
    return & $appGroupScript @PSBoundParameters
}

function Get-SortedAppInfos {
    [CmdletBinding()]
    param (
        $AppGroups,
        [string[]]$sortingOrder,
        [switch]$AddUnspecifiedApps
    )

    function Get-VersionFromObject {
        param(
            [Parameter(Mandatory = $true, Position = 0)]
            $version
        )

        if ($null -eq $version) {
            throw "Version object cannot be null."
        }
        elseif ($version -is [version]) {
            return $version
        }
        elseif ($version -is [string]) {
            return [version]$version
        }
        elseif ($version -is [System.Management.Automation.PSObject]) {
            try {
                $values = @($version.Major, $version.Minor, $version.Build, $version.Revision)
                if ($values -contains $null) {
                    throw "Version object must have properties Major, Minor, Build and Revision."
                }
                return [version]::new($version.Major, $version.Minor, $version.Build, $version.Revision)
            }
            catch {
                throw "Unable to convert object to version. $($_.Exception.Message)"
            }
        }

        throw "Unable to convert object to version."
    }

    function Get-GuidFromObject {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true, Position = 0)]
            $guid
        )

        if ($null -eq $guid) {
            throw "GUID object cannot be null."
        }
        try {
            return [guid]$guid
        }
        catch {
            # Invalid GUID, throw error
            if ($guid -is [string]) {
                [guid]$guid
            }
            try {
                [guid]$guid.Value
            }
            catch {
                throw "Unable to convert object to GUID. $($_.Exception.Message)"
            }
        }
    }

    function Get-AppInfosWithTyping {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true, Position = 0)]
            $AppInfos
        )

        foreach ($AppInfo in $AppInfos) {
            $AppInfo.Version = Get-VersionFromObject $AppInfo.Version
            $AppInfo.AppId = Get-GuidFromObject $AppInfo.AppId
        }

        return $AppInfos
    }

    if (-not $AppGroups) {
        if (-not $sortingOrder) {
            return @()
        }
    }

    $AppGroups = ConvertTo-Hashtable2 -object $AppGroups

    $sortedAppInfos = @()
    $usedKeys = @()        # Groups that are defined in the app groups
    $unusedKeys = @()      # Groups that aren't defined in the app groups
    $specifiedKeys = @()   # Groups that are listed in the sorting order
    $unspecifiedKeys = @() # Groups that aren't listed in the sorting order

    foreach ($key in $sortingOrder) {
        if ($key -in $AppGroups.Keys) {
            if ($AppGroups[$key].Count -gt 0) {
                $sortedAppInfos += $AppGroups[$key]
            }
            $specifiedKeys += $key
            $usedKeys += $key
        }
        else {
            $unusedKeys += $key
        }
    }
    $unspecifiedKeys = $AppGroups.Keys | Where-Object { $_ -notin $usedKeys }

    $warnMsg = @()
    if ($unusedSortingKeys.Count -gt 0) {
        $warnMsg += "The following sorting keys were not used:`n$($unusedSortingKeys -join "`n")"
    }

    if ($unspecifiedApps.Count -gt 0) {
        $warnMsg += "The following app groups were not specified:`n$($unspecifiedKeys -join "`n")"
    }

    if ($warnMsg.Count -gt 0) {
        Write-Warning $warnMsg -join "`n"
    }

    if ($AddUnspecifiedApps) {
        Write-Verbose "Adding unspecified app groups"
        foreach ($key in $unspecifiedKeys) {
            $sortedAppInfos += $AppGroups[$key]
        }
    }

    $sortedAppInfos = $sortedAppInfos | Where-Object { $_ }

    $sortedAppInfos = Get-AppInfosWithTyping -AppInfos $sortedAppInfos

    return $sortedAppInfos
}

# End of functions

$functions = Select-String -Path $MyInvocation.MyCommand.Path -Pattern "^function\s+([^\s{$]+)" | ForEach-Object {
    Write-Host "Function: $($_.Matches[0].Groups[1].Value)" -ForegroundColor DarkGray
    $_.Matches[0].Groups[1].Value
}
Export-ModuleMember -Function $functions
Write-HostTimed "Helper functions loaded." -ForegroundColor Cyan
