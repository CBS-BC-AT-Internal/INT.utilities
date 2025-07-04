[CmdletBinding()] # TODO: Instead of "C:\Program Files", use "$env:\Program Files" instead or find path with "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Microsoft Dynamics NAV\*"
param(
    [switch]$NavAdminTool,
    [switch]$UninstallOnly,
    [string]$NavVersion,
    [string]$NavVersionFolder = "*",
    [string]$CloudReadyPath = "C:\Install\Cloud.Ready.Software.PowerShell\PSModules\InstallModule.ps1",
    [string]$NavAdminToolPath = "C:\Program Files\Microsoft Dynamics 365 Business Central\*\Service\NavAdminTool.ps1",
    [string]$cacheFilePath = ".temp\",
    [switch]$clearCache
)

$script:moduleRequirements = @(
    @{
        File = 'Microsoft.Dynamics.Nav.Management.psm1';
        Dll  = 'Microsoft.Dynamics.Nav.Management.dll';
        Name = 'NAV Management'
    },
    @{
        File = 'Microsoft.Dynamics.NAV.Model.Tools.psd1';
        Dll  = 'Microsoft.Dynamics.NAV.Model.Tools.dll';
        Name = 'NAV Model Tools'
    },
    @{
        File = 'Microsoft.Dynamics.Nav.Apps.Tools.psd1';
        Dll  = 'Microsoft.Dynamics.Nav.Apps.Tools.dll';
        Name = 'NAV Apps Tools'
    },
    @{
        File = 'Microsoft.Dynamics.NAV.Apps.Management.psd1';
        Dll  = 'Microsoft.Dynamics.Nav.Apps.Management.dll';
        Name = 'NAV Apps Management'
    }
)

function Import-NAVAdminTool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NavAdminToolPath,
        [Parameter(Mandatory = $true)]
        [string]$NavVersionFolder
    )

    $NavAdminToolPath = $NavAdminToolPath -replace '/', '\'
    $NavAdminToolPath = $NavAdminToolPath -replace '\*\\Service', "${NavVersionFolder}\Service"
    Write-Verbose "Searching for NavAdminTool.ps1 at $NavAdminToolPath"
    $ToolFile = Get-Item -Path $NavAdminToolPath -ErrorAction SilentlyContinue

    if (-not $ToolFile) {
        Write-Error "NavAdminTool.ps1 not found at $NavAdminToolPath"
    }
    elseif ($ToolFile.Count -gt 1) {
        Write-Host "NavAdminTool.ps1 files found:`n$($ToolFile.FullName -join "`n")" -ForegroundColor Red
        Write-Error "Multiple NavAdminTool.ps1 files found. Please specify a single file using the -NavVersionFolder parameter."
    }

    & $ToolFile.FullName -WarningAction SilentlyContinue | Out-Null
}

function Get-CRSNModule {
    param(
        [string]$ModulePath,
        [string]$ModuleName = "Cloud.Ready.Software.NAV"
    )

    $CRSNInstalled = Get-Module -Name "Cloud.Ready.Software.NAV" -ErrorAction SilentlyContinue
    if (-not $CRSNInstalled) {
        Write-Host "Cloud.Ready.Software.NAV module is not installed. Installing..."
        & $CloudReadyPath -WarningAction SilentlyContinue | Out-Null
    }
}

function Remove-NAVModules {
    # TODO: Don't remove modules, compare assembly version instead
    # TODO: If assembly version is different, throw an error and prompt user to start a new session
    $NAVModules = Get-Module -Name "Microsoft.Dynamics.Nav.*" -ErrorAction SilentlyContinue

    if ($NAVModules) {
        foreach ($module in $NAVModules) {
            Write-Host "Removing $($module.Name) $($module.Version)..." -ForegroundColor DarkGray
            Remove-Module -Name $module.Name -Force

            # Unregister the module
            $modulePath = (Get-Module -ListAvailable -Name $module.Name).ModuleBase
            if ($modulePath) {
                # Unregister-PSRepository -Name $module.Name -ErrorAction SilentlyContinue
                Write-Host "Unregistered $($module.Name) from $modulePath" -ForegroundColor DarkGray
            }
        }
    }
    else {
        $NAVModules = @()
    }
    Write-Output $NAVModules
}

function Get-CompatibleVersions {
    param (
        [Parameter(Mandatory = $true)]
        $version,
        [Parameter(Mandatory = $true)]
        [array]$possibleVersions
    )

    $version = [version]$version
    $possibleVersions = $possibleVersions | ForEach-Object {
        if($_ -match '^\d+\.\d+\.\d+\.\d+') {
            [version]$Matches[0]
        }
    } | Sort-Object -Property Name

    if ($version -in $possibleVersions) {
        return $version
    }

    $possibleVersions = $possibleVersions | Where-Object {
        $_.Major -eq $version.Major -and $_ -ge $version
    }

    return $possibleVersions
}

function Get-BestMatchingNAVModules {
    param (
        [Parameter(Mandatory = $true)]
        [array]$navModules,
        [string]$NavVersion
    )

    if ($navModules.Count -eq 0) {
        return $null
    }

    $modulesByVersion = $navModules | Group-Object -Property VersionNo | Sort-Object -Property Name

    $verboseBuffer = @('Found the following NAV module versions:')
    foreach ($module in $modulesByVersion) {
        $verboseBuffer += "BC $($module.Name): $($module.Count) modules found"
    }
    Write-Verbose ($verboseBuffer -join "`n")

    if ($modulesByVersion.Count -eq 1) {
        return $modulesByVersion[0] | Select-Object -ExpandProperty Group
    }

    if ([String]::IsNullOrEmpty($NavVersion)) {
        throw "Multiple NAV module versions found. Please specify a version using the -NavVersion parameter:`n$($modulesByVersion | ForEach-Object { $_.Name })"
    }

    $avlVersions = $modulesByVersion | ForEach-Object { $_.Name }
    $compVersions = Get-CompatibleVersions -version $NavVersion -possibleVersions $avlVersions

    switch ($compVersions.Count) {
        0 { return $null }
        1 { $bestVersion = $compVersions[0] }
        Default {
            $bestVersion = $compVersions | Sort-Object -Property Name | Select-Object -First 1
        }
    }

    return $modulesByVersion | Where-Object { $_.Name -eq $bestVersion } | Select-Object -ExpandProperty Group
}

function Get-NAVModules {
    param(
        [string]$NavVersion
    )

    $navModules = @()
    foreach ($moduleReq in $script:moduleRequirements) {
        $params = @{
            navModuleName    = $moduleReq.File
            navModuleDllName = $moduleReq.Dll
            navModuleTitle   = $moduleReq.Name
            ErrorAction      = 'SilentlyContinue'
            WarningAction    = 'SilentlyContinue'
        }
        Write-Host "Searching $($moduleReq.Name)..."
        Write-Verbose "Get-NAVModuleVersions $(($params.GetEnumerator() | ForEach-Object { "-$($_.Key) $($_.Value)" }) -join ' ')"
        $navModules += Get-NAVModuleVersions @params
    }

    Write-Verbose "Found modules:`n$($navModules | Format-Table -AutoSize | Out-String)"

    $navModules = Get-BestMatchingNAVModules -navModules $navModules -NavVersion $NavVersion

    Write-Verbose "NAV modules:`n$($navModules | Format-Table -AutoSize | Out-String)"

    return $navModules
}

function Test-AssemblyToImport {
    param (
        [Parameter(Mandatory = $true)]
        $moduleToImport
    )

    function Get-LoadedAssembly {
        param (
            [Parameter(Mandatory = $true)]
            [string]$AssemblyName
        )

        $loadedAssemblies = [AppDomain]::CurrentDomain.GetAssemblies()
        return $loadedAssemblies | Where-Object { $_.GetName().Name -eq $AssemblyName }
    }

    $assemblyFullPath = Join-Path (Split-Path $moduleToImport.ModuleFileFullName) $moduleToImport.ModuleDllFileName

    if (-not (Test-Path $assemblyFullPath)) {
        throw "Assembly file not found: $assemblyFullPath"
    }

    $assemblyToImport = [System.Reflection.Assembly]::LoadFrom($assemblyFullPath)
    $assemblyName = $assemblyToImport.GetName().Name
    $assemblyVersion = $assemblyToImport.GetName().Version

    Write-Verbose "Checking assembly $($assemblyName) $($assemblyVersion)"
    $loadedAssembly = Get-LoadedAssembly -AssemblyName $assemblyName
    if ($loadedAssembly) {
        Write-Verbose "Comparing $($loadedAssembly.GetName().Version) with $($assemblyVersion)"
        if ($loadedAssembly.GetName().Version -eq $assemblyVersion) {
            Write-Verbose "$($moduleToImport.ModuleTitle) $($moduleToImport.VersionNo) is already loaded"
        }
        else {
            throw "$($moduleToImport.ModuleTitle) is already loaded with a different version $($loadedAssembly.GetName().Version). Please start a new session."
        }
    }
    else {
        Write-Verbose "$($moduleToImport.ModuleTitle) $($moduleToImport.VersionNo) is not loaded"
    }
}

function Import-NAVModules2 {
    param(
        $navModules
    )

    if ($navModules.Count -eq 0) {
        Write-Error "No compatible NAV module versions found"
    }
    else {
        foreach ($moduleToImport in $navModules) {
            try { # TODO: NavAdminTool doesn't use assemblies, so a different approach is needed
                Test-AssemblyToImport -moduleToImport $moduleToImport
                Import-Module $moduleToImport.ModuleFileFullName -DisableNameChecking -Global -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                Write-Host "$($moduleToImport.ModuleTitle) module has been imported"
            }
            catch {
                Write-Error "$($moduleToImport.ModuleTitle) module has not been imported due to the following error:`n$($_.Exception.Message)"
            }
        }
    }
}

function Export-NAVModulesAsCSV {
    param(
        $navModules,
        [Parameter(Mandatory = $true)]
        [string]$cacheFilePath,
        [string]$NavVersion
    )

    function Get-FileName {
        param(
            [Parameter(Mandatory = $true, Position = 0)]
            [string]$NavVersion
        )

        if ([String]::IsNullOrEmpty($NavVersion)) {
            return "NAVModules.csv"
        }
        else {
            return "NAVModules_${NavVersion}.csv"
        }
    }

    function Get-CacheFilePath {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path,
            [string]$NavVersion
        )

        if ([System.IO.Path]::IsPathRooted($Path)) {
            $fullPath = $Path
        }
        else {
            $fullPath = Join-Path $PWD $Path
        }
        if ($fullPath -match "\.csv$") {
            return $fullPath
        }
        $fileName = Get-FileName $NavVersion
        return Join-Path $fullPath $fileName
    }

    function New-CacheFolderPath {
        param(
            [Parameter(Mandatory = $true, Position = 0)]
            [string]$Path,
            [switch]$Force
        )

        if ($Path -match "\.csv$") {
            $Path = Split-Path $Path -Parent
        }
        else {
            $Path = $Path
        }

        New-Item -ItemType Directory -Path $Path -Force:$Force | Out-Null
    }

    $filePath = Get-CacheFilePath -Path $cacheFilePath -NavVersion $NavVersion
    New-CacheFolderPath -Path $filePath -Force
    Write-Host "Exporting NAV modules to $filePath..."
    try {
        $navModules | Export-Csv -Path $filepath -NoTypeInformation -Force
    }
    catch {
        Write-Warning "Failed to export NAV modules to $filePath due to the following error:"
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

function Get-AndTestCacheFilePath {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$cacheFilePath,
        [string]$navVersion = "*"
    )

    if ([System.IO.Path]::IsPathRooted($cacheFilePath)) {
        $fullCacheFilePath = $cacheFilePath
    }
    else {
        $fullCacheFilePath = Join-Path $PWD $cacheFilePath
    }

    if ($fullCacheFilePath -notmatch ".*\\[^\\]+\.[a-zA-Z0-9]+$") {
        New-Item -ItemType Directory -Path $fullCacheFilePath -Force | Out-Null
        $cacheFiles = Get-ChildItem -Path $fullCacheFilePath -Filter "NavModules_${navVersion}.csv"
        if (($null -ne $cacheFiles) -and ($cacheFiles.Count -eq 1)) {
            return $cacheFiles[0].FullName
        }
        else {
            return $null
        }
    }

    if (Test-Path $fullCacheFilePath -PathType Leaf -ErrorAction SilentlyContinue) {
        return $fullCacheFilePath
    }
    else {
        return $null
    }
}

function Import-ModuleConfigFromCache {
    param (
        [Parameter(Mandatory = $true)]
        [string]$cacheFilePath,
        [string]$NavVersion
    )

    $cacheFilePath = Get-AndTestCacheFilePath -cacheFilePath $cacheFilePath -navVersion $NavVersion
    if (-not $cacheFilePath) {
        return $null
    }

    if ($cacheFilePath -notmatch "\.csv$") {
        Write-Error "The cache file must be a CSV file. Actual file: $cacheFilePath"
    }

    try {
        $navModules = Import-Csv -Path $cacheFilePath
    }
    catch {
        return $null
    }

    $requiredColumns = @("ModuleFileFullName", "ModuleTitle")
    $missingColumns = $requiredColumns | Where-Object { -not $navModules[0].PSObject.Properties[$_].Value }

    if ($missingColumns.Count -gt 0) {
        Write-Error "The table $cacheFilePath is missing the following columns: $($missingColumns -join ', ')"
    }
    Write-Host "Cache file found. Importing NAV modules from $cacheFilePath" -ForegroundColor Cyan

    return $navModules
}

$ErrorActionPreference = "Stop"

Remove-NAVModules

if ($UninstallOnly) {
    return
}

if ($NavAdminTool) {
    Import-NAVAdminTool -NavAdminToolPath $NavAdminToolPath -NavVersionFolder $NavVersionFolder
}
else {
    if ($clearCache) {
        $fullCacheFilePath = Get-AndTestCacheFilePath -cacheFilePath $cacheFilePath -navVersion $NavVersion
        if ($fullCacheFilePath) {
            Write-Verbose "Clearing cache file $fullCacheFilePath"
            Remove-Item -Path $fullCacheFilePath -Force
        }
    }
    else {
        $navModules = Import-ModuleConfigFromCache -cacheFilePath $cacheFilePath -NavVersion $NavVersion
    }

    if (-not $navModules -or $navModules.Count -eq 0) {
        Write-Warning "No cache file found. Searching for NAV modules."
        Get-CRSNModule -ModulePath $CloudReadyPath
        $navModules = Get-NAVModules -NavVersion $NavVersion
        if ($navModules.Count -gt 0) {
            Write-Output $navModules
            Export-NAVModulesAsCSV -navModules $navModules -cacheFilePath $cacheFilePath -NavVersion $NavVersion
        }
    }

    Import-NAVModules2 -navModules $navModules
}
