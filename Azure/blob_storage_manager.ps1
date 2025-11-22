function Show-Usage {
    Write-Host "==============================================" -ForegroundColor Blue
    Write-Host "Azure Blob Storage Manager - NimbusDFIR" -ForegroundColor Green
    Write-Host "==============================================" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Usage: .\\blob_storage_manager.ps1 [COMMAND] [OPTIONS]"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  list [account]         List all blob containers or containers in a storage account"
    Write-Host "  create                 Create a new blob container"
    Write-Host "  delete [container]     Delete a blob container"
    Write-Host "  upload <file/folder> <container>   Upload file(s) or all files in a folder to a container"
    Write-Host "  download <container> <blob>        Download a blob from a container"
    Write-Host "  dump <container>       Download all blobs from a container as a zip"
    Write-Host "  info <container>       Show information about a container"
    Write-Host "  help                   Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\\blob_storage_manager.ps1 list"
    Write-Host "  .\\blob_storage_manager.ps1 list mystorageaccount"
    Write-Host "  .\\blob_storage_manager.ps1 create"
    Write-Host "  .\\blob_storage_manager.ps1 delete mycontainer"
    Write-Host "  .\\blob_storage_manager.ps1 upload C:\\data\\file.txt mycontainer"
    Write-Host "  .\\blob_storage_manager.ps1 upload C:\\data mycontainer"
    Write-Host "  .\\blob_storage_manager.ps1 download mycontainer file.txt"
    Write-Host "  .\\blob_storage_manager.ps1 dump mycontainer"
    Write-Host "  .\\blob_storage_manager.ps1 info mycontainer"
    Write-Host ""
}
# ================================================================
# Argument Handling (fix for positional parameter errors)
# ================================================================
if ($args.Count -eq 0) {
    $Command = ""
    $args = @()
}
else {
    $Command = $args[0]
    if ($args.Count -gt 1) {
        $args = $args[1..($args.Count-1)]
    } else {
        $args = @()
    }
}

# Colors
$ColorGreen = 'Green'
$ColorYellow = 'Yellow'
$ColorRed = 'Red'
$ColorBlue = 'Blue'
$ColorCyan = 'Cyan'

function Show-Banner {
    Write-Host "==============================================" -ForegroundColor Blue
    Write-Host "          Azure Blob Storage Manager          " -ForegroundColor Green
    Write-Host "==============================================" -ForegroundColor Blue
}

function Get-AllStorageAccounts {
    return az storage account list --query "[].name" -o tsv
}

function List-BlobContainers {
    param([string]$Account)
    Write-Host "Fetching containers for account: $Account..." -ForegroundColor Yellow

    $containers = az storage container list --account-name $Account --auth-mode login --query "[].name" -o tsv
    
    if (-not $containers) {
        Write-Host "No containers found in $Account." -ForegroundColor Red
        return
    }

    $i = 1
    foreach ($c in $containers) {
        Write-Host ("{0,-3} {1,-30}" -f $i, $c)
        $i++
    }
}

function Create-BlobContainer {
    $accounts = Get-AllStorageAccounts
    if (-not $accounts) {
        Write-Host "No storage accounts found." -ForegroundColor Red
        return
    }

    Write-Host "Storage Accounts:" -ForegroundColor Cyan
    $i = 1
    foreach ($a in $accounts) {
        Write-Host "  $i) $a"
        $i++
    }

    $choice = Read-Host "Choose account number"
    $idx = [int]$choice - 1
    $account = $accounts[$idx]

    $name = Read-Host "Container name"
    az storage container create --name $name --account-name $account --auth-mode login | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Container '$name' created." -ForegroundColor Green
    }
}

function Delete-BlobContainer {
    param([string]$Container)

    $accounts = Get-AllStorageAccounts
    $all = @()

    foreach ($acc in $accounts) {
        $containers = az storage container list --account-name $acc --auth-mode login --query "[].name" -o tsv
        foreach ($c in $containers) {
            $all += [PSCustomObject]@{ Name = $c; Account = $acc }
        }
    }

    if (-not $all) {
        Write-Host "No containers found." -ForegroundColor Red
        return
    }

    if (-not $Container) {
        Write-Host ("{0,-3} {1,-30} {2,-30}" -f "#","Container","Account")
        $i = 1
        foreach ($c in $all) {
            Write-Host ("{0,-3} {1,-30} {2,-30}" -f $i, $c.Name, $c.Account)
            $i++
        }
        $choice = Read-Host "Choose number"
        $idx = [int]$choice - 1
        $Container = $all[$idx].Name
        $Account = $all[$idx].Account
    } else {
        $obj = $all | Where-Object { $_.Name -eq $Container }
        if (-not $obj) {
            Write-Host "Container not found." -ForegroundColor Red
            return
        }
        $Account = $obj.Account
    }

    $confirm = Read-Host "Delete $Container in $Account? (y/N)"
    if ($confirm -notin @("y","Y")) { return }

    az storage container delete --name $Container --account-name $Account --auth-mode login | Out-Null
    Write-Host "Container deleted." -ForegroundColor Green
}

function Get-AllBlobContainers {
    $accounts = Get-AllStorageAccounts
    $list = @()
    foreach ($acc in $accounts) {
        $containers = az storage container list --account-name $acc --auth-mode login --query "[].name" -o tsv
        foreach ($c in $containers) {
            $list += [PSCustomObject]@{ Name = $c; Account = $acc }
        }
    }
    return $list
}

function List-AllBlobContainers {
    $containers = Get-AllBlobContainers
    if (-not $containers) {
        Write-Host "No blob containers found." -ForegroundColor Red
        return
    }
    Write-Host ("{0,-3} {1,-30} {2,-30}" -f "#","Container","Account")
    $i = 1
    foreach ($c in $containers) {
        Write-Host ("{0,-3} {1,-30} {2,-30}" -f $i, $c.Name, $c.Account)
        $i++
    }
}

# ================================================================
#UPLOAD FUNCTION — file or folder
# ================================================================
function Upload-ToBlobContainer {
    param(
        [string[]]$Items,
        [string]$Container
    )

    $containers = Get-AllBlobContainers
    $account = ($containers | Where-Object { $_.Name -eq $Container }).Account
    
    if (-not $account) {
        Write-Host "Container not found." -ForegroundColor Red
        return
    }

    foreach ($item in $Items) {

        if (-not (Test-Path $item)) {
            Write-Host "Not found: $item" -ForegroundColor Red
            continue
        }

        $obj = Get-Item $item

        # Folder
        if ($obj.PSIsContainer) {
            $files = Get-ChildItem -Path $obj.FullName -File
            foreach ($f in $files) {
                $blob = $f.Name
                Write-Host "Uploading $blob..."
                az storage blob upload `
                    --account-name $account `
                    --container-name $Container `
                    --file $f.FullName `
                    --name $blob `
                    --auth-mode login | Out-Null
                Write-Host "OK: $blob" -ForegroundColor Green
            }
        }
        else {
            # File
            $blob = Split-Path $item -Leaf
            Write-Host "Uploading $blob..."
            az storage blob upload `
                --account-name $account `
                --container-name $Container `
                --file $item `
                --name $blob `
                --auth-mode login | Out-Null
            Write-Host "OK: $blob" -ForegroundColor Green
        }
    }
}

function Download-FromBlobContainer {
    param([string]$Container, [string]$Blob)

    $containers = Get-AllBlobContainers
    $account = ($containers | Where-Object { $_.Name -eq $Container }).Account

    if (-not $account) { Write-Host "Container not found." -ForegroundColor Red; return }

    $default = "$HOME/Downloads/$Blob"
    az storage blob download --name $Blob --container-name $Container --file $default --account-name $account --auth-mode login | Out-Null

    Write-Host "Downloaded: $default" -ForegroundColor Green
}

function Dump-BlobContainer {
    param([string]$Container)

    $containers = Get-AllBlobContainers
    $account = ($containers | Where-Object { $_.Name -eq $Container }).Account
    if (-not $account) { Write-Host "Container not found." -ForegroundColor Red; return }

    $guid = [guid]::NewGuid().ToString()
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("blobdump_$guid")
    New-Item -ItemType Directory -Path $temp | Out-Null

    az storage blob download-batch --account-name $account --destination $temp --source $Container --auth-mode login | Out-Null

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $downloads = Join-Path $env:USERPROFILE 'Downloads'
    $defaultZip = Join-Path $downloads ("${Container}_$timestamp.zip")
    $zip = Read-Host "Save zip to [$defaultZip]? (ENTER to confirm or type path)"
    if ([string]::IsNullOrWhiteSpace($zip)) { $zip = $defaultZip }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($temp,$zip)

    Remove-Item $temp -Recurse -Force
    Write-Host "Dump saved: $zip" -ForegroundColor Green
}

function Info-BlobContainer {
    param([string]$Container)
    $containers = Get-AllBlobContainers
    $acc = ($containers | Where-Object { $_.Name -eq $Container }).Account

    if (-not $acc) { Write-Host "Container not found." -ForegroundColor Red; return }

    az storage container show --account-name $acc --name $Container --auth-mode login
}

# ================================================================
# MAIN SWITCH
# ================================================================
switch ($Command.ToLower()) {

    "" {
        Show-Usage
    }
    "help" {
        Show-Usage
    }

    "list" {
        Show-Banner
        if ($args.Count -ge 1) { List-BlobContainers -Account $args[0] }
        else { List-AllBlobContainers }
    }

    "create" {
        Show-Banner
        Create-BlobContainer
    }

    "delete" {
        Show-Banner
        Delete-BlobContainer -Container ($args[0] -as [string])
    }

    "upload" {
        Show-Banner

        if ($args.Count -lt 2) {
            Write-Host "Usage: upload <file/folder> <container>"
            return
        }

        $Container = $args[-1]
        $Items = $args[0..($args.Count-2)]

        Upload-ToBlobContainer -Items $Items -Container $Container
    }

    "download" {
        Show-Banner
        Download-FromBlobContainer -Container $args[0] -Blob $args[1]
    }

    "dump" {
        Show-Banner
        Dump-BlobContainer -Container $args[0]
    }

    "info" {
        Show-Banner
        Info-BlobContainer -Container $args[0]
    }

    default {
        Show-Banner
        Write-Host "Unknown command: $Command" -ForegroundColor Red
    }
}
