# Azure MySQL Dump Database Script - PowerShell Version
# Author: NimbusDFIR
# Description: Dump database from Azure MySQL Flexible Server

param(
    [Parameter(Position=0)]
    [string]$ServerName,
    
    [Parameter(Position=1)]
    [string]$DatabaseName,
    
    [Parameter(Position=2)]
    [string]$OutputPath,
    
    [Parameter()]
    [switch]$Help
)

# Check if Azure CLI is installed
function Test-AzureCLI {
    $azCmd = Get-Command az -ErrorAction SilentlyContinue
    if (-not $azCmd) {
        Write-Host "Error: Azure CLI is not installed" -ForegroundColor Red
        Write-Host "Please install Azure CLI first"
        exit 1
    }
}

# Check if MySQL client is installed
function Test-MySQLClient {
    $mysqlCmd = Get-Command mysqldump -ErrorAction SilentlyContinue
    if (-not $mysqlCmd) {
        # Try common MySQL paths if not in PATH
        $commonPaths = @(
            "C:\Program Files\MySQL\MySQL Server 8.4\bin\mysqldump.exe",
            "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqldump.exe",
            "C:\Program Files (x86)\MySQL\MySQL Server 8.4\bin\mysqldump.exe",
            "C:\Program Files (x86)\MySQL\MySQL Server 8.0\bin\mysqldump.exe"
        )
        
        $mysqldumpFound = $false
        foreach ($path in $commonPaths) {
            if (Test-Path $path) {
                $pathDir = Split-Path $path -Parent
                $env:PATH += ";$pathDir"
                $mysqldumpFound = $true
                break
            }
        }
        
        if (-not $mysqldumpFound) {
            Write-Host "Error: MySQL client (mysqldump) is not installed" -ForegroundColor Red
            Write-Host "Please install MySQL client first"
            Write-Host "Windows: Download from https://dev.mysql.com/downloads/mysql/"
            Write-Host "Or use: winget install Oracle.MySQL"
            exit 1
        }
    }
}

# Check if logged in to Azure
function Test-AzureLogin {
    try {
        $null = az account show 2>$null
    }
    catch {
        Write-Host "Error: Not logged in to Azure" -ForegroundColor Red
        Write-Host "Please run: az login"
        exit 1
    }
}

# Display usage information
function Show-Usage {
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "Azure MySQL Dump Database - NimbusDFIR"
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Usage: .\mysql_dump_database.ps1 [SERVER_NAME] [DATABASE_NAME] [OUTPUT_PATH]"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\mysql_dump_database.ps1                              # Interactive mode"
    Write-Host "  .\mysql_dump_database.ps1 my-server testdb             # Direct mode"
    Write-Host "  .\mysql_dump_database.ps1 my-server testdb C:\backups  # With custom path"
    Write-Host ""
    Write-Host "Features:"
    Write-Host "  - Auto-detects existing SSH tunnels"
    Write-Host "  - Lists available databases for selection"
    Write-Host "  - Saves to Downloads folder by default"
    Write-Host "  - Generates timestamped dump files"
    Write-Host ""
}

# Check for active SSH tunnel
function Test-SSHTunnel {
    Write-Host "Checking for active SSH tunnel..." -ForegroundColor Blue
    
    # Check if there's an SSH process running with MySQL tunnel
    $sshProcesses = Get-Process -Name "ssh" -ErrorAction SilentlyContinue | Where-Object { 
        $_.ProcessName -eq "ssh" 
    }
    
    $tunnelActive = $false
    $localPort = 3307  # Default tunnel port
    
    if ($sshProcesses) {
        # Check if port 3307 is listening (typical MySQL tunnel port)
        try {
            $tcpConnection = Get-NetTCPConnection -LocalPort $localPort -State Listen -ErrorAction SilentlyContinue
            if ($tcpConnection) {
                $tunnelActive = $true
                Write-Host "✓ Active SSH tunnel detected on port $localPort" -ForegroundColor Green
                return @{
                    Active = $true
                    Port = $localPort
                }
            }
        }
        catch {
            # Port check failed, no tunnel
        }
    }
    
    Write-Host "✗ No active SSH tunnel found" -ForegroundColor Yellow
    Write-Host "Please run mysql_connect.ps1 first to establish tunnel, then run this script" -ForegroundColor Yellow
    Write-Host "Or use this script independently (will prompt for server selection)" -ForegroundColor Cyan
    Write-Host ""
    
    return @{
        Active = $false
        Port = $localPort
    }
}

# Get Azure MySQL server name for tunnel connection
function Get-TunnelServerName {
    Write-Host "Detecting Azure MySQL server name..." -ForegroundColor Blue
    
    # Get all Azure MySQL flexible servers and pick the first available one
    try {
        $servers = az mysql flexible-server list --query "[].name" -o tsv 2>$null
        
        if ($servers) {
            $serverList = $servers -split "`n" | Where-Object { $_.Trim() -ne "" }
            
            if ($serverList.Count -gt 0) {
                # Use the first server found (most likely the one being used for the tunnel)
                $serverName = $serverList[0].Trim()
                Write-Host "✓ Auto-detected Azure MySQL server: $serverName" -ForegroundColor Green
                return $serverName
            }
        }
    }
    catch {
        # Azure CLI failed, use generic name
    }
    
    # Fallback: use generic Azure server name
    Write-Host "⚠ Could not auto-detect server name, using generic name" -ForegroundColor Yellow
    return "azure-mysql-flexible-server"
}

# List available MySQL servers
function Get-MySQLServers {
    Write-Host "Available MySQL Servers:" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        $servers = az mysql flexible-server list --output json | ConvertFrom-Json
        
        if ($servers.Count -eq 0) {
            Write-Host "No MySQL flexible servers found" -ForegroundColor Yellow
            exit 0
        }
        
        for ($i = 0; $i -lt $servers.Count; $i++) {
            $server = $servers[$i]
            Write-Host "$($i + 1). $($server.name) ($($server.resourceGroup) - $($server.state))"
        }
        Write-Host ""
        
        return $servers
    }
    catch {
        Write-Host "Error retrieving MySQL servers: $_" -ForegroundColor Red
        exit 1
    }
}

# Get server information
function Get-ServerInfo {
    param([string]$ServerName)
    
    try {
        $serverInfo = az mysql flexible-server list --query "[?name=='$ServerName']" -o json | ConvertFrom-Json
        
        if ($serverInfo.Count -eq 0) {
            Write-Host "Error: MySQL server '$ServerName' not found" -ForegroundColor Red
            exit 1
        }
        
        $server = $serverInfo[0]
        Write-Host "✓ Server found in resource group: $($server.resourceGroup)" -ForegroundColor Green
        
        return @{
            Name = $server.name
            ResourceGroup = $server.resourceGroup
            Status = $server.state
        }
    }
    catch {
        Write-Host "Error getting server information: $_" -ForegroundColor Red
        exit 1
    }
}

# List databases via tunnel
function Get-DatabasesViaTunnel {
    param($Username, $Password, $LocalPort)
    
    Write-Host "Listing databases via SSH tunnel..." -ForegroundColor Blue
    
    # Use environment variable for secure password handling
    $env:MYSQL_PWD = $Password
    try {
        # Execute the mysql command and capture output as string
        $rawOutput = & mysql -h 127.0.0.1 -P $LocalPort -u $Username -e "SHOW DATABASES;" 2>$null | Out-String
        
        if ($LASTEXITCODE -eq 0 -and $rawOutput) {
            # System databases to exclude
            $systemDbs = @("Database", "information_schema", "performance_schema", "mysql", "sys")
            
            # Split by lines and filter
            $allLines = $rawOutput -split "`r?`n"
            $userDatabases = @()
            
            foreach ($line in $allLines) {
                $dbName = $line.Trim()
                if ($dbName -and $dbName -notin $systemDbs -and $dbName -ne "") {
                    $userDatabases += $dbName
                }
            }
            
            return $userDatabases
        }
        
        Write-Host "Error: Failed to connect to MySQL via tunnel" -ForegroundColor Red
        return @()
    }
    finally {
        Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
    }
}

# List databases via Azure CLI
function Get-DatabasesViaAzureCLI {
    param($ServerName, $ResourceGroup)
    
    Write-Host "Listing databases via Azure CLI..." -ForegroundColor Blue
    
    try {
        $databases = az mysql flexible-server db list --resource-group $ResourceGroup --server-name $ServerName --query "[].name" -o tsv
        
        if ($databases) {
            return $databases -split "`n" | Where-Object { $_.Trim() -ne "" }
        } else {
            Write-Host "Error: No databases found" -ForegroundColor Red
            return $null
        }
    }
    catch {
        Write-Host "Error retrieving databases: $_" -ForegroundColor Red
        return $null
    }
}

# Perform database dump via tunnel
function Invoke-DumpViaTunnel {
    param($Username, $Password, $DatabaseName, $LocalPort, $OutputFile, $ServerName)
    
    Write-Host "Creating database dump via SSH tunnel..." -ForegroundColor Green
    
    # Use environment variable for secure password handling
    $env:MYSQL_PWD = $Password
    try {
        # Create dump with custom header comment
        $tempFile = [System.IO.Path]::GetTempFileName()
        
        # Create mysqldump and then modify the header
        & mysqldump -h 127.0.0.1 -P $LocalPort -u $Username --single-transaction --routines --triggers $DatabaseName > $tempFile
        
        if ($LASTEXITCODE -eq 0) {
            # Read the dump file and replace the host information
            $content = Get-Content $tempFile -Raw
            
            # Replace the host line to show the actual Azure server name
            $content = $content -replace "-- Host: 127\.0\.0\.1", "-- Host: $ServerName (via SSH tunnel from 127.0.0.1)"
            
            # Write the modified content to the output file
            Set-Content -Path $OutputFile -Value $content -Encoding UTF8
            
            # Clean up temp file
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            
            return $true
        } else {
            Write-Host "Error: mysqldump failed" -ForegroundColor Red
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            return $false
        }
    }
    finally {
        Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
    }
}

# Perform database dump via Azure CLI
function Invoke-DumpViaAzureCLI {
    param($ServerName, $Username, $Password, $DatabaseName, $OutputFile)
    
    Write-Host "Creating database dump via Azure CLI..." -ForegroundColor Green
    
    try {
        # Azure CLI doesn't have direct dump capability, so we'll use mysql client if available
        Write-Host "Note: Azure CLI doesn't support direct database dumps" -ForegroundColor Yellow
        Write-Host "Please use SSH tunnel method for full dump functionality" -ForegroundColor Yellow
        return $false
    }
    catch {
        Write-Host "Error: Dump via Azure CLI not supported" -ForegroundColor Red
        return $false
    }
}

# Main script execution
try {
    if ($Help) {
        Show-Usage
        exit 0
    }
    
    # Check prerequisites
    Test-AzureCLI
    Test-MySQLClient
    Test-AzureLogin
    
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "Azure MySQL Dump Database"
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host ""
    
    # Check for active SSH tunnel
    $tunnelInfo = Test-SSHTunnel
    
    # Get credentials first
    Write-Host "Enter MySQL credentials:" -ForegroundColor Blue
    $dbUsername = Read-Host "Enter MySQL admin username (default: mysqladmin)"
    if (-not $dbUsername) {
        $dbUsername = "mysqladmin"
    }
    
    $dbPassword = Read-Host "Enter MySQL admin password" -AsSecureString
    $dbPasswordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($dbPassword))
    
    if (-not $dbPasswordPlain) {
        Write-Host "Error: Password is required" -ForegroundColor Red
        exit 1
    }
    
    # Get server and database information
    $serverInfo = $null
    $databases = $null
    
    if ($tunnelInfo.Active) {
        Write-Host "Using existing SSH tunnel for database operations" -ForegroundColor Green
        Write-Host ""
        
        # Get server name for tunnel connection
        $tunnelServerName = Get-TunnelServerName -Username $dbUsername -Password $dbPasswordPlain -LocalPort $tunnelInfo.Port
        
        # List databases via tunnel
        $databases = Get-DatabasesViaTunnel -Username $dbUsername -Password $dbPasswordPlain -LocalPort $tunnelInfo.Port
    } else {
        # Fallback to server selection mode
        if (-not $ServerName) {
            $servers = Get-MySQLServers
            $serverInput = Read-Host "Select server number or enter name"
            
            if (-not $serverInput) {
                Write-Host "Error: Server selection is required" -ForegroundColor Red
                exit 1
            }
            
            # Check if input is a number
            if ($serverInput -match '^\d+$') {
                $serverIndex = [int]$serverInput - 1
                if ($serverIndex -ge 0 -and $serverIndex -lt $servers.Count) {
                    $ServerName = $servers[$serverIndex].name
                } else {
                    Write-Host "Error: Invalid selection" -ForegroundColor Red
                    exit 1
                }
            } else {
                $ServerName = $serverInput
            }
        }
        
        # Get server information
        Write-Host ""
        Write-Host "Finding server details..." -ForegroundColor Blue
        $serverInfo = Get-ServerInfo -ServerName $ServerName
        
        # List databases via Azure CLI
        $databases = Get-DatabasesViaAzureCLI -ServerName $ServerName -ResourceGroup $serverInfo.ResourceGroup
    }
    
    if (-not $databases) {
        Write-Host "Error: No databases available for dump" -ForegroundColor Red
        exit 1
    }
    
    # Show databases and get selection
    Write-Host ""
    Write-Host "Available Databases:" -ForegroundColor Cyan
    
    # Force databases to be treated as array
    if ($databases -is [string]) {
        $databases = @($databases)
    }
    
    # Display databases with proper indexing
    for ($i = 0; $i -lt $databases.Length; $i++) {
        $dbName = $databases[$i]
        Write-Host "$($i + 1). $dbName"
    }
    Write-Host ""
    
    if (-not $DatabaseName) {
        $dbInput = Read-Host "Select database number or enter name"
        
        if (-not $dbInput) {
            Write-Host "Error: Database selection is required" -ForegroundColor Red
            exit 1
        }
        
        # Check if input is a number
        if ($dbInput -match '^\d+$') {
            $dbIndex = [int]$dbInput - 1
            if ($dbIndex -ge 0 -and $dbIndex -lt $databases.Length) {
                $DatabaseName = $databases[$dbIndex]
            } else {
                Write-Host "Error: Invalid selection" -ForegroundColor Red
                exit 1
            }
        } else {
            $DatabaseName = $dbInput
        }
    }
    
    # Get output path
    if (-not $OutputPath) {
        $defaultPath = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
        Write-Host ""
        $OutputPath = Read-Host "Enter output directory (default: $defaultPath)"
        if (-not $OutputPath) {
            $OutputPath = $defaultPath
        }
    }
    
    # Create output directory if it doesn't exist
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    # Generate output filename with timestamp
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputFile = Join-Path $OutputPath "${DatabaseName}_dump_${timestamp}.sql"
    
    Write-Host ""
    Write-Host "Database dump configuration:" -ForegroundColor Blue
    if ($tunnelInfo.Active) {
        Write-Host "Connection: SSH Tunnel (localhost:$($tunnelInfo.Port))"
        Write-Host "Azure Server: $tunnelServerName"
    } else {
        Write-Host "Server: $ServerName"
        Write-Host "Resource Group: $($serverInfo.ResourceGroup)"
    }
    Write-Host "Database: $DatabaseName"
    Write-Host "Output File: $outputFile"
    Write-Host ""
    
    $confirm = Read-Host "Proceed with dump? (Y/n)"
    if ($confirm -eq "n" -or $confirm -eq "N") {
        Write-Host "Dump cancelled" -ForegroundColor Yellow
        exit 0
    }
    
    # Perform the dump
    Write-Host ""
    Write-Host "Starting database dump..." -ForegroundColor Yellow
    
    $success = $false
    if ($tunnelInfo.Active) {
        $success = Invoke-DumpViaTunnel -Username $dbUsername -Password $dbPasswordPlain -DatabaseName $DatabaseName -LocalPort $tunnelInfo.Port -OutputFile $outputFile -ServerName $tunnelServerName
    } else {
        $success = Invoke-DumpViaAzureCLI -ServerName $ServerName -Username $dbUsername -Password $dbPasswordPlain -DatabaseName $DatabaseName -OutputFile $outputFile
    }
    
    if ($success) {
        $fileInfo = Get-Item $outputFile
        Write-Host ""
        Write-Host "==========================================" -ForegroundColor Green
        Write-Host "✓ Database dump completed successfully!" -ForegroundColor Green
        Write-Host "==========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Database: $DatabaseName"
        Write-Host "Output File: $outputFile"
        Write-Host "File Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB"
        Write-Host "Created: $($fileInfo.CreationTime)"
        Write-Host ""
        Write-Host "Dump completed!" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "✗ Database dump failed" -ForegroundColor Red
        if (Test-Path $outputFile) {
            Remove-Item $outputFile -Force
        }
        exit 1
    }
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}