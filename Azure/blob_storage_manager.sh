#!/usr/bin/env bash

# =============================================================
# Azure Blob Storage Manager
# Cross-platform: macOS (Bash 5+) + Linux
# =============================================================

# Colors
GREEN="$(tput setaf 2)"
YELLOW="$(tput setaf 3)"
RED="$(tput setaf 1)"
BLUE="$(tput setaf 4)"
NC="$(tput sgr0)"

# -------------------------------------------------------------
# Interactive deletion of any blob container from any storage account
delete_blob_container_interactive() {
    echo "${YELLOW}Fetching all Storage Accounts and Blob Containers...${NC}"
    get_all_blob_containers
    if [[ ${#containers_list[@]} -eq 0 ]]; then
        echo "${RED}No Blob Containers found in any Storage Account.${NC}"
        return 1
    fi
    printf "%-3s %-30s %-30s\n" "#" "Blob Container" "Storage Account"
    printf "%-3s %-30s %-30s\n" "---" "------------------------------" "------------------------------"
    for i in "${!containers_list[@]}"; do
        printf "%-3d %-30s %-30s\n" "$((i+1))" "${containers_list[i]}" "${containers_accounts[i]}"
    done
    echo
    read -rp "Enter the ID of the Blob Container to delete: " choice
    idx=$((choice-1))
    if [[ $idx -lt 0 || $idx -ge ${#containers_list[@]} ]]; then
        echo "${RED}Invalid selection.${NC}"
        return 1
    fi
    CONTAINER_NAME="${containers_list[$idx]}"
    STORAGE_ACCOUNT="${containers_accounts[$idx]}"
    echo "${RED}Are you sure you want to delete Blob Container '$CONTAINER_NAME' in Storage Account '$STORAGE_ACCOUNT'?${NC}"
    read -rp "Confirm deletion? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "${YELLOW}Operation cancelled.${NC}"
        return 1
    fi
    echo "${YELLOW}Deleting Blob Container '$CONTAINER_NAME' from '$STORAGE_ACCOUNT'...${NC}"
    az storage container delete --name "$CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT" --auth-mode login
    if [[ $? -eq 0 ]]; then
        echo "${GREEN}Blob Container deleted successfully!${NC}"
    else
        echo "${RED}Error deleting Blob Container.${NC}"
    fi
}
banner() {
    echo "${BLUE}==============================================${NC}"
    echo "${GREEN}          Azure Blob Storage Manager          ${NC}"
    echo "${BLUE}==============================================${NC}"
}

# -------------------------------------------------------------
pause() {
    echo
    read -rp "Press ENTER to continue..." _
}

# -------------------------------------------------------------
# Function to select from array
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

    if [[ -z "$choice" ]]; then
        echo "$default"
        return
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice>=1 && choice<=size)); then
        echo "${arr[$((choice-1))]}"
        return
    fi

    for val in "${arr[@]}"; do
        if [[ "$val" == "$choice" ]]; then
            echo "$val"
            return
        fi
    done

    echo "$default"
}

# -------------------------------------------------------------
list_blob_containers() {
    if [[ -z "$1" ]]; then
        echo "${RED}Storage Account name is required.${NC}"
        return 1
    fi

    echo "${YELLOW}Fetching Blob Containers from Storage Account '$1'...${NC}"
    containers=$(az storage container list --account-name "$1" --auth-mode login --query '[].name' -o tsv)

    if [[ -z "$containers" ]]; then
        echo "${RED}No Blob Containers found.${NC}"
        return 1
    fi

    echo "${GREEN}Blob Containers found in '$1':${NC}"
    index=1
    while IFS= read -r container; do
        echo "$index    $container"
        ((index++))
    done <<< "$containers"
    echo
}

# -------------------------------------------------------------
create_blob_container() {
    # Listar storage accounts para seleção
    accounts_str="$(az storage account list --query '[].name' -o tsv)"
    accounts=()
    while IFS= read -r line; do
        accounts+=("$line")
    done <<< "$accounts_str"
    if [[ ${#accounts[@]} -eq 0 ]]; then
        echo "${RED}No Storage Accounts found.${NC}"
        return 1
    fi
    echo "Available Storage Accounts:"
    for i in "${!accounts[@]}"; do
        echo "  $((i+1))) ${accounts[i]}"
    done
    read -rp "Select Storage Account (number): " acc_choice
    acc_idx=$((acc_choice-1))
    if [[ $acc_idx -lt 0 || $acc_idx -ge ${#accounts[@]} ]]; then
        echo "${RED}Invalid selection.${NC}"
        return 1
    fi
    STORAGE_ACCOUNT="${accounts[$acc_idx]}"

    read -rp "Enter new Blob Container name: " CONTAINER_NAME
    if [[ -z "$CONTAINER_NAME" ]]; then
        echo "${RED}Container name is required.${NC}"
        return 1
    fi

    echo "${YELLOW}Creating Blob Container '$CONTAINER_NAME' in Storage Account '$STORAGE_ACCOUNT'...${NC}"
    az storage container create --name "$CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT" --auth-mode login

    if [[ $? -eq 0 ]]; then
        echo "${GREEN}Blob Container created successfully!${NC}"
    else
        echo "${RED}Failed to create Blob Container.${NC}"
    fi
}

# -------------------------------------------------------------
delete_blob_container() {
    if [[ -z "$1" ]]; then
        echo "${RED}Storage Account name is required.${NC}"
        return 1
    fi

    # List containers to select
    containers=()
    az storage container list --account-name "$1" --auth-mode login --query '[].name' -o tsv | while IFS= read -r line; do
        containers+=("$line")
    done
    if [[ ${#containers[@]} -eq 0 ]]; then
        echo "${RED}No Blob Containers found in '$1'.${NC}"
        return 1
    fi

    echo "Available Blob Containers in '$1':"
    for i in "${!containers[@]}"; do
        echo "  $((i+1))) ${containers[i]}"
    done

    read -rp "Enter the ID of the Blob Container to delete: " choice
    idx=$((choice-1))
    if [[ $idx -lt 0 || $idx -ge ${#containers[@]} ]]; then
        echo "${RED}Invalid selection.${NC}"
        return 1
    fi

    CONTAINER_NAME="${containers[$idx]}"

    echo "${RED}Are you sure you want to delete Blob Container '$CONTAINER_NAME' in Storage Account '$1'?${NC}"
    read -rp "Confirm deletion? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "${YELLOW}Operation cancelled.${NC}"
        return 1
    fi

    echo "${YELLOW}Deleting Blob Container '$CONTAINER_NAME'...${NC}"
    az storage container delete --name "$CONTAINER_NAME" --account-name "$1" --yes

    if [[ $? -eq 0 ]]; then
        echo "${GREEN}Blob Container deleted successfully!${NC}"
    else
        echo "${RED}Error deleting Blob Container.${NC}"
    fi
}

# -------------------------------------------------------------
get_all_blob_containers() {
    accounts_str="$(az storage account list --query '[].name' -o tsv)"
    accounts=()
    while IFS= read -r line; do
        accounts+=("$line")
    done <<< "$accounts_str"
    containers_list=()
    containers_accounts=()
    for account in "${accounts[@]}"; do
        containers=$(az storage container list --account-name "$account" --auth-mode login --query '[].name' -o tsv)
        if [[ -n "$containers" ]]; then
            while IFS= read -r container; do
                containers_list+=("$container")
                containers_accounts+=("$account")
            done <<< "$containers"
        fi
    done
}

# -------------------------------------------------------------
list_all_blob_containers() {
    echo "${YELLOW}Fetching all Storage Accounts...${NC}"
    get_all_blob_containers
    if [[ ${#containers_list[@]} -eq 0 ]]; then
        echo "${RED}No Blob Containers found in any Storage Account.${NC}"
        return 1
    fi
    printf "%-3s %-30s %-30s\n" "#" "Blob Container" "Storage Account"
    printf "%-3s %-30s %-30s\n" "---" "------------------------------" "------------------------------"
    for i in "${!containers_list[@]}"; do
        printf "%-3d %-30s %-30s\n" "$((i+1))" "${containers_list[i]}" "${containers_accounts[i]}"
    done
}

# -------------------------------------------------------------
# Main CLI
# Usage: ./blob_manager.sh [command] [storage_account] 
case "$1" in
    list)
        banner
        if [[ -z "$2" ]]; then
            list_all_blob_containers
        else
            list_blob_containers "$2"
        fi
        ;;
    create)
        banner
        create_blob_container
        ;;
    delete)
        banner
        if [[ -z "$2" ]]; then
            delete_blob_container_interactive
        else
            # Search for the container name in all storage accounts
            get_all_blob_containers
            found_idx=-1
            for i in "${!containers_list[@]}"; do
                if [[ "${containers_list[$i]}" == "$2" ]]; then
                    found_idx=$i
                    break
                fi
            done
            if [[ $found_idx -eq -1 ]]; then
                echo "${RED}Blob Container '$2' not found in any Storage Account.${NC}"
                exit 1
            fi
            CONTAINER_NAME="${containers_list[$found_idx]}"
            STORAGE_ACCOUNT="${containers_accounts[$found_idx]}"
            echo "${RED}Are you sure you want to delete Blob Container '$CONTAINER_NAME' in Storage Account '$STORAGE_ACCOUNT'?${NC}"
            read -rp "Confirm deletion? (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "${YELLOW}Operation cancelled.${NC}"
                exit 1
            fi
            echo "${YELLOW}Deleting Blob Container '$CONTAINER_NAME' from '$STORAGE_ACCOUNT'...${NC}"
            az storage container delete --name "$CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT" --auth-mode login
            if [[ $? -eq 0 ]]; then
                echo "${GREEN}Blob Container deleted successfully!${NC}"
            else
                echo "${RED}Error deleting Blob Container.${NC}"
            fi
        fi
        ;;
    help|--help|-h|*)
        echo "Usage: $0 [COMMAND] [ARGUMENT]"
        echo
        echo "Commands:"
        echo "  list <storage_account>         List all Blob Containers in a Storage Account"
        echo "  list                          List all Blob Containers in all Storage Accounts"
        echo "  create                        Create a new Blob Container (interactive)"
        echo "  delete <blob_container_name>   Delete a Blob Container by name (searches all Storage Accounts)"
        echo "  delete                        Delete a Blob Container (interactive)"
        echo "  help                          Show this help message"
        echo
        echo "Examples:"
        echo "  $0 list mystorageaccount"
        echo "  $0 list"
        echo "  $0 create"
        echo "  $0 delete blobcontainer-pos1"
        echo "  $0 delete"
        ;;
esac
