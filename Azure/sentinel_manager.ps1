<#
.SYNOPSIS
Azure Sentinel Lab Manager

.DESCRIPTION
Interactive PowerShell script that:
- Lists Azure Resource Groups
- Lets you select a Resource Group
- Enumerates monitorable Azure resources
- Creates Log Analytics Workspace
- Enables Microsoft Sentinel
- Installs Azure Monitor Agent (AMA)
- Creates Data Collection Rules (DCR)
- Associates DCRs with resources
- Enables Diagnostic Settings
- Prepares an Azure SOC / DFIR lab

REQUIREMENTS
- Azure CLI installed
- Logged in with: az login
- Sentinel extension:
    az extension add --name sentinel

RECOMMENDED
- Run as Administrator
#>

Clear-Host

# =========================================================
# Helper Functions
# =========================================================

function Invoke-AzCli {
    param([string]$Command)

    Write-Host "`n[Azure CLI] az $Command" -ForegroundColor Cyan

    $result = Invoke-Expression "az $Command"

    return $result
}

function Select-FromList {
    param(
        [string]$Title,
        [array]$Items,
        [string]$DisplayProperty
    )

    Write-Host ""
    Write-Host $Title -ForegroundColor Yellow

    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host "[$($i+1)] $($Items[$i].$DisplayProperty)"
    }

    do {
        $selection = Read-Host "Select option"
        $index = [int]$selection - 1
    }
    until ($index -ge 0 -and $index -lt $Items.Count)

    return $Items[$index]
}

function Read-MultiSelection {
    param(
        [array]$Items,
        [string]$DisplayProperty
    )

    Write-Host ""
    Write-Host "Select one or more options separated by comma" -ForegroundColor Yellow

    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host "[$($i+1)] $($Items[$i].$DisplayProperty)"
    }

    $inputSelections = Read-Host "Selections"

    $indexes = $inputSelections.Split(",") | ForEach-Object {
        ([int]$_.Trim()) - 1
    }

    $selected = @()

    foreach ($idx in $indexes) {
        if ($idx -ge 0 -and $idx -lt $Items.Count) {
            $selected += $Items[$idx]
        }
    }

    return $selected
}

function Ensure-DataCollectionRule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuleName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Windows", "Linux")]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$WorkspaceId,

        [Parameter(Mandatory = $true)]
        [string]$Location
    )

    $existingId = az monitor data-collection rule show `
        --resource-group $RG_NAME `
        --name $RuleName `
        --query id `
        -o tsv 2>$null

    if (-not [string]::IsNullOrWhiteSpace($existingId)) {
        return $existingId
    }

    try {
        Write-Host "Creating $Kind Data Collection Rule: $RuleName" -ForegroundColor Yellow

        $dcrBody = [ordered]@{
            location = $Location
            kind = $Kind
            properties = [ordered]@{
                destinations = [ordered]@{
                    logAnalytics = @(
                        [ordered]@{
                            name = 'law-destination'
                            workspaceResourceId = $WorkspaceId
                        }
                    )
                }
                dataFlows = @()
                dataSources = [ordered]@{}
            }
        }

        if ($Kind -eq 'Windows') {
            $dcrBody.properties.dataSources.windowsEventLogs = @(
                [ordered]@{
                    name = 'security-events'
                    streams = @('Microsoft-Event')
                    xPathQueries = @('Security!*[System[(EventID=4624 or EventID=4625)]]')
                }
            )

            $dcrBody.properties.dataFlows = @(
                [ordered]@{
                    streams = @('Microsoft-Event')
                    destinations = @('law-destination')
                    outputStream = 'Microsoft-Event'
                }
            )
        }
        else {
            $dcrBody.properties.dataSources.syslog = @(
                [ordered]@{
                    name = 'linux-security'
                    streams = @('Microsoft-Syslog')
                    facilityNames = @('auth', 'authpriv')
                    logLevels = @('Info', 'Notice', 'Warning', 'Error', 'Critical', 'Alert', 'Emergency')
                }
            )

            $dcrBody.properties.dataFlows = @(
                [ordered]@{
                    streams = @('Microsoft-Syslog')
                    destinations = @('law-destination')
                    outputStream = 'Microsoft-Syslog'
                }
            )
        }

        $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "$RuleName-$([guid]::NewGuid().ToString()).json"
        
        try {
            $dcrBody | ConvertTo-Json -Depth 12 | Set-Content -Path $tempFile -Encoding utf8
            $dcrUrl = 'https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Insights/dataCollectionRules/{2}?api-version=2023-03-11' -f $account.id, $RG_NAME, $RuleName

            Write-Host "[Azure CLI] az rest --method put --url $dcrUrl --body @$tempFile" -ForegroundColor DarkCyan

            az rest --method put --url $dcrUrl --body "@$tempFile" | Out-Null

            if ($LASTEXITCODE -ne 0) {
                throw "Failed to create data collection rule '$RuleName'"
            }
        }
        finally {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        throw
    }

    $createdId = az monitor data-collection rule show `
        --resource-group $RG_NAME `
        --name $RuleName `
        --query id `
        -o tsv

    if ([string]::IsNullOrWhiteSpace($createdId)) {
        throw "Unable to resolve data collection rule ID for '$RuleName'"
    }

    return $createdId
}

# =========================================================
# Azure Login Validation
# =========================================================

Write-Host ""
Write-Host "Checking Azure authentication..." -ForegroundColor Green

try {
    $account = az account show --output json | ConvertFrom-Json

    Write-Host ""
    Write-Host "Connected as:" -ForegroundColor Green
    Write-Host "Subscription: $($account.name)"
    Write-Host "Tenant: $($account.tenantId)"
}
catch {
    Write-Host ""
    Write-Host "You are not logged in." -ForegroundColor Red
    Write-Host "Run: az login"
    exit
}

Write-Host "Enabling Azure CLI extension auto-install..." -ForegroundColor DarkCyan
az config set extension.use_dynamic_install=yes_without_prompt extension.dynamic_install_allow_preview=true | Out-Null

Write-Host "Ensuring Azure Monitor extension is installed..." -ForegroundColor DarkCyan
$monitorExtension = az extension list --query "[?name=='monitor-control-service']" -o json | ConvertFrom-Json
if (-not $monitorExtension -or $monitorExtension.Count -eq 0) {
    az extension add --name monitor-control-service --yes --only-show-errors | Out-Null
}

# =========================================================
# Select Resource Group
# =========================================================

Write-Host ""
Write-Host "Retrieving Resource Groups..." -ForegroundColor Green

$resourceGroups = az group list `
    --query "[].{Name:name, Location:location}" `
    -o json | ConvertFrom-Json

if (-not $resourceGroups) {
    Write-Host "No Resource Groups found." -ForegroundColor Red
    exit
}

$selectedRG = Select-FromList `
    -Title "Available Resource Groups" `
    -Items $resourceGroups `
    -DisplayProperty "Name"

$RG_NAME = $selectedRG.Name
$LOCATION = $selectedRG.Location

Write-Host ""
Write-Host "Selected RG: $RG_NAME" -ForegroundColor Green

# =========================================================
# Create / Reuse Log Analytics Workspace
# =========================================================

$workspaceName = "law-$RG_NAME"

Write-Host ""
Write-Host "Checking Log Analytics Workspace..." -ForegroundColor Green

$workspaceExists = az monitor log-analytics workspace list `
    --resource-group $RG_NAME `
    --query "[?name=='$workspaceName']" `
    -o json | ConvertFrom-Json

if (-not $workspaceExists) {

    Write-Host ""
    Write-Host "Creating Log Analytics Workspace..." -ForegroundColor Yellow

    az monitor log-analytics workspace create `
        --resource-group $RG_NAME `
        --workspace-name $workspaceName `
        --location $LOCATION | Out-Null
}
else {
    Write-Host "Workspace already exists." -ForegroundColor Yellow
}

# =========================================================
# Enable Sentinel
# =========================================================

Write-Host ""
Write-Host "Enabling Microsoft Sentinel..." -ForegroundColor Green

$onboardingStateName = "default"
$existingOnboardingState = az sentinel onboarding-state show `
    --resource-group $RG_NAME `
    --workspace-name $workspaceName `
    --name $onboardingStateName `
    -o json 2>$null | ConvertFrom-Json

if ($existingOnboardingState) {
    Write-Host "Sentinel already enabled." -ForegroundColor Yellow
}
else {
    az sentinel onboarding-state create `
        --resource-group $RG_NAME `
        --workspace-name $workspaceName `
        --name $onboardingStateName `
        --customer-managed-key false | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Sentinel enabled successfully." -ForegroundColor Green
    }
    else {
        Write-Host "ERROR: Failed to enable Microsoft Sentinel" -ForegroundColor Red
        exit 1
    }
}

# =========================================================
# Enumerate Resources
# =========================================================

Write-Host ""
Write-Host "Enumerating monitorable resources..." -ForegroundColor Green

$vms = az vm list `
    --resource-group $RG_NAME `
    -o json | ConvertFrom-Json

$nsgs = az network nsg list `
    --resource-group $RG_NAME `
    -o json | ConvertFrom-Json

$storageAccounts = az storage account list `
    --resource-group $RG_NAME `
    -o json | ConvertFrom-Json

# =========================================================
# Monitoring Options
# =========================================================

$monitoringOptions = @()

foreach ($vm in $vms) {
    $monitoringOptions += [PSCustomObject]@{
        Type = "VM"
        Name = $vm.name
        ResourceId = $vm.id
        OsType = $vm.storageProfile.osDisk.osType
    }
}

foreach ($nsg in $nsgs) {
    $monitoringOptions += [PSCustomObject]@{
        Type = "NSG"
        Name = $nsg.name
        ResourceId = $nsg.id
        OsType = ""
    }
}

foreach ($sa in $storageAccounts) {
    $monitoringOptions += [PSCustomObject]@{
        Type = "Storage"
        Name = $sa.name
        ResourceId = $sa.id
        OsType = ""
    }
}

if (-not $monitoringOptions) {
    Write-Host "No supported resources found." -ForegroundColor Red
    exit
}

$selectedResources = Read-MultiSelection `
    -Items $monitoringOptions `
    -DisplayProperty "Name"

# =========================================================
# Create DCRs
# =========================================================

Write-Host ""
Write-Host "Creating Data Collection Rules..." -ForegroundColor Green

$dcrWindows = "dcr-windows-security"
$dcrLinux = "dcr-linux-security"

$workspaceInfo = az monitor log-analytics workspace show `
    --resource-group $RG_NAME `
    --workspace-name $workspaceName `
    --query '{id:id, location:location}' `
    -o json | ConvertFrom-Json

$dcrWindowsId = Ensure-DataCollectionRule -RuleName $dcrWindows -Kind "Windows" -WorkspaceId $workspaceInfo.id -Location $workspaceInfo.location
$dcrLinuxId = Ensure-DataCollectionRule -RuleName $dcrLinux -Kind "Linux" -WorkspaceId $workspaceInfo.id -Location $workspaceInfo.location

# =========================================================
# Configure Monitoring
# =========================================================

foreach ($resource in $selectedResources) {

    Write-Host ""
    Write-Host "Configuring monitoring for $($resource.Name)" -ForegroundColor Cyan

    # =====================================================
    # VM Monitoring
    # =====================================================

    if ($resource.Type -eq "VM") {

        if ($resource.OsType -eq "Windows") {

            Write-Host "Installing Azure Monitor Agent (Windows)..." -ForegroundColor Yellow

            az vm extension set `
                --publisher Microsoft.Azure.Monitor `
                --name AzureMonitorWindowsAgent `
                --resource-group $RG_NAME `
                --vm-name $resource.Name | Out-Null

            Write-Host "Associating Windows DCR..." -ForegroundColor Yellow

            az monitor data-collection rule association create `
                --name "assoc-$($resource.Name)" `
                --rule-id $dcrWindowsId `
                --resource $resource.ResourceId | Out-Null
        }

        else {

            Write-Host "Installing Azure Monitor Agent (Linux)..." -ForegroundColor Yellow

            az vm extension set `
                --publisher Microsoft.Azure.Monitor `
                --name AzureMonitorLinuxAgent `
                --resource-group $RG_NAME `
                --vm-name $resource.Name | Out-Null

            Write-Host "Associating Linux DCR..." -ForegroundColor Yellow

            az monitor data-collection rule association create `
                --name "assoc-$($resource.Name)" `
                --rule-id $dcrLinuxId `
                --resource $resource.ResourceId | Out-Null
        }
    }

    # =====================================================
    # NSG Monitoring
    # =====================================================

    elseif ($resource.Type -eq "NSG") {

        Write-Host "Enabling NSG Diagnostic Settings..." -ForegroundColor Yellow

        $workspaceId = az monitor log-analytics workspace show `
            --resource-group $RG_NAME `
            --workspace-name $workspaceName `
            --query id `
            -o tsv

        az monitor diagnostic-settings create `
            --name "diag-$($resource.Name)" `
            --resource $resource.ResourceId `
            --workspace $workspaceId `
            --logs '[{"category":"NetworkSecurityGroupEvent","enabled":true},{"category":"NetworkSecurityGroupRuleCounter","enabled":true}]' | Out-Null
    }

    # =====================================================
    # Storage Monitoring
    # =====================================================

    elseif ($resource.Type -eq "Storage") {

        Write-Host "Enabling Storage Diagnostic Settings..." -ForegroundColor Yellow

        $workspaceId = az monitor log-analytics workspace show `
            --resource-group $RG_NAME `
            --workspace-name $workspaceName `
            --query id `
            -o tsv

        az monitor diagnostic-settings create `
            --name "diag-$($resource.Name)" `
            --resource $resource.ResourceId `
            --workspace $workspaceId `
            --logs '[{"category":"StorageRead","enabled":true},{"category":"StorageWrite","enabled":true},{"category":"StorageDelete","enabled":true}]' | Out-Null
    }
}

# =========================================================
# Enable Azure Activity Logs
# =========================================================

Write-Host ""
Write-Host "Enable subscription Activity Logs? (y/n)" -ForegroundColor Yellow

$enableActivity = Read-Host

if ($enableActivity -eq "y") {

    $subscriptionId = az account show `
        --query id `
        -o tsv

    $workspaceId = az monitor log-analytics workspace show `
        --resource-group $RG_NAME `
        --workspace-name $workspaceName `
        --query id `
        -o tsv

    az monitor diagnostic-settings create `
        --name "subscription-activitylogs" `
        --resource "/subscriptions/$subscriptionId" `
        --workspace $workspaceId `
        --logs '[{"category":"Administrative","enabled":true},{"category":"Security","enabled":true},{"category":"Policy","enabled":true}]' | Out-Null

    Write-Host "Activity Logs enabled." -ForegroundColor Green
}

# =========================================================
# Final Output
# =========================================================

Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host " SENTINEL LAB CONFIGURATION COMPLETE"
Write-Host "====================================================" -ForegroundColor Green

Write-Host ""
Write-Host "Workspace: $workspaceName"
Write-Host "Resource Group: $RG_NAME"

Write-Host ""
Write-Host "You can now access:"
Write-Host "Microsoft Sentinel"
Write-Host "Log Analytics"
Write-Host "Analytics Rules"
Write-Host "Incidents"
Write-Host "Threat Hunting"

Write-Host ""
Write-Host "Useful KQL Queries:"
Write-Host ""

Write-Host "Failed Windows Logins:"
Write-Host @"
SecurityEvent
| where EventID == 4625
| take 20
"@

Write-Host ""
Write-Host "Successful Windows Logins:"
Write-Host @"
SecurityEvent
| where EventID == 4624
| take 20
"@

Write-Host ""
Write-Host "Linux SSH Failures:"
Write-Host @"
Syslog
| where SyslogMessage contains "Failed password"
"@

Write-Host ""
Write-Host "Azure Activity Logs:"
Write-Host @"
AzureActivity
| take 20
"@

Write-Host ""
Write-Host "Done."