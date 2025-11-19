# MySQL Installation Script for Windows
# Author: NimbusDFIR
# Description: Automated MySQL installation with privilege elevation and PATH configuration

param(
    [switch]$Force,
    [switch]$Help
)

# Check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Request administrator privileges
function Request-AdminPrivileges {
    if (-not (Test-Administrator)) {
        Write-Host "Administrator privileges required. Requesting elevation..." -ForegroundColor Yellow
        
        $scriptPath = $PSCommandPath
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        
        if ($Force) { $arguments += " -Force" }
        
        try {
            Start-Process PowerShell -ArgumentList $arguments -Verb RunAs -Wait
            exit 0
        } catch {
            Write-Host "Error: Failed to obtain administrator privileges" -ForegroundColor Red
            Write-Host "Please run PowerShell as Administrator manually" -ForegroundColor Yellow
            exit 1
        }
    }
}

# Display help information
function Show-Help {
    Write-Host "===========================================" -ForegroundColor Blue
    Write-Host "MySQL Installation Script - NimbusDFIR" -ForegroundColor Blue
    Write-Host "===========================================" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Description:" -ForegroundColor Yellow
    Write-Host "  Installs MySQL Community Server on Windows with automatic configuration"
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\install_mysql_windows.ps1 [-Force] [-Help]"
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Yellow
    Write-Host "  -Force    : Force reinstallation if MySQL is already installed"
    Write-Host "  -Help     : Display this help information"
    Write-Host ""
    Write-Host "Features:" -ForegroundColor Yellow
    Write-Host "  - Automatic administrator privilege elevation"
    Write-Host "  - Winget package manager integration"
    Write-Host "  - MSI installer fallback option"
    Write-Host "  - Automatic PATH environment variable configuration"
    Write-Host "  - Installation verification"
    Write-Host ""
    Write-Host "Requirements:" -ForegroundColor Yellow
    Write-Host "  - Windows 10/11"
    Write-Host "  - Internet connection"
    Write-Host "  - Administrator privileges (auto-requested)"
    Write-Host ""
}

# Check if Winget is available
function Test-Winget {
    try {
        $null = Get-Command winget -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# Get system architecture
function Get-SystemArchitecture {
    $arch = (Get-WmiObject Win32_OperatingSystem).OSArchitecture
    return $arch
}

# Check if MySQL is already installed
function Test-MySQLInstalled {
    try {
        # Check via Winget
        $wingetList = winget list --id Oracle.MySQL 2>$null
        if ($LASTEXITCODE -eq 0 -and $wingetList -match "Oracle.MySQL") {
            return $true
        }
        
        # Check via registry/file system
        $mysqlPaths = @(
            "C:\Program Files\MySQL",
            "C:\Program Files (x86)\MySQL"
        )
        
        foreach ($path in $mysqlPaths) {
            if (Test-Path $path) {
                $mysqlDirs = Get-ChildItem -Path $path -Directory -Filter "*MySQL Server*" -ErrorAction SilentlyContinue
                if ($mysqlDirs) {
                    return $true
                }
            }
        }
        
        return $false
    } catch {
        return $false
    }
}

# Install MySQL via Winget
function Install-MySQL-Winget {
    Write-Host "Installing MySQL via Winget..." -ForegroundColor Yellow
    Write-Host ""
    
    try {
        # Install MySQL Community Server
        $result = winget install --id Oracle.MySQL --accept-package-agreements --accept-source-agreements --silent
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ MySQL installed successfully via Winget" -ForegroundColor Green
            return $true
        } else {
            Write-Host "✗ Winget installation failed (Exit code: $LASTEXITCODE)" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "✗ Winget installation failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Install MySQL via MSI (fallback)
function Install-MySQL-MSI {
    Write-Host "Installing MySQL via MSI installer..." -ForegroundColor Yellow
    Write-Host ""
    
    # Get the latest MySQL download URL
    $downloadUrl = "https://dev.mysql.com/get/Downloads/MySQLInstaller/mysql-installer-community-8.4.6.0.msi"
    $tempPath = "$env:TEMP\mysql-installer.msi"
    
    try {
        Write-Host "Downloading MySQL installer..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempPath -UseBasicParsing
        
        if (Test-Path $tempPath) {
            Write-Host "Running MySQL installer..." -ForegroundColor Yellow
            
            # Run MSI installer
            $installArgs = "/i `"$tempPath`" /quiet /norestart"
            $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
            
            if ($process.ExitCode -eq 0) {
                Write-Host "✓ MySQL installed successfully via MSI" -ForegroundColor Green
                Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                return $true
            } else {
                Write-Host "✗ MSI installation failed (Exit code: $($process.ExitCode))" -ForegroundColor Red
                Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                return $false
            }
        } else {
            Write-Host "✗ Failed to download MySQL installer" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "✗ MSI installation failed: $($_.Exception.Message)" -ForegroundColor Red
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        return $false
    }
}

# Find MySQL installation path
function Find-MySQLPath {
    $possiblePaths = @(
        "C:\Program Files\MySQL\MySQL Server 8.4\bin",
        "C:\Program Files\MySQL\MySQL Server 8.0\bin",
        "C:\Program Files\MySQL\MySQL Server 5.7\bin",
        "C:\Program Files (x86)\MySQL\MySQL Server 8.4\bin",
        "C:\Program Files (x86)\MySQL\MySQL Server 8.0\bin",
        "C:\Program Files (x86)\MySQL\MySQL Server 5.7\bin"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path "$path\mysql.exe") {
            return $path
        }
    }
    
    # Search dynamically
    $mysqlRoots = @(
        "C:\Program Files\MySQL",
        "C:\Program Files (x86)\MySQL"
    )
    
    foreach ($root in $mysqlRoots) {
        if (Test-Path $root) {
            $servers = Get-ChildItem -Path $root -Directory -Filter "*MySQL Server*" | Sort-Object Name -Descending
            foreach ($server in $servers) {
                $binPath = Join-Path $server.FullName "bin"
                if (Test-Path "$binPath\mysql.exe") {
                    return $binPath
                }
            }
        }
    }
    
    return $null
}

# Configure PATH environment variable
function Set-MySQLPath {
    param([string]$MySQLBinPath)
    
    Write-Host "Configuring PATH environment variable..." -ForegroundColor Yellow
    
    try {
        # Get current system PATH
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        
        # Check if MySQL is already in PATH
        if ($currentPath -split ';' | Where-Object { $_ -eq $MySQLBinPath }) {
            Write-Host "✓ MySQL is already in system PATH" -ForegroundColor Green
            return $true
        }
        
        # Add MySQL to system PATH
        $newPath = $currentPath + ";" + $MySQLBinPath
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
        
        # Update current session PATH
        $env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [Environment]::GetEnvironmentVariable("PATH", "User")
        
        Write-Host "✓ MySQL added to system PATH successfully" -ForegroundColor Green
        Write-Host "MySQL PATH: $MySQLBinPath" -ForegroundColor Cyan
        
        return $true
    } catch {
        Write-Host "✗ Failed to configure PATH: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Verify MySQL installation
function Test-MySQLInstallation {
    Write-Host "Verifying MySQL installation..." -ForegroundColor Yellow
    
    try {
        # Test mysql command
        $mysqlVersion = & mysql --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $mysqlVersion) {
            Write-Host "✓ MySQL client is working correctly" -ForegroundColor Green
            Write-Host "$mysqlVersion" -ForegroundColor Cyan
            return $true
        }
        
        # Try with full path if command not found
        $mysqlPath = Find-MySQLPath
        if ($mysqlPath) {
            $mysqlExe = Join-Path $mysqlPath "mysql.exe"
            $mysqlVersion = & $mysqlExe --version 2>$null
            if ($LASTEXITCODE -eq 0 -and $mysqlVersion) {
                Write-Host "✓ MySQL client found at: $mysqlPath" -ForegroundColor Green
                Write-Host "$mysqlVersion" -ForegroundColor Cyan
                return $true
            }
        }
        
        Write-Host "✗ MySQL client verification failed" -ForegroundColor Red
        return $false
    } catch {
        Write-Host "✗ MySQL verification failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main execution
function Main {
    Write-Host "===========================================" -ForegroundColor Blue
    Write-Host "MySQL Installation Script - NimbusDFIR" -ForegroundColor Blue
    Write-Host "===========================================" -ForegroundColor Blue
    Write-Host ""
    
    # Show help if requested
    if ($Help) {
        Show-Help
        return
    }
    
    # Request admin privileges
    Request-AdminPrivileges
    
    # System information
    Write-Host "System Information:" -ForegroundColor Yellow
    Write-Host "OS Architecture: $(Get-SystemArchitecture)" -ForegroundColor Cyan
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
    Write-Host ""
    
    # Check if MySQL is already installed
    if ((Test-MySQLInstalled) -and -not $Force) {
        Write-Host "MySQL is already installed" -ForegroundColor Green
        
        # Still configure PATH if needed
        $mysqlPath = Find-MySQLPath
        if ($mysqlPath) {
            Set-MySQLPath -MySQLBinPath $mysqlPath
            Test-MySQLInstallation
        }
        
        Write-Host ""
        Write-Host "Use -Force parameter to reinstall" -ForegroundColor Yellow
        return
    }
    
    $installSuccess = $false
    
    # Try Winget first
    if (Test-Winget) {
        Write-Host "Winget is available - using preferred installation method" -ForegroundColor Green
        Write-Host ""
        
        $installSuccess = Install-MySQL-Winget
    } else {
        Write-Host "Winget not available - using MSI installer" -ForegroundColor Yellow
        Write-Host ""
    }
    
    # Fallback to MSI if Winget failed
    if (-not $installSuccess) {
        Write-Host "Trying MSI installer as fallback..." -ForegroundColor Yellow
        $installSuccess = Install-MySQL-MSI
    }
    
    if ($installSuccess) {
        Write-Host ""
        Write-Host "Installation completed successfully!" -ForegroundColor Green
        Write-Host ""
        
        # Wait a moment for installation to complete
        Start-Sleep -Seconds 5
        
        # Configure PATH
        $mysqlPath = Find-MySQLPath
        if ($mysqlPath) {
            Set-MySQLPath -MySQLBinPath $mysqlPath
            Write-Host ""
            
            # Verify installation
            Test-MySQLInstallation
        } else {
            Write-Host "Warning: Could not locate MySQL installation path" -ForegroundColor Yellow
            Write-Host "You may need to manually add MySQL to your PATH" -ForegroundColor Yellow
        }
        
        Write-Host ""
        Write-Host "===========================================" -ForegroundColor Green
        Write-Host "MySQL Installation Complete!" -ForegroundColor Green
        Write-Host "===========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next Steps:" -ForegroundColor Yellow
        Write-Host "1. Restart your terminal/PowerShell for PATH changes to take effect" -ForegroundColor Cyan
        Write-Host "2. Configure MySQL server (run MySQL Installer for server setup)" -ForegroundColor Cyan
        Write-Host "3. Test connection: mysql -u root -p" -ForegroundColor Cyan
        Write-Host ""
        
    } else {
        Write-Host ""
        Write-Host "Installation failed!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Manual installation options:" -ForegroundColor Yellow
        Write-Host "1. Download from: https://dev.mysql.com/downloads/mysql/" -ForegroundColor Cyan
        Write-Host "2. Use MySQL Installer: https://dev.mysql.com/downloads/installer/" -ForegroundColor Cyan
        Write-Host ""
        exit 1
    }
}

# Execute main function
Main