#!/bin/bash

# Script to test Azure CLI connection
# Author: NimbusDFIR
# Description: Tests Azure connection and displays account information

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================="
echo "Azure Connection Test - NimbusDFIR"
echo -e "==========================================${NC}"
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Azure CLI is not installed"
    echo ""
    echo "To install Azure CLI, run:"
    echo -e "  ${GREEN}./install_azure_cli_macos.sh${NC}"
    exit 1
fi

# Check if logged in
echo -e "${BLUE}[INFO]${NC} Checking Azure authentication..."
az account show &> /dev/null

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} Not logged in to Azure"
    echo ""
    echo "Please log in first:"
    echo -e "  ${GREEN}az login${NC}"
    exit 1
fi

# Get account information
echo -e "${GREEN}[SUCCESS]${NC} Azure connection successful!"
echo ""

# Get account details
ACCOUNT_NAME=$(az account show --query name -o tsv 2>/dev/null)
ACCOUNT_ID=$(az account show --query id -o tsv 2>/dev/null)
TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null)
USER_NAME=$(az account show --query user.name -o tsv 2>/dev/null)
USER_TYPE=$(az account show --query user.type -o tsv 2>/dev/null)

echo -e "${CYAN}Account Information:${NC}"
echo "===================="
echo -e "  Account Name: ${GREEN}$ACCOUNT_NAME${NC}"
echo -e "  Subscription ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "  Tenant ID: ${GREEN}$TENANT_ID${NC}"
echo -e "  User: ${GREEN}$USER_NAME${NC}"
echo -e "  Type: ${GREEN}$USER_TYPE${NC}"
echo ""

# List all subscriptions
echo -e "${CYAN}Available Subscriptions:${NC}"
echo "===================="
az account list --query "[].{Name:name, ID:id, State:state, IsDefault:isDefault}" -o table 2>/dev/null
echo ""

# List available locations
echo -e "${CYAN}Available Locations (Regions):${NC}"
echo "===================="
az account list-locations --query "[].{Name:name, DisplayName:displayName}" -o table 2>/dev/null | head -20
echo "... (showing first 20 regions)"
echo ""

# Get Azure CLI version
AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null)
echo -e "${BLUE}[INFO]${NC} Azure CLI Version: ${GREEN}$AZ_VERSION${NC}"
echo ""

echo -e "${GREEN}[SUCCESS]${NC} All checks completed successfully!"
