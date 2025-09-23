[CmdletBinding()]
param (
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Path = '.',
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$GitHubToken,
    $GetAlGoAppVersionScriptPath = '../.AL-Go/Get-ALGoAppVersion.ps1',
    [string]$branch,
    [switch]$Force
)

function Get-GitHubToken {
    param (
        [string]$TokenValue
    )

    if (-null -eq $GithubToken -or $GithubToken -eq '') {
        Write-Verbose "No GITHUB_TOKEN provided. Proceeding without authentication."
        return $null
    }

    if ($TokenValue -and (Test-Path $TokenValue)) {
        $secretsContent = Get-Content $TokenValue
        $TokenValue = $secretsContent | ForEach-Object {
            if ($_ -match 'GH_TOKEN=(.*)') {
                Write-Verbose "Extracted GITHUB_TOKEN from file."
                return $matches[1]
            }
        }

        if (-not $TokenValue) {
            Throw "Unable to extract GITHUB_TOKEN from the file '$TokenValue'. Must be in the format GH_TOKEN=***."
        }
    }
    else {
        Write-Verbose "Using provided GITHUB_TOKEN."
    }

    return $TokenValue
}

function TestBranch {
    param (
        [string]$branch,
        $algoSettings
    )

    # Check if there are uncommitted changes
    if (git status --porcelain) {
        Throw "There are uncommitted changes. Please push, stash or discard them first."
    }
    Write-Verbose "No uncommitted changes found."

    # Check if the current branch is on the remote
    $remoteBranch = "refs/remotes/origin/$branch"
    $remoteCheck = git show-ref --verify $remoteBranch 2>$null
    if (-not $remoteCheck) {
        Throw "The current branch '$branch' is not on the remote. Please push it first."
    }
    Write-Verbose "Current branch '$branch' is on the remote."

    # Check if HEAD is ahead of remote (unpushed commits)
    $ahead = git rev-list --count $remoteBranch..HEAD
    if ($ahead -gt 0) {
        Throw "There are unpushed commits. Please push them first."
    }
    Write-Verbose "No unpushed commits. (HEAD is at or behind remote)"
}

function TestCICDBranch {
    param(
        [string]$branch,
        $algoSettings
    )

    # Get the list of CI/CD branches
    $ciBranches = $algoSettings.CICDPushBranches

    if (-not $ciBranches) {
        $ciBranches = @('master', 'main', 'release/*', 'feature/*')
    }

    # Check if the current branch is in the list of CI/CD branches
    if (-not ($ciBranches | Where-Object { $branch -like $_ })) {
        Throw "The current branch '$branch' is not in the list of CI/CD branches."
    }
    Write-Verbose "Current branch '$branch' is in the list of CI/CD branches."
}

# Set the current location
$currentLocation = Get-Location
Set-Location $Path

try {
    # Check if the directory or parent directory is a git repository
    if (-not (Test-Path '.git') -and -not (Test-Path '../.git')) {
        Throw "The current directory is not a git repository."
    }
    Write-Verbose "Current directory is a git repository."

    $GitHubToken = Get-GitHubToken -TokenValue $GitHubToken
    $rootPath = git rev-parse --show-toplevel
    $appManifestPath = Resolve-Path 'app.json' -ErrorAction Stop
    $algoSettingsPath = Join-Path $rootPath '.github/AL-Go-Settings.json' -Resolve -ErrorAction Stop
    $GetAlGoAppVersionScriptPath = Resolve-Path $GetAlGoAppVersionScriptPath -ErrorAction Stop

    # Load the AL-Go settings
    try {
        $algoSettings = Get-Content $algoSettingsPath | ConvertFrom-Json
    }
    catch {
        $algoSettings = $null
    }

    if (-not $algoSettings) {
        Throw "The AL-Go settings file '$algoSettingsPath' is invalid."
    }

    # Fetch the latest changes
    git fetch

    if (-not $branch) {
        $commitSHA = git rev-parse HEAD

        # Check if HEAD is detached
        $symbolicRef = git symbolic-ref -q HEAD 2>$null
        if ($symbolicRef) {
            $branch = git rev-parse --abbrev-ref HEAD
            Write-Verbose "Using current branch '$branch'."
            $overrideBranch = $false
        }
        else {
            # Detached HEAD: find branch containing current commit
            $branches = git branch -r --contains $commitSHA | ForEach-Object { $_.Trim() -replace '^origin/', '' } | Where-Object { $_ -ne '' -and $_ -notmatch '->' }
            if ($null -eq $branches -or $branches.Count -eq 0) {
                Throw "Commit $($commitSHA.Substring(0, 7)) is not contained in any branch. Cannot determine branch."
            }
            if ($branches -is [string]) {
                $branch = $branches
            }
            else {
                $branch = $branches[0]
            }
            Write-Verbose "HEAD is detached. Using branch '$branch' containing commit $commitSHA."
            $overrideBranch = $false
        }
    }
    else {
        Write-Verbose "Using override branch '$branch'."
        $remoteBranch = "refs/remotes/origin/$branch"
        $overrideBranch = $true
        $commitSHA = git rev-parse $remoteBranch
    }

    Write-Verbose "Using commit SHA: $commitSHA"

    if ($Force) {
        Write-Host "Force mode enabled. Skipping branch validation."
    }
    else {
        if (-not $overrideBranch) {
            # Check if the head is set correctly
            TestBranch -branch $branch -algoSettings $algoSettings
            Write-Verbose "Branch '$branch' is valid for CI/CD."
        }
        # Check if the branch is in the list of CI/CD branches
        TestCICDBranch -branch $branch -algoSettings $algoSettings
        Write-Verbose "Branch '$branch' is in the list of CI/CD branches."
    }

    # Get the CI/CD run number
    try {
        $runNo, $attempt = & $GetAlGoAppVersionScriptPath -GitHubToken $GitHubToken -CommitSHA $commitSHA -Repo $algoSettings.GitHubRepo
    }
    catch {
        Throw "Failed to get the CI/CD run number."
    }

    # Load the app manifest
    $appManifest = Get-Content $appManifestPath | ConvertFrom-Json
    $version = $appManifest.version -split '\.'

    # Update the app manifest
    $version[2] = $runNo
    if ($attempt -gt 1) {
        $version[3] = $attempt
    }
    else {
        $version[3] = 0
    }
    $appManifest.version = $version -join '.'
    $appManifest | ConvertTo-Json -Depth 100 -Compress:$false | Set-Content $appManifestPath

    Write-Host "The app manifest has been updated to version '$($appManifest.version)'."
}
finally {
    Set-Location $currentLocation
}
