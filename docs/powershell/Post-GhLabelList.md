# PowerShell Script: Post-GhLabelList

## Synopsis

Creates or updates GitHub labels for a repository using a JSON file and the GitHub CLI.

## Description

This script reads a JSON file containing label definitions and applies them to a specified GitHub repository. It will create new labels or update existing ones using the GitHub CLI (`gh`).

## Parameters

- `JsonFilePath`: Path to the JSON file containing label definitions.
- `Repo`: Name of the GitHub repository (e.g., 'my-repo' or 'owner/my-repo').
- `Owner`: Owner of the repository (default: 'CBS-BC-AT').
- `Silent`: If specified, writes less output to the console.

## JSON File Format

The JSON file must be an array of objects, each with the following properties:

```json
[
    {
        "name": "LabelName",
        "color": "hexcolor",         // e.g., "f29513"
        "description": "Description" // Optional
    },
    ...
]
```

## Example

```powershell
.\Post-GhLabelList.ps1 -JsonFilePath ".\labels.json" -Repo "my-repo"
```

## Notes

- Requires GitHub CLI (`gh`) to be installed and authenticated.
- The script checks if the repository exists and if the GitHub CLI is installed.
- Existing labels are updated; new labels are created as needed.
- Summary output includes the number of labels created, updated, or skipped.

## Output

The script prints a summary of actions taken (labels created, updated, skipped) to the console. If `-Silent` is specified, output is minimized.

## Error Handling

- If the GitHub CLI is not installed, the script exits with an error.
- If the JSON file cannot be read or parsed, the script exits with an error.
- If the repository does not exist or is inaccessible, the script exits with an error.

## See Also

- [Download GitHub CLI](https://cli.github.com/)
- [GitHub CLI Documentation](https://cli.github.com/manual/)
- [GitHub Label API Reference](https://docs.github.com/en/rest/issues/labels)
