param (
    [Parameter(Position = 0)]
    [string]$GithubToken,
    [string]$Repo,
    [string]$WorkflowName = 'CICD.yaml',
    [string]$CommitSHA
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

if ($CommitSHA) {
    # Check if the commit exists
    try{
        git cat-file -e $CommitSHA
    } catch {
        Throw "Commit SHA '$CommitSHA' does not exist."
    }
} else {

    # Get the commit SHA of the current branch
    $CommitSHA = git rev-parse HEAD
    if (-not $CommitSHA) {
        Throw "Unable to get the commit SHA of the current branch."
    }
}

Write-Host "Using commit SHA: $CommitSHA"

# Get the repository name from the remote URL
if (-not $Repo) {
    $RepoUrl = git remote get-url origin
    $Repo = $RepoUrl -replace '^.*github.com[:/](.*?)(\.git)?$', '$1'
}

Write-Host "Using repository: $Repo"

# Set GitHub API Headers
$Headers = @{
    "Accept"        = "application/vnd.github.v3+json"
}

if ($GithubToken) {
    $Headers["Authorization"] = "Bearer $GithubToken"
}

# Test the GitHub API connection
$TestUrl = "https://api.github.com/repos/$Repo"
Write-Verbose "GET $TestUrl"
$TestResponse = Invoke-RestMethod -Uri $TestUrl -Headers $Headers -Method Get -ErrorAction Stop

if (-not $TestResponse.id) {
    Throw "Unable to connect to repository '$Repo'."
}

Write-Verbose "Successfully connected to repository '$Repo' (id: $($TestResponse.id))."

# Get the Workflow ID
$WorkflowUrl = "https://api.github.com/repos/$Repo/actions/workflows/$WorkflowName"
Write-Verbose "GET $WorkflowUrl"
$WorkflowResponse = Invoke-RestMethod -Uri $WorkflowUrl -Headers $Headers -Method Get -ErrorAction Stop
$WorkflowId = $WorkflowResponse.id

if (-not $WorkflowId) {
    Throw "Workflow '$WorkflowName' not found in repository '$Repo'."
}

Write-Verbose "Found workflow '$WorkflowName' (id: $WorkflowId) in repository '$Repo'."

# Get Workflow Runs filtered by Commit SHA
$RunsUrl = "https://api.github.com/repos/$Repo/actions/workflows/$WorkflowId/runs?head_sha=$CommitSHA"
Write-Verbose "GET $RunsUrl"
$RunsResponse = Invoke-RestMethod -Uri $RunsUrl -Headers $Headers -Method Get -ErrorAction Stop

# Check if any runs exist
if (-not $RunsResponse.workflow_runs -or $RunsResponse.workflow_runs.Count -eq 0) {
    Throw "No workflow runs found for commit $CommitSHA."
}

# Get the most recent run
$LatestRun = $RunsResponse.workflow_runs | Sort-Object -Property created_at -Descending | Select-Object -First 1
$RunNumber = $LatestRun.run_number
$Attempt = $LatestRun.run_attempt - 1 # Adjusting for zero-based index

return $RunNumber, $Attempt
