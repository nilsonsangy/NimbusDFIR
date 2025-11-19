#!/bin/bash

# Azure MySQL Connect Script
# Author: NimbusDFIR
# Description: Connect to Azure MySQL Flexible Server - handles both public and private instances
#              Creates a jump server VM for private MySQL access

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
    exit 1
fi

# Check if mysql client is installed
if ! command -v mysql &> /dev/null; then
    echo -e "${RED}Error: MySQL client is not installed${NC}"
    echo "Please install MySQL client first"
    echo "macOS: brew install mysql-client"
    echo "Ubuntu/Debian: sudo apt-get install mysql-client"
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
    echo "Azure MySQL Connect - NimbusDFIR"
    echo -e "==========================================${NC}"
    echo ""
    echo "Usage: $0 [SERVER_NAME]"
    echo ""
    echo "Description:"
    echo "  Connects to an Azure MySQL Flexible Server"
    echo "  - For public servers: connects directly"
    echo "  - For private servers: creates Azure VM jump server with SSH tunnel"
    echo ""
    echo "Examples:"
    echo "  $0 my-mysql-server"
    echo "  $0"
    echo ""
}

# Function to list available MySQL servers
list_servers() {
    echo -e "${BLUE}Available Azure MySQL Flexible Servers:${NC}"
    echo ""
    
    SERVERS=$(az mysql flexible-server list --output json 2>/dev/null)
    
    if [ "$SERVERS" == "[]" ] || [ -z "$SERVERS" ]; then
        echo -e "${YELLOW}No MySQL flexible servers found${NC}"
        exit 1
    fi
    
    echo "$SERVERS" | jq -r '.[] | "\(.name) (\(.resourceGroup) - \(.state) - Public: \(.network.publicNetworkAccess // "Unknown"))"' | nl -w2 -s'. '
    echo ""
}

# Function to get MySQL server information
get_server_info() {
    local SERVER_NAME=$1
    
    # Check if server exists
    SERVER_INFO=$(az mysql flexible-server list --query "[?name=='$SERVER_NAME']" -o json)
    
    if [ "$SERVER_INFO" == "[]" ]; then
        echo -e "${RED}Error: MySQL server '$SERVER_NAME' not found${NC}"
        exit 1
    fi
    
    SERVER_STATUS=$(echo "$SERVER_INFO" | jq -r '.[0].state')
    SERVER_FQDN=$(echo "$SERVER_INFO" | jq -r '.[0].fullyQualifiedDomainName')
    SERVER_VERSION=$(echo "$SERVER_INFO" | jq -r '.[0].version')
    SERVER_LOCATION=$(echo "$SERVER_INFO" | jq -r '.[0].location')
    SERVER_RG=$(echo "$SERVER_INFO" | jq -r '.[0].resourceGroup')
    SERVER_PUBLIC=$(echo "$SERVER_INFO" | jq -r '.[0].network.publicNetworkAccess // "Disabled"')
    
    if [ "$SERVER_STATUS" != "Ready" ]; then
        echo -e "${RED}Error: Server is not ready (Status: $SERVER_STATUS)${NC}"
        exit 1
    fi
    
    # Check if there are firewall rules (only matters if public access is enabled)
    if [ "$SERVER_PUBLIC" == "Enabled" ]; then
        FIREWALL_RULES=$(az mysql flexible-server firewall-rule list \
            --resource-group "$SERVER_RG" \
            --name "$SERVER_NAME" \
            --query "length(@)" \
            -o tsv 2>/dev/null || echo "0")
        
        if [ "$FIREWALL_RULES" == "0" ]; then
            echo -e "${YELLOW}Warning: Server has public access enabled but no firewall rules${NC}"
            echo -e "${YELLOW}Treating as private server - will use jump server${NC}"
            SERVER_PUBLIC="Disabled"
        fi
    fi
}

# Function to connect to public MySQL server
connect_public_mysql() {
    echo -e "${GREEN}Server has public access enabled${NC}"
    echo "Connecting directly to MySQL server..."
    echo ""
    echo "Connection details:"
    echo "  Host: $SERVER_FQDN"
    echo "  Port: 3306"
    echo ""
    
    read -p "Enter MySQL username: " MYSQL_USER
    
    if [ -z "$MYSQL_USER" ]; then
        echo -e "${RED}Error: Username is required${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Enter password for user '$MYSQL_USER':${NC}"
    read -s MYSQL_PASSWORD
    echo ""
    
    if [ -z "$MYSQL_PASSWORD" ]; then
        echo -e "${RED}Error: Password is required${NC}"
        exit 1
    fi
    
    read -p "Enter database name (press Enter for no database): " DB_NAME
    echo ""
    
    echo "Connecting to MySQL..."
    if [ -n "$DB_NAME" ]; then
        mysql -h "$SERVER_FQDN" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$DB_NAME"
    else
        mysql -h "$SERVER_FQDN" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD"
    fi
}

# Function to create Azure VM jump server instance
create_jumpserver_vm() {
    echo -e "${YELLOW}Server is private - checking for existing jump server...${NC}"
    echo ""
    
    JUMPSERVER_RG="$SERVER_RG"
    JUMPSERVER_LOCATION="$SERVER_LOCATION"

    # Check for existing jump server VMs
    EXISTING_JUMPSERVERS=$(az vm list \
        --resource-group "$JUMPSERVER_RG" \
        --query "[?starts_with(name, 'mysql-jumpserver')].{name:name, state:powerState, ip:publicIps}" \
        -o json 2>/dev/null)
    
    if [ "$EXISTING_JUMPSERVERS" != "[]" ] && [ -n "$EXISTING_JUMPSERVERS" ]; then
        # Found existing jump server(s)
        JUMPSERVER_COUNT=$(echo "$EXISTING_JUMPSERVERS" | jq 'length')
        
        if [ "$JUMPSERVER_COUNT" -gt 0 ]; then
            echo -e "${GREEN}Found $JUMPSERVER_COUNT existing jump server VM(s)${NC}"
            echo "$EXISTING_JUMPSERVERS" | jq -r '.[] | "\(.name) - \(.state) - \(.ip)"' | nl -w2 -s'. '
            echo
            read -p "Use existing jump server? (Y/n): " USE_EXISTING
            
            if [[ ! "$USE_EXISTING" =~ ^[Nn]$ ]]; then
                # Use first running jump server or first jump server if none running
                JUMPSERVER_NAME=$(echo "$EXISTING_JUMPSERVERS" | jq -r '.[0].name')
                JUMPSERVER_STATE=$(echo "$EXISTING_JUMPSERVERS" | jq -r '.[0].state')
                
                # Get public IP
                JUMPSERVER_PUBLIC_IP=$(az vm show \
                    --resource-group "$JUMPSERVER_RG" \
                    --name "$JUMPSERVER_NAME" \
                    --show-details \
                    --query publicIps \
                    -o tsv 2>/dev/null)
                
                # Start VM if it's stopped
                if [[ "$JUMPSERVER_STATE" == *"stopped"* ]] || [[ "$JUMPSERVER_STATE" == *"deallocated"* ]]; then
                    echo -e "${YELLOW}Starting existing jump server VM: $JUMPSERVER_NAME${NC}"
                    az vm start --resource-group "$JUMPSERVER_RG" --name "$JUMPSERVER_NAME" --no-wait
                    sleep 10
                    
                    # Get public IP after starting
                    JUMPSERVER_PUBLIC_IP=$(az vm show \
                        --resource-group "$JUMPSERVER_RG" \
                        --name "$JUMPSERVER_NAME" \
                        --show-details \
                        --query publicIps \
                        -o tsv 2>/dev/null)
                fi
                
                echo -e "${GREEN}✓ Using existing jump server VM: $JUMPSERVER_NAME${NC}"
                echo "Public IP: $JUMPSERVER_PUBLIC_IP"
                echo ""
                
                # Save info - will be cleaned up on exit
                echo "$JUMPSERVER_NAME|$JUMPSERVER_RG|$JUMPSERVER_PUBLIC_IP" > /tmp/azure_mysql_jumpserver_info.txt
                
                # Export for use in connect function
                export JUMPSERVER_VM_NAME="$JUMPSERVER_NAME"
                export JUMPSERVER_VM_RG="$JUMPSERVER_RG"
                export JUMPSERVER_VM_IP="$JUMPSERVER_PUBLIC_IP"
                return 0
            fi
        fi
    fi
    
    # Create new jump server VM
    echo -e "${YELLOW}Creating new Azure VM jump server instance...${NC}"
    echo ""
    
    # Generate unique name
    BASTION_NAME="mysql-bastion-$(date +%s)"
    
    # Create resource group if it doesn't exist (usually will exist)
    az group show --name "$BASTION_RG" &> /dev/null || \
        az group create --name "$BASTION_RG" --location "$BASTION_LOCATION" --output none
    
    echo "Creating jump server VM: $JUMPSERVER_NAME"
    echo "Location: $JUMPSERVER_LOCATION"
    echo "Resource Group: $JUMPSERVER_RG"
    echo ""
    
    # Create VM with SSH key
    echo "Launching VM (this may take 2-3 minutes)..."
    
    VM_OUTPUT=$(az vm create \
        --resource-group "$JUMPSERVER_RG" \
        --name "$JUMPSERVER_NAME" \
        --location "$JUMPSERVER_LOCATION" \
        --image Ubuntu2204 \
        --size Standard_B1s \
        --admin-username azureuser \
        --generate-ssh-keys \
        --public-ip-sku Standard \
        --public-ip-address "${JUMPSERVER_NAME}-ip" \
        --nsg "${JUMPSERVER_NAME}-nsg" \
        --nsg-rule SSH \
        --output json)
    
    # Extract JSON part (skip warnings at the beginning)
    VM_JSON=$(echo "$VM_OUTPUT" | sed -n '/{/,/}/p')
    
    # Check if we got valid JSON
    if [ -z "$VM_JSON" ] || ! echo "$VM_JSON" | jq empty 2>/dev/null; then
        echo -e "${RED}Error: Failed to create jump server VM${NC}"
        echo "Error details:"
        echo "$VM_OUTPUT"
        exit 1
    fi
    
    JUMPSERVER_PUBLIC_IP=$(echo "$VM_JSON" | jq -r '.publicIpAddress // empty')
    JUMPSERVER_PRIVATE_IP=$(echo "$VM_JSON" | jq -r '.privateIpAddress // empty')

    if [ -z "$JUMPSERVER_PUBLIC_IP" ]; then
        echo -e "${RED}Error: Failed to get jump server VM public IP${NC}"
        echo "VM creation output:"
        echo "$VM_JSON" | jq '.'
        exit 1
    fi
    
    echo -e "${GREEN}✓ Jump server VM created successfully${NC}"
    echo "Public IP: $JUMPSERVER_PUBLIC_IP"
    echo "Private IP: $JUMPSERVER_PRIVATE_IP"
    echo ""
    
    # Save cleanup info - will be cleaned up on exit
    echo "$JUMPSERVER_NAME|$JUMPSERVER_RG|$JUMPSERVER_PUBLIC_IP" > /tmp/azure_mysql_jumpserver_info.txt
    
    # Export for use in connect function
    export JUMPSERVER_VM_NAME="$JUMPSERVER_NAME"
    export JUMPSERVER_VM_RG="$JUMPSERVER_RG"
    export JUMPSERVER_VM_IP="$JUMPSERVER_PUBLIC_IP"
}

# Function to connect via SSH tunnel through jump server VM
connect_via_jumpserver() {
    local JUMPSERVER_IP=$1
    local JUMPSERVER_RG=$2
    local JUMPSERVER_NAME=$3
    
    echo ""
    echo -e "${BLUE}Setting up SSH tunnel to MySQL through jump server VM...${NC}"
    echo ""
    echo "Waiting for VM to be fully ready (this may take 30-60 seconds)..."
    
    # Wait for SSH to be ready
    SSH_READY=false
    for i in {1..60}; do
        if ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o ConnectionAttempts=1 azureuser@"$JUMPSERVER_IP" "echo SSH ready" &> /dev/null; then
            echo -e "${GREEN}✓ SSH connection established${NC}"
            SSH_READY=true
            break
        fi
        if [ $((i % 10)) -eq 0 ]; then
            echo "Still waiting... ($i/60 seconds)"
        fi
        sleep 1
    done
    
    if [ "$SSH_READY" = false ]; then
        echo -e "${RED}Error: SSH connection timeout${NC}"
        echo "The jump server VM may not be accessible. Checking VM status..."
        az vm show --resource-group "$JUMPSERVER_RG" --name "$JUMPSERVER_NAME" --query "powerState" -o tsv
        exit 1
    fi
    echo ""
    
    # Add firewall rule for jump server VM to access MySQL
    echo -e "${YELLOW}Adding firewall rule for jump server VM...${NC}"
    JUMPSERVER_PUBLIC_IP_FOR_FW=$(echo "$JUMPSERVER_IP")
    RULE_NAME="jumpserver-access-$(date +%s)"
    
    az mysql flexible-server firewall-rule create \
        --resource-group "$SERVER_RG" \
        --name "$SERVER_NAME" \
        --rule-name "$RULE_NAME" \
        --start-ip-address "$JUMPSERVER_PUBLIC_IP_FOR_FW" \
        --end-ip-address "$JUMPSERVER_PUBLIC_IP_FOR_FW" \
        --output none
    
    echo -e "${GREEN}✓ Firewall rule created${NC}"
    echo ""
    
    # Get MySQL credentials
    read -p "Enter MySQL username: " MYSQL_USER
    
    if [ -z "$MYSQL_USER" ]; then
        echo -e "${RED}Error: Username is required${NC}"
        exit 1
    fi
    
    read -p "Enter database name (press Enter for no database): " DB_NAME
    echo ""
    
    # Store credentials temporarily using mysql_config_editor (will prompt for password interactively)
    echo -e "${YELLOW}Setting up secure credentials (you'll be prompted for password)...${NC}"
    LOGIN_PATH="nimbus-temp-$$"
    mysql_config_editor set --login-path="$LOGIN_PATH" --host=127.0.0.1 --port=3307 --user="$MYSQL_USER" --password
    
    echo ""
    
    LOCAL_PORT=3307
    
    echo -e "${GREEN}===========================================
✓ SSH Tunnel Configuration
===========================================${NC}"
    echo "Local Port: $LOCAL_PORT"
    echo "Remote MySQL: $SERVER_FQDN:3306"
    echo "Jump Server: $JUMPSERVER_IP"
    echo ""
    echo -e "${YELLOW}Starting SSH tunnel in background...${NC}"
    
    # Start SSH tunnel in background
    ssh -i ~/.ssh/id_rsa -f -N -L "$LOCAL_PORT:$SERVER_FQDN:3306" -o StrictHostKeyChecking=no azureuser@"$JUMPSERVER_IP"
    
    sleep 2
    
    echo -e "${GREEN}✓ SSH tunnel established${NC}"
    echo ""
    echo "Connecting to MySQL through tunnel..."
    echo ""
    
    # Connect to MySQL through tunnel using temporary credentials
    if [ -n "$DB_NAME" ]; then
        mysql --login-path="$LOGIN_PATH" "$DB_NAME"
    else
        mysql --login-path="$LOGIN_PATH"
    fi
    
    # Cleanup after MySQL session ends
    echo ""
    echo "Cleaning up..."
    
    # Remove temporary credentials from mysql_config_editor
    mysql_config_editor remove --login-path="$LOGIN_PATH" 2>/dev/null || true
    
    # Remove firewall rule
    echo "Removing firewall rule..."
    az mysql flexible-server firewall-rule delete \
        --resource-group "$SERVER_RG" \
        --name "$SERVER_NAME" \
        --rule-name "$RULE_NAME" \
        --yes \
        --output none 2>/dev/null || true
    
    # Kill SSH tunnel
    echo "Closing SSH tunnel..."
    pkill -f "ssh.*$LOCAL_PORT:$SERVER_FQDN:3306" 2>/dev/null || true
}

# Function to cleanup jump server resources
cleanup_jumpserver() {
    if [ -f /tmp/azure_mysql_jumpserver_info.txt ]; then
        echo ""
        echo -e "${YELLOW}Cleaning up jump server resources...${NC}"
        
        IFS='|' read -r JUMPSERVER_NAME JUMPSERVER_RG JUMPSERVER_IP < /tmp/azure_mysql_jumpserver_info.txt
        
        if [ -n "$JUMPSERVER_NAME" ] && [ -n "$JUMPSERVER_RG" ]; then
            echo "Deleting jump server VM and all associated resources: $JUMPSERVER_NAME"
            
            # Get all resource IDs associated with the bastion VM
            echo "Collecting all resources to delete..."
            
            # Delete VM first (this will trigger deletion of some dependencies)
            echo "  - Deleting VM: $JUMPSERVER_NAME"
            az vm delete \
                --resource-group "$JUMPSERVER_RG" \
                --name "$JUMPSERVER_NAME" \
                --yes \
                --force-deletion yes \
                --output none 2>/dev/null || true
            
            # Wait for VM deletion to complete
            echo "  - Waiting for VM deletion to complete..."
            sleep 10
            
            # Delete NIC (must be deleted before VNET)
            echo "  - Deleting network interface(s)..."
            NIC_NAMES=$(az network nic list --resource-group "$JUMPSERVER_RG" --query "[?contains(name, '$JUMPSERVER_NAME')].name" -o tsv)
            for NIC_NAME in $NIC_NAMES; do
                az network nic delete \
                    --resource-group "$JUMPSERVER_RG" \
                    --name "$NIC_NAME" \
                    --output none 2>/dev/null || true
            done
            
            # Delete Public IP
            echo "  - Deleting public IP..."
            az network public-ip delete \
                --resource-group "$JUMPSERVER_RG" \
                --name "${JUMPSERVER_NAME}-ip" \
                --output none 2>/dev/null || true
            
            # Delete NSG
            echo "  - Deleting network security group..."
            az network nsg delete \
                --resource-group "$JUMPSERVER_RG" \
                --name "${JUMPSERVER_NAME}-nsg" \
                --output none 2>/dev/null || true
            
            # Delete Disk
            echo "  - Deleting disk(s)..."
            DISK_NAMES=$(az disk list --resource-group "$JUMPSERVER_RG" --query "[?contains(name, '$JUMPSERVER_NAME')].name" -o tsv)
            for DISK_NAME in $DISK_NAMES; do
                az disk delete \
                    --resource-group "$JUMPSERVER_RG" \
                    --name "$DISK_NAME" \
                    --yes \
                    --output none 2>/dev/null || true
            done
            
            # Wait a bit before deleting VNET
            sleep 5
            
            # Delete VNET (must be last, after all NICs are deleted)
            echo "  - Deleting virtual network..."
            VNET_NAMES=$(az network vnet list --resource-group "$JUMPSERVER_RG" --query "[?contains(name, '$JUMPSERVER_NAME')].name" -o tsv)
            for VNET_NAME in $VNET_NAMES; do
                az network vnet delete \
                    --resource-group "$JUMPSERVER_RG" \
                    --name "$VNET_NAME" \
                    --output none 2>/dev/null || true
            done
            
            echo -e "${GREEN}✓ All jump server resources deleted${NC}"
        fi
        
        rm -f /tmp/azure_mysql_jumpserver_info.txt
    fi
}

# Trap to cleanup on exit
trap cleanup_jumpserver EXIT INT TERM

# Main script logic
if [ "$1" == "help" ] || [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    usage
    exit 0
fi

SERVER_NAME=$1

if [ -z "$SERVER_NAME" ]; then
    list_servers
    echo ""
    read -p "Select server number or enter name: " SERVER_INPUT
    
    if [ -z "$SERVER_INPUT" ]; then
        echo -e "${RED}Error: Server selection is required${NC}"
        exit 1
    fi
    
    # Check if input is a number
    if [[ "$SERVER_INPUT" =~ ^[0-9]+$ ]]; then
        SERVERS=$(az mysql flexible-server list --output json 2>/dev/null)
        SERVER_NAME=$(echo "$SERVERS" | jq -r ".[$(($SERVER_INPUT-1))].name" 2>/dev/null)
        if [ -z "$SERVER_NAME" ] || [ "$SERVER_NAME" == "null" ]; then
            echo -e "${RED}Error: Invalid selection${NC}"
            exit 1
        fi
    else
        SERVER_NAME="$SERVER_INPUT"
    fi
fi

# Get server information
echo -e "${BLUE}Gathering MySQL server information...${NC}"
get_server_info "$SERVER_NAME"

echo -e "${BLUE}=========================================="
echo "MySQL Server Information"
echo -e "==========================================${NC}"
echo "Name: $SERVER_NAME"
echo "FQDN: $SERVER_FQDN"
echo "Version: $SERVER_VERSION"
echo "Location: $SERVER_LOCATION"
echo "Resource Group: $SERVER_RG"
echo "Public Access: $SERVER_PUBLIC"
echo "Status: $SERVER_STATUS"
echo ""

# Connect based on public access
if [ "$SERVER_PUBLIC" == "Enabled" ]; then
    connect_public_mysql
else
    create_jumpserver_vm
    connect_via_jumpserver "$JUMPSERVER_VM_IP" "$JUMPSERVER_VM_RG" "$JUMPSERVER_VM_NAME"
fi

echo ""
echo -e "${GREEN}MySQL connection closed${NC}"
