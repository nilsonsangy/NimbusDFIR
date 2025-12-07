param(
    [string]$InstanceId,
    [string]$Engine,
    [string]$User,
    [string]$Password,
    [string]$Database,
    [string]$OutputPath
)

function Show-Usage {
    Write-Host "AWS RDS Dump (PowerShell)" -ForegroundColor Cyan
    Write-Host "Usage: .\\rds_dump.ps1 [-InstanceId <id>] [-Engine mysql|postgres] [-User <user>] [-Password <pass>] [-Database <db>] [-OutputPath <path>]"
    Write-Host "If InstanceId is provided, endpoint and engine will be auto-detected."
}

function Test-AwsCli {
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        throw "AWS CLI not found. Please install and configure AWS CLI."
    }
}

function Get-InstanceInfo {
    param([string]$Id)
    if (-not $Id) { return $null }
    $info = aws rds describe-db-instances --db-instance-identifier $Id --output json | ConvertFrom-Json
    if (-not $info.DBInstances) { throw "Instance not found: $Id" }
    return $info.DBInstances[0]
}

try {
    Test-AwsCli
    $endpoint = $null
    $port = $null
    if ($InstanceId) {
        $inst = Get-InstanceInfo -Id $InstanceId
        $endpoint = $inst.Endpoint.Address
        if (-not $Engine) { $Engine = $inst.Engine }
        $port = [int]$inst.Endpoint.Port
        Write-Host "[AWS CLI] aws rds describe-db-instances --db-instance-identifier $InstanceId --output json" -ForegroundColor DarkCyan
    }

    if (-not $Engine) { $Engine = Read-Host "Engine (mysql/postgres)" }
    if (-not $endpoint) { $endpoint = Read-Host "Endpoint address" }
    if (-not $User) { $User = Read-Host "Username" }
    if (-not $Password) { $Password = Read-Host "Password" }
    if (-not $Database) { $Database = Read-Host "Database name" }
    if (-not $OutputPath) {
        $Downloads = Join-Path $env:USERPROFILE 'Downloads'
        $fname = "${Database}_dump_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
        $OutputPath = Join-Path $Downloads $fname
        Write-Host "No output path specified. Using: $OutputPath" -ForegroundColor Yellow
    }

    switch ($Engine.ToLower()) {
        'mysql' {
            Write-Host "[Command] mysqldump -h $endpoint -P $port -u $User -p****** $Database > $OutputPath" -ForegroundColor DarkCyan
            $env:MYSQL_PWD = $Password
            & mysqldump -h $endpoint -P $port -u $User $Database 2>&1 | Tee-Object -FilePath $OutputPath | Out-Null
            Write-Host "Dump saved to $OutputPath" -ForegroundColor Green
        }
        'postgres' {
            Write-Host "[Command] pg_dump -h $endpoint -p $port -U $User -d $Database -Fc -f $OutputPath" -ForegroundColor DarkCyan
            $env:PGPASSWORD = $Password
            & pg_dump -h $endpoint -p $port -U $User -d $Database -f $OutputPath
            Write-Host "Dump saved to $OutputPath" -ForegroundColor Green
        }
        default { throw "Unsupported engine: $Engine (use mysql or postgres)" }
    }
} catch {
    Write-Error $_
    Show-Usage
    exit 1
}
