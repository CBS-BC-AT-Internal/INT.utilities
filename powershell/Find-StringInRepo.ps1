<#
.SYNOPSIS
Retrieves a list of all files containing a specified line across all branches in a Git repository.

.DESCRIPTION
This script reads a list of strings, provided in the parameters. For each string, it retrieves a list of all files containing the string across all branches in a Git repository. It then prints the string, the files containing the string, and the branches containing the files. This can be used to find AL objects that only exist in a single branch.

.PARAMETER InputParameter
Specifies the input parameter for the script.

.EXAMPLE
.\Script.ps1 -InputParameter "example"
This example demonstrates how to run the script with the specified input parameter.

.NOTES
Author: [Your Name]
Date: [Current Date]
Version: 1.0
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$FilePath
)

foreach ($line in (Get-Content -Path $FilePath)) {
    # get a list of all files containing the line across all branches
    $files = git rev-list --all | ForEach-Object { git grep -l $line $_ }

    # if there are files, then...
    if ($files) {
        # print the object id
        Write-Host "Object ${line}:"

        Write-Host "  Files:"

        # trim everything before the last slash
        $filenames = $files | ForEach-Object { $_.Substring($_.LastIndexOf('/') + 1) }

        # filter out duplicate results
        $filenames = $filenames | Sort-Object -Unique

        # print the filenames
        $filenames | ForEach-Object { Write-Host "    $_" }

        Write-Host "  Branches:"

        # trim everything after the first colon
        $branches = $files | ForEach-Object { $_.Substring(0, $_.IndexOf(':')) }

        # get the branch names containing the commit in the result
        $branches = $branches | ForEach-Object { git name-rev --name-only $_ }

        # filter to only remote branches
        $branches = $branches | Where-Object { $_ -like "remotes/*" }

        # trim everything before the last slash
        $branches = $branches | ForEach-Object { $_.Substring($_.LastIndexOf('/') + 1) }

        # trim everything after the first caret
        $branches = $branches | ForEach-Object {
            $index = $_.IndexOf('^')
            if ($index -ge 0) {
                $_.Substring(0, $index)
            }
            else {
                $_
            }
        }

        # trim everything after the first tilde
        $branches = $branches | ForEach-Object {
            $index = $_.IndexOf('~')
            if ($index -ge 0) {
                $_.Substring(0, $index)
            }
            else {
                $_
            }
        }

        # filter out duplicate results
        $branches = $branches | Sort-Object -Unique

        # print the branch names
        $branches | ForEach-Object { Write-Host "    $_" }
    }
    else {
        Write-Host "Object ${line} not found in any branch."
    }
}
