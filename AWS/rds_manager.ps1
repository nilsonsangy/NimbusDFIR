param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('list','start','stop','describe','help')]
    [string]$Command,
    [string]$InstanceId
)

function Show-Usage {
    Write-Host "AWS RDS Manager (PowerShell)" -ForegroundColor Cyan
    Write-Host "Usage: .\\rds_manager.ps1 -Command <list|start|stop|describe|help> [-InstanceId <id>]"
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\\rds_manager.ps1 -Command list"
    Write-Host "  .\\rds_manager.ps1 -Command describe -InstanceId my-db"
    Write-Host "  .\\rds_manager.ps1 -Command start -InstanceId my-db"
    Write-Host "  .\\rds_manager.ps1 -Command stop -InstanceId my-db"
}

function Test-AwsCli {
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        throw "AWS CLI not found. Please install and configure AWS CLI."
    }
}

function List-RdsInstances {
    Write-Host "[AWS CLI] aws rds describe-db-instances --query 'DBInstances[].{Id:DBInstanceIdentifier,Engine:Engine,Status:DBInstanceStatus,Endpoint:Endpoint.Address}' --output table" -ForegroundColor DarkCyan
    aws rds describe-db-instances --query "DBInstances[].{Id:DBInstanceIdentifier,Engine:Engine,Status:DBInstanceStatus,Endpoint:Endpoint.Address}" --output table
}

function Describe-RdsInstance {
    param([string]$Id)
    if (-not $Id) { throw "InstanceId is required for describe." }
    Write-Host "[AWS CLI] aws rds describe-db-instances --db-instance-identifier $Id --output json" -ForegroundColor DarkCyan
    aws rds describe-db-instances --db-instance-identifier $Id --output json | Write-Output
}

function Start-RdsInstance {
    param([string]$Id)
    if (-not $Id) { throw "InstanceId is required for start." }
    Write-Host "[AWS CLI] aws rds start-db-instance --db-instance-identifier $Id" -ForegroundColor DarkCyan
    aws rds start-db-instance --db-instance-identifier $Id | Write-Output
}

function Stop-RdsInstance {
    param([string]$Id)
    if (-not $Id) { throw "InstanceId is required for stop." }
    Write-Host "[AWS CLI] aws rds stop-db-instance --db-instance-identifier $Id" -ForegroundColor DarkCyan
    aws rds stop-db-instance --db-instance-identifier $Id | Write-Output
}

try {
    Test-AwsCli
    switch ($Command) {
        'help' { Show-Usage }
        'list' { List-RdsInstances }
        'describe' { Describe-RdsInstance -Id $InstanceId }
        'start' { Start-RdsInstance -Id $InstanceId }
        'stop' { Stop-RdsInstance -Id $InstanceId }
        default { Show-Usage }
    }
} catch {
    Write-Error $_
    Show-Usage
    exit 1
}
