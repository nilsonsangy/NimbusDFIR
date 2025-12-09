#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Test GCP (Google Cloud Platform) connectivity and authentication
.DESCRIPTION
    This script verifies that gcloud CLI is installed, authenticated, and can connect to GCP.
    It displays basic information about your GCP environment.
.EXAMPLE
    .\hello_gcp.ps1
#>

Write-Host "==========================================" -ForegroundColor Blue
Write-Host "Hello GCP - Connection Test" -ForegroundColor Blue
Write-Host "==========================================" -ForegroundColor Blue
Write-Host ""

# Check if gcloud CLI is installed
Write-Host "[1/4] Checking if gcloud CLI is installed..." -ForegroundColor Cyan
try {
    $gcloudVersion = gcloud version --format="value(core.version)" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ gcloud CLI is installed (version: $gcloudVersion)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ gcloud CLI is not installed" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please install gcloud CLI first:" -ForegroundColor Yellow
        Write-Host "  Run: .\install_gcloud_cli_windows.ps1" -ForegroundColor Cyan
        exit 1
    }
}
catch {
    Write-Host "  ✗ gcloud CLI is not installed" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install gcloud CLI first:" -ForegroundColor Yellow
    Write-Host "  Run: .\install_gcloud_cli_windows.ps1" -ForegroundColor Cyan
    exit 1
}

# Check authentication
Write-Host ""
Write-Host "[2/4] Checking GCP authentication..." -ForegroundColor Cyan
$account = gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>$null
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($account)) {
    Write-Host "  ✓ Authenticated as: $account" -ForegroundColor Green
} else {
    Write-Host "  ✗ Not authenticated to GCP" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please authenticate:" -ForegroundColor Yellow
    Write-Host "  Run: gcloud auth login" -ForegroundColor Cyan
    exit 1
}

# Check project configuration
Write-Host ""
Write-Host "[3/4] Checking GCP project configuration..." -ForegroundColor Cyan
$project = gcloud config get-value project 2>$null
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($project) -and $project -ne "(unset)") {
    Write-Host "  ✓ Active project: $project" -ForegroundColor Green
} else {
    Write-Host "  ✗ No project configured" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please set a project:" -ForegroundColor Yellow
    Write-Host "  Run: gcloud config set project YOUR_PROJECT_ID" -ForegroundColor Cyan
    exit 1
}

# Test API connectivity
Write-Host ""
Write-Host "[4/4] Testing GCP API connectivity..." -ForegroundColor Cyan
$projectInfo = gcloud projects describe $project --format="json" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ Successfully connected to GCP" -ForegroundColor Green
    
    # Parse project info
    $projectData = $projectInfo | ConvertFrom-Json
    Write-Host ""
    Write-Host "Project Details:" -ForegroundColor Cyan
    Write-Host "  Name:        $($projectData.name)" -ForegroundColor White
    Write-Host "  Project ID:  $($projectData.projectId)" -ForegroundColor White
    Write-Host "  Number:      $($projectData.projectNumber)" -ForegroundColor White
    Write-Host "  State:       $($projectData.lifecycleState)" -ForegroundColor White
} else {
    Write-Host "  ✗ Failed to connect to GCP" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please check your network connection and try again" -ForegroundColor Yellow
    exit 1
}

# Get current configuration
Write-Host ""
Write-Host "Current Configuration:" -ForegroundColor Cyan
$region = gcloud config get-value compute/region 2>$null
$zone = gcloud config get-value compute/zone 2>$null

if (-not [string]::IsNullOrWhiteSpace($region) -and $region -ne "(unset)") {
    Write-Host "  Default Region: $region" -ForegroundColor White
} else {
    Write-Host "  Default Region: Not set" -ForegroundColor Gray
}

if (-not [string]::IsNullOrWhiteSpace($zone) -and $zone -ne "(unset)") {
    Write-Host "  Default Zone:   $zone" -ForegroundColor White
} else {
    Write-Host "  Default Zone:   Not set" -ForegroundColor Gray
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "✓ GCP Connection Test Passed!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "You are ready to use GCP services!" -ForegroundColor White
Write-Host ""
