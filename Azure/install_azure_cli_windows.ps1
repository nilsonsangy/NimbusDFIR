# Script to install Azure CLI on Windows
# Author: NimbusDFIR
# Description: Installs the latest Azure CLI for Windows using MSI installer

Write-Host "==========================================" -ForegroundColor Blue
Write-Host "Azure CLI Installation Script for Windows" -ForegroundColor Blue
Write-Host "==========================================" -ForegroundColor Blue
Write-Host ""

# Check if Azure CLI is already installed
$azInstalled = Get-Command az -ErrorAction SilentlyContinue

if ($azInstalled) {
    try {
        $currentVersion = (az version --query '"azure-cli"' -o tsv 2>$null)
        Write-Host "Azure CLI is already installed (version: $currentVersion)" -ForegroundColor Yellow
        $response = Read-Host "Do you want to reinstall/update? (y/n)"
        if ($response -notmatch '^[Yy]$') {
            Write-Host "Installation cancelled." -ForegroundColor Yellow
            exit 0
        }
    }
    catch {
        Write-Host "Azure CLI is already installed" -ForegroundColor Yellow
        $response = Read-Host "Do you want to reinstall/update? (y/n)"
        if ($response -notmatch '^[Yy]$') {
            Write-Host "Installation cancelled." -ForegroundColor Yellow
            exit 0
        }
    }
}

# Download URL for the latest Azure CLI MSI installer
$installerUrl = "https://aka.ms/installazurecliwindows"
$installerPath = "$env:TEMP\AzureCLI.msi"

Write-Host "Downloading Azure CLI installer..." -ForegroundColor Cyan
try {
    # Download the installer
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
    Write-Host "✓ Download complete" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to download Azure CLI installer" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

# Install Azure CLI
Write-Host ""
Write-Host "Installing Azure CLI..." -ForegroundColor Cyan
Write-Host "This may take a few minutes. Please wait..." -ForegroundColor Yellow

try {
    # Run the MSI installer silently
    $arguments = "/i `"$installerPath`" /quiet /norestart"
    $process = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
        Write-Host "✓ Installation completed successfully" -ForegroundColor Green
    }
    else {
        Write-Host "✗ Installation failed with exit code: $($process.ExitCode)" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "✗ Failed to install Azure CLI" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
finally {
    # Clean up installer file
    if (Test-Path $installerPath) {
        Remove-Item $installerPath -Force
    }
}

# Refresh environment variables
Write-Host ""
Write-Host "Refreshing environment variables..." -ForegroundColor Cyan
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# Verify installation
Write-Host ""
Write-Host "Verifying installation..." -ForegroundColor Cyan
Start-Sleep -Seconds 2

# Check if az command is available
$azCommand = Get-Command az -ErrorAction SilentlyContinue

if ($azCommand) {
    try {
        $azVersion = (az version --query '"azure-cli"' -o tsv 2>$null)
        Write-Host "✓ Azure CLI installed successfully!" -ForegroundColor Green
        Write-Host "Version: $azVersion" -ForegroundColor Green
    }
    catch {
        Write-Host "✓ Azure CLI installed successfully!" -ForegroundColor Green
        Write-Host "Note: Please restart your terminal to use the 'az' command" -ForegroundColor Yellow
    }
}
else {
    Write-Host "✓ Azure CLI installed successfully!" -ForegroundColor Green
    Write-Host "Note: Please restart your terminal to use the 'az' command" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "To log in to Azure, run:" -ForegroundColor Cyan
Write-Host "  az login" -ForegroundColor White
Write-Host ""
Write-Host "To configure default subscription, run:" -ForegroundColor Cyan
Write-Host "  az account set --subscription <subscription-id>" -ForegroundColor White
Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "IMPORTANT: You may need to restart your terminal or PowerShell window" -ForegroundColor Yellow
Write-Host "for the 'az' command to be available." -ForegroundColor Yellow
