param (
    [switch]$y
)

function Confirm-Or-Skip($message) {
    if ($y) { return $true }

    $choice = Read-Host "$message [Y/N]"
    return $choice -match '^[Yy]$'
}

function Install-AWSCLI {
    Write-Host "`n--- AWS CLI Installation ---"
    if (-not (Confirm-Or-Skip "Do you want to install AWS CLI?")) { return }

    $url = 'https://awscli.amazonaws.com/AWSCLIV2.msi'
    $installer = "$env:TEMP\AWSCLIV2.msi"

    Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
    Start-Process msiexec.exe -ArgumentList "/i `"$installer`" /qn" -Wait
    Remove-Item $installer -Force
    Write-Host "AWS CLI installed."
}

function Install-AzureCLI {
    Write-Host "`n--- Azure CLI Installation ---"
    if (-not (Confirm-Or-Skip "Do you want to install Azure CLI?")) { return }

    $url = 'https://aka.ms/installazurecliwindowsx64'
    $installer = "$env:TEMP\AzureCLI.msi"

    Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
    Start-Process msiexec.exe -ArgumentList "/i `"$installer`" /quiet" -Wait
    Remove-Item $installer -Force
    Write-Host "Azure CLI installed."
}

function Install-GCloudCLI {
    Write-Host "`n--- Google Cloud CLI Installation ---"
    if (-not (Confirm-Or-Skip "Do you want to install Google Cloud CLI?")) { return }

    $url = 'https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe'
    $installer = "$env:TEMP\GoogleCloudSDKInstaller.exe"

    Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
    Start-Process -FilePath $installer -ArgumentList '/quiet' -Wait
    Remove-Item $installer -Force
    Write-Host "Google Cloud CLI installed."
}

# --- Main Execution ---

Write-Host "Cloud CLI Installer Script"
Write-Host "Note: This script must be run as Administrator." -ForegroundColor Yellow

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "You must run this script as Administrator. Exiting."
    exit 1
}

Install-AWSCLI
Install-AzureCLI
Install-GCloudCLI

Write-Host "`nAll selected CLI tools have been processed."
