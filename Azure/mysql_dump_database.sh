#!/bin/bash

# Azure MySQL Dump Database Script - Bash Version
# Author: NimbusDFIR
# Description: Dump database from Azure MySQL Flexible Server using Azure CLI

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo -e "${BLUE}=========================================="
    echo "Azure MySQL Dump Database - NimbusDFIR"
    echo -e "==========================================${NC}"
    echo ""
    echo "Usage: $0 [server-name] [database-name] [output-path]"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive mode"
    echo "  $0 my-mysql-server testdb             # Direct mode"
    echo "  $0 my-mysql-server testdb ~/backups   # With custom path"
    echo ""
    echo "Features:"
    echo "  - Auto-detects existing SSH tunnels"
    echo "  - Lists available databases for selection"
    echo "  - Saves to Downloads folder by default"
    echo "  - Generates timestamped dump files"
    echo ""
}

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed${NC}"
    echo "Please install Azure CLI first"
    exit 1
fi

# Check if MySQL client is installed
if ! command -v mysqldump &> /dev/null; then
    echo -e "${RED}Error: MySQL client (mysqldump) is not installed${NC}"
    echo "Please install MySQL client first"
    echo "macOS: brew install mysql-client"
    echo "Ubuntu/Debian: sudo apt-get install mysql-client"
    echo "RHEL/CentOS: sudo yum install mysql"
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo -e "${RED}Error: Not logged in to Azure${NC}"
    echo "Please run: az login"
    exit 1
fi

# Check for active SSH tunnel
check_ssh_tunnel() {
    echo -e "${BLUE}Checking for active SSH tunnel...${NC}"
    
    TUNNEL_ACTIVE=false
    LOCAL_PORT=3307
    
    # Check if there's an SSH process running with MySQL tunnel
    if pgrep -f "ssh.*3307.*3306" > /dev/null 2>&1; then
        # Check if port 3307 is listening
        if command -v lsof &> /dev/null; then
            if lsof -i :$LOCAL_PORT > /dev/null 2>&1; then
                TUNNEL_ACTIVE=true
                echo -e "${GREEN}✓ Active SSH tunnel detected on port $LOCAL_PORT${NC}"
            fi
        elif command -v netstat &> /dev/null; then
            if netstat -ln | grep ":$LOCAL_PORT " > /dev/null 2>&1; then
                TUNNEL_ACTIVE=true
                echo -e "${GREEN}✓ Active SSH tunnel detected on port $LOCAL_PORT${NC}"
            fi
        fi
    fi
    
    if [ "$TUNNEL_ACTIVE" != "true" ]; then
        echo -e "${YELLOW}✗ No active SSH tunnel found${NC}"
        echo -e "${YELLOW}Please run mysql_connect.sh first to establish tunnel, then run this script${NC}"
        echo -e "${CYAN}Or use this script independently (will prompt for server selection)${NC}"
        echo ""
    else
        echo -e "${GREEN}Using existing SSH tunnel for database operations${NC}"
        echo ""
    fi
}

# List available MySQL servers
list_mysql_servers() {
    echo -e "${CYAN}Available MySQL Servers:${NC}"
    SERVERS=$(az mysql flexible-server list --output json 2>/dev/null)
    
    if [ "$SERVERS" == "[]" ] || [ -z "$SERVERS" ]; then
        echo -e "${YELLOW}No MySQL flexible servers found${NC}"
        exit 0
    fi
    
    echo "$SERVERS" | jq -r '.[] | "\(.name) (\(.resourceGroup) - \(.state))"' | nl -w2 -s'. '
    echo ""
}

# Get server information
get_server_info() {
    local server_name=$1
    
    echo ""
    echo -e "${BLUE}Finding server details...${NC}"
    SERVER_INFO=$(az mysql flexible-server list --query "[?name=='$server_name']" -o json)
    
    if [ "$SERVER_INFO" == "[]" ]; then
        echo -e "${RED}Error: MySQL server '$server_name' not found${NC}"
        exit 1
    fi
    
    RG_NAME=$(echo "$SERVER_INFO" | jq -r '.[0].resourceGroup')
    echo -e "${GREEN}✓ Server found in resource group: $RG_NAME${NC}"
}

# Get Azure MySQL server name automatically
get_azure_server_name() {
    local server_name
    server_name=$(az mysql flexible-server list --query '[].name' -o tsv 2>/dev/null | head -n1)
    
    if [ -n "$server_name" ]; then
        echo "$server_name"
    else
        echo "azure-mysql-server"
    fi
}

# List databases via SSH tunnel
list_databases_via_tunnel() {
    local username=$1
    local password=$2
    local local_port=$3
    
    echo -e "${BLUE}Listing databases via SSH tunnel...${NC}"
    
    # Use MYSQL_PWD for secure password handling
    MYSQL_PWD="$password" mysql -h 127.0.0.1 -P "$local_port" -u "$username" -e "SHOW DATABASES;" 2>/dev/null | \
    grep -v -E "^Database$|^-+$|^\+|information_schema|performance_schema|mysql|sys" | \
    sed 's/^|//; s/|$//' | \
    sed 's/^ *//; s/ *$//' | \
    grep -v "^$"
}

# List databases via Azure CLI
list_databases_via_cli() {
    local server_name=$1
    local resource_group=$2
    
    echo -e "${BLUE}Listing databases via Azure CLI...${NC}"
    
    az mysql flexible-server db list --resource-group "$resource_group" --server-name "$server_name" --query "[].name" -o tsv 2>/dev/null
}

# Perform database dump via SSH tunnel
dump_via_tunnel() {
    local username=$1
    local password=$2
    local database_name=$3
    local local_port=$4
    local output_file=$5
    local server_name=$6
    
    echo -e "${GREEN}Creating database dump via SSH tunnel...${NC}"
    
    # Create temporary file for dump
    local temp_file="/tmp/mysql_dump_$$.sql"
    
    # Use MYSQL_PWD for secure password handling
    if MYSQL_PWD="$password" mysqldump -h 127.0.0.1 -P "$local_port" -u "$username" --single-transaction --routines --triggers "$database_name" > "$temp_file" 2>/dev/null; then
        # Modify the dump header to show Azure server name
        sed "s/-- Host: 127\.0\.0\.1/-- Host: $server_name (via SSH tunnel from 127.0.0.1)/g" "$temp_file" > "$output_file"
        rm -f "$temp_file"
        return 0
    else
        echo -e "${RED}Error: mysqldump failed${NC}"
        rm -f "$temp_file"
        return 1
    fi
}

# Main script
if [ "$1" == "help" ] || [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    usage
    exit 0
fi

echo -e "${BLUE}=========================================="
echo "Azure MySQL Dump Database"
echo -e "==========================================${NC}"
echo ""

# Check for SSH tunnel
check_ssh_tunnel

# Get credentials first
echo -e "${BLUE}Enter MySQL credentials:${NC}"
read -p "Enter MySQL admin username (default: mysqladmin): " DB_USERNAME
DB_USERNAME=${DB_USERNAME:-mysqladmin}

echo ""
echo -e "${YELLOW}Enter MySQL admin password:${NC}"
read -s DB_PASSWORD
echo ""

if [ -z "$DB_PASSWORD" ]; then
    echo -e "${RED}Error: Password is required${NC}"
    exit 1
fi

# Get server and database information
SERVER_NAME=$1
DATABASE_NAME=$2
OUTPUT_PATH=$3

if [ "$TUNNEL_ACTIVE" = "true" ]; then
    # Get Azure server name
    AZURE_SERVER_NAME=$(get_azure_server_name)
    
    # List databases via tunnel
    DATABASES=$(list_databases_via_tunnel "$DB_USERNAME" "$DB_PASSWORD" "$LOCAL_PORT")
else
    # Get server name if not provided
    if [ -z "$SERVER_NAME" ]; then
        list_mysql_servers
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
    get_server_info "$SERVER_NAME"
    
    # List databases via Azure CLI
    DATABASES=$(list_databases_via_cli "$SERVER_NAME" "$RG_NAME")
fi

if [ -z "$DATABASES" ]; then
    echo -e "${RED}Error: No databases available for dump${NC}"
    exit 1
fi

# Show databases and get selection
echo ""
echo -e "${CYAN}Available Databases:${NC}"
echo "$DATABASES" | nl -w2 -s'. '
echo ""

if [ -z "$DATABASE_NAME" ]; then
    read -p "Select database number or enter name: " DB_INPUT
    
    if [ -z "$DB_INPUT" ]; then
        echo -e "${RED}Error: Database selection is required${NC}"
        exit 1
    fi
    
    # Check if input is a number
    if [[ "$DB_INPUT" =~ ^[0-9]+$ ]]; then
        DATABASE_NAME=$(echo "$DATABASES" | sed -n "${DB_INPUT}p")
        if [ -z "$DATABASE_NAME" ]; then
            echo -e "${RED}Error: Invalid selection${NC}"
            exit 1
        fi
    else
        DATABASE_NAME="$DB_INPUT"
    fi
fi

# Get output path
if [ -z "$OUTPUT_PATH" ]; then
    DEFAULT_PATH="$HOME/Downloads"
    echo ""
    read -p "Enter output directory (default: $DEFAULT_PATH): " OUTPUT_PATH
    OUTPUT_PATH=${OUTPUT_PATH:-$DEFAULT_PATH}
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_PATH"

# Generate output filename with timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="$OUTPUT_PATH/${DATABASE_NAME}_dump_${TIMESTAMP}.sql"

echo ""
echo -e "${BLUE}Database dump configuration:${NC}"
if [ "$TUNNEL_ACTIVE" = "true" ]; then
    echo "Connection: SSH Tunnel (localhost:$LOCAL_PORT)"
    echo "Azure Server: $AZURE_SERVER_NAME"
else
    echo "Server: $SERVER_NAME"
    echo "Resource Group: $RG_NAME"
fi
echo "Database: $DATABASE_NAME"
echo "Output File: $OUTPUT_FILE"
echo ""

read -p "Proceed with dump? (Y/n): " CONFIRM
if [ "$CONFIRM" == "n" ] || [ "$CONFIRM" == "N" ]; then
    echo -e "${YELLOW}Dump cancelled${NC}"
    exit 0
fi

# Perform the dump
echo ""
echo -e "${YELLOW}Starting database dump...${NC}"

SUCCESS=false
if [ "$TUNNEL_ACTIVE" = "true" ]; then
    if dump_via_tunnel "$DB_USERNAME" "$DB_PASSWORD" "$DATABASE_NAME" "$LOCAL_PORT" "$OUTPUT_FILE" "$AZURE_SERVER_NAME"; then
        SUCCESS=true
    fi
else
    echo -e "${YELLOW}Note: Direct Azure CLI dump not supported${NC}"
    echo -e "${YELLOW}Please use SSH tunnel method for full dump functionality${NC}"
    exit 1
fi

if [ "$SUCCESS" = "true" ]; then
    FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
    echo ""
    echo -e "${GREEN}=========================================="
    echo "✓ Database dump completed successfully!"
    echo -e "==========================================${NC}"
    echo ""
    echo "Database: $DATABASE_NAME"
    echo "Output File: $OUTPUT_FILE"
    echo "File Size: $FILE_SIZE"
    echo "Created: $(date)"
    echo ""
    echo -e "${GREEN}Dump completed!${NC}"
else
    echo ""
    echo -e "${RED}✗ Database dump failed${NC}"
    [ -f "$OUTPUT_FILE" ] && rm -f "$OUTPUT_FILE"
    exit 1
fi