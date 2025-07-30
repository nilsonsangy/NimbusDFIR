# Load AWS credentials from .env file located in the root directory
$envPath = ".\.env"
if (Test-Path $envPath) {
    # Load AWS credentials from .env file and set as environment variables for this process
    Get-Content $envPath | ForEach-Object {
        if ($_ -match "^\s*([^#=]+?)\s*=\s*(.*)$") {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()

            # Skip setting AWS_SESSION_TOKEN if it's empty
            if ($key -eq "AWS_SESSION_TOKEN" -and [string]::IsNullOrWhiteSpace($value)) {
                return
            }

            [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
} else {
    Write-Host "'.env' file not found. Exiting..." -ForegroundColor Red
    exit
}




# Function to show menu and capture choice
function Show-Menu {
    Clear-Host
    Write-Host "=== AWS EC2 Incident Response Menu ===" -ForegroundColor Cyan
    Write-Host "1. Capture EC2 Instance Metadata"
    Write-Host "2. Protect EC2 Instance from Accidental Termination"
    Write-Host "3. Isolate EC2 Instance"
    Write-Host "4. Detach EC2 from Auto Scaling Group"
    Write-Host "5. Deregister EC2 from ELB"
    Write-Host "6. Snapshot EBS Volume"
    Write-Host "7. Tag EC2 Instance"
    Write-Host "0. Exit"
    return Read-Host "Enter your choice (0-7)"
}

# Function to execute each command based on user input
function Handle-Action {
    param([string]$choice)

    switch ($choice) {
        "1" {
            $ip = Read-Host "Enter the IP address of the EC2 instance"
            aws ec2 describe-instances --filters "Name=ip-address,Values=$ip"
        }
        "2" {
            $instanceId = Read-Host "Enter the EC2 instance ID"
            aws ec2 modify-instance-attribute --instance-id $instanceId --attribute disableApiTermination --value true
        }
        "3" {
            $instanceId = Read-Host "Enter the EC2 instance ID"
            $securityGroupId = Read-Host "Enter the security group ID for isolation"
            aws ec2 modify-instance-attribute --instance-id $instanceId --groups $securityGroupId
        }
        "4" {
            $instanceId = Read-Host "Enter the EC2 instance ID"
            $asgName = Read-Host "Enter the Auto Scaling group name"
            aws autoscaling detach-instances --instance-ids $instanceId --auto-scaling-group-name $asgName --should-decrement-desired-capacity
        }
        "5" {
            $instanceId = Read-Host "Enter the EC2 instance ID"
            $elbName = Read-Host "Enter the ELB name"
            aws elb deregister-instances-from-load-balancer --load-balancer-name $elbName --instances $instanceId
        }
        "6" {
            $volumeId = Read-Host "Enter the EBS volume ID (e.g., vol-xxxxx)"
            $referenceId = Read-Host "Enter a reference ID for description"
            $desc = "ResponderName-Date-$referenceId"
            aws ec2 create-snapshot --volume-id $volumeId --description $desc
        }
        "7" {
            $instanceId = Read-Host "Enter the EC2 instance ID"
            $referenceId = Read-Host "Enter a reference ID for the tag"
            aws ec2 create-tags --resources $instanceId --tags "Key=Environment,Value=Quarantine:$referenceId"
        }
        "0" {
            Write-Host "Exiting..." -ForegroundColor Yellow
            exit
        }
        default {
            Write-Host "Invalid choice. Try again." -ForegroundColor Red
        }
    }
}

# Main loop to show menu repeatedly
while ($true) {
    $userChoice = Show-Menu
    Handle-Action -choice $userChoice
    Write-Host "`nPress any key to return to menu..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
