#!/bin/bash

# EC2 Manager Script
# Author: NimbusDFIR
# Description: Manage EC2 instances - list, create, and remove instances

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
    echo "EC2 Manager - NimbusDFIR"
    echo -e "==========================================${NC}"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  list              List all EC2 instances"
    echo "  create            Create a new EC2 instance"
    echo "  remove            Terminate an EC2 instance"
    echo "  start             Start a stopped instance"
    echo "  stop              Stop a running instance"
    echo "  help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 create"
    echo "  $0 remove i-1234567890abcdef0"
    echo "  $0 start i-1234567890abcdef0"
    echo "  $0 stop i-1234567890abcdef0"
    echo ""
}

# Function to list EC2 instances
list_instances() {
    echo -e "${BLUE}Listing EC2 Instances...${NC}"
    echo ""
    
    INSTANCES=$(aws ec2 describe-instances \
        --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,PublicIpAddress,PrivateIpAddress,Tags[?Key==`Name`].Value|[0]]' \
        --output text)
    
    if [ -z "$INSTANCES" ]; then
        echo -e "${YELLOW}No EC2 instances found${NC}"
        return
    fi
    
    echo -e "${GREEN}Instance ID\t\tType\t\tState\t\tPublic IP\tPrivate IP\tName${NC}"
    echo "--------------------------------------------------------------------------------------------------------"
    echo "$INSTANCES" | while IFS=$'\t' read -r id type state public_ip private_ip name; do
        if [ "$state" == "running" ]; then
            echo -e "${GREEN}$id\t$type\t$state\t\t$public_ip\t$private_ip\t$name${NC}"
        elif [ "$state" == "stopped" ]; then
            echo -e "${YELLOW}$id\t$type\t$state\t\t$public_ip\t$private_ip\t$name${NC}"
        else
            echo -e "$id\t$type\t$state\t\t$public_ip\t$private_ip\t$name"
        fi
    done
}

# Function to create EC2 instance
create_instance() {
    echo -e "${BLUE}Create New EC2 Instance${NC}"
    echo ""
    
    # Get AMI (Amazon Linux 2023 by default)
    read -p "Enter AMI ID (press Enter for Amazon Linux 2023 in current region): " AMI_ID
    if [ -z "$AMI_ID" ]; then
        echo "Getting latest Amazon Linux 2023 AMI..."
        AMI_ID=$(aws ec2 describe-images \
            --owners amazon \
            --filters "Name=name,Values=al2023-ami-2023*-x86_64" \
            --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
            --output text)
        echo "Using AMI: $AMI_ID"
    fi
    
    # Get instance type
    read -p "Enter instance type (default: t2.micro): " INSTANCE_TYPE
    INSTANCE_TYPE=${INSTANCE_TYPE:-t2.micro}
    
    # Get key pair name
    read -p "Enter key pair name (optional): " KEY_NAME
    
    # Get security group
    read -p "Enter security group ID (optional): " SECURITY_GROUP
    
    # Get subnet
    read -p "Enter subnet ID (optional): " SUBNET_ID
    
    # Get instance name
    read -p "Enter instance name tag: " INSTANCE_NAME
    
    # Build command
    CMD="aws ec2 run-instances --image-id $AMI_ID --instance-type $INSTANCE_TYPE --count 1"
    
    if [ ! -z "$KEY_NAME" ]; then
        CMD="$CMD --key-name $KEY_NAME"
    fi
    
    if [ ! -z "$SECURITY_GROUP" ]; then
        CMD="$CMD --security-group-ids $SECURITY_GROUP"
    fi
    
    if [ ! -z "$SUBNET_ID" ]; then
        CMD="$CMD --subnet-id $SUBNET_ID"
    fi
    
    if [ ! -z "$INSTANCE_NAME" ]; then
        CMD="$CMD --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]'"
    fi
    
    echo ""
    echo -e "${YELLOW}Creating instance...${NC}"
    
    RESULT=$(eval $CMD)
    INSTANCE_ID=$(echo $RESULT | jq -r '.Instances[0].InstanceId')
    
    if [ ! -z "$INSTANCE_ID" ]; then
        echo -e "${GREEN}✓ Instance created successfully!${NC}"
        echo "Instance ID: $INSTANCE_ID"
        echo ""
        echo "Waiting for instance to start..."
        aws ec2 wait instance-running --instance-ids $INSTANCE_ID
        echo -e "${GREEN}✓ Instance is now running${NC}"
        
        # Get instance details
        PUBLIC_IP=$(aws ec2 describe-instances \
            --instance-ids $INSTANCE_ID \
            --query 'Reservations[0].Instances[0].PublicIpAddress' \
            --output text)
        
        if [ "$PUBLIC_IP" != "None" ]; then
            echo "Public IP: $PUBLIC_IP"
        fi
    else
        echo -e "${RED}✗ Failed to create instance${NC}"
    fi
}

# Function to remove/terminate instance
remove_instance() {
    INSTANCE_ID=$1
    
    if [ -z "$INSTANCE_ID" ]; then
        echo -e "${YELLOW}Available instances:${NC}"
        list_instances
        echo ""
        read -p "Enter instance ID to terminate: " INSTANCE_ID
    fi
    
    if [ -z "$INSTANCE_ID" ]; then
        echo -e "${RED}Error: Instance ID is required${NC}"
        exit 1
    fi
    
    # Verify instance exists
    if ! aws ec2 describe-instances --instance-ids $INSTANCE_ID &> /dev/null; then
        echo -e "${RED}Error: Instance $INSTANCE_ID not found${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}WARNING: This will terminate instance $INSTANCE_ID${NC}"
    read -p "Are you sure? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "Operation cancelled"
        exit 0
    fi
    
    echo "Terminating instance..."
    aws ec2 terminate-instances --instance-ids $INSTANCE_ID > /dev/null
    
    echo -e "${GREEN}✓ Instance $INSTANCE_ID is being terminated${NC}"
}

# Function to start instance
start_instance() {
    INSTANCE_ID=$1
    
    if [ -z "$INSTANCE_ID" ]; then
        echo -e "${YELLOW}Available stopped instances:${NC}"
        aws ec2 describe-instances \
            --filters "Name=instance-state-name,Values=stopped" \
            --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
            --output text
        echo ""
        read -p "Enter instance ID to start: " INSTANCE_ID
    fi
    
    if [ -z "$INSTANCE_ID" ]; then
        echo -e "${RED}Error: Instance ID is required${NC}"
        exit 1
    fi
    
    echo "Starting instance $INSTANCE_ID..."
    aws ec2 start-instances --instance-ids $INSTANCE_ID > /dev/null
    
    echo -e "${GREEN}✓ Instance $INSTANCE_ID is starting${NC}"
    echo "Waiting for instance to be running..."
    aws ec2 wait instance-running --instance-ids $INSTANCE_ID
    echo -e "${GREEN}✓ Instance is now running${NC}"
}

# Function to stop instance
stop_instance() {
    INSTANCE_ID=$1
    
    if [ -z "$INSTANCE_ID" ]; then
        echo -e "${YELLOW}Available running instances:${NC}"
        aws ec2 describe-instances \
            --filters "Name=instance-state-name,Values=running" \
            --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
            --output text
        echo ""
        read -p "Enter instance ID to stop: " INSTANCE_ID
    fi
    
    if [ -z "$INSTANCE_ID" ]; then
        echo -e "${RED}Error: Instance ID is required${NC}"
        exit 1
    fi
    
    echo "Stopping instance $INSTANCE_ID..."
    aws ec2 stop-instances --instance-ids $INSTANCE_ID > /dev/null
    
    echo -e "${GREEN}✓ Instance $INSTANCE_ID is stopping${NC}"
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
        list_instances
        ;;
    create)
        create_instance
        ;;
    remove|terminate)
        remove_instance "$@"
        ;;
    start)
        start_instance "$@"
        ;;
    stop)
        stop_instance "$@"
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
