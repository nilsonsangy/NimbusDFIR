#!/bin/bash

# RDS Database Dump Script
# Author: NimbusDFIR
# Description: Dump databases from RDS through an existing SSH tunnel
# Note: Requires rds_connect.sh to be running first

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variables
TUNNEL_PORT=""
MYSQL_HOST="127.0.0.1"
DUMP_DIR="$HOME/Downloads"
COMPRESS=true
MYSQL_PASSWORD=""

# Function to display usage
usage() {
    echo -e "${BLUE}=========================================="
    echo "RDS Database Dump - NimbusDFIR"
    echo -e "==========================================${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "  $0 [OPTIONS]"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  -l, --list              List all databases in the RDS instance"
    echo "  -d, --dump <database>   Dump a specific database"
    echo "  -o, --output <dir>      Output directory for dumps (default: ~/Downloads)"
    echo "  -n, --no-compress       Do not compress the dump file (default: compress with gzip)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  # List all databases"
    echo -e "  ${GREEN}$0 --list${NC}"
    echo ""
    echo "  # Dump a specific database"
    echo -e "  ${GREEN}$0 --dump mydb${NC}"
    echo ""
    echo "  # Dump to a custom directory"
    echo -e "  ${GREEN}$0 --dump mydb --output /path/to/backups${NC}"
    echo ""
    echo "  # Dump without compression"
    echo -e "  ${GREEN}$0 --dump mydb --no-compress${NC}"
    echo ""
    echo -e "${YELLOW}⚠ Prerequisites:${NC}"
    echo "  1. First, connect to your RDS using:"
    echo -e "     ${GREEN}./rds_connect.sh your-db-identifier${NC}"
    echo ""
    echo "  2. Keep that connection active in one terminal"
    echo ""
    echo "  3. Run this script in a new terminal"
    echo ""
}

# Check if there's an active SSH tunnel for RDS
check_tunnel() {
    echo -e "${BLUE}[INFO]${NC} Checking for active SSH tunnel..."
    
    # Look for SSH tunnels on common ports (3307-3320)
    for port in {3307..3320}; do
        if lsof -Pi :$port -sTCP:LISTEN | grep -q ssh 2>/dev/null; then
            TUNNEL_PORT=$port
            echo -e "${GREEN}[SUCCESS]${NC} Found SSH tunnel on port ${TUNNEL_PORT}"
            return 0
        fi
    done
    
    return 1
}

# List all databases
list_databases() {
    echo -e "${BLUE}[INFO]${NC} Listing databases on RDS instance..."
    
    # Prompt for password once
    echo -e "${YELLOW}[PROMPT]${NC} Enter MySQL password:"
    read -s MYSQL_PASSWORD
    echo ""
    
    # Get list of databases, excluding system databases
    DATABASES=$(mysql -h "$MYSQL_HOST" -P "$TUNNEL_PORT" -u admin -p"$MYSQL_PASSWORD" \
        --connect-timeout=30 \
        -e "SHOW DATABASES;" 2>/dev/null | \
        grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$")
    
    echo ""
    
    if [ $? -eq 0 ]; then
        echo -e "${CYAN}Available databases:${NC}"
        echo "===================="
        echo "$DATABASES" | while read -r db; do
            # Get database size
            SIZE=$(mysql -h "$MYSQL_HOST" -P "$TUNNEL_PORT" -u admin -p"$MYSQL_PASSWORD" \
                --connect-timeout=30 \
                -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)' 
                    FROM information_schema.TABLES 
                    WHERE table_schema = '$db';" 2>/dev/null | tail -1)
            
            if [ "$SIZE" != "NULL" ] && [ ! -z "$SIZE" ]; then
                echo -e "  ${GREEN}•${NC} $db ${YELLOW}(${SIZE} MB)${NC}"
            else
                echo -e "  ${GREEN}•${NC} $db ${YELLOW}(empty)${NC}"
            fi
        done
        echo ""
        return 0
    else
        echo -e "${RED}[ERROR]${NC} Failed to list databases. Check your MySQL password."
        return 1
    fi
}

# Dump a specific database
dump_database() {
    local DB_NAME=$1
    
    if [ -z "$DB_NAME" ]; then
        echo -e "${RED}[ERROR]${NC} Database name is required"
        usage
        exit 1
    fi
    
    echo -e "${BLUE}[INFO]${NC} Preparing to dump database: ${CYAN}$DB_NAME${NC}"
    
    # Prompt for password if not already set
    if [ -z "$MYSQL_PASSWORD" ]; then
        echo -e "${YELLOW}[PROMPT]${NC} Enter MySQL password:"
        read -s MYSQL_PASSWORD
        echo ""
    fi
    
    # Create dump directory if it doesn't exist
    mkdir -p "$DUMP_DIR"
    
    # Generate filename with timestamp
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    DUMP_FILE="$DUMP_DIR/${DB_NAME}_${TIMESTAMP}.sql"
    
    echo -e "${BLUE}[INFO]${NC} Dump file: ${CYAN}$DUMP_FILE${NC}"
    
    # Check if database exists
    echo -e "${BLUE}[INFO]${NC} Validating database..."
    DB_EXISTS=$(mysql -h "$MYSQL_HOST" -P "$TUNNEL_PORT" -u admin -p"$MYSQL_PASSWORD" \
        --connect-timeout=30 \
        -e "SHOW DATABASES LIKE '$DB_NAME';" 2>/dev/null | grep -c "$DB_NAME")
    
    if [ "$DB_EXISTS" -eq 0 ]; then
        echo -e "${RED}[ERROR]${NC} Database '$DB_NAME' does not exist"
        echo -e "${YELLOW}[TIP]${NC} Use --list to see available databases"
        exit 1
    fi
    
    # Perform the dump
    echo ""
    echo -e "${BLUE}[INFO]${NC} Starting database dump..."
    mysqldump -h "$MYSQL_HOST" -P "$TUNNEL_PORT" -u admin -p"$MYSQL_PASSWORD" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --set-gtid-purged=OFF \
        --compress \
        "$DB_NAME" > "$DUMP_FILE" 2>&1
    
    if [ $? -eq 0 ] && [ -s "$DUMP_FILE" ]; then
        FILE_SIZE=$(du -h "$DUMP_FILE" | cut -f1)
        echo ""
        echo -e "${GREEN}[SUCCESS]${NC} Database dump completed!"
        echo -e "${BLUE}[INFO]${NC} File: ${CYAN}$DUMP_FILE${NC}"
        echo -e "${BLUE}[INFO]${NC} Size: ${CYAN}$FILE_SIZE${NC}"
        echo ""
        
        # Show dump statistics
        echo -e "${CYAN}Dump Statistics:${NC}"
        echo "===================="
        TABLES=$(grep -c "CREATE TABLE" "$DUMP_FILE")
        INSERTS=$(grep -c "INSERT INTO" "$DUMP_FILE")
        echo -e "  Tables: ${GREEN}$TABLES${NC}"
        echo -e "  Insert statements: ${GREEN}$INSERTS${NC}"
        echo ""
        
        # Compress the dump if enabled
        if [ "$COMPRESS" = true ]; then
            echo -e "${BLUE}[INFO]${NC} Compressing dump file..."
            gzip "$DUMP_FILE"
            
            if [ $? -eq 0 ]; then
                COMPRESSED_SIZE=$(du -h "${DUMP_FILE}.gz" | cut -f1)
                echo -e "${GREEN}[SUCCESS]${NC} Compression completed!"
                echo -e "${BLUE}[INFO]${NC} Compressed file: ${CYAN}${DUMP_FILE}.gz${NC}"
                echo -e "${BLUE}[INFO]${NC} Compressed size: ${CYAN}$COMPRESSED_SIZE${NC}"
            fi
        else
            echo -e "${BLUE}[INFO]${NC} Compression skipped (--no-compress flag used)"
        fi
        
        return 0
    else
        echo -e "${RED}[ERROR]${NC} Database dump failed"
        [ -f "$DUMP_FILE" ] && rm -f "$DUMP_FILE"
        return 1
    fi
}

# Interactive mode - let user select database
interactive_dump() {
    echo -e "${BLUE}[INFO]${NC} Interactive database selection"
    
    # Prompt for password once
    echo -e "${YELLOW}[PROMPT]${NC} Enter MySQL password:"
    read -s MYSQL_PASSWORD
    echo ""
    
    # Get list of databases
    DATABASES=$(mysql -h "$MYSQL_HOST" -P "$TUNNEL_PORT" -u admin -p"$MYSQL_PASSWORD" \
        --connect-timeout=30 \
        -e "SHOW DATABASES;" 2>/dev/null | \
        grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$")
    
    echo ""
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} Failed to retrieve database list"
        exit 1
    fi
    
    # Convert to array
    DB_ARRAY=()
    while IFS= read -r line; do
        [ ! -z "$line" ] && DB_ARRAY+=("$line")
    done <<< "$DATABASES"
    
    if [ ${#DB_ARRAY[@]} -eq 0 ]; then
        echo -e "${YELLOW}[WARNING]${NC} No user databases found in RDS instance"
        exit 0
    fi
    
    # Display menu
    echo -e "${CYAN}Select a database to dump:${NC}"
    echo "===================="
    for i in "${!DB_ARRAY[@]}"; do
        echo -e "  ${GREEN}$((i+1)).${NC} ${DB_ARRAY[$i]}"
    done
    echo -e "  ${RED}0.${NC} Cancel"
    echo ""
    
    # Get user selection
    read -p "Enter your choice [0-${#DB_ARRAY[@]}]: " choice
    
    if [ "$choice" -eq 0 ] 2>/dev/null; then
        echo -e "${YELLOW}[CANCELLED]${NC} Operation cancelled by user"
        exit 0
    elif [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le ${#DB_ARRAY[@]} ]; then
        SELECTED_DB="${DB_ARRAY[$((choice-1))]}"
        echo ""
        dump_database "$SELECTED_DB"
    else
        echo -e "${RED}[ERROR]${NC} Invalid selection"
        exit 1
    fi
}

# Main script execution
main() {
    # Check if tunnel exists
    if ! check_tunnel; then
        echo -e "${RED}[ERROR]${NC} No active SSH tunnel found"
        echo ""
        echo -e "${YELLOW}Please start rds_connect.sh first:${NC}"
        echo "  ${GREEN}./rds_connect.sh your-db-identifier${NC}"
        echo ""
        exit 1
    fi
    
    # Parse command line arguments
    if [ $# -eq 0 ]; then
        # No arguments - run interactive mode
        interactive_dump
        exit 0
    fi
    
    # Parse all arguments first
    while [ $# -gt 0 ]; do
        case "$1" in
            -l|--list)
                list_databases
                exit $?
                ;;
            -d|--dump)
                if [ -z "$2" ]; then
                    echo -e "${RED}[ERROR]${NC} --dump requires a database name"
                    usage
                    exit 1
                fi
                DB_NAME="$2"
                shift 2
                ;;
            -o|--output)
                if [ -z "$2" ]; then
                    echo -e "${RED}[ERROR]${NC} --output requires a directory path"
                    usage
                    exit 1
                fi
                DUMP_DIR="$2"
                shift 2
                ;;
            -n|--no-compress)
                COMPRESS=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo -e "${RED}[ERROR]${NC} Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # If database name was provided, dump it
    # Otherwise, run interactive mode (allows flags like -n to work with interactive)
    if [ ! -z "$DB_NAME" ]; then
        dump_database "$DB_NAME"
    else
        interactive_dump
    fi
}

# Run main function
main "$@"
