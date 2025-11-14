# EC2 Manager Script - PowerShell
# Author: NimbusDFIR
# Description: Manage EC2 instances - list, create, start, stop, and terminate instances

param(
    [Parameter(Position=0)]
    [ValidateSet('list', 'create', 'remove', 'terminate', 'start', 'stop', 'help')]
    [string]$Command,
    
    [Parameter(Position=1)]
    [string]$InstanceId
)

# Check if AWS CLI is installed
function Test-AwsCli {
    try {
        $null = Get-Command aws -ErrorAction Stop
        return $true
    }
    catch {
        Write-Host "Error: AWS CLI is not installed" -ForegroundColor Red
        Write-Host "Please install AWS CLI first"
        return $false
    }
}

# Check if AWS credentials are configured
function Test-AwsCredentials {
    try {
        $null = aws sts get-caller-identity 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: AWS credentials not configured" -ForegroundColor Red
            Write-Host "Please run: aws configure"
            return $false
        }
        return $true
    }
    catch {
        Write-Host "Error: AWS credentials not configured" -ForegroundColor Red
        Write-Host "Please run: aws configure"
        return $false
    }
}

# Display usage information
function Show-Usage {
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "EC2 Manager - NimbusDFIR"
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Usage: .\ec2_manager.ps1 [COMMAND] [OPTIONS]"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  list              List all EC2 instances"
    Write-Host "  create            Create a new EC2 instance"
    Write-Host "  remove            Terminate an EC2 instance"
    Write-Host "  start             Start a stopped instance"
    Write-Host "  stop              Stop a running instance"
    Write-Host "  help              Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\ec2_manager.ps1 list"
    Write-Host "  .\ec2_manager.ps1 create"
    Write-Host "  .\ec2_manager.ps1 remove i-1234567890abcdef0"
    Write-Host "  .\ec2_manager.ps1 start i-1234567890abcdef0"
    Write-Host "  .\ec2_manager.ps1 stop i-1234567890abcdef0"
    Write-Host ""
}

# List all EC2 instances
function Get-Ec2Instances {
    Write-Host "Listing EC2 Instances..." -ForegroundColor Blue
    Write-Host ""
    
    $instances = aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,PublicIpAddress,PrivateIpAddress,Tags[?Key==`Name`].Value|[0]]' --output json | ConvertFrom-Json
    
    if (-not $instances -or $instances.Count -eq 0) {
        Write-Host "No EC2 instances found" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Instance ID`t`tType`t`tState`t`tPublic IP`tPrivate IP`tName" -ForegroundColor Green
    Write-Host "--------------------------------------------------------------------------------------------------------"
    
    foreach ($reservation in $instances) {
        foreach ($instance in $reservation) {
            $id = $instance[0]
            $type = $instance[1]
            $state = $instance[2]
            $publicIp = if ($instance[3]) { $instance[3] } else { "N/A" }
            $privateIp = if ($instance[4]) { $instance[4] } else { "N/A" }
            $name = if ($instance[5]) { $instance[5] } else { "N/A" }
            
            $color = switch ($state) {
                "running" { "Green" }
                "stopped" { "Yellow" }
                default { "White" }
            }
            
            Write-Host "$id`t$type`t$state`t`t$publicIp`t$privateIp`t$name" -ForegroundColor $color
        }
    }
}

# Create a new EC2 instance
function New-Ec2Instance {
    Write-Host "Create New EC2 Instance" -ForegroundColor Blue
    Write-Host ""
    
    # Get AMI ID
    $amiId = Read-Host "Enter AMI ID (press Enter for Amazon Linux 2023 in current region)"
    if ([string]::IsNullOrWhiteSpace($amiId)) {
        Write-Host "Getting latest Amazon Linux 2023 AMI..." -ForegroundColor Yellow
        $amiId = aws ec2 describe-images --owners amazon --filters "Name=name,Values=al2023-ami-2023*-x86_64" --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' --output text
        Write-Host "Using AMI: $amiId"
    }
    
    # Get instance type
    $instanceType = Read-Host "Enter instance type (default: t2.micro)"
    if ([string]::IsNullOrWhiteSpace($instanceType)) {
        $instanceType = "t2.micro"
    }
    
    # Get key pair name
    $keyName = Read-Host "Enter key pair name (optional)"
    
    # Get security group
    $securityGroup = Read-Host "Enter security group ID (optional)"
    
    # Get subnet
    $subnetId = Read-Host "Enter subnet ID (optional)"
    
    # Get instance name
    $instanceName = Read-Host "Enter instance name tag"
    
    # Build command
    $cmd = "aws ec2 run-instances --image-id $amiId --instance-type $instanceType --count 1"
    
    if (-not [string]::IsNullOrWhiteSpace($keyName)) {
        $cmd += " --key-name $keyName"
    }
    
    if (-not [string]::IsNullOrWhiteSpace($securityGroup)) {
        $cmd += " --security-group-ids $securityGroup"
    }
    
    if (-not [string]::IsNullOrWhiteSpace($subnetId)) {
        $cmd += " --subnet-id $subnetId"
    }
    
    if (-not [string]::IsNullOrWhiteSpace($instanceName)) {
        $cmd += " --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=$instanceName}]'"
    }
    
    Write-Host ""
    Write-Host "Creating instance..." -ForegroundColor Yellow
    
    $result = Invoke-Expression "$cmd --output json" | ConvertFrom-Json
    $newInstanceId = $result.Instances[0].InstanceId
    
    if ($newInstanceId) {
        Write-Host "✓ Instance created successfully!" -ForegroundColor Green
        Write-Host "Instance ID: $newInstanceId"
        Write-Host ""
        Write-Host "Waiting for instance to start..."
        aws ec2 wait instance-running --instance-ids $newInstanceId
        Write-Host "✓ Instance is now running" -ForegroundColor Green
        
        # Get instance details
        $publicIp = aws ec2 describe-instances --instance-ids $newInstanceId --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
        
        if ($publicIp -and $publicIp -ne "None") {
            Write-Host "Public IP: $publicIp"
        }
    }
    else {
        Write-Host "✗ Failed to create instance" -ForegroundColor Red
    }
}

# Remove/terminate an EC2 instance
function Remove-Ec2Instance {
    param([string]$InstanceId)
    
    if ([string]::IsNullOrWhiteSpace($InstanceId)) {
        Write-Host "Available instances:" -ForegroundColor Yellow
        Get-Ec2Instances
        Write-Host ""
        $InstanceId = Read-Host "Enter instance ID to terminate"
    }
    
    if ([string]::IsNullOrWhiteSpace($InstanceId)) {
        Write-Host "Error: Instance ID is required" -ForegroundColor Red
        return
    }
    
    # Verify instance exists
    try {
        $null = aws ec2 describe-instances --instance-ids $InstanceId 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Instance $InstanceId not found" -ForegroundColor Red
            return
        }
    }
    catch {
        Write-Host "Error: Instance $InstanceId not found" -ForegroundColor Red
        return
    }
    
    Write-Host "WARNING: This will terminate instance $InstanceId" -ForegroundColor Yellow
    $confirm = Read-Host "Are you sure? (yes/no)"
    
    if ($confirm -ne "yes") {
        Write-Host "Operation cancelled"
        return
    }
    
    Write-Host "Terminating instance..."
    $null = aws ec2 terminate-instances --instance-ids $InstanceId
    
    Write-Host "✓ Instance $InstanceId is being terminated" -ForegroundColor Green
}

# Start a stopped EC2 instance
function Start-Ec2Instance {
    param([string]$InstanceId)
    
    if ([string]::IsNullOrWhiteSpace($InstanceId)) {
        Write-Host "Available stopped instances:" -ForegroundColor Yellow
        aws ec2 describe-instances --filters "Name=instance-state-name,Values=stopped" --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' --output text
        Write-Host ""
        $InstanceId = Read-Host "Enter instance ID to start"
    }
    
    if ([string]::IsNullOrWhiteSpace($InstanceId)) {
        Write-Host "Error: Instance ID is required" -ForegroundColor Red
        return
    }
    
    Write-Host "Starting instance $InstanceId..."
    $null = aws ec2 start-instances --instance-ids $InstanceId
    
    Write-Host "✓ Instance $InstanceId is starting" -ForegroundColor Green
    Write-Host "Waiting for instance to be running..."
    aws ec2 wait instance-running --instance-ids $InstanceId
    Write-Host "✓ Instance is now running" -ForegroundColor Green
}

# Stop a running EC2 instance
function Stop-Ec2Instance {
    param([string]$InstanceId)
    
    if ([string]::IsNullOrWhiteSpace($InstanceId)) {
        Write-Host "Available running instances:" -ForegroundColor Yellow
        aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' --output text
        Write-Host ""
        $InstanceId = Read-Host "Enter instance ID to stop"
    }
    
    if ([string]::IsNullOrWhiteSpace($InstanceId)) {
        Write-Host "Error: Instance ID is required" -ForegroundColor Red
        return
    }
    
    Write-Host "Stopping instance $InstanceId..."
    $null = aws ec2 stop-instances --instance-ids $InstanceId
    
    Write-Host "✓ Instance $InstanceId is stopping" -ForegroundColor Green
}

# Main script execution
if (-not (Test-AwsCli)) {
    exit 1
}

if (-not (Test-AwsCredentials)) {
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Command)) {
    Show-Usage
    exit 0
}

switch ($Command) {
    'list' {
        Get-Ec2Instances
    }
    'create' {
        New-Ec2Instance
    }
    { $_ -in 'remove', 'terminate' } {
        Remove-Ec2Instance -InstanceId $InstanceId
    }
    'start' {
        Start-Ec2Instance -InstanceId $InstanceId
    }
    'stop' {
        Stop-Ec2Instance -InstanceId $InstanceId
    }
    'help' {
        Show-Usage
    }
    default {
        Write-Host "Error: Unknown command '$Command'" -ForegroundColor Red
        Write-Host ""
        Show-Usage
        exit 1
    }
}
