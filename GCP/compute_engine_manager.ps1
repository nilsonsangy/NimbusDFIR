# GCP Compute Engine Manager Script - PowerShell
# Author: NimbusDFIR
# Description: Manage GCP VM instances - list, create, start, stop, and delete instances

param(
    [Parameter(Position=0)]
    [ValidateSet('list', 'create', 'delete', 'start', 'stop', 'help')]
    [string]$Command,
    
    [Parameter(Position=1)]
    [string]$InstanceName
)

function Write-GcloudCommand {
    param([string]$Command)
    Write-Host "[gcloud] $Command" -ForegroundColor DarkCyan
}

# Check if gcloud CLI is installed
function Test-GcloudCli {
    try {
        $null = Get-Command gcloud -ErrorAction Stop
        return $true
    }
    catch {
        Write-Host "Error: gcloud CLI is not installed" -ForegroundColor Red
        Write-Host "Please install gcloud CLI first" -ForegroundColor Yellow
        Write-Host "Run: .\install_gcloud_cli_windows.ps1" -ForegroundColor Green
        return $false
    }
}

# Check if authenticated to GCP
function Test-GcloudAuth {
    try {
        Write-GcloudCommand "gcloud auth list --filter=status:ACTIVE --format=`"value(account)`""
        $account = gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>&1
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($account)) {
            Write-Host "Error: Not authenticated to GCP" -ForegroundColor Red
            Write-Host "Please run: gcloud auth login" -ForegroundColor Yellow
            return $false
        }
        return $true
    }
    catch {
        Write-Host "Error: Not authenticated to GCP" -ForegroundColor Red
        Write-Host "Please run: gcloud auth login" -ForegroundColor Yellow
        return $false
    }
}

# Check if project is set
function Test-GcloudProject {
    try {
        Write-GcloudCommand "gcloud config get-value project"
        $project = gcloud config get-value project 2>&1
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($project) -or $project -eq "(unset)") {
            Write-Host "Error: No GCP project configured" -ForegroundColor Red
            Write-Host "Please run: gcloud config set project YOUR_PROJECT_ID" -ForegroundColor Yellow
            return $false
        }
        return $true
    }
    catch {
        Write-Host "Error: No GCP project configured" -ForegroundColor Red
        Write-Host "Please run: gcloud config set project YOUR_PROJECT_ID" -ForegroundColor Yellow
        return $false
    }
}

# Display usage information
function Show-Usage {
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "GCP Compute Engine Manager - NimbusDFIR" -ForegroundColor Blue
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Usage: .\compute_engine_manager.ps1 [COMMAND] [OPTIONS]"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  list              List all VM instances"
    Write-Host "  create            Create a new VM instance"
    Write-Host "  delete            Delete a VM instance"
    Write-Host "  start             Start a stopped instance"
    Write-Host "  stop              Stop a running instance"
    Write-Host "  help              Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\compute_engine_manager.ps1 list"
    Write-Host "  .\compute_engine_manager.ps1 create"
    Write-Host "  .\compute_engine_manager.ps1 delete my-instance"
    Write-Host "  .\compute_engine_manager.ps1 start my-instance"
    Write-Host "  .\compute_engine_manager.ps1 stop my-instance"
    Write-Host ""
}

# List all VM instances
function Get-GceInstances {
    Write-Host "Listing GCP VM Instances..." -ForegroundColor Blue
    Write-Host ""
    
    Write-GcloudCommand "gcloud compute instances list --format=json"
    $instancesJson = gcloud compute instances list --format=json
    
    if ($LASTEXITCODE -ne 0) {
        return
    }
    
    if ([string]::IsNullOrWhiteSpace($instancesJson) -or $instancesJson -eq "[]") {
        Write-Host "No VM instances found" -ForegroundColor Yellow
        return
    }
    
    try {
        $instances = $instancesJson | ConvertFrom-Json
        
        Write-Host "VM Instances:" -ForegroundColor Green
        Write-Host ("="*100) -ForegroundColor Green
        Write-Host "NAME`t`t`tZONE`t`t`tMACHINE_TYPE`t`tSTATUS`t`tEXTERNAL_IP" -ForegroundColor Cyan
        Write-Host ("="*100) -ForegroundColor Green
        
        foreach ($instance in $instances) {
            $name = $instance.name
            $zone = ($instance.zone -split '/')[-1]
            $machineType = ($instance.machineType -split '/')[-1]
            $status = $instance.status
            
            # Get external IP
            $externalIP = "None"
            if ($instance.networkInterfaces -and $instance.networkInterfaces[0].accessConfigs) {
                $externalIP = $instance.networkInterfaces[0].accessConfigs[0].natIP
                if ([string]::IsNullOrWhiteSpace($externalIP)) {
                    $externalIP = "None"
                }
            }
            
            $color = switch ($status) {
                "RUNNING" { "Green" }
                "TERMINATED" { "Yellow" }
                "STOPPING" { "Yellow" }
                "PROVISIONING" { "Cyan" }
                "STAGING" { "Cyan" }
                default { "White" }
            }
            
            Write-Host "$name`t`t$zone`t`t$machineType`t" -NoNewline -ForegroundColor White
            Write-Host "$status`t" -NoNewline -ForegroundColor $color
            Write-Host "$externalIP" -ForegroundColor Gray
        }
        
        Write-Host ""
        Write-Host "Total instances: $($instances.Count)" -ForegroundColor Blue
        
    } catch {
        Write-Host "Error processing VM instances: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Create a new VM instance
function New-GceInstance {
    Write-Host "Create New GCP VM Instance" -ForegroundColor Blue
    Write-Host ""
    
    # Get instance name
    $defaultName = "gcp-vm-$(Get-Random -Minimum 1000 -Maximum 9999)"
    $instanceName = Read-Host "Enter instance name (default: $defaultName)"
    if ([string]::IsNullOrWhiteSpace($instanceName)) {
        $instanceName = $defaultName
        Write-Host "Using default name: $instanceName" -ForegroundColor Cyan
    }
    
    # Validate instance name (lowercase, numbers, hyphens only)
    if ($instanceName -notmatch '^[a-z0-9-]+$') {
        Write-Host "Error: Instance name must contain only lowercase letters, numbers, and hyphens" -ForegroundColor Red
        return
    }
    
    # Get zone
    Write-Host ""
    Write-Host "Select Zone (lowest cost regions):" -ForegroundColor Cyan
    Write-Host "  1. us-central1-a    - Iowa (lowest cost)"
    Write-Host "  2. us-west1-a       - Oregon"
    Write-Host "  3. us-east1-b       - South Carolina"
    Write-Host "  4. us-south1-a      - Dallas"
    Write-Host "  5. europe-west4-a   - Netherlands"
    Write-Host ""
    $zoneChoice = Read-Host "Choose zone [1-5] (default: 1)"
    if ([string]::IsNullOrWhiteSpace($zoneChoice)) {
        $zoneChoice = "1"
    }
    
    $zone = switch ($zoneChoice) {
        "1" { "us-central1-a" }
        "2" { "us-west1-a" }
        "3" { "us-east1-b" }
        "4" { "us-south1-a" }
        "5" { "europe-west4-a" }
        default { "us-central1-a" }
    }
    
    # Get machine type
    Write-Host ""
    Write-Host "Select Machine Type:" -ForegroundColor Cyan
    Write-Host "  1. e2-micro       - 2 vCPU, 1 GB RAM   (lowest cost)"
    Write-Host "  2. e2-small       - 2 vCPU, 2 GB RAM"
    Write-Host "  3. e2-medium      - 2 vCPU, 4 GB RAM"
    Write-Host "  4. e2-standard-2  - 2 vCPU, 8 GB RAM"
    Write-Host "  5. n1-standard-1  - 1 vCPU, 3.75 GB RAM"
    Write-Host ""
    $machineChoice = Read-Host "Choose machine type [1-5] (default: 1)"
    if ([string]::IsNullOrWhiteSpace($machineChoice)) {
        $machineChoice = "1"
    }
    
    $machineType = switch ($machineChoice) {
        "1" { "e2-micro" }
        "2" { "e2-small" }
        "3" { "e2-medium" }
        "4" { "e2-standard-2" }
        "5" { "n1-standard-1" }
        default { "e2-micro" }
    }
    
    # Get image
    Write-Host ""
    Write-Host "Select Image:" -ForegroundColor Cyan
    Write-Host "  1. Ubuntu 22.04 LTS"
    Write-Host "  2. Ubuntu 24.04 LTS"
    Write-Host "  3. Debian 11"
    Write-Host "  4. Debian 12"
    Write-Host "  5. CentOS Stream 9"
    Write-Host ""
    $imageChoice = Read-Host "Choose image [1-5] (default: 1)"
    if ([string]::IsNullOrWhiteSpace($imageChoice)) {
        $imageChoice = "1"
    }
    
    $imageProject = ""
    $imageFamily = ""
    
    switch ($imageChoice) {
        "1" { 
            $imageProject = "ubuntu-os-cloud"
            $imageFamily = "ubuntu-2204-lts"
        }
        "2" { 
            $imageProject = "ubuntu-os-cloud"
            $imageFamily = "ubuntu-2404-lts-amd64"
        }
        "3" { 
            $imageProject = "debian-cloud"
            $imageFamily = "debian-11"
        }
        "4" { 
            $imageProject = "debian-cloud"
            $imageFamily = "debian-12"
        }
        "5" { 
            $imageProject = "centos-cloud"
            $imageFamily = "centos-stream-9"
        }
        default { 
            $imageProject = "ubuntu-os-cloud"
            $imageFamily = "ubuntu-2204-lts"
        }
    }
    
    # Ask about boot disk size
    Write-Host ""
    $diskSize = Read-Host "Enter boot disk size in GB (default: 10)"
    if ([string]::IsNullOrWhiteSpace($diskSize)) {
        $diskSize = "10"
    }
    
    # Build command
    $cmd = "gcloud compute instances create $instanceName --zone=$zone --machine-type=$machineType --image-project=$imageProject --image-family=$imageFamily --boot-disk-size=${diskSize}GB --boot-disk-type=pd-standard"
    
    # Ask about preemptible (spot) instance
    Write-Host ""
    $preemptible = Read-Host "Create as preemptible (spot) instance? Lower cost but can be terminated (y/N)"
    if ($preemptible -eq "y" -or $preemptible -eq "Y") {
        $cmd += " --preemptible"
    }
    
    Write-Host ""
    Write-Host "Creating VM instance... (this may take a few minutes)" -ForegroundColor Yellow
    Write-Host "[INFO] Instance: $instanceName | Zone: $zone | Type: $machineType | Image: $imageFamily" -ForegroundColor Blue
    Write-Host ""
    Write-GcloudCommand $cmd
    
    Invoke-Expression $cmd
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "✓ VM instance created successfully!" -ForegroundColor Green
        Write-Host ""
        
        # Get instance details
        Write-Host "Instance Details:" -ForegroundColor Cyan
        Write-GcloudCommand "gcloud compute instances describe $instanceName --zone=$zone --format=`"table(name,status,networkInterfaces[0].networkIP,networkInterfaces[0].accessConfigs[0].natIP)`""
        gcloud compute instances describe $instanceName --zone=$zone --format="table(name,status,networkInterfaces[0].networkIP,networkInterfaces[0].accessConfigs[0].natIP)"
    } else {
        Write-Host "✗ Failed to create VM instance" -ForegroundColor Red
        exit 1
    }
}

# Delete a VM instance
function Remove-GceInstance {
    param([string]$InstanceName)
    
    if ([string]::IsNullOrWhiteSpace($InstanceName)) {
        # List instances and let user choose
        Write-Host "Available VM instances:" -ForegroundColor Cyan
        Write-Host ""
        
        Write-GcloudCommand "gcloud compute instances list --format=json"
        $instancesJson = gcloud compute instances list --format=json 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Failed to retrieve VM instances" -ForegroundColor Red
            return
        }
        
        if ([string]::IsNullOrWhiteSpace($instancesJson) -or $instancesJson -eq "[]") {
            Write-Host "No VM instances found" -ForegroundColor Yellow
            return
        }
        
        $instances = $instancesJson | ConvertFrom-Json
        
        # Display numbered list
        for ($i = 0; $i -lt $instances.Count; $i++) {
            $inst = $instances[$i]
            $zone = ($inst.zone -split '/')[-1]
            Write-Host "  $($i + 1). $($inst.name) ($zone) - $($inst.status)" -ForegroundColor White
        }
        
        Write-Host ""
        $selection = Read-Host "Select VM to delete [1-$($instances.Count)] or 0 to cancel"
        
        if ($selection -eq "0" -or [string]::IsNullOrWhiteSpace($selection)) {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
            return
        }
        
        try {
            $selectedIndex = [int]$selection - 1
            if ($selectedIndex -lt 0 -or $selectedIndex -ge $instances.Count) {
                Write-Host "Invalid selection" -ForegroundColor Red
                return
            }
            
            $InstanceName = $instances[$selectedIndex].name
            $zone = ($instances[$selectedIndex].zone -split '/')[-1]
        }
        catch {
            Write-Host "Invalid selection" -ForegroundColor Red
            return
        }
    }
    else {
        # Get zone for specified instance
        Write-GcloudCommand "gcloud compute instances list --filter=`"name=$InstanceName`" --format=`"value(zone)`""
        $zone = gcloud compute instances list --filter="name=$InstanceName" --format="value(zone)" 2>&1
        
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($zone)) {
            Write-Host "Error: Instance '$InstanceName' not found" -ForegroundColor Red
            return
        }
        
        $zone = ($zone -split '/')[-1]
    }
    
    Write-Host ""
    Write-Host "Instance: $InstanceName (Zone: $zone)" -ForegroundColor Yellow
    $confirm = Read-Host "Are you sure you want to delete this VM? (y/N)"
    
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Deletion cancelled" -ForegroundColor Yellow
        return
    }
    
    Write-Host ""
    Write-Host "Deleting VM instance..." -ForegroundColor Yellow
    Write-GcloudCommand "gcloud compute instances delete $InstanceName --zone=$zone --quiet"
    gcloud compute instances delete $InstanceName --zone=$zone --quiet
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ VM instance deleted successfully" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to delete VM instance" -ForegroundColor Red
        exit 1
    }
}

# Start a VM instance
function Start-GceInstance {
    param([string]$InstanceName)
    
    if ([string]::IsNullOrWhiteSpace($InstanceName)) {
        # List stopped instances
        Write-Host "Available stopped VM instances:" -ForegroundColor Cyan
        Write-Host ""
        
        Write-GcloudCommand "gcloud compute instances list --filter=`"status:TERMINATED`" --format=json"
        $instancesJson = gcloud compute instances list --filter="status:TERMINATED" --format=json 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Failed to retrieve VM instances" -ForegroundColor Red
            return
        }
        
        if ([string]::IsNullOrWhiteSpace($instancesJson) -or $instancesJson -eq "[]") {
            Write-Host "No stopped VM instances found" -ForegroundColor Yellow
            return
        }
        
        $instances = $instancesJson | ConvertFrom-Json
        
        # Display numbered list
        for ($i = 0; $i -lt $instances.Count; $i++) {
            $inst = $instances[$i]
            $zone = ($inst.zone -split '/')[-1]
            Write-Host "  $($i + 1). $($inst.name) ($zone)" -ForegroundColor White
        }
        
        Write-Host ""
        $selection = Read-Host "Select VM to start [1-$($instances.Count)] or 0 to cancel"
        
        if ($selection -eq "0" -or [string]::IsNullOrWhiteSpace($selection)) {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
            return
        }
        
        try {
            $selectedIndex = [int]$selection - 1
            if ($selectedIndex -lt 0 -or $selectedIndex -ge $instances.Count) {
                Write-Host "Invalid selection" -ForegroundColor Red
                return
            }
            
            $InstanceName = $instances[$selectedIndex].name
            $zone = ($instances[$selectedIndex].zone -split '/')[-1]
        }
        catch {
            Write-Host "Invalid selection" -ForegroundColor Red
            return
        }
    }
    else {
        # Get zone for specified instance
        Write-GcloudCommand "gcloud compute instances list --filter=`"name=$InstanceName`" --format=`"value(zone)`""
        $zone = gcloud compute instances list --filter="name=$InstanceName" --format="value(zone)" 2>&1
        
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($zone)) {
            Write-Host "Error: Instance '$InstanceName' not found" -ForegroundColor Red
            return
        }
        
        $zone = ($zone -split '/')[-1]
    }
    
    Write-Host "Starting VM instance: $InstanceName" -ForegroundColor Yellow
    Write-GcloudCommand "gcloud compute instances start $InstanceName --zone=$zone"
    gcloud compute instances start $InstanceName --zone=$zone
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ VM instance started successfully" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to start VM instance" -ForegroundColor Red
        exit 1
    }
}

# Stop a VM instance
function Stop-GceInstance {
    param([string]$InstanceName)
    
    if ([string]::IsNullOrWhiteSpace($InstanceName)) {
        # List running instances
        Write-Host "Available running VM instances:" -ForegroundColor Cyan
        Write-Host ""
        
        Write-GcloudCommand "gcloud compute instances list --filter=`"status:RUNNING`" --format=json"
        $instancesJson = gcloud compute instances list --filter="status:RUNNING" --format=json 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Failed to retrieve VM instances" -ForegroundColor Red
            return
        }
        
        if ([string]::IsNullOrWhiteSpace($instancesJson) -or $instancesJson -eq "[]") {
            Write-Host "No running VM instances found" -ForegroundColor Yellow
            return
        }
        
        $instances = $instancesJson | ConvertFrom-Json
        
        # Display numbered list
        for ($i = 0; $i -lt $instances.Count; $i++) {
            $inst = $instances[$i]
            $zone = ($inst.zone -split '/')[-1]
            Write-Host "  $($i + 1). $($inst.name) ($zone)" -ForegroundColor White
        }
        
        Write-Host ""
        $selection = Read-Host "Select VM to stop [1-$($instances.Count)] or 0 to cancel"
        
        if ($selection -eq "0" -or [string]::IsNullOrWhiteSpace($selection)) {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
            return
        }
        
        try {
            $selectedIndex = [int]$selection - 1
            if ($selectedIndex -lt 0 -or $selectedIndex -ge $instances.Count) {
                Write-Host "Invalid selection" -ForegroundColor Red
                return
            }
            
            $InstanceName = $instances[$selectedIndex].name
            $zone = ($instances[$selectedIndex].zone -split '/')[-1]
        }
        catch {
            Write-Host "Invalid selection" -ForegroundColor Red
            return
        }
    }
    else {
        # Get zone for specified instance
        Write-GcloudCommand "gcloud compute instances list --filter=`"name=$InstanceName`" --format=`"value(zone)`""
        $zone = gcloud compute instances list --filter="name=$InstanceName" --format="value(zone)" 2>&1
        
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($zone)) {
            Write-Host "Error: Instance '$InstanceName' not found" -ForegroundColor Red
            return
        }
        
        $zone = ($zone -split '/')[-1]
    }
    
    Write-Host "Stopping VM instance: $InstanceName" -ForegroundColor Yellow
    Write-GcloudCommand "gcloud compute instances stop $InstanceName --zone=$zone"
    gcloud compute instances stop $InstanceName --zone=$zone
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ VM instance stopped successfully" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to stop VM instance" -ForegroundColor Red
        exit 1
    }
}

# Main script logic
if (-not (Test-GcloudCli)) {
    exit 1
}

if (-not (Test-GcloudAuth)) {
    exit 1
}

if (-not (Test-GcloudProject)) {
    exit 1
}

switch ($Command.ToLower()) {
    "list" {
        Get-GceInstances
    }
    "create" {
        New-GceInstance
    }
    "delete" {
        Remove-GceInstance -InstanceName $InstanceName
    }
    "start" {
        Start-GceInstance -InstanceName $InstanceName
    }
    "stop" {
        Stop-GceInstance -InstanceName $InstanceName
    }
    "help" {
        Show-Usage
    }
    default {
        Show-Usage
        exit 1
    }
}
