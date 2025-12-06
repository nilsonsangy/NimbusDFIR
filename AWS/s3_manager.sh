#!/bin/bash

# S3 Manager Script
# Author: NimbusDFIR
# Description: S3 bucket manager

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Check if AWS credentials are configured
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}Error: AWS credentials not configured${NC}"
        echo "Run: aws configure"
        return 1
    fi
    return 0
}

# Function to display usage
usage() {
    echo -e "${BLUE}=========================================="
    echo "S3 Manager - NimbusDFIR"
    echo -e "==========================================${NC}"
    echo ""
    echo "Usage: ./s3_manager.sh [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  list                List all S3 buckets"
    echo "  create              Create a new S3 bucket"
    echo "  delete [bucket]     Delete an S3 bucket"
    echo "  upload <path> [bucket]  Upload file/folder to bucket"
    echo "  download <bucket> <file>  Download a file from bucket"
    echo "  dump <bucket>       Download all files from bucket as zip"
    echo "  help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./s3_manager.sh list"
    echo "  ./s3_manager.sh create"
    echo "  ./s3_manager.sh delete my-bucket"
    echo "  ./s3_manager.sh upload /path/to/photo.jpg my-bucket"
    echo "  ./s3_manager.sh upload /path/to/folder"
    echo "  ./s3_manager.sh download my-bucket photo.jpg"
    echo "  ./s3_manager.sh dump my-bucket"
    echo ""
}

# List all S3 buckets
list_buckets() {
    echo -e "${YELLOW}Listing S3 buckets...${NC}"
    echo ""
    
    echo -e "${CYAN}[AWS CLI] aws s3api list-buckets --output json${NC}"
    local buckets_json=$(aws s3api list-buckets --output json)
    
    if [[ -z "$buckets_json" ]] || ! echo "$buckets_json" | jq -e '.Buckets | length > 0' &> /dev/null; then
        echo -e "${RED}No buckets found${NC}"
        return
    fi
    
    echo -e "${BLUE}Available buckets:${NC}"
    echo ""
    printf "${CYAN}%-40s %s${NC}\n" "Bucket Name" "Created"
    printf "${CYAN}%-40s %s${NC}\n" "-----------" "-------"
    
    echo "$buckets_json" | jq -r '.Buckets[] | "\(.Name)|\(.CreationDate)"' | while IFS='|' read -r name date; do
        printf "${GREEN}%-40s %s${NC}\n" "$name" "$date"
    done
    
    echo ""
    local count=$(echo "$buckets_json" | jq '.Buckets | length')
    echo "Total: $count bucket(s)"
}

# Create a new S3 bucket
create_bucket() {
    local bucket_name="$1"
    
    # If no bucket name provided, ask for it
    if [[ -z "$bucket_name" ]]; then
        read -p "New bucket name: " bucket_name
    fi
    
    if [[ -z "$bucket_name" ]]; then
        echo -e "${RED}Error: Bucket name cannot be empty${NC}"
        return 1
    }
    
    echo -e "${YELLOW}Creating bucket '$bucket_name'...${NC}"
    echo -e "${CYAN}[AWS CLI] aws s3api create-bucket --bucket $bucket_name${NC}"
    
    if aws s3api create-bucket --bucket "$bucket_name" &> /dev/null; then
        echo -e "${GREEN}✓ Bucket created successfully${NC}"
    else
        echo -e "${RED}✗ Failed to create bucket${NC}"
        return 1
    fi
}

# Delete an S3 bucket
delete_bucket() {
    local bucket_name="$1"
    
    # If no bucket name provided, list buckets for selection
    if [[ -z "$bucket_name" ]]; then
        echo -e "${YELLOW}Available buckets:${NC}"
        
        local buckets_json=$(aws s3api list-buckets --output json)
        
        if [[ -z "$buckets_json" ]] || ! echo "$buckets_json" | jq -e '.Buckets | length > 0' &> /dev/null; then
            echo -e "${RED}No buckets found${NC}"
            return 1
        fi
        
        echo ""
        local i=1
        echo "$buckets_json" | jq -r '.Buckets[].Name' | while read -r bucket; do
            echo "$i. $bucket"
            ((i++))
        done
        
        echo ""
        read -p "Select bucket number to delete: " selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            bucket_name=$(echo "$buckets_json" | jq -r ".Buckets[$((selection - 1))].Name")
            
            if [[ -z "$bucket_name" ]] || [[ "$bucket_name" == "null" ]]; then
                echo -e "${RED}Invalid selection${NC}"
                return 1
            fi
        else
            echo -e "${RED}Invalid input${NC}"
            return 1
        fi
    fi
    
    # Confirm deletion
    echo ""
    echo -e "${RED}WARNING: This action cannot be undone!${NC}"
    read -p "Are you sure you want to delete bucket '$bucket_name'? (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Operation cancelled${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Deleting bucket '$bucket_name'...${NC}"
    
    # Try to empty the bucket first
    echo -e "${CYAN}[AWS CLI] aws s3 rm s3://$bucket_name --recursive${NC}"
    aws s3 rm "s3://$bucket_name" --recursive &> /dev/null || true
    
    # Delete the bucket
    echo -e "${CYAN}[AWS CLI] aws s3api delete-bucket --bucket $bucket_name${NC}"
    if aws s3api delete-bucket --bucket "$bucket_name" &> /dev/null; then
        echo -e "${GREEN}✓ Bucket deleted successfully${NC}"
    else
        echo -e "${RED}✗ Failed to delete bucket${NC}"
        return 1
    fi
}

# Upload file or folder to S3
upload_files() {
    local path="$1"
    local bucket_name="$2"
    
    # Check if path was provided
    if [[ -z "$path" ]]; then
        echo -e "${YELLOW}Usage: ./s3_manager.sh upload <path> [bucket]${NC}"
        return 1
    fi
    
    # Check if path exists
    if [[ ! -e "$path" ]]; then
        echo -e "${RED}Error: Path '$path' not found${NC}"
        return 1
    fi
    
    # If no bucket name provided, list buckets for selection
    if [[ -z "$bucket_name" ]]; then
        echo -e "${YELLOW}Available buckets:${NC}"
        
        local buckets_json=$(aws s3api list-buckets --output json)
        
        if [[ -z "$buckets_json" ]] || ! echo "$buckets_json" | jq -e '.Buckets | length > 0' &> /dev/null; then
            echo -e "${RED}No buckets found${NC}"
            return 1
        fi
        
        echo ""
        local i=1
        echo "$buckets_json" | jq -r '.Buckets[].Name' | while read -r bucket; do
            echo "$i. $bucket"
            ((i++))
        done
        
        echo ""
        read -p "Select bucket number for upload: " selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            bucket_name=$(echo "$buckets_json" | jq -r ".Buckets[$((selection - 1))].Name")
            
            if [[ -z "$bucket_name" ]] || [[ "$bucket_name" == "null" ]]; then
                echo -e "${RED}Invalid selection${NC}"
                return 1
            fi
        else
            echo -e "${RED}Invalid input${NC}"
            return 1
        fi
    fi
    
    # Verify bucket exists
    if ! aws s3api head-bucket --bucket "$bucket_name" &> /dev/null; then
        echo -e "${RED}Error: Bucket '$bucket_name' not found or access denied${NC}"
        return 1
    fi
    
    # Check if path is a file or directory
    if [[ -d "$path" ]]; then
        # It's a directory - use sync
        echo -e "${YELLOW}Uploading folder '$path' to bucket '$bucket_name'...${NC}"
        echo -e "${CYAN}[AWS CLI] aws s3 sync $path s3://$bucket_name/ --no-progress${NC}"
        aws s3 sync "$path" "s3://$bucket_name/" --no-progress
        
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}✓ Folder uploaded successfully${NC}"
        else
            echo -e "${RED}✗ Failed to upload folder${NC}"
            return 1
        fi
    else
        # It's a file - use cp
        local file_name=$(basename "$path")
        echo -e "${YELLOW}Uploading file '$file_name' to bucket '$bucket_name'...${NC}"
        echo -e "${CYAN}[AWS CLI] aws s3 cp $path s3://$bucket_name/$file_name${NC}"
        aws s3 cp "$path" "s3://$bucket_name/$file_name"
        
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}✓ File uploaded successfully${NC}"
        else
            echo -e "${RED}✗ Failed to upload file${NC}"
            return 1
        fi
    fi
}

# Download file from S3
download_file() {
    local bucket_name="$1"
    local file_name="$2"
    
    if [[ -z "$bucket_name" ]] || [[ -z "$file_name" ]]; then
        echo -e "${YELLOW}Usage: ./s3_manager.sh download <bucket> <file>${NC}"
        return 1
    fi
    
    # Verify bucket exists
    if ! aws s3api head-bucket --bucket "$bucket_name" &> /dev/null; then
        echo -e "${RED}Error: Bucket '$bucket_name' not found or access denied${NC}"
        return 1
    fi
    
    # Default path and ask user
    local default_path="$HOME/Downloads/$file_name"
    echo -e "${BLUE}Default destination: $default_path${NC}"
    read -p "Change destination? (y/N): " custom
    
    local download_path
    if [[ "$custom" =~ ^[Yy]$ ]]; then
        read -p "Enter full path for destination file: " download_path
        if [[ -z "$download_path" ]]; then
            download_path="$default_path"
        fi
    else
        download_path="$default_path"
    fi
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$download_path")"
    
    echo -e "${YELLOW}Downloading '$file_name' from '$bucket_name'...${NC}"
    echo -e "${CYAN}[AWS CLI] aws s3 cp s3://$bucket_name/$file_name $download_path${NC}"
    
    if aws s3 cp "s3://$bucket_name/$file_name" "$download_path"; then
        echo -e "${GREEN}✓ Download completed${NC}"
        echo "Destination: $download_path"
    else
        echo -e "${RED}✗ Failed to download file${NC}"
        return 1
    fi
}

# Dump bucket to zip
dump_bucket() {
    local bucket_name="$1"
    
    # If no bucket name provided, list buckets for selection
    if [[ -z "$bucket_name" ]]; then
        echo -e "${YELLOW}Available buckets:${NC}"
        
        local buckets_json=$(aws s3api list-buckets --output json)
        
        if [[ -z "$buckets_json" ]] || ! echo "$buckets_json" | jq -e '.Buckets | length > 0' &> /dev/null; then
            echo -e "${RED}No buckets found${NC}"
            return 1
        fi
        
        echo ""
        local i=1
        echo "$buckets_json" | jq -r '.Buckets[].Name' | while read -r bucket; do
            echo "$i. $bucket"
            ((i++))
        done
        
        echo ""
        read -p "Select bucket number to dump: " selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            bucket_name=$(echo "$buckets_json" | jq -r ".Buckets[$((selection - 1))].Name")
            
            if [[ -z "$bucket_name" ]] || [[ "$bucket_name" == "null" ]]; then
                echo -e "${RED}Invalid selection${NC}"
                return 1
            fi
        else
            echo -e "${RED}Invalid input${NC}"
            return 1
        fi
    fi
    
    # Verify bucket exists
    if ! aws s3api head-bucket --bucket "$bucket_name" &> /dev/null; then
        echo -e "${RED}Error: Bucket '$bucket_name' not found or access denied${NC}"
        return 1
    fi
    
    # Zip file name
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local zip_filename="${bucket_name}_${timestamp}.zip"
    local default_zip_path="$HOME/Downloads/$zip_filename"
    
    echo ""
    echo -e "${BLUE}Default destination: $default_zip_path${NC}"
    read -p "Change destination? (y/N): " custom
    
    local zip_path
    if [[ "$custom" =~ ^[Yy]$ ]]; then
        read -p "Enter full path for zip file: " zip_path
        if [[ -z "$zip_path" ]]; then
            zip_path="$default_zip_path"
        fi
    else
        zip_path="$default_zip_path"
    fi
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    
    echo ""
    echo -e "${YELLOW}Downloading files from bucket...${NC}"
    echo -e "${CYAN}[AWS CLI] aws s3 sync s3://$bucket_name $temp_dir --no-progress${NC}"
    
    # Download files and count successes
    aws s3 sync "s3://$bucket_name" "$temp_dir" --no-progress 2>&1
    
    # Check if any files were downloaded
    local file_count=$(find "$temp_dir" -type f | wc -l)
    
    if [[ $file_count -gt 0 ]]; then
        echo -e "${GREEN}✓ Files downloaded ($file_count file(s))${NC}"
        echo ""
        echo -e "${YELLOW}Creating zip archive...${NC}"
        
        # Create zip file
        (cd "$temp_dir" && zip -r "$zip_path" . -q)
        
        echo -e "${GREEN}✓ Zip archive created${NC}"
        echo ""
        echo "----------------------------------------"
        echo -e "${GREEN}Zip file: $zip_path${NC}"
        
        local zip_size=$(stat -f%z "$zip_path" 2>/dev/null || stat -c%s "$zip_path" 2>/dev/null)
        local zip_size_mb=$(echo "scale=2; $zip_size / 1024 / 1024" | bc)
        echo -e "${GREEN}Size: ${zip_size_mb} MB${NC}"
        echo "----------------------------------------"
    else
        echo -e "${RED}✗ Failed to download files from bucket${NC}"
    fi
    
    # Remove temporary directory
    rm -rf "$temp_dir"
    
    echo ""
    echo -e "${GREEN}Dump completed!${NC}"
}

# Main execution
main() {
    local command="${1:-}"
    
    if [[ -z "$command" ]]; then
        usage
        exit 0
    fi
    
    if [[ "$command" == "help" ]]; then
        usage
        exit 0
    fi
    
    if ! check_aws_credentials; then
        exit 1
    fi
    
    case "$command" in
        list)
            list_buckets
            ;;
        create)
            create_bucket "$2"
            ;;
        delete)
            delete_bucket "$2"
            ;;
        upload)
            upload_files "$2" "$3"
            ;;
        download)
            download_file "$2" "$3"
            ;;
        dump)
            dump_bucket "$2"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
