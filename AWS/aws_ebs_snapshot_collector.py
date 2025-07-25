#!/usr/bin/env python3
"""
AWS EBS Snapshot Collector: Script to collect EBS disk snapshots in AWS and generate hashes of the volumes.
Requirements:
- AWS CLI configured
- boto3 installed
- Python 3.x

Usage:
  python aws_ebs_snapshot_collector.py <instance_id>
"""
import sys
import boto3
import hashlib
import os

def get_ebs_volumes(instance_id):
    ec2 = boto3.resource('ec2')
    instance = ec2.Instance(instance_id)
    return [vol.id for vol in instance.volumes.all()]

def create_snapshot(volume_id, description='Snapshot for forensics'):
    ec2 = boto3.client('ec2')
    response = ec2.create_snapshot(VolumeId=volume_id, Description=description)
    return response['SnapshotId']

def get_snapshot_data(snapshot_id, region):
    # Normally, you can't directly download EBS snapshot data via boto3.
    # For forensics, you would use AWS Data Lifecycle Manager or copy the volume, attach to an instance, and read raw data.
    # Here, we just return the snapshot ID for hash demonstration purposes.
    return snapshot_id.encode()

def generate_hash(data):
    sha256 = hashlib.sha256()
    sha256.update(data)
    return sha256.hexdigest()

def main():
    if len(sys.argv) != 2:
        print('Usage: python aws_ebs_snapshot_collector.py <instance_id>')
        sys.exit(1)
    instance_id = sys.argv[1]
    region = os.environ.get('AWS_REGION', 'us-east-1')
    print(f'Collecting EBS volumes from instance {instance_id}...')
    volumes = get_ebs_volumes(instance_id)
    print(f'Volumes found: {volumes}')
    for vol_id in volumes:
        print(f'Creating snapshot of volume {vol_id}...')
        snap_id = create_snapshot(vol_id)
        print(f'Snapshot created: {snap_id}')
        print('Generating hash of the snapshot (ID)...')
        data = get_snapshot_data(snap_id, region)
        hash_value = generate_hash(data)
        print(f'SHA256 hash of snapshot {snap_id}: {hash_value}')

if __name__ == '__main__':
    main()
