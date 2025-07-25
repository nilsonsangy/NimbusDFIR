# PowerShell script to set up Python environment and install dependencies for the project
# Also checks and installs AWS CLI, Azure CLI, and GCP CLI if not present
# Usage: Run this script from the project root

# Create Python virtual environment in 'venv' folder
python -m venv venv

# Activate the virtual environment
$venvPath = Join-Path $PSScriptRoot 'venv'
$activateScript = Join-Path $venvPath 'Scripts\Activate.ps1'
. $activateScript

# Check and install AWS CLI
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Host 'AWS CLI not found. Installing...'
    $awsInstaller = 'https://awscli.amazonaws.com/AWSCLIV2.msi'
    $awsInstallerPath = "$env:TEMP\AWSCLIV2.msi"
    Invoke-WebRequest -Uri $awsInstaller -OutFile $awsInstallerPath -UseBasicParsing
    Start-Process msiexec.exe -ArgumentList "/i $awsInstallerPath /qn" -Wait
    Remove-Item $awsInstallerPath
    Write-Host 'AWS CLI installed.'
} else {
    Write-Host 'AWS CLI already installed.'
}

# Check and install Azure CLI
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host 'Azure CLI not found. Installing...'
    $azureInstaller = 'https://aka.ms/installazurecliwindows'
    $azureInstallerPath = "$env:TEMP\AzureCLI.msi"
    Invoke-WebRequest -Uri $azureInstaller -OutFile $azureInstallerPath -UseBasicParsing
    Start-Process msiexec.exe -ArgumentList "/i $azureInstallerPath /qn" -Wait
    Remove-Item $azureInstallerPath
    Write-Host 'Azure CLI installed.'
} else {
    Write-Host 'Azure CLI already installed.'
}

# Check and install GCP CLI (gcloud)
if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    Write-Host 'GCP CLI not found. Installing...'
    $gcpInstaller = 'https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe'
    $gcpInstallerPath = "$env:TEMP\GoogleCloudSDKInstaller.exe"
    Invoke-WebRequest -Uri $gcpInstaller -OutFile $gcpInstallerPath -UseBasicParsing
    Start-Process -FilePath $gcpInstallerPath -ArgumentList '/quiet' -Wait
    Remove-Item $gcpInstallerPath
    Write-Host 'GCP CLI installed.'
} else {
    Write-Host 'GCP CLI already installed.'
}

# Install dependencies from requirements.txt (must already exist)
pip install -r requirements.txt

Write-Host 'Python environment setup complete. Dependencies installed.'
