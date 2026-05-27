# AWS Connection Test Script
# Author: NimbusDFIR
# Description: Tests AWS connection and displays account information

# Check if AWS CLI is installed
$script:AwsCliPath = (Get-Command aws -CommandType Application -ErrorAction SilentlyContinue).Source
if (-not $script:AwsCliPath) {
    Write-Host "ERROR: AWS CLI is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install AWS CLI from: https://aws.amazon.com/cli/" -ForegroundColor Yellow
    exit 1
}

function aws {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    Write-Host "[AWS CLI] aws $($Arguments -join ' ')" -ForegroundColor DarkCyan
    & $script:AwsCliPath @Arguments
}

Write-Host "==========================================" -ForegroundColor Blue
Write-Host "AWS Connection Test - NimbusDFIR" -ForegroundColor Blue
Write-Host "==========================================" -ForegroundColor Blue
Write-Host ""

# Check if AWS credentials are configured
Write-Host "[INFO] Checking AWS authentication..." -ForegroundColor Blue
$identityJson = aws sts get-caller-identity --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] AWS credentials not configured or not valid" -ForegroundColor Red
    Write-Host "Please run: aws configure" -ForegroundColor Yellow
    exit 1
}

$identity = $identityJson | ConvertFrom-Json
$accountId = $identity.Account

Write-Host "[SUCCESS] AWS connection successful! Account ID: $accountId" -ForegroundColor Green
Write-Host ""

# List available regions
Write-Host "Available regions:" -ForegroundColor Cyan
Write-Host "====================" -ForegroundColor Cyan

$regionsJson = aws ec2 describe-regions --query "Regions[].RegionName" --output json 2>&1

if ($LASTEXITCODE -eq 0) {
    $regions = $regionsJson | ConvertFrom-Json
    foreach ($region in $regions) {
        Write-Host $region
    }
} else {
    Write-Host "Unable to retrieve regions. Check your AWS permissions." -ForegroundColor Yellow
}
