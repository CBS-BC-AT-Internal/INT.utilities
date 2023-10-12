
Write-Host DO NOT RUN the whole SCRIPT -BackgroundColor Red
break

Import-Module 'C:\Program Files\Microsoft Dynamics 365 Business Central\180\Service\NavAdminTool.ps1'

## Create NAV service BC18_DEMO
New-NAVServerInstance    `
    -ServerInstance        'BC18_DEMO'  `
    -DatabaseServer        'BCSQL'       `
    -DatabaseInstance      ''          `
    -DatabaseName          'BC18_DEMO'   `
    -ManagementServicesPort 8155  `
    -ClientServicesPort     8156      `
    -SOAPServicesPort       8157        `
    -ODataServicesPort      8158       `
    -DeveloperServicesPort  8159   `
    -ClientServicesCredentialType Windows

Write-Host Account for service has to be done manually  -BackgroundColor Magenta

New-NAVWebServerInstance `
    -Server localhost    `
    -WebServerInstance     'BC18_DEMO'  `
    -ServerInstance        'BC18_DEMO'  `
    -ManagementServicesPort 8155  `
    -ClientServicesPort     8156      `
    -ClientServicesCredentialType Windows

break;    
## Create NAV service BC18_DEMO for NavUserPass
New-NAVServerInstance `
    -ServerInstance        'BC18_DEMO2_USERPW'  `
    -DatabaseServer        'BCSQL'       `
    -DatabaseInstance      ''          `
    -DatabaseName          'BC18_DEMO'   `
    -ManagementServicesPort 8165  `
    -ClientServicesPort     8166      `
    -SOAPServicesPort       8167        `
    -ODataServicesPort      8168       `
    -DeveloperServicesPort  8169   `
    -ServicesCertificateThumbprint 895338551f7c11d671ae761400c4e5e7973a8d04 `
    -ClientServicesCredentialType NavUserPassword

Write-Host Account for service has to be done manually  -BackgroundColor Magenta

New-NAVWebServerInstance  `
    -Server localhost  `
    -WebServerInstance     'BC18_DEMO2_USERPW'  `
    -ServerInstance        'BC18_DEMO2_USERPW'  `
    -DnsIdentity           'BCAPP'  `
    -ManagementServicesPort 8165    `
    -ClientServicesPort     8166    `
    -ClientServicesCredentialType NavUserPassword

break;    
## Remove-NAV Instances und Web Instance
Remove-NAVWebServerInstance -WebServerInstance 'BC18_DEMO2_USERPW'  `
Remove-NAVServerInstance -WebServerInstance 'BC18_DEMO2_USERPW'  `
