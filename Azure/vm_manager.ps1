# Azure VM Manager Script - PowerShell
# Author: NimbusDFIR
# Description: Manage Azure VMs - list, create, start, stop, and delete VMs

param(
    [Parameter(Position=0)]
    [string]$Command,
    [Parameter(Position=1)]
    [string]$VMName
)

# Check if Azure CLI is installed
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Azure CLI is not installed" -ForegroundColor Red
    Write-Host "Please install Azure CLI first" -ForegroundColor Yellow
    Write-Host "Run: winget install Microsoft.AzureCLI" -ForegroundColor Green
    exit 1
}

# Check if logged in to Azure
$accountCheck = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Not logged in to Azure" -ForegroundColor Red
    Write-Host "Please run: az login" -ForegroundColor Yellow
    exit 1
}

function Show-Usage {
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "Azure VM Manager - NimbusDFIR" -ForegroundColor Blue
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Usage: .\vm_manager.ps1 [COMMAND] [OPTIONS]"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  list              List all VMs in current subscription"
    Write-Host "  create            Create a new VM"
    Write-Host "  delete            Delete a VM"
    Write-Host "  start             Start a stopped VM"
    Write-Host "  stop              Stop a running VM (deallocate)"
    Write-Host "  help              Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\vm_manager.ps1 list"
    Write-Host "  .\vm_manager.ps1 create"
    Write-Host "  .\vm_manager.ps1 delete myVM"
    Write-Host "  .\vm_manager.ps1 start myVM"
    Write-Host "  .\vm_manager.ps1 stop myVM"
    Write-Host ""
}

function Get-VMs {
    Write-Host "Listing Azure VMs..." -ForegroundColor Blue
    Write-Host ""
    
    $vms = az vm list --output json 2>$null | ConvertFrom-Json
    
    if (-not $vms -or $vms.Count -eq 0) {
        Write-Host "No VMs found in current subscription" -ForegroundColor Yellow
        return
    }
    
    Write-Host "VM Name`t`t`tResource Group`t`tLocation`tSize`t`tState" -ForegroundColor Cyan
    Write-Host "----------------------------------------------------------------------------------------"
    
    foreach ($vm in $vms) {
        $powerState = az vm get-instance-view --name $vm.name --resource-group $vm.resourceGroup --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>$null
        
        $color = "White"
        if ($powerState -match "running") {
            $color = "Green"
        } elseif ($powerState -match "stopped|deallocated") {
            $color = "Yellow"
        }
        
        Write-Host "$($vm.name)`t`t$($vm.resourceGroup)`t`t$($vm.location)`t$($vm.hardwareProfile.vmSize)`t$powerState" -ForegroundColor $color
    }
}

function New-VM {
    Write-Host "Create New Azure VM" -ForegroundColor Blue
    Write-Host ""
    
    # Get VM name
    $vmName = Read-Host "Enter VM name (default: azure-vm-$(Get-Date -Format 'yyyyMMddHHmmss'))"
    if ([string]::IsNullOrWhiteSpace($vmName)) {
        $vmName = "azure-vm-$(Get-Date -Format 'yyyyMMddHHmmss')"
    }
    
    # Get or create resource group
    Write-Host ""
    Write-Host "Available Resource Groups:" -ForegroundColor Cyan
    $resourceGroups = az group list --query "[].{Name:name, Location:location}" -o json | ConvertFrom-Json
    
    if ($resourceGroups -and $resourceGroups.Count -gt 0) {
        for ($i = 0; $i -lt $resourceGroups.Count; $i++) {
            Write-Host "  $($i+1). $($resourceGroups[$i].Name) ($($resourceGroups[$i].Location))"
        }
    } else {
        Write-Host "  No resource groups found"
    }
    
    Write-Host ""
    $rgInput = Read-Host "Enter resource group name or number (default: rg-forensics)"
    if ([string]::IsNullOrWhiteSpace($rgInput)) {
        $rgName = "rg-forensics"
    } elseif ($rgInput -match '^[0-9]+$') {
        $rgIndex = [int]$rgInput - 1
        if ($resourceGroups -and $rgIndex -ge 0 -and $rgIndex -lt $resourceGroups.Count) {
            $rgName = $resourceGroups[$rgIndex].Name
        } else {
            Write-Host "Invalid resource group number. Using default: rg-forensics" -ForegroundColor Yellow
            $rgName = "rg-forensics"
        }
    } else {
        $rgName = $rgInput
    }
    
    # Check if resource group exists
    $rgExists = az group show --name $rgName 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Resource group does not exist. Creating..." -ForegroundColor Yellow
        $location = Read-Host "Enter location (default: northcentralus)"
        if ([string]::IsNullOrWhiteSpace($location)) {
            $location = "northcentralus"
        }
        az group create --name $rgName --location $location --output table
        Write-Host "✓ Resource group created" -ForegroundColor Green
    } else {
        $location = az group show --name $rgName --query location -o tsv
    }
    
    # Get VM size
    Write-Host ""
    Write-Host "Select VM Size:" -ForegroundColor Cyan
    Write-Host "  1. Standard_B1s   - 1 vCPU, 1 GB RAM  (Lowest cost)"
    Write-Host "  2. Standard_B1ms  - 1 vCPU, 2 GB RAM"
    Write-Host "  3. Standard_B2s   - 2 vCPU, 4 GB RAM"
    Write-Host "  4. Standard_D2s_v3 - 2 vCPU, 8 GB RAM"
    Write-Host ""
    $vmSizeChoice = Read-Host "Choose VM size [1-4] (default: 1)"
    if ([string]::IsNullOrWhiteSpace($vmSizeChoice)) {
        $vmSizeChoice = "1"
    }
    
    $vmSize = switch ($vmSizeChoice) {
        "1" { "Standard_B1s" }
        "2" { "Standard_B1ms" }
        "3" { "Standard_B2s" }
        "4" { "Standard_D2s_v3" }
        default { "Standard_B1s" }
    }
    
    # Get image
    Write-Host ""
    Write-Host "Select Image:" -ForegroundColor Cyan
    Write-Host "  1. Ubuntu2204     - Ubuntu 22.04 LTS"
    Write-Host "  2. Ubuntu2404     - Ubuntu 24.04 LTS"
    Write-Host "  3. Debian11       - Debian 11"
    Write-Host "  4. Win2022Datacenter - Windows Server 2022"
    Write-Host "  5. Win2019Datacenter - Windows Server 2019"
    Write-Host ""
    $imageChoice = Read-Host "Choose image [1-5] (default: 1)"
    if ([string]::IsNullOrWhiteSpace($imageChoice)) {
        $imageChoice = "1"
    }
    
    $image = switch ($imageChoice) {
        "1" { "Ubuntu2204" }
        "2" { "Ubuntu2404" }
        "3" { "Debian11" }
        "4" { "Win2022Datacenter" }
        "5" { "Win2019Datacenter" }
        default { "Ubuntu2204" }
    }
    
    # Get authentication
    Write-Host ""
    $adminUser = Read-Host "Enter admin username (default: azureuser)"
    if ([string]::IsNullOrWhiteSpace($adminUser)) {
        $adminUser = "azureuser"
    }
    
    Write-Host ""
    Write-Host "Authentication Method:" -ForegroundColor Cyan
    Write-Host "  1. SSH key (Linux VMs)"
    Write-Host "  2. Password"
    Write-Host ""
    $authMethod = Read-Host "Choose authentication method [1-2] (default: 1)"
    if ([string]::IsNullOrWhiteSpace($authMethod)) {
        $authMethod = "1"
    }
    
    # Build command
    $cmd = "az vm create --name $vmName --resource-group $rgName --location $location --size $vmSize --image $image --admin-username $adminUser"
    
    if ($authMethod -eq "1") {
        $cmd += " --generate-ssh-keys"
    } else {
        $adminPassword = Read-Host "Enter admin password" -AsSecureString
        $adminPasswordText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPassword))
        $cmd += " --admin-password '$adminPasswordText'"
    }
    
    # Ask about public IP
    Write-Host ""
    $publicIP = Read-Host "Assign public IP? (y/N)"
    if ($publicIP -ne "y" -and $publicIP -ne "Y") {
        $cmd += " --public-ip-address ''"
    }
    
    Write-Host ""
    Write-Host "Creating VM... (this may take a few minutes)" -ForegroundColor Yellow
    Write-Host "[INFO] VM: $vmName | Size: $vmSize | Image: $image | Location: $location" -ForegroundColor Blue
    Write-Host ""
    
    Invoke-Expression $cmd
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "✓ VM created successfully!" -ForegroundColor Green
        Write-Host ""
        
        # Get VM details
        Write-Host "VM Details:" -ForegroundColor Cyan
        az vm show --name $vmName --resource-group $rgName --show-details --query "{Name:name, ResourceGroup:resourceGroup, Location:location, Size:hardwareProfile.vmSize, PublicIP:publicIps, PrivateIP:privateIps}" -o table
    } else {
        Write-Host "✗ Failed to create VM" -ForegroundColor Red
        exit 1
    }
}

function Remove-VM {
    param([string]$VMName)
    
    if ([string]::IsNullOrWhiteSpace($VMName)) {
        # List VMs and let user choose
        Write-Host "Available VMs to delete:" -ForegroundColor Cyan
        Write-Host ""
        
        $vms = az vm list --output json 2>$null | ConvertFrom-Json
        
        if (-not $vms -or $vms.Count -eq 0) {
            Write-Host "No VMs found in current subscription" -ForegroundColor Yellow
            exit 0
        }
        
        # Display numbered list of all VMs
        for ($i = 0; $i -lt $vms.Count; $i++) {
            $vm = $vms[$i]
            $powerState = az vm get-instance-view --name $vm.name --resource-group $vm.resourceGroup --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>$null
            
            $color = "White"
            if ($powerState -match "running") {
                $color = "Green"
            } elseif ($powerState -match "stopped|deallocated") {
                $color = "Yellow"
            }
            
            Write-Host "  $($i + 1). $($vm.name) ($($vm.resourceGroup)) - $($vm.location) [$powerState]" -ForegroundColor $color
        }
        
        Write-Host ""
        $selection = Read-Host "Select VM to delete [1-$($vms.Count)] or 0 to cancel"
        
        if ($selection -eq "0" -or [string]::IsNullOrWhiteSpace($selection)) {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
            exit 0
        }
        
        try {
            $selectedIndex = [int]$selection - 1
            if ($selectedIndex -lt 0 -or $selectedIndex -ge $vms.Count) {
                Write-Host "Invalid selection" -ForegroundColor Red
                exit 1
            }
            
            $VMName = $vms[$selectedIndex].name
            $rgName = $vms[$selectedIndex].resourceGroup
        }
        catch {
            Write-Host "Invalid selection" -ForegroundColor Red
            exit 1
        }
    }
    else {
        # Find VM and get resource group
        Write-Host "Finding VM: $VMName" -ForegroundColor Blue
        $vmInfo = az vm list --query "[?name=='$VMName']" -o json | ConvertFrom-Json
        
        if (-not $vmInfo -or $vmInfo.Count -eq 0) {
            Write-Host "Error: VM '$VMName' not found" -ForegroundColor Red
            exit 1
        }
        
        $rgName = $vmInfo[0].resourceGroup
    }
    
    Write-Host "VM found in resource group: $rgName" -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Are you sure you want to delete VM '$VMName'? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Deletion cancelled"
        exit 0
    }
    
    Write-Host ""
    Write-Host "Deleting VM and associated resources..." -ForegroundColor Yellow
    
    # Delete VM and associated resources
    az vm delete --name $VMName --resource-group $rgName --yes
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ VM deleted successfully" -ForegroundColor Green
        
        # Ask to delete associated resources
        $deleteResources = Read-Host "Delete associated NICs and disks? (y/n)"
        if ($deleteResources -eq "y") {
            Write-Host "Cleaning up all associated resources..." -ForegroundColor Yellow
            Write-Host ""
            
            # Delete NICs
            Write-Host "[INFO] Deleting Network Interfaces..." -ForegroundColor Blue
            $nics = az network nic list --resource-group $rgName --query "[?contains(name, '$VMName')].[name]" -o tsv
            foreach ($nic in $nics) {
                if ($nic.Trim()) {
                    Write-Host "  Deleting NIC: $nic" -ForegroundColor Yellow
                    az network nic delete --resource-group $rgName --name $nic
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "    ✓ NIC deleted: $nic" -ForegroundColor Green
                    } else {
                        Write-Host "    ✗ Failed to delete NIC: $nic" -ForegroundColor Red
                    }
                }
            }
            
            # Delete Public IPs
            Write-Host "[INFO] Deleting Public IP addresses..." -ForegroundColor Blue
            $publicIPs = az network public-ip list --resource-group $rgName --query "[?contains(name, '$VMName')].[name]" -o tsv
            foreach ($publicIP in $publicIPs) {
                if ($publicIP.Trim()) {
                    Write-Host "  Deleting Public IP: $publicIP" -ForegroundColor Yellow
                    az network public-ip delete --resource-group $rgName --name $publicIP
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "    ✓ Public IP deleted: $publicIP" -ForegroundColor Green
                    } else {
                        Write-Host "    ✗ Failed to delete Public IP: $publicIP" -ForegroundColor Red
                    }
                }
            }
            
            # Delete Network Security Groups
            Write-Host "[INFO] Deleting Network Security Groups..." -ForegroundColor Blue
            $nsgs = az network nsg list --resource-group $rgName --query "[?contains(name, '$VMName')].[name]" -o tsv
            foreach ($nsg in $nsgs) {
                if ($nsg.Trim()) {
                    Write-Host "  Deleting NSG: $nsg" -ForegroundColor Yellow
                    az network nsg delete --resource-group $rgName --name $nsg
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "    ✓ NSG deleted: $nsg" -ForegroundColor Green
                    } else {
                        Write-Host "    ✗ Failed to delete NSG: $nsg" -ForegroundColor Red
                    }
                }
            }
            
            # Delete Disks
            Write-Host "[INFO] Deleting Disks..." -ForegroundColor Blue
            $disks = az disk list --resource-group $rgName --query "[?contains(name, '$VMName')].[name]" -o tsv
            foreach ($disk in $disks) {
                if ($disk.Trim()) {
                    Write-Host "  Deleting disk: $disk" -ForegroundColor Yellow
                    az disk delete --resource-group $rgName --name $disk --yes
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "    ✓ Disk deleted: $disk" -ForegroundColor Green
                    } else {
                        Write-Host "    ✗ Failed to delete disk: $disk" -ForegroundColor Red
                    }
                }
            }
            
            # Delete Virtual Networks (only if they are VM-specific)
            Write-Host "[INFO] Checking Virtual Networks..." -ForegroundColor Blue
            $vnets = az network vnet list --resource-group $rgName --query "[?contains(name, '$VMName')].[name]" -o tsv
            foreach ($vnet in $vnets) {
                if ($vnet.Trim()) {
                    Write-Host "  Deleting VNET: $vnet" -ForegroundColor Yellow
                    az network vnet delete --resource-group $rgName --name $vnet
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "    ✓ VNET deleted: $vnet" -ForegroundColor Green
                    } else {
                        Write-Host "    ✗ Failed to delete VNET: $vnet" -ForegroundColor Red
                    }
                }
            }
            
            Write-Host ""
            Write-Host "✓ All resources cleanup completed" -ForegroundColor Green
        }
    } else {
        Write-Host "✗ Failed to delete VM" -ForegroundColor Red
        exit 1
    }
}

function Start-AzureVM {
    param([string]$VMName)
    
    if ([string]::IsNullOrWhiteSpace($VMName)) {
        # List VMs and let user choose
        Write-Host "Available VMs to start:" -ForegroundColor Cyan
        Write-Host ""
        
        $vms = az vm list --output json 2>$null | ConvertFrom-Json
        
        if (-not $vms -or $vms.Count -eq 0) {
            Write-Host "No VMs found in current subscription" -ForegroundColor Yellow
            exit 0
        }
        
        # Filter only stopped VMs
        $stoppedVMs = @()
        foreach ($vm in $vms) {
            $powerState = az vm get-instance-view --name $vm.name --resource-group $vm.resourceGroup --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>$null
            if ($powerState -match "stopped|deallocated") {
                $stoppedVMs += $vm
            }
        }
        
        if ($stoppedVMs.Count -eq 0) {
            Write-Host "No stopped VMs found to start" -ForegroundColor Yellow
            exit 0
        }
        
        # Display numbered list of stopped VMs
        for ($i = 0; $i -lt $stoppedVMs.Count; $i++) {
            $vm = $stoppedVMs[$i]
            Write-Host "  $($i + 1). $($vm.name) ($($vm.resourceGroup)) - $($vm.location)" -ForegroundColor White
        }
        
        Write-Host ""
        $selection = Read-Host "Select VM to start [1-$($stoppedVMs.Count)] or 0 to cancel"
        
        if ($selection -eq "0" -or [string]::IsNullOrWhiteSpace($selection)) {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
            exit 0
        }
        
        try {
            $selectedIndex = [int]$selection - 1
            if ($selectedIndex -lt 0 -or $selectedIndex -ge $stoppedVMs.Count) {
                Write-Host "Invalid selection" -ForegroundColor Red
                exit 1
            }
            
            $VMName = $stoppedVMs[$selectedIndex].name
            $rgName = $stoppedVMs[$selectedIndex].resourceGroup
        }
        catch {
            Write-Host "Invalid selection" -ForegroundColor Red
            exit 1
        }
    }
    else {
        # Find VM and get resource group
        $vmInfo = az vm list --query "[?name=='$VMName']" -o json | ConvertFrom-Json
        
        if (-not $vmInfo -or $vmInfo.Count -eq 0) {
            Write-Host "Error: VM '$VMName' not found" -ForegroundColor Red
            exit 1
        }
        
        $rgName = $vmInfo[0].resourceGroup
    }
    
    Write-Host "Starting VM: $VMName" -ForegroundColor Yellow
    az vm start --name $VMName --resource-group $rgName
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ VM started successfully" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to start VM" -ForegroundColor Red
        exit 1
    }
}

function Stop-AzureVM {
    param([string]$VMName)
    
    if ([string]::IsNullOrWhiteSpace($VMName)) {
        # List VMs and let user choose
        Write-Host "Available VMs to stop:" -ForegroundColor Cyan
        Write-Host ""
        
        $vms = az vm list --output json 2>$null | ConvertFrom-Json
        
        if (-not $vms -or $vms.Count -eq 0) {
            Write-Host "No VMs found in current subscription" -ForegroundColor Yellow
            exit 0
        }
        
        # Filter only running VMs
        $runningVMs = @()
        foreach ($vm in $vms) {
            $powerState = az vm get-instance-view --name $vm.name --resource-group $vm.resourceGroup --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>$null
            if ($powerState -match "running") {
                $runningVMs += $vm
            }
        }
        
        if ($runningVMs.Count -eq 0) {
            Write-Host "No running VMs found to stop" -ForegroundColor Yellow
            exit 0
        }
        
        # Display numbered list of running VMs
        for ($i = 0; $i -lt $runningVMs.Count; $i++) {
            $vm = $runningVMs[$i]
            Write-Host "  $($i + 1). $($vm.name) ($($vm.resourceGroup)) - $($vm.location)" -ForegroundColor White
        }
        
        Write-Host ""
        $selection = Read-Host "Select VM to stop [1-$($runningVMs.Count)] or 0 to cancel"
        
        if ($selection -eq "0" -or [string]::IsNullOrWhiteSpace($selection)) {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
            exit 0
        }
        
        try {
            $selectedIndex = [int]$selection - 1
            if ($selectedIndex -lt 0 -or $selectedIndex -ge $runningVMs.Count) {
                Write-Host "Invalid selection" -ForegroundColor Red
                exit 1
            }
            
            $VMName = $runningVMs[$selectedIndex].name
            $rgName = $runningVMs[$selectedIndex].resourceGroup
        }
        catch {
            Write-Host "Invalid selection" -ForegroundColor Red
            exit 1
        }
    }
    else {
        # Find VM and get resource group
        $vmInfo = az vm list --query "[?name=='$VMName']" -o json | ConvertFrom-Json
        
        if (-not $vmInfo -or $vmInfo.Count -eq 0) {
            Write-Host "Error: VM '$VMName' not found" -ForegroundColor Red
            exit 1
        }
        
        $rgName = $vmInfo[0].resourceGroup
    }
    
    Write-Host "Stopping and deallocating VM: $VMName" -ForegroundColor Yellow
    az vm deallocate --name $VMName --resource-group $rgName
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ VM stopped and deallocated successfully" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to stop VM" -ForegroundColor Red
        exit 1
    }
}

# Main script logic
switch ($Command.ToLower()) {
    "list" {
        Get-VMs
    }
    "create" {
        New-VM
    }
    "delete" {
        Remove-VM -VMName $VMName
    }
    "start" {
        Start-AzureVM -VMName $VMName
    }
    "stop" {
        Stop-AzureVM -VMName $VMName
    }
    "help" {
        Show-Usage
    }
    default {
        Show-Usage
        exit 1
    }
}