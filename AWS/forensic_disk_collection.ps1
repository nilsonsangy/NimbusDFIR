# Forensic Disk Collection in AWS using AWS CLI
# Author: [Your Name]
# This script helps collect disk evidence from compromised AWS EC2 instances
# It prompts the user step-by-step and stores all data in an Amazon S3 bucket

# Load environment variables from .env file
$envFile = ".\.env"
Get-Content $envFile | ForEach-Object {
    if ($_ -match "^\s*([A-Z_]+)\s*=\s*(.+?)\s*$") {
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
    }
}

# Configure AWS CLI with loaded credentials
aws configure set aws_access_key_id $env:AWS_ACCESS_KEY_ID
aws configure set aws_secret_access_key $env:AWS_SECRET_ACCESS_KEY
aws configure set region $env:AWS_REGION

Write-Host "AWS CLI configured with provided credentials."

# Step 1: Ask user for instance ID
$instanceId = Read-Host "Enter the compromised EC2 instance ID"

# Step 2: List attached EBS volumes
Write-Host "`nFetching attached EBS volumes..."
$volumes = aws ec2 describe-instances --instance-ids $instanceId --query "Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId" --output text

if (-not $volumes) {
    Write-Host "No volumes found or invalid instance ID." -ForegroundColor Red
    exit
}

Write-Host "Found the following volumes:"
$volumes -split "`n" | ForEach-Object { Write-Host "- $_" }

# Step 3: Create snapshots of each volume
$snapshotIds = @()
foreach ($volume in $volumes -split "`n") {
    Write-Host "`nCreating snapshot for volume $volume..."
    $snapshotId = aws ec2 create-snapshot --volume-id $volume --description "Forensic snapshot of $volume" --query "SnapshotId" --output text
    $snapshotIds += $snapshotId
    Write-Host "Snapshot created: $snapshotId"
}

# Step 4: Create temporary EC2 instance for bit-for-bit copy
$imageId = Read-Host "`nEnter the AMI ID to use for analysis instance (e.g. Amazon Linux 2)"
$instanceType = Read-Host "Enter instance type (e.g. t3.micro)"
$keyName = Read-Host "Enter key pair name for SSH access (must exist)"
$securityGroup = Read-Host "Enter Security Group ID to use"

Write-Host "`nLaunching forensic EC2 instance..."
$forensicInstanceId = aws ec2 run-instances `
    --image-id $imageId `
    --count 1 `
    --instance-type $instanceType `
    --key-name $keyName `
    --security-group-ids $securityGroup `
    --query "Instances[0].InstanceId" `
    --output text

Write-Host "Instance launched: $forensicInstanceId"

# Step 5: Ask user for S3 bucket to store evidence
$bucketName = Read-Host "`nEnter the name of the Amazon S3 evidence bucket"

# Step 6: Create folder (prefix) in S3 bucket
$evidenceFolder = Read-Host "Enter folder name for this case in S3 (e.g. case-20250729)"
aws s3api put-object --bucket $bucketName --key "$evidenceFolder/"

Write-Host "S3 evidence folder created: s3://$bucketName/$evidenceFolder"

# Step 7: Ask user to manually SSH into instance and perform dd + upload
Write-Host "`nNext steps:"
Write-Host "- SSH into forensic EC2 instance: ssh -i <key.pem> ec2-user@<public-ip>"
Write-Host "- Attach snapshots as volumes"
Write-Host "- Use dd or dc3dd to make raw .dd images"
Write-Host "- Upload .dd images to S3 with:"
Write-Host "    aws s3 cp <image>.dd s3://$bucketName/$evidenceFolder/"
Write-Host "`nDon't forget to terminate the forensic instance when done!"

# End of script
