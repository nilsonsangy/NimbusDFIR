#!/usr/bin/env python3

"""
EC2 Manager Script - Python
Author: NimbusDFIR
Description: Manage EC2 instances - list, create, start, stop, and terminate instances
"""

import boto3
import sys
import time
from botocore.exceptions import ClientError, NoCredentialsError

# ANSI color codes
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color

def print_color(text, color):
    """Print colored text"""
    print(f"{color}{text}{Colors.NC}")

def check_aws_credentials():
    """Check if AWS credentials are configured"""
    try:
        sts = boto3.client('sts')
        sts.get_caller_identity()
        return True
    except NoCredentialsError:
        print_color("Error: AWS credentials not configured", Colors.RED)
        print("Please configure AWS credentials using 'aws configure' or environment variables")
        return False
    except Exception as e:
        print_color(f"Error: {str(e)}", Colors.RED)
        return False

def show_usage():
    """Display usage information"""
    print_color("==========================================", Colors.BLUE)
    print("EC2 Manager - NimbusDFIR")
    print_color("==========================================", Colors.BLUE)
    print()
    print("Usage: python ec2_manager.py [COMMAND] [OPTIONS]")
    print()
    print("Commands:")
    print("  list              List all EC2 instances")
    print("  create            Create a new EC2 instance")
    print("  remove            Terminate an EC2 instance")
    print("  start             Start a stopped instance")
    print("  stop              Stop a running instance")
    print("  help              Show this help message")
    print()
    print("Examples:")
    print("  python ec2_manager.py list")
    print("  python ec2_manager.py create")
    print("  python ec2_manager.py remove i-1234567890abcdef0")
    print("  python ec2_manager.py start i-1234567890abcdef0")
    print("  python ec2_manager.py stop i-1234567890abcdef0")
    print()

def list_instances(ec2):
    """List all EC2 instances"""
    print_color("Listing EC2 Instances...", Colors.BLUE)
    print()
    
    try:
        response = ec2.describe_instances()
        
        instances = []
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instances.append(instance)
        
        if not instances:
            print_color("No EC2 instances found", Colors.YELLOW)
            return
        
        print_color(f"{'Instance ID':<20} {'Type':<12} {'State':<12} {'Public IP':<15} {'Private IP':<15} {'Name'}", Colors.GREEN)
        print("-" * 100)
        
        for instance in instances:
            instance_id = instance['InstanceId']
            instance_type = instance['InstanceType']
            state = instance['State']['Name']
            public_ip = instance.get('PublicIpAddress', 'N/A')
            private_ip = instance.get('PrivateIpAddress', 'N/A')
            
            name = 'N/A'
            if 'Tags' in instance:
                for tag in instance['Tags']:
                    if tag['Key'] == 'Name':
                        name = tag['Value']
                        break
            
            color = Colors.NC
            if state == 'running':
                color = Colors.GREEN
            elif state == 'stopped':
                color = Colors.YELLOW
            
            print_color(f"{instance_id:<20} {instance_type:<12} {state:<12} {public_ip:<15} {private_ip:<15} {name}", color)
    
    except ClientError as e:
        print_color(f"Error listing instances: {e}", Colors.RED)

def create_instance(ec2):
    """Create a new EC2 instance"""
    print_color("Create New EC2 Instance", Colors.BLUE)
    print()
    
    # Get AMI ID
    ami_id = input("Enter AMI ID (press Enter for Amazon Linux 2023 in current region): ").strip()
    if not ami_id:
        print("Getting latest Amazon Linux 2023 AMI...")
        try:
            response = ec2.describe_images(
                Owners=['amazon'],
                Filters=[
                    {'Name': 'name', 'Values': ['al2023-ami-2023*-x86_64']},
                    {'Name': 'state', 'Values': ['available']}
                ]
            )
            images = sorted(response['Images'], key=lambda x: x['CreationDate'], reverse=True)
            ami_id = images[0]['ImageId']
            print(f"Using AMI: {ami_id}")
        except Exception as e:
            print_color(f"Error getting AMI: {e}", Colors.RED)
            return
    
    # Get instance type
    instance_type = input("Enter instance type (default: t2.micro): ").strip()
    if not instance_type:
        instance_type = "t2.micro"
    
    # Get key pair name
    key_name = input("Enter key pair name (optional): ").strip()
    
    # Get security group
    security_group = input("Enter security group ID (optional): ").strip()
    
    # Get subnet
    subnet_id = input("Enter subnet ID (optional): ").strip()
    
    # Get instance name
    instance_name = input("Enter instance name tag: ").strip()
    
    # Build parameters
    params = {
        'ImageId': ami_id,
        'InstanceType': instance_type,
        'MinCount': 1,
        'MaxCount': 1
    }
    
    if key_name:
        params['KeyName'] = key_name
    
    if security_group:
        params['SecurityGroupIds'] = [security_group]
    
    if subnet_id:
        params['SubnetId'] = subnet_id
    
    if instance_name:
        params['TagSpecifications'] = [
            {
                'ResourceType': 'instance',
                'Tags': [{'Key': 'Name', 'Value': instance_name}]
            }
        ]
    
    print()
    print_color("Creating instance...", Colors.YELLOW)
    
    try:
        response = ec2.run_instances(**params)
        instance_id = response['Instances'][0]['InstanceId']
        
        print_color("✓ Instance created successfully!", Colors.GREEN)
        print(f"Instance ID: {instance_id}")
        print()
        print("Waiting for instance to start...")
        
        waiter = ec2.get_waiter('instance_running')
        waiter.wait(InstanceIds=[instance_id])
        
        print_color("✓ Instance is now running", Colors.GREEN)
        
        # Get instance details
        response = ec2.describe_instances(InstanceIds=[instance_id])
        public_ip = response['Reservations'][0]['Instances'][0].get('PublicIpAddress')
        
        if public_ip:
            print(f"Public IP: {public_ip}")
    
    except ClientError as e:
        print_color(f"✗ Failed to create instance: {e}", Colors.RED)

def remove_instance(ec2, instance_id=None):
    """Remove/terminate an EC2 instance"""
    if not instance_id:
        print_color("Available instances:", Colors.YELLOW)
        list_instances(ec2)
        print()
        instance_id = input("Enter instance ID to terminate: ").strip()
    
    if not instance_id:
        print_color("Error: Instance ID is required", Colors.RED)
        return
    
    # Verify instance exists
    try:
        ec2.describe_instances(InstanceIds=[instance_id])
    except ClientError:
        print_color(f"Error: Instance {instance_id} not found", Colors.RED)
        return
    
    print_color(f"WARNING: This will terminate instance {instance_id}", Colors.YELLOW)
    confirm = input("Are you sure? (yes/no): ").strip().lower()
    
    if confirm != "yes":
        print("Operation cancelled")
        return
    
    print("Terminating instance...")
    try:
        ec2.terminate_instances(InstanceIds=[instance_id])
        print_color(f"✓ Instance {instance_id} is being terminated", Colors.GREEN)
    except ClientError as e:
        print_color(f"Error terminating instance: {e}", Colors.RED)

def start_instance(ec2, instance_id=None):
    """Start a stopped EC2 instance"""
    if not instance_id:
        print_color("Available stopped instances:", Colors.YELLOW)
        try:
            response = ec2.describe_instances(
                Filters=[{'Name': 'instance-state-name', 'Values': ['stopped']}]
            )
            for reservation in response['Reservations']:
                for instance in reservation['Instances']:
                    name = 'N/A'
                    if 'Tags' in instance:
                        for tag in instance['Tags']:
                            if tag['Key'] == 'Name':
                                name = tag['Value']
                                break
                    print(f"{instance['InstanceId']} - {name}")
        except ClientError as e:
            print_color(f"Error: {e}", Colors.RED)
        
        print()
        instance_id = input("Enter instance ID to start: ").strip()
    
    if not instance_id:
        print_color("Error: Instance ID is required", Colors.RED)
        return
    
    print(f"Starting instance {instance_id}...")
    try:
        ec2.start_instances(InstanceIds=[instance_id])
        print_color(f"✓ Instance {instance_id} is starting", Colors.GREEN)
        print("Waiting for instance to be running...")
        
        waiter = ec2.get_waiter('instance_running')
        waiter.wait(InstanceIds=[instance_id])
        
        print_color("✓ Instance is now running", Colors.GREEN)
    except ClientError as e:
        print_color(f"Error starting instance: {e}", Colors.RED)

def stop_instance(ec2, instance_id=None):
    """Stop a running EC2 instance"""
    if not instance_id:
        print_color("Available running instances:", Colors.YELLOW)
        try:
            response = ec2.describe_instances(
                Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]
            )
            for reservation in response['Reservations']:
                for instance in reservation['Instances']:
                    name = 'N/A'
                    if 'Tags' in instance:
                        for tag in instance['Tags']:
                            if tag['Key'] == 'Name':
                                name = tag['Value']
                                break
                    print(f"{instance['InstanceId']} - {name}")
        except ClientError as e:
            print_color(f"Error: {e}", Colors.RED)
        
        print()
        instance_id = input("Enter instance ID to stop: ").strip()
    
    if not instance_id:
        print_color("Error: Instance ID is required", Colors.RED)
        return
    
    print(f"Stopping instance {instance_id}...")
    try:
        ec2.stop_instances(InstanceIds=[instance_id])
        print_color(f"✓ Instance {instance_id} is stopping", Colors.GREEN)
    except ClientError as e:
        print_color(f"Error stopping instance: {e}", Colors.RED)

def main():
    """Main script execution"""
    if not check_aws_credentials():
        sys.exit(1)
    
    if len(sys.argv) < 2:
        show_usage()
        sys.exit(0)
    
    command = sys.argv[1].lower()
    instance_id = sys.argv[2] if len(sys.argv) > 2 else None
    
    ec2 = boto3.client('ec2')
    
    if command == 'list':
        list_instances(ec2)
    elif command == 'create':
        create_instance(ec2)
    elif command in ['remove', 'terminate']:
        remove_instance(ec2, instance_id)
    elif command == 'start':
        start_instance(ec2, instance_id)
    elif command == 'stop':
        stop_instance(ec2, instance_id)
    elif command in ['help', '--help', '-h']:
        show_usage()
    else:
        print_color(f"Error: Unknown command '{command}'", Colors.RED)
        print()
        show_usage()
        sys.exit(1)

if __name__ == "__main__":
    main()
