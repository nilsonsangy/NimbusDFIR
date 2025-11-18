#!/bin/bash

# EC2 Evidence Preservation Script - Shell
# Author: NimbusDFIR
# Description: Digital forensics and incident response tools for EC2 instances
# Functions: isolate instances, create EBS snapshots for evidence preservation

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Print colored text
print_colored() {
    local color=$1
    local text=$2
    echo -e "${color}${text}${NC}"
}

# Print separator
print_separator() {
    local char=${1:-"="}
    local length=${2:-50}
    printf "%*s\n" "$length" | tr ' ' "$char"
}

# Show usage information
show_usage() {
    echo
    print_colored "$GREEN" "EC2 Evidence Preservation Tool"
    print_separator
    echo
    print_colored "$CYAN" "DESCRIPTION:"
    echo "  Digital forensics and incident response tools for AWS EC2 instances"
    echo "  Provides isolation and evidence preservation capabilities"
    echo
    print_colored "$CYAN" "USAGE:"
    echo "  ./ec2_evidence_preservation.sh <command> [args...]"
    echo
    print_colored "$CYAN" "COMMANDS:"
    echo "  isolate          - Isolate EC2 instance for incident response"
    echo "  snapshot         - Create EBS snapshot for evidence preservation"
    echo "  snapshot delete  - Delete EBS snapshot (use with caution)"
    echo "  help             - Show this help message"
    echo
    print_colored "$CYAN" "EXAMPLES:"
    echo "  ./ec2_evidence_preservation.sh isolate i-1234567890abcdef0"
    echo "  ./ec2_evidence_preservation.sh isolate"
    echo "  ./ec2_evidence_preservation.sh snapshot i-1234567890abcdef0"
    echo "  ./ec2_evidence_preservation.sh snapshot"
    echo "  ./ec2_evidence_preservation.sh snapshot delete snap-1234567890abcdef0"
    echo "  ./ec2_evidence_preservation.sh snapshot delete"
    echo
    print_colored "$RED" "INCIDENT RESPONSE WORKFLOW:"
    echo "  1. Use 'isolate' to quarantine compromised instance"
    echo "  2. Use 'snapshot' to preserve evidence"
    echo "  3. Document all actions for chain of custody"
    echo
}

# Test AWS CLI and credentials
test_aws_credentials() {
    if ! command -v aws &> /dev/null; then
        print_colored "$RED" "Error: AWS CLI is not installed"
        print_colored "$YELLOW" "Please install AWS CLI from: https://aws.amazon.com/cli/"
        return 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_colored "$RED" "Error: AWS credentials not configured"
        print_colored "$YELLOW" "Please run 'aws configure' to set up your credentials"
        return 1
    fi
    
    return 0
}

# Get instance selection from user
get_instance_selection() {
    local purpose=${1:-"process"}
    
    echo
    print_colored "$CYAN" "Available EC2 Instances:"
    printf "%s\n" "$(printf '%*s' 40 | tr ' ' '-')"
    
    # Get instances
    local instances_json=$(aws ec2 describe-instances --output json 2>/dev/null)
    if [ $? -ne 0 ]; then
        print_colored "$RED" "Error: Failed to retrieve EC2 instances"
        return 1
    fi
    
    local instances=()
    local index=1
    
    # Parse instances (simplified - real implementation would use jq for better parsing)
    while IFS= read -r line; do
        if echo "$line" | grep -q '"InstanceId"'; then
            local instance_id=$(echo "$line" | sed 's/.*"InstanceId": *"\([^"]*\)".*/\1/')
            local state="unknown"
            local name="No Name"
            
            # Get instance details
            local instance_details=$(aws ec2 describe-instances --instance-ids "$instance_id" --output json 2>/dev/null)
            if [ $? -eq 0 ]; then
                state=$(echo "$instance_details" | grep '"Name": "running"' > /dev/null && echo "running" || echo "stopped")
                name=$(echo "$instance_details" | grep -A1 '"Key": "Name"' | grep '"Value"' | sed 's/.*"Value": *"\([^"]*\)".*/\1/' || echo "No Name")
            fi
            
            if [ "$state" != "terminated" ]; then
                instances+=("$instance_id|$name|$state")
                
                if [ "$state" = "running" ]; then
                    printf "%d. %s%s | %s | %s%s%s\n" "$index" "$CYAN" "$instance_id" "$name" "$GREEN" "$state" "$NC"
                else
                    printf "%d. %s%s | %s | %s%s%s\n" "$index" "$CYAN" "$instance_id" "$name" "$YELLOW" "$state" "$NC"
                fi
                
                ((index++))
            fi
        fi
    done <<< "$(echo "$instances_json" | grep '"InstanceId"')"
    
    if [ ${#instances[@]} -eq 0 ]; then
        print_colored "$YELLOW" "No EC2 instances available for $purpose"
        return 1
    fi
    
    echo
    read -p "Select instance to $purpose (1-${#instances[@]}) or 'q' to quit: " selection
    
    if [ "$selection" = "q" ] || [ "$selection" = "Q" ]; then
        print_colored "$YELLOW" "Operation cancelled"
        return 1
    fi
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#instances[@]} ]; then
        local selected_instance=${instances[$((selection-1))]}
        local instance_id=$(echo "$selected_instance" | cut -d'|' -f1)
        local instance_name=$(echo "$selected_instance" | cut -d'|' -f2)
        
        echo
        print_colored "$CYAN" "Selected instance: $instance_id ($instance_name)"
        echo "$instance_id"
        return 0
    else
        print_colored "$RED" "Invalid selection. Please select a number between 1 and ${#instances[@]}"
        return 1
    fi
}

# Generate evidence report
new_evidence_report() {
    local instance_id=$1
    local action=$2
    local details_file=$3
    
    local timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    local report_filename="evidence-report-${instance_id}-$(date '+%Y%m%d-%H%M%S').txt"
    
    # Get default Downloads folder
    local default_path="$HOME/Downloads"
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        default_path="$USERPROFILE/Downloads"
    fi
    
    echo
    print_colored "$CYAN" "EVIDENCE REPORT LOCATION:"
    print_colored "$YELLOW" "Default location: $default_path"
    read -p "Enter custom path (press Enter for default Downloads folder): " custom_path
    
    local save_path="$default_path"
    if [ -n "$custom_path" ]; then
        if [ -d "$custom_path" ]; then
            save_path="$custom_path"
        else
            print_colored "$YELLOW" "Warning: Path '$custom_path' does not exist. Using default Downloads folder."
        fi
    fi
    
    # Ensure directory exists
    if [ ! -d "$save_path" ]; then
        if mkdir -p "$save_path" 2>/dev/null; then
            print_colored "$GREEN" "Created directory: $save_path"
        else
            print_colored "$RED" "Error creating directory. Using current folder."
            save_path="."
        fi
    fi
    
    local report_file="$save_path/$report_filename"
    
    # Get AWS region
    local region=$(aws configure get region 2>/dev/null || echo "us-east-1")
    
    cat > "$report_file" << EOF
================================================================================
AWS EC2 DIGITAL EVIDENCE PRESERVATION REPORT
================================================================================

CASE INFORMATION:
  Instance ID: $instance_id
  Action Performed: $action
  Timestamp: $timestamp
  Operator: ${USER:-${USERNAME:-Unknown}}
  Computer: ${HOSTNAME:-${COMPUTERNAME:-Unknown}}
  AWS Region: $region

EVIDENCE DETAILS:
EOF
    
    # Add details from temporary file
    if [ -f "$details_file" ]; then
        cat "$details_file" >> "$report_file"
        rm -f "$details_file"
    fi
    
    cat >> "$report_file" << EOF

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
EOF
    
    echo "$report_file"
}

# Isolate EC2 instance for incident response
isolate_instance() {
    local instance_id=$1
    
    print_colored "$RED" "EC2 Instance Isolation for Incident Response"
    print_separator
    echo
    
    # Create quarantine security group if it doesn't exist
    local quarantine_sg_name="ec2-quarantine-sg"
    local quarantine_sg_description="Quarantine Security Group for Incident Response - Blocks all traffic"
    
    print_colored "$YELLOW" "Checking for quarantine security group..."
    
    # Check if quarantine SG exists
    local quarantine_sg_id=$(aws ec2 describe-security-groups --group-names "$quarantine_sg_name" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
    
    if [ $? -ne 0 ] || [ "$quarantine_sg_id" = "None" ]; then
        print_colored "$YELLOW" "Creating quarantine security group..."
        
        # Get default VPC
        local default_vpc=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)
        
        if [ $? -ne 0 ] || [ "$default_vpc" = "None" ]; then
            print_colored "$RED" "Error: Could not find default VPC"
            return 1
        fi
        
        # Create quarantine security group
        quarantine_sg_id=$(aws ec2 create-security-group --group-name "$quarantine_sg_name" --description "$quarantine_sg_description" --vpc-id "$default_vpc" --query 'GroupId' --output text)
        
        if [ $? -ne 0 ]; then
            print_colored "$RED" "Error: Failed to create quarantine security group"
            return 1
        fi
        
        print_colored "$GREEN" "Created quarantine security group: $quarantine_sg_id"
        
        # Remove default egress rule (allow all outbound)
        aws ec2 revoke-security-group-egress --group-id "$quarantine_sg_id" --protocol "-1" --cidr "0.0.0.0/0" 2>/dev/null
        
        print_colored "$GREEN" "Quarantine security group configured (no inbound/outbound traffic allowed)"
    else
        print_colored "$GREEN" "Using existing quarantine security group: $quarantine_sg_id"
    fi
    
    # If no instance ID provided, let user select from list
    if [ -z "$instance_id" ]; then
        instance_id=$(get_instance_selection "isolate")
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi
    
    # Verify instance exists and get current security groups
    print_colored "$YELLOW" "Verifying instance $instance_id..."
    
    local instance_data=$(aws ec2 describe-instances --instance-ids "$instance_id" --output json 2>/dev/null)
    if [ $? -ne 0 ]; then
        print_colored "$RED" "Error: Instance $instance_id not found"
        return 1
    fi
    
    local current_sgs=$(echo "$instance_data" | grep -A1 '"GroupId"' | grep -o '"sg-[^"]*"' | tr -d '"')
    
    print_colored "$YELLOW" "Current security groups:"
    for sg in $current_sgs; do
        local sg_name=$(aws ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0].GroupName' --output text 2>/dev/null)
        echo "  - $sg ($sg_name)"
    done
    
    # Confirm isolation
    echo
    print_colored "$RED" "WARNING: This will isolate the instance by replacing all security groups with quarantine SG"
    print_colored "$RED" "The instance will be completely isolated from network traffic"
    read -p "Are you sure you want to proceed? (y/N): " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        print_colored "$YELLOW" "Operation cancelled"
        return 1
    fi
    
    # Store original security groups for potential restoration
    local temp_path="/tmp"
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        temp_path="$TEMP"
    fi
    
    local original_sgs_file="$temp_path/original-sgs-$instance_id.json"
    echo "[$current_sgs]" | tr ' ' ',' > "$original_sgs_file"
    
    print_colored "$GREEN" "Original security groups saved to: $original_sgs_file"
    
    # Apply quarantine security group
    print_colored "$YELLOW" "Applying quarantine security group..."
    
    aws ec2 modify-instance-attribute --instance-id "$instance_id" --groups "$quarantine_sg_id"
    
    if [ $? -ne 0 ]; then
        print_colored "$RED" "Error: Failed to apply quarantine security group"
        return 1
    fi
    
    # Generate evidence report for isolation
    local details_file=$(mktemp)
    local instance_info=$(echo "$instance_data" | grep -E '"State"|"InstanceType"|"AvailabilityZone"|"LaunchTime"')
    
    cat > "$details_file" << EOF
  Quarantine Security Group: $quarantine_sg_id
  Original Security Groups: $current_sgs
  Instance State: $(echo "$instance_info" | grep '"Name"' | head -1 | cut -d'"' -f4)
  Instance Type: $(echo "$instance_info" | grep '"InstanceType"' | cut -d'"' -f4)
  Availability Zone: $(echo "$instance_info" | grep '"AvailabilityZone"' | cut -d'"' -f4)
  Launch Time: $(echo "$instance_info" | grep '"LaunchTime"' | cut -d'"' -f4)
  Original SG Backup File: $original_sgs_file
EOF
    
    local report_file=$(new_evidence_report "$instance_id" "NETWORK_ISOLATION" "$details_file")
    
    echo
    print_colored "$GREEN" "✓ Instance $instance_id has been successfully isolated!"
    print_colored "$GREEN" "✓ Applied quarantine security group: $quarantine_sg_id"
    print_colored "$GREEN" "✓ All network traffic blocked (inbound and outbound)"
    print_colored "$GREEN" "✓ Original security groups backed up to: $original_sgs_file"
    print_colored "$GREEN" "✓ Evidence report generated: $report_file"
    echo
    print_colored "$RED" "INCIDENT RESPONSE NOTE:"
    print_colored "$YELLOW" "- Instance is now isolated for forensic analysis"
    print_colored "$YELLOW" "- Consider creating EBS snapshots for evidence preservation"
    print_colored "$YELLOW" "- Document the isolation time and reason in case file"
    print_colored "$YELLOW" "- To restore connectivity, restore original security groups from backup file"
    
    # Ask if user wants to create EBS snapshot
    echo
    read -p "Do you want to create an EBS snapshot for evidence preservation? (y/N): " create_snapshot
    
    if [ "$create_snapshot" = "y" ] || [ "$create_snapshot" = "Y" ]; then
        echo
        print_colored "$CYAN" "Creating EBS snapshot..."
        create_snapshot_evidence "$instance_id"
    fi
}

# Create EBS snapshot for evidence preservation
create_snapshot_evidence() {
    local instance_id=$1
    
    print_colored "$BLUE" "EBS Snapshot Creation for Evidence Preservation"
    print_separator
    echo
    
    # If no instance ID provided, let user select from list
    if [ -z "$instance_id" ]; then
        instance_id=$(get_instance_selection "snapshot")
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi
    
    # Get instance information and volumes
    print_colored "$YELLOW" "Retrieving instance information..."
    
    local instance_data=$(aws ec2 describe-instances --instance-ids "$instance_id" --output json 2>/dev/null)
    if [ $? -ne 0 ]; then
        print_colored "$RED" "Error: Instance $instance_id not found"
        return 1
    fi
    
    local volumes=$(echo "$instance_data" | grep -A2 '"BlockDeviceMappings"' | grep -o '"VolumeId": "[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$volumes" ]; then
        print_colored "$YELLOW" "No EBS volumes found attached to instance $instance_id"
        return 1
    fi
    
    local volume_count=$(echo "$volumes" | wc -l)
    print_colored "$GREEN" "Found $volume_count EBS volume(s) attached to instance:"
    for vol in $volumes; do
        local device=$(echo "$instance_data" | grep -B2 -A2 "$vol" | grep '"DeviceName"' | cut -d'"' -f4)
        echo "  - Volume: $vol (Device: $device)"
    done
    
    # Get case information for documentation
    echo
    print_colored "$RED" "EVIDENCE DOCUMENTATION:"
    read -p "Enter case/incident number (optional, press Enter to skip): " case_number
    read -p "Enter reason for evidence preservation: " reason
    
    if [ -z "$reason" ]; then
        reason="Digital forensics evidence collection"
    fi
    
    local timestamp=$(date '+%Y-%m-%d-%H%M%S')
    local snapshots=()
    
    echo
    print_colored "$YELLOW" "Creating snapshots..."
    
    for vol in $volumes; do
        local device=$(echo "$instance_data" | grep -B2 -A2 "$vol" | grep '"DeviceName"' | cut -d'"' -f4)
        
        # Create snapshot description
        local description="EVIDENCE-SNAPSHOT-$instance_id-$device-$timestamp"
        if [ -n "$case_number" ]; then
            description="CASE-$case_number-$description"
        fi
        
        print_colored "$YELLOW" "  Creating snapshot for volume $vol ($device)..."
        
        local snapshot_id=$(aws ec2 create-snapshot --volume-id "$vol" --description "$description" --query 'SnapshotId' --output text)
        
        if [ $? -ne 0 ]; then
            print_colored "$RED" "  Error: Failed to create snapshot for volume $vol"
            continue
        fi
        
        # Add tags for evidence tracking
        aws ec2 create-tags --resources "$snapshot_id" --tags \
            "Key=Name,Value=Evidence-$instance_id-$device" \
            "Key=SourceInstance,Value=$instance_id" \
            "Key=SourceVolume,Value=$vol" \
            "Key=EvidenceType,Value=DigitalForensics" \
            "Key=CreatedBy,Value=${USER:-${USERNAME:-Unknown}}" \
            "Key=CreationReason,Value=$reason"
        
        if [ -n "$case_number" ]; then
            aws ec2 create-tags --resources "$snapshot_id" --tags "Key=CaseNumber,Value=$case_number"
        fi
        
        snapshots+=("$snapshot_id|$vol|$device")
        
        print_colored "$GREEN" "  ✓ Snapshot created: $snapshot_id"
    done
    
    if [ ${#snapshots[@]} -eq 0 ]; then
        print_colored "$RED" "No snapshots were created successfully"
        return 1
    fi
    
    # Generate comprehensive evidence report
    local details_file=$(mktemp)
    local instance_info=$(echo "$instance_data" | grep -E '"InstanceType"|"State"|"AvailabilityZone"|"LaunchTime"')
    
    cat > "$details_file" << EOF
  Case Number: ${case_number:-"Not specified"}
  Preservation Reason: $reason
  Source Instance Type: $(echo "$instance_info" | grep '"InstanceType"' | cut -d'"' -f4)
  Source Instance State: $(echo "$instance_info" | grep '"Name"' | head -1 | cut -d'"' -f4)
  Source Instance AZ: $(echo "$instance_info" | grep '"AvailabilityZone"' | cut -d'"' -f4)
  Source Instance Launch Time: $(echo "$instance_info" | grep '"LaunchTime"' | cut -d'"' -f4)
  Total Volumes Processed: $volume_count
  Snapshots Created: ${#snapshots[@]}
EOF
    
    # Add snapshot details
    local i=1
    for snap_info in "${snapshots[@]}"; do
        local snap_id=$(echo "$snap_info" | cut -d'|' -f1)
        local vol_id=$(echo "$snap_info" | cut -d'|' -f2)
        local device=$(echo "$snap_info" | cut -d'|' -f3)
        local start_time=$(aws ec2 describe-snapshots --snapshot-ids "$snap_id" --query 'Snapshots[0].StartTime' --output text)
        
        cat >> "$details_file" << EOF
  Snapshot $i ID: $snap_id
  Snapshot $i Source Volume: $vol_id
  Snapshot $i Device: $device
  Snapshot $i Start Time: $start_time
EOF
        ((i++))
    done
    
    local report_file=$(new_evidence_report "$instance_id" "EBS_SNAPSHOT_CREATION" "$details_file")
    
    echo
    print_colored "$GREEN" "✓ Evidence preservation completed successfully!"
    print_colored "$GREEN" "✓ Created ${#snapshots[@]} EBS snapshot(s)"
    print_colored "$GREEN" "✓ Evidence report generated: $report_file"
    echo
    print_colored "$RED" "SNAPSHOT DETAILS FOR CHAIN OF CUSTODY:"
    printf "%s\n" "$(printf '%*s' 60 | tr ' ' '=')"
    
    for snap_info in "${snapshots[@]}"; do
        local snap_id=$(echo "$snap_info" | cut -d'|' -f1)
        local vol_id=$(echo "$snap_info" | cut -d'|' -f2)
        local device=$(echo "$snap_info" | cut -d'|' -f3)
        local start_time=$(aws ec2 describe-snapshots --snapshot-ids "$snap_id" --query 'Snapshots[0].StartTime' --output text)
        
        echo -e "${CYAN}Snapshot ID: ${NC}$snap_id"
        echo -e "${CYAN}Source Volume: ${NC}$vol_id"
        echo -e "${CYAN}Device: ${NC}$device"
        echo -e "${CYAN}Created: ${NC}$start_time"
        printf "%s\n" "$(printf '%*s' 30 | tr ' ' '-')"
    done
    
    echo
    print_colored "$RED" "FORENSIC ANALYST INSTRUCTIONS:"
    print_colored "$YELLOW" "- Document all snapshot IDs in case file"
    print_colored "$YELLOW" "- Verify snapshot completion status in AWS console"
    print_colored "$YELLOW" "- Create EBS volumes from snapshots for analysis"
    print_colored "$YELLOW" "- Preserve evidence report for legal proceedings"
    print_colored "$YELLOW" "- Calculate hash values of created volumes if required"
}

# Delete EBS snapshot
delete_snapshot() {
    local snapshot_id=$1
    
    print_colored "$RED" "EBS Snapshot Deletion"
    print_separator
    echo
    
    # If no snapshot ID provided, let user select from list
    if [ -z "$snapshot_id" ]; then
        print_colored "$CYAN" "Available EBS Snapshots:"
        printf "%s\n" "$(printf '%*s' 40 | tr ' ' '-')"
        
        # Get snapshots owned by current account
        local snapshots_json=$(aws ec2 describe-snapshots --owner-ids self --output json 2>/dev/null)
        if [ $? -ne 0 ]; then
            print_colored "$RED" "Error: Failed to retrieve snapshots"
            return 1
        fi
        
        local snapshots=()
        local index=1
        
        # Parse snapshots (simplified)
        while IFS= read -r line; do
            if echo "$line" | grep -q '"SnapshotId"'; then
                local snap_id=$(echo "$line" | sed 's/.*"SnapshotId": *"\([^"]*\)".*/\1/')
                local description=$(aws ec2 describe-snapshots --snapshot-ids "$snap_id" --query 'Snapshots[0].Description' --output text 2>/dev/null)
                local size=$(aws ec2 describe-snapshots --snapshot-ids "$snap_id" --query 'Snapshots[0].VolumeSize' --output text 2>/dev/null)
                local state=$(aws ec2 describe-snapshots --snapshot-ids "$snap_id" --query 'Snapshots[0].State' --output text 2>/dev/null)
                local start_time=$(aws ec2 describe-snapshots --snapshot-ids "$snap_id" --query 'Snapshots[0].StartTime' --output text 2>/dev/null)
                
                snapshots+=("$snap_id|$description|$size|$state|$start_time")
                
                if [ "$state" = "completed" ]; then
                    printf "%d. %s%s | %s | %sGB | %s | %s%s%s\n" "$index" "$CYAN" "$snap_id" "${description:0:30}" "$size" "$start_time" "$GREEN" "$state" "$NC"
                else
                    printf "%d. %s%s | %s | %sGB | %s | %s%s%s\n" "$index" "$CYAN" "$snap_id" "${description:0:30}" "$size" "$start_time" "$YELLOW" "$state" "$NC"
                fi
                
                ((index++))
            fi
        done <<< "$(echo "$snapshots_json" | grep '"SnapshotId"')"
        
        if [ ${#snapshots[@]} -eq 0 ]; then
            print_colored "$YELLOW" "No snapshots found in your account"
            return 1
        fi
        
        echo
        read -p "Select snapshot to delete (1-${#snapshots[@]}) or 'q' to quit: " selection
        
        if [ "$selection" = "q" ] || [ "$selection" = "Q" ]; then
            print_colored "$YELLOW" "Operation cancelled"
            return 1
        fi
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#snapshots[@]} ]; then
            local selected_snapshot=${snapshots[$((selection-1))]}
            snapshot_id=$(echo "$selected_snapshot" | cut -d'|' -f1)
            local snap_desc=$(echo "$selected_snapshot" | cut -d'|' -f2)
            
            echo
            print_colored "$CYAN" "Selected snapshot: $snapshot_id ($snap_desc)"
        else
            print_colored "$RED" "Invalid selection. Please select a number between 1 and ${#snapshots[@]}"
            return 1
        fi
    fi
    
    # Verify snapshot exists and get details
    print_colored "$YELLOW" "Verifying snapshot $snapshot_id..."
    
    local snapshot_data=$(aws ec2 describe-snapshots --snapshot-ids "$snapshot_id" --output json 2>/dev/null)
    if [ $? -ne 0 ]; then
        print_colored "$RED" "Error: Snapshot $snapshot_id not found or access denied"
        return 1
    fi
    
    local description=$(echo "$snapshot_data" | grep '"Description"' | cut -d'"' -f4)
    local size=$(echo "$snapshot_data" | grep '"VolumeSize"' | grep -o '[0-9]*')
    local state=$(echo "$snapshot_data" | grep '"State"' | cut -d'"' -f4)
    local start_time=$(echo "$snapshot_data" | grep '"StartTime"' | cut -d'"' -f4)
    
    print_colored "$YELLOW" "Snapshot Details:"
    echo "  ID: $snapshot_id"
    echo "  Description: $description"
    echo "  Size: ${size}GB"
    echo "  Created: $start_time"
    echo "  State: $state"
    
    # Show warning about evidence deletion
    echo
    print_colored "$RED" "⚠️  CRITICAL WARNING ⚠️"
    print_colored "$RED" "You are about to DELETE digital evidence!"
    print_colored "$RED" "This action is IRREVERSIBLE and may impact legal proceedings."
    print_colored "$RED" "Ensure you have proper authorization and documentation."
    echo
    
    # Get deletion reason for audit trail
    read -p "Enter reason for snapshot deletion (required): " reason
    if [ -z "$reason" ]; then
        print_colored "$RED" "Error: Deletion reason is required for audit purposes"
        return 1
    fi
    
    # Final confirmation
    read -p "Type 'DELETE' to confirm snapshot deletion: " confirm1
    if [ "$confirm1" != "DELETE" ]; then
        print_colored "$YELLOW" "Operation cancelled - confirmation text did not match"
        return 1
    fi
    
    read -p "Are you absolutely sure? This cannot be undone! (yes/no): " confirm2
    if [ "$confirm2" != "yes" ]; then
        print_colored "$YELLOW" "Operation cancelled"
        return 1
    fi
    
    # Generate deletion audit log before deletion
    local details_file=$(mktemp)
    cat > "$details_file" << EOF
  Deleted Snapshot ID: $snapshot_id
  Snapshot Description: $description
  Snapshot Size: ${size}GB
  Snapshot Creation Time: $start_time
  Deletion Reason: $reason
  Deletion Authorization: Confirmed by operator
EOF
    
    local audit_file=$(new_evidence_report "DELETED-SNAPSHOT" "SNAPSHOT_DELETION" "$details_file")
    
    # Delete the snapshot
    print_colored "$YELLOW" "Deleting snapshot $snapshot_id..."
    
    aws ec2 delete-snapshot --snapshot-id "$snapshot_id"
    
    if [ $? -ne 0 ]; then
        print_colored "$RED" "Error: Failed to delete snapshot $snapshot_id"
        print_colored "$YELLOW" "The snapshot may be in use by an AMI or have other dependencies"
        return 1
    fi
    
    echo
    print_colored "$GREEN" "✓ Snapshot $snapshot_id has been successfully deleted"
    print_colored "$GREEN" "✓ Deletion audit log generated: $audit_file"
    echo
    print_colored "$RED" "AUDIT TRAIL REMINDER:"
    print_colored "$YELLOW" "- Snapshot deletion has been logged with timestamp and reason"
    print_colored "$YELLOW" "- Preserve the audit log for compliance and legal purposes"
    print_colored "$YELLOW" "- Verify no dependent resources were affected"
}

# Main function
main() {
    if [ $# -lt 1 ]; then
        show_usage
        exit 0
    fi
    
    if ! test_aws_credentials; then
        exit 1
    fi
    
    case "${1,,}" in
        "help")
            show_usage
            exit 0
            ;;
        "isolate")
            isolate_instance "$2"
            ;;
        "snapshot")
            if [ "${2,,}" = "delete" ]; then
                # snapshot delete
                delete_snapshot "$3"
            else
                # Regular snapshot creation
                create_snapshot_evidence "$2"
            fi
            ;;
        *)
            print_colored "$RED" "Error: Unknown command '$1'"
            echo
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"