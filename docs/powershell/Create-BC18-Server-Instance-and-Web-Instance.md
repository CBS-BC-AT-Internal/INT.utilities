# Create-BC18-Server-Instance-and-Web-Instance

This script is a collection of snippets used to create and manage Microsoft Dynamics 365 Business Central server instances and web instances.

**WARNING!** This is not a complete script intended for general use. It contains multiple literals and expects already installed modules.

## Summary

1. Create a new server instance named `BC18_DEMO` with specified parameters like database server, database name, and various service ports. The credential type for client services is set to Windows. A corresponding web server instance is also created.

2. Create a new server instance `BC18_DEMO2_USERPW` with specified parameters like database server, database name, and various service ports. The credential type for client services is set to NavUserPassword. A corresponding web server instance is also created.

3. Removes the 'BC18_DEMO2_USERPW' server and web server instances.
