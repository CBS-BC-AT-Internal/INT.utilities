# Create-Container.ps1

This script is used to create a new Business Central (BC) container using the latest version and the country `at`.

## Summary

1. It starts by defining parameters that can be passed to the script, including the container name, version, authentication method, license path, shortcut path, and whether to include the test toolkit.

2. It then checks and fixes BC Container Helper permissions.

3. It builds a parameter hashtable for fetching the BC artifact URL, which is used to download the specific version of BC for the container.

4. If the version parameter is not null or empty, it adds it to the parameters.

5. It fetches the BC artifact URL and prints it to the console.

6. It builds another parameter hashtable for creating the BC container, including parameters to accept the EULA, the artifact URL, authentication method, whether to update hosts, and whether to include the test toolkit.

7. If the container name, license path, or shortcut path parameters are not null or empty, it adds them to the parameters.

8. Finally, it creates the BC container using the `New-BCContainer` cmdlet with the built parameters.
