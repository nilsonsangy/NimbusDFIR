# Azure MySQL Connect Script - PowerShell Version
# Author: NimbusDFIR
# Description: Connect to Azure MySQL Flexible Server - handles both public and private instances

param(
    [Parameter(Position=0)]
    [string]$ServerName,
    
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
    $mysqlCmd = Get-Command mysql -ErrorAction SilentlyContinue
    if (-not $mysqlCmd) {
        # Try common MySQL paths if not in PATH
        $commonPaths = @(
            "C:\Program Files\MySQL\MySQL Server 8.4\bin\mysql.exe",
            "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe",
            "C:\Program Files (x86)\MySQL\MySQL Server 8.4\bin\mysql.exe",
            "C:\Program Files (x86)\MySQL\MySQL Server 8.0\bin\mysql.exe"
        )
        
        $mysqlFound = $false
        foreach ($path in $commonPaths) {
            if (Test-Path $path) {
                $pathDir = Split-Path $path -Parent
                $env:PATH += ";$pathDir"
                $mysqlFound = $true
                break
            }
        }
        
        if (-not $mysqlFound) {
            Write-Host "Error: MySQL client is not installed" -ForegroundColor Red
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
    Write-Host "Azure MySQL Connect - NimbusDFIR"
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Usage: .\mysql_connect.ps1 [SERVER_NAME]"
    Write-Host ""
    Write-Host "Description:"
    Write-Host "  Connects to an Azure MySQL Flexible Server"
    Write-Host "  - For public servers: connects directly"
    Write-Host "  - For private servers: creates Azure VM jump server with SSH tunnel"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\mysql_connect.ps1 my-mysql-server"
    Write-Host "  .\mysql_connect.ps1"
    Write-Host ""
}

# List available MySQL servers
function Get-MySQLServers {
    Write-Host "Available Azure MySQL Flexible Servers:" -ForegroundColor Blue
    Write-Host ""
    
    try {
        $servers = az mysql flexible-server list --output json | ConvertFrom-Json
        
        if ($servers.Count -eq 0) {
            Write-Host "No MySQL flexible servers found" -ForegroundColor Yellow
            exit 1
        }
        
        for ($i = 0; $i -lt $servers.Count; $i++) {
            $server = $servers[$i]
            $publicAccess = if ($server.network.publicNetworkAccess) { $server.network.publicNetworkAccess } else { "Unknown" }
            Write-Host "$($i + 1). $($server.name) ($($server.resourceGroup) - $($server.state) - Public: $publicAccess)"
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
        
        if ($server.state -ne "Ready") {
            Write-Host "Error: Server is not ready (Status: $($server.state))" -ForegroundColor Red
            exit 1
        }
        
        # Check firewall rules for public servers
        $publicAccess = if ($server.network.publicNetworkAccess -eq "Enabled") { "Enabled" } else { "Disabled" }
        
        if ($publicAccess -eq "Enabled") {
            try {
                $firewallRules = az mysql flexible-server firewall-rule list --resource-group $server.resourceGroup --name $ServerName --query "length(@)" -o tsv
                if ([int]$firewallRules -eq 0) {
                    Write-Host "Warning: Server has public access enabled but no firewall rules" -ForegroundColor Yellow
                    Write-Host "Treating as private server - will use jump server" -ForegroundColor Yellow
                    $publicAccess = "Disabled"
                }
            }
            catch {
                $publicAccess = "Disabled"
            }
        }
        
        return @{
            Name = $server.name
            FQDN = $server.fullyQualifiedDomainName
            Version = $server.version
            Location = $server.location
            ResourceGroup = $server.resourceGroup
            PublicAccess = $publicAccess
            Status = $server.state
        }
    }
    catch {
        Write-Host "Error getting server information: $_" -ForegroundColor Red
        exit 1
    }
}

# Connect to public MySQL server
function Connect-PublicMySQL {
    param($ServerInfo)
    
    Write-Host "Server has public access enabled" -ForegroundColor Green
    Write-Host "Connecting directly to MySQL server..."
    Write-Host ""
    Write-Host "Connection details:"
    Write-Host "  Host: $($ServerInfo.FQDN)"
    Write-Host "  Port: 3306"
    Write-Host ""
    
    $mysqlUser = Read-Host "Enter MySQL username"
    if (-not $mysqlUser) {
        Write-Host "Error: Username is required" -ForegroundColor Red
        exit 1
    }
    
    $mysqlPassword = Read-Host "Enter password for user '$mysqlUser'" -AsSecureString
    $mysqlPasswordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($mysqlPassword))
    
    if (-not $mysqlPasswordPlain) {
        Write-Host "Error: Password is required" -ForegroundColor Red
        exit 1
    }
    
    $dbName = Read-Host "Enter database name (press Enter for no database)"
    Write-Host ""
    
    Write-Host "Connecting to MySQL..."
    Write-Host "Type 'exit' to disconnect from MySQL and cleanup resources" -ForegroundColor Yellow
    Write-Host ""
    
    if ($dbName) {
        & mysql -h $ServerInfo.FQDN -u $mysqlUser -p"$mysqlPasswordPlain" $dbName
    } else {
        & mysql -h $ServerInfo.FQDN -u $mysqlUser -p"$mysqlPasswordPlain"
    }
}

# Create jump server VM
function New-JumpServerVM {
    param($ServerInfo)
    
    Write-Host "Server is private - checking for existing jump server..." -ForegroundColor Yellow
    Write-Host ""
    
    $jumpServerRG = $ServerInfo.ResourceGroup
    $jumpServerLocation = $ServerInfo.Location

    # Check for existing jump server VMs
    try {
        $existingJumpServers = az vm list --resource-group $jumpServerRG --query "[?starts_with(name, 'mysql-jumpserver')].{name:name, state:powerState, ip:publicIps}" -o json | ConvertFrom-Json

        if ($existingJumpServers.Count -gt 0) {
            Write-Host "Found $($existingJumpServers.Count) existing jump server VM(s)" -ForegroundColor Green
            for ($i = 0; $i -lt $existingJumpServers.Count; $i++) {
                Write-Host "$($i + 1). $($existingJumpServers[$i].name) - $($existingJumpServers[$i].state) - $($existingJumpServers[$i].ip)"
            }
            Write-Host ""
            
            $useExisting = Read-Host "Use existing bastion? (Y/n)"
            if ($useExisting -ne "n" -and $useExisting -ne "N") {
                $bastion = $existingBastions[0]
                $bastionName = $bastion.name
                
                # Get public IP
                $jumpServerPublicIP = az vm show --resource-group $jumpServerRG --name $jumpServerName --show-details --query publicIps -o tsv
                
                # Start VM if stopped
                if ($jumpServer.state -match "stopped" -or $jumpServer.state -match "deallocated") {
                    Write-Host "Starting existing jump server VM: $jumpServerName" -ForegroundColor Yellow
                    az vm start --resource-group $jumpServerRG --name $jumpServerName --no-wait
                    Start-Sleep -Seconds 10
                    
                    $jumpServerPublicIP = az vm show --resource-group $jumpServerRG --name $jumpServerName --show-details --query publicIps -o tsv
                }
                
                Write-Host "Using existing jump server VM: $jumpServerName" -ForegroundColor Green
                Write-Host "Public IP: $jumpServerPublicIP"
                Write-Host ""
                
                # Save jump server info
                "$jumpServerName|$jumpServerRG|$jumpServerPublicIP" | Out-File -FilePath "$env:TEMP\azure_mysql_jumpserver_info.txt" -Encoding utf8
                
                return @{
                    Name = $jumpServerName
                    ResourceGroup = $jumpServerRG
                    PublicIP = $jumpServerPublicIP
                }
            }
        }
    }
    catch {
        # No existing jump servers found, continue with creation
    }
    
    # Create new jump server VM
    Write-Host "Creating new Azure VM jump server instance..." -ForegroundColor Yellow
    Write-Host ""
    
    $jumpServerName = "mysql-jumpserver-$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    Write-Host "Creating jump server VM: $jumpServerName"
    Write-Host "Location: $jumpServerLocation"
    Write-Host "Resource Group: $jumpServerRG"
    Write-Host ""
    Write-Host "Launching VM (this may take 2-3 minutes)..."
    
    try {
        $vmOutput = az vm create `
            --resource-group $jumpServerRG `
            --name $jumpServerName `
            --location $jumpServerLocation `
            --image Ubuntu2204 `
            --size Standard_B1s `
            --admin-username azureuser `
            --generate-ssh-keys `
            --public-ip-sku Standard `
            --public-ip-address "$jumpServerName-ip" `
            --nsg "$jumpServerName-nsg" `
            --nsg-rule SSH `
            --output json | ConvertFrom-Json
        
        $jumpServerPublicIP = $vmOutput.publicIpAddress
        
        if (-not $jumpServerPublicIP) {
            throw "Failed to get jump server VM public IP"
        }
        
        Write-Host "Jump server VM created successfully" -ForegroundColor Green
        Write-Host "Public IP: $jumpServerPublicIP"
        Write-Host ""
        
        # Save jump server info for cleanup
        "$jumpServerName|$jumpServerRG|$jumpServerPublicIP" | Out-File -FilePath "$env:TEMP\azure_mysql_jumpserver_info.txt" -Encoding utf8
        
        return @{
            Name = $jumpServerName
            ResourceGroup = $jumpServerRG
            PublicIP = $jumpServerPublicIP
        }
    }
    catch {
        Write-Host "Error: Failed to create jump server VM" -ForegroundColor Red
        Write-Host "Error details: $_"
        exit 1
    }
}

# Connect via SSH tunnel through jump server VM
function Connect-ViaJumpServerVM {
    param($ServerInfo, $JumpServerInfo)
    
    Write-Host ""
    Write-Host "Setting up connection to MySQL through jump server VM..." -ForegroundColor Blue
    Write-Host ""
    Write-Host "Waiting for VM to be fully ready (this may take 30-60 seconds)..."
    
    # Wait for SSH to be ready (simplified for Windows)
    Write-Host "Checking SSH connectivity..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30  # Give VM time to boot
    
    # Add firewall rule for jump server VM
    Write-Host "Adding firewall rule for jump server VM..." -ForegroundColor Yellow
    $ruleName = "jumpserver-access-$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    az mysql flexible-server firewall-rule create `
        --resource-group $ServerInfo.ResourceGroup `
        --name $ServerInfo.Name `
        --rule-name $ruleName `
        --start-ip-address $JumpServerInfo.PublicIP `
        --end-ip-address $JumpServerInfo.PublicIP `
        --output none
    
    Write-Host "Firewall rule created" -ForegroundColor Green
    Write-Host ""
    
    # Get MySQL credentials
    $mysqlUser = Read-Host "Enter MySQL username"
    if (-not $mysqlUser) {
        Write-Host "Error: Username is required" -ForegroundColor Red
        exit 1
    }
    
    $mysqlPassword = Read-Host "Enter password for user '$mysqlUser'" -AsSecureString
    $mysqlPasswordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($mysqlPassword))
    
    $dbName = Read-Host "Enter database name (press Enter for no database)"
    Write-Host ""
    
    $localPort = 3307
    
    Write-Host "===========================================" -ForegroundColor Green
    Write-Host "SSH Tunnel Configuration" -ForegroundColor Green
    Write-Host "===========================================" -ForegroundColor Green
    Write-Host "Local Port: $localPort"
    Write-Host "Remote MySQL: $($ServerInfo.FQDN):3306"
    Write-Host "Jump Server: $($JumpServerInfo.PublicIP)"
    Write-Host ""
    
    # Note: For full SSH tunnel functionality on Windows, you'd need plink or ssh.exe
    Write-Host "Note: SSH tunnel setup requires SSH client (Windows 10+ has built-in SSH)" -ForegroundColor Yellow
    Write-Host "For production use, consider using Azure Bastion service or VPN instead" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Manual connection command:" -ForegroundColor Cyan
    Write-Host "ssh -L ${localPort}:$($ServerInfo.FQDN):3306 azureuser@$($JumpServerInfo.PublicIP)" -ForegroundColor Gray
    Write-Host "Then connect to: mysql -h 127.0.0.1 -P $localPort -u $mysqlUser -p" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Setting up SSH tunnel and connecting to MySQL..." -ForegroundColor Green
    Write-Host "Type 'exit' in MySQL to disconnect and cleanup resources" -ForegroundColor Yellow
    Write-Host ""
    
    # Start SSH tunnel in background and connect to MySQL
    try {
        # Create SSH tunnel using built-in Windows SSH
        $sshProcess = Start-Process -FilePath "ssh" -ArgumentList "-L", "${localPort}:$($ServerInfo.FQDN):3306", "azureuser@$($JumpServerInfo.PublicIP)", "-o", "StrictHostKeyChecking=no" -PassThru -WindowStyle Hidden
        
        # Wait a moment for tunnel to establish
        Start-Sleep -Seconds 5
        
        # Connect to MySQL through the tunnel
        if ($dbName) {
            & mysql -h 127.0.0.1 -P $localPort -u $mysqlUser -p"$mysqlPasswordPlain" $dbName
        } else {
            & mysql -h 127.0.0.1 -P $localPort -u $mysqlUser -p"$mysqlPasswordPlain"
        }
        
        # Stop SSH tunnel after MySQL session ends
        if ($sshProcess -and !$sshProcess.HasExited) {
            $sshProcess.Kill()
        }
    }
    catch {
        Write-Host "SSH tunnel setup failed. Using manual method:" -ForegroundColor Yellow
        Write-Host "1. Open new terminal and run: ssh -L ${localPort}:$($ServerInfo.FQDN):3306 azureuser@$($JumpServerInfo.PublicIP)" -ForegroundColor Cyan
        Write-Host "2. In another terminal, run: mysql -h 127.0.0.1 -P $localPort -u $mysqlUser -p" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Press Enter when done with MySQL session to cleanup..."
        Read-Host
    }
    
    # Remove firewall rule
    Write-Host "Removing firewall rule..." -ForegroundColor Yellow
    az mysql flexible-server firewall-rule delete `
        --resource-group $ServerInfo.ResourceGroup `
        --name $ServerInfo.Name `
        --rule-name $ruleName `
        --yes `
        --output none 2>$null
}

# Cleanup jump server resources
function Remove-JumpServerVM {
    if (Test-Path "$env:TEMP\azure_mysql_jumpserver_info.txt") {
        Write-Host ""
        Write-Host "Cleaning up jump server resources..." -ForegroundColor Yellow
        
        $jumpServerInfo = Get-Content "$env:TEMP\azure_mysql_jumpserver_info.txt" -Raw
        $jumpServerName, $jumpServerRG, $jumpServerIP = $jumpServerInfo.Split('|')
        
        if ($jumpServerName -and $jumpServerRG) {
            Write-Host "Deleting jump server VM and associated resources: $jumpServerName"
            
            # Delete VM and associated resources
            Write-Host "  - Deleting VM: $jumpServerName"
            az vm delete --resource-group $jumpServerRG --name $jumpServerName --yes --force-deletion yes --output none 2>$null
            
            Start-Sleep -Seconds 10
            
            Write-Host "  - Deleting network interface(s)..."
            $nicNames = az network nic list --resource-group $jumpServerRG --query "[?contains(name, '$jumpServerName')].name" -o tsv
            foreach ($nicName in $nicNames) {
                az network nic delete --resource-group $jumpServerRG --name $nicName --output none 2>$null
            }
            
            Write-Host "  - Deleting public IP..."
            az network public-ip delete --resource-group $jumpServerRG --name "$jumpServerName-ip" --output none 2>$null
            
            Write-Host "  - Deleting network security group..."
            az network nsg delete --resource-group $jumpServerRG --name "$jumpServerName-nsg" --output none 2>$null
            
            Write-Host "  - Deleting disk(s)..."
            $diskNames = az disk list --resource-group $jumpServerRG --query "[?contains(name, '$jumpServerName')].name" -o tsv
            foreach ($diskName in $diskNames) {
                az disk delete --resource-group $jumpServerRG --name $diskName --yes --output none 2>$null
            }
            
            Write-Host "  - Deleting virtual network..."
            $vnetNames = az network vnet list --resource-group $jumpServerRG --query "[?contains(name, '$jumpServerName')].name" -o tsv
            foreach ($vnetName in $vnetNames) {
                az network vnet delete --resource-group $jumpServerRG --name $vnetName --output none 2>$null
            }
            
            Write-Host "All jump server resources deleted" -ForegroundColor Green
        }
        
        Remove-Item "$env:TEMP\azure_mysql_jumpserver_info.txt" -Force -ErrorAction SilentlyContinue
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
    
    if (-not $ServerName) {
        $servers = Get-MySQLServers
        Write-Host ""
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
    Write-Host "Gathering MySQL server information..." -ForegroundColor Blue
    $serverInfo = Get-ServerInfo -ServerName $ServerName
    
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "MySQL Server Information"
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "Name: $($serverInfo.Name)"
    Write-Host "FQDN: $($serverInfo.FQDN)"
    Write-Host "Version: $($serverInfo.Version)"
    Write-Host "Location: $($serverInfo.Location)"
    Write-Host "Resource Group: $($serverInfo.ResourceGroup)"
    Write-Host "Public Access: $($serverInfo.PublicAccess)"
    Write-Host "Status: $($serverInfo.Status)"
    Write-Host ""
    
    # Connect based on public access
    if ($serverInfo.PublicAccess -eq "Enabled") {
        Connect-PublicMySQL -ServerInfo $serverInfo
    } else {
        $jumpServerInfo = New-JumpServerVM -ServerInfo $serverInfo
        Connect-ViaJumpServerVM -ServerInfo $serverInfo -JumpServerInfo $jumpServerInfo
    }
    
    Write-Host ""
    Write-Host "MySQL connection session ended" -ForegroundColor Green
}
finally {
    # Cleanup on exit
    Remove-JumpServerVM
}