#!/usr/bin/env python3
"""
s3_bucket_evidence.py
Collects forensic evidence for every S3 bucket in an AWS account
and stores the results in a timestamped JSON file.

Requirements:
  pip install boto3 python-dotenv
"""

import boto3
import botocore
import os
import json
from datetime import datetime
from pathlib import Path
from dotenv import load_dotenv
from typing import Dict, Any, List, Optional


# ------------- Load AWS credentials ------------------------------------ #

def load_credentials() -> Dict[str, str]:
    """
    Load AWS credentials from a .env file located one level
    above this script OR fall back to environment variables.
    """
    env_path = Path(__file__).resolve().parent.parent / ".env"
    if env_path.exists():
        load_dotenv(dotenv_path=env_path)

    key    = os.getenv("AWS_ACCESS_KEY_ID")
    secret = os.getenv("AWS_SECRET_ACCESS_KEY")
    token  = os.getenv("AWS_SESSION_TOKEN") or None
    region = os.getenv("AWS_REGION") or "us-east-1"

    if not key or not secret:
        raise RuntimeError("AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY not set.")

    return {
        "aws_access_key_id": key,
        "aws_secret_access_key": secret,
        "aws_session_token": token,
        "region_name": region,
    }


def create_s3_client(creds: Dict[str, str]):
    """Create a boto3 S3 client using the loaded credentials."""
    return boto3.client(
        "s3",
        aws_access_key_id=creds["aws_access_key_id"],
        aws_secret_access_key=creds["aws_secret_access_key"],
        aws_session_token=creds["aws_session_token"],
        region_name=creds["region_name"],
    )


# ------------- Safe API call wrapper ----------------------------------- #

def safe_call(callable_, *args, **kwargs) -> Optional[Any]:
    """
    Wraps boto3 API calls to avoid crashing on permission errors
    or missing data. Returns None or error message.
    """
    try:
        return callable_(*args, **kwargs)
    except botocore.exceptions.ClientError as e:
        return {"_error": e.response["Error"]["Message"]}


# ------------- Optional: Bucket object stats --------------------------- #

def get_object_stats(s3, bucket: str) -> Dict[str, Any]:
    """
    Counts total number of objects and total size in bytes for a given bucket.
    WARNING: This may be slow or costly for large buckets.
    """
    total_size = 0
    object_count = 0

    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket):
        for obj in page.get("Contents", []):
            object_count += 1
            total_size += obj["Size"]

    return {"object_count": object_count, "total_size_bytes": total_size}


# ------------- Collect info for a single bucket ------------------------ #

def collect_bucket_info(s3, bucket: Dict[str, Any], include_objects: bool = False) -> Dict[str, Any]:
    """Collects metadata and configuration info from a single S3 bucket."""
    name = bucket["Name"]
    info = {
        "bucket_name": name,
        "creation_date": bucket["CreationDate"].isoformat(),
        "location": safe_call(s3.get_bucket_location, Bucket=name),
        "acl": safe_call(s3.get_bucket_acl, Bucket=name),
        "public_access_block": safe_call(s3.get_public_access_block, Bucket=name),
        "policy": safe_call(s3.get_bucket_policy, Bucket=name),
        "versioning": safe_call(s3.get_bucket_versioning, Bucket=name),
        "encryption": safe_call(s3.get_bucket_encryption, Bucket=name),
        "logging": safe_call(s3.get_bucket_logging, Bucket=name),
        "lifecycle": safe_call(s3.get_bucket_lifecycle_configuration, Bucket=name),
    }

    if include_objects:
        info.update(get_object_stats(s3, name))

    return info


# ------------- Prompt output location ---------------------------------- #

def prompt_output_path() -> Path:
    """
    Asks the user where to save the output JSON file.
    Defaults to the Desktop if no path is provided.
    """
    default_path = Path.home() / "Desktop"
    print(f"\n💾 Output path (press Enter to use Desktop):")
    user_input = input("Enter directory path: ").strip()

    output_dir = Path(user_input) if user_input else default_path
    if not output_dir.exists():
        try:
            output_dir.mkdir(parents=True)
        except Exception as e:
            print(f"❌ Could not create directory: {e}")
            exit(1)

    return output_dir


# ------------- Main function ------------------------------------------- #

def main():
    print("=== S3 Forensic Evidence Collector ===")

    # Load credentials
    creds = load_credentials()
    s3 = create_s3_client(creds)

    # Ask user whether to include object-level stats
    include_objects = input("Include object count and total size? (y/N): ").strip().lower() == "y"

    # Get output path
    output_dir = prompt_output_path()

    # List buckets
    print("\n🔍 Retrieving bucket list...")
    buckets_resp = s3.list_buckets()
    bucket_list: List[Dict[str, Any]] = buckets_resp.get("Buckets", [])

    if not bucket_list:
        print("⚠️ No buckets found in this AWS account.")
        return

    # Collect evidence
    evidence: List[Dict[str, Any]] = []
    for bucket in bucket_list:
        print(f"📦 Processing: {bucket['Name']}")
        evidence.append(collect_bucket_info(s3, bucket, include_objects=include_objects))

    # Save to file
    timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    output_file = output_dir / f"s3_bucket_evidence_{timestamp}.json"

    try:
        output_file.write_text(json.dumps(evidence, indent=2, default=str))
        print(f"\n✅ Evidence saved to: {output_file}")
    except Exception as e:
        print(f"❌ Failed to write output file: {e}")


# ------------- Entry point --------------------------------------------- #

if __name__ == "__main__":
    main()
