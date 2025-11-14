#!/bin/bash

# S3 Manager Script
# Author: NimbusDFIR
# Description: Manage S3 buckets - list, create, and delete buckets

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
    echo "S3 Manager - NimbusDFIR"
    echo -e "==========================================${NC}"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  list              List all S3 buckets"
    echo "  create            Create a new S3 bucket"
    echo "  delete            Delete an S3 bucket"
    echo "  upload            Upload files to a bucket"
    echo "  download          Download a file from a bucket"
    echo "  dump              Download all files from a bucket as a zip"
    echo "  info              Get bucket information"
    echo "  help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 create"
    echo "  $0 delete my-bucket-name"
    echo "  $0 upload ~/Pictures/* my-bucket-name"
    echo "  $0 upload ~/Documents/file.pdf"
    echo "  $0 download my-bucket-name"
    echo "  $0 download my-bucket-name file.jpg"
    echo "  $0 dump my-bucket-name"
    echo "  $0 info my-bucket-name"
    echo ""
}

# Function to list S3 buckets
list_buckets() {
    echo -e "${BLUE}Listing S3 Buckets...${NC}"
    echo ""
    
    BUCKETS=$(aws s3api list-buckets --query 'Buckets[*].[Name,CreationDate]' --output text)
    
    if [ -z "$BUCKETS" ]; then
        echo -e "${YELLOW}No S3 buckets found${NC}"
        return
    fi
    
    echo -e "${GREEN}Bucket Name\t\t\t\tCreation Date${NC}"
    echo "--------------------------------------------------------------------------------"
    echo "$BUCKETS" | while IFS=$'\t' read -r name date; do
        echo -e "${GREEN}$name\t\t$date${NC}"
    done
    
    echo ""
    TOTAL=$(echo "$BUCKETS" | wc -l | xargs)
    echo -e "Total buckets: ${GREEN}$TOTAL${NC}"
}

# Function to create S3 bucket
create_bucket() {
    echo -e "${BLUE}Create New S3 Bucket${NC}"
    echo ""
    
    # Get bucket name
    read -p "Enter bucket name (must be globally unique, lowercase, no spaces): " BUCKET_NAME
    
    if [ -z "$BUCKET_NAME" ]; then
        echo -e "${RED}Error: Bucket name is required${NC}"
        return
    fi
    
    # Validate bucket name
    if ! [[ "$BUCKET_NAME" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ]]; then
        echo -e "${RED}Error: Invalid bucket name${NC}"
        echo "Bucket names must:"
        echo "  - Be 3-63 characters long"
        echo "  - Start and end with lowercase letter or number"
        echo "  - Contain only lowercase letters, numbers, hyphens, and periods"
        return
    fi
    
    # Get region
    CURRENT_REGION=$(aws configure get region)
    read -p "Enter region (default: $CURRENT_REGION): " REGION
    REGION=${REGION:-$CURRENT_REGION}
    
    echo ""
    echo -e "${YELLOW}Creating bucket '$BUCKET_NAME' in region '$REGION'...${NC}"
    
    # Create bucket
    if [ "$REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION" > /dev/null
    else
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION" > /dev/null
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Bucket '$BUCKET_NAME' created successfully!${NC}"
        
        # Enable versioning (optional)
        read -p "Enable versioning? (y/N): " ENABLE_VERSIONING
        if [[ "$ENABLE_VERSIONING" =~ ^[Yy]$ ]]; then
            aws s3api put-bucket-versioning \
                --bucket "$BUCKET_NAME" \
                --versioning-configuration Status=Enabled
            echo -e "${GREEN}✓ Versioning enabled${NC}"
        fi
        
        # Block public access (recommended)
        read -p "Block all public access? (recommended) (Y/n): " BLOCK_PUBLIC
        if [[ "$BLOCK_PUBLIC" =~ ^[Yy]$ ]]; then
            aws s3api put-public-access-block \
                --bucket "$BUCKET_NAME" \
                --public-access-block-configuration \
                "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
            echo -e "${GREEN}✓ Public access blocked${NC}"
        fi
    else
        echo -e "${RED}✗ Failed to create bucket${NC}"
    fi
}

# Function to delete bucket
delete_bucket() {
    BUCKET_NAME=$1
    
    if [ -z "$BUCKET_NAME" ]; then
        echo -e "${YELLOW}Available buckets:${NC}"
        list_buckets
        echo ""
        read -p "Enter bucket name to delete: " BUCKET_NAME
    fi
    
    if [ -z "$BUCKET_NAME" ]; then
        echo -e "${RED}Error: Bucket name is required${NC}"
        return
    fi
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        echo -e "${RED}Error: Bucket '$BUCKET_NAME' not found or not accessible${NC}"
        return
    fi
    
    # Check if bucket has objects
    OBJECT_COUNT=$(aws s3 ls s3://"$BUCKET_NAME" --recursive --summarize 2>/dev/null | grep "Total Objects:" | awk '{print $3}')
    
    if [ ! -z "$OBJECT_COUNT" ] && [ "$OBJECT_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}WARNING: Bucket '$BUCKET_NAME' contains $OBJECT_COUNT objects${NC}"
        read -p "Do you want to delete all objects first? (yes/no): " DELETE_OBJECTS
        
        if [ "$DELETE_OBJECTS" == "yes" ]; then
            echo "Deleting all objects and versions..."
            
            # Delete all versions and delete markers
            aws s3api delete-objects \
                --bucket "$BUCKET_NAME" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$BUCKET_NAME" \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                    --max-items 1000)" 2>/dev/null || true
            
            # Delete delete markers
            aws s3api delete-objects \
                --bucket "$BUCKET_NAME" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$BUCKET_NAME" \
                    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                    --max-items 1000)" 2>/dev/null || true
            
            # Force remove remaining objects
            aws s3 rm s3://"$BUCKET_NAME" --recursive 2>/dev/null || true
            
            echo -e "${GREEN}✓ Objects deleted${NC}"
        else
            echo "Operation cancelled. Bucket must be empty to delete."
            return
        fi
    fi
    
    echo -e "${YELLOW}WARNING: This will permanently delete bucket '$BUCKET_NAME'${NC}"
    read -p "Are you sure? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "Operation cancelled"
        return
    fi
    
    echo "Deleting bucket..."
    aws s3api delete-bucket --bucket "$BUCKET_NAME"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Bucket '$BUCKET_NAME' deleted successfully${NC}"
    else
        echo -e "${RED}✗ Failed to delete bucket${NC}"
    fi
}

# Function to get bucket information
bucket_info() {
    BUCKET_NAME=$1
    
    if [ -z "$BUCKET_NAME" ]; then
        read -p "Enter bucket name: " BUCKET_NAME
    fi
    
    if [ -z "$BUCKET_NAME" ]; then
        echo -e "${RED}Error: Bucket name is required${NC}"
        return
    fi
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        echo -e "${RED}Error: Bucket '$BUCKET_NAME' not found or not accessible${NC}"
        return
    fi
    
    echo -e "${BLUE}Bucket Information: $BUCKET_NAME${NC}"
    echo "----------------------------------------"
    
    # Get region
    REGION=$(aws s3api get-bucket-location --bucket "$BUCKET_NAME" --query 'LocationConstraint' --output text)
    [ "$REGION" == "None" ] && REGION="us-east-1"
    echo "Region: $REGION"
    
    # Get creation date
    CREATION_DATE=$(aws s3api list-buckets --query "Buckets[?Name=='$BUCKET_NAME'].CreationDate" --output text)
    echo "Created: $CREATION_DATE"
    
    # Get versioning status
    VERSIONING=$(aws s3api get-bucket-versioning --bucket "$BUCKET_NAME" --query 'Status' --output text)
    [ -z "$VERSIONING" ] && VERSIONING="Disabled"
    echo "Versioning: $VERSIONING"
    
    # Get public access block
    PUBLIC_BLOCK=$(aws s3api get-public-access-block --bucket "$BUCKET_NAME" --query 'PublicAccessBlockConfiguration.BlockPublicAcls' --output text 2>/dev/null)
    if [ "$PUBLIC_BLOCK" == "True" ]; then
        echo "Public Access: Blocked"
    else
        echo "Public Access: Not Blocked"
    fi
    
    # Get object count and size
    echo ""
    echo "Calculating bucket size (this may take a moment)..."
    STATS=$(aws s3 ls s3://"$BUCKET_NAME" --recursive --summarize 2>/dev/null | tail -2)
    echo "$STATS"
}

# Function to upload files to bucket
upload_files() {
    local FILES=()
    local BUCKET_NAME=""
    
    # Parse arguments - collect all files first
    while [ $# -gt 0 ]; do
        if [ -f "$1" ] || [ -d "$1" ]; then
            FILES+=("$1")
            shift
        elif aws s3api head-bucket --bucket "$1" 2>/dev/null; then
            BUCKET_NAME="$1"
            shift
        else
            # Check if it's a potential file path that exists
            if [ -e "$1" ]; then
                FILES+=("$1")
                shift
            else
                # Might be a bucket name, save it
                BUCKET_NAME="$1"
                shift
            fi
        fi
    done
    
    # If no files provided, show error
    if [ ${#FILES[@]} -eq 0 ]; then
        echo -e "${RED}Error: No files specified${NC}"
        echo "Usage: $0 upload <files...> [bucket-name]"
        echo "Example: $0 upload ~/Pictures/* my-bucket"
        return
    fi
    
    # If bucket not provided, let user select
    if [ -z "$BUCKET_NAME" ]; then
        echo -e "${BLUE}Available buckets:${NC}"
        
        BUCKET_LIST=$(aws s3api list-buckets --query 'Buckets[*].Name' --output text)
        
        if [ -z "$BUCKET_LIST" ]; then
            echo -e "${RED}No buckets found. Please create a bucket first.${NC}"
            return
        fi
        
        # Convert to array
        BUCKET_ARRAY=($BUCKET_LIST)
        
        # Display numbered list
        echo ""
        for i in "${!BUCKET_ARRAY[@]}"; do
            echo "$((i+1)). ${BUCKET_ARRAY[$i]}"
        done
        
        echo ""
        read -p "Select bucket number (or enter bucket name): " SELECTION
        
        # Check if it's a number
        if [[ "$SELECTION" =~ ^[0-9]+$ ]]; then
            INDEX=$((SELECTION-1))
            if [ $INDEX -ge 0 ] && [ $INDEX -lt ${#BUCKET_ARRAY[@]} ]; then
                BUCKET_NAME="${BUCKET_ARRAY[$INDEX]}"
            else
                echo -e "${RED}Invalid selection${NC}"
                return
            fi
        else
            BUCKET_NAME="$SELECTION"
        fi
    fi
    
    # Verify bucket exists
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        echo -e "${RED}Error: Bucket '$BUCKET_NAME' not found or not accessible${NC}"
        return
    fi
    
    echo -e "${BLUE}Uploading files to bucket: $BUCKET_NAME${NC}"
    echo ""
    
    # Upload files
    TOTAL_FILES=0
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    
    for FILE_PATH in "${FILES[@]}"; do
        # Expand wildcards and process each file
        for FILE in $FILE_PATH; do
            if [ -f "$FILE" ]; then
                TOTAL_FILES=$((TOTAL_FILES+1))
                FILENAME=$(basename "$FILE")
                
                echo -n "Uploading $FILENAME... "
                
                if aws s3 cp "$FILE" "s3://$BUCKET_NAME/$FILENAME" --no-progress 2>/dev/null; then
                    echo -e "${GREEN}✓${NC}"
                    SUCCESS_COUNT=$((SUCCESS_COUNT+1))
                else
                    echo -e "${RED}✗${NC}"
                    FAIL_COUNT=$((FAIL_COUNT+1))
                fi
            elif [ -d "$FILE" ]; then
                echo -e "${YELLOW}Skipping directory: $FILE (use recursive upload for directories)${NC}"
            fi
        done
    done
    
    echo ""
    echo "----------------------------------------"
    echo -e "Total files processed: ${BLUE}$TOTAL_FILES${NC}"
    echo -e "Successfully uploaded: ${GREEN}$SUCCESS_COUNT${NC}"
    if [ $FAIL_COUNT -gt 0 ]; then
        echo -e "Failed: ${RED}$FAIL_COUNT${NC}"
    fi
    echo ""
    echo -e "${GREEN}Upload complete!${NC}"
}

# Function to download file from bucket
download_file() {
    local BUCKET_NAME=""
    local FILE_NAME=""
    local DOWNLOAD_PATH=""
    
    # Parse arguments
    if [ $# -ge 1 ]; then
        # Check if first argument is a bucket name
        if aws s3api head-bucket --bucket "$1" 2>/dev/null; then
            BUCKET_NAME="$1"
            if [ $# -ge 2 ]; then
                FILE_NAME="$2"
            fi
            if [ $# -ge 3 ]; then
                DOWNLOAD_PATH="$3"
            fi
        fi
    fi
    
    # If bucket not provided, let user select
    if [ -z "$BUCKET_NAME" ]; then
        echo -e "${BLUE}Available buckets:${NC}"
        
        BUCKET_LIST=$(aws s3api list-buckets --query 'Buckets[*].Name' --output text)
        
        if [ -z "$BUCKET_LIST" ]; then
            echo -e "${RED}No buckets found${NC}"
            return
        fi
        
        # Convert to array
        BUCKET_ARRAY=($BUCKET_LIST)
        
        # Display numbered list
        echo ""
        for i in "${!BUCKET_ARRAY[@]}"; do
            echo "$((i+1)). ${BUCKET_ARRAY[$i]}"
        done
        
        echo ""
        read -p "Select bucket number (or enter bucket name): " SELECTION
        
        # Check if it's a number
        if [[ "$SELECTION" =~ ^[0-9]+$ ]]; then
            INDEX=$((SELECTION-1))
            if [ $INDEX -ge 0 ] && [ $INDEX -lt ${#BUCKET_ARRAY[@]} ]; then
                BUCKET_NAME="${BUCKET_ARRAY[$INDEX]}"
            else
                echo -e "${RED}Invalid selection${NC}"
                return
            fi
        else
            BUCKET_NAME="$SELECTION"
        fi
    fi
    
    # Verify bucket exists
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        echo -e "${RED}Error: Bucket '$BUCKET_NAME' not found or not accessible${NC}"
        return
    fi
    
    # If file not provided, list files in bucket
    if [ -z "$FILE_NAME" ]; then
        echo -e "${BLUE}Files in bucket '$BUCKET_NAME':${NC}"
        echo ""
        
        FILE_LIST=$(aws s3 ls s3://"$BUCKET_NAME" --recursive | awk '{print $4}')
        
        if [ -z "$FILE_LIST" ]; then
            echo -e "${YELLOW}No files found in bucket${NC}"
            return
        fi
        
        # Convert to array
        FILE_ARRAY=()
        while IFS= read -r line; do
            FILE_ARRAY+=("$line")
        done <<< "$FILE_LIST"
        
        # Display numbered list
        for i in "${!FILE_ARRAY[@]}"; do
            echo "$((i+1)). ${FILE_ARRAY[$i]}"
        done
        
        echo ""
        read -p "Select file number (or enter file name): " SELECTION
        
        # Check if it's a number
        if [[ "$SELECTION" =~ ^[0-9]+$ ]]; then
            INDEX=$((SELECTION-1))
            if [ $INDEX -ge 0 ] && [ $INDEX -lt ${#FILE_ARRAY[@]} ]; then
                FILE_NAME="${FILE_ARRAY[$INDEX]}"
            else
                echo -e "${RED}Invalid selection${NC}"
                return
            fi
        else
            FILE_NAME="$SELECTION"
        fi
    fi
    
    # Check if file exists in bucket
    if ! aws s3 ls "s3://$BUCKET_NAME/$FILE_NAME" &>/dev/null; then
        echo -e "${RED}Error: File '$FILE_NAME' not found in bucket '$BUCKET_NAME'${NC}"
        return
    fi
    
    # Determine download path
    if [ -z "$DOWNLOAD_PATH" ]; then
        DEFAULT_PATH="$HOME/Downloads/$FILE_NAME"
        read -p "Download to ~/Downloads/$FILE_NAME? (Y/n): " CONFIRM
        
        if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
            read -p "Enter download path: " DOWNLOAD_PATH
            # Expand ~ if present
            DOWNLOAD_PATH="${DOWNLOAD_PATH/#\~/$HOME}"
        else
            DOWNLOAD_PATH="$DEFAULT_PATH"
        fi
    fi
    
    # Download file
    echo ""
    echo -e "${YELLOW}Downloading '$FILE_NAME' from bucket '$BUCKET_NAME'...${NC}"
    
    if aws s3 cp "s3://$BUCKET_NAME/$FILE_NAME" "$DOWNLOAD_PATH"; then
        echo ""
        echo -e "${GREEN}✓ File downloaded successfully!${NC}"
        echo "Saved to: $DOWNLOAD_PATH"
        
        # Show file info
        if [ -f "$DOWNLOAD_PATH" ]; then
            FILE_SIZE=$(ls -lh "$DOWNLOAD_PATH" | awk '{print $5}')
            echo "File size: $FILE_SIZE"
        fi
    else
        echo -e "${RED}✗ Failed to download file${NC}"
    fi
}

# Function to dump all files from bucket to zip
dump_bucket() {
    local BUCKET_NAME="$1"
    local ZIP_PATH=""
    
    # If bucket not provided, let user select
    if [ -z "$BUCKET_NAME" ]; then
        echo -e "${BLUE}Available buckets:${NC}"
        
        BUCKET_LIST=$(aws s3api list-buckets --query 'Buckets[*].Name' --output text)
        
        if [ -z "$BUCKET_LIST" ]; then
            echo -e "${RED}No buckets found${NC}"
            return
        fi
        
        # Convert to array
        BUCKET_ARRAY=($BUCKET_LIST)
        
        # Display numbered list
        echo ""
        for i in "${!BUCKET_ARRAY[@]}"; do
            echo "$((i+1)). ${BUCKET_ARRAY[$i]}"
        done
        
        echo ""
        read -p "Select bucket number (or enter bucket name): " SELECTION
        
        # Check if it's a number
        if [[ "$SELECTION" =~ ^[0-9]+$ ]]; then
            INDEX=$((SELECTION-1))
            if [ $INDEX -ge 0 ] && [ $INDEX -lt ${#BUCKET_ARRAY[@]} ]; then
                BUCKET_NAME="${BUCKET_ARRAY[$INDEX]}"
            else
                echo -e "${RED}Invalid selection${NC}"
                return
            fi
        else
            BUCKET_NAME="$SELECTION"
        fi
    fi
    
    # Verify bucket exists
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        echo -e "${RED}Error: Bucket '$BUCKET_NAME' not found or not accessible${NC}"
        return
    fi
    
    # Check if bucket has files
    FILE_COUNT=$(aws s3 ls s3://"$BUCKET_NAME" --recursive 2>/dev/null | wc -l | xargs)
    
    if [ "$FILE_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}Bucket '$BUCKET_NAME' is empty${NC}"
        return
    fi
    
    echo -e "${BLUE}Bucket '$BUCKET_NAME' contains $FILE_COUNT files${NC}"
    
    # Generate zip filename with timestamp
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ZIP_FILENAME="${BUCKET_NAME}_${TIMESTAMP}.zip"
    DEFAULT_ZIP_PATH="$HOME/Downloads/$ZIP_FILENAME"
    
    echo ""
    read -p "Save zip to ~/Downloads/$ZIP_FILENAME? (Y/n): " CONFIRM
    
    if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
        read -p "Enter zip file path: " ZIP_PATH
        # Expand ~ if present
        ZIP_PATH="${ZIP_PATH/#\~/$HOME}"
    else
        ZIP_PATH="$DEFAULT_ZIP_PATH"
    fi
    
    # Create temporary directory for download
    TEMP_DIR=$(mktemp -d)
    echo ""
    echo -e "${YELLOW}Downloading files from bucket...${NC}"
    
    # Download all files from bucket
    if aws s3 sync s3://"$BUCKET_NAME" "$TEMP_DIR" --no-progress; then
        echo -e "${GREEN}✓ Files downloaded${NC}"
        
        # Count downloaded files
        DOWNLOADED_COUNT=$(find "$TEMP_DIR" -type f | wc -l | xargs)
        echo "Downloaded $DOWNLOADED_COUNT files"
        
        # Create zip file
        echo ""
        echo -e "${YELLOW}Creating zip archive...${NC}"
        
        # Ensure target directory exists
        mkdir -p "$(dirname "$ZIP_PATH")"
        
        # Create zip (cd to temp dir to avoid including temp path in zip)
        if (cd "$TEMP_DIR" && zip -r -q "$ZIP_PATH" .); then
            echo -e "${GREEN}✓ Zip archive created${NC}"
            
            # Show zip info
            if [ -f "$ZIP_PATH" ]; then
                ZIP_SIZE=$(ls -lh "$ZIP_PATH" | awk '{print $5}')
                echo ""
                echo "----------------------------------------"
                echo -e "Zip file: ${GREEN}$ZIP_PATH${NC}"
                echo -e "Size: ${GREEN}$ZIP_SIZE${NC}"
                echo -e "Files: ${GREEN}$DOWNLOADED_COUNT${NC}"
                echo "----------------------------------------"
            fi
        else
            echo -e "${RED}✗ Failed to create zip archive${NC}"
        fi
    else
        echo -e "${RED}✗ Failed to download files from bucket${NC}"
    fi
    
    # Cleanup temporary directory
    echo ""
    echo "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    
    echo -e "${GREEN}Dump complete!${NC}"
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
        list_buckets
        ;;
    create)
        create_bucket
        ;;
    delete)
        delete_bucket "$@"
        ;;
    upload)
        upload_files "$@"
        ;;
    download)
        download_file "$@"
        ;;
    dump)
        dump_bucket "$@"
        ;;
    info)
        bucket_info "$@"
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
