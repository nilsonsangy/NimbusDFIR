#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Install or Uninstall Google Cloud CLI (gcloud) on Windows
.DESCRIPTION
    This script installs or uninstalls the Google Cloud CLI on Windows systems for the current user.
    It downloads the official installer and runs it with user-level installation (no admin required).
.PARAMETER Uninstall
    If specified, uninstalls Google Cloud CLI instead of installing it
.EXAMPLE
    .\install_gcloud_cli_windows.ps1
    Installs Google Cloud CLI for current user
.EXAMPLE
    .\install_gcloud_cli_windows.ps1 -Uninstall
    Uninstalls Google Cloud CLI
#>

param(
    [switch]$Uninstall
)

# Colors for output
$ErrorColor = "Red"
$SuccessColor = "Green"
$InfoColor = "Cyan"
$WarningColor = "Yellow"

function Write-Step {
    param([string]$Message)
    Write-Host "`n[INFO] $Message" -ForegroundColor $InfoColor
}

function Write-Command {
    param([string]$Command)
    Write-Host "[COMMAND] $Command" -ForegroundColor DarkCyan
}

if ($Uninstall) {
    Write-Host "==========================================" -ForegroundColor $InfoColor
    Write-Host "Google Cloud CLI Uninstaller" -ForegroundColor $InfoColor
    Write-Host "==========================================" -ForegroundColor $InfoColor
    
    Write-Step "Checking if Google Cloud CLI is installed..."
    
    # Check if gcloud exists
    $gcloudPath = Get-Command gcloud -ErrorAction SilentlyContinue
    
    if (-not $gcloudPath) {
        Write-Host "✓ Google Cloud CLI is not installed" -ForegroundColor $SuccessColor
        exit 0
    }
    
    Write-Host "Found Google Cloud CLI at: $($gcloudPath.Source)" -ForegroundColor $WarningColor
    
    # Find installation directory (user-level installation only)
    $installDir = $null
    $possiblePaths = @(
        "$env:LOCALAPPDATA\Google\Cloud SDK"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $installDir = $path
            break
        }
    }
    
    if ($installDir) {
        Write-Host "Installation directory: $installDir" -ForegroundColor $WarningColor
        Write-Host ""
        $confirm = Read-Host "Are you sure you want to uninstall Google Cloud CLI? (y/N)"
        
        if ($confirm -ne "y" -and $confirm -ne "Y") {
            Write-Host "Uninstallation cancelled" -ForegroundColor $WarningColor
            exit 0
        }
        
        Write-Step "Uninstalling Google Cloud CLI..."
        
        # Try to find and run uninstaller
        $uninstallerPath = Join-Path $installDir "uninstall.exe"
        
        if (Test-Path $uninstallerPath) {
            Write-Command "Start-Process -FilePath '$uninstallerPath' -ArgumentList '/S' -Wait"
            Start-Process -FilePath $uninstallerPath -ArgumentList "/S" -Wait -NoNewWindow
        } else {
            Write-Host "Uninstaller not found, removing directory manually..." -ForegroundColor $WarningColor
            Write-Command "Remove-Item -Path '$installDir' -Recurse -Force"
            Remove-Item -Path $installDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Remove from PATH
        Write-Step "Removing from PATH..."
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        
        $binPath = Join-Path $installDir "bin"
        
        if ($userPath -like "*$binPath*") {
            $newUserPath = ($userPath -split ';' | Where-Object { $_ -notlike "*Google*Cloud SDK*" }) -join ';'
            Write-Command "[Environment]::SetEnvironmentVariable('Path', '$newUserPath', 'User')"
            [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        }
        
        if ($machinePath -like "*$binPath*") {
            $newMachinePath = ($machinePath -split ';' | Where-Object { $_ -notlike "*Google*Cloud SDK*" }) -join ';'
            Write-Command "[Environment]::SetEnvironmentVariable('Path', '$newMachinePath', 'Machine')"
            [Environment]::SetEnvironmentVariable("Path", $newMachinePath, "Machine")
        }
        
        Write-Host ""
        Write-Host "✓ Google Cloud CLI uninstalled successfully" -ForegroundColor $SuccessColor
        Write-Host "Note: You may need to restart your terminal for PATH changes to take effect" -ForegroundColor $WarningColor
    } else {
        Write-Host "Could not find Google Cloud CLI installation directory" -ForegroundColor $ErrorColor
        exit 1
    }
    
    exit 0
}

# Installation process
Write-Host "==========================================" -ForegroundColor $InfoColor
Write-Host "Google Cloud CLI Installer for Windows" -ForegroundColor $InfoColor
Write-Host "==========================================" -ForegroundColor $InfoColor

# Check if already installed
Write-Step "Checking if Google Cloud CLI is already installed..."
$gcloudExists = Get-Command gcloud -ErrorAction SilentlyContinue

if ($gcloudExists) {
    Write-Host "Google Cloud CLI is already installed at: $($gcloudExists.Source)" -ForegroundColor $WarningColor
    Write-Command "gcloud version"
    gcloud version
    Write-Host ""
    $reinstall = Read-Host "Do you want to reinstall? (y/N)"
    if ($reinstall -ne "y" -and $reinstall -ne "Y") {
        Write-Host "Installation cancelled" -ForegroundColor $WarningColor
        exit 0
    }
}

# Create temporary directory
$tempDir = Join-Path $env:TEMP "gcloud_installer"
Write-Step "Creating temporary directory: $tempDir"
Write-Command "New-Item -ItemType Directory -Path '$tempDir' -Force"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Download URL
$installerUrl = "https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe"
$installerPath = Join-Path $tempDir "GoogleCloudSDKInstaller.exe"

Write-Step "Downloading Google Cloud CLI installer..."
Write-Host "URL: $installerUrl" -ForegroundColor DarkGray
Write-Command "Invoke-WebRequest -Uri '$installerUrl' -OutFile '$installerPath'"

try {
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
    Write-Host "✓ Download completed" -ForegroundColor $SuccessColor
}
catch {
    Write-Host "✗ Failed to download installer: $_" -ForegroundColor $ErrorColor
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# Verify download
if (-not (Test-Path $installerPath)) {
    Write-Host "✗ Installer file not found after download" -ForegroundColor $ErrorColor
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Step "Installing Google Cloud CLI for current user..."
Write-Host "This may take a few minutes..." -ForegroundColor $WarningColor
Write-Host "Installation will be at: $env:LOCALAPPDATA\Google\Cloud SDK" -ForegroundColor DarkGray
Write-Command "Start-Process -FilePath '$installerPath' -ArgumentList '/S', '/allusers=0', '/D=$env:LOCALAPPDATA\Google\Cloud SDK' -Wait"

try {
    # Run installer silently for current user only
    # /S = Silent mode
    # /allusers=0 = Install for current user only (no admin needed)
    # /D= = Installation directory
    $installPath = "$env:LOCALAPPDATA\Google\Cloud SDK"
    Start-Process -FilePath $installerPath -ArgumentList "/S", "/allusers=0", "/D=$installPath" -Wait -NoNewWindow
    Write-Host "✓ Installation completed" -ForegroundColor $SuccessColor
}
catch {
    Write-Host "✗ Installation failed: $_" -ForegroundColor $ErrorColor
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# Clean up
Write-Step "Cleaning up temporary files..."
Write-Command "Remove-Item -Path '$tempDir' -Recurse -Force"
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "==========================================" -ForegroundColor $SuccessColor
Write-Host "✓ Google Cloud CLI installed successfully!" -ForegroundColor $SuccessColor
Write-Host "==========================================" -ForegroundColor $SuccessColor
Write-Host ""
Write-Host "Next steps:" -ForegroundColor $InfoColor
Write-Host "  1. Restart your terminal to refresh PATH" -ForegroundColor White
Write-Host "  2. Run: gcloud init" -ForegroundColor White
Write-Host "  3. Authenticate with: gcloud auth login" -ForegroundColor White
Write-Host ""
Write-Host "To verify installation, run:" -ForegroundColor $InfoColor
Write-Host "  gcloud version" -ForegroundColor White
Write-Host ""
