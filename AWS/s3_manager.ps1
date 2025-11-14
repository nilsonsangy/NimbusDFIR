# S3 Manager Script - PowerShell
# Author: NimbusDFIR
# Description: Manage S3 buckets - list, create, remove, upload, download, and dump buckets

param(
    [Parameter(Position=0)]
    [ValidateSet('list', 'create', 'remove', 'delete', 'upload', 'download', 'dump', 'info', 'help')]
    [string]$Command,
    
    [Parameter(Position=1, ValueFromRemainingArguments=$true)]
    [string[]]$Arguments
)

# Check if AWS CLI is installed
function Test-AwsCli {
    try {
        $null = Get-Command aws -ErrorAction Stop
        return $true
    }
    catch {
        Write-Host "Error: AWS CLI is not installed" -ForegroundColor Red
        Write-Host "Please install AWS CLI first"
        return $false
    }
}

# Check if AWS credentials are configured
function Test-AwsCredentials {
    try {
        $null = aws sts get-caller-identity 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: AWS credentials not configured" -ForegroundColor Red
            Write-Host "Please run: aws configure"
            return $false
        }
        return $true
    }
    catch {
        Write-Host "Error: AWS credentials not configured" -ForegroundColor Red
        Write-Host "Please run: aws configure"
        return $false
    }
}

# Display usage information
function Show-Usage {
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "S3 Manager - NimbusDFIR"
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Usage: .\s3_manager.ps1 [COMMAND] [OPTIONS]"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  list              List all S3 buckets"
    Write-Host "  create            Create a new S3 bucket"
    Write-Host "  remove            Delete an S3 bucket"
    Write-Host "  upload            Upload files to a bucket"
    Write-Host "  download          Download a file from a bucket"
    Write-Host "  dump              Download all files from a bucket as a zip"
    Write-Host "  info              Get bucket information"
    Write-Host "  help              Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\s3_manager.ps1 list"
    Write-Host "  .\s3_manager.ps1 create"
    Write-Host "  .\s3_manager.ps1 upload C:\Pictures\* my-bucket"
    Write-Host "  .\s3_manager.ps1 download my-bucket file.jpg"
    Write-Host "  .\s3_manager.ps1 dump my-bucket"
    Write-Host ""
}

# List all S3 buckets
function Get-S3Buckets {
    Write-Host "Listing S3 Buckets..." -ForegroundColor Blue
    Write-Host ""
    
    $buckets = aws s3api list-buckets --query 'Buckets[*].[Name,CreationDate]' --output json | ConvertFrom-Json
    
    if (-not $buckets -or $buckets.Count -eq 0) {
        Write-Host "No S3 buckets found" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Bucket Name`t`t`t`tCreation Date" -ForegroundColor Green
    Write-Host "--------------------------------------------------------------------------------"
    
    foreach ($bucket in $buckets) {
        $name = $bucket[0]
        $date = $bucket[1]
        Write-Host "$name`t`t$date" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Total buckets: $($buckets.Count)" -ForegroundColor Green
}

# Create a new S3 bucket
function New-S3Bucket {
    Write-Host "Create New S3 Bucket" -ForegroundColor Blue
    Write-Host ""
    
    $bucketName = Read-Host "Enter bucket name (must be globally unique, lowercase, no spaces)"
    
    if ([string]::IsNullOrWhiteSpace($bucketName)) {
        Write-Host "Error: Bucket name is required" -ForegroundColor Red
        return
    }
    
    # Validate bucket name
    if ($bucketName -notmatch '^[a-z0-9][a-z0-9.-]*[a-z0-9]$') {
        Write-Host "Error: Invalid bucket name" -ForegroundColor Red
        Write-Host "Bucket names must:"
        Write-Host "  - Be 3-63 characters long"
        Write-Host "  - Start and end with lowercase letter or number"
        Write-Host "  - Contain only lowercase letters, numbers, hyphens, and periods"
        return
    }
    
    $currentRegion = aws configure get region
    $region = Read-Host "Enter region (default: $currentRegion)"
    if ([string]::IsNullOrWhiteSpace($region)) {
        $region = $currentRegion
    }
    
    Write-Host ""
    Write-Host "Creating bucket '$bucketName' in region '$region'..." -ForegroundColor Yellow
    
    # Create bucket
    try {
        if ($region -eq "us-east-1") {
            aws s3api create-bucket --bucket $bucketName --region $region | Out-Null
        }
        else {
            aws s3api create-bucket --bucket $bucketName --region $region --create-bucket-configuration LocationConstraint=$region | Out-Null
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Bucket '$bucketName' created successfully!" -ForegroundColor Green
            
            # Enable versioning
            $enableVersioning = Read-Host "Enable versioning? (y/N)"
            if ($enableVersioning -match '^[Yy]$') {
                aws s3api put-bucket-versioning --bucket $bucketName --versioning-configuration Status=Enabled
                Write-Host "✓ Versioning enabled" -ForegroundColor Green
            }
            
            # Block public access
            $blockPublic = Read-Host "Block all public access? (recommended) (Y/n)"
            if ($blockPublic -notmatch '^[Nn]$') {
                aws s3api put-public-access-block --bucket $bucketName --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
                Write-Host "✓ Public access blocked" -ForegroundColor Green
            }
        }
        else {
            Write-Host "✗ Failed to create bucket" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "✗ Failed to create bucket: $_" -ForegroundColor Red
    }
}

# Remove/delete a bucket
function Remove-S3Bucket {
    param([string]$BucketName)
    
    if ([string]::IsNullOrWhiteSpace($BucketName)) {
        Write-Host "Available buckets:" -ForegroundColor Yellow
        Get-S3Buckets
        Write-Host ""
        $BucketName = Read-Host "Enter bucket name to delete"
    }
    
    if ([string]::IsNullOrWhiteSpace($BucketName)) {
        Write-Host "Error: Bucket name is required" -ForegroundColor Red
        return
    }
    
    # Check if bucket exists
    try {
        $null = aws s3api head-bucket --bucket $BucketName 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Bucket '$BucketName' not found or not accessible" -ForegroundColor Red
            return
        }
    }
    catch {
        Write-Host "Error: Bucket '$BucketName' not found or not accessible" -ForegroundColor Red
        return
    }
    
    Write-Host "WARNING: This will permanently delete bucket '$BucketName'" -ForegroundColor Yellow
    $confirm = Read-Host "Are you sure? (yes/no)"
    
    if ($confirm -ne "yes") {
        Write-Host "Operation cancelled"
        return
    }
    
    # Empty bucket first
    Write-Host "Emptying bucket..." -ForegroundColor Yellow
    aws s3 rm "s3://$BucketName" --recursive 2>&1 | Out-Null
    
    Write-Host "Deleting bucket..."
    aws s3api delete-bucket --bucket $BucketName
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Bucket '$BucketName' deleted successfully" -ForegroundColor Green
    }
    else {
        Write-Host "✗ Failed to delete bucket" -ForegroundColor Red
    }
}

# Upload files to bucket
function Add-S3Files {
    param([string[]]$Files)
    
    if ($Files.Count -eq 0) {
        Write-Host "Error: No files specified" -ForegroundColor Red
        Write-Host "Usage: .\s3_manager.ps1 upload <files...> [bucket-name]"
        return
    }
    
    # Check if last argument is a bucket name
    $bucketName = $null
    $fileList = @()
    
    foreach ($arg in $Files) {
        if (Test-Path $arg -PathType Leaf) {
            $fileList += $arg
        }
        else {
            # Try as bucket name
            $null = aws s3api head-bucket --bucket $arg 2>&1
            if ($LASTEXITCODE -eq 0) {
                $bucketName = $arg
            }
        }
    }
    
    if ([string]::IsNullOrWhiteSpace($bucketName)) {
        Write-Host "Available buckets:" -ForegroundColor Blue
        $buckets = aws s3api list-buckets --query 'Buckets[*].Name' --output json | ConvertFrom-Json
        
        if (-not $buckets) {
            Write-Host "No buckets found" -ForegroundColor Red
            return
        }
        
        Write-Host ""
        for ($i = 0; $i -lt $buckets.Count; $i++) {
            Write-Host "$($i+1). $($buckets[$i])"
        }
        
        Write-Host ""
        $selection = Read-Host "Select bucket number (or enter bucket name)"
        
        if ($selection -match '^\d+$') {
            $index = [int]$selection - 1
            if ($index -ge 0 -and $index -lt $buckets.Count) {
                $bucketName = $buckets[$index]
            }
        }
        else {
            $bucketName = $selection
        }
    }
    
    Write-Host "Uploading files to bucket: $bucketName" -ForegroundColor Blue
    Write-Host ""
    
    $successCount = 0
    $failCount = 0
    
    foreach ($file in $fileList) {
        $fileName = Split-Path $file -Leaf
        Write-Host "Uploading $fileName... " -NoNewline
        
        aws s3 cp $file "s3://$bucketName/$fileName" --no-progress 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓" -ForegroundColor Green
            $successCount++
        }
        else {
            Write-Host "✗" -ForegroundColor Red
            $failCount++
        }
    }
    
    Write-Host ""
    Write-Host "----------------------------------------"
    Write-Host "Successfully uploaded: $successCount" -ForegroundColor Green
    if ($failCount -gt 0) {
        Write-Host "Failed: $failCount" -ForegroundColor Red
    }
}

# Download file from bucket
function Get-S3File {
    param([string[]]$Args)
    
    $bucketName = $null
    $fileName = $null
    $downloadPath = $null
    
    if ($Args.Count -ge 1) {
        $null = aws s3api head-bucket --bucket $Args[0] 2>&1
        if ($LASTEXITCODE -eq 0) {
            $bucketName = $Args[0]
            if ($Args.Count -ge 2) { $fileName = $Args[1] }
            if ($Args.Count -ge 3) { $downloadPath = $Args[2] }
        }
    }
    
    # Select bucket if not provided
    if ([string]::IsNullOrWhiteSpace($bucketName)) {
        Write-Host "Available buckets:" -ForegroundColor Blue
        $buckets = aws s3api list-buckets --query 'Buckets[*].Name' --output json | ConvertFrom-Json
        
        if (-not $buckets) {
            Write-Host "No buckets found" -ForegroundColor Red
            return
        }
        
        Write-Host ""
        for ($i = 0; $i -lt $buckets.Count; $i++) {
            Write-Host "$($i+1). $($buckets[$i])"
        }
        
        Write-Host ""
        $selection = Read-Host "Select bucket number (or enter bucket name)"
        
        if ($selection -match '^\d+$') {
            $index = [int]$selection - 1
            if ($index -ge 0 -and $index -lt $buckets.Count) {
                $bucketName = $buckets[$index]
            }
        }
        else {
            $bucketName = $selection
        }
    }
    
    # List files if not provided
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        Write-Host "Files in bucket '$bucketName':" -ForegroundColor Blue
        $files = aws s3 ls "s3://$bucketName" --recursive | ForEach-Object { ($_ -split '\s+', 4)[3] }
        
        if (-not $files) {
            Write-Host "No files found" -ForegroundColor Yellow
            return
        }
        
        $fileArray = @($files)
        Write-Host ""
        for ($i = 0; $i -lt $fileArray.Count; $i++) {
            Write-Host "$($i+1). $($fileArray[$i])"
        }
        
        Write-Host ""
        $selection = Read-Host "Select file number (or enter file name)"
        
        if ($selection -match '^\d+$') {
            $index = [int]$selection - 1
            if ($index -ge 0 -and $index -lt $fileArray.Count) {
                $fileName = $fileArray[$index]
            }
        }
        else {
            $fileName = $selection
        }
    }
    
    # Set download path
    if ([string]::IsNullOrWhiteSpace($downloadPath)) {
        $defaultPath = Join-Path $env:USERPROFILE "Downloads\$fileName"
        $confirm = Read-Host "Download to $defaultPath? (Y/n)"
        
        if ($confirm -match '^[Nn]$') {
            $downloadPath = Read-Host "Enter download path"
        }
        else {
            $downloadPath = $defaultPath
        }
    }
    
    Write-Host ""
    Write-Host "Downloading '$fileName' from bucket '$bucketName'..." -ForegroundColor Yellow
    
    aws s3 cp "s3://$bucketName/$fileName" $downloadPath
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "✓ File downloaded successfully!" -ForegroundColor Green
        Write-Host "Saved to: $downloadPath"
    }
    else {
        Write-Host "✗ Failed to download file" -ForegroundColor Red
    }
}

# Dump entire bucket to zip
function Export-S3Bucket {
    param([string]$BucketName)
    
    if ([string]::IsNullOrWhiteSpace($BucketName)) {
        Write-Host "Available buckets:" -ForegroundColor Blue
        $buckets = aws s3api list-buckets --query 'Buckets[*].Name' --output json | ConvertFrom-Json
        
        if (-not $buckets) {
            Write-Host "No buckets found" -ForegroundColor Red
            return
        }
        
        Write-Host ""
        for ($i = 0; $i -lt $buckets.Count; $i++) {
            Write-Host "$($i+1). $($buckets[$i])"
        }
        
        Write-Host ""
        $selection = Read-Host "Select bucket number (or enter bucket name)"
        
        if ($selection -match '^\d+$') {
            $index = [int]$selection - 1
            if ($index -ge 0 -and $index -lt $buckets.Count) {
                $BucketName = $buckets[$index]
            }
        }
        else {
            $BucketName = $selection
        }
    }
    
    # Check bucket
    $null = aws s3api head-bucket --bucket $BucketName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Bucket '$BucketName' not found" -ForegroundColor Red
        return
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $zipFilename = "${BucketName}_${timestamp}.zip"
    $defaultZipPath = Join-Path $env:USERPROFILE "Downloads\$zipFilename"
    
    Write-Host ""
    $confirm = Read-Host "Save zip to $defaultZipPath? (Y/n)"
    
    if ($confirm -match '^[Nn]$') {
        $zipPath = Read-Host "Enter zip file path"
    }
    else {
        $zipPath = $defaultZipPath
    }
    
    $tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ([System.Guid]::NewGuid()))
    
    Write-Host ""
    Write-Host "Downloading files from bucket..." -ForegroundColor Yellow
    
    aws s3 sync "s3://$BucketName" $tempDir.FullName --no-progress
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Files downloaded" -ForegroundColor Green
        
        Write-Host ""
        Write-Host "Creating zip archive..." -ForegroundColor Yellow
        
        Compress-Archive -Path "$($tempDir.FullName)\*" -DestinationPath $zipPath -Force
        
        Write-Host "✓ Zip archive created" -ForegroundColor Green
        Write-Host ""
        Write-Host "----------------------------------------"
        Write-Host "Zip file: $zipPath" -ForegroundColor Green
        
        $zipSize = (Get-Item $zipPath).Length
        Write-Host "Size: $([math]::Round($zipSize/1MB, 2)) MB" -ForegroundColor Green
        Write-Host "----------------------------------------"
    }
    
    Remove-Item -Path $tempDir.FullName -Recurse -Force
    Write-Host ""
    Write-Host "Dump complete!" -ForegroundColor Green
}

# Get bucket info
function Get-S3BucketInfo {
    param([string]$BucketName)
    
    if ([string]::IsNullOrWhiteSpace($BucketName)) {
        $BucketName = Read-Host "Enter bucket name"
    }
    
    $null = aws s3api head-bucket --bucket $BucketName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Bucket '$BucketName' not found" -ForegroundColor Red
        return
    }
    
    Write-Host "Bucket Information: $BucketName" -ForegroundColor Blue
    Write-Host "----------------------------------------"
    
    $region = aws s3api get-bucket-location --bucket $BucketName --query 'LocationConstraint' --output text
    if ($region -eq "None") { $region = "us-east-1" }
    Write-Host "Region: $region"
    
    $versioning = aws s3api get-bucket-versioning --bucket $BucketName --query 'Status' --output text
    if ([string]::IsNullOrWhiteSpace($versioning)) { $versioning = "Disabled" }
    Write-Host "Versioning: $versioning"
    
    Write-Host ""
    Write-Host "Calculating bucket size..."
    aws s3 ls "s3://$BucketName" --recursive --summarize | Select-Object -Last 2
}

# Main execution
if (-not (Test-AwsCli)) {
    exit 1
}

if (-not (Test-AwsCredentials)) {
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Command)) {
    Show-Usage
    exit 0
}

switch ($Command) {
    'list' {
        Get-S3Buckets
    }
    'create' {
        New-S3Bucket
    }
    { $_ -in 'remove', 'delete' } {
        Remove-S3Bucket -BucketName $Arguments[0]
    }
    'upload' {
        Add-S3Files -Files $Arguments
    }
    'download' {
        Get-S3File -Args $Arguments
    }
    'dump' {
        Export-S3Bucket -BucketName $Arguments[0]
    }
    'info' {
        Get-S3BucketInfo -BucketName $Arguments[0]
    }
    'help' {
        Show-Usage
    }
    default {
        Write-Host "Error: Unknown command '$Command'" -ForegroundColor Red
        Write-Host ""
        Show-Usage
        exit 1
    }
}
