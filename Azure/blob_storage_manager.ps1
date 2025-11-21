<#
.SYNOPSIS
    Azure Blob Storage Manager (PowerShell)
.DESCRIPTION
    Manages Azure containers and blobs interactively.
#>

function Show-Banner {
    Write-Host "==============================================" -ForegroundColor Blue
    Write-Host "          Azure Blob Storage Manager          " -ForegroundColor Green
    Write-Host "==============================================" -ForegroundColor Blue
}

function Get-AllBlobContainers {
    $accounts = az storage account list --query "[].name" -o tsv
    $result = @()
    foreach ($account in $accounts) {
        $containers = az storage container list --account-name $account --auth-mode login --query "[].name" -o tsv
        foreach ($c in $containers) {
            if ($c) { $result += [PSCustomObject]@{ Name = $c; Account = $account } }
        }
    }
    return $result
}

function List-AllBlobContainers {
    $containers = Get-AllBlobContainers
    if (-not $containers) {
        Write-Host "No Blob Containers found in any Storage Account." -ForegroundColor Red
        return
    }
    Write-Host ("{0,-3} {1,-30} {2,-30}" -f '#', 'Container', 'Account')
    $i = 1
    foreach ($c in $containers) {
        Write-Host ("{0,-3} {1,-30} {2,-30}" -f $i, $c.Name, $c.Account)
        $i++
    }
}

function Upload-ToBlobContainer {
    param([string[]]$Files, [string]$Container)
    $containers = Get-AllBlobContainers
    $account = ($containers | Where-Object { $_.Name -eq $Container }).Account
    if (-not $account) {
        Write-Host "Blob Container '$Container' not found." -ForegroundColor Red
        return
    }
    foreach ($file in $Files) {
        if (-not (Test-Path $file)) {
            Write-Host "File not found: $file" -ForegroundColor Red
            continue
        }
        $blob = Split-Path $file -Leaf
        Write-Host "Uploading $file as blob '$blob' to container '$Container' in account '$account'..."
        az storage blob upload --account-name $account --container-name $Container --file $file --name $blob --auth-mode login | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Upload complete: $blob" -ForegroundColor Green
        } else {
            Write-Host "Upload failed for $file" -ForegroundColor Red
        }
    }
}

function Download-FromBlobContainer {
    param([string]$Container, [string]$Blob)
    $containers = Get-AllBlobContainers
    $account = ($containers | Where-Object { $_.Name -eq $Container }).Account
    if (-not $account) {
        Write-Host "Blob Container '$Container' not found." -ForegroundColor Red
        return
    }
    $blobs = az storage blob list --account-name $account --container-name $Container --query '[].name' -o tsv --auth-mode login
    if (-not $blobs) {
        Write-Host "No blobs found." -ForegroundColor Red
        return
    }
    if (-not $Blob) {
        Write-Host "Available blobs:"
        $i = 1
        foreach ($b in $blobs) { Write-Host "  $i) $b"; $i++ }
        $sel = Read-Host "Choose blob (ENTER = all)"
        if (-not $sel) {
            foreach ($b in $blobs) {
                $default = "$HOME/Downloads/$b"
                $save = Read-Host "Download '$b' to $default? (ENTER to confirmar, ou digite caminho)"
                if (-not $save) { $save = $default }
                az storage blob download --account-name $account --container-name $Container --name $b --file $save --auth-mode login | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Download complete: $save" -ForegroundColor Green
                } else {
                    Write-Host "Download failed for $b" -ForegroundColor Red
                }
            }
            return
        }
        $idx = [int]$sel - 1
        $Blob = $blobs[$idx]
    }
    $default = "$HOME/Downloads/$Blob"
    $save = Read-Host "Download '$Blob' to $default? (ENTER to confirmar, ou digite caminho)"
    if (-not $save) { $save = $default }
    az storage blob download --account-name $account --container-name $Container --name $Blob --file $save --auth-mode login | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Download complete: $save" -ForegroundColor Green
    } else {
        Write-Host "Download failed for $Blob" -ForegroundColor Red
    }
}

function Dump-BlobContainer {
    param([string]$Container)
    $containers = Get-AllBlobContainers
    $account = ($containers | Where-Object { $_.Name -eq $Container }).Account
    if (-not $account) {
        Write-Host "Blob Container '$Container' not found." -ForegroundColor Red
        return
    }
    $temp = New-TemporaryFile | Split-Path
    Remove-Item $temp
    New-Item -ItemType Directory -Path $temp | Out-Null
    Write-Host "Downloading all blobs from container '$Container'..."
    az storage blob download-batch --account-name $account --destination $temp --source $Container --auth-mode login | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error downloading blobs." -ForegroundColor Red
        Remove-Item -Recurse -Force $temp
        return
    }
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $zip = "$HOME/Downloads/${Container}_$timestamp.zip"
    $zip_path = Read-Host "Save zip to $zip? (ENTER to confirm, or type path)"
    if (-not $zip_path) { $zip_path = $zip }
    Write-Host "Zipping files to $zip_path..."
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($temp, $zip_path)
    if (Test-Path $zip_path) {
        Write-Host "Dump complete: $zip_path" -ForegroundColor Green
    } else {
        Write-Host "Error creating zip file." -ForegroundColor Red
    }
    Remove-Item -Recurse -Force $temp
}

function Info-BlobContainer {
    param([string]$Container)
    $containers = Get-AllBlobContainers
    $account = ($containers | Where-Object { $_.Name -eq $Container }).Account
    if (-not $account) {
        Write-Host "Blob Container '$Container' not found." -ForegroundColor Red
        return
    }
    $info = az storage container show --account-name $account --name $Container --auth-mode login
    Write-Host $info
}

param(
    [Parameter(Position=0)] [string]$Command,
    [Parameter(Position=1)] [string[]]$Args
)

switch ($Command) {
    "list"     { Show-Banner; List-AllBlobContainers }
    "upload"   { Show-Banner; Upload-ToBlobContainer -Files $Args[0..($Args.Length-2)] -Container $Args[-1] }
    "download" { Show-Banner; Download-FromBlobContainer -Container $Args[0] -Blob ($Args[1] -as [string]) }
    "dump"     { Show-Banner; Dump-BlobContainer -Container $Args[0] }
    "info"     { Show-Banner; Info-BlobContainer -Container $Args[0] }
    default    {
        Show-Banner
        Write-Host "Usage: blob_storage_manager.ps1 <command> <args>" -ForegroundColor Cyan
        Write-Host "Commands: list, upload, download, dump, info"
    }
}
