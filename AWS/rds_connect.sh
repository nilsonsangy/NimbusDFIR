#!/bin/bash

# RDS Connect Script
# Author: NimbusDFIR
# Description: Connect to RDS MySQL database - handles both public and private instances
#              Creates a jump server EC2 instance for private RDS access

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

# Check if mysql client is installed
if ! command -v mysql &> /dev/null; then
    echo -e "${RED}Error: MySQL client is not installed${NC}"
    echo "Please install MySQL client first"
    echo "macOS: brew install mysql-client"
    echo "Ubuntu/Debian: sudo apt-get install mysql-client"
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
    echo "RDS Connect - NimbusDFIR"
    echo -e "==========================================${NC}"
    echo ""
    echo "Usage: $0 [DB_IDENTIFIER]"
    echo ""
    echo "Description:"
    echo "  Connects to an RDS MySQL database"
    echo "  - For public databases: connects directly"
    echo "  - For private databases: creates EC2 jump server with SSH tunnel"
    echo ""
    echo "Examples:"
    echo "  $0 my-database"
    echo "  $0"
    echo ""
}

# Function to list available RDS databases
list_databases() {
    echo -e "${BLUE}Available RDS MySQL/MariaDB Instances:${NC}"
    echo ""
    
    DBS=$(aws rds describe-db-instances --query 'DBInstances[?Engine==`mysql` || Engine==`mariadb`].[DBInstanceIdentifier,Engine,DBInstanceStatus,PubliclyAccessible,Endpoint.Address]' --output text)
    
    if [ -z "$DBS" ]; then
        echo -e "${YELLOW}No MySQL/MariaDB RDS database instances found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}DB Identifier\t\tEngine\t\tStatus\t\tPublic\t\tEndpoint${NC}"
    echo "--------------------------------------------------------------------------------"
    
    echo "$DBS" | while IFS=$'\t' read -r id engine status public endpoint; do
        if [ "$status" == "available" ]; then
            echo -e "${GREEN}$id\t$engine\t$status\t$public\t$endpoint${NC}"
        else
            echo -e "${YELLOW}$id\t$engine\t$status\t$public\t$endpoint${NC}"
        fi
    done
    echo ""
}

# Function to get RDS information
get_rds_info() {
    local DB_IDENTIFIER=$1
    
    # Check if database exists
    if ! aws rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" &> /dev/null; then
        echo -e "${RED}Error: Database instance '$DB_IDENTIFIER' not found${NC}"
        exit 1
    fi
    
    DB_INFO=$(aws rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" --query 'DBInstances[0]')
    
    DB_STATUS=$(echo "$DB_INFO" | jq -r '.DBInstanceStatus')
    DB_ENGINE=$(echo "$DB_INFO" | jq -r '.Engine')
    DB_ENDPOINT=$(echo "$DB_INFO" | jq -r '.Endpoint.Address // "N/A"')
    DB_PORT=$(echo "$DB_INFO" | jq -r '.Endpoint.Port // "3306"')
    DB_USERNAME=$(echo "$DB_INFO" | jq -r '.MasterUsername')
    DB_PUBLIC=$(echo "$DB_INFO" | jq -r '.PubliclyAccessible')
    DB_VPC=$(echo "$DB_INFO" | jq -r '.DBSubnetGroup.VpcId')
    DB_SECURITY_GROUPS=$(echo "$DB_INFO" | jq -r '.VpcSecurityGroups[].VpcSecurityGroupId' | tr '\n' ' ')
    
    if [ "$DB_STATUS" != "available" ]; then
        echo -e "${RED}Error: Database is not available (Status: $DB_STATUS)${NC}"
        exit 1
    fi
    
    if [[ ! "$DB_ENGINE" =~ ^(mysql|mariadb)$ ]]; then
        echo -e "${RED}Error: This script only supports MySQL/MariaDB databases${NC}"
        echo "Database engine: $DB_ENGINE"
        exit 1
    fi
}

# Function to connect to public RDS
connect_public_rds() {
    echo -e "${GREEN}Database is publicly accessible${NC}"
    echo "Connecting directly to RDS instance..."
    echo ""
    echo "Connection details:"
    echo "  Host: $DB_ENDPOINT"
    echo "  Port: $DB_PORT"
    echo "  Username: $DB_USERNAME"
    echo ""
    
    read -p "Enter database name (press Enter for default/no database): " DB_NAME
    echo -e "${YELLOW}Enter password for user '$DB_USERNAME':${NC}"
    read -s DB_PASSWORD
    echo ""
    
    if [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}Error: Password is required${NC}"
        exit 1
    fi
    
    echo "Connecting to MySQL..."
    if [ -n "$DB_NAME" ]; then
        mysql -h "$DB_ENDPOINT" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_NAME"
    else
        mysql -h "$DB_ENDPOINT" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD"
    fi
}

# Function to create EC2 jump server instance
create_jumpserver_instance() {
    echo -e "${YELLOW}Database is private - creating EC2 jump server instance...${NC}"
    echo ""
    
    # Get default VPC subnet in the same VPC as RDS
    SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$DB_VPC" "Name=map-public-ip-on-launch,Values=true" \
        --query 'Subnets[0].SubnetId' \
        --output text)
    
    if [ "$SUBNET_ID" == "None" ] || [ -z "$SUBNET_ID" ]; then
        echo -e "${YELLOW}No public subnet found in VPC. Using first available subnet...${NC}"
        SUBNET_ID=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$DB_VPC" \
            --query 'Subnets[0].SubnetId' \
            --output text)
    fi
    
    if [ "$SUBNET_ID" == "None" ] || [ -z "$SUBNET_ID" ]; then
        echo -e "${RED}Error: No subnet found in VPC $DB_VPC${NC}"
        exit 1
    fi
    
    echo "Using subnet: $SUBNET_ID"
    
    # Get latest Amazon Linux 2023 AMI
    AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    echo "Using AMI: $AMI_ID"
    
    # Create or get security group for jump server
    JUMPSERVER_SG_NAME="rds-jumpserver-sg-$(date +%s)"
    echo "Creating security group: $JUMPSERVER_SG_NAME"
    
    JUMPSERVER_SG_ID=$(aws ec2 create-security-group \
        --group-name "$JUMPSERVER_SG_NAME" \
        --description "Jump server for RDS access" \
        --vpc-id "$DB_VPC" \
        --query 'GroupId' \
        --output text)
    
    # Allow SSH access from current IP
    CURRENT_IP=$(curl -s ifconfig.me 2>/dev/null || echo "0.0.0.0/0")
    
    echo "Adding SSH rule for IP: $CURRENT_IP"
    
    # Check if it's IPv6 and add both IPv4 and IPv6 rules if needed
    if [[ "$CURRENT_IP" =~ : ]]; then
        # IPv6 address
        aws ec2 authorize-security-group-ingress \
            --group-id "$JUMPSERVER_SG_ID" \
            --ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,Ipv6Ranges="[{CidrIpv6=$CURRENT_IP/128}]" &> /dev/null || true
    else
        # IPv4 address
        if [ "$CURRENT_IP" != "0.0.0.0/0" ]; then
            CURRENT_IP="$CURRENT_IP/32"
        fi
        aws ec2 authorize-security-group-ingress \
            --group-id "$JUMPSERVER_SG_ID" \
            --protocol tcp \
            --port 22 \
            --cidr "$CURRENT_IP" &> /dev/null || true
    fi
    
    # Also allow from 0.0.0.0/0 as fallback (can be removed later for security)
    echo "Adding fallback SSH rule (0.0.0.0/0) for connectivity"
    aws ec2 authorize-security-group-ingress \
        --group-id "$JUMPSERVER_SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr "0.0.0.0/0" &> /dev/null || true
    
    # Update RDS security group to allow bastion access
    echo "Updating RDS security groups to allow bastion access..."
    for SG_ID in $DB_SECURITY_GROUPS; do
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port "$DB_PORT" \
            --source-group "$BASTION_SG_ID" &> /dev/null || echo "Rule may already exist for $SG_ID"
    done
    
    # Create key pair
    KEY_NAME="rds-bastion-key-$(date +%s)"
    KEY_FILE="$HOME/.ssh/$KEY_NAME.pem"
    
    # Ensure .ssh directory exists
    mkdir -p "$HOME/.ssh"
    
    echo "Creating EC2 key pair: $KEY_NAME"
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --query 'KeyMaterial' \
        --output text > "$KEY_FILE"
    
    if [ ! -f "$KEY_FILE" ]; then
        echo -e "${RED}Error: Failed to create key file${NC}"
        exit 1
    fi
    
    chmod 400 "$KEY_FILE"
    echo -e "${GREEN}✓ Key pair saved to: $KEY_FILE${NC}"
    
    # Launch EC2 instance
    echo "Launching EC2 bastion instance..."
    
    LAUNCH_OUTPUT=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type t2.micro \
        --key-name "$KEY_NAME" \
        --security-group-ids "$BASTION_SG_ID" \
        --subnet-id "$SUBNET_ID" \
        --associate-public-ip-address \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=rds-bastion-temp},{Key=Purpose,Value=RDS-Access}]" \
        --output json)
    
    INSTANCE_ID=$(echo "$LAUNCH_OUTPUT" | jq -r '.Instances[0].InstanceId // empty')
    
    if [ -z "$INSTANCE_ID" ]; then
        echo -e "${RED}Error: Failed to create EC2 instance${NC}"
        echo "AWS Response:"
        echo "$LAUNCH_OUTPUT" | jq '.'
        exit 1
    fi
    
    echo -e "${GREEN}✓ Bastion instance created: $INSTANCE_ID${NC}"
    echo "Waiting for instance to be running..."
    
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
    
    # Get instance public IP
    BASTION_IP=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    if [ -z "$BASTION_IP" ] || [ "$BASTION_IP" == "None" ]; then
        echo -e "${RED}Error: Failed to get public IP for bastion instance${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Bastion instance is running${NC}"
    echo "Public IP: $BASTION_IP"
    echo ""
    
    # Save connection info for cleanup
    echo "$INSTANCE_ID|$KEY_FILE|$KEY_NAME|$BASTION_SG_ID" > /tmp/rds_bastion_info.txt
    
    # Export for use in connect function
    export BASTION_INSTANCE_ID="$INSTANCE_ID"
    export BASTION_KEY_FILE="$KEY_FILE"
    export BASTION_IP_ADDR="$BASTION_IP"
}

# Function to connect via SSH tunnel
connect_via_bastion() {
    local BASTION_IP=$1
    local KEY_FILE=$2
    
    echo ""
    echo -e "${BLUE}Setting up SSH tunnel to RDS through bastion...${NC}"
    echo ""
    echo "Waiting for SSH to be available (this may take 30-60 seconds)..."
    
    # Wait for SSH to be ready with better retry logic
    SSH_READY=false
    for i in {1..60}; do
        if ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o ConnectionAttempts=1 ec2-user@"$BASTION_IP" "echo SSH ready" &> /dev/null; then
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
        echo "The bastion instance may not be accessible. Please check:"
        echo "  - Security group rules"
        echo "  - Instance status"
        echo "  - Network connectivity"
        exit 1
    fi
    echo ""
    
    # Get database credentials
    read -p "Enter database name (press Enter for default/no database): " DB_NAME
    echo -e "${YELLOW}Enter password for user '$DB_USERNAME':${NC}"
    read -s DB_PASSWORD
    echo ""
    
    if [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}Error: Password is required${NC}"
        exit 1
    fi
    
    LOCAL_PORT=3307
    
    echo -e "${GREEN}===========================================
✓ SSH Tunnel Configuration
===========================================${NC}"
    echo "Local Port: $LOCAL_PORT"
    echo "Remote RDS: $DB_ENDPOINT:$DB_PORT"
    echo "Bastion: $BASTION_IP"
    echo ""
    echo -e "${YELLOW}Starting SSH tunnel in background...${NC}"
    
    # Start SSH tunnel in background
    ssh -i "$KEY_FILE" -f -N -L "$LOCAL_PORT:$DB_ENDPOINT:$DB_PORT" -o StrictHostKeyChecking=no ec2-user@"$BASTION_IP"
    
    sleep 2
    
    echo -e "${GREEN}✓ SSH tunnel established${NC}"
    echo ""
    echo "Connecting to MySQL through tunnel..."
    echo ""
    
    # Connect to MySQL through tunnel
    if [ -n "$DB_NAME" ]; then
        mysql -h 127.0.0.1 -P "$LOCAL_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_NAME"
    else
        mysql -h 127.0.0.1 -P "$LOCAL_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD"
    fi
    
    # Kill SSH tunnel
    echo ""
    echo "Closing SSH tunnel..."
    pkill -f "ssh.*$LOCAL_PORT:$DB_ENDPOINT:$DB_PORT" 2>/dev/null || true
}

# Function to cleanup bastion resources
cleanup_bastion() {
    if [ -f /tmp/rds_bastion_info.txt ]; then
        echo ""
        echo -e "${YELLOW}Cleaning up bastion resources...${NC}"
        
        IFS='|' read -r INSTANCE_ID KEY_FILE KEY_NAME BASTION_SG_ID < /tmp/rds_bastion_info.txt
        
        # Terminate instance
        if [ -n "$INSTANCE_ID" ]; then
            echo "Terminating EC2 instance: $INSTANCE_ID"
            aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" &> /dev/null || true
            aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" 2>/dev/null || true
        fi
        
        # Delete key pair
        if [ -n "$KEY_NAME" ]; then
            echo "Deleting key pair: $KEY_NAME"
            aws ec2 delete-key-pair --key-name "$KEY_NAME" &> /dev/null || true
            rm -f "$KEY_FILE" 2>/dev/null || true
        fi
        
        # Delete security group
        if [ -n "$BASTION_SG_ID" ]; then
            echo "Deleting security group: $BASTION_SG_ID"
            sleep 5  # Wait a bit for instance to fully terminate
            aws ec2 delete-security-group --group-id "$BASTION_SG_ID" &> /dev/null || true
        fi
        
        rm -f /tmp/rds_bastion_info.txt
        echo -e "${GREEN}✓ Cleanup complete${NC}"
    fi
}

# Trap to cleanup on exit
trap cleanup_bastion EXIT INT TERM

# Main script logic
if [ "$1" == "help" ] || [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    usage
    exit 0
fi

DB_IDENTIFIER=$1

if [ -z "$DB_IDENTIFIER" ]; then
    list_databases
    echo ""
    read -p "Enter DB instance identifier: " DB_IDENTIFIER
    
    if [ -z "$DB_IDENTIFIER" ]; then
        echo -e "${RED}Error: DB identifier is required${NC}"
        exit 1
    fi
fi

# Get RDS information
echo -e "${BLUE}Gathering RDS information...${NC}"
get_rds_info "$DB_IDENTIFIER"

echo -e "${BLUE}=========================================="
echo "Database Information"
echo -e "==========================================${NC}"
echo "Identifier: $DB_IDENTIFIER"
echo "Engine: $DB_ENGINE"
echo "Endpoint: $DB_ENDPOINT:$DB_PORT"
echo "Username: $DB_USERNAME"
echo "Public: $DB_PUBLIC"
echo "VPC: $DB_VPC"
echo ""

# Connect based on accessibility
if [ "$DB_PUBLIC" == "true" ]; then
    connect_public_rds
else
    create_bastion_instance
    connect_via_bastion "$BASTION_IP_ADDR" "$BASTION_KEY_FILE"
fi

echo ""
echo -e "${GREEN}Connection closed${NC}"
