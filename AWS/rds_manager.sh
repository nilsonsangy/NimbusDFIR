#!/bin/bash

# RDS Manager Script
# Author: NimbusDFIR
# Description: Manage RDS databases - list, create, and delete RDS instances

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    echo "Please install AWS CLI first"
    exit 1
fi

# Check if AWS credentials are configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    echo "Please run: aws configure"
    exit 1
fi

# Function to display usage
usage() {
    echo -e "${BLUE}=========================================="
    echo "RDS Manager - NimbusDFIR"
    echo -e "==========================================${NC}"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  list              List all RDS database instances"
    echo "  create            Create a new RDS database instance"
    echo "  delete            Delete an RDS database instance"
    echo "  info              Get database instance information"
    echo "  help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 create"
    echo "  $0 delete my-database"
    echo "  $0 info my-database"
    echo ""
}

# Function to list RDS instances
list_databases() {
    echo -e "${BLUE}Listing RDS Database Instances...${NC}"
    echo ""
    
    DBS=$(aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,Engine,DBInstanceClass,DBInstanceStatus,Endpoint.Address,AllocatedStorage]' --output text)
    
    if [ -z "$DBS" ]; then
        echo -e "${YELLOW}No RDS database instances found${NC}"
        return
    fi
    
    echo -e "${GREEN}DB Identifier\t\tEngine\t\tClass\t\tStatus\t\tEndpoint\t\t\t\tStorage(GB)${NC}"
    echo "------------------------------------------------------------------------------------------------------------------------------------------------"
    
    echo "$DBS" | while IFS=$'\t' read -r id engine class status endpoint storage; do
        if [ "$status" == "available" ]; then
            echo -e "${GREEN}$id\t$engine\t$class\t$status\t$endpoint\t$storage${NC}"
        elif [ "$status" == "creating" ]; then
            echo -e "${YELLOW}$id\t$engine\t$class\t$status\t$endpoint\t$storage${NC}"
        elif [ "$status" == "deleting" ]; then
            echo -e "${RED}$id\t$engine\t$class\t$status\t$endpoint\t$storage${NC}"
        else
            echo -e "$id\t$engine\t$class\t$status\t$endpoint\t$storage"
        fi
    done
    
    echo ""
    TOTAL=$(echo "$DBS" | wc -l | xargs)
    echo -e "Total databases: ${GREEN}$TOTAL${NC}"
}

# Function to create RDS instance
create_database() {
    echo -e "${BLUE}Create New RDS Database Instance${NC}"
    echo ""
    
    # Get DB identifier
    read -p "Enter DB instance identifier (lowercase, alphanumeric, hyphens): " DB_IDENTIFIER
    
    if [ -z "$DB_IDENTIFIER" ]; then
        echo -e "${RED}Error: DB identifier is required${NC}"
        return
    fi
    
    # Validate identifier
    if ! [[ "$DB_IDENTIFIER" =~ ^[a-z][a-z0-9-]*$ ]]; then
        echo -e "${RED}Error: Invalid DB identifier${NC}"
        echo "Must start with a letter, contain only lowercase letters, numbers, and hyphens"
        return
    fi
    
    # Select engine
    echo ""
    echo "Available database engines:"
    echo "1. MySQL"
    echo "2. PostgreSQL"
    echo "3. MariaDB"
    echo "4. Oracle"
    echo "5. SQL Server"
    read -p "Select engine (1-5): " ENGINE_CHOICE
    
    case $ENGINE_CHOICE in
        1) ENGINE="mysql"; ENGINE_VERSION="8.0";;
        2) ENGINE="postgres"; ENGINE_VERSION="15.3";;
        3) ENGINE="mariadb"; ENGINE_VERSION="10.11";;
        4) ENGINE="oracle-ee"; ENGINE_VERSION="19";;
        5) ENGINE="sqlserver-ex"; ENGINE_VERSION="15.00";;
        *) echo -e "${RED}Invalid choice${NC}"; return;;
    esac
    
    # Get instance class
    echo ""
    echo "Common instance classes:"
    echo "1. db.t3.micro (1 vCPU, 1 GB RAM) - Free tier eligible"
    echo "2. db.t3.small (2 vCPU, 2 GB RAM)"
    echo "3. db.t3.medium (2 vCPU, 4 GB RAM)"
    echo "4. db.m5.large (2 vCPU, 8 GB RAM)"
    read -p "Select instance class (default: db.t3.micro): " CLASS_CHOICE
    
    case $CLASS_CHOICE in
        1|"") INSTANCE_CLASS="db.t3.micro";;
        2) INSTANCE_CLASS="db.t3.small";;
        3) INSTANCE_CLASS="db.t3.medium";;
        4) INSTANCE_CLASS="db.m5.large";;
        *) INSTANCE_CLASS="$CLASS_CHOICE";;
    esac
    
    # Get storage
    read -p "Enter allocated storage in GB (default: 20): " STORAGE
    STORAGE=${STORAGE:-20}
    
    # Get master username
    read -p "Enter master username (default: admin): " MASTER_USERNAME
    MASTER_USERNAME=${MASTER_USERNAME:-admin}
    
    # Get master password
    echo ""
    echo -e "${YELLOW}Master password requirements:${NC}"
    echo "  - At least 8 characters"
    echo "  - Cannot contain /, @, or \""
    read -sp "Enter master password: " MASTER_PASSWORD
    echo ""
    
    if [ ${#MASTER_PASSWORD} -lt 8 ]; then
        echo -e "${RED}Error: Password must be at least 8 characters${NC}"
        return
    fi
    
    # Public accessibility
    read -p "Make database publicly accessible? (y/N): " PUBLIC_ACCESS
    if [[ "$PUBLIC_ACCESS" =~ ^[Yy]$ ]]; then
        PUBLIC_FLAG="--publicly-accessible"
    else
        PUBLIC_FLAG="--no-publicly-accessible"
    fi
    
    echo ""
    echo -e "${YELLOW}Creating RDS database instance...${NC}"
    echo "This may take several minutes..."
    
    # Create database
    aws rds create-db-instance \
        --db-instance-identifier "$DB_IDENTIFIER" \
        --db-instance-class "$INSTANCE_CLASS" \
        --engine "$ENGINE" \
        --engine-version "$ENGINE_VERSION" \
        --master-username "$MASTER_USERNAME" \
        --master-user-password "$MASTER_PASSWORD" \
        --allocated-storage "$STORAGE" \
        $PUBLIC_FLAG \
        --backup-retention-period 7 \
        --no-multi-az \
        --storage-encrypted \
        --output json > /dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Database instance '$DB_IDENTIFIER' creation initiated!${NC}"
        echo ""
        echo "Database details:"
        echo "  Identifier: $DB_IDENTIFIER"
        echo "  Engine: $ENGINE $ENGINE_VERSION"
        echo "  Instance class: $INSTANCE_CLASS"
        echo "  Storage: ${STORAGE}GB"
        echo ""
        echo -e "${YELLOW}Note: Database creation takes 5-10 minutes. Use '$0 info $DB_IDENTIFIER' to check status.${NC}"
    else
        echo -e "${RED}✗ Failed to create database instance${NC}"
    fi
}

# Function to delete RDS instance
delete_database() {
    DB_IDENTIFIER=$1
    
    if [ -z "$DB_IDENTIFIER" ]; then
        echo -e "${YELLOW}Available databases:${NC}"
        list_databases
        echo ""
        read -p "Enter DB instance identifier to delete: " DB_IDENTIFIER
    fi
    
    if [ -z "$DB_IDENTIFIER" ]; then
        echo -e "${RED}Error: DB identifier is required${NC}"
        return
    fi
    
    # Verify database exists
    if ! aws rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" &> /dev/null; then
        echo -e "${RED}Error: Database instance '$DB_IDENTIFIER' not found${NC}"
        return
    fi
    
    echo -e "${YELLOW}WARNING: This will permanently delete database instance '$DB_IDENTIFIER'${NC}"
    echo "All data will be lost unless you create a final snapshot."
    echo ""
    read -p "Create final snapshot before deletion? (Y/n): " CREATE_SNAPSHOT
    
    if [[ "$CREATE_SNAPSHOT" =~ ^[Nn]$ ]]; then
        read -p "Are you absolutely sure you want to delete WITHOUT a snapshot? (yes/no): " CONFIRM
        
        if [ "$CONFIRM" != "yes" ]; then
            echo "Operation cancelled"
            return
        fi
        
        echo "Deleting database without final snapshot..."
        aws rds delete-db-instance \
            --db-instance-identifier "$DB_IDENTIFIER" \
            --skip-final-snapshot \
            --output json > /dev/null
    else
        SNAPSHOT_ID="${DB_IDENTIFIER}-final-$(date +%Y%m%d-%H%M%S)"
        
        echo "Deleting database with final snapshot: $SNAPSHOT_ID"
        aws rds delete-db-instance \
            --db-instance-identifier "$DB_IDENTIFIER" \
            --final-db-snapshot-identifier "$SNAPSHOT_ID" \
            --output json > /dev/null
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Database instance '$DB_IDENTIFIER' deletion initiated${NC}"
        echo "Deletion may take several minutes to complete."
    else
        echo -e "${RED}✗ Failed to delete database instance${NC}"
    fi
}

# Function to get database information
database_info() {
    DB_IDENTIFIER=$1
    
    if [ -z "$DB_IDENTIFIER" ]; then
        read -p "Enter DB instance identifier: " DB_IDENTIFIER
    fi
    
    if [ -z "$DB_IDENTIFIER" ]; then
        echo -e "${RED}Error: DB identifier is required${NC}"
        return
    fi
    
    # Check if database exists
    if ! aws rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" &> /dev/null; then
        echo -e "${RED}Error: Database instance '$DB_IDENTIFIER' not found${NC}"
        return
    fi
    
    echo -e "${BLUE}Database Instance Information: $DB_IDENTIFIER${NC}"
    echo "----------------------------------------"
    
    DB_INFO=$(aws rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" --query 'DBInstances[0]')
    
    # Parse and display information
    STATUS=$(echo "$DB_INFO" | jq -r '.DBInstanceStatus')
    ENGINE=$(echo "$DB_INFO" | jq -r '.Engine')
    ENGINE_VERSION=$(echo "$DB_INFO" | jq -r '.EngineVersion')
    INSTANCE_CLASS=$(echo "$DB_INFO" | jq -r '.DBInstanceClass')
    STORAGE=$(echo "$DB_INFO" | jq -r '.AllocatedStorage')
    ENDPOINT=$(echo "$DB_INFO" | jq -r '.Endpoint.Address // "N/A"')
    PORT=$(echo "$DB_INFO" | jq -r '.Endpoint.Port // "N/A"')
    STORAGE_ENCRYPTED=$(echo "$DB_INFO" | jq -r '.StorageEncrypted')
    MULTI_AZ=$(echo "$DB_INFO" | jq -r '.MultiAZ')
    PUBLIC=$(echo "$DB_INFO" | jq -r '.PubliclyAccessible')
    
    echo "Status: $STATUS"
    echo "Engine: $ENGINE $ENGINE_VERSION"
    echo "Instance Class: $INSTANCE_CLASS"
    echo "Allocated Storage: ${STORAGE}GB"
    echo "Endpoint: $ENDPOINT"
    echo "Port: $PORT"
    echo "Encrypted: $STORAGE_ENCRYPTED"
    echo "Multi-AZ: $MULTI_AZ"
    echo "Publicly Accessible: $PUBLIC"
    
    if [ "$STATUS" == "available" ]; then
        echo ""
        echo -e "${GREEN}Database is ready for connections${NC}"
    elif [ "$STATUS" == "creating" ]; then
        echo ""
        echo -e "${YELLOW}Database is being created...${NC}"
    fi
}

# Main script logic
if [ $# -eq 0 ]; then
    usage
    exit 0
fi

COMMAND=$1
shift

case $COMMAND in
    list)
        list_databases
        ;;
    create)
        create_database
        ;;
    delete|remove)
        delete_database "$@"
        ;;
    info)
        database_info "$@"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        echo -e "${RED}Error: Unknown command '$COMMAND'${NC}"
        echo ""
        usage
        exit 1
        ;;
esac
