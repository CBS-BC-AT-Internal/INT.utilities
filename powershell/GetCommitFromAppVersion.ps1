<#
.SYNOPSIS
    Retrieves the commit SHA associated with a specific GitHub Actions workflow run based on the provided version string.
.DESCRIPTION
    This script takes a version string formatted as 'major.minor.build.revision' (e.g., '1.0.123.2') and extracts the build number and attempt number.
    It then queries the GitHub API to find the corresponding workflow run in the specified repository and retrieves the commit SHA associated with that run.
    If no repository is specified, it attempts to determine the repository from the current Git configuration.
.PARAMETER GithubToken
    A GitHub personal access token with permissions to read workflow runs in the target repository.
.PARAMETER Version
    The version string in the format 'major.minor.build.revision' (e.g., '1.0.123.2').
.PARAMETER Repo
    The GitHub repository in the format 'owner/repo'. If not provided, the script will attempt to determine it from the remote URL of the current Git repository.
.PARAMETER WorkflowName
    The name of the GitHub Actions workflow file (default: 'CICD.yaml').c:\repo\GAR.Base\.AL-Go\Update-AppManifest.ps1 c:\repo\GAR.Base\.AL-Go\Get-ALGoAppVersion.ps1
#>
param (
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$GithubToken,
    [Parameter(Position = 1, Mandatory = $true)]
    [string]$Version,
    [string]$Repo,
    [string]$WorkflowName = 'CICD.yaml'
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

$GithubToken = Get-GitHubToken -TokenValue $GithubToken

# Parse version string (expects format: major.minor.build.revision)
if ($Version -notmatch '^\d+\.\d+\.(\d+)\.(\d+)$') {
    Throw "Version must be in the format 'x.y.runNumber.attempt', e.g., '1.0.123.2'"
}
$RunNumber = [int]$Matches[1]
$Attempt = [int]$Matches[2]

# Get the repository name from the remote URL if not provided
if (-not $Repo) {
    $RepoUrl = git remote get-url origin
    $Repo = $RepoUrl -replace '^.*github.com[:/](.*?)(\.git)?$', '$1'
}

Write-Host "Using repository: $Repo"
Write-Host "Searching for run number $RunNumber, attempt $Attempt"

# Set GitHub API Headers
$Headers = @{
    "Accept"        = "application/vnd.github.v3+json"
}

if ($GithubToken) {
    $Headers["Authorization"] = "Bearer $GithubToken"
}

# Get the Workflow ID
$WorkflowUrl = "https://api.github.com/repos/$Repo/actions/workflows/$WorkflowName"
$WorkflowResponse = Invoke-RestMethod -Uri $WorkflowUrl -Headers $Headers -Method Get -ErrorAction Stop
$WorkflowId = $WorkflowResponse.id

if (-not $WorkflowId) {
    Throw "Workflow '$WorkflowName' not found in repository '$Repo'."
}

# Get Workflow Runs (paginated, so may need to loop if many runs)
$Page = 1
$Found = $false
$CommitSHA = $null

while (-not $Found) {
    $RunsUrl = "https://api.github.com/repos/$Repo/actions/workflows/$WorkflowId/runs?per_page=100&page=$Page"
    $RunsResponse = Invoke-RestMethod -Uri $RunsUrl -Headers $Headers -Method Get -ErrorAction Stop

    foreach ($run in $RunsResponse.workflow_runs) {
        if ($run.run_number -eq $RunNumber -and ($run.run_attempt - 1) -eq $Attempt) {
            $CommitSHA = $run.head_sha
            $Found = $true
            break
        }
    }

    if ($Found -or $RunsResponse.workflow_runs.Count -lt 100) {
        break
    }
    $Page++
}

if (-not $CommitSHA) {
    Throw "No workflow run found for run number $RunNumber and attempt $Attempt."
}

Write-Host "Commit SHA for version ${Version}: $CommitSHA"
return $CommitSHA