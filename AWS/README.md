# AWS DFIR Tools - Usage Examples

This directory contains forensic and incident response tools for AWS environments. Below are usage examples for each tool.

---

## 📋 Table of Contents
- [Installation AWS CLI](#installation-aws-cli)
- [Connection Testing](#connection-testing)
- [EC2 Management](#ec2-management)
- [RDS Tools](#rds-tools)
- [S3 Management](#s3-management)
- [CloudTrail Investigation](#cloudtrail-investigation)
- [EBS Snapshot Tools](#ebs-snapshot-tools)

---

## Installation AWS CLI

### install_aws_cli_macos.sh
Install AWS CLI v2 on macOS.

```bash
# Install AWS CLI
./install_aws_cli_macos.sh

# Verify installation
aws --version
```

---

## Connection Testing

### hello_aws.py
Test AWS credentials and connection.

```bash
# Test AWS connection (bash/python/powershell available)
python3 hello_aws.py

# Output shows:
# - Account ID
# - Available regions
# - Connection status
```

---

## EC2 Management

### ec2_manager.sh
Manage EC2 instances (list, create, start, stop, terminate).

```bash
# List all EC2 instances (.sh / .ps1 / .py available)
./ec2_manager.sh list

# Create a new instance
./ec2_manager.sh create --ami-id ami-12345678 --instance-type t2.micro

# Start an instance
./ec2_manager.sh start i-1234567890abcdef0

# Stop an instance
./ec2_manager.sh stop i-1234567890abcdef0

# Delete (terminate) an instance
./ec2_manager.sh delete i-1234567890abcdef0
```

### ec2_evidence.ps1
Collect forensic evidence from EC2 instances.

```powershell
# Collect evidence from an instance
.\ec2_evidence.ps1 -InstanceId i-1234567890abcdef0 -OutputPath ./evidence

# Include memory dump
.\ec2_evidence.ps1 -InstanceId i-1234567890abcdef0 -OutputPath ./evidence -IncludeMemory
```

### forensic_disk_collection.ps1
Automated forensic disk collection from EC2.

```powershell
# Collect disk evidence
.\forensic_disk_collection.ps1 -InstanceId i-1234567890abcdef0

# Specify target region
.\forensic_disk_collection.ps1 -InstanceId i-1234567890abcdef0 -Region us-west-2
```

---

## RDS Tools

### rds_connect.sh
Connect to RDS instances (public or private). Creates SSH tunnel via bastion host for private RDS.

```bash
# Connect to a public RDS instance
./rds_connect.sh my-rds-instance

# Connect to a private RDS instance (automatically creates bastion)
./rds_connect.sh my-private-rds-instance

# Once connected, use MySQL client:
# mysql -h 127.0.0.1 -P 3307 -u admin -p
```

### rds_dump_database.sh
Dump RDS databases for backup or forensic analysis.

```bash
# Step 1: Connect to RDS (in terminal 1)
./rds_connect.sh my-rds-instance

# Step 2: In a new terminal, list available databases
./rds_dump_database.sh --list

# Dump a specific database
./rds_dump_database.sh --dump my_database

# Dump without compression
./rds_dump_database.sh --dump my_database --no-compress

# Interactive mode (select from menu)
./rds_dump_database.sh

# Custom output directory
./rds_dump_database.sh --dump my_database --output /path/to/backups
```

**⚠️ Important:** This tool requires `rds_connect.sh` to be running first in a separate terminal. It uses the existing SSH tunnel created by `rds_connect.sh` to access the RDS instance.

### rds_insert_mock_data.sh
Insert mock e-commerce data into RDS for testing.

```bash
# Step 1: Connect to RDS (in terminal 1)
./rds_connect.sh my-rds-instance

# Step 2: In a new terminal, insert mock data
./rds_insert_mock_data.sh

# Mock data includes:
# - 10 customers
# - 10 products
# - 5 sales with correlations
```

**⚠️ Important:** This tool requires `rds_connect.sh` to be running first in a separate terminal. It uses the existing SSH tunnel created by `rds_connect.sh` to access the RDS instance.

### rds_manager.sh
Manage RDS instances lifecycle.

```bash
# List all RDS instances
./rds_manager.sh list

# Create RDS instance
./rds_manager.sh create --db-name mydb --instance-class db.t3.micro

# Stop RDS instance
./rds_manager.sh stop my-rds-instance

# Start RDS instance
./rds_manager.sh start my-rds-instance

# Delete RDS instance
./rds_manager.sh delete my-rds-instance
```

---

## S3 Management

### s3_manager.sh
Manage S3 buckets (list, create, delete, upload, download, dump).

```bash
# List all S3 buckets (.sh / .ps1 / .py available)
./s3_manager.sh list

# Create a new bucket
./s3_manager.sh create my-forensic-bucket

# Upload file to bucket
./s3_manager.sh upload my-bucket /path/to/evidence.zip

# Download file from bucket
./s3_manager.sh download my-bucket evidence.zip /local/path/

# Dump entire bucket contents
./s3_manager.sh dump my-bucket /local/directory/

# Delete bucket
./s3_manager.sh delete my-bucket
```

### s3_bucket_evidence.py
Specialized tool for collecting S3 bucket evidence.

```bash
# Collect evidence from a bucket
python3 s3_bucket_evidence.py --bucket-name my-bucket --output-dir ./evidence

# Include object metadata
python3 s3_bucket_evidence.py --bucket-name my-bucket --include-metadata
```

---

## CloudTrail Investigation

### cloudtrail_investigation.ps1
Investigate security incidents using CloudTrail logs.

```powershell
# Search for specific user activity
.\cloudtrail_investigation.ps1 -UserName suspicious-user -StartTime "2025-01-01" -EndTime "2025-01-31"

# Search for specific event
.\cloudtrail_investigation.ps1 -EventName "DeleteBucket" -Region us-east-1

# Export results to CSV
.\cloudtrail_investigation.ps1 -UserName user123 -OutputFile investigation.csv
```

---

## EBS Snapshot Tools

### aws_ebs_snapshot_collector.py
Collects EBS snapshots and generates SHA256 hashes for forensic analysis.

```bash
# Collect snapshot and generate hash
python3 aws_ebs_snapshot_collector.py --instance-id i-1234567890abcdef0

# Specify output directory
python3 aws_ebs_snapshot_collector.py --instance-id i-1234567890abcdef0 --output-dir ./evidence
```

### aws_ebs_snapshot_hash.py
Generates SHA256 hashes for existing EBS snapshots.

```bash
# Generate hash for a specific snapshot
python3 aws_ebs_snapshot_hash.py --snapshot-id snap-1234567890abcdef0

# Generate hashes for all snapshots in a region
python3 aws_ebs_snapshot_hash.py --region us-east-1
```
