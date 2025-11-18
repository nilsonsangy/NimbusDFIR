#!/usr/bin/env python3

"""
EC2 Evidence Preservation Script - Python
Author: NimbusDFIR
Description: Digital forensics and incident response tools for EC2 instances
Functions: isolate instances, create EBS snapshots for evidence preservation
"""

import boto3
import sys
import json
import time
import os
import datetime
from pathlib import Path
from botocore.exceptions import ClientError, NoCredentialsError

# ANSI color codes
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    MAGENTA = '\033[0;35m'
    NC = '\033[0m'  # No Color

def print_colored(text, color):
    """Print text with color"""
    print(f"{color}{text}{Colors.NC}")

def print_separator(char="=", length=50):
    """Print a separator line"""
    print(char * length)

def show_usage():
    """Display usage information"""
    print()
    print_colored("EC2 Evidence Preservation Tool", Colors.GREEN)
    print_separator()
    print()
    print_colored("DESCRIPTION:", Colors.CYAN)
    print("  Digital forensics and incident response tools for AWS EC2 instances")
    print("  Provides isolation and evidence preservation capabilities")
    print()
    print_colored("USAGE:", Colors.CYAN)
    print("  python3 ec2_evidence_preservation.py <command> [args...]")
    print()
    print_colored("COMMANDS:", Colors.CYAN)
    print("  isolate          - Isolate EC2 instance for incident response")
    print("  snapshot         - Create EBS snapshot for evidence preservation")
    print("  snapshot delete  - Delete EBS snapshot (use with caution)")
    print("  help             - Show this help message")
    print()
    print_colored("EXAMPLES:", Colors.CYAN)
    print("  python3 ec2_evidence_preservation.py isolate i-1234567890abcdef0")
    print("  python3 ec2_evidence_preservation.py isolate")
    print("  python3 ec2_evidence_preservation.py snapshot i-1234567890abcdef0")
    print("  python3 ec2_evidence_preservation.py snapshot")
    print("  python3 ec2_evidence_preservation.py snapshot delete snap-1234567890abcdef0")
    print("  python3 ec2_evidence_preservation.py snapshot delete")
    print()
    print_colored("INCIDENT RESPONSE WORKFLOW:", Colors.RED)
    print("  1. Use 'isolate' to quarantine compromised instance")
    print("  2. Use 'snapshot' to preserve evidence")
    print("  3. Document all actions for chain of custody")
    print()

def test_aws_credentials():
    """Test AWS credentials and connection"""
    try:
        sts = boto3.client('sts')
        sts.get_caller_identity()
        return True
    except NoCredentialsError:
        print_colored("Error: AWS credentials not configured", Colors.RED)
        print_colored("Please run 'aws configure' or set AWS environment variables", Colors.YELLOW)
        return False
    except Exception as e:
        print_colored(f"Error: Failed to connect to AWS: {str(e)}", Colors.RED)
        return False

def get_instance_selection(purpose="process"):
    """Get EC2 instance selection from user"""
    try:
        ec2 = boto3.client('ec2')
        
        print()
        print_colored("Available EC2 Instances:", Colors.CYAN)
        print("-" * 40)
        
        # Get instances
        response = ec2.describe_instances()
        instances = []
        index = 1
        
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                if instance['State']['Name'] != 'terminated':
                    name = "No Name"
                    if 'Tags' in instance:
                        for tag in instance['Tags']:
                            if tag['Key'] == 'Name':
                                name = tag['Value']
                                break
                    
                    instances.append({
                        'index': index,
                        'instance_id': instance['InstanceId'],
                        'name': name,
                        'state': instance['State']['Name'],
                        'type': instance['InstanceType']
                    })
                    
                    color = Colors.GREEN if instance['State']['Name'] == 'running' else Colors.YELLOW
                    print(f"{index}. {Colors.CYAN}{instance['InstanceId']} | {name} | {color}{instance['State']['Name']}{Colors.NC}")
                    
                    index += 1
        
        if not instances:
            print_colored(f"No EC2 instances available for {purpose}", Colors.YELLOW)
            return None
        
        print()
        selection = input(f"Select instance to {purpose} (1-{len(instances)}) or 'q' to quit: ")
        
        if selection.lower() == 'q':
            print_colored("Operation cancelled", Colors.YELLOW)
            return None
        
        try:
            selected_index = int(selection)
            if 1 <= selected_index <= len(instances):
                selected_instance = instances[selected_index - 1]
                print()
                print_colored(f"Selected instance: {selected_instance['instance_id']} ({selected_instance['name']})", Colors.CYAN)
                return selected_instance['instance_id']
            else:
                print_colored(f"Invalid selection. Please select a number between 1 and {len(instances)}", Colors.RED)
                return None
        except ValueError:
            print_colored("Invalid selection. Please enter a valid number", Colors.RED)
            return None
            
    except Exception as e:
        print_colored(f"Error retrieving instances: {str(e)}", Colors.RED)
        return None

def new_evidence_report(instance_id, action, details):
    """Generate evidence documentation"""
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    report_filename = f"evidence-report-{instance_id}-{datetime.datetime.now().strftime('%Y%m%d-%H%M%S')}.txt"
    
    # Get default Downloads folder
    default_path = os.path.join(os.path.expanduser("~"), "Downloads")
    
    print()
    print_colored("EVIDENCE REPORT LOCATION:", Colors.CYAN)
    print_colored(f"Default location: {default_path}", Colors.YELLOW)
    custom_path = input("Enter custom path (press Enter for default Downloads folder): ")
    
    if not custom_path.strip():
        save_path = default_path
    else:
        if os.path.exists(custom_path):
            save_path = custom_path
        else:
            print_colored(f"Warning: Path '{custom_path}' does not exist. Using default Downloads folder.", Colors.YELLOW)
            save_path = default_path
    
    # Ensure directory exists
    if not os.path.exists(save_path):
        try:
            os.makedirs(save_path)
            print_colored(f"Created directory: {save_path}", Colors.GREEN)
        except Exception:
            print_colored("Error creating directory. Using current folder.", Colors.RED)
            save_path = "."
    
    report_file = os.path.join(save_path, report_filename)
    
    # Get AWS region
    try:
        session = boto3.Session()
        region = session.region_name or 'us-east-1'
    except:
        region = 'us-east-1'
    
    report_content = f"""================================================================================
AWS EC2 DIGITAL EVIDENCE PRESERVATION REPORT
================================================================================

CASE INFORMATION:
  Instance ID: {instance_id}
  Action Performed: {action}
  Timestamp: {timestamp}
  Operator: {os.getenv('USER', os.getenv('USERNAME', 'Unknown'))}
  Computer: {os.getenv('HOSTNAME', os.getenv('COMPUTERNAME', 'Unknown'))}
  AWS Region: {region}

EVIDENCE DETAILS:
"""
    
    for key, value in details.items():
        report_content += f"  {key}: {value}\n"
    
    report_content += """
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
"""
    
    with open(report_file, 'w', encoding='utf-8') as f:
        f.write(report_content)
    
    return report_file

def isolate_instance(instance_id=None):
    """Isolate EC2 instance for incident response"""
    print_colored("EC2 Instance Isolation for Incident Response", Colors.RED)
    print_separator()
    print()
    
    try:
        ec2 = boto3.client('ec2')
        
        # Create quarantine security group if it doesn't exist
        quarantine_sg_name = "ec2-quarantine-sg"
        quarantine_sg_description = "Quarantine Security Group for Incident Response - Blocks all traffic"
        
        print_colored("Checking for quarantine security group...", Colors.YELLOW)
        
        # Check if quarantine SG exists
        quarantine_sg_id = None
        try:
            response = ec2.describe_security_groups(GroupNames=[quarantine_sg_name])
            quarantine_sg_id = response['SecurityGroups'][0]['GroupId']
            print_colored(f"Using existing quarantine security group: {quarantine_sg_id}", Colors.GREEN)
        except ClientError as e:
            if e.response['Error']['Code'] == 'InvalidGroup.NotFound':
                print_colored("Creating quarantine security group...", Colors.YELLOW)
                
                # Get default VPC
                vpc_response = ec2.describe_vpcs(Filters=[{'Name': 'isDefault', 'Values': ['true']}])
                if not vpc_response['Vpcs']:
                    print_colored("Error: Could not find default VPC", Colors.RED)
                    return
                
                default_vpc = vpc_response['Vpcs'][0]['VpcId']
                
                # Create quarantine security group
                sg_response = ec2.create_security_group(
                    GroupName=quarantine_sg_name,
                    Description=quarantine_sg_description,
                    VpcId=default_vpc
                )
                
                quarantine_sg_id = sg_response['GroupId']
                print_colored(f"Created quarantine security group: {quarantine_sg_id}", Colors.GREEN)
                
                # Remove default egress rule (allow all outbound)
                try:
                    ec2.revoke_security_group_egress(
                        GroupId=quarantine_sg_id,
                        IpProtocol='-1',
                        CidrIp='0.0.0.0/0'
                    )
                except ClientError:
                    pass  # Rule might not exist
                
                print_colored("Quarantine security group configured (no inbound/outbound traffic allowed)", Colors.GREEN)
            else:
                raise e
        
        # If no instance ID provided, let user select from list
        if not instance_id:
            instance_id = get_instance_selection("isolate")
            if not instance_id:
                return
        
        # Verify instance exists and get current security groups
        print_colored(f"Verifying instance {instance_id}...", Colors.YELLOW)
        
        try:
            instance_response = ec2.describe_instances(InstanceIds=[instance_id])
            instance_info = instance_response['Reservations'][0]['Instances'][0]
            current_sgs = instance_info['SecurityGroups']
        except ClientError:
            print_colored(f"Error: Instance {instance_id} not found", Colors.RED)
            return
        
        print_colored("Current security groups:", Colors.YELLOW)
        for sg in current_sgs:
            print(f"  - {sg['GroupId']} ({sg['GroupName']})")
        
        # Confirm isolation
        print()
        print_colored("WARNING: This will isolate the instance by replacing all security groups with quarantine SG", Colors.RED)
        print_colored("The instance will be completely isolated from network traffic", Colors.RED)
        confirm = input("Are you sure you want to proceed? (y/N): ")
        
        if confirm.lower() != 'y':
            print_colored("Operation cancelled", Colors.YELLOW)
            return
        
        # Store original security groups for potential restoration
        temp_path = os.path.join(os.path.expanduser("~"), ".tmp") if os.name != 'nt' else os.environ.get('TEMP', '/tmp')
        if not os.path.exists(temp_path):
            temp_path = "/tmp"
        
        original_sgs_file = os.path.join(temp_path, f"original-sgs-{instance_id}.json")
        original_sgs = [sg['GroupId'] for sg in current_sgs]
        
        with open(original_sgs_file, 'w') as f:
            json.dump(original_sgs, f)
        
        print_colored(f"Original security groups saved to: {original_sgs_file}", Colors.GREEN)
        
        # Apply quarantine security group
        print_colored("Applying quarantine security group...", Colors.YELLOW)
        
        ec2.modify_instance_attribute(
            InstanceId=instance_id,
            Groups=[quarantine_sg_id]
        )
        
        # Generate evidence report for isolation
        evidence_details = {
            "Quarantine Security Group": quarantine_sg_id,
            "Original Security Groups": ", ".join(original_sgs),
            "Instance State": instance_info['State']['Name'],
            "Instance Type": instance_info['InstanceType'],
            "Availability Zone": instance_info['Placement']['AvailabilityZone'],
            "Launch Time": str(instance_info['LaunchTime']),
            "Original SG Backup File": original_sgs_file
        }
        
        report_file = new_evidence_report(instance_id, "NETWORK_ISOLATION", evidence_details)
        
        print()
        print_colored(f"✓ Instance {instance_id} has been successfully isolated!", Colors.GREEN)
        print_colored(f"✓ Applied quarantine security group: {quarantine_sg_id}", Colors.GREEN)
        print_colored("✓ All network traffic blocked (inbound and outbound)", Colors.GREEN)
        print_colored(f"✓ Original security groups backed up to: {original_sgs_file}", Colors.GREEN)
        print_colored(f"✓ Evidence report generated: {report_file}", Colors.GREEN)
        print()
        print_colored("INCIDENT RESPONSE NOTE:", Colors.RED)
        print_colored("- Instance is now isolated for forensic analysis", Colors.YELLOW)
        print_colored("- Consider creating EBS snapshots for evidence preservation", Colors.YELLOW)
        print_colored("- Document the isolation time and reason in case file", Colors.YELLOW)
        print_colored("- To restore connectivity, restore original security groups from backup file", Colors.YELLOW)
        
        # Ask if user wants to create EBS snapshot
        print()
        create_snapshot = input("Do you want to create an EBS snapshot for evidence preservation? (y/N): ")
        
        if create_snapshot.lower() == 'y':
            print()
            print_colored("Creating EBS snapshot...", Colors.CYAN)
            create_snapshot_evidence(instance_id)
            
    except Exception as e:
        print_colored(f"Error during isolation process: {str(e)}", Colors.RED)

def create_snapshot_evidence(instance_id=None):
    """Create EBS snapshot for evidence preservation"""
    print_colored("EBS Snapshot Creation for Evidence Preservation", Colors.BLUE)
    print_separator()
    print()
    
    try:
        ec2 = boto3.client('ec2')
        
        # If no instance ID provided, let user select from list
        if not instance_id:
            instance_id = get_instance_selection("snapshot")
            if not instance_id:
                return
        
        # Get instance information and volumes
        print_colored("Retrieving instance information...", Colors.YELLOW)
        
        try:
            instance_response = ec2.describe_instances(InstanceIds=[instance_id])
            instance_info = instance_response['Reservations'][0]['Instances'][0]
            volumes = instance_info['BlockDeviceMappings']
        except ClientError:
            print_colored(f"Error: Instance {instance_id} not found", Colors.RED)
            return
        
        if not volumes:
            print_colored(f"No EBS volumes found attached to instance {instance_id}", Colors.YELLOW)
            return
        
        print_colored(f"Found {len(volumes)} EBS volume(s) attached to instance:", Colors.GREEN)
        for vol in volumes:
            print(f"  - Volume: {vol['Ebs']['VolumeId']} (Device: {vol['DeviceName']})")
        
        # Get case information for documentation
        print()
        print_colored("EVIDENCE DOCUMENTATION:", Colors.RED)
        case_number = input("Enter case/incident number (optional, press Enter to skip): ")
        reason = input("Enter reason for evidence preservation: ")
        
        if not reason.strip():
            reason = "Digital forensics evidence collection"
        
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d-%H%M%S")
        snapshots = []
        
        print()
        print_colored("Creating snapshots...", Colors.YELLOW)
        
        for vol in volumes:
            volume_id = vol['Ebs']['VolumeId']
            device_name = vol['DeviceName']
            
            # Create snapshot description
            description = f"EVIDENCE-SNAPSHOT-{instance_id}-{device_name}-{timestamp}"
            if case_number.strip():
                description = f"CASE-{case_number}-{description}"
            
            print_colored(f"  Creating snapshot for volume {volume_id} ({device_name})...", Colors.YELLOW)
            
            snapshot_response = ec2.create_snapshot(
                VolumeId=volume_id,
                Description=description
            )
            
            snapshot_id = snapshot_response['SnapshotId']
            
            # Add tags for evidence tracking
            tags = [
                {'Key': 'Name', 'Value': f'Evidence-{instance_id}-{device_name}'},
                {'Key': 'SourceInstance', 'Value': instance_id},
                {'Key': 'SourceVolume', 'Value': volume_id},
                {'Key': 'EvidenceType', 'Value': 'DigitalForensics'},
                {'Key': 'CreatedBy', 'Value': os.getenv('USER', os.getenv('USERNAME', 'Unknown'))},
                {'Key': 'CreationReason', 'Value': reason}
            ]
            
            if case_number.strip():
                tags.append({'Key': 'CaseNumber', 'Value': case_number})
            
            ec2.create_tags(Resources=[snapshot_id], Tags=tags)
            
            snapshots.append({
                'snapshot_id': snapshot_id,
                'volume_id': volume_id,
                'device_name': device_name,
                'description': description,
                'start_time': snapshot_response['StartTime']
            })
            
            print_colored(f"  ✓ Snapshot created: {snapshot_id}", Colors.GREEN)
        
        if not snapshots:
            print_colored("No snapshots were created successfully", Colors.RED)
            return
        
        # Generate comprehensive evidence report
        evidence_details = {
            "Case Number": case_number if case_number.strip() else "Not specified",
            "Preservation Reason": reason,
            "Source Instance Type": instance_info['InstanceType'],
            "Source Instance State": instance_info['State']['Name'],
            "Source Instance AZ": instance_info['Placement']['AvailabilityZone'],
            "Source Instance Launch Time": str(instance_info['LaunchTime']),
            "Total Volumes Processed": str(len(volumes)),
            "Snapshots Created": str(len(snapshots))
        }
        
        # Add snapshot details
        for i, snap in enumerate(snapshots, 1):
            evidence_details[f"Snapshot {i} ID"] = snap['snapshot_id']
            evidence_details[f"Snapshot {i} Source Volume"] = snap['volume_id']
            evidence_details[f"Snapshot {i} Device"] = snap['device_name']
            evidence_details[f"Snapshot {i} Start Time"] = str(snap['start_time'])
        
        report_file = new_evidence_report(instance_id, "EBS_SNAPSHOT_CREATION", evidence_details)
        
        print()
        print_colored("✓ Evidence preservation completed successfully!", Colors.GREEN)
        print_colored(f"✓ Created {len(snapshots)} EBS snapshot(s)", Colors.GREEN)
        print_colored(f"✓ Evidence report generated: {report_file}", Colors.GREEN)
        print()
        print_colored("SNAPSHOT DETAILS FOR CHAIN OF CUSTODY:", Colors.RED)
        print("=" * 60)
        
        for snap in snapshots:
            print_colored(f"Snapshot ID: {snap['snapshot_id']}", Colors.WHITE)
            print_colored(f"Source Volume: {snap['volume_id']}", Colors.WHITE)
            print_colored(f"Device: {snap['device_name']}", Colors.WHITE)
            print_colored(f"Created: {snap['start_time']}", Colors.WHITE)
            print("-" * 30)
        
        print()
        print_colored("FORENSIC ANALYST INSTRUCTIONS:", Colors.RED)
        print_colored("- Document all snapshot IDs in case file", Colors.YELLOW)
        print_colored("- Verify snapshot completion status in AWS console", Colors.YELLOW)
        print_colored("- Create EBS volumes from snapshots for analysis", Colors.YELLOW)
        print_colored("- Preserve evidence report for legal proceedings", Colors.YELLOW)
        print_colored("- Calculate hash values of created volumes if required", Colors.YELLOW)
        
    except Exception as e:
        print_colored(f"Error during snapshot creation: {str(e)}", Colors.RED)

def delete_snapshot(snapshot_id=None):
    """Delete EBS snapshot"""
    print_colored("EBS Snapshot Deletion", Colors.RED)
    print_separator()
    print()
    
    try:
        ec2 = boto3.client('ec2')
        
        # If no snapshot ID provided, let user select from list
        if not snapshot_id:
            print_colored("Available EBS Snapshots:", Colors.CYAN)
            print("-" * 40)
            
            # Get snapshots owned by current account
            try:
                response = ec2.describe_snapshots(OwnerIds=['self'])
                snapshots = []
                index = 1
                
                for snapshot in response['Snapshots']:
                    # Get snapshot name from tags if available
                    name = "No Name"
                    source_instance = "Unknown"
                    
                    if 'Tags' in snapshot:
                        for tag in snapshot['Tags']:
                            if tag['Key'] == 'Name':
                                name = tag['Value']
                            elif tag['Key'] == 'SourceInstance':
                                source_instance = tag['Value']
                    
                    snapshots.append({
                        'index': index,
                        'snapshot_id': snapshot['SnapshotId'],
                        'name': name,
                        'description': snapshot['Description'],
                        'start_time': snapshot['StartTime'],
                        'state': snapshot['State'],
                        'volume_size': snapshot['VolumeSize'],
                        'source_instance': source_instance
                    })
                    
                    color = Colors.GREEN if snapshot['State'] == 'completed' else Colors.YELLOW
                    if snapshot['State'] == 'error':
                        color = Colors.RED
                    
                    print(f"{index}. {Colors.CYAN}{snapshot['SnapshotId']} | {name} | {snapshot['VolumeSize']}GB | {snapshot['StartTime']} | {color}{snapshot['State']}{Colors.NC}")
                    
                    index += 1
                
                if not snapshots:
                    print_colored("No snapshots found in your account", Colors.YELLOW)
                    return
                
                print()
                selection = input(f"Select snapshot to delete (1-{len(snapshots)}) or 'q' to quit: ")
                
                if selection.lower() == 'q':
                    print_colored("Operation cancelled", Colors.YELLOW)
                    return
                
                try:
                    selected_index = int(selection)
                    if 1 <= selected_index <= len(snapshots):
                        selected_snapshot = snapshots[selected_index - 1]
                        snapshot_id = selected_snapshot['snapshot_id']
                        print()
                        print_colored(f"Selected snapshot: {snapshot_id} ({selected_snapshot['name']})", Colors.CYAN)
                    else:
                        print_colored(f"Invalid selection. Please select a number between 1 and {len(snapshots)}", Colors.RED)
                        return
                except ValueError:
                    print_colored("Invalid selection. Please enter a valid number", Colors.RED)
                    return
            except Exception as e:
                print_colored(f"Error retrieving snapshots: {str(e)}", Colors.RED)
                return
        
        # Verify snapshot exists and get details
        print_colored(f"Verifying snapshot {snapshot_id}...", Colors.YELLOW)
        
        try:
            snapshot_response = ec2.describe_snapshots(SnapshotIds=[snapshot_id])
            snapshot_info = snapshot_response['Snapshots'][0]
        except ClientError:
            print_colored(f"Error: Snapshot {snapshot_id} not found or access denied", Colors.RED)
            return
        
        print_colored("Snapshot Details:", Colors.YELLOW)
        print(f"  ID: {snapshot_info['SnapshotId']}")
        print(f"  Description: {snapshot_info['Description']}")
        print(f"  Size: {snapshot_info['VolumeSize']}GB")
        print(f"  Created: {snapshot_info['StartTime']}")
        print(f"  State: {snapshot_info['State']}")
        
        # Show warning about evidence deletion
        print()
        print_colored("⚠️  CRITICAL WARNING ⚠️", Colors.RED)
        print_colored("You are about to DELETE digital evidence!", Colors.RED)
        print_colored("This action is IRREVERSIBLE and may impact legal proceedings.", Colors.RED)
        print_colored("Ensure you have proper authorization and documentation.", Colors.RED)
        print()
        
        # Get deletion reason for audit trail
        reason = input("Enter reason for snapshot deletion (required): ")
        if not reason.strip():
            print_colored("Error: Deletion reason is required for audit purposes", Colors.RED)
            return
        
        # Final confirmation
        confirm1 = input("Type 'DELETE' to confirm snapshot deletion: ")
        if confirm1 != 'DELETE':
            print_colored("Operation cancelled - confirmation text did not match", Colors.YELLOW)
            return
        
        confirm2 = input("Are you absolutely sure? This cannot be undone! (yes/no): ")
        if confirm2.lower() != 'yes':
            print_colored("Operation cancelled", Colors.YELLOW)
            return
        
        # Generate deletion audit log before deletion
        deletion_details = {
            "Deleted Snapshot ID": snapshot_id,
            "Snapshot Description": snapshot_info['Description'],
            "Snapshot Size": f"{snapshot_info['VolumeSize']}GB",
            "Snapshot Creation Time": str(snapshot_info['StartTime']),
            "Deletion Reason": reason,
            "Deletion Authorization": "Confirmed by operator"
        }
        
        audit_file = new_evidence_report("DELETED-SNAPSHOT", "SNAPSHOT_DELETION", deletion_details)
        
        # Delete the snapshot
        print_colored(f"Deleting snapshot {snapshot_id}...", Colors.YELLOW)
        
        ec2.delete_snapshot(SnapshotId=snapshot_id)
        
        print()
        print_colored(f"✓ Snapshot {snapshot_id} has been successfully deleted", Colors.GREEN)
        print_colored(f"✓ Deletion audit log generated: {audit_file}", Colors.GREEN)
        print()
        print_colored("AUDIT TRAIL REMINDER:", Colors.RED)
        print_colored("- Snapshot deletion has been logged with timestamp and reason", Colors.YELLOW)
        print_colored("- Preserve the audit log for compliance and legal purposes", Colors.YELLOW)
        print_colored("- Verify no dependent resources were affected", Colors.YELLOW)
        
    except Exception as e:
        print_colored(f"Error during snapshot deletion: {str(e)}", Colors.RED)

def main():
    """Main function"""
    if len(sys.argv) < 2:
        show_usage()
        sys.exit(0)
    
    if not test_aws_credentials():
        sys.exit(1)
    
    command = sys.argv[1].lower()
    
    if command == 'help':
        show_usage()
        sys.exit(0)
    
    if command == 'isolate':
        instance_id = sys.argv[2] if len(sys.argv) > 2 else None
        isolate_instance(instance_id)
    elif command == 'snapshot':
        if len(sys.argv) > 2 and sys.argv[2].lower() == 'delete':
            # snapshot delete
            snapshot_id = sys.argv[3] if len(sys.argv) > 3 else None
            delete_snapshot(snapshot_id)
        else:
            # Regular snapshot creation
            instance_id = sys.argv[2] if len(sys.argv) > 2 else None
            create_snapshot_evidence(instance_id)
    else:
        print_colored(f"Error: Unknown command '{command}'", Colors.RED)
        print()
        show_usage()
        sys.exit(1)

if __name__ == "__main__":
    main()