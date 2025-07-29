import boto3
import botocore
import re
import os
from dotenv import load_dotenv
from pathlib import Path

def validate_bucket_name(name):
    """
    Validates the bucket name according to AWS rules:
    - 3 to 63 characters
    - Only lowercase letters, numbers, hyphens and dots
    - No consecutive dots
    """
    return bool(re.match(r'^[a-z0-9.-]{3,63}$', name)) and not re.search(r'\.\.', name)

def load_credentials_from_env():
    """
    Loads AWS credentials from a .env file located two levels above this script.
    Returns a dictionary with access keys and region.
    """
    env_path = Path(__file__).resolve().parents[2] / ".env"
    if env_path.exists():
        load_dotenv(dotenv_path=env_path)
    else:
        print(f"❌ .env file not found at: {env_path}")
        exit(1)

    aws_access_key_id = os.getenv("AWS_ACCESS_KEY_ID")
    aws_secret_access_key = os.getenv("AWS_SECRET_ACCESS_KEY")
    aws_session_token = os.getenv("AWS_SESSION_TOKEN", "")
    aws_region = os.getenv("AWS_REGION", "us-east-1")

    if not aws_access_key_id or not aws_secret_access_key:
        print("❌ AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY is missing in .env")
        exit(1)

    return {
        "aws_access_key_id": aws_access_key_id,
        "aws_secret_access_key": aws_secret_access_key,
        "aws_session_token": aws_session_token if aws_session_token else None,
        "region_name": aws_region
    }

def create_s3_client(credentials):
    """
    Creates and returns a boto3 S3 client using the provided credentials.
    """
    return boto3.client(
        's3',
        aws_access_key_id=credentials['aws_access_key_id'],
        aws_secret_access_key=credentials['aws_secret_access_key'],
        aws_session_token=credentials['aws_session_token'],
        region_name=credentials['region_name']
    )

def create_bucket(s3, region):
    """
    Prompts the user for bucket name and ACL, then attempts to create the bucket.
    """
    while True:
        bucket_name = input("Enter a globally unique bucket name (lowercase letters, numbers, hyphens and dots): ").strip()
        if validate_bucket_name(bucket_name):
            break
        print("❌ Invalid bucket name. Try again.")

    # ACL options
    acls = ["private", "public-read", "public-read-write", "authenticated-read"]
    print(f"Available ACLs: {', '.join(acls)}")
    acl = input("Choose an ACL [private]: ").strip() or "private"
    if acl not in acls:
        print("Invalid ACL. Using 'private' as default.")
        acl = "private"

    # Create bucket
    try:
        if region == "us-east-1":
            s3.create_bucket(Bucket=bucket_name, ACL=acl)
        else:
            s3.create_bucket(
                Bucket=bucket_name,
                CreateBucketConfiguration={'LocationConstraint': region},
                ACL=acl
            )
        print(f"✅ Bucket '{bucket_name}' successfully created in region '{region}' with ACL '{acl}'")
    except botocore.exceptions.ClientError as e:
        print(f"❌ Error creating bucket: {e.response['Error']['Message']}")

def list_buckets(s3):
    """
    Lists all S3 buckets in the current AWS account.
    """
    try:
        response = s3.list_buckets()
        buckets = response.get('Buckets', [])
        if not buckets:
            print("ℹ️ No buckets found.")
        else:
            print("📦 Existing buckets:")
            for bucket in buckets:
                print(f" - {bucket['Name']}")
    except botocore.exceptions.ClientError as e:
        print(f"❌ Error listing buckets: {e.response['Error']['Message']}")

def delete_bucket(s3):
    """
    Lists buckets and prompts the user to choose one to delete.
    """
    try:
        response = s3.list_buckets()
        buckets = response.get('Buckets', [])
        if not buckets:
            print("ℹ️ No buckets available to delete.")
            return

        print("📦 Buckets available for deletion:")
        for i, bucket in enumerate(buckets):
            print(f"{i + 1}. {bucket['Name']}")

        choice = input("Enter the number of the bucket to delete (or 'cancel' to abort): ").strip()

        if choice.lower() == 'cancel':
            print("🚫 Operation cancelled.")
            return

        try:
            index = int(choice) - 1
            bucket_name = buckets[index]['Name']
        except (IndexError, ValueError):
            print("❌ Invalid selection.")
            return

        confirmation = input(f"⚠️ Are you sure you want to delete the bucket '{bucket_name}'? (y/n): ").strip().lower()
        if confirmation != 'y':
            print("🚫 Operation cancelled.")
            return

        s3.delete_bucket(Bucket=bucket_name)
        print(f"✅ Bucket '{bucket_name}' deleted successfully.")
    except botocore.exceptions.ClientError as e:
        print(f"❌ Error deleting bucket: {e.response['Error']['Message']}")

def main_menu():
    """
    Displays the main menu for the user to choose actions.
    """
    credentials = load_credentials_from_env()
    s3 = create_s3_client(credentials)

    while True:
        print("\n=== S3 Bucket Manager ===")
        print("1. Create bucket")
        print("2. List buckets")
        print("3. Delete bucket")
        print("4. Exit")

        option = input("Choose an option: ").strip()

        if option == '1':
            create_bucket(s3, credentials['region_name'])
        elif option == '2':
            list_buckets(s3)
        elif option == '3':
            delete_bucket(s3)
        elif option == '4':
            print("👋 Exiting...")
            break
        else:
            print("❌ Invalid option. Please try again.")

if __name__ == "__main__":
    main_menu()
