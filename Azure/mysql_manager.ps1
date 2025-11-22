# Azure MySQL Manager Script - PowerShell Version
# Author: NimbusDFIR
# Description: Manage MySQL databases (list, create, delete) via Azure tunnel or direct

param(
    [Parameter(Position=0)]
    [string]$Command,
    [Parameter(Position=1)]
    [string]$DatabaseName
)

function Show-Usage {
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "Azure MySQL Manager - NimbusDFIR" -ForegroundColor Blue
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Usage: .\mysql_manager.ps1 [COMMAND] [DATABASE_NAME]"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  list                List all databases"
    Write-Host "  create [NAME]        Create a new database"
    Write-Host "  delete [NAME]        Delete a database"
    Write-Host "  help                 Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\mysql_manager.ps1 list"
    Write-Host "  .\mysql_manager.ps1 create testdb"
    Write-Host "  .\mysql_manager.ps1 delete testdb"
    Write-Host ""
}

function Get-MySQLCredentials {
    $user = Read-Host "Enter MySQL admin username (default: mysqladmin)"
    if ([string]::IsNullOrWhiteSpace($user)) { $user = "mysqladmin" }
    $pass = Read-Host "Enter MySQL admin password" -AsSecureString
    $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))
    return @{ User = $user; Pass = $plain }
}

function List-Databases {
    Write-Host "Listing Azure Database for MySQL Flexible Servers..." -ForegroundColor Blue
    $servers = az mysql flexible-server list --output json 2>$null | ConvertFrom-Json
    if (-not $servers -or $servers.Count -eq 0) {
        Write-Host "No Azure MySQL Flexible Servers found" -ForegroundColor Yellow
        return
    }
    Write-Host "Name`tResource Group`tLocation`tVersion`tState" -ForegroundColor Cyan
    Write-Host ("-" * 70)
    foreach ($s in $servers) {
        Write-Host ("{0}`t{1}`t{2}`t{3}`t{4}" -f $s.name, $s.resourceGroup, $s.location, $s.version, $s.state)
    }
}

function Create-Database {
    param([string]$Name)
    if (-not $Name) {
        $Name = Read-Host "Enter new Azure MySQL Flexible Server name"
        if (-not $Name) { Write-Host "Server name required" -ForegroundColor Red; return }
    }
    $rg = Read-Host "Enter resource group (default: rg-forensics)"
    if ([string]::IsNullOrWhiteSpace($rg)) { $rg = "rg-forensics" }
    $location = Read-Host "Enter location (default: westeurope)"
    if ([string]::IsNullOrWhiteSpace($location)) { $location = "westeurope" }
    $admin = Read-Host "Enter admin username (default: mysqladmin)"
    if ([string]::IsNullOrWhiteSpace($admin)) { $admin = "mysqladmin" }
    $pass = Read-Host "Enter admin password" -AsSecureString
    $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))
    if ([string]::IsNullOrWhiteSpace($plainPass)) { Write-Host "Admin password required" -ForegroundColor Red; return }
    Write-Host "Creating Azure Database for MySQL Flexible Server..." -ForegroundColor Yellow
    $cmd = "az mysql flexible-server create --name $Name --resource-group $rg --location $location --admin-user $admin --admin-password '$plainPass' --sku-name Standard_B1ms --yes"
    Write-Host "[INFO] $cmd" -ForegroundColor Gray
    Invoke-Expression $cmd
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Azure MySQL Flexible Server '$Name' created." -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to create Azure MySQL Flexible Server '$Name'" -ForegroundColor Red
    }
}

function Delete-Database {
    param([string]$Name)
    if (-not $Name) {
        Write-Host "Listing Azure Database for MySQL Flexible Servers..." -ForegroundColor Blue
        $servers = az mysql flexible-server list --output json 2>$null | ConvertFrom-Json
        if (-not $servers -or $servers.Count -eq 0) {
            Write-Host "No Azure MySQL Flexible Servers found" -ForegroundColor Yellow
            return
        }
        for ($i = 0; $i -lt $servers.Count; $i++) {
            Write-Host "  $($i+1). $($servers[$i].name) ($($servers[$i].resourceGroup))"
        }
        $sel = Read-Host "Enter server number or name to delete"
        if ([string]::IsNullOrWhiteSpace($sel)) {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
            return
        }
        if ($sel -match '^[0-9]+$') {
            $idx = [int]$sel - 1
            if ($idx -ge 0 -and $idx -lt $servers.Count) {
                $Name = $servers[$idx].name
                $rg = $servers[$idx].resourceGroup
            } else {
                Write-Host "Invalid selection" -ForegroundColor Red
                return
            }
        } else {
            $match = $servers | Where-Object { $_.name -eq $sel }
            if ($match) {
                $Name = $match.name
                $rg = $match.resourceGroup
            } else {
                Write-Host "Server not found" -ForegroundColor Red
                return
            }
        }
    } else {
        # Find resource group for the given server name
        $info = az mysql flexible-server list --output json 2>$null | ConvertFrom-Json | Where-Object { $_.name -eq $Name }
        if (-not $info) {
            Write-Host "Server '$Name' not found" -ForegroundColor Red
            return
        }
        $rg = $info.resourceGroup
    }
    $confirm = Read-Host "Are you sure you want to delete Azure MySQL Flexible Server '$Name'? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Deletion cancelled"
        return
    }
    Write-Host "Deleting Azure MySQL Flexible Server '$Name'..." -ForegroundColor Yellow
    az mysql flexible-server delete --name $Name --resource-group $rg --yes
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Azure MySQL Flexible Server '$Name' deleted." -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to delete Azure MySQL Flexible Server '$Name'" -ForegroundColor Red
    }
}

switch ($Command) {
    "list"   { List-Databases }
    "create" { Create-Database -Name $DatabaseName }
    "delete" { Delete-Database -Name $DatabaseName }
    "help"   { Show-Usage }
    default  { Show-Usage }
}
