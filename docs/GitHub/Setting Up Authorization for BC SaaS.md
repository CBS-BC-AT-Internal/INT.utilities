# Setting Up Automated Deployment for BC SaaS

This guide will walk you through the process of setting up an automatic **GitHub pipeline** for a **Microsoft 365 Dynamics BC SaaS** environment.
By following this guide, you will be able to automatically publish the latest build of your apps and its dependencies on a sandbox environment, as well as publish new releases to production environments.

## Table of Contents <!-- omit from toc -->

- [Prerequisites](#prerequisites)
- [Azure Configuration](#azure-configuration)
- [Business Central Configuration](#business-central-configuration)
- [GitHub Configuration](#github-configuration)
- [VS Code Configuration](#vs-code-configuration)
- [Publishing](#publishing)

## Prerequisites

- A **GitHub repository** with AL Go system files (Use the [AL Go Template](https://github.com/CBS-BC-AT/AL-Go) to create a new repository or copy the files from)
- A valid **BC environment**
- A **Microsoft account** with admin access in BC and permissions to add and modify Microsoft Entra apps in Azure

## Azure Configuration

1. Navigate to the **Azure Portal** of the customer at [https://portal.azure.com/](https://portal.azure.com/).
2. For multi-tenant environments, make sure to select the correct tenant in **Settings**.
3. Create a new **Microsoft Entra Application**:
   - Browse to `Identity > Applications > App registrations` and select `New registration`.
   - Enter the following details:
     - **Name**: Anything, but something like "*GitHub/BC Access*" is recommended
     - **Supported account types**: "*Accounts in this organizational directory only (Single tenant)*"
     - **Redirect URI**: This is only necessary for human-facing apps, so you can skip this step.
   - Note down the **Client ID** in the overview.
4. Add a **secret**:
   - Navigate to `Certificates & secrets > Client secrets > New client secret > Add`.
   - Note down the **SECRET VALUE** (not ID!). Remember that secrets have **expiry dates**, so be sure to renew them.
5. Add **permission** to BC API:
   - Navigate to `API permissions > Add a permission > Dynamics 365 Business Central > Application permissions`.
   - Add the following permissions:
     - `API.ReadWrite.All`
     - `Automation.ReadWrite.All`
   - Click on `Add permissions > Grant admin consent`.

## Business Central Configuration

1. Navigate to the **Business Central webclient** of the customer at [https://businesscentral.dynamics.com/](https://businesscentral.dynamics.com/).
2. If you haven't already, note down the **Tenant ID** in the URL.
3. Add the new application:
   - Browse to **Microsoft Entra Applications** and select **New**.
   - Enter the following details:
     - **Client ID**: Use the *Client ID* from earlier
     - **Description**: Anything, but the *name of the Entra app* is recommended
     - **State**: *Enabled*
4. Assign **permission sets**:
   - These are needed to allow the app to access the API used to publish new extensions
   - If the **User Permission Sets** table at the bottom of the page is still disabled, reload the page
   - Add the following lines:
     - `D365 AUTOMATION`
     - `EXTEN. MGT. - ADMIN`

## GitHub Configuration

1. Navigate to the **GitHub repo** of the project at [https://github.com/orgs/CBS-BC-AT/repositories](https://github.com/orgs/CBS-BC-AT/repositories).
2. Create a new **environment**:
   - Browse to `Settings > Environments > New Environment`.
   - Name: Anything, as long as it's easy to identify. The *same name as the BC environment* is recommended. Note down the name.
3. Set **branch policy** (This is optional, but prevents accidental releases. Don't create a production environment without one.):
   - Click on **Deployment branches and tags** and choose *Selected branches and tags*.
     - Add any branch or tag the app should be published from. For example, adding the tag `v*` will only allow deployments from commits tagged with something that starts with "*v*".
4. Set **Authorization values**:
   - Navigate to `Environment secrets > Add secret`.
   - Enter the following details:
     - **Name**: `AUTHCONTEXT`
     - **Value**: `{"TenantID":"<Tenant ID>","ClientID":"<Client ID>","ClientSecret":"<Secret value>"}` (Fill in the IDs and secret you've written down. This must be compressed, no whitespaces allowed!)

## VS Code Configuration

1. Open the repository in **VS Code**.
2. Open `.github\AL-Go-Settings.json`.
3. Configure **deploy settings** by adding this property:

   ```json
   "DeployTo<GitHub Environment Name>":
   {
     "Branches": ["main"],
     "ContinuousDeployment": "<Sandbox?>",
     "environmentName": "<BC Environment Name>",
     "environmentType": "SaaS",
     "runs-on": "windows-latest"
   }
   ```

   - `Branches`: A whitelist of branches allowed to deploy from. Defaults to the *default branch only*.
   - `ContinuousDevelopment`: Whether to deploy on each push, or only manually and on release. Use `true` for Sandbox and `false` for Production environments.
   - `environmentName`: The name of the BC environment. Defaults to the *GitHub environment name*.
   - `environmentType`: Defaults to `SaaS`. Custom types can be defined with a `.github\DeployTo<Environment Type>.ps1` script.
   - `runs-on`: The OS of the action runner performing the deployment. At the time of writing, due to a bug, `windows-latest` is necessary. This might be outdated.
4. **Push** the changes.

## Publishing

- To publish to sandbox environments: This is automated and triggers on every push of the branch.
- To publish to production: Go to `GitHub > Actions > Create release`. Run the workflow with parameters defined for the project.
