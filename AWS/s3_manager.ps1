# S3 Manager Script - PowerShell
# Author: NimbusDFIR
# Description: S3 bucket manager

param(
    [Parameter(Position=0)]
    [ValidateSet('list', 'create', 'delete', 'upload', 'download', 'dump', 'help')]
    [string]$Command,

    [Parameter(Position=1, ValueFromRemainingArguments=$true)]
    [string[]]$Arguments
)

# -----------------------
# Environment Checks
# -----------------------

# Check if AWS CLI is installed
function Test-AwsCli {
    try {
        $null = Get-Command aws -ErrorAction Stop
        return $true
    }
    catch {
        Write-Host "Error: AWS CLI is not installed" -ForegroundColor Red
        return $false
    }
}

# Check if AWS credentials are configured
function Test-AwsCredentials {
    try {
        $null = aws sts get-caller-identity 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: AWS credentials not configured" -ForegroundColor Red
            Write-Host "Run: aws configure"
            return $false
        }
        return $true
    }
    catch {
        Write-Host "Error: AWS credentials not configured" -ForegroundColor Red
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
    Write-Host "  list                List all S3 buckets"
    Write-Host "  create              Create a new S3 bucket"
    Write-Host "  delete [bucket]     Delete an S3 bucket"
    Write-Host "  upload <path> [bucket]  Upload file/folder to bucket"
    Write-Host "  download <bucket> <file>  Download a file from bucket"
    Write-Host "  dump <bucket>       Download all files from bucket as zip"
    Write-Host "  help                Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\s3_manager.ps1 list"
    Write-Host "  .\s3_manager.ps1 create"
    Write-Host "  .\s3_manager.ps1 delete my-bucket"
    Write-Host "  .\s3_manager.ps1 upload C:\files\photo.jpg my-bucket"
    Write-Host "  .\s3_manager.ps1 upload C:\my-folder"
    Write-Host "  .\s3_manager.ps1 download my-bucket photo.jpg"
    Write-Host "  .\s3_manager.ps1 dump my-bucket"
    Write-Host ""
}

# -----------------------
# S3 Functions
# -----------------------

# List all S3 buckets
function Get-S3Buckets {
    Write-Host "Listing S3 buckets..." -ForegroundColor Yellow
    Write-Host ""
    
    # Get buckets list
    Write-Host "[AWS CLI] aws s3api list-buckets --output json" -ForegroundColor Magenta
    $jsonOutput = aws s3api list-buckets --output json
    $buckets = $jsonOutput | ConvertFrom-Json
    
    if (-not $buckets.Buckets -or $buckets.Buckets.Count -eq 0) {
        Write-Host "No buckets found" -ForegroundColor Red
        return
    }
    
    Write-Host "Available buckets:" -ForegroundColor Blue
    Write-Host ""
    Write-Host ("{0,-40} {1}" -f "Bucket Name", "Created") -ForegroundColor Cyan
    Write-Host ("{0,-40} {1}" -f "-----------", "-------") -ForegroundColor Cyan
    
    foreach ($bucket in $buckets.Buckets) {
        Write-Host ("{0,-40} {1}" -f $bucket.Name, $bucket.CreationDate) -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Total: $($buckets.Buckets.Count) bucket(s)"
}

# Create a new S3 bucket
function New-S3Bucket {
    param([string]$BucketName)
    
    # If no bucket name provided, ask for it
    if ([string]::IsNullOrWhiteSpace($BucketName)) {
        $BucketName = Read-Host "New bucket name"
    }
    
    if ([string]::IsNullOrWhiteSpace($BucketName)) {
        Write-Host "Error: Bucket name cannot be empty" -ForegroundColor Red
        return
    }
    
    Write-Host "Creating bucket '$bucketName'..." -ForegroundColor Yellow
    Write-Host "[AWS CLI] aws s3api create-bucket --bucket $bucketName" -ForegroundColor Magenta
    
    $result = aws s3api create-bucket --bucket $bucketName 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Bucket created successfully" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to create bucket" -ForegroundColor Red
        Write-Host $result
    }
}

# Delete an S3 bucket
function Delete-S3Bucket {
    param([string]$BucketName)
    
    # If no bucket name provided, list buckets for selection
    if ([string]::IsNullOrWhiteSpace($BucketName)) {
        Write-Host "Available buckets:" -ForegroundColor Yellow
        
        $jsonOutput = aws s3api list-buckets --output json
        $bucketsData = $jsonOutput | ConvertFrom-Json
        
        if (-not $bucketsData.Buckets -or $bucketsData.Buckets.Count -eq 0) {
            Write-Host "No buckets found" -ForegroundColor Red
            return
        }
        
        Write-Host ""
        for ($i = 0; $i -lt $bucketsData.Buckets.Count; $i++) {
            Write-Host "$($i+1). $($bucketsData.Buckets[$i].Name)"
        }
        
        Write-Host ""
        $selection = Read-Host "Select bucket number to delete"
        
        if ($selection -match '^\d+$') {
            $index = [int]$selection - 1
            if ($index -ge 0 -and $index -lt $bucketsData.Buckets.Count) {
                $BucketName = $bucketsData.Buckets[$index].Name
            } else {
                Write-Host "Invalid selection" -ForegroundColor Red
                return
            }
        } else {
            Write-Host "Invalid input" -ForegroundColor Red
            return
        }
    }
    
    # Confirm deletion
    Write-Host ""
    Write-Host "WARNING: This action cannot be undone!" -ForegroundColor Red
    $confirm = Read-Host "Are you sure you want to delete bucket '$BucketName'? (y/N)"
    
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "Operation cancelled" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Deleting bucket '$BucketName'..." -ForegroundColor Yellow
    
    # Try to empty the bucket first
    Write-Host "[AWS CLI] aws s3 rm s3://$BucketName --recursive" -ForegroundColor Magenta
    aws s3 rm "s3://$BucketName" --recursive 2>&1 | Out-Null
    
    # Delete the bucket
    Write-Host "[AWS CLI] aws s3api delete-bucket --bucket $BucketName" -ForegroundColor Magenta
    aws s3api delete-bucket --bucket $BucketName 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Bucket deleted successfully" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to delete bucket" -ForegroundColor Red
    }
}

# Download file from S3
function Get-S3File {
    param(
        [Parameter(Mandatory=$false)]
        [string]$BucketName,
        
        [Parameter(Mandatory=$false)]
        [string]$FileName
    )

    if ([string]::IsNullOrWhiteSpace($BucketName) -or [string]::IsNullOrWhiteSpace($FileName)) {
        Write-Host "Usage: .\s3_manager.ps1 download <bucket> <file>" -ForegroundColor Yellow
        return
    }

    # Verify bucket exists
    Write-Host "[AWS CLI] aws s3api head-bucket --bucket $BucketName" -ForegroundColor Magenta
    $null = aws s3api head-bucket --bucket $BucketName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Bucket '$BucketName' not found or access denied" -ForegroundColor Red
        return
    }

    # Default path and ask user
    $defaultPath = Join-Path $env:USERPROFILE "Downloads\$FileName"
    Write-Host "Default destination: $defaultPath" -ForegroundColor Blue
    $custom = Read-Host "Change destination? (y/N)"
    
    if ($custom -match '^[Yy]$') {
        $downloadPath = Read-Host "Enter full path for destination file"
        if ([string]::IsNullOrWhiteSpace($downloadPath)) {
            $downloadPath = $defaultPath
        }
    } else {
        $downloadPath = $defaultPath
    }

    Write-Host "Downloading '$FileName' from '$BucketName'..." -ForegroundColor Yellow
    Write-Host "[AWS CLI] aws s3 cp s3://$BucketName/$FileName $downloadPath" -ForegroundColor Magenta
    aws s3 cp "s3://$BucketName/$FileName" $downloadPath

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Download completed" -ForegroundColor Green
        Write-Host "Destination: $downloadPath"
    } else {
        Write-Host "✗ Failed to download file" -ForegroundColor Red
    }
}

# Upload file or folder to S3
function Add-S3Files {
    param(
        [string]$Path,
        [string]$BucketName
    )
    
    # Check if path was provided
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Host "Usage: .\s3_manager.ps1 upload <path> [bucket]" -ForegroundColor Yellow
        return
    }
    
    # Check if path exists
    if (-not (Test-Path $Path)) {
        Write-Host "Error: Path '$Path' not found" -ForegroundColor Red
        return
    }
    
    # If no bucket name provided, list buckets for selection
    if ([string]::IsNullOrWhiteSpace($BucketName)) {
        Write-Host "Available buckets:" -ForegroundColor Yellow
        
        Write-Host "[AWS CLI] aws s3api list-buckets --output json" -ForegroundColor Magenta
        $jsonOutput = aws s3api list-buckets --output json
        $bucketsData = $jsonOutput | ConvertFrom-Json
        
        if (-not $bucketsData.Buckets -or $bucketsData.Buckets.Count -eq 0) {
            Write-Host "No buckets found" -ForegroundColor Red
            return
        }
        
        Write-Host ""
        for ($i = 0; $i -lt $bucketsData.Buckets.Count; $i++) {
            Write-Host "$($i+1). $($bucketsData.Buckets[$i].Name)"
        }
        
        Write-Host ""
        $selection = Read-Host "Select bucket number for upload"
        
        if ($selection -match '^\d+$') {
            $index = [int]$selection - 1
            if ($index -ge 0 -and $index -lt $bucketsData.Buckets.Count) {
                $BucketName = $bucketsData.Buckets[$index].Name
            } else {
                Write-Host "Invalid selection" -ForegroundColor Red
                return
            }
        } else {
            Write-Host "Invalid input" -ForegroundColor Red
            return
        }
    }
    
    # Verify bucket exists
    Write-Host "[AWS CLI] aws s3api head-bucket --bucket $BucketName" -ForegroundColor Magenta
    $null = aws s3api head-bucket --bucket $BucketName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Bucket '$BucketName' not found or access denied" -ForegroundColor Red
        return
    }
    
    # Check if path is a file or directory
    $item = Get-Item $Path
    
    if ($item.PSIsContainer) {
        # It's a directory - use sync
        Write-Host "Uploading folder '$Path' to bucket '$BucketName'..." -ForegroundColor Yellow
        Write-Host "[AWS CLI] aws s3 sync $Path s3://$BucketName/ --no-progress" -ForegroundColor Magenta
        aws s3 sync $Path "s3://$BucketName/" --no-progress
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Folder uploaded successfully" -ForegroundColor Green
        } else {
            Write-Host "✗ Failed to upload folder" -ForegroundColor Red
        }
    } else {
        # It's a file - use cp
        $fileName = $item.Name
        Write-Host "Uploading file '$fileName' to bucket '$BucketName'..." -ForegroundColor Yellow
        Write-Host "[AWS CLI] aws s3 cp $Path s3://$BucketName/$fileName" -ForegroundColor Magenta
        aws s3 cp $Path "s3://$BucketName/$fileName"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ File uploaded successfully" -ForegroundColor Green
        } else {
            Write-Host "✗ Failed to upload file" -ForegroundColor Red
        }
    }
}

# Dump bucket to zip
function Export-S3Bucket {
    param([string]$BucketName)
    
    # If no bucket name provided, list buckets for selection
    if ([string]::IsNullOrWhiteSpace($BucketName)) {
        Write-Host "Available buckets:" -ForegroundColor Yellow
        
        Write-Host "[AWS CLI] aws s3api list-buckets --output json" -ForegroundColor Magenta
        $jsonOutput = aws s3api list-buckets --output json
        $bucketsData = $jsonOutput | ConvertFrom-Json
        
        if (-not $bucketsData.Buckets -or $bucketsData.Buckets.Count -eq 0) {
            Write-Host "No buckets found" -ForegroundColor Red
            return
        }
        
        Write-Host ""
        for ($i = 0; $i -lt $bucketsData.Buckets.Count; $i++) {
            Write-Host "$($i+1). $($bucketsData.Buckets[$i].Name)"
        }
        
        Write-Host ""
        $selection = Read-Host "Select bucket number to dump"
        
        if ($selection -match '^\d+$') {
            $index = [int]$selection - 1
            if ($index -ge 0 -and $index -lt $bucketsData.Buckets.Count) {
                $BucketName = $bucketsData.Buckets[$index].Name
            } else {
                Write-Host "Invalid selection" -ForegroundColor Red
                return
            }
        } else {
            Write-Host "Invalid input" -ForegroundColor Red
            return
        }
    }
    
    # Verify bucket exists
    Write-Host "[AWS CLI] aws s3api head-bucket --bucket $BucketName" -ForegroundColor Magenta
    $null = aws s3api head-bucket --bucket $BucketName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Bucket '$BucketName' not found or access denied" -ForegroundColor Red
        return
    }
    
    # Zip file name
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $zipFilename = "${BucketName}_${timestamp}.zip"
    $defaultZipPath = Join-Path $env:USERPROFILE "Downloads\$zipFilename"
    
    Write-Host ""
    Write-Host "Default destination: $defaultZipPath" -ForegroundColor Blue
    $custom = Read-Host "Change destination? (y/N)"
    
    if ($custom -match '^[Yy]$') {
        $zipPath = Read-Host "Enter full path for zip file"
        if ([string]::IsNullOrWhiteSpace($zipPath)) {
            $zipPath = $defaultZipPath
        }
    } else {
        $zipPath = $defaultZipPath
    }
    
    # Create temporary directory
    $tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ([System.Guid]::NewGuid()))
    
    Write-Host ""
    Write-Host "Downloading files from bucket..." -ForegroundColor Yellow
    Write-Host "[AWS CLI] aws s3 sync s3://$BucketName $($tempDir.FullName) --no-progress" -ForegroundColor Magenta
    
    # Use aws s3 sync with error handling
    $syncOutput = aws s3 sync "s3://$BucketName" $tempDir.FullName --no-progress 2>&1
    
    # Check if directory has any files (sync may partially succeed)
    $downloadedFiles = Get-ChildItem -Path $tempDir.FullName -Recurse -File -ErrorAction SilentlyContinue
    
    if ($downloadedFiles -and $downloadedFiles.Count -gt 0) {
        Write-Host "✓ Files downloaded ($($downloadedFiles.Count) file(s))" -ForegroundColor Green
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
    } else {
        Write-Host "✗ Failed to download files from bucket" -ForegroundColor Red
    }
    
    # Remove temporary directory
    Remove-Item -Path $tempDir.FullName -Recurse -Force
    Write-Host ""
    Write-Host "Dump completed!" -ForegroundColor Green
}

# -----------------------
# Main
# -----------------------
if ([string]::IsNullOrWhiteSpace($Command)) {
    Show-Usage
    exit 0
}

if (-not (Test-AwsCli)) { exit 1 }
if (-not (Test-AwsCredentials)) { exit 1 }

switch ($Command) {
    'list' {
        Get-S3Buckets
    }
    'create' {
        if ($Arguments.Count -ge 1) {
            New-S3Bucket -BucketName $Arguments[0]
        } else {
            New-S3Bucket
        }
    }
    'delete' {
        if ($Arguments.Count -ge 1) {
            Delete-S3Bucket -BucketName $Arguments[0]
        } else {
            Delete-S3Bucket
        }
    }
    'upload' {
        if ($Arguments.Count -ge 2) {
            Add-S3Files -Path $Arguments[0] -BucketName $Arguments[1]
        } elseif ($Arguments.Count -ge 1) {
            Add-S3Files -Path $Arguments[0]
        } else {
            Write-Host "Usage: .\s3_manager.ps1 upload <path> [bucket]" -ForegroundColor Yellow
        }
    }
    'download' { 
        if ($Arguments.Count -ge 2) {
            Get-S3File -BucketName $Arguments[0] -FileName $Arguments[1]
        } else {
            Write-Host "Usage: .\s3_manager.ps1 download <bucket> <file>" -ForegroundColor Yellow
        }
    }
    'dump' {
        if ($Arguments.Count -ge 1) {
            Export-S3Bucket -BucketName $Arguments[0]
        } else {
            Export-S3Bucket
        }
    }
    'help' {
        Show-Usage
    }
    default {
        Show-Usage
        exit 1
    }
}
