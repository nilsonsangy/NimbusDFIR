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

# -------------------------------------------------------------------------
# UPLOAD – with validation + safe blob naming
# -------------------------------------------------------------------------
upload_to_blob_container() {
    local args=("$@")

    # Remove first arg ("upload")
    args=("${args[@]:1}")

    # Last argument = container name
    local container="${args[-1]}"
    unset 'args[-1]'

    # Remaining arguments = files
    local files=("${args[@]}")

    # Ask manually if user didn't pass files
    if [[ ${#files[@]} -eq 0 ]]; then
        read -rp "Enter the path(s) to file(s) to upload: " file_input
        files=($file_input)
    fi

    # Check if directory expansion returned nothing
    for f in "${files[@]}"; do
        if [[ ! -f "$f" ]]; then
            echo "${RED}File not found: $f${NC}"
            echo "${YELLOW}Tip: If using '*', make sure the directory is not empty.${NC}"
            return 1
        fi
    done

    # Resolve container and account
    if [[ -z "$container" ]]; then
        get_all_blob_containers
        echo "Select the destination Blob Container:"
        for i in "${!containers_list[@]}"; do
            printf "%-3d %-30s %-30s\n" "$((i+1))" "${containers_list[i]}" "${containers_accounts[i]}"
        done
        read -rp "Enter the ID of the Blob Container: " choice
        idx=$((choice-1))
        if [[ $idx -lt 0 || $idx -ge ${#containers_list[@]} ]]; then
            echo "${RED}Invalid selection.${NC}"
            return 1
        fi
        container="${containers_list[$idx]}"
        account="${containers_accounts[$idx]}"
    else
        get_all_blob_containers
        idx=-1
        for i in "${!containers_list[@]}"; do
            if [[ "${containers_list[$i]}" == "$container" ]]; then
                idx=$i
                break
            fi
        done
        if [[ $idx -eq -1 ]]; then
            echo "${RED}Blob Container '$container' not found.${NC}"
            return 1
        fi
        account="${containers_accounts[$idx]}"
    fi

    # Perform the uploads
    for file in "${files[@]}"; do
        blob_name="$(basename "$file")"
        echo "Uploading $file as blob '$blob_name' to container '$container' in account '$account'..."

        az storage blob upload \
            --account-name "$account" \
            --container-name "$container" \
            --file "$file" \
            --name "$blob_name" \
            --auth-mode login

        if [[ $? -ne 0 ]]; then
            echo "${RED}Upload failed for $file${NC}"
        fi
    done
}

# -------------------------------------------------------------------------
download_from_blob_container() {
    local container="$2"
    local blob="$3"
    get_all_blob_containers

    if [[ -z "$container" ]]; then
        echo "Select the Blob Container to download from:"
        for i in "${!containers_list[@]}"; do
            printf "%-3d %-30s %-30s\n" "$((i+1))" "${containers_list[i]}" "${containers_accounts[i]}"
        done
        read -rp "Enter the ID: " choice
        idx=$((choice-1))
        if [[ $idx -lt 0 || $idx -ge ${#containers_list[@]} ]]; then
            echo "${RED}Invalid selection.${NC}"
            return 1
        fi
        container="${containers_list[$idx]}"
        account="${containers_accounts[$idx]}"
    else
        idx=-1
        for i in "${!containers_list[@]}"; do
            if [[ "${containers_list[$i]}" == "$container" ]]; then
                idx=$i
                break
            fi
        done
        if [[ $idx -eq -1 ]]; then
            echo "${RED}Blob Container '$container' not found.${NC}"
            return 1
        fi
        account="${containers_accounts[$idx]}"
    fi

    if [[ -z "$blob" ]]; then
        echo "Listing blobs:"
        blobs=$(az storage blob list --account-name "$account" --container-name "$container" --query '[].name' -o tsv --auth-mode login)

        if [[ -z "$blobs" ]]; then
            echo "${RED}No blobs found.${NC}"
            return 1
        fi

        mapfile -t blob_list <<< "$blobs"

        for i in "${!blob_list[@]}"; do
            echo "  $((i+1))) ${blob_list[i]}"
        done

        read -rp "Choose blob (ENTER = all): " blob_choice
        if [[ -z "$blob_choice" ]]; then
            for b in "${blob_list[@]}"; do
                default_path="$HOME/Downloads/$b"
                read -rp "Download '$b' to $default_path? (ENTER to confirm, or type path): " save_path
                save_path=${save_path:-$default_path}
                echo "Downloading $b to $save_path..."
                az storage blob download --account-name "$account" --container-name "$container" --name "$b" --file "$save_path" --auth-mode login
            done
            return
        fi

        idx=$((blob_choice-1))
        if (( idx < 0 || idx >= ${#blob_list[@]} )); then
            echo "${RED}Invalid selection.${NC}"
            return 1
        fi
        blob="${blob_list[$idx]}"
    fi

    default_path="$HOME/Downloads/$blob"
    read -rp "Download '$blob' to $default_path? (ENTER to confirm, or type path): " save_path
    save_path=${save_path:-$default_path}
    echo "Downloading $blob to $save_path..."
    az storage blob download --account-name "$account" --container-name "$container" --name "$blob" --file "$save_path" --auth-mode login > /dev/null
    if [[ $? -eq 0 ]]; then
        echo "${GREEN}Download complete: $save_path${NC}"
    else
        echo "${RED}Download failed for $blob${NC}"
    fi
}

# -------------------------------------------------------------------------
dump_blob_container() {
    local container="$2"
    get_all_blob_containers

    if [[ -z "$container" ]]; then
        echo "Select the Blob Container to dump:"
        for i in "${!containers_list[@]}"; do
            printf "%-3d %-30s %-30s\n" "$((i+1))" "${containers_list[i]}" "${containers_accounts[i]}"
        done
        read -rp "ID: " choice
        idx=$((choice-1))
        container="${containers_list[$idx]}"
        account="${containers_accounts[$idx]}"
    else
        idx=-1
        for i in "${!containers_list[@]}"; do
            if [[ "${containers_list[$i]}" == "$container" ]]; then
                idx=$i; break
            fi
        done
        if (( idx == -1 )); then
            echo "${RED}Container not found.${NC}"
            return 1
        fi
        account="${containers_accounts[$idx]}"
    fi

    # Temporary folder for download
    temp_dir=$(mktemp -d)
    echo "Downloading all blobs from container '$container'..."
    az storage blob download-batch --account-name "$account" --destination "$temp_dir" --source "$container" --auth-mode login > /dev/null
    if [[ $? -ne 0 ]]; then
        echo "${RED}Error downloading blobs.${NC}"
        rm -rf "$temp_dir"
        return 1
    fi

    # Name of the zip
    timestamp=$(date +%Y%m%d_%H%M%S)
    zip_name="${container}_${timestamp}.zip"
    default_zip="$HOME/Downloads/$zip_name"
    read -rp "Save zip to $default_zip? (ENTER to confirm, or type path): " zip_path
    zip_path=${zip_path:-$default_zip}

    echo "Zipping files to $zip_path..."
    (cd "$temp_dir" && zip -r -q "$zip_path" .)
    if [[ $? -eq 0 ]]; then
        echo "${GREEN}Dump complete: $zip_path${NC}"
    else
        echo "${RED}Error creating zip.${NC}"
    fi
    rm -rf "$temp_dir"
}

# -------------------------------------------------------------------------
info_blob_container() {
    local container="$2"
    get_all_blob_containers

    if [[ -z "$container" ]]; then
        echo "Select container:"
        for i in "${!containers_list[@]}"; do
            printf "%-3d %-30s %-30s\n" "$((i+1))" "${containers_list[i]}" "${containers_accounts[i]}"
        done
        read -rp "ID: " choice
        idx=$((choice-1))
        container="${containers_list[$idx]}"
        account="${containers_accounts[$idx]}"
    else
        idx=-1
        for i in "${!containers_list[@]}"; do
            [[ "${containers_list[$i]}" == "$container" ]] && idx=$i && break
        done
        if (( idx == -1 )); then
            echo "${RED}Not found.${NC}"
            return 1
        fi
        account="${containers_accounts[$idx]}"
    fi

    echo "Info:"
    az storage container show --account-name "$account" --name "$container" --auth-mode login
}

# -------------------------------------------------------------------------
delete_blob_container_interactive() {
    echo "${YELLOW}Fetching Blob Containers...${NC}"
    get_all_blob_containers
    if (( ${#containers_list[@]} == 0 )); then
        echo "${RED}No containers.${NC}"
        return
    fi

    printf "%-3s %-30s %-30s\n" "#" "Container" "Account"
    for i in "${!containers_list[@]}"; do
        printf "%-3d %-30s %-30s\n" "$((i+1))" "${containers_list[i]}" "${containers_accounts[i]}"
    done

    read -rp "ID to delete: " choice
    idx=$((choice-1))
    container="${containers_list[$idx]}"
    account="${containers_accounts[$idx]}"

    read -rp "Confirm delete $container? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || return

    az storage container delete --name "$container" --account-name "$account" --auth-mode login
}

# -------------------------------------------------------------------------
banner() {
    echo "${BLUE}==============================================${NC}"
    echo "${GREEN}          Azure Blob Storage Manager          ${NC}"
    echo "${BLUE}==============================================${NC}"
}

pause() {
    echo
    read -rp "Press ENTER to continue..." _
}

# -------------------------------------------------------------------------
list_blob_containers() {
    if [[ -z "$1" ]]; then
        echo "${RED}Storage Account required.${NC}"
        return 1
    fi

    echo "${YELLOW}Fetching containers...${NC}"
    containers=$(az storage container list --account-name "$1" --auth-mode login -o tsv --query '[].name')

    if [[ -z "$containers" ]]; then
        echo "${RED}None found.${NC}"
        return
    fi

    idx=1
    while IFS= read -r c; do
        echo "$idx    $c"
        ((idx++))
    done <<< "$containers"
}

# -------------------------------------------------------------------------
create_blob_container() {
    accounts_str=$(az storage account list --query '[].name' -o tsv)
    mapfile -t accounts <<< "$accounts_str"

    echo "Accounts:"
    for i in "${!accounts[@]}"; do
        echo "  $((i+1))) ${accounts[i]}"
    done

    read -rp "Select: " acc_choice
    account="${accounts[$((acc_choice-1))]}"

    read -rp "Container name: " name

    az storage container create \
        --name "$name" \
        --account-name "$account" \
        --auth-mode login \
        --public-access off
}

# -------------------------------------------------------------------------
delete_blob_container() {
    if [[ -z "$1" ]]; then
        echo "${RED}Storage Account required.${NC}"
        return
    fi

    mapfile -t containers < <(az storage container list --account-name "$1" --auth-mode login -o tsv --query '[].name')

    echo "Containers:"
    for i in "${!containers[@]}"; do
        echo "$((i+1))) ${containers[i]}"
    done

    read -rp "ID: " choice
    container="${containers[$((choice-1))]}"

    read -rp "Confirm delete? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || return

    az storage container delete --name "$container" --account-name "$1" --auth-mode login
}

# -------------------------------------------------------------------------
get_all_blob_containers() {
    accounts_str=$(az storage account list --query '[].name' -o tsv)
    mapfile -t accounts <<< "$accounts_str"

    containers_list=()
    containers_accounts=()

    for account in "${accounts[@]}"; do
        containers=$(az storage container list --account-name "$account" --auth-mode login -o tsv --query '[].name')
        while IFS= read -r c; do
            if [[ -n "$c" ]]; then
                containers_list+=("$c")
                containers_accounts+=("$account")
            fi
        done <<< "$containers"
    done
}

# -------------------------------------------------------------------------
list_all_blob_containers() {
    get_all_blob_containers

    if [[ ${#containers_list[@]} -gt 0 ]]; then
        printf "%-3s %-30s %-30s\n" "#" "Container" "Account"
        for i in "${!containers_list[@]}"; do
            printf "%-3d %-30s %-30s\n" "$((i+1))" "${containers_list[i]}" "${containers_accounts[i]}"
        done
    else
        echo "${RED}No Blob Containers found in any Storage Account.${NC}"
    fi
}

# -------------------------------------------------------------------------
# MAIN
case "$1" in
    upload)
        banner
        upload_to_blob_container "$@"
        ;;
    download)
        banner
        download_from_blob_container "$@"
        ;;
    dump)
        banner
        dump_blob_container "$@"
        ;;
    info)
        banner
        info_blob_container "$@"
        ;;
    list)
        banner
        if [[ -z "$2" ]]; then list_all_blob_containers; else list_blob_containers "$2"; fi
        ;;
    create)
        banner
        create_blob_container
        ;;
    delete)
        banner
        if [[ -z "$2" ]]; then delete_blob_container_interactive; else delete_blob_container "$2"; fi
        ;;
    help|--help|-h|*)
        echo "Usage: $0 COMMAND [ARGS]"
        echo
        echo "Commands:"
        echo "  list <storage_account>   List containers in an account"
        echo "  list                     List containers in all accounts"
        echo "  create                   Create container"
        echo "  delete <container>       Delete container"
        echo "  upload <files> <ctr>     Upload files"
        echo "  download <ctr> [blob]    Download blobs"
        echo "  dump <ctr>               List blobs"
        echo "  info <ctr>               Container info"
        ;;
esac
