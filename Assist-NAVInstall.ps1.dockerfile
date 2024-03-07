# Use a base image with PowerShell installed
FROM mcr.microsoft.com/windows/servercore:10.0.20348.2322
LABEL Name=int

# Set the working directory
WORKDIR /app

# Copy the PowerShell script into the Docker image
COPY powershell/Assist-NAVInstall.ps1 .
COPY test/Assist-NAVInstall C:/app/Assist-NAVInstall

# Run the PowerShell script when the Docker container is started
CMD ["powershell", "-File", "Assist-NAVInstall.ps1", "-appFolder", "Assist-NAVInstall", "-configURI", "Assist-NAVInstall/NAVInstall.config.json"]
