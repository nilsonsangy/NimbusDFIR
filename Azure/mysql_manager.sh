#!/bin/bash

# Azure MySQL Manager Script
# Author: NimbusDFIR
# Description: Manage Azure Database for MySQL Flexible Servers - list, create, and delete

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed${NC}"
    echo "Please install Azure CLI first"
    echo "Run: ./install_azure_cli_macos.sh"
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo -e "${RED}Error: Not logged in to Azure${NC}"
    echo "Please run: az login"
    exit 1
fi

# Function to display usage
usage() {
    echo -e "${BLUE}=========================================="
    echo "Azure MySQL Manager - NimbusDFIR"
    echo -e "==========================================${NC}"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  list              List all MySQL flexible servers"
    echo "  create            Create a new MySQL flexible server"
    echo "  delete            Delete a MySQL flexible server"
    echo "  start             Start a stopped server"
    echo "  stop              Stop a running server"
    echo "  info              Get server information"
    echo "  help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 create"
    echo "  $0 delete my-mysql-server"
    echo "  $0 start my-mysql-server"
    echo "  $0 stop my-mysql-server"
    echo "  $0 info my-mysql-server"
    echo ""
}

# Function to list MySQL servers
list_servers() {
    echo -e "${BLUE}Listing Azure MySQL Flexible Servers...${NC}"
    echo ""
    
    SERVERS=$(az mysql flexible-server list --output json 2>/dev/null)
    
    if [ "$SERVERS" == "[]" ] || [ -z "$SERVERS" ]; then
        echo -e "${YELLOW}No MySQL flexible servers found${NC}"
        return
    fi
    
    echo -e "${CYAN}Server Name\t\t\tResource Group\t\tLocation\tSKU\t\tVersion\tState${NC}"
    echo "----------------------------------------------------------------------------------------------------------------"
    
    echo "$SERVERS" | jq -r '.[] | [.name, .resourceGroup, .location, .sku.name, .version, .state] | @tsv' | while IFS=$'\t' read -r name rg location sku version state; do
        if [[ "$state" == "Ready" ]]; then
            echo -e "${GREEN}$name\t\t$rg\t\t$location\t$sku\t$version\t$state${NC}"
        elif [[ "$state" == "Stopped" ]]; then
            echo -e "${YELLOW}$name\t\t$rg\t\t$location\t$sku\t$version\t$state${NC}"
        else
            echo -e "$name\t\t$rg\t\t$location\t$sku\t$version\t$state"
        fi
    done
}

# Function to create MySQL server
create_server() {
    echo -e "${BLUE}Create New Azure MySQL Flexible Server${NC}"
    echo ""
    
    # Get server name
    read -p "Enter server name (default: mysql-$(date +%s)): " SERVER_NAME
    SERVER_NAME=${SERVER_NAME:-mysql-$(date +%s)}
    
    # Validate server name
    if ! [[ "$SERVER_NAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]]; then
        echo -e "${RED}Error: Invalid server name${NC}"
        echo "Must contain only lowercase letters, numbers, and hyphens"
        echo "Must start and end with letter or number"
        exit 1
    fi
    
    # Select Location first
    echo ""
    echo -e "${CYAN}Select Location for MySQL Server:${NC}"
    echo "  1. westeurope       - West Europe (Netherlands) - Default"
    echo "  2. northeurope      - North Europe (Ireland)"
    echo "  3. eastus           - East US (Virginia)"
    echo "  4. westus2          - West US 2 (Washington)"
    echo "  5. southcentralus   - South Central US (Texas)"
    echo ""
    read -p "Choose location [1-5] (default: 1): " LOCATION_CHOICE
    LOCATION_CHOICE=${LOCATION_CHOICE:-1}
    
    case $LOCATION_CHOICE in
        1) LOCATION="westeurope" ;;
        2) LOCATION="northeurope" ;;
        3) LOCATION="eastus" ;;
        4) LOCATION="westus2" ;;
        5) LOCATION="southcentralus" ;;
        *) LOCATION="westeurope" ;;
    esac
    
    echo -e "${BLUE}Selected location: $LOCATION${NC}"
    
    # Get or create resource group
    echo ""
    echo -e "${CYAN}Available Resource Groups in $LOCATION:${NC}"
    RG_LIST=$(az group list --query "[?location=='$LOCATION'].{Name:name, Location:location}" -o json)
    
    if [ "$RG_LIST" != "[]" ]; then
        echo "$RG_LIST" | jq -r '.[] | "\(.Name) (\(.Location))"' | nl -w2 -s'. '
        echo ""
        read -p "Select resource group number, enter new name, or press Enter for default (default: rg-forensics): " RG_INPUT
        RG_INPUT=${RG_INPUT:-rg-forensics}
        
        # Check if input is a number
        if [[ "$RG_INPUT" =~ ^[0-9]+$ ]]; then
            RG_NAME=$(echo "$RG_LIST" | jq -r ".[$(($RG_INPUT-1))].Name" 2>/dev/null)
            if [ -z "$RG_NAME" ] || [ "$RG_NAME" == "null" ]; then
                echo -e "${RED}Error: Invalid selection${NC}"
                exit 1
            fi
        else
            RG_NAME="$RG_INPUT"
        fi
    else
        echo "  No resource groups found in $LOCATION"
        echo ""
        read -p "Enter resource group name (default: rg-forensics): " RG_NAME
        RG_NAME=${RG_NAME:-rg-forensics}
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RG_NAME" &> /dev/null; then
        echo -e "${YELLOW}Resource group '$RG_NAME' does not exist. Creating in $LOCATION...${NC}"
        az group create --name "$RG_NAME" --location "$LOCATION" --output table
        echo -e "${GREEN}✓ Resource group created${NC}"
    else
        RG_LOCATION=$(az group show --name "$RG_NAME" --query location -o tsv)
        if [ "$RG_LOCATION" != "$LOCATION" ]; then
            echo -e "${YELLOW}Warning: Resource group '$RG_NAME' exists in $RG_LOCATION, but you selected $LOCATION${NC}"
            echo -e "${YELLOW}MySQL server will be created in $LOCATION (resource group location: $RG_LOCATION)${NC}"
        else
            echo -e "${GREEN}✓ Using existing resource group in $LOCATION${NC}"
        fi
    fi
    
    # Select SKU (pricing tier)
    echo ""
    echo -e "${CYAN}Select SKU (Pricing Tier):${NC}"
    echo "  1. Standard_B1ms  - 1 vCore, 2 GB RAM, Burstable (Cheapest)"
    echo "  2. Standard_B2s   - 2 vCore, 4 GB RAM, Burstable"
    echo "  3. Standard_B2ms  - 2 vCore, 8 GB RAM, Burstable"
    echo "  4. Standard_D2ds_v4 - 2 vCore, 8 GB RAM, General Purpose"
    echo ""
    read -p "Choose SKU [1-4] (default: 1): " SKU_CHOICE
    SKU_CHOICE=${SKU_CHOICE:-1}
    
    case $SKU_CHOICE in
        1) SKU="Standard_B1ms"; TIER="Burstable" ;;
        2) SKU="Standard_B2s"; TIER="Burstable" ;;
        3) SKU="Standard_B2ms"; TIER="Burstable" ;;
        4) SKU="Standard_D2ds_v4"; TIER="GeneralPurpose" ;;
        *) SKU="Standard_B1ms"; TIER="Burstable" ;;
    esac
    
    # Select MySQL version - now we have $LOCATION defined
    echo ""
    echo -e "${YELLOW}Fetching available MySQL versions for $LOCATION...${NC}"
    
    # Get all available MySQL versions
    VERSIONS_JSON=$(az mysql flexible-server list-skus --location "$LOCATION" -o json 2>/dev/null | jq -r '[.[].supportedFlexibleServerEditions[].supportedServerVersions[].name] | unique | sort | reverse' 2>/dev/null)
    
    if [ -z "$VERSIONS_JSON" ] || [ "$VERSIONS_JSON" == "[]" ] || [ "$VERSIONS_JSON" == "null" ]; then
        echo -e "${RED}Error: Could not fetch MySQL versions for location $LOCATION${NC}"
        echo "Using default version 8.0.21"
        VERSION="8.0.21"
    else
        # Parse versions array
        VERSIONS=($(echo "$VERSIONS_JSON" | jq -r '.[]' 2>/dev/null))
        
        if [ ${#VERSIONS[@]} -eq 0 ]; then
            echo -e "${RED}Error: No versions found${NC}"
            echo "Using default version 8.0.21"
            VERSION="8.0.21"
        else
            echo -e "${CYAN}Select MySQL Version:${NC}"
            
            # Display all available versions
            DISPLAY_COUNT=${#VERSIONS[@]}
            for i in $(seq 0 $(($DISPLAY_COUNT - 1))); do
                VERSION_NUM=$((i + 1))
                if [ $i -eq 0 ]; then
                    echo "  $VERSION_NUM. ${VERSIONS[$i]} (Latest)"
                else
                    echo "  $VERSION_NUM. ${VERSIONS[$i]}"
                fi
            done
            
            echo ""
            read -p "Choose version [1-$DISPLAY_COUNT] (default: 1): " VERSION_CHOICE
            VERSION_CHOICE=${VERSION_CHOICE:-1}
            
            # Validate choice
            if [[ "$VERSION_CHOICE" =~ ^[0-9]+$ ]] && [ "$VERSION_CHOICE" -ge 1 ] && [ "$VERSION_CHOICE" -le "$DISPLAY_COUNT" ]; then
                VERSION="${VERSIONS[$((VERSION_CHOICE - 1))]}"
            else
                echo -e "${YELLOW}Invalid choice, using latest version${NC}"
                VERSION="${VERSIONS[0]}"
            fi
        fi
    fi
    
    # Get storage size
    echo ""
    read -p "Enter storage size in GB (default: 20, min: 20, max: 16384): " STORAGE_SIZE
    STORAGE_SIZE=${STORAGE_SIZE:-20}
    
    # Validate storage
    if [ "$STORAGE_SIZE" -lt 20 ]; then
        echo -e "${YELLOW}Warning: Minimum storage is 20 GB. Setting to 20 GB.${NC}"
        STORAGE_SIZE=20
    fi
    
    # Get admin username
    echo ""
    read -p "Enter admin username (default: mysqladmin): " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-mysqladmin}
    
    # Get admin password
    echo ""
    echo -e "${YELLOW}Password requirements:${NC}"
    echo "  - At least 8 characters"
    echo "  - Must contain uppercase, lowercase, and numbers"
    
    while true; do
        read -sp "Enter admin password: " ADMIN_PASSWORD
        echo ""
        
        if [ -z "$ADMIN_PASSWORD" ]; then
            echo -e "${RED}Error: Password is required${NC}"
            exit 1
        fi
        
        read -sp "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
        echo ""
        
        if [ "$ADMIN_PASSWORD" == "$ADMIN_PASSWORD_CONFIRM" ]; then
            echo -e "${GREEN}✓ Password confirmed${NC}"
            break
        else
            echo -e "${RED}Error: Passwords do not match. Please try again.${NC}"
            echo ""
        fi
    done
    
    # High availability
    echo ""
    read -p "Enable high availability? (y/N): " HA_ENABLED
    HA_ENABLED=${HA_ENABLED:-n}
    
    # Backup retention
    echo ""
    read -p "Backup retention days (default: 7, min: 1, max: 35): " BACKUP_RETENTION
    BACKUP_RETENTION=${BACKUP_RETENTION:-7}
    
    # Public access
    echo ""
    read -p "Enable public access? (y/N): " PUBLIC_ACCESS
    PUBLIC_ACCESS=${PUBLIC_ACCESS:-n}
    
    # Build command
    echo ""
    echo -e "${YELLOW}Creating MySQL flexible server... (this may take several minutes)${NC}"
    echo -e "${BLUE}[INFO]${NC} Server: $SERVER_NAME | SKU: $SKU | Version: $VERSION | Location: $LOCATION"
    echo ""
    
    CMD="az mysql flexible-server create \
        --name $SERVER_NAME \
        --resource-group $RG_NAME \
        --location $LOCATION \
        --admin-user $ADMIN_USER \
        --admin-password '$ADMIN_PASSWORD' \
        --sku-name $SKU \
        --tier $TIER \
        --version $VERSION \
        --storage-size $STORAGE_SIZE \
        --backup-retention $BACKUP_RETENTION"
    
    # Add high availability if enabled
    if [[ "$HA_ENABLED" =~ ^[Yy]$ ]]; then
        CMD="$CMD --high-availability Enabled"
    fi
    
    # Add public access if enabled
    if [[ "$PUBLIC_ACCESS" =~ ^[Yy]$ ]]; then
        CMD="$CMD --public-access All"
    else
        CMD="$CMD --public-access None"
    fi
    
    # Execute command
    eval $CMD
    
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ MySQL flexible server created successfully!${NC}"
        echo ""
        
        # Get server details
        echo -e "${CYAN}Server Details:${NC}"
        az mysql flexible-server show \
            --name "$SERVER_NAME" \
            --resource-group "$RG_NAME" \
            --query "{Name:name, ResourceGroup:resourceGroup, Location:location, Version:version, SKU:sku.name, State:state, FQDN:fullyQualifiedDomainName}" \
            -o table
        
        echo ""
        echo -e "${CYAN}Connection Information:${NC}"
        FQDN=$(az mysql flexible-server show --name "$SERVER_NAME" --resource-group "$RG_NAME" --query fullyQualifiedDomainName -o tsv)
        echo "Host: $FQDN"
        echo "Port: 3306"
        echo "Username: $ADMIN_USER"
        echo ""
        echo "Connection string:"
        echo "mysql -h $FQDN -u $ADMIN_USER -p"
        
        # Add firewall rule if public access enabled
        if [[ "$PUBLIC_ACCESS" =~ ^[Yy]$ ]]; then
            echo ""
            read -p "Add firewall rule to allow your IP? (Y/n): " ADD_FIREWALL
            if [[ ! "$ADD_FIREWALL" =~ ^[Nn]$ ]]; then
                MY_IP=$(curl -s ifconfig.me)
                echo "Adding firewall rule for IP: $MY_IP"
                az mysql flexible-server firewall-rule create \
                    --resource-group "$RG_NAME" \
                    --name "$SERVER_NAME" \
                    --rule-name AllowMyIP \
                    --start-ip-address "$MY_IP" \
                    --end-ip-address "$MY_IP"
                echo -e "${GREEN}✓ Firewall rule added${NC}"
            fi
        fi
    else
        echo -e "${RED}✗ Failed to create MySQL flexible server${NC}"
        exit 1
    fi
}

# Function to delete server
delete_server() {
    local SERVER_NAME=$1
    
    if [ -z "$SERVER_NAME" ]; then
        echo -e "${CYAN}Available MySQL Servers:${NC}"
        SERVERS=$(az mysql flexible-server list --output json 2>/dev/null)
        
        if [ "$SERVERS" == "[]" ] || [ -z "$SERVERS" ]; then
            echo -e "${YELLOW}No MySQL flexible servers found${NC}"
            exit 0
        fi
        
        echo "$SERVERS" | jq -r '.[] | "\(.name) (\(.resourceGroup) - \(.location))"' | nl -w2 -s'. '
        echo ""
        read -p "Select server number or enter name: " SERVER_INPUT
        
        if [ -z "$SERVER_INPUT" ]; then
            echo -e "${RED}Error: Server selection is required${NC}"
            exit 1
        fi
        
        # Check if input is a number
        if [[ "$SERVER_INPUT" =~ ^[0-9]+$ ]]; then
            SERVER_NAME=$(echo "$SERVERS" | jq -r ".[$(($SERVER_INPUT-1))].name" 2>/dev/null)
            if [ -z "$SERVER_NAME" ] || [ "$SERVER_NAME" == "null" ]; then
                echo -e "${RED}Error: Invalid selection${NC}"
                exit 1
            fi
        else
            SERVER_NAME="$SERVER_INPUT"
        fi
    fi
    
    # Find server and get resource group
    echo -e "${BLUE}Finding MySQL server: $SERVER_NAME${NC}"
    SERVER_INFO=$(az mysql flexible-server list --query "[?name=='$SERVER_NAME']" -o json)
    
    if [ "$SERVER_INFO" == "[]" ]; then
        echo -e "${RED}Error: MySQL server '$SERVER_NAME' not found${NC}"
        exit 1
    fi
    
    RG_NAME=$(echo "$SERVER_INFO" | jq -r '.[0].resourceGroup')
    
    echo -e "${YELLOW}Server found in resource group: $RG_NAME${NC}"
    echo ""
    echo -e "${RED}WARNING: This will permanently delete the MySQL server and all databases!${NC}"
    read -p "Are you sure you want to delete server '$SERVER_NAME'? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "Deletion cancelled"
        exit 0
    fi
    
    echo ""
    echo -e "${YELLOW}Deleting MySQL server...${NC}"
    
    az mysql flexible-server delete \
        --name "$SERVER_NAME" \
        --resource-group "$RG_NAME" \
        --yes
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ MySQL server deleted successfully${NC}"
    else
        echo -e "${RED}✗ Failed to delete MySQL server${NC}"
        exit 1
    fi
}

# Function to start server
start_server() {
    local SERVER_NAME=$1
    
    if [ -z "$SERVER_NAME" ]; then
        echo -e "${CYAN}Available MySQL Servers:${NC}"
        SERVERS=$(az mysql flexible-server list --output json 2>/dev/null)
        
        if [ "$SERVERS" == "[]" ] || [ -z "$SERVERS" ]; then
            echo -e "${YELLOW}No MySQL flexible servers found${NC}"
            exit 0
        fi
        
        echo "$SERVERS" | jq -r '.[] | "\(.name) (\(.resourceGroup) - \(.state))"' | nl -w2 -s'. '
        echo ""
        read -p "Select server number or enter name: " SERVER_INPUT
        
        if [ -z "$SERVER_INPUT" ]; then
            echo -e "${RED}Error: Server selection is required${NC}"
            exit 1
        fi
        
        # Check if input is a number
        if [[ "$SERVER_INPUT" =~ ^[0-9]+$ ]]; then
            SERVER_NAME=$(echo "$SERVERS" | jq -r ".[$(($SERVER_INPUT-1))].name" 2>/dev/null)
            if [ -z "$SERVER_NAME" ] || [ "$SERVER_NAME" == "null" ]; then
                echo -e "${RED}Error: Invalid selection${NC}"
                exit 1
            fi
        else
            SERVER_NAME="$SERVER_INPUT"
        fi
    fi
    
    # Find server and get resource group
    SERVER_INFO=$(az mysql flexible-server list --query "[?name=='$SERVER_NAME']" -o json)
    
    if [ "$SERVER_INFO" == "[]" ]; then
        echo -e "${RED}Error: MySQL server '$SERVER_NAME' not found${NC}"
        exit 1
    fi
    
    RG_NAME=$(echo "$SERVER_INFO" | jq -r '.[0].resourceGroup')
    
    echo -e "${YELLOW}Starting MySQL server: $SERVER_NAME${NC}"
    az mysql flexible-server start --name "$SERVER_NAME" --resource-group "$RG_NAME"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ MySQL server started successfully${NC}"
    else
        echo -e "${RED}✗ Failed to start MySQL server${NC}"
        exit 1
    fi
}

# Function to stop server
stop_server() {
    local SERVER_NAME=$1
    
    if [ -z "$SERVER_NAME" ]; then
        echo -e "${CYAN}Available MySQL Servers:${NC}"
        SERVERS=$(az mysql flexible-server list --output json 2>/dev/null)
        
        if [ "$SERVERS" == "[]" ] || [ -z "$SERVERS" ]; then
            echo -e "${YELLOW}No MySQL flexible servers found${NC}"
            exit 0
        fi
        
        echo "$SERVERS" | jq -r '.[] | "\(.name) (\(.resourceGroup) - \(.state))"' | nl -w2 -s'. '
        echo ""
        read -p "Select server number or enter name: " SERVER_INPUT
        
        if [ -z "$SERVER_INPUT" ]; then
            echo -e "${RED}Error: Server selection is required${NC}"
            exit 1
        fi
        
        # Check if input is a number
        if [[ "$SERVER_INPUT" =~ ^[0-9]+$ ]]; then
            SERVER_NAME=$(echo "$SERVERS" | jq -r ".[$(($SERVER_INPUT-1))].name" 2>/dev/null)
            if [ -z "$SERVER_NAME" ] || [ "$SERVER_NAME" == "null" ]; then
                echo -e "${RED}Error: Invalid selection${NC}"
                exit 1
            fi
        else
            SERVER_NAME="$SERVER_INPUT"
        fi
    fi
    
    # Find server and get resource group
    SERVER_INFO=$(az mysql flexible-server list --query "[?name=='$SERVER_NAME']" -o json)
    
    if [ "$SERVER_INFO" == "[]" ]; then
        echo -e "${RED}Error: MySQL server '$SERVER_NAME' not found${NC}"
        exit 1
    fi
    
    RG_NAME=$(echo "$SERVER_INFO" | jq -r '.[0].resourceGroup')
    
    echo -e "${YELLOW}Stopping MySQL server: $SERVER_NAME${NC}"
    az mysql flexible-server stop --name "$SERVER_NAME" --resource-group "$RG_NAME"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ MySQL server stopped successfully${NC}"
    else
        echo -e "${RED}✗ Failed to stop MySQL server${NC}"
        exit 1
    fi
}

# Function to get server info
server_info() {
    local SERVER_NAME=$1
    
    if [ -z "$SERVER_NAME" ]; then
        echo -e "${CYAN}Available MySQL Servers:${NC}"
        SERVERS=$(az mysql flexible-server list --output json 2>/dev/null)
        
        if [ "$SERVERS" == "[]" ] || [ -z "$SERVERS" ]; then
            echo -e "${YELLOW}No MySQL flexible servers found${NC}"
            exit 0
        fi
        
        echo "$SERVERS" | jq -r '.[] | "\(.name) (\(.resourceGroup) - \(.state))"' | nl -w2 -s'. '
        echo ""
        read -p "Select server number or enter name: " SERVER_INPUT
        
        if [ -z "$SERVER_INPUT" ]; then
            echo -e "${RED}Error: Server selection is required${NC}"
            exit 1
        fi
        
        # Check if input is a number
        if [[ "$SERVER_INPUT" =~ ^[0-9]+$ ]]; then
            SERVER_NAME=$(echo "$SERVERS" | jq -r ".[$(($SERVER_INPUT-1))].name" 2>/dev/null)
            if [ -z "$SERVER_NAME" ] || [ "$SERVER_NAME" == "null" ]; then
                echo -e "${RED}Error: Invalid selection${NC}"
                exit 1
            fi
        else
            SERVER_NAME="$SERVER_INPUT"
        fi
    fi
    
    # Find server and get resource group
    SERVER_INFO=$(az mysql flexible-server list --query "[?name=='$SERVER_NAME']" -o json)
    
    if [ "$SERVER_INFO" == "[]" ]; then
        echo -e "${RED}Error: MySQL server '$SERVER_NAME' not found${NC}"
        exit 1
    fi
    
    RG_NAME=$(echo "$SERVER_INFO" | jq -r '.[0].resourceGroup')
    
    echo -e "${BLUE}MySQL Server Information: $SERVER_NAME${NC}"
    echo "========================================"
    
    az mysql flexible-server show \
        --name "$SERVER_NAME" \
        --resource-group "$RG_NAME" \
        --output table
    
    echo ""
    echo -e "${CYAN}Firewall Rules:${NC}"
    az mysql flexible-server firewall-rule list \
        --resource-group "$RG_NAME" \
        --name "$SERVER_NAME" \
        --output table
    
    echo ""
    echo -e "${CYAN}Databases:${NC}"
    az mysql flexible-server db list \
        --resource-group "$RG_NAME" \
        --server-name "$SERVER_NAME" \
        --output table
}

# Main script logic
case "$1" in
    list)
        list_servers
        ;;
    create)
        create_server
        ;;
    delete)
        delete_server "$2"
        ;;
    start)
        start_server "$2"
        ;;
    stop)
        stop_server "$2"
        ;;
    info)
        server_info "$2"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
