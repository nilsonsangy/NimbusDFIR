param(
    [string]$InstanceId,
    [string]$Engine,
    [string]$User,
    [string]$Password,
    [string]$Database,
    [int]$Port
)

function Show-Usage {
    Write-Host "AWS RDS Connect (PowerShell)" -ForegroundColor Cyan
    Write-Host "Usage: .\\rds_connect.ps1 [-InstanceId <id>] [-Engine mysql|postgres] [-User <user>] [-Password <pass>] [-Database <db>] [-Port <port>]"
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
    if ($InstanceId) {
        $inst = Get-InstanceInfo -Id $InstanceId
        $endpoint = $inst.Endpoint.Address
        if (-not $Engine) { $Engine = $inst.Engine }
        if (-not $Port) { $Port = [int]$inst.Endpoint.Port }
        Write-Host "[AWS CLI] aws rds describe-db-instances --db-instance-identifier $InstanceId --output json" -ForegroundColor DarkCyan
    }

    if (-not $Engine) { $Engine = Read-Host "Engine (mysql/postgres)" }
    if (-not $endpoint) { $endpoint = Read-Host "Endpoint address" }
    if (-not $Port) { $Port = [int](Read-Host "Port (e.g., 3306/5432)") }
    if (-not $User) { $User = Read-Host "Username" }
    if (-not $Password) { $Password = Read-Host "Password" }
    if (-not $Database) { $Database = Read-Host "Database name" }

    switch ($Engine.ToLower()) {
        'mysql' {
            Write-Host "[Command] mysql -h $endpoint -P $Port -u $User -p****** $Database" -ForegroundColor DarkCyan
            $env:MYSQL_PWD = $Password
            & mysql -h $endpoint -P $Port -u $User $Database
        }
        'postgres' {
            $connStrMasked = "postgresql://{0}:{1}@{2}:{3}/{4}" -f $User, '******', $endpoint, $Port, $Database
            Write-Host "[Command] psql \"$connStrMasked\"" -ForegroundColor DarkCyan
            $env:PGPASSWORD = $Password
            $connStr = "postgresql://{0}:{1}@{2}:{3}/{4}" -f $User, $Password, $endpoint, $Port, $Database
            & psql $connStr
        }
        default { throw "Unsupported engine: $Engine (use mysql or postgres)" }
    }
} catch {
    Write-Error $_
    Show-Usage
    exit 1
}
