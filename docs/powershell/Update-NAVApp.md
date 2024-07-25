# PowerShell Script Update-NAVApp.ps1

This script is used to manage the lifecycle of a NAV App in a Business Central server instance.

## Summary

1. **Parameters**: The script accepts three parameters - `$srvInst` (the server instance), `$appPath` (the path to the app), and `$ForceSync` (a switch to force synchronization).

2. **Prepare PowerShell for default BC18 installation**: The script sets the execution policy to unrestricted, checks if the 'Cloud.Ready.Software.NAV' module is available, and if not, installs it.

3. **Color description**: The script sets up color-coded output for different types of messages (info, success, error, etc.).

4. **Function "AddAppToDependentList"**: This function is used to create a list of all apps that depend on the given `$appName`.

5. **Check parameters and app version**: The script checks if the app file exists and if the version of the app is already published.

6. **Get list of apps which have to be uninstalled**: The script creates a list of dependent apps that need to be uninstalled before the new app can be installed.

7. **Uninstall dependent apps**: The script uninstalls all dependent apps.

8. **Publish new app**: The script publishes the new app if its version is different from the old one.

9. **Sync and Upgrade new app**: The script synchronizes and upgrades the new app.

10. **Install dependent apps**: The script reinstalls the previously uninstalled dependent apps.

11. **Unpublish all previous app versions**: The script unpublishes all previous versions of the app.

The script ends by displaying a success message indicating that the app has been deployed.
