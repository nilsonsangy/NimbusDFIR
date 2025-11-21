#!/usr/bin/env bash

# =============================================================
# Azure Storage Account Manager
# Cross-platform: macOS (Bash 5+) + Linux
# =============================================================

# Colors
GREEN="$(tput setaf 2)"
YELLOW="$(tput setaf 3)"
RED="$(tput setaf 1)"
BLUE="$(tput setaf 4)"
NC="$(tput sgr0)"

# Default options
DEFAULT_LOCATION="eastus"
DEFAULT_SKU="Standard_LRS"
DEFAULT_KIND="StorageV2"

# Arrays
LOCATIONS=("eastus" "centralus" "westus" "eastus2" "southcentralus")
SKUS=("Standard_LRS" "Standard_GRS" "Standard_RAGRS" "Standard_ZRS" "Premium_LRS")
KINDS=("StorageV2" "Storage" "BlobStorage" "FileStorage" "BlockBlobStorage")

# -------------------------------------------------------------
banner() {
    echo "${BLUE}==============================================${NC}"
    echo "${GREEN}        Azure Storage Account Manager         ${NC}"
    echo "${BLUE}==============================================${NC}"
}

# -------------------------------------------------------------
pause() {
    echo
    read -rp "Press ENTER to continue..." _
}

# -------------------------------------------------------------
# Function to select from array
# Works for macOS Bash 5+ and Linux
# $1 = array name
# $2 = default value
select_from_list() {
    local array_name="$1"
    local default="$2"
    local arr
    eval "arr=(\"\${${array_name}[@]}\")"
    local size=${#arr[@]}

    echo >&2
    for i in "${!arr[@]}"; do
        local num=$((i+1))
        if [[ "${arr[i]}" == "$default" ]]; then
            echo "  ${BLUE}${num}) ${arr[i]} (default)${NC}" >&2
        else
            echo "  ${BLUE}${num}) ${arr[i]}${NC}" >&2
        fi
    done

    local choice
    read -rp "Choose an option (ENTER for default: $default): " choice

    # ENTER = default
    if [[ -z "$choice" ]]; then
        echo "$default"
        return
    fi

    # Numeric input
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice>=1 && choice<=size)); then
        echo "${arr[$((choice-1))]}"
        return
    fi

    # Exact text match
    for val in "${arr[@]}"; do
        if [[ "$val" == "$choice" ]]; then
            echo "$val"
            return
        fi
    done

    # Invalid input = default
    echo "$default"
}

# -------------------------------------------------------------
list_storage_accounts() {
    echo "${YELLOW}Fetching Storage Accounts from all Resource Groups...${NC}"
    storage_accounts=$(az storage account list --query '[].{name:name, rg:resourceGroup}' -o tsv)

    if [[ -z "$storage_accounts" ]]; then
        echo "${RED}No Storage Accounts found.${NC}"
        return 1
    fi

    echo "${GREEN}Storage Accounts found:${NC}"
    echo "ID    Storage Account                          Resource Group"
    echo "---------------------------------------------------------------"

    index=1
    while IFS=$'\t' read -r name rg; do
        if [[ -n "$name" && -n "$rg" ]] && [[ ! "$name" =~ ^- ]]; then
            echo "$index    $name                              $rg"
            ((index++))
        fi
    done <<< "$storage_accounts"
    echo
}

# -------------------------------------------------------------
create_storage_account() {
    echo "${GREEN}Create new Storage Account${NC}"

    echo "${YELLOW}Fetching Resource Groups...${NC}"
    rgs=($(az group list --query '[].name' -o tsv))

    echo "Available Resource Groups:"
    for i in "${!rgs[@]}"; do
        echo "  $((i+1))) ${rgs[i]}"
    done
    echo "  0) Create NEW Resource Group"
    echo

    read -rp "Choose a Resource Group option: " rg_choice

    if [[ "$rg_choice" == "0" ]]; then
        read -rp "Enter new Resource Group name: " RG
        read -rp "Location for new RG (ENTER for $DEFAULT_LOCATION): " RG_LOCATION
        RG_LOCATION=${RG_LOCATION:-$DEFAULT_LOCATION}
        echo "${YELLOW}Creating Resource Group...${NC}"
        az group create --name "$RG" --location "$RG_LOCATION"
    else
        idx=$((rg_choice-1))
        RG="${rgs[$idx]}"
        if [[ -z "$RG" ]]; then
            echo "${RED}Invalid Resource Group selection.${NC}"
            return 1
        fi
    fi

    read -rp "Storage Account name (lowercase, 3-24 chars): " SA_NAME
    if [[ -z "$SA_NAME" ]]; then
        echo "${RED}Name is required.${NC}"
        return 1
    fi

    # Select Location, SKU, Kind
    LOCATION=$(select_from_list "LOCATIONS" "$DEFAULT_LOCATION")
    SKU=$(select_from_list "SKUS" "$DEFAULT_SKU")
    KIND=$(select_from_list "KINDS" "$DEFAULT_KIND")

    echo "${YELLOW}Creating Storage Account...${NC}"
    az storage account create \
        --name "$SA_NAME" \
        --resource-group "$RG" \
        --location "$LOCATION" \
        --sku "$SKU" \
        --kind "$KIND"

    if [[ $? -eq 0 ]]; then
        echo "${GREEN}Storage Account created successfully!${NC}"
    else
        echo "${RED}Failed to create Storage Account.${NC}"
    fi
}

# -------------------------------------------------------------
delete_storage_account() {
    if [[ -z "$1" ]]; then
        # List and select if no argument
        list_storage_accounts || return 1
        read -rp "Enter the ID of the Storage Account to delete: " choice
        mapfile -t storage_accounts < <(az storage account list --query '[].{name:name, rg:resourceGroup}' -o tsv)
        idx=$((choice-1))
        if [[ $idx -lt 0 || $idx -ge ${#storage_accounts[@]} ]]; then
            echo "${RED}Invalid selection.${NC}"
            return 1
        fi
        selected="${storage_accounts[$idx]}"
        SA_NAME=$(echo "$selected" | awk '{print $1}')
        RG=$(echo "$selected" | awk '{print $2}')
    else
        # Direct deletion
        SA_NAME="$1"
        RG=$(az storage account show --name "$SA_NAME" --query 'resourceGroup' -o tsv)
    fi

    echo "${RED}Are you sure you want to delete:${NC}"
    echo "  Storage Account: ${YELLOW}$SA_NAME${NC}"
    echo "  Resource Group:  ${YELLOW}$RG${NC}"
    read -rp "Confirm deletion? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "${YELLOW}Operation cancelled.${NC}"
        return 1
    fi

    echo "${YELLOW}Deleting Storage Account...${NC}"
    az storage account delete --name "$SA_NAME" --resource-group "$RG" --yes

    if [[ $? -eq 0 ]]; then
        echo "${GREEN}Storage Account deleted successfully!${NC}"
    else
        echo "${RED}Error deleting Storage Account.${NC}"
    fi
}

# -------------------------------------------------------------
# Main CLI
# Usage: ./script.sh [command] [arguments]
case "$1" in
    list)
        banner
        list_storage_accounts
        ;;
    create)
        banner
        create_storage_account
        ;;
    delete)
        banner
        delete_storage_account "$2"
        ;;
    help|--help|-h|*)
        echo "Usage: $0 [COMMAND] [OPTIONS]"
        echo
        echo "Commands:"
        echo "  list              List all Storage Accounts"
        echo "  create            Create a new Storage Account"
        echo "  delete [NAME]     Delete a Storage Account (select if NAME omitted)"
        echo "  help              Show this help message"
        echo
        echo "Examples:"
        echo "  $0 list"
        echo "  $0 create"
        echo "  $0 delete my-storage-account"
        ;;
esac
