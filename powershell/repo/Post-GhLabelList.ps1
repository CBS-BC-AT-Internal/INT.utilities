<#
.SYNOPSIS
    Creates or updates GitHub labels for a repository using a JSON file and the GitHub CLI.

.DESCRIPTION
    This script reads a JSON file containing label definitions and applies them to a specified GitHub repository.
    It will create new labels or update existing ones using the GitHub CLI (`gh`).

.PARAMETER JsonFilePath
    Path to the JSON file containing label definitions.

.PARAMETER Repo
    Name of the GitHub repository (e.g., 'my-repo' or 'owner/my-repo').

.PARAMETER Owner
    Owner of the repository (default: 'CBS-BC-AT').

.PARAMETER Silent
    If specified, writes less output to the console.

.JSON FILE FORMAT
    The JSON file must be an array of objects, each with the following properties:
    [
        {
            "name": "LabelName",
            "color": "hexcolor",         # e.g., "f29513"
            "description": "Description" # Optional
        },
        ...
    ]

.EXAMPLE
    .\Post-GhLabelList.ps1 -JsonFilePath ".\labels.json" -Repo "my-repo"

.NOTES
    Requires GitHub CLI (`gh`) to be installed and authenticated.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$JsonFilePath,
    [Parameter(Mandatory=$true)]
    [string]$Repo,
    [string]$Owner = 'CBS-BC-AT',
    [switch]$Silent
)

# Check if GitHub CLI is installed
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) is not installed. Please install it first: https://cli.github.com/"
    exit 1
}

# Read and parse the JSON file
try {
    $labels = Get-Content -Raw -Path $JsonFilePath | ConvertFrom-Json
} catch {
    Write-Error "Failed to read or parse JSON file: $JsonFilePath"
    exit 1
}

# Generate the repo address
if ($Repo -notmatch "/") {
    $Repo = "$Owner/$Repo"
}

# Check if repository exists
$repoExists = & gh repo view $Repo --json id
if (-not $repoExists) {
    Write-Error "Repository '$Repo' does not exist or is inaccessible. Use `gh auth login` to authenticate."
    exit 1
}

# Get all existing labels
$existingLabels = & gh label list --repo $Repo --json name | ConvertFrom-Json
$labelsCreated = 0
$labelsPatched = 0
$labelsSkipped = 0

foreach ($label in $labels) {
    $name = $label.name
    $color = $label.color
    $description = $label.description

    # Check if label exists using the cached list
    $labelExists = $existingLabels | Where-Object { $_.name -eq $name }
    $labelExists = $null -ne $labelExists

    if ($labelExists) {
        if (-not $Silent) {
            Write-Host "Updating label '$name'" -ForegroundColor DarkGray
        }
        try {
            if ($description -and $description.Trim() -ne "") {
                gh label edit $name --repo $Repo --color $color --description $description
            } else {
                gh label edit $name --repo $Repo --color $color
            }
            if (-not $Silent) {
                Write-Host "Label '$name' patched successfully." -ForegroundColor Green
            }
            $labelsPatched++
        } catch {
            Write-Warning "Failed to patch label '$name'."
            $labelsSkipped++
        }
    } else {
        if (-not $Silent) {
            Write-Host "Creating label: $name" -ForegroundColor DarkGray
        }
        try {
            if ($description -and $description.Trim() -ne "") {
                gh label create $name --repo $Repo --color $color --description $description
            } else {
                gh label create $name --repo $Repo --color $color
            }
            if (-not $Silent) {
                Write-Host "Label '$name' created successfully." -ForegroundColor Green
            }
            $labelsCreated++
        } catch {
            Write-Warning "Failed to create label '$name'."
            $labelsSkipped++
        }
    }
}

$result = ''
if ($labelsCreated -gt 0) {
    $result += " $labelsCreated labels created."
}
if ($labelsPatched -gt 0) {
    $result += " $labelsPatched labels updated."
}
if ($labelsSkipped -gt 0) {
    $result += " $labelsSkipped labels skipped."
}

Write-Host $result.Trim() -ForegroundColor Cyan
