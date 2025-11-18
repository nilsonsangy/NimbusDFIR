# EC2 Evidence Preservation Script - PowerShell
# Author: NimbusDFIR
# Description: Digital forensics and incident response tools for EC2 instances
# Functions: isolate instances, create EBS snapshots for evidence preservation

param(
    [Parameter(Position=0)]
    [ValidateSet('isolate', 'snapshot', 'help')]
    [string]$Command,
    
    [Parameter(Position=1)]
    [string]$SubCommand,
    
    [Parameter(Position=2)]
    [string]$InstanceId
)

# Check if AWS CLI is installed
function Test-AwsCli {
    try {
        $null = aws --version 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: AWS CLI is not installed or not in PATH" -ForegroundColor Red
            Write-Host "Please install AWS CLI from: https://aws.amazon.com/cli/" -ForegroundColor Yellow
            return $false
        }
        return $true
    } catch {
        Write-Host "Error: AWS CLI is not installed or not in PATH" -ForegroundColor Red
        Write-Host "Please install AWS CLI from: https://aws.amazon.com/cli/" -ForegroundColor Yellow
        return $false
    }
}

# Check AWS credentials
function Test-AwsCredentials {
    try {
        $null = aws sts get-caller-identity 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: AWS credentials not configured" -ForegroundColor Red
            Write-Host "Please run 'aws configure' to set up your credentials" -ForegroundColor Yellow
            return $false
        }
        return $true
    } catch {
        Write-Host "Error: AWS credentials not configured" -ForegroundColor Red
        Write-Host "Please run 'aws configure' to set up your credentials" -ForegroundColor Yellow
        return $false
    }
}

# Show usage information
function Show-Usage {
    Write-Host ""
    Write-Host "EC2 Evidence Preservation Tool" -ForegroundColor Green
    Write-Host ("="*50) -ForegroundColor Green
    Write-Host ""
    Write-Host "DESCRIPTION:" -ForegroundColor Cyan
    Write-Host "  Digital forensics and incident response tools for AWS EC2 instances"
    Write-Host "  Provides isolation and evidence preservation capabilities"
    Write-Host ""
    Write-Host "USAGE:" -ForegroundColor Cyan
    Write-Host "  .\ec2_evidence_preservation.ps1 <command> [instance-id]"
    Write-Host ""
    Write-Host "COMMANDS:" -ForegroundColor Cyan
    Write-Host "  isolate          - Isolate EC2 instance for incident response"
    Write-Host "  snapshot         - Create EBS snapshot for evidence preservation"
    Write-Host "  snapshot delete  - Delete EBS snapshot (use with caution)"
    Write-Host "  help             - Show this help message"
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Cyan
    Write-Host "  .\ec2_evidence_preservation.ps1 isolate i-1234567890abcdef0"
    Write-Host "  .\ec2_evidence_preservation.ps1 isolate"
    Write-Host "  .\ec2_evidence_preservation.ps1 snapshot i-1234567890abcdef0"
    Write-Host "  .\ec2_evidence_preservation.ps1 snapshot"
    Write-Host "  .\ec2_evidence_preservation.ps1 snapshot delete snap-1234567890abcdef0"
    Write-Host "  .\ec2_evidence_preservation.ps1 snapshot delete"
    Write-Host ""
    Write-Host "INCIDENT RESPONSE WORKFLOW:" -ForegroundColor Red
    Write-Host "  1. Use 'isolate' to quarantine compromised instance"
    Write-Host "  2. Use 'snapshot' to preserve evidence"
    Write-Host "  3. Document all actions for chain of custody"
    Write-Host ""
}

# Get list of EC2 instances for selection
function Get-InstanceSelection {
    param(
        [string]$Purpose = "process"
    )
    
    Write-Host ""
    Write-Host "Available EC2 Instances:" -ForegroundColor Cyan
    Write-Host ("-"*40) -ForegroundColor Cyan
    
    # Get instances
    $awsOutput = aws ec2 describe-instances --output json
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Failed to retrieve EC2 instances" -ForegroundColor Red
        return $null
    }
    
    $ec2Data = $awsOutput | ConvertFrom-Json
    $instances = @()
    $index = 1
    
    foreach ($reservation in $ec2Data.Reservations) {
        foreach ($instance in $reservation.Instances) {
            if ($instance.State.Name -ne "terminated") {
                $name = "No Name"
                if ($instance.Tags) {
                    $nameTag = $instance.Tags | Where-Object { $_.Key -eq "Name" }
                    if ($nameTag) {
                        $name = $nameTag.Value
                    }
                }
                
                $instances += [PSCustomObject]@{
                    Index = $index
                    InstanceId = $instance.InstanceId
                    Name = $name
                    State = $instance.State.Name
                    Type = $instance.InstanceType
                }
                
                $color = switch ($instance.State.Name) {
                    "running" { "Green" }
                    "stopped" { "Yellow" }
                    default { "White" }
                }
                
                Write-Host "$index. " -NoNewline -ForegroundColor White
                Write-Host "$($instance.InstanceId) | $name | " -NoNewline -ForegroundColor Cyan
                Write-Host $instance.State.Name -ForegroundColor $color
                
                $index++
            }
        }
    }
    
    if ($instances.Count -eq 0) {
        Write-Host "No EC2 instances available for $Purpose" -ForegroundColor Yellow
        return $null
    }
    
    Write-Host ""
    $selection = Read-Host "Select instance to $Purpose (1-$($instances.Count)) or 'q' to quit"
    
    if ($selection -eq 'q' -or $selection -eq 'Q') {
        Write-Host "Operation cancelled" -ForegroundColor Yellow
        return $null
    }
    
    try {
        $selectedIndex = [int]$selection
        if ($selectedIndex -lt 1 -or $selectedIndex -gt $instances.Count) {
            Write-Host "Invalid selection. Please select a number between 1 and $($instances.Count)" -ForegroundColor Red
            return $null
        }
        
        $selectedInstance = $instances[$selectedIndex - 1]
        Write-Host ""
        Write-Host "Selected instance: $($selectedInstance.InstanceId) ($($selectedInstance.Name))" -ForegroundColor Cyan
        return $selectedInstance.InstanceId
    } catch {
        Write-Host "Invalid selection. Please enter a valid number" -ForegroundColor Red
        return $null
    }
}

# Generate evidence documentation
function New-EvidenceReport {
    param(
        [string]$InstanceId,
        [string]$Action,
        [hashtable]$Details
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
    $reportFileName = "evidence-report-$InstanceId-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    
    # Get default Downloads folder
    $defaultPath = [System.IO.Path]::Combine($env:USERPROFILE, "Downloads")
    
    Write-Host ""
    Write-Host "EVIDENCE REPORT LOCATION:" -ForegroundColor Cyan
    Write-Host "Default location: $defaultPath" -ForegroundColor Yellow
    $customPath = Read-Host "Enter custom path (press Enter for default Downloads folder)"
    
    if ([string]::IsNullOrWhiteSpace($customPath)) {
        $savePath = $defaultPath
    } else {
        # Validate custom path
        if (Test-Path $customPath) {
            $savePath = $customPath
        } else {
            Write-Host "Warning: Path '$customPath' does not exist. Using default Downloads folder." -ForegroundColor Yellow
            $savePath = $defaultPath
        }
    }
    
    # Ensure Downloads folder exists
    if (!(Test-Path $savePath)) {
        try {
            New-Item -ItemType Directory -Path $savePath -Force | Out-Null
            Write-Host "Created directory: $savePath" -ForegroundColor Green
        } catch {
            Write-Host "Error creating directory. Using current folder." -ForegroundColor Red
            $savePath = "."
        }
    }
    
    $reportFile = Join-Path $savePath $reportFileName
    
    $report = @"
================================================================================
AWS EC2 DIGITAL EVIDENCE PRESERVATION REPORT
================================================================================

CASE INFORMATION:
  Instance ID: $InstanceId
  Action Performed: $Action
  Timestamp: $timestamp
  Operator: $env:USERNAME
  Computer: $env:COMPUTERNAME
  AWS Region: $(aws configure get region 2>$null)

EVIDENCE DETAILS:
"@
    
    foreach ($key in $Details.Keys) {
        $report += "`n  $key`: $($Details[$key])"
    }
    
    $report += @"


CHAIN OF CUSTODY:
  - Digital evidence preserved using AWS native tools
  - All actions logged with timestamps and operator identification
  - Evidence integrity maintained through AWS checksums and metadata

VERIFICATION STEPS:
  - Verify snapshot integrity using AWS console or CLI
  - Document snapshot ID and creation timestamp
  - Preserve this report as part of case documentation

NEXT STEPS FOR DIGITAL FORENSICS ANALYST:
  - Create EBS volume from snapshot for analysis
  - Mount volume in isolated forensic workstation
  - Perform disk imaging if required for legal proceedings
  - Calculate and document hash values for court admissibility

================================================================================
Report generated by NimbusDFIR EC2 Evidence Preservation Tool
================================================================================
"@
    
    $report | Out-File -FilePath $reportFile -Encoding UTF8
    return $reportFile
}

# Isolate EC2 instance for incident response
function Invoke-Ec2Isolate {
    param(
        [string]$InstanceId
    )
    
    Write-Host "EC2 Instance Isolation for Incident Response" -ForegroundColor Red
    Write-Host ("="*50) -ForegroundColor Red
    Write-Host ""
    
    try {
        # Create quarantine security group if it doesn't exist
        $quarantineSgName = "ec2-quarantine-sg"
        $quarantineSgDescription = "Quarantine Security Group for Incident Response - Blocks all traffic"
        
        Write-Host "Checking for quarantine security group..." -ForegroundColor Yellow
        
        # Check if quarantine SG exists
        $existingSg = aws ec2 describe-security-groups --group-names $quarantineSgName --output json 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Creating quarantine security group..." -ForegroundColor Yellow
            
            # Get default VPC
            $defaultVpc = aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text
            
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($defaultVpc)) {
                Write-Host "Error: Could not find default VPC" -ForegroundColor Red
                return
            }
            
            # Create quarantine security group
            $sgResult = aws ec2 create-security-group --group-name $quarantineSgName --description $quarantineSgDescription --vpc-id $defaultVpc --output json
            
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Error: Failed to create quarantine security group" -ForegroundColor Red
                return
            }
            
            $sgData = $sgResult | ConvertFrom-Json
            $quarantineSgId = $sgData.GroupId
            
            Write-Host "Created quarantine security group: $quarantineSgId" -ForegroundColor Green
            
            # Remove default egress rule (allow all outbound)
            aws ec2 revoke-security-group-egress --group-id $quarantineSgId --protocol "-1" --cidr "0.0.0.0/0" 2>$null
            
            Write-Host "Quarantine security group configured (no inbound/outbound traffic allowed)" -ForegroundColor Green
        } else {
            $sgData = $existingSg | ConvertFrom-Json
            $quarantineSgId = $sgData.SecurityGroups[0].GroupId
            Write-Host "Using existing quarantine security group: $quarantineSgId" -ForegroundColor Green
        }
        
        # If no instance ID provided, let user select from list
        if ([string]::IsNullOrWhiteSpace($InstanceId)) {
            $InstanceId = Get-InstanceSelection -Purpose "isolate"
            if ([string]::IsNullOrWhiteSpace($InstanceId)) {
                return
            }
        }
        
        # Verify instance exists and get current security groups
        Write-Host "Verifying instance $InstanceId..." -ForegroundColor Yellow
        
        $instanceData = aws ec2 describe-instances --instance-ids $InstanceId --output json 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Instance $InstanceId not found" -ForegroundColor Red
            return
        }
        
        $instanceInfo = ($instanceData | ConvertFrom-Json).Reservations[0].Instances[0]
        $currentSgs = $instanceInfo.SecurityGroups
        
        Write-Host "Current security groups:" -ForegroundColor Yellow
        foreach ($sg in $currentSgs) {
            Write-Host "  - $($sg.GroupId) ($($sg.GroupName))" -ForegroundColor White
        }
        
        # Confirm isolation
        Write-Host ""
        Write-Host "WARNING: This will isolate the instance by replacing all security groups with quarantine SG" -ForegroundColor Red
        Write-Host "The instance will be completely isolated from network traffic" -ForegroundColor Red
        $confirm = Read-Host "Are you sure you want to proceed? (y/N)"
        
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
            return
        }
        
        # Store original security groups for potential restoration
        $tempPath = [System.IO.Path]::GetTempPath()
        $originalSgsFileName = "original-sgs-$InstanceId.json"
        $originalSgsFile = Join-Path $tempPath $originalSgsFileName
        
        $originalSgs = @()
        foreach ($sg in $currentSgs) {
            $originalSgs += $sg.GroupId
        }
        $originalSgs | ConvertTo-Json | Out-File -FilePath $originalSgsFile -Encoding UTF8
        Write-Host "Original security groups saved to: $originalSgsFile" -ForegroundColor Green
        
        # Apply quarantine security group
        Write-Host "Applying quarantine security group..." -ForegroundColor Yellow
        
        $isolateResult = aws ec2 modify-instance-attribute --instance-id $InstanceId --groups $quarantineSgId 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Failed to apply quarantine security group" -ForegroundColor Red
            return
        }
        
        # Generate evidence report for isolation
        $evidenceDetails = @{
            "Quarantine Security Group" = $quarantineSgId
            "Original Security Groups" = ($originalSgs -join ", ")
            "Instance State" = $instanceInfo.State.Name
            "Instance Type" = $instanceInfo.InstanceType
            "Availability Zone" = $instanceInfo.Placement.AvailabilityZone
            "Launch Time" = $instanceInfo.LaunchTime
            "Original SG Backup File" = $originalSgsFile
        }
        
        $reportFile = New-EvidenceReport -InstanceId $InstanceId -Action "NETWORK_ISOLATION" -Details $evidenceDetails
        
        Write-Host ""
        Write-Host "✓ Instance $InstanceId has been successfully isolated!" -ForegroundColor Green
        Write-Host "✓ Applied quarantine security group: $quarantineSgId" -ForegroundColor Green
        Write-Host "✓ All network traffic blocked (inbound and outbound)" -ForegroundColor Green
        Write-Host "✓ Original security groups backed up to: $originalSgsFile" -ForegroundColor Green
        Write-Host "✓ Evidence report generated: $reportFile" -ForegroundColor Green
        Write-Host ""
        Write-Host "INCIDENT RESPONSE NOTE:" -ForegroundColor Red
        Write-Host "- Instance is now isolated for forensic analysis" -ForegroundColor Yellow
        Write-Host "- Consider creating EBS snapshots for evidence preservation" -ForegroundColor Yellow
        Write-Host "- Document the isolation time and reason in case file" -ForegroundColor Yellow
        Write-Host "- To restore connectivity, restore original security groups from backup file" -ForegroundColor Yellow
        
        # Ask if user wants to create EBS snapshot
        Write-Host ""
        $createSnapshot = Read-Host "Do you want to create an EBS snapshot for evidence preservation? (y/N)"
        
        if ($createSnapshot -eq 'y' -or $createSnapshot -eq 'Y') {
            Write-Host ""
            Write-Host "Creating EBS snapshot..." -ForegroundColor Cyan
            Invoke-Ec2Snapshot -InstanceId $InstanceId
        }
        
    } catch {
        Write-Host "Error during isolation process: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Delete EBS snapshot
function Invoke-SnapshotDelete {
    param(
        [string]$SnapshotId
    )
    
    Write-Host "EBS Snapshot Deletion" -ForegroundColor Red
    Write-Host ("="*50) -ForegroundColor Red
    Write-Host ""
    
    try {
        # If no snapshot ID provided, let user select from list
        if ([string]::IsNullOrWhiteSpace($SnapshotId)) {
            Write-Host "Available EBS Snapshots:" -ForegroundColor Cyan
            Write-Host ("-"*40) -ForegroundColor Cyan
            
            # Get snapshots owned by current account
            $snapshotsOutput = aws ec2 describe-snapshots --owner-ids self --output json
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Error: Failed to retrieve snapshots" -ForegroundColor Red
                return
            }
            
            $snapshotData = $snapshotsOutput | ConvertFrom-Json
            $snapshots = @()
            $index = 1
            
            foreach ($snapshot in $snapshotData.Snapshots) {
                # Get snapshot name from tags if available
                $name = "No Name"
                if ($snapshot.Tags) {
                    $nameTag = $snapshot.Tags | Where-Object { $_.Key -eq "Name" }
                    if ($nameTag) {
                        $name = $nameTag.Value
                    }
                }
                
                # Get source instance from tags if available
                $sourceInstance = "Unknown"
                if ($snapshot.Tags) {
                    $sourceTag = $snapshot.Tags | Where-Object { $_.Key -eq "SourceInstance" }
                    if ($sourceTag) {
                        $sourceInstance = $sourceTag.Value
                    }
                }
                
                $snapshots += [PSCustomObject]@{
                    Index = $index
                    SnapshotId = $snapshot.SnapshotId
                    Name = $name
                    Description = $snapshot.Description
                    StartTime = $snapshot.StartTime
                    State = $snapshot.State
                    VolumeSize = $snapshot.VolumeSize
                    SourceInstance = $sourceInstance
                }
                
                $color = switch ($snapshot.State) {
                    "completed" { "Green" }
                    "pending" { "Yellow" }
                    "error" { "Red" }
                    default { "White" }
                }
                
                Write-Host "$index. " -NoNewline -ForegroundColor White
                Write-Host "$($snapshot.SnapshotId) | " -NoNewline -ForegroundColor Cyan
                Write-Host "$name | " -NoNewline -ForegroundColor White
                Write-Host "$($snapshot.VolumeSize)GB | " -NoNewline -ForegroundColor White
                Write-Host "$($snapshot.StartTime) | " -NoNewline -ForegroundColor Gray
                Write-Host $snapshot.State -ForegroundColor $color
                
                $index++
            }
            
            if ($snapshots.Count -eq 0) {
                Write-Host "No snapshots found in your account" -ForegroundColor Yellow
                return
            }
            
            Write-Host ""
            $selection = Read-Host "Select snapshot to delete (1-$($snapshots.Count)) or 'q' to quit"
            
            if ($selection -eq 'q' -or $selection -eq 'Q') {
                Write-Host "Operation cancelled" -ForegroundColor Yellow
                return
            }
            
            try {
                $selectedIndex = [int]$selection
                if ($selectedIndex -lt 1 -or $selectedIndex -gt $snapshots.Count) {
                    Write-Host "Invalid selection. Please select a number between 1 and $($snapshots.Count)" -ForegroundColor Red
                    return
                }
                
                $selectedSnapshot = $snapshots[$selectedIndex - 1]
                $SnapshotId = $selectedSnapshot.SnapshotId
                Write-Host ""
                Write-Host "Selected snapshot: $SnapshotId ($($selectedSnapshot.Name))" -ForegroundColor Cyan
            } catch {
                Write-Host "Invalid selection. Please enter a valid number" -ForegroundColor Red
                return
            }
        }
        
        # Verify snapshot exists and get details
        Write-Host "Verifying snapshot $SnapshotId..." -ForegroundColor Yellow
        
        $snapshotDetails = aws ec2 describe-snapshots --snapshot-ids $SnapshotId --output json 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Snapshot $SnapshotId not found or access denied" -ForegroundColor Red
            return
        }
        
        $snapshotInfo = ($snapshotDetails | ConvertFrom-Json).Snapshots[0]
        
        Write-Host "Snapshot Details:" -ForegroundColor Yellow
        Write-Host "  ID: $($snapshotInfo.SnapshotId)" -ForegroundColor White
        Write-Host "  Description: $($snapshotInfo.Description)" -ForegroundColor White
        Write-Host "  Size: $($snapshotInfo.VolumeSize)GB" -ForegroundColor White
        Write-Host "  Created: $($snapshotInfo.StartTime)" -ForegroundColor White
        Write-Host "  State: $($snapshotInfo.State)" -ForegroundColor White
        
        # Show warning about evidence deletion
        Write-Host ""
        Write-Host "⚠️  CRITICAL WARNING ⚠️" -ForegroundColor Red
        Write-Host "You are about to DELETE digital evidence!" -ForegroundColor Red
        Write-Host "This action is IRREVERSIBLE and may impact legal proceedings." -ForegroundColor Red
        Write-Host "Ensure you have proper authorization and documentation." -ForegroundColor Red
        Write-Host ""
        
        # Get deletion reason for audit trail
        $reason = Read-Host "Enter reason for snapshot deletion (required)"
        if ([string]::IsNullOrWhiteSpace($reason)) {
            Write-Host "Error: Deletion reason is required for audit purposes" -ForegroundColor Red
            return
        }
        
        # Final confirmation
        $confirm1 = Read-Host "Type 'DELETE' to confirm snapshot deletion"
        if ($confirm1 -ne 'DELETE') {
            Write-Host "Operation cancelled - confirmation text did not match" -ForegroundColor Yellow
            return
        }
        
        $confirm2 = Read-Host "Are you absolutely sure? This cannot be undone! (yes/no)"
        if ($confirm2 -ne 'yes') {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
            return
        }
        
        # Generate deletion audit log before deletion
        $deletionDetails = @{
            "Deleted Snapshot ID" = $SnapshotId
            "Snapshot Description" = $snapshotInfo.Description
            "Snapshot Size" = "$($snapshotInfo.VolumeSize)GB"
            "Snapshot Creation Time" = $snapshotInfo.StartTime
            "Deletion Reason" = $reason
            "Deletion Authorization" = "Confirmed by operator"
        }
        
        $auditFile = New-EvidenceReport -InstanceId "DELETED-SNAPSHOT" -Action "SNAPSHOT_DELETION" -Details $deletionDetails
        
        # Delete the snapshot
        Write-Host "Deleting snapshot $SnapshotId..." -ForegroundColor Yellow
        
        $deleteResult = aws ec2 delete-snapshot --snapshot-id $SnapshotId 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Failed to delete snapshot $SnapshotId" -ForegroundColor Red
            Write-Host "The snapshot may be in use by an AMI or have other dependencies" -ForegroundColor Yellow
            return
        }
        
        Write-Host ""
        Write-Host "✓ Snapshot $SnapshotId has been successfully deleted" -ForegroundColor Green
        Write-Host "✓ Deletion audit log generated: $auditFile" -ForegroundColor Green
        Write-Host ""
        Write-Host "AUDIT TRAIL REMINDER:" -ForegroundColor Red
        Write-Host "- Snapshot deletion has been logged with timestamp and reason" -ForegroundColor Yellow
        Write-Host "- Preserve the audit log for compliance and legal purposes" -ForegroundColor Yellow
        Write-Host "- Verify no dependent resources were affected" -ForegroundColor Yellow
        
    } catch {
        Write-Host "Error during snapshot deletion: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Create EBS snapshot for evidence preservation
function Invoke-Ec2Snapshot {
    param(
        [string]$InstanceId
    )
    
    Write-Host "EBS Snapshot Creation for Evidence Preservation" -ForegroundColor Blue
    Write-Host ("="*50) -ForegroundColor Blue
    Write-Host ""
    
    try {
        # If no instance ID provided, let user select from list
        if ([string]::IsNullOrWhiteSpace($InstanceId)) {
            $InstanceId = Get-InstanceSelection -Purpose "snapshot"
            if ([string]::IsNullOrWhiteSpace($InstanceId)) {
                return
            }
        }
        
        # Get instance information and volumes
        Write-Host "Retrieving instance information..." -ForegroundColor Yellow
        
        $instanceData = aws ec2 describe-instances --instance-ids $InstanceId --output json 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Instance $InstanceId not found" -ForegroundColor Red
            return
        }
        
        $instanceInfo = ($instanceData | ConvertFrom-Json).Reservations[0].Instances[0]
        $volumes = $instanceInfo.BlockDeviceMappings
        
        if ($volumes.Count -eq 0) {
            Write-Host "No EBS volumes found attached to instance $InstanceId" -ForegroundColor Yellow
            return
        }
        
        Write-Host "Found $($volumes.Count) EBS volume(s) attached to instance:" -ForegroundColor Green
        foreach ($vol in $volumes) {
            Write-Host "  - Volume: $($vol.Ebs.VolumeId) (Device: $($vol.DeviceName))" -ForegroundColor White
        }
        
        # Get case information for documentation
        Write-Host ""
        Write-Host "EVIDENCE DOCUMENTATION:" -ForegroundColor Red
        $caseNumber = Read-Host "Enter case/incident number (optional, press Enter to skip)"
        $reason = Read-Host "Enter reason for evidence preservation"
        
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $reason = "Digital forensics evidence collection"
        }
        
        $timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
        $snapshots = @()
        
        Write-Host ""
        Write-Host "Creating snapshots..." -ForegroundColor Yellow
        
        foreach ($vol in $volumes) {
            $volumeId = $vol.Ebs.VolumeId
            $deviceName = $vol.DeviceName
            
            # Create snapshot description
            $description = "EVIDENCE-SNAPSHOT-$InstanceId-$deviceName-$timestamp"
            if (![string]::IsNullOrWhiteSpace($caseNumber)) {
                $description = "CASE-$caseNumber-$description"
            }
            
            Write-Host "  Creating snapshot for volume $volumeId ($deviceName)..." -ForegroundColor Yellow
            
            $snapshotResult = aws ec2 create-snapshot --volume-id $volumeId --description $description --output json
            
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  Error: Failed to create snapshot for volume $volumeId" -ForegroundColor Red
                continue
            }
            
            $snapshotData = $snapshotResult | ConvertFrom-Json
            $snapshotId = $snapshotData.SnapshotId
            
            # Add tags for evidence tracking
            $tags = @(
                "Key=Name,Value=Evidence-$InstanceId-$deviceName"
                "Key=SourceInstance,Value=$InstanceId"
                "Key=SourceVolume,Value=$volumeId"
                "Key=EvidenceType,Value=DigitalForensics"
                "Key=CreatedBy,Value=$env:USERNAME"
                "Key=CreationReason,Value=$reason"
            )
            
            if (![string]::IsNullOrWhiteSpace($caseNumber)) {
                $tags += "Key=CaseNumber,Value=$caseNumber"
            }
            
            aws ec2 create-tags --resources $snapshotId --tags $tags 2>$null
            
            $snapshots += [PSCustomObject]@{
                SnapshotId = $snapshotId
                VolumeId = $volumeId
                DeviceName = $deviceName
                Description = $description
                StartTime = $snapshotData.StartTime
            }
            
            Write-Host "  ✓ Snapshot created: $snapshotId" -ForegroundColor Green
        }
        
        if ($snapshots.Count -eq 0) {
            Write-Host "No snapshots were created successfully" -ForegroundColor Red
            return
        }
        
        # Generate comprehensive evidence report
        $evidenceDetails = @{
            "Case Number" = if ([string]::IsNullOrWhiteSpace($caseNumber)) { "Not specified" } else { $caseNumber }
            "Preservation Reason" = $reason
            "Source Instance Type" = $instanceInfo.InstanceType
            "Source Instance State" = $instanceInfo.State.Name
            "Source Instance AZ" = $instanceInfo.Placement.AvailabilityZone
            "Source Instance Launch Time" = $instanceInfo.LaunchTime
            "Total Volumes Processed" = $volumes.Count.ToString()
            "Snapshots Created" = $snapshots.Count.ToString()
        }
        
        # Add snapshot details
        for ($i = 0; $i -lt $snapshots.Count; $i++) {
            $snap = $snapshots[$i]
            $evidenceDetails["Snapshot $($i+1) ID"] = $snap.SnapshotId
            $evidenceDetails["Snapshot $($i+1) Source Volume"] = $snap.VolumeId
            $evidenceDetails["Snapshot $($i+1) Device"] = $snap.DeviceName
            $evidenceDetails["Snapshot $($i+1) Start Time"] = $snap.StartTime
        }
        
        $reportFile = New-EvidenceReport -InstanceId $InstanceId -Action "EBS_SNAPSHOT_CREATION" -Details $evidenceDetails
        
        Write-Host ""
        Write-Host "✓ Evidence preservation completed successfully!" -ForegroundColor Green
        Write-Host "✓ Created $($snapshots.Count) EBS snapshot(s)" -ForegroundColor Green
        Write-Host "✓ Evidence report generated: $reportFile" -ForegroundColor Green
        Write-Host ""
        Write-Host "SNAPSHOT DETAILS FOR CHAIN OF CUSTODY:" -ForegroundColor Red
        Write-Host ("="*60) -ForegroundColor Red
        
        foreach ($snap in $snapshots) {
            Write-Host "Snapshot ID: " -NoNewline -ForegroundColor Cyan
            Write-Host $snap.SnapshotId -ForegroundColor White
            Write-Host "Source Volume: " -NoNewline -ForegroundColor Cyan
            Write-Host $snap.VolumeId -ForegroundColor White
            Write-Host "Device: " -NoNewline -ForegroundColor Cyan
            Write-Host $snap.DeviceName -ForegroundColor White
            Write-Host "Created: " -NoNewline -ForegroundColor Cyan
            Write-Host $snap.StartTime -ForegroundColor White
            Write-Host ("-"*30) -ForegroundColor Gray
        }
        
        Write-Host ""
        Write-Host "FORENSIC ANALYST INSTRUCTIONS:" -ForegroundColor Red
        Write-Host "- Document all snapshot IDs in case file" -ForegroundColor Yellow
        Write-Host "- Verify snapshot completion status in AWS console" -ForegroundColor Yellow
        Write-Host "- Create EBS volumes from snapshots for analysis" -ForegroundColor Yellow
        Write-Host "- Preserve evidence report for legal proceedings" -ForegroundColor Yellow
        Write-Host "- Calculate hash values of created volumes if required" -ForegroundColor Yellow
        
    } catch {
        Write-Host "Error during snapshot creation: $($_.Exception.Message)" -ForegroundColor Red
    }
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

if ($Command -eq 'help') {
    Show-Usage
    exit 0
}

switch ($Command) {
    'isolate' {
        Invoke-Ec2Isolate -InstanceId $SubCommand
    }
    'snapshot' {
        if ($SubCommand -eq 'delete') {
            # snapshot delete - InstanceId contains the snapshot ID
            Invoke-SnapshotDelete -SnapshotId $InstanceId
        } else {
            # Regular snapshot creation - SubCommand contains the instance ID
            Invoke-Ec2Snapshot -InstanceId $SubCommand
        }
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