#!/bin/bash

# Azure VM Manager Script
# Author: NimbusDFIR
# Description: Manage Azure VMs - list, create, start, stop, and delete VMs

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
    echo "Azure VM Manager - NimbusDFIR"
    echo -e "==========================================${NC}"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  list              List all VMs in current subscription"
    echo "  create            Create a new VM"
    echo "  delete            Delete a VM"
    echo "  start             Start a stopped VM"
    echo "  stop              Stop a running VM (deallocate)"
    echo "  help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 create"
    echo "  $0 delete myVM"
    echo "  $0 start myVM"
    echo "  $0 stop myVM"
    echo ""
}

# Function to list VMs
list_vms() {
    echo -e "${BLUE}Listing Azure VMs...${NC}"
    echo ""
    
    VMS=$(az vm list --output json 2>/dev/null)
    
    if [ "$VMS" == "[]" ] || [ -z "$VMS" ]; then
        echo -e "${YELLOW}No VMs found in current subscription${NC}"
        return
    fi
    
    echo -e "${CYAN}VM Name\t\t\tResource Group\t\tLocation\tSize\t\tState${NC}"
    echo "----------------------------------------------------------------------------------------"
    
    echo "$VMS" | jq -r '.[] | [.name, .resourceGroup, .location, .hardwareProfile.vmSize] | @tsv' | while IFS=$'\t' read -r name rg location size; do
        # Get power state
        POWER_STATE=$(az vm get-instance-view --name "$name" --resource-group "$rg" --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>/dev/null)
        
        if [[ "$POWER_STATE" == *"running"* ]]; then
            echo -e "${GREEN}$name\t\t$rg\t\t$location\t$size\t$POWER_STATE${NC}"
        elif [[ "$POWER_STATE" == *"stopped"* ]] || [[ "$POWER_STATE" == *"deallocated"* ]]; then
            echo -e "${YELLOW}$name\t\t$rg\t\t$location\t$size\t$POWER_STATE${NC}"
        else
            echo -e "$name\t\t$rg\t\t$location\t$size\t$POWER_STATE"
        fi
    done
}

# Function to create VM
create_vm() {
    echo -e "${BLUE}Create New Azure VM${NC}"
    echo ""
    
    # Get VM name
    read -p "Enter VM name (default: azure-vm-$(date +%s)): " VM_NAME
    VM_NAME=${VM_NAME:-azure-vm-$(date +%s)}
    
    # Get or create resource group
    echo ""
    echo -e "${CYAN}Available Resource Groups:${NC}"
    RG_LIST=$(az group list --query "[].{Name:name, Location:location}" -o json)
    
    if [ "$RG_LIST" != "[]" ]; then
        echo "$RG_LIST" | jq -r '.[] | "\(.Name) (\(.Location))"' | nl -w2 -s'. '
    else
        echo "  No resource groups found"
    fi
    
    echo ""
    read -p "Enter resource group name or number (default: rg-forensics): " RG_INPUT
    if [ -z "$RG_INPUT" ]; then
        RG_NAME="rg-forensics"
    elif [[ "$RG_INPUT" =~ ^[0-9]+$ ]]; then
        RG_INDEX=$((RG_INPUT-1))
        RG_COUNT=$(echo "$RG_LIST" | jq length)
        if [ $RG_INDEX -ge 0 ] && [ $RG_INDEX -lt $RG_COUNT ]; then
            RG_NAME=$(echo "$RG_LIST" | jq -r ".[$RG_INDEX].Name")
        else
            echo -e "${YELLOW}Invalid resource group number. Using default: rg-forensics${NC}"
            RG_NAME="rg-forensics"
        fi
    else
        RG_NAME="$RG_INPUT"
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RG_NAME" &> /dev/null; then
        echo -e "${YELLOW}Resource group does not exist. Creating...${NC}"
        read -p "Enter location (default: northcentralus): " LOCATION
        LOCATION=${LOCATION:-northcentralus}
        az group create --name "$RG_NAME" --location "$LOCATION" --output table
        echo -e "${GREEN}✓ Resource group created${NC}"
    else
        LOCATION=$(az group show --name "$RG_NAME" --query location -o tsv)
    fi
    
    # Get VM size
    echo ""
    echo -e "${CYAN}Select VM Size:${NC}"
    echo "  1. Standard_B1s   - 1 vCPU, 1 GB RAM  (Lowest cost)"
    echo "  2. Standard_B1ms  - 1 vCPU, 2 GB RAM"
    echo "  3. Standard_B2s   - 2 vCPU, 4 GB RAM"
    echo "  4. Standard_D2s_v3 - 2 vCPU, 8 GB RAM"
    echo ""
    read -p "Choose VM size [1-4] (default: 1): " VM_SIZE_CHOICE
    VM_SIZE_CHOICE=${VM_SIZE_CHOICE:-1}
    
    case $VM_SIZE_CHOICE in
        1) VM_SIZE="Standard_B1s" ;;
        2) VM_SIZE="Standard_B1ms" ;;
        3) VM_SIZE="Standard_B2s" ;;
        4) VM_SIZE="Standard_D2s_v3" ;;
        *) VM_SIZE="Standard_B1s" ;;
    esac
    
    # Get image
    echo ""
    echo -e "${CYAN}Select Image:${NC}"
    echo "  1. Ubuntu2204     - Ubuntu 22.04 LTS"
    echo "  2. Ubuntu2404     - Ubuntu 24.04 LTS"
    echo "  3. Debian11       - Debian 11"
    echo "  4. Win2022Datacenter - Windows Server 2022"
    echo "  5. Win2019Datacenter - Windows Server 2019"
    echo ""
    read -p "Choose image [1-5] (default: 1): " IMAGE_CHOICE
    IMAGE_CHOICE=${IMAGE_CHOICE:-1}
    
    case $IMAGE_CHOICE in
        1) IMAGE="Ubuntu2204" ;;
        2) IMAGE="Ubuntu2404" ;;
        3) IMAGE="Debian11" ;;
        4) IMAGE="Win2022Datacenter" ;;
        5) IMAGE="Win2019Datacenter" ;;
        *) IMAGE="Ubuntu2204" ;;
    esac
    
    # Get authentication
    echo ""
    read -p "Enter admin username (default: azureuser): " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-azureuser}
    
    echo ""
    echo -e "${CYAN}Authentication Method:${NC}"
    echo "  1. SSH key (Linux VMs)"
    echo "  2. Password"
    echo ""
    read -p "Choose authentication method [1-2] (default: 1): " AUTH_METHOD
    AUTH_METHOD=${AUTH_METHOD:-1}
    
    # Build command
    CMD="az vm create --name $VM_NAME --resource-group $RG_NAME --location $LOCATION --size $VM_SIZE --image $IMAGE --admin-username $ADMIN_USER"
    
    if [ "$AUTH_METHOD" == "1" ]; then
        CMD="$CMD --generate-ssh-keys"
    else
        read -sp "Enter admin password: " ADMIN_PASSWORD
        echo ""
        CMD="$CMD --admin-password '$ADMIN_PASSWORD'"
    fi
    
    # Ask about public IP
    echo ""
    read -p "Assign public IP? (y/N): " PUBLIC_IP
    PUBLIC_IP=${PUBLIC_IP:-n}
    if [ "$PUBLIC_IP" != "y" ] && [ "$PUBLIC_IP" != "Y" ]; then
        CMD="$CMD --public-ip-address ''"
    fi
    
    echo ""
    echo -e "${YELLOW}Creating VM... (this may take a few minutes)${NC}"
    echo -e "${BLUE}[INFO]${NC} VM: $VM_NAME | Size: $VM_SIZE | Image: $IMAGE | Location: $LOCATION"
    echo ""
    
    eval $CMD
    
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ VM created successfully!${NC}"
        echo ""
        
        # Get VM details
        echo -e "${CYAN}VM Details:${NC}"
        az vm show --name "$VM_NAME" --resource-group "$RG_NAME" --show-details --query "{Name:name, ResourceGroup:resourceGroup, Location:location, Size:hardwareProfile.vmSize, PublicIP:publicIps, PrivateIP:privateIps}" -o table
    else
        echo -e "${RED}✗ Failed to create VM${NC}"
        exit 1
    fi
}

# Function to delete VM
delete_vm() {
    local VM_NAME=$1
    
    if [ -z "$VM_NAME" ]; then
        # List VMs and let user choose
        echo -e "${CYAN}Available VMs to delete:${NC}"
        echo ""
        
        VMS=$(az vm list --output json 2>/dev/null)
        
        if [ "$VMS" == "[]" ] || [ -z "$VMS" ]; then
            echo -e "${YELLOW}No VMs found in current subscription${NC}"
            exit 0
        fi
        
        # Get all VMs with their status
        ALL_VMS=$(echo "$VMS" | jq -r '.[] | select(.name != null) | .name + "|" + .resourceGroup + "|" + .location')
        
        rm -f /tmp/all_vms.txt
        COUNT=0
        
        echo "$ALL_VMS" | while IFS='|' read -r vm_name rg_name location; do
            if [ -n "$vm_name" ]; then
                # Get power state
                POWER_STATE=$(az vm get-instance-view --name "$vm_name" --resource-group "$rg_name" --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>/dev/null)
                
                COUNT=$((COUNT + 1))
                echo "$COUNT|$vm_name|$rg_name|$location|$POWER_STATE" >> /tmp/all_vms.txt
            fi
        done
        
        if [ ! -f /tmp/all_vms.txt ] || [ ! -s /tmp/all_vms.txt ]; then
            echo -e "${YELLOW}No VMs found${NC}"
            exit 0
        fi
        
        # Display numbered list of all VMs with status
        while IFS='|' read -r num vm_name rg_name location power_state; do
            if [[ "$power_state" == *"running"* ]]; then
                echo -e "  ${GREEN}$num. $vm_name ($rg_name) - $location [$power_state]${NC}"
            elif [[ "$power_state" == *"stopped"* ]] || [[ "$power_state" == *"deallocated"* ]]; then
                echo -e "  ${YELLOW}$num. $vm_name ($rg_name) - $location [$power_state]${NC}"
            else
                echo -e "  $num. $vm_name ($rg_name) - $location [$power_state]"
            fi
        done < /tmp/all_vms.txt
        
        TOTAL_VMS=$(wc -l < /tmp/all_vms.txt)
        
        echo ""
        read -p "Select VM to delete [1-$TOTAL_VMS] or 0 to cancel: " SELECTION
        
        if [ "$SELECTION" == "0" ] || [ -z "$SELECTION" ]; then
            echo -e "${YELLOW}Operation cancelled${NC}"
            rm -f /tmp/all_vms.txt
            exit 0
        fi
        
        # Validate selection
        if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "$TOTAL_VMS" ]; then
            echo -e "${RED}Invalid selection${NC}"
            rm -f /tmp/all_vms.txt
            exit 1
        fi
        
        # Get selected VM info
        SELECTED_LINE=$(sed -n "${SELECTION}p" /tmp/all_vms.txt)
        VM_NAME=$(echo "$SELECTED_LINE" | cut -d'|' -f2)
        RG_NAME=$(echo "$SELECTED_LINE" | cut -d'|' -f3)
        
        rm -f /tmp/all_vms.txt
    else
        # Find VM and get resource group
        echo -e "${BLUE}Finding VM: $VM_NAME${NC}"
        VM_INFO=$(az vm list --query "[?name=='$VM_NAME']" -o json)
        
        if [ "$VM_INFO" == "[]" ]; then
            echo -e "${RED}Error: VM '$VM_NAME' not found${NC}"
            exit 1
        fi
        
        RG_NAME=$(echo "$VM_INFO" | jq -r '.[0].resourceGroup')
    fi
    
    echo -e "${YELLOW}VM found in resource group: $RG_NAME${NC}"
    echo ""
    read -p "Are you sure you want to delete VM '$VM_NAME'? (y/N): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "Deletion cancelled"
        exit 0
    fi
    
    echo ""
    echo -e "${YELLOW}Deleting VM and associated resources...${NC}"
    
    # Delete VM and associated resources
    az vm delete --name "$VM_NAME" --resource-group "$RG_NAME" --yes
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ VM deleted successfully${NC}"
        
        # Ask to delete associated resources
        read -p "Delete associated NICs and disks? (y/n): " DELETE_RESOURCES
        if [ "$DELETE_RESOURCES" == "y" ]; then
            echo -e "${YELLOW}Cleaning up all associated resources...${NC}"
            echo ""
            
            # Delete NICs
            echo -e "${BLUE}[INFO] Deleting Network Interfaces...${NC}"
            az network nic list --resource-group "$RG_NAME" --query "[?contains(name, '$VM_NAME')].[name]" -o tsv | while read nic; do
                if [ -n "$nic" ]; then
                    echo -e "${YELLOW}  Deleting NIC: $nic${NC}"
                    if az network nic delete --resource-group "$RG_NAME" --name "$nic"; then
                        echo -e "${GREEN}    ✓ NIC deleted: $nic${NC}"
                    else
                        echo -e "${RED}    ✗ Failed to delete NIC: $nic${NC}"
                    fi
                fi
            done
            
            # Delete Public IPs
            echo -e "${BLUE}[INFO] Deleting Public IP addresses...${NC}"
            az network public-ip list --resource-group "$RG_NAME" --query "[?contains(name, '$VM_NAME')].[name]" -o tsv | while read public_ip; do
                if [ -n "$public_ip" ]; then
                    echo -e "${YELLOW}  Deleting Public IP: $public_ip${NC}"
                    if az network public-ip delete --resource-group "$RG_NAME" --name "$public_ip"; then
                        echo -e "${GREEN}    ✓ Public IP deleted: $public_ip${NC}"
                    else
                        echo -e "${RED}    ✗ Failed to delete Public IP: $public_ip${NC}"
                    fi
                fi
            done
            
            # Delete Network Security Groups
            echo -e "${BLUE}[INFO] Deleting Network Security Groups...${NC}"
            az network nsg list --resource-group "$RG_NAME" --query "[?contains(name, '$VM_NAME')].[name]" -o tsv | while read nsg; do
                if [ -n "$nsg" ]; then
                    echo -e "${YELLOW}  Deleting NSG: $nsg${NC}"
                    if az network nsg delete --resource-group "$RG_NAME" --name "$nsg"; then
                        echo -e "${GREEN}    ✓ NSG deleted: $nsg${NC}"
                    else
                        echo -e "${RED}    ✗ Failed to delete NSG: $nsg${NC}"
                    fi
                fi
            done
            
            # Delete Disks
            echo -e "${BLUE}[INFO] Deleting Disks...${NC}"
            az disk list --resource-group "$RG_NAME" --query "[?contains(name, '$VM_NAME')].[name]" -o tsv | while read disk; do
                if [ -n "$disk" ]; then
                    echo -e "${YELLOW}  Deleting disk: $disk${NC}"
                    if az disk delete --resource-group "$RG_NAME" --name "$disk" --yes; then
                        echo -e "${GREEN}    ✓ Disk deleted: $disk${NC}"
                    else
                        echo -e "${RED}    ✗ Failed to delete disk: $disk${NC}"
                    fi
                fi
            done
            
            # Delete Virtual Networks (only if they are VM-specific)
            echo -e "${BLUE}[INFO] Checking Virtual Networks...${NC}"
            az network vnet list --resource-group "$RG_NAME" --query "[?contains(name, '$VM_NAME')].[name]" -o tsv | while read vnet; do
                if [ -n "$vnet" ]; then
                    echo -e "${YELLOW}  Deleting VNET: $vnet${NC}"
                    if az network vnet delete --resource-group "$RG_NAME" --name "$vnet"; then
                        echo -e "${GREEN}    ✓ VNET deleted: $vnet${NC}"
                    else
                        echo -e "${RED}    ✗ Failed to delete VNET: $vnet${NC}"
                    fi
                fi
            done
            
            echo ""
            echo -e "${GREEN}✓ All resources cleanup completed${NC}"
        fi
    else
        echo -e "${RED}✗ Failed to delete VM${NC}"
        exit 1
    fi
}

# Function to start VM
start_vm() {
    local VM_NAME=$1
    
    if [ -z "$VM_NAME" ]; then
        # List VMs and let user choose
        echo -e "${CYAN}Available VMs to start:${NC}"
        echo ""
        
        VMS=$(az vm list --output json 2>/dev/null)
        
        if [ "$VMS" == "[]" ] || [ -z "$VMS" ]; then
            echo -e "${YELLOW}No VMs found in current subscription${NC}"
            exit 0
        fi
        
        # Filter only stopped VMs
        STOPPED_VMS=$(echo "$VMS" | jq -r '.[] | select(.name != null) | .name + "|" + .resourceGroup + "|" + .location')
        STOPPED_LIST=""
        COUNT=0
        
        rm -f /tmp/stopped_vms.txt
        
        echo "$STOPPED_VMS" | while IFS='|' read -r vm_name rg_name location; do
            if [ -n "$vm_name" ]; then
                # Get power state
                POWER_STATE=$(az vm get-instance-view --name "$vm_name" --resource-group "$rg_name" --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>/dev/null)
                
                if [[ "$POWER_STATE" == *"stopped"* ]] || [[ "$POWER_STATE" == *"deallocated"* ]]; then
                    COUNT=$((COUNT + 1))
                    echo "$COUNT|$vm_name|$rg_name|$location" >> /tmp/stopped_vms.txt
                fi
            fi
        done
        
        if [ ! -f /tmp/stopped_vms.txt ] || [ ! -s /tmp/stopped_vms.txt ]; then
            echo -e "${YELLOW}No stopped VMs found to start${NC}"
            exit 0
        fi
        
        # Display numbered list of stopped VMs
        while IFS='|' read -r num vm_name rg_name location; do
            echo -e "  $num. $vm_name ($rg_name) - $location"
        done < /tmp/stopped_vms.txt
        
        TOTAL_STOPPED=$(wc -l < /tmp/stopped_vms.txt)
        
        echo ""
        read -p "Select VM to start [1-$TOTAL_STOPPED] or 0 to cancel: " SELECTION
        
        if [ "$SELECTION" == "0" ] || [ -z "$SELECTION" ]; then
            echo -e "${YELLOW}Operation cancelled${NC}"
            rm -f /tmp/stopped_vms.txt
            exit 0
        fi
        
        # Validate selection
        if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "$TOTAL_STOPPED" ]; then
            echo -e "${RED}Invalid selection${NC}"
            rm -f /tmp/stopped_vms.txt
            exit 1
        fi
        
        # Get selected VM info
        SELECTED_LINE=$(sed -n "${SELECTION}p" /tmp/stopped_vms.txt)
        VM_NAME=$(echo "$SELECTED_LINE" | cut -d'|' -f2)
        RG_NAME=$(echo "$SELECTED_LINE" | cut -d'|' -f3)
        
        rm -f /tmp/stopped_vms.txt
    else
        # Find VM and get resource group
        VM_INFO=$(az vm list --query "[?name=='$VM_NAME']" -o json)
        
        if [ "$VM_INFO" == "[]" ]; then
            echo -e "${RED}Error: VM '$VM_NAME' not found${NC}"
            exit 1
        fi
        
        RG_NAME=$(echo "$VM_INFO" | jq -r '.[0].resourceGroup')
    fi
    
    echo -e "${YELLOW}Starting VM: $VM_NAME${NC}"
    az vm start --name "$VM_NAME" --resource-group "$RG_NAME"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ VM started successfully${NC}"
    else
        echo -e "${RED}✗ Failed to start VM${NC}"
        exit 1
    fi
}

# Function to stop VM
stop_vm() {
    local VM_NAME=$1
    
    if [ -z "$VM_NAME" ]; then
        # List VMs and let user choose
        echo -e "${CYAN}Available VMs to stop:${NC}"
        echo ""
        
        VMS=$(az vm list --output json 2>/dev/null)
        
        if [ "$VMS" == "[]" ] || [ -z "$VMS" ]; then
            echo -e "${YELLOW}No VMs found in current subscription${NC}"
            exit 0
        fi
        
        # Filter only running VMs
        RUNNING_VMS=$(echo "$VMS" | jq -r '.[] | select(.name != null) | .name + "|" + .resourceGroup + "|" + .location')
        RUNNING_LIST=""
        COUNT=0
        
        echo "$RUNNING_VMS" | while IFS='|' read -r vm_name rg_name location; do
            if [ -n "$vm_name" ]; then
                # Get power state
                POWER_STATE=$(az vm get-instance-view --name "$vm_name" --resource-group "$rg_name" --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>/dev/null)
                
                if [[ "$POWER_STATE" == *"running"* ]]; then
                    COUNT=$((COUNT + 1))
                    echo "$COUNT|$vm_name|$rg_name|$location" >> /tmp/running_vms.txt
                fi
            fi
        done
        
        if [ ! -f /tmp/running_vms.txt ] || [ ! -s /tmp/running_vms.txt ]; then
            echo -e "${YELLOW}No running VMs found to stop${NC}"
            exit 0
        fi
        
        # Display numbered list of running VMs
        while IFS='|' read -r num vm_name rg_name location; do
            echo -e "  $num. $vm_name ($rg_name) - $location"
        done < /tmp/running_vms.txt
        
        TOTAL_RUNNING=$(wc -l < /tmp/running_vms.txt)
        
        echo ""
        read -p "Select VM to stop [1-$TOTAL_RUNNING] or 0 to cancel: " SELECTION
        
        if [ "$SELECTION" == "0" ] || [ -z "$SELECTION" ]; then
            echo -e "${YELLOW}Operation cancelled${NC}"
            rm -f /tmp/running_vms.txt
            exit 0
        fi
        
        # Validate selection
        if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "$TOTAL_RUNNING" ]; then
            echo -e "${RED}Invalid selection${NC}"
            rm -f /tmp/running_vms.txt
            exit 1
        fi
        
        # Get selected VM info
        SELECTED_LINE=$(sed -n "${SELECTION}p" /tmp/running_vms.txt)
        VM_NAME=$(echo "$SELECTED_LINE" | cut -d'|' -f2)
        RG_NAME=$(echo "$SELECTED_LINE" | cut -d'|' -f3)
        
        rm -f /tmp/running_vms.txt
    else
        # Find VM and get resource group
        VM_INFO=$(az vm list --query "[?name=='$VM_NAME']" -o json)
        
        if [ "$VM_INFO" == "[]" ]; then
            echo -e "${RED}Error: VM '$VM_NAME' not found${NC}"
            exit 1
        fi
        
        RG_NAME=$(echo "$VM_INFO" | jq -r '.[0].resourceGroup')
    fi
    
    echo -e "${YELLOW}Stopping and deallocating VM: $VM_NAME${NC}"
    az vm deallocate --name "$VM_NAME" --resource-group "$RG_NAME"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ VM stopped and deallocated successfully${NC}"
    else
        echo -e "${RED}✗ Failed to stop VM${NC}"
        exit 1
    fi
}

# Main script logic
case "$1" in
    list)
        list_vms
        ;;
    create)
        create_vm
        ;;
    delete)
        delete_vm "$2"
        ;;
    start)
        start_vm "$2"
        ;;
    stop)
        stop_vm "$2"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
