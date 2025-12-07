# AWS CLI Installation Script for Windows
# Author: NimbusDFIR
# Usage: .\install_aws_cli_windows.ps1 [-Uninstall]

param(
    [switch]$Uninstall
)

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

function Uninstall-AWSCLI {
    Write-Host "AWS CLI Uninstallation Script" -ForegroundColor Yellow
    Write-Host "Running with administrator privileges" -ForegroundColor Green
    Write-Host ""
    
    # Try uninstall via winget first
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Write-Host "[Command] winget uninstall Amazon.AWSCLI --silent" -ForegroundColor DarkCyan
        try {
            $process = Start-Process winget -ArgumentList @("uninstall", "Amazon.AWSCLI", "--silent") -Wait -PassThru -NoNewWindow
            if ($process.ExitCode -eq 0) {
                Write-Host "AWS CLI uninstalled via winget." -ForegroundColor Green
                exit 0
            }
        } catch {
            Write-Host "Winget uninstall failed, trying MSI method..." -ForegroundColor Yellow
        }
    }
    
    # Try MSI uninstall
    Write-Host "[Command] Get-WmiObject -Class Win32_Product | Where-Object { `$_.Name -like '*AWS Command Line*' } | ForEach-Object { `$_.Uninstall() }" -ForegroundColor DarkCyan
    $awsProducts = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like '*AWS Command Line*' }
    if ($awsProducts) {
        foreach ($product in $awsProducts) {
            Write-Host "Uninstalling: $($product.Name)" -ForegroundColor Gray
            $product.Uninstall() | Out-Null
        }
        Write-Host "AWS CLI uninstalled successfully." -ForegroundColor Green
    } else {
        Write-Host "AWS CLI installation not found via Windows Installer." -ForegroundColor Yellow
        
        # Manual cleanup
        $awsPath = "$env:ProgramFiles\Amazon\AWSCLIV2"
        if (Test-Path $awsPath) {
            Write-Host "[Command] Remove-Item -Recurse -Force '$awsPath'" -ForegroundColor DarkCyan
            Remove-Item -Recurse -Force $awsPath
            Write-Host "Removed AWS CLI directory." -ForegroundColor Green
        }
        
        # Remove from PATH
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        if ($userPath -like "*Amazon\AWSCLIV2*" -or $machinePath -like "*Amazon\AWSCLIV2*") {
            Write-Host "Cleaning PATH environment variable..." -ForegroundColor Gray
            $userPath = ($userPath -split ';' | Where-Object { $_ -notlike "*Amazon\AWSCLIV2*" }) -join ';'
            $machinePath = ($machinePath -split ';' | Where-Object { $_ -notlike "*Amazon\AWSCLIV2*" }) -join ';'
            [Environment]::SetEnvironmentVariable('Path', $userPath, 'User')
            [Environment]::SetEnvironmentVariable('Path', $machinePath, 'Machine')
            Write-Host "PATH cleaned." -ForegroundColor Green
        }
    }
    
    Write-Host "Uninstall complete." -ForegroundColor Green
    exit 0
}

if ($Uninstall) {
    if (-NOT (Test-Administrator)) {
        Write-Host "Administrator privileges required. Requesting elevation..." -ForegroundColor Yellow
        try {
            $scriptPath = $MyInvocation.MyCommand.Path
            Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Uninstall" -Wait
            exit 0
        } catch {
            Write-Host "Failed to elevate privileges." -ForegroundColor Red
            exit 1
        }
    }
    Uninstall-AWSCLI
}

Write-Host "AWS CLI Installation Script" -ForegroundColor Blue
Write-Host "Running with administrator privileges" -ForegroundColor Green
Write-Host ""

# Check if AWS CLI is already installed
$awsInstalled = Get-Command aws -ErrorAction SilentlyContinue

if ($awsInstalled) {
    try {
        $currentVersion = (aws --version 2>$null)
        Write-Host "AWS CLI is already installed: $currentVersion" -ForegroundColor Yellow
        $response = Read-Host "Do you want to reinstall/update? (y/n)"
        if ($response -notmatch '^[Yy]$') {
            Write-Host "Installation cancelled." -ForegroundColor Yellow
            exit 0
        }
    }
    catch {
        Write-Host "AWS CLI is already installed" -ForegroundColor Yellow
        $response = Read-Host "Do you want to reinstall/update? (y/n)"
        if ($response -notmatch '^[Yy]$') {
            Write-Host "Installation cancelled." -ForegroundColor Yellow
            exit 0
        }
    }
}

function Install-AWSCLI-MSI {
    param([string]$installerPath)
    
    Write-Host "Attempting MSI installation..." -ForegroundColor Cyan
    
    $logPath = "$env:TEMP\AWSCLI_Install.log"
    
    try {
        Write-Host "Installing AWS CLI..." -ForegroundColor Gray
        $arguments = @("/i", "`"$installerPath`"", "/quiet", "/norestart", "/L*v", "`"$logPath`"")
        $process = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru -NoNewWindow
        
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

function Install-AWSCLI-Winget {
    Write-Host "Attempting Winget installation..." -ForegroundColor Cyan
    
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        Write-Host "Winget not available on this system" -ForegroundColor Yellow
        return $false
    }
    
    try {
        # Winget automatically selects the correct architecture
        Write-Host "Installing via Windows Package Manager..." -ForegroundColor Gray
        $arguments = @("install", "Amazon.AWSCLI", "--accept-package-agreements", "--accept-source-agreements", "--silent")
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

# Set appropriate installer URL based on architecture (always latest version)
if ($architecture -eq "x64") {
    # AWS CLI v2 latest for 64-bit systems
    $installerUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
    Write-Host "Targeting AWS CLI v2 (latest) for 64-bit system" -ForegroundColor Gray
} else {
    # AWS CLI v2 only supports 64-bit, fallback to latest v1 for 32-bit
    Write-Host "Note: AWS CLI v2 requires 64-bit system. Installing latest v1 for 32-bit compatibility." -ForegroundColor Yellow
    $installerUrl = "https://s3.amazonaws.com/aws-cli/AWSCLI32PY3.msi"
}

$installerPath = "$env:TEMP\AWSCLI-$architecture.msi"
$installationSuccessful = $false

# Try installation methods in order of preference
Write-Host ""
Write-Host "Installing AWS CLI..." -ForegroundColor Cyan

# Method 1: Winget (preferred - modern package manager)
$installationSuccessful = Install-AWSCLI-Winget

# Method 2: MSI (fallback if Winget failed)
if (-not $installationSuccessful) {
    Write-Host ""
    Write-Host "Winget failed, trying MSI installer..." -ForegroundColor Yellow
    
    # Download appropriate MSI
    Write-Host "Downloading AWS CLI installer ($architecture)..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
        Write-Host "Download complete" -ForegroundColor Green
        
        $installationSuccessful = Install-AWSCLI-MSI -installerPath $installerPath
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
    $env:Path = $env:Path + ';C:\Program Files\Amazon\AWSCLIV2'
    $env:Path = $env:Path + ';C:\Program Files (x86)\Amazon\AWSCLI'
} catch { }

Start-Sleep -Seconds 3

$awsCommand = Get-Command aws -ErrorAction SilentlyContinue

# If not found in PATH, check common installation locations
if (-not $awsCommand) {
    $commonPaths = @(
        "C:\Program Files\Amazon\AWSCLIV2\aws.exe",
        "C:\Program Files (x86)\Amazon\AWSCLI\aws.exe",
        "$env:LOCALAPPDATA\Programs\Amazon\AWSCLI\aws.exe"
    )
    
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            Write-Host "Found AWS CLI at: $path" -ForegroundColor Gray
            # Add to current session PATH
            $pathDir = Split-Path $path -Parent
            if ($env:Path -notlike "*$pathDir*") {
                $env:Path += ";$pathDir"
            }
            $awsCommand = Get-Command aws -ErrorAction SilentlyContinue
            break
        }
    }
}

if ($awsCommand) {
    Write-Host "AWS CLI installed successfully!" -ForegroundColor Green
    Write-Host "Location: $($awsCommand.Source)" -ForegroundColor Gray
    
    try {
        $awsVersion = & aws --version 2>&1
        if ($awsVersion) {
            Write-Host "Version: $awsVersion" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Version check failed but command is available" -ForegroundColor Yellow
    }
}
elseif ($installationSuccessful) {
    Write-Host "Installation completed!" -ForegroundColor Green
    Write-Host "Please restart your terminal to use the aws command" -ForegroundColor Yellow
}
else {
    Write-Host "Installation failed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "MANUAL OPTIONS:" -ForegroundColor Yellow
    Write-Host "1. Download from: https://aws.amazon.com/cli/" -ForegroundColor White
    Write-Host "2. Use winget: winget install Amazon.AWSCLI" -ForegroundColor White
    Write-Host "3. Use Chocolatey: choco install awscli" -ForegroundColor White
    Write-Host ""
    Write-Host "Press any key to close..."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Cyan
Write-Host "1. Configure AWS credentials:" -ForegroundColor White
Write-Host "   aws configure" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Test connection:" -ForegroundColor White
Write-Host "   aws sts get-caller-identity" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Check for updates:" -ForegroundColor White
Write-Host "   aws --version" -ForegroundColor Gray
Write-Host ""
Write-Host "Installation complete! (Always installs latest available version)" -ForegroundColor Green

Write-Host "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')