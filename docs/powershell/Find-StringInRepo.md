# `Find-StringInRepo.ps1`

This script is designed to retrieve a list of all files containing a specified line across all branches in a Git repository.

## Summary

1. **Parameters**: The script accepts one mandatory parameter, `FilePath`, which is the path to a file containing a list of strings to search for.

2. **Reading the File**: The script reads the file line by line using the `Get-Content` cmdlet.

3. **Searching the Repository**: For each line (string) in the file, the script uses `git rev-list --all` to get a list of all commits across all branches, and then `git grep -l` to find all files containing the string in each commit.

4. **Processing the Results**: If any files are found, the script processes the results to extract the filenames and the branches where the files were found. It does this by manipulating the strings and using various PowerShell cmdlets like `Sort-Object`, `Where-Object`, and `ForEach-Object`.

5. **Output**: The script then prints the string, the filenames, and the branches to the console. If no files are found for a string, it prints a message stating that the string was not found in any branch.

This script can be useful for finding specific strings across a large codebase with multiple branches. It complements the **AL Object ID Ninja** extension for VS Code by looking for unused object IDs that have been registered.
