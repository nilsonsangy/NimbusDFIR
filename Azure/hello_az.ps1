# Azure Connection Test Script
# Author: NimbusDFIR
# Description: Tests Azure connection and displays account information

# Check if Azure CLI is installed
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Azure CLI is not installed" -ForegroundColor Red
    Write-Host ""
    Write-Host "To install Azure CLI on Windows, visit:"
    Write-Host "  https://aka.ms/installazurecliwindows" -ForegroundColor Green
    Write-Host ""
    Write-Host "Or use winget:"
    Write-Host "  winget install Microsoft.AzureCLI" -ForegroundColor Green
    exit 1
}

Write-Host "==========================================" -ForegroundColor Blue
Write-Host "Azure Connection Test - NimbusDFIR" -ForegroundColor Blue
Write-Host "==========================================" -ForegroundColor Blue
Write-Host ""

# Check if logged in
Write-Host "[INFO] Checking Azure authentication..." -ForegroundColor Blue
$accountCheck = az account show 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Not logged in to Azure" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please log in first:"
    Write-Host "  az login" -ForegroundColor Green
    exit 1
}

Write-Host "[SUCCESS] Azure connection successful!" -ForegroundColor Green
Write-Host ""

# Get account details
$accountName = az account show --query name -o tsv
$accountId = az account show --query id -o tsv
$tenantId = az account show --query tenantId -o tsv
$userName = az account show --query user.name -o tsv
$userType = az account show --query user.type -o tsv

Write-Host "Account Information:" -ForegroundColor Cyan
Write-Host "===================="
Write-Host "  Account Name: " -NoNewline
Write-Host "$accountName" -ForegroundColor Green
Write-Host "  Subscription ID: " -NoNewline
Write-Host "$accountId" -ForegroundColor Green
Write-Host "  Tenant ID: " -NoNewline
Write-Host "$tenantId" -ForegroundColor Green
Write-Host "  User: " -NoNewline
Write-Host "$userName" -ForegroundColor Green
Write-Host "  Type: " -NoNewline
Write-Host "$userType" -ForegroundColor Green
Write-Host ""

# List all subscriptions
Write-Host "Available Subscriptions:" -ForegroundColor Cyan
Write-Host "===================="
az account list --query "[].{Name:name, ID:id, State:state, IsDefault:isDefault}" -o table
Write-Host ""

# List available locations
Write-Host "Available Locations (Regions):" -ForegroundColor Cyan
Write-Host "===================="
$locations = az account list-locations --query "[].{Name:name, DisplayName:displayName}" -o json | ConvertFrom-Json
$locations | Select-Object -First 20 | Format-Table -AutoSize
Write-Host "... (showing first 20 regions)"
Write-Host ""

# Get Azure CLI version
$azVersion = az version --query '"azure-cli"' -o tsv
Write-Host "[INFO] Azure CLI Version: " -NoNewline -ForegroundColor Blue
Write-Host "$azVersion" -ForegroundColor Green
Write-Host ""

Write-Host "[SUCCESS] All checks completed successfully!" -ForegroundColor Green
