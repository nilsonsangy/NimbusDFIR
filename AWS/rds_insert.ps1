param(
    [string]$InstanceId,
    [string]$Engine,
    [string]$User,
    [string]$Password,
    [string]$Database,
    [string]$TableName = "mock_data",
    [int]$RowCount = 10
)

function Show-Usage {
    Write-Host "AWS RDS Insert Mock Data (PowerShell)" -ForegroundColor Cyan
    Write-Host "Usage: .\\rds_insert.ps1 [-InstanceId <id>] [-Engine mysql|postgres] [-User <user>] [-Password <pass>] [-Database <db>] [-TableName <name>] [-RowCount <n>]"
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

    switch ($Engine.ToLower()) {
        'mysql' {
            Write-Host "[Command] mysql -h $endpoint -P $port -u $User -p****** $Database" -ForegroundColor DarkCyan
            $env:MYSQL_PWD = $Password
            $sql = @"
CREATE TABLE IF NOT EXISTS $TableName (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
"@
            & mysql -h $endpoint -P $port -u $User $Database -e $sql
            for ($i=1; $i -le $RowCount; $i++) {
                $name = "Name_$i"
                & mysql -h $endpoint -P $port -u $User $Database -e "INSERT INTO $TableName (name) VALUES ('$name');"
            }
            Write-Host "Inserted $RowCount rows into $TableName" -ForegroundColor Green
        }
        'postgres' {
            $connStrMasked = "postgresql://{0}:{1}@{2}:{3}/{4}" -f $User, '******', $endpoint, $port, $Database
            Write-Host "[Command] psql \"$connStrMasked\"" -ForegroundColor DarkCyan
            $env:PGPASSWORD = $Password
            $sqlCreate = @"
CREATE TABLE IF NOT EXISTS $TableName (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
"@
            $connStr = "postgresql://{0}:{1}@{2}:{3}/{4}" -f $User, $Password, $endpoint, $port, $Database
            & psql $connStr -c $sqlCreate
            for ($i=1; $i -le $RowCount; $i++) {
                $name = "Name_$i"
                & psql $connStr -c "INSERT INTO $TableName (name) VALUES ('$name');"
            }
            Write-Host "Inserted $RowCount rows into $TableName" -ForegroundColor Green
        }
        default { throw "Unsupported engine: $Engine (use mysql or postgres)" }
    }
} catch {
    Write-Error $_
    Show-Usage
    exit 1
}
