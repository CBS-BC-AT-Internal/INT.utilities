param(
    [parameter(Mandatory = $true, position = 0)]
    [ValidateNotNullOrEmpty()]
    [string] $srvInst,
    [parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string] $appPath,
    [string] $Tenant = "default",
    [ValidateSet("Add", "Clean", "Development", "ForceSync", "None")]
    [string] $SyncMode = "Add",
    [switch] $ForceSync,
    [string] $bcVersion,
    [string] $folderVersion,
    [ValidateScript({ if (![string]::IsNullOrEmpty($_)) { Test-Path $_ -PathType Leaf } else { $true } })]
    [string] $modulePath,
    [switch] $showColorKey,
    [switch] $runAsJob,
    [switch] $dryRun
)

if ($ForceSync) {
    $SyncMode = "ForceSync"
}

$updateAppScriptPath = (Join-Path $PSScriptRoot "Update-NAVAppScript.ps1")

$updateParams = @{
    ServerInstance = $srvInst
    AppFilePath    = $appPath
    Tenant         = $Tenant
    SyncMode       = $SyncMode
    $installedApps = $null
    DryRun         = $dryRun
}

& $updateAppScriptPath @updateParams
