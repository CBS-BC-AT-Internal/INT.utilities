# PowerShell Script: Assist-NAVInstall

## Synopsis

This PowerShell script is used to automatically install the latest version of a given extension in a Business Central environment.

## Description

The script deploys one or all applications defined in a configuration file to a Business Central environment. If any information is missing from the configuration file, the script will prompt the user for input. By providing the application name and folder, the script will automatically locate the latest version for deployment. It then retrieves and executes the update script to publish and install the application in the environment.

## Parameters

- `configURI`: Specifies the path to the configuration file. Accepts filepaths and URLs. Default value is "\NAVInstall.config.json".
- `server`: Specifies the server instance. If not provided, the user can choose between the server instances defined in the configuration file.
- `appPath`: Specifies the path to the application file. If not provided, the script will search for the application file with the highest version number in the specified application folder.
- `scriptURI`: Specifies the path to the update script. May be a path to a local file or a URL. By default, it points towards the [Update-NAVApp.ps1](../../powershell/Update-NAVApp.ps1) script in this repository.
- `ForceSync`: Switch parameter to force synchronization during the update process.
- `dryRun`: Specifies whether to run the script without writing any changes to the system. Used for testing purposes.

For more information, refer to the [Assist-NAVInstall.md](../../powershell/Assist-NAVInstall.ps1) file.

## Configuration file

By default, the script attempt to load a configuration file called
`NAVInstall.config.json` within its folder. Using the parameter `configURI`, a
different location may be specified.

### Properties

- `"apps"`: An array defining zero or more apps.
  - `"folder"`: The folder containing the app file.
  - `"name"`: The name of the app. Note that the required filename structure has
  to be `"*_[VERSION].app"`. If the filename does not contain the version number
  or uses a different version number, the script can't locate the latest app to
  deploy.
- `"servers"`: A list defining zero or more server instances.
  - `Server alias`: Each element within `"servers"` is interpreted as an
    environment, whereas the key is used as an alias to easily identify the
    server, and the value is used as the server instance.
- `"bcversion"`: Defines the version of the BC server. This value is optional
and only needed if more than one version of BC is installed on the same system.

## Example config file

```json
{
    "apps":
    [
        {
            "folder": "C:\\apps",
            "name": "Cegeka_Sample Extension"
        }
    ],
    "servers":
    {
        "DEV": "bc20-CBS-DEV",
        "TEST": "bc20-CBS-TEST",
        "LIVE": "bc20-CBS-LIVE"
    }
}
```
