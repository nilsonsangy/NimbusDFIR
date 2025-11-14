#!/usr/bin/env python3

"""
S3 Manager Script - Python
Author: NimbusDFIR
Description: Manage S3 buckets - list, create, delete, upload, download, and dump buckets
"""

import boto3
import sys
import os
import zipfile
import tempfile
import shutil
from datetime import datetime
from pathlib import Path
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
    print("S3 Manager - NimbusDFIR")
    print_color("==========================================", Colors.BLUE)
    print()
    print("Usage: python s3_manager.py [COMMAND] [OPTIONS]")
    print()
    print("Commands:")
    print("  list              List all S3 buckets")
    print("  create            Create a new S3 bucket")
    print("  delete            Delete an S3 bucket")
    print("  upload            Upload file(s) to a bucket")
    print("  download          Download a file from a bucket")
    print("  dump              Download all files from a bucket as a zip")
    print("  info              Get bucket information")
    print("  help              Show this help message")
    print()
    print("Examples:")
    print("  python s3_manager.py list")
    print("  python s3_manager.py create")
    print("  python s3_manager.py upload file.txt my-bucket")
    print("  python s3_manager.py download my-bucket file.txt")
    print("  python s3_manager.py dump my-bucket")
    print()

def list_buckets(s3):
    """List all S3 buckets"""
    print_color("Listing S3 Buckets...", Colors.BLUE)
    print()
    
    try:
        response = s3.list_buckets()
        buckets = response.get('Buckets', [])
        
        if not buckets:
            print_color("No S3 buckets found", Colors.YELLOW)
            return
        
        print_color(f"{'Bucket Name':<40} {'Creation Date'}", Colors.GREEN)
        print("-" * 80)
        
        for bucket in buckets:
            name = bucket['Name']
            date = bucket['CreationDate'].strftime('%Y-%m-%d %H:%M:%S')
            print_color(f"{name:<40} {date}", Colors.GREEN)
        
        print()
        print_color(f"Total buckets: {len(buckets)}", Colors.GREEN)
    
    except ClientError as e:
        print_color(f"Error listing buckets: {e}", Colors.RED)

def create_bucket(s3):
    """Create a new S3 bucket"""
    print_color("Create New S3 Bucket", Colors.BLUE)
    print()
    
    bucket_name = input("Enter bucket name (must be globally unique, lowercase, no spaces): ").strip()
    
    if not bucket_name:
        print_color("Error: Bucket name is required", Colors.RED)
        return
    
    # Validate bucket name
    if not bucket_name.replace('-', '').replace('.', '').isalnum() or not bucket_name[0].isalnum() or not bucket_name[-1].isalnum():
        print_color("Error: Invalid bucket name", Colors.RED)
        print("Bucket names must:")
        print("  - Be 3-63 characters long")
        print("  - Start and end with lowercase letter or number")
        print("  - Contain only lowercase letters, numbers, hyphens, and periods")
        return
    
    # Get region
    session = boto3.session.Session()
    current_region = session.region_name or 'us-east-1'
    region = input(f"Enter region (default: {current_region}): ").strip()
    if not region:
        region = current_region
    
    print()
    print_color(f"Creating bucket '{bucket_name}' in region '{region}'...", Colors.YELLOW)
    
    try:
        s3_client = boto3.client('s3', region_name=region)
        
        if region == 'us-east-1':
            s3_client.create_bucket(Bucket=bucket_name)
        else:
            s3_client.create_bucket(
                Bucket=bucket_name,
                CreateBucketConfiguration={'LocationConstraint': region}
            )
        
        print_color(f"✓ Bucket '{bucket_name}' created successfully!", Colors.GREEN)
        
        # Enable versioning
        enable_versioning = input("Enable versioning? (y/N): ").strip().lower()
        if enable_versioning == 'y':
            s3_client.put_bucket_versioning(
                Bucket=bucket_name,
                VersioningConfiguration={'Status': 'Enabled'}
            )
            print_color("✓ Versioning enabled", Colors.GREEN)
        
        # Block public access
        block_public = input("Block all public access? (recommended) (Y/n): ").strip().lower()
        if block_public != 'n':
            s3_client.put_public_access_block(
                Bucket=bucket_name,
                PublicAccessBlockConfiguration={
                    'BlockPublicAcls': True,
                    'IgnorePublicAcls': True,
                    'BlockPublicPolicy': True,
                    'RestrictPublicBuckets': True
                }
            )
            print_color("✓ Public access blocked", Colors.GREEN)
    
    except ClientError as e:
        print_color(f"✗ Failed to create bucket: {e}", Colors.RED)

def select_bucket(s3):
    """Helper function to select a bucket interactively"""
    try:
        response = s3.list_buckets()
        buckets = response.get('Buckets', [])
        
        if not buckets:
            print_color("No buckets found", Colors.RED)
            return None
        
        print_color("Available buckets:", Colors.BLUE)
        print()
        for i, bucket in enumerate(buckets, 1):
            print(f"{i}. {bucket['Name']}")
        
        print()
        selection = input("Select bucket number (or enter bucket name): ").strip()
        
        if selection.isdigit():
            index = int(selection) - 1
            if 0 <= index < len(buckets):
                return buckets[index]['Name']
        else:
            return selection
        
        print_color("Invalid selection", Colors.RED)
        return None
    
    except ClientError as e:
        print_color(f"Error: {e}", Colors.RED)
        return None

def delete_bucket(s3, bucket_name=None):
    """Delete an S3 bucket"""
    if not bucket_name:
        print_color("Available buckets:", Colors.YELLOW)
        list_buckets(s3)
        print()
        bucket_name = input("Enter bucket name to delete: ").strip()
    
    if not bucket_name:
        print_color("Error: Bucket name is required", Colors.RED)
        return
    
    print_color(f"WARNING: This will permanently delete bucket '{bucket_name}'", Colors.YELLOW)
    confirm = input("Are you sure? (yes/no): ").strip().lower()
    
    if confirm != "yes":
        print("Operation cancelled")
        return
    
    try:
        # Empty bucket first
        print("Emptying bucket...")
        bucket = boto3.resource('s3').Bucket(bucket_name)
        bucket.objects.all().delete()
        bucket.object_versions.delete()
        
        # Delete bucket
        print("Deleting bucket...")
        s3.delete_bucket(Bucket=bucket_name)
        print_color(f"✓ Bucket '{bucket_name}' deleted successfully", Colors.GREEN)
    
    except ClientError as e:
        print_color(f"✗ Failed to delete bucket: {e}", Colors.RED)

def upload_files(s3, files, bucket_name=None):
    """Upload files to a bucket"""
    if not files:
        print_color("Error: No files specified", Colors.RED)
        print("Usage: python s3_manager.py upload <files...> [bucket-name]")
        return
    
    # Check if bucket name is in the arguments
    if not bucket_name:
        # Check if last argument is a bucket
        try:
            s3.head_bucket(Bucket=files[-1])
            bucket_name = files[-1]
            files = files[:-1]
        except:
            bucket_name = select_bucket(s3)
    
    if not bucket_name:
        return
    
    print_color(f"Uploading files to bucket: {bucket_name}", Colors.BLUE)
    print()
    
    success_count = 0
    fail_count = 0
    
    for file_path in files:
        if os.path.isfile(file_path):
            filename = os.path.basename(file_path)
            print(f"Uploading {filename}... ", end='')
            
            try:
                s3.upload_file(file_path, bucket_name, filename)
                print_color("✓", Colors.GREEN)
                success_count += 1
            except ClientError as e:
                print_color("✗", Colors.RED)
                fail_count += 1
    
    print()
    print("----------------------------------------")
    print_color(f"Successfully uploaded: {success_count}", Colors.GREEN)
    if fail_count > 0:
        print_color(f"Failed: {fail_count}", Colors.RED)

def download_file(s3, bucket_name=None, file_name=None, download_path=None):
    """Download a file from a bucket"""
    if not bucket_name:
        bucket_name = select_bucket(s3)
    
    if not bucket_name:
        return
    
    # List files if not provided
    if not file_name:
        print_color(f"Files in bucket '{bucket_name}':", Colors.BLUE)
        try:
            response = s3.list_objects_v2(Bucket=bucket_name)
            if 'Contents' not in response:
                print_color("No files found in bucket", Colors.YELLOW)
                return
            
            files = [obj['Key'] for obj in response['Contents']]
            print()
            for i, f in enumerate(files, 1):
                print(f"{i}. {f}")
            
            print()
            selection = input("Select file number (or enter file name): ").strip()
            
            if selection.isdigit():
                index = int(selection) - 1
                if 0 <= index < len(files):
                    file_name = files[index]
            else:
                file_name = selection
        
        except ClientError as e:
            print_color(f"Error: {e}", Colors.RED)
            return
    
    # Set download path
    if not download_path:
        default_path = os.path.join(Path.home(), 'Downloads', file_name)
        confirm = input(f"Download to ~/Downloads/{file_name}? (Y/n): ").strip().lower()
        
        if confirm == 'n':
            download_path = input("Enter download path: ").strip()
            download_path = os.path.expanduser(download_path)
        else:
            download_path = default_path
    
    print()
    print_color(f"Downloading '{file_name}' from bucket '{bucket_name}'...", Colors.YELLOW)
    
    try:
        # Ensure directory exists
        os.makedirs(os.path.dirname(download_path), exist_ok=True)
        
        s3.download_file(bucket_name, file_name, download_path)
        
        print()
        print_color("✓ File downloaded successfully!", Colors.GREEN)
        print(f"Saved to: {download_path}")
        
        # Show file size
        file_size = os.path.getsize(download_path)
        print(f"File size: {file_size / (1024*1024):.2f} MB")
    
    except ClientError as e:
        print_color(f"✗ Failed to download file: {e}", Colors.RED)

def dump_bucket(s3, bucket_name=None):
    """Download all files from bucket as a zip"""
    if not bucket_name:
        bucket_name = select_bucket(s3)
    
    if not bucket_name:
        return
    
    try:
        # Check if bucket has files
        response = s3.list_objects_v2(Bucket=bucket_name)
        if 'Contents' not in response:
            print_color(f"Bucket '{bucket_name}' is empty", Colors.YELLOW)
            return
        
        file_count = len(response['Contents'])
        print_color(f"Bucket '{bucket_name}' contains {file_count} files", Colors.BLUE)
        
        # Generate zip filename
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        zip_filename = f"{bucket_name}_{timestamp}.zip"
        default_zip_path = os.path.join(Path.home(), 'Downloads', zip_filename)
        
        print()
        confirm = input(f"Save zip to ~/Downloads/{zip_filename}? (Y/n): ").strip().lower()
        
        if confirm == 'n':
            zip_path = input("Enter zip file path: ").strip()
            zip_path = os.path.expanduser(zip_path)
        else:
            zip_path = default_zip_path
        
        # Create temporary directory
        temp_dir = tempfile.mkdtemp()
        
        print()
        print_color("Downloading files from bucket...", Colors.YELLOW)
        
        # Download all files
        downloaded_count = 0
        for obj in response['Contents']:
            key = obj['Key']
            local_path = os.path.join(temp_dir, key)
            os.makedirs(os.path.dirname(local_path), exist_ok=True)
            s3.download_file(bucket_name, key, local_path)
            downloaded_count += 1
        
        print_color("✓ Files downloaded", Colors.GREEN)
        print(f"Downloaded {downloaded_count} files")
        
        # Create zip
        print()
        print_color("Creating zip archive...", Colors.YELLOW)
        
        os.makedirs(os.path.dirname(zip_path), exist_ok=True)
        
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
            for root, dirs, files in os.walk(temp_dir):
                for file in files:
                    file_path = os.path.join(root, file)
                    arcname = os.path.relpath(file_path, temp_dir)
                    zipf.write(file_path, arcname)
        
        print_color("✓ Zip archive created", Colors.GREEN)
        
        # Show info
        zip_size = os.path.getsize(zip_path)
        print()
        print("----------------------------------------")
        print_color(f"Zip file: {zip_path}", Colors.GREEN)
        print_color(f"Size: {zip_size / (1024*1024):.2f} MB", Colors.GREEN)
        print_color(f"Files: {downloaded_count}", Colors.GREEN)
        print("----------------------------------------")
        
        # Cleanup
        shutil.rmtree(temp_dir)
        print()
        print_color("Dump complete!", Colors.GREEN)
    
    except ClientError as e:
        print_color(f"Error: {e}", Colors.RED)

def bucket_info(s3, bucket_name=None):
    """Get bucket information"""
    if not bucket_name:
        bucket_name = input("Enter bucket name: ").strip()
    
    if not bucket_name:
        print_color("Error: Bucket name is required", Colors.RED)
        return
    
    try:
        s3.head_bucket(Bucket=bucket_name)
        
        print_color(f"Bucket Information: {bucket_name}", Colors.BLUE)
        print("----------------------------------------")
        
        # Get region
        location = s3.get_bucket_location(Bucket=bucket_name)
        region = location['LocationConstraint'] or 'us-east-1'
        print(f"Region: {region}")
        
        # Get versioning
        versioning = s3.get_bucket_versioning(Bucket=bucket_name)
        status = versioning.get('Status', 'Disabled')
        print(f"Versioning: {status}")
        
        # Get object count
        response = s3.list_objects_v2(Bucket=bucket_name)
        if 'Contents' in response:
            count = len(response['Contents'])
            total_size = sum(obj['Size'] for obj in response['Contents'])
            print(f"Objects: {count}")
            print(f"Total Size: {total_size / (1024*1024):.2f} MB")
        else:
            print("Objects: 0")
    
    except ClientError as e:
        print_color(f"Error: {e}", Colors.RED)

def main():
    """Main script execution"""
    if not check_aws_credentials():
        sys.exit(1)
    
    if len(sys.argv) < 2:
        show_usage()
        sys.exit(0)
    
    command = sys.argv[1].lower()
    args = sys.argv[2:] if len(sys.argv) > 2 else []
    
    s3 = boto3.client('s3')
    
    if command == 'list':
        list_buckets(s3)
    elif command == 'create':
        create_bucket(s3)
    elif command == 'delete':
        bucket_name = args[0] if args else None
        delete_bucket(s3, bucket_name)
    elif command == 'upload':
        files = args[:-1] if args and args[-1] else args
        bucket_name = args[-1] if args else None
        upload_files(s3, files, bucket_name)
    elif command == 'download':
        bucket_name = args[0] if len(args) > 0 else None
        file_name = args[1] if len(args) > 1 else None
        download_path = args[2] if len(args) > 2 else None
        download_file(s3, bucket_name, file_name, download_path)
    elif command == 'dump':
        bucket_name = args[0] if args else None
        dump_bucket(s3, bucket_name)
    elif command == 'info':
        bucket_name = args[0] if args else None
        bucket_info(s3, bucket_name)
    elif command in ['help', '--help', '-h']:
        show_usage()
    else:
        print_color(f"Error: Unknown command '{command}'", Colors.RED)
        print()
        show_usage()
        sys.exit(1)

if __name__ == "__main__":
    main()
