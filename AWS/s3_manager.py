#!/usr/bin/env python3

"""
S3 Manager Script - Python
Author: NimbusDFIR
Description: S3 bucket manager
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
    CYAN = '\033[0;36m'
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
        print("Run: aws configure")
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
    print("  list                List all S3 buckets")
    print("  create              Create a new S3 bucket")
    print("  delete [bucket]     Delete an S3 bucket")
    print("  upload <path> [bucket]  Upload file/folder to bucket")
    print("  download <bucket> <file>  Download a file from bucket")
    print("  dump <bucket>       Download all files from bucket as zip")
    print("  help                Show this help message")
    print()
    print("Examples:")
    print("  python s3_manager.py list")
    print("  python s3_manager.py create")
    print("  python s3_manager.py delete my-bucket")
    print("  python s3_manager.py upload /path/to/photo.jpg my-bucket")
    print("  python s3_manager.py upload /path/to/folder")
    print("  python s3_manager.py download my-bucket photo.jpg")
    print("  python s3_manager.py dump my-bucket")
    print()

def list_buckets():
    """List all S3 buckets"""
    print_color("Listing S3 buckets...", Colors.YELLOW)
    print()
    
    s3 = boto3.client('s3')
    
    print_color("[AWS CLI] aws s3api list-buckets", Colors.CYAN)
    try:
        response = s3.list_buckets()
        buckets = response.get('Buckets', [])
        
        if not buckets:
            print_color("No buckets found", Colors.RED)
            return
        
        print_color("Available buckets:", Colors.BLUE)
        print()
        print_color(f"{'Bucket Name':<40} {'Created'}", Colors.CYAN)
        print_color(f"{'-----------':<40} {'-------'}", Colors.CYAN)
        
        for bucket in buckets:
            print_color(f"{bucket['Name']:<40} {bucket['CreationDate']}", Colors.GREEN)
        
        print()
        print(f"Total: {len(buckets)} bucket(s)")
        
    except ClientError as e:
        print_color(f"Error listing buckets: {str(e)}", Colors.RED)

def create_bucket(bucket_name=None):
    """Create a new S3 bucket"""
    # If no bucket name provided, ask for it
    if not bucket_name:
        bucket_name = input("New bucket name: ").strip()
    
    if not bucket_name:
        print_color("Error: Bucket name cannot be empty", Colors.RED)
        return
    
    print_color(f"Creating bucket '{bucket_name}'...", Colors.YELLOW)
    
    s3 = boto3.client('s3')
    
    print_color(f"[AWS CLI] aws s3api create-bucket --bucket {bucket_name}", Colors.CYAN)
    try:
        s3.create_bucket(Bucket=bucket_name)
        print_color("✓ Bucket created successfully", Colors.GREEN)
    except ClientError as e:
        print_color("✗ Failed to create bucket", Colors.RED)
        print_color(str(e), Colors.RED)

def delete_bucket(bucket_name=None):
    """Delete an S3 bucket"""
    s3 = boto3.client('s3')
    
    # If no bucket name provided, list buckets for selection
    if not bucket_name:
        print_color("Available buckets:", Colors.YELLOW)
        
        try:
            response = s3.list_buckets()
            buckets = response.get('Buckets', [])
            
            if not buckets:
                print_color("No buckets found", Colors.RED)
                return
            
            print()
            for i, bucket in enumerate(buckets, 1):
                print(f"{i}. {bucket['Name']}")
            
            print()
            selection = input("Select bucket number to delete: ").strip()
            
            if selection.isdigit():
                index = int(selection) - 1
                if 0 <= index < len(buckets):
                    bucket_name = buckets[index]['Name']
                else:
                    print_color("Invalid selection", Colors.RED)
                    return
            else:
                print_color("Invalid input", Colors.RED)
                return
                
        except ClientError as e:
            print_color(f"Error listing buckets: {str(e)}", Colors.RED)
            return
    
    # Confirm deletion
    print()
    print_color("WARNING: This action cannot be undone!", Colors.RED)
    confirm = input(f"Are you sure you want to delete bucket '{bucket_name}'? (y/N): ").strip()
    
    if confirm.lower() != 'y':
        print_color("Operation cancelled", Colors.YELLOW)
        return
    
    print_color(f"Deleting bucket '{bucket_name}'...", Colors.YELLOW)
    
    print_color(f"[AWS CLI] aws s3 rm s3://{bucket_name} --recursive", Colors.CYAN)
    print_color(f"[AWS CLI] aws s3api delete-bucket --bucket {bucket_name}", Colors.CYAN)
    try:
        # Try to empty the bucket first
        try:
            bucket = boto3.resource('s3').Bucket(bucket_name)
            bucket.objects.all().delete()
        except:
            pass
        
        # Delete the bucket
        s3.delete_bucket(Bucket=bucket_name)
        print_color("✓ Bucket deleted successfully", Colors.GREEN)
        
    except ClientError as e:
        print_color("✗ Failed to delete bucket", Colors.RED)
        print_color(str(e), Colors.RED)

def upload_files(path, bucket_name=None):
    """Upload file or folder to S3 bucket"""
    # Check if path was provided
    if not path:
        print_color("Usage: python s3_manager.py upload <path> [bucket]", Colors.YELLOW)
        return
    
    # Check if path exists
    if not os.path.exists(path):
        print_color(f"Error: Path '{path}' not found", Colors.RED)
        return
    
    s3 = boto3.client('s3')
    
    # If no bucket name provided, list buckets for selection
    if not bucket_name:
        print_color("Available buckets:", Colors.YELLOW)
        
        try:
            response = s3.list_buckets()
            buckets = response.get('Buckets', [])
            
            if not buckets:
                print_color("No buckets found", Colors.RED)
                return
            
            print()
            for i, bucket in enumerate(buckets, 1):
                print(f"{i}. {bucket['Name']}")
            
            print()
            selection = input("Select bucket number for upload: ").strip()
            
            if selection.isdigit():
                index = int(selection) - 1
                if 0 <= index < len(buckets):
                    bucket_name = buckets[index]['Name']
                else:
                    print_color("Invalid selection", Colors.RED)
                    return
            else:
                print_color("Invalid input", Colors.RED)
                return
                
        except ClientError as e:
            print_color(f"Error listing buckets: {str(e)}", Colors.RED)
            return
    
    # Verify bucket exists
    try:
        s3.head_bucket(Bucket=bucket_name)
    except ClientError:
        print_color(f"Error: Bucket '{bucket_name}' not found or access denied", Colors.RED)
        return
    
    # Check if path is a file or directory
    if os.path.isdir(path):
        # It's a directory - upload all files
        print_color(f"Uploading folder '{path}' to bucket '{bucket_name}'...", Colors.YELLOW)
        print_color(f"[AWS CLI] aws s3 sync {path} s3://{bucket_name}/", Colors.CYAN)
        
        uploaded_count = 0
        for root, dirs, files in os.walk(path):
            for file in files:
                local_path = os.path.join(root, file)
                relative_path = os.path.relpath(local_path, path)
                
                try:
                    s3.upload_file(local_path, bucket_name, relative_path)
                    uploaded_count += 1
                except ClientError:
                    pass
        
        if uploaded_count > 0:
            print_color(f"✓ Folder uploaded successfully ({uploaded_count} file(s))", Colors.GREEN)
        else:
            print_color("✗ Failed to upload folder", Colors.RED)
    else:
        # It's a file - upload single file
        file_name = os.path.basename(path)
        print_color(f"Uploading file '{file_name}' to bucket '{bucket_name}'...", Colors.YELLOW)
        print_color(f"[AWS CLI] aws s3 cp {path} s3://{bucket_name}/{file_name}", Colors.CYAN)
        
        try:
            s3.upload_file(path, bucket_name, file_name)
            print_color("✓ File uploaded successfully", Colors.GREEN)
        except ClientError as e:
            print_color("✗ Failed to upload file", Colors.RED)
            print_color(str(e), Colors.RED)

def download_file(bucket_name, file_name):
    """Download a file from S3 bucket"""
    if not bucket_name or not file_name:
        print_color("Usage: python s3_manager.py download <bucket> <file>", Colors.YELLOW)
        return
    
    s3 = boto3.client('s3')
    
    # Verify bucket exists
    try:
        s3.head_bucket(Bucket=bucket_name)
    except ClientError:
        print_color(f"Error: Bucket '{bucket_name}' not found or access denied", Colors.RED)
        return
    
    # Default path and ask user
    downloads_folder = str(Path.home() / "Downloads")
    default_path = os.path.join(downloads_folder, file_name)
    
    print_color(f"Default destination: {default_path}", Colors.BLUE)
    custom = input("Change destination? (y/N): ").strip()
    
    if custom.lower() == 'y':
        download_path = input("Enter full path for destination file: ").strip()
        if not download_path:
            download_path = default_path
    else:
        download_path = default_path
    
    # Create directory if it doesn't exist
    os.makedirs(os.path.dirname(download_path), exist_ok=True)
    
    print_color(f"Downloading '{file_name}' from '{bucket_name}'...", Colors.YELLOW)
    print_color(f"[AWS CLI] aws s3 cp s3://{bucket_name}/{file_name} {download_path}", Colors.CYAN)
    
    try:
        s3.download_file(bucket_name, file_name, download_path)
        print_color("✓ Download completed", Colors.GREEN)
        print(f"Destination: {download_path}")
    except ClientError as e:
        print_color("✗ Failed to download file", Colors.RED)
        print_color(str(e), Colors.RED)

def dump_bucket(bucket_name=None):
    """Dump bucket to zip file"""
    s3 = boto3.client('s3')
    
    # If no bucket name provided, list buckets for selection
    if not bucket_name:
        print_color("Available buckets:", Colors.YELLOW)
        
        try:
            response = s3.list_buckets()
            buckets = response.get('Buckets', [])
            
            if not buckets:
                print_color("No buckets found", Colors.RED)
                return
            
            print()
            for i, bucket in enumerate(buckets, 1):
                print(f"{i}. {bucket['Name']}")
            
            print()
            selection = input("Select bucket number to dump: ").strip()
            
            if selection.isdigit():
                index = int(selection) - 1
                if 0 <= index < len(buckets):
                    bucket_name = buckets[index]['Name']
                else:
                    print_color("Invalid selection", Colors.RED)
                    return
            else:
                print_color("Invalid input", Colors.RED)
                return
                
        except ClientError as e:
            print_color(f"Error listing buckets: {str(e)}", Colors.RED)
            return
    
    # Verify bucket exists
    try:
        s3.head_bucket(Bucket=bucket_name)
    except ClientError:
        print_color(f"Error: Bucket '{bucket_name}' not found or access denied", Colors.RED)
        return
    
    # Zip file name
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    zip_filename = f"{bucket_name}_{timestamp}.zip"
    downloads_folder = str(Path.home() / "Downloads")
    default_zip_path = os.path.join(downloads_folder, zip_filename)
    
    print()
    print_color(f"Default destination: {default_zip_path}", Colors.BLUE)
    custom = input("Change destination? (y/N): ").strip()
    
    if custom.lower() == 'y':
        zip_path = input("Enter full path for zip file: ").strip()
        if not zip_path:
            zip_path = default_zip_path
    else:
        zip_path = default_zip_path
    
    # Create temporary directory
    temp_dir = tempfile.mkdtemp()
    
    try:
        print()
        print_color("Downloading files from bucket...", Colors.YELLOW)
        print_color(f"[AWS CLI] aws s3 sync s3://{bucket_name} <temp_folder>", Colors.CYAN)
        
        # List and download all objects
        bucket = boto3.resource('s3').Bucket(bucket_name)
        objects = list(bucket.objects.all())
        
        if not objects:
            print_color("Bucket is empty", Colors.YELLOW)
            return
        
        downloaded_count = 0
        for obj in objects:
            try:
                file_path = os.path.join(temp_dir, obj.key)
                os.makedirs(os.path.dirname(file_path), exist_ok=True)
                bucket.download_file(obj.key, file_path)
                downloaded_count += 1
            except Exception as e:
                # Continue downloading other files even if one fails
                pass
        
        if downloaded_count > 0:
            print_color(f"✓ Files downloaded ({downloaded_count} file(s))", Colors.GREEN)
            print()
            print_color("Creating zip archive...", Colors.YELLOW)
            
            # Create zip file
            with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
                for root, dirs, files in os.walk(temp_dir):
                    for file in files:
                        file_path = os.path.join(root, file)
                        arcname = os.path.relpath(file_path, temp_dir)
                        zipf.write(file_path, arcname)
            
            print_color("✓ Zip archive created", Colors.GREEN)
            print()
            print("----------------------------------------")
            print_color(f"Zip file: {zip_path}", Colors.GREEN)
            
            zip_size = os.path.getsize(zip_path)
            print_color(f"Size: {zip_size / (1024 * 1024):.2f} MB", Colors.GREEN)
            print("----------------------------------------")
        else:
            print_color("✗ Failed to download files from bucket", Colors.RED)
        
    except ClientError as e:
        print_color("✗ Failed to download files from bucket", Colors.RED)
        print_color(str(e), Colors.RED)
    finally:
        # Remove temporary directory
        shutil.rmtree(temp_dir, ignore_errors=True)
    
    print()
    print_color("Dump completed!", Colors.GREEN)

def main():
    """Main function"""
    if len(sys.argv) < 2:
        show_usage()
        sys.exit(0)
    
    command = sys.argv[1].lower()
    
    if command == 'help':
        show_usage()
        sys.exit(0)
    
    if not check_aws_credentials():
        sys.exit(1)
    
    if command == 'list':
        list_buckets()
    elif command == 'create':
        bucket_name = sys.argv[2] if len(sys.argv) >= 3 else None
        create_bucket(bucket_name)
    elif command == 'delete':
        bucket_name = sys.argv[2] if len(sys.argv) >= 3 else None
        delete_bucket(bucket_name)
    elif command == 'upload':
        if len(sys.argv) >= 4:
            upload_files(sys.argv[2], sys.argv[3])
        elif len(sys.argv) >= 3:
            upload_files(sys.argv[2])
        else:
            print_color("Usage: python s3_manager.py upload <path> [bucket]", Colors.YELLOW)
    elif command == 'download':
        if len(sys.argv) >= 4:
            download_file(sys.argv[2], sys.argv[3])
        else:
            print_color("Usage: python s3_manager.py download <bucket> <file>", Colors.YELLOW)
    elif command == 'dump':
        bucket_name = sys.argv[2] if len(sys.argv) >= 3 else None
        dump_bucket(bucket_name)
    else:
        show_usage()
        sys.exit(1)

if __name__ == "__main__":
    main()
