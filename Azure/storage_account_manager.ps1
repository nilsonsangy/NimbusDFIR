
param(
    [Parameter(Position=0)] [string]$Command,
    [Parameter(Position=1)] [string]$Arg
)

<#
.SYNOPSIS
    Azure Storage Account Manager (PowerShell)
.DESCRIPTION
    Cross-platform script for managing Azure Storage Accounts interactively.
#>

# Main CLI param block must be at the top

function Show-Banner {
    Write-Host "==============================================" -ForegroundColor Blue
    Write-Host "        Azure Storage Account Manager         " -ForegroundColor Green
    Write-Host "==============================================" -ForegroundColor Blue
}

function Pause {
    Read-Host "Press ENTER to continue..."
}

function Select-FromList {
    param(
        [Parameter(Mandatory)] [string[]]$Options,
        [Parameter(Mandatory)] [string]$Default
    )
    for ($i = 0; $i -lt $Options.Count; $i++) {
        if ($Options[$i] -eq $Default) {
            Write-Host "  $($i+1)) $($Options[$i]) (default)" -ForegroundColor Blue
        } else {
            Write-Host "  $($i+1)) $($Options[$i])" -ForegroundColor Blue
        }
    }
    $choice = Read-Host "Choose an option (ENTER for default: $Default)"
    if ([string]::IsNullOrWhiteSpace($choice)) { return $Default }
    if ($choice -match '^[0-9]+$' -and $choice -ge 1 -and $choice -le $Options.Count) {
        return $Options[$choice-1]
    }
    if ($Options -contains $choice) { return $choice }
    return $Default
}

function List-StorageAccounts {
    Write-Host "Fetching Storage Accounts from all Resource Groups..." -ForegroundColor Yellow
    $accounts = az storage account list --query "[].{name:name, rg:resourceGroup}" -o tsv
    if (-not $accounts) {
        Write-Host "No Storage Accounts found." -ForegroundColor Red
        return
    }
    Write-Host "Storage Accounts found:" -ForegroundColor Green
    Write-Host "ID    Storage Account                          Resource Group"
    Write-Host "---------------------------------------------------------------"
    $lines = $accounts -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $parts = $lines[$i] -split "`t"
        if ($parts.Count -eq 2) {
            Write-Host "$($i+1)    $($parts[0])                              $($parts[1])"
        }
    }
    Write-Host
}

function Create-StorageAccount {
    Write-Host "Create new Storage Account" -ForegroundColor Green
    Write-Host "Fetching Resource Groups..." -ForegroundColor Yellow
    $rgs = az group list --query "[].name" -o tsv
    $rgList = $rgs -split "`n"
    for ($i = 0; $i -lt $rgList.Count; $i++) {
        Write-Host "  $($i+1)) $($rgList[$i])"
    }
    Write-Host "  0) Create NEW Resource Group"
    $rg_choice = Read-Host "Choose a Resource Group option"
    if ($rg_choice -eq "0") {
        $RG = Read-Host "Enter new Resource Group name"
        $RG_LOCATION = Read-Host "Location for new Resource Group (ENTER for eastus)"
        if (-not $RG_LOCATION) { $RG_LOCATION = "eastus" }
        Write-Host "Creating Resource Group..." -ForegroundColor Yellow
        az group create --name $RG --location $RG_LOCATION | Out-Null
    } else {
        $idx = [int]$rg_choice - 1
        $RG = $rgList[$idx]
        if (-not $RG) {
            Write-Host "Invalid Resource Group selection." -ForegroundColor Red
            return
        }
    }
    $SA_NAME = Read-Host "Storage Account name (lowercase, 3-24 chars)"
    if (-not $SA_NAME) {
        Write-Host "Name is required." -ForegroundColor Red
        return
    }
    $LOCATIONS = @("eastus", "centralus", "westus", "eastus2", "southcentralus")
    $SKUS = @("Standard_LRS", "Standard_GRS", "Standard_RAGRS", "Standard_ZRS", "Premium_LRS")
    $KINDS = @("StorageV2", "Storage", "BlobStorage", "FileStorage", "BlockBlobStorage")
    $LOCATION = Select-FromList -Options $LOCATIONS -Default "eastus"
    $SKU = Select-FromList -Options $SKUS -Default "Standard_LRS"
    $KIND = Select-FromList -Options $KINDS -Default "StorageV2"
    Write-Host "Creating Storage Account with Azure AD authentication enabled..." -ForegroundColor Yellow
    az storage account create --name $SA_NAME --resource-group $RG --location $LOCATION --sku $SKU --kind $KIND --allow-shared-key-access false --min-tls-version TLS1_2 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to create Storage Account." -ForegroundColor Red
        return
    }
    Write-Host "Storage Account created successfully!" -ForegroundColor Green
    Write-Host "Assigning 'Storage Blob Data Owner' role to the signed-in user..." -ForegroundColor Yellow
    $USER_ID = az ad signed-in-user show --query id -o tsv
    $SUB_ID = az account show --query id -o tsv
    az role assignment create --assignee $USER_ID --role "Storage Blob Data Owner" --scope "/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$SA_NAME" | Out-Null
    Write-Host "Role assignment completed! You now have permission to upload using --auth-mode login." -ForegroundColor Green
}

function Delete-StorageAccount {
    param([string]$Name)
    if (-not $Name) {
        List-StorageAccounts
        $choice = Read-Host "Enter the ID of the Storage Account to delete"
        $accounts = az storage account list --query "[].{name:name, rg:resourceGroup}" -o tsv
        $lines = $accounts -split "`n"
        $idx = [int]$choice - 1
        if ($idx -lt 0 -or $idx -ge $lines.Count) {
            Write-Host "Invalid selection." -ForegroundColor Red
            return
        }
        $parts = $lines[$idx] -split "`t"
        $SA_NAME = $parts[0]
        $RG = $parts[1]
    } else {
        $SA_NAME = $Name
        $RG = az storage account show --name $SA_NAME --query "resourceGroup" -o tsv
    }
    Write-Host "Are you sure you want to delete:" -ForegroundColor Red
    Write-Host "  Storage Account: $SA_NAME" -ForegroundColor Yellow
    Write-Host "  Resource Group:  $RG" -ForegroundColor Yellow
    $confirm = Read-Host "Confirm deletion? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        return
    }
    Write-Host "Deleting Storage Account..." -ForegroundColor Yellow
    az storage account delete --name $SA_NAME --resource-group $RG --yes | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Storage Account deleted successfully!" -ForegroundColor Green
    } else {
        Write-Host "Error deleting Storage Account." -ForegroundColor Red
    }
}

function Show-Help {
    Write-Host "Usage: ./storage_account_manager.ps1 [COMMAND] [OPTIONS]" -ForegroundColor Cyan
    Write-Host
    Write-Host "Commands:" -ForegroundColor Cyan
    Write-Host "  list              List all Storage Accounts"
    Write-Host "  create            Create a new Storage Account"
    Write-Host "  delete [NAME]     Delete a Storage Account (select if NAME omitted)"
    Write-Host "  help              Show this help message"
    Write-Host
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  ./storage_account_manager.ps1 list"
    Write-Host "  ./storage_account_manager.ps1 create"
    Write-Host "  ./storage_account_manager.ps1 delete my-storage-account"
}

# Main CLI

switch ($Command) {
    "list"   { Show-Banner; List-StorageAccounts }
    "create" { Show-Banner; Create-StorageAccount }
    "delete" { Show-Banner; Delete-StorageAccount -Name $Arg }
    "help"   { Show-Help }
    default  { Show-Help }
}
