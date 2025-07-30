# Investigate IAM-related security incidents in AWS CloudTrail using PowerShell and AWS CLI
# This script loads AWS credentials from a .env file and guides the user through common IAM-related CloudTrail queries

# Load AWS credentials from .env
$envPath = ".\.env"

if (-Not (Test-Path $envPath)) {
    Write-Error ".env file not found in the project root. Aborting."
    exit 1
}

# Load .env file and export variables to current process (skip empty AWS_SESSION_TOKEN)
Get-Content $envPath | ForEach-Object {
    if ($_ -match "^\s*([^#=]+?)\s*=\s*(.*)$") {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()

        if ($key -eq "AWS_SESSION_TOKEN" -and [string]::IsNullOrWhiteSpace($value)) {
            return
        }

        [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
    }
}

# Confirm credentials loaded correctly
Write-Host "Testing AWS credentials..."
try {
    $identity = aws sts get-caller-identity | ConvertFrom-Json
    Write-Host "Authenticated as: $($identity.Arn)"
} catch {
    Write-Error "AWS credentials failed to authenticate. Check your .env file."
    exit 1
}

# Ask user for region (default: us-east-1)
$region = Read-Host "Enter AWS region (default: us-east-1)"
if ([string]::IsNullOrWhiteSpace($region)) { $region = "us-east-1" }

# Ask user what they want to do
Write-Host "What do you want to investigate?"
Write-Host "1. List IAM access denied events"
Write-Host "2. Search by source IP address"
Write-Host "3. Search by Access Key ID (requires jq installed)"

$choice = Read-Host "Enter option (1/2/3)"

switch ($choice) {
    '1' {
        Write-Host "Running access denied query in CloudTrail Insights..."

        $query = "filter errorCode like /Unauthorized|Denied|Forbidden/ | fields awsRegion, userIdentity.arn, eventSource, eventName, sourceIPAddress, userAgent"
        aws cloudtrail lookup-events --region $region --lookup-attributes AttributeKey=ErrorCode,AttributeValue=UnauthorizedAccess | Out-Host

        Write-Host "You can also run this query in CloudTrail Lake with the following syntax:"
        Write-Host $query
    }
    '2' {
        $ip = Read-Host "Enter source IP address to investigate"
        $query = "filter sourceIPAddress = '$ip' | fields awsRegion, userIdentity.arn, eventSource, eventName, sourceIPAddress, userAgent"

        Write-Host "You can run this query in CloudTrail Lake:"
        Write-Host $query

        Write-Host "(Note: direct CLI support for query requires CloudTrail Lake configuration.)"
    }
    '3' {
        $accessKeyId = Read-Host "Enter the Access Key ID to search for"
        $startTime = Read-Host "Enter start time in epoch milliseconds (e.g., 1551402000000)"

        $cmd = "aws logs filter-log-events --region $region --start-time $startTime --log-group-name CloudTrail/DefaultLogGroup --filter-pattern '$accessKeyId' --output json --query 'events[*].message' | jq -r '.[] | fromjson | .userIdentity, .sourceIPAddress, .responseElements'"

        Write-Host "Executing log query..."
        Invoke-Expression $cmd
    }
    default {
        Write-Host "Invalid option. Exiting."
    }
}
