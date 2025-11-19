# Azure CLI Installation Script for Windows
# Author: NimbusDFIR

param()

function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($user)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SystemArchitecture {
    $arch = [Environment]::Is64BitOperatingSystem
    if ($arch) {
        return "x64"
    } else {
        return "x86"
    }
}

if (-NOT (Test-Administrator)) {
    Write-Host "Administrator privileges required. Requesting elevation..." -ForegroundColor Yellow
    
    try {
        $scriptPath = $MyInvocation.MyCommand.Path
        $process = Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -PassThru
        $process.WaitForExit()
        Write-Host "Script completed." -ForegroundColor Green
        exit 0
    }
    catch {
        Write-Host "Failed to elevate privileges." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Azure CLI Installation Script" -ForegroundColor Blue
Write-Host "Running with administrator privileges" -ForegroundColor Green
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

function Install-AzureCLI-MSI {
    param([string]$installerPath)
    
    Write-Host "Attempting MSI installation..." -ForegroundColor Cyan
    
    $logPath = "$env:TEMP\AzureCLI_Install.log"
    
    try {
        Write-Host "Installing for all users..." -ForegroundColor Gray
        $arguments = @("/i", "`"$installerPath`"", "/quiet", "/norestart", "ALLUSERS=1", "/L*v", "`"$logPath`"")
        $process = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 1925 -or $process.ExitCode -eq 1603) {
            Write-Host "Retrying with per-user installation..." -ForegroundColor Yellow
            $logPath = "$env:TEMP\AzureCLI_Install_PerUser.log"
            $arguments = @("/i", "`"$installerPath`"", "/quiet", "/norestart", "ALLUSERS=2", "MSIINSTALLPERUSER=1", "/L*v", "`"$logPath`"")
            $process = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru -NoNewWindow
        }
        
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Host "MSI installation successful!" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "MSI installation failed with exit code: $($process.ExitCode)" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "MSI installation failed: $_" -ForegroundColor Red
        return $false
    }
}

function Install-AzureCLI-Winget {
    Write-Host "Attempting Winget installation..." -ForegroundColor Cyan
    
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        Write-Host "Winget not available on this system" -ForegroundColor Yellow
        return $false
    }
    
    try {
        # Winget automatically selects the correct architecture
        Write-Host "Installing via Windows Package Manager..." -ForegroundColor Gray
        $arguments = @("install", "Microsoft.AzureCLI", "--accept-package-agreements", "--accept-source-agreements", "--silent")
        $process = Start-Process winget -ArgumentList $arguments -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Winget installation successful!" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "Winget installation failed with exit code: $($process.ExitCode)" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "Winget installation error: $_" -ForegroundColor Red
        return $false
    }
}

# Main installation logic
$architecture = Get-SystemArchitecture
Write-Host "Detected system architecture: $architecture" -ForegroundColor Gray

# Set appropriate installer URL based on architecture
if ($architecture -eq "x64") {
    $installerUrl = "https://azcliprod.azureedge.net/msi/azure-cli-latest-x64.msi"
} else {
    $installerUrl = "https://azcliprod.azureedge.net/msi/azure-cli-latest-x86.msi"
}

$installerPath = "$env:TEMP\AzureCLI-$architecture.msi"
$installationSuccessful = $false



# Try installation methods in order of preference
Write-Host ""
Write-Host "Installing Azure CLI..." -ForegroundColor Cyan

# Method 1: Winget (preferred - modern package manager)
$installationSuccessful = Install-AzureCLI-Winget

# Method 2: MSI (fallback if Winget failed)
if (-not $installationSuccessful) {
    Write-Host ""
    Write-Host "Winget failed, trying MSI installer..." -ForegroundColor Yellow
    
    # Download appropriate MSI
    Write-Host "Downloading Azure CLI installer ($architecture)..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
        Write-Host "Download complete" -ForegroundColor Green
        
        $installationSuccessful = Install-AzureCLI-MSI -installerPath $installerPath
    }
    catch {
        Write-Host "Failed to download installer: $_" -ForegroundColor Red
    }
}

# Clean up installer file
if (Test-Path $installerPath) {
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
}

# Final verification
Write-Host ""
Write-Host "Verifying installation..." -ForegroundColor Cyan

# Refresh environment variables
Write-Host "Refreshing environment variables..." -ForegroundColor Gray
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')

# Also try to refresh the current session
try {
    $env:Path = $env:Path + ';C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin'
    $env:Path = $env:Path + ';C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin'
} catch { }

Start-Sleep -Seconds 3

$azCommand = Get-Command az -ErrorAction SilentlyContinue

# If not found in PATH, check common installation locations
if (-not $azCommand) {
    $commonPaths = @(
        "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd",
        "C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin\az.cmd",
        "$env:LOCALAPPDATA\Programs\Azure CLI\wbin\az.cmd"
    )
    
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            Write-Host "Found Azure CLI at: $path" -ForegroundColor Gray
            # Add to current session PATH
            $pathDir = Split-Path $path -Parent
            if ($env:Path -notlike "*$pathDir*") {
                $env:Path += ";$pathDir"
            }
            $azCommand = Get-Command az -ErrorAction SilentlyContinue
            break
        }
    }
}

if ($azCommand) {
    Write-Host "Azure CLI installed successfully!" -ForegroundColor Green
    Write-Host "Location: $($azCommand.Source)" -ForegroundColor Gray
    
    try {
        $azVersion = & az version --query 'azure-cli' -o tsv 2>$null
        if ($azVersion) {
            Write-Host "Version: $azVersion" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Version check failed but command is available" -ForegroundColor Yellow
    }
}
elseif ($installationSuccessful) {
    Write-Host "Installation completed!" -ForegroundColor Green
    Write-Host "Please restart your terminal to use the az command" -ForegroundColor Yellow
}
else {
    Write-Host "Installation failed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "MANUAL OPTIONS:" -ForegroundColor Yellow
    Write-Host "1. Download from: https://aka.ms/installazurecliwindows" -ForegroundColor White
    Write-Host "2. Use winget: winget install Microsoft.AzureCLI" -ForegroundColor White
    Write-Host ""
    Write-Host "Press any key to close..."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

Write-Host ""
Write-Host "To log in to Azure:" -ForegroundColor Cyan
Write-Host "  az login" -ForegroundColor White
Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green

Write-Host "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')