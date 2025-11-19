#!/bin/bash

# Azure MySQL Insert Mock Data Script
# Author: NimbusDFIR
# Description: Insert mock data into an Azure MySQL Flexible Server using Azure CLI

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo -e "${BLUE}=========================================="
    echo "Azure MySQL Insert Mock Data - NimbusDFIR"
    echo -e "==========================================${NC}"
    echo ""
    echo "Usage: $0 [server-name] [database-name]"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive mode"
    echo "  $0 my-mysql-server testdb             # Direct mode"
    echo ""
    echo "Mock data includes:"
    echo "  - 10 customers"
    echo "  - 10 products"
    echo "  - 5 sales"
    echo "  - Purchase details linking customers, sales, and products"
    echo ""
}

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed${NC}"
    echo "Please install Azure CLI first"
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo -e "${RED}Error: Not logged in to Azure${NC}"
    echo "Please run: az login"
    exit 1
fi

# Main script
if [ "$1" == "help" ] || [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    usage
    exit 0
fi

echo -e "${BLUE}=========================================="
echo "Azure MySQL Insert Mock Data"
echo -e "==========================================${NC}"
echo ""

# Check for active SSH tunnel first
echo -e "${BLUE}Checking for active SSH tunnel...${NC}"
TUNNEL_ACTIVE=false
LOCAL_PORT=3307

# Check if there's an SSH process running with MySQL tunnel
if pgrep -f "ssh.*3307.*3306" > /dev/null 2>&1; then
    # Check if port 3307 is listening
    if command -v lsof &> /dev/null; then
        if lsof -i :$LOCAL_PORT > /dev/null 2>&1; then
            TUNNEL_ACTIVE=true
            echo -e "${GREEN}✓ Active SSH tunnel detected on port $LOCAL_PORT${NC}"
        fi
    elif command -v netstat &> /dev/null; then
        if netstat -ln | grep ":$LOCAL_PORT " > /dev/null 2>&1; then
            TUNNEL_ACTIVE=true
            echo -e "${GREEN}✓ Active SSH tunnel detected on port $LOCAL_PORT${NC}"
        fi
    fi
fi

if [ "$TUNNEL_ACTIVE" != "true" ]; then
    echo -e "${YELLOW}✗ No active SSH tunnel found${NC}"
    echo -e "${YELLOW}Please run mysql_connect.sh first to establish tunnel, then run this script${NC}"
    echo -e "${CYAN}Or use this script independently (will prompt for server selection)${NC}"
    echo ""
    
    # Fallback to server selection mode
    SERVER_NAME=$1
    if [ -z "$SERVER_NAME" ]; then
        echo -e "${CYAN}Available MySQL Servers:${NC}"
        SERVERS=$(az mysql flexible-server list --output json 2>/dev/null)
    
    if [ "$SERVERS" == "[]" ] || [ -z "$SERVERS" ]; then
        echo -e "${YELLOW}No MySQL flexible servers found${NC}"
        exit 0
    fi
    
    echo "$SERVERS" | jq -r '.[] | "\(.name) (\(.resourceGroup) - \(.state))"' | nl -w2 -s'. '
    echo ""
    read -p "Select server number or enter name: " SERVER_INPUT
    
    if [ -z "$SERVER_INPUT" ]; then
        echo -e "${RED}Error: Server selection is required${NC}"
        exit 1
    fi
    
    # Check if input is a number
    if [[ "$SERVER_INPUT" =~ ^[0-9]+$ ]]; then
        SERVER_NAME=$(echo "$SERVERS" | jq -r ".[$(($SERVER_INPUT-1))].name" 2>/dev/null)
        if [ -z "$SERVER_NAME" ] || [ "$SERVER_NAME" == "null" ]; then
            echo -e "${RED}Error: Invalid selection${NC}"
            exit 1
        fi
    else
        SERVER_NAME="$SERVER_INPUT"
    fi
fi

        fi
    else
        echo -e "${GREEN}Using existing SSH tunnel for data insertion${NC}"
        echo ""
    fi
else
    echo -e "${GREEN}Using existing SSH tunnel for data insertion${NC}"
    echo ""
fi

# Get server information only if not using tunnel
if [ "$TUNNEL_ACTIVE" != "true" ] && [ -n "$SERVER_NAME" ]; then
    echo ""
    echo -e "${BLUE}Finding server details...${NC}"
    SERVER_INFO=$(az mysql flexible-server list --query "[?name=='$SERVER_NAME']" -o json)
    
    if [ "$SERVER_INFO" == "[]" ]; then
        echo -e "${RED}Error: MySQL server '$SERVER_NAME' not found${NC}"
        exit 1
    fi
    
    RG_NAME=$(echo "$SERVER_INFO" | jq -r '.[0].resourceGroup')
    echo -e "${GREEN}✓ Server found in resource group: $RG_NAME${NC}"
fi

# Get database name
DB_NAME=$2
if [ -z "$DB_NAME" ]; then
    echo ""
    read -p "Enter database name to create (default: testdb): " DB_NAME
    DB_NAME=${DB_NAME:-testdb}
fi

# Get admin username
echo ""
read -p "Enter MySQL admin username (default: mysqladmin): " DB_USERNAME
DB_USERNAME=${DB_USERNAME:-mysqladmin}

# Get admin password
echo ""
echo -e "${YELLOW}Enter MySQL admin password:${NC}"
read -s DB_PASSWORD
echo ""

if [ -z "$DB_PASSWORD" ]; then
    echo -e "${RED}Error: Password is required${NC}"
    exit 1
fi

# Create database
echo ""
echo -e "${BLUE}Creating database '$DB_NAME'...${NC}"

if [ "$TUNNEL_ACTIVE" = "true" ]; then
    # Use SSH tunnel - connect directly to localhost:3307
    echo -e "${GREEN}Using SSH tunnel connection...${NC}"
    MYSQL_PWD="$DB_PASSWORD" mysql -h 127.0.0.1 -P $LOCAL_PORT -u "$DB_USERNAME" -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;" 2>/dev/null
else
    # Use Azure CLI method
    az mysql flexible-server db create \
        --resource-group "$RG_NAME" \
        --server-name "$SERVER_NAME" \
        --database-name "$DB_NAME" &> /dev/null || true
fi

echo -e "${GREEN}✓ Database ready${NC}"

# Create temporary SQL file with mock data
TEMP_SQL=$(mktemp /tmp/mysql_mock_data_XXXXX.sql)

cat > "$TEMP_SQL" <<'EOF'
-- Drop tables if they exist (for re-running the script)
DROP TABLE IF EXISTS sale_items;
DROP TABLE IF EXISTS sales;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;

-- Create customers table
CREATE TABLE customers (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    phone VARCHAR(20),
    city VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create products table
CREATE TABLE products (
    product_id INT AUTO_INCREMENT PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL,
    stock_quantity INT NOT NULL DEFAULT 0,
    category VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create sales table
CREATE TABLE sales (
    sale_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    sale_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10, 2) NOT NULL DEFAULT 0,
    status VARCHAR(20) DEFAULT 'completed',
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

-- Create sale_items table (many-to-many relationship)
CREATE TABLE sale_items (
    sale_item_id INT AUTO_INCREMENT PRIMARY KEY,
    sale_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    unit_price DECIMAL(10, 2) NOT NULL,
    FOREIGN KEY (sale_id) REFERENCES sales(sale_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- Insert 10 customers
INSERT INTO customers (customer_name, email, phone, city) VALUES
('Alice Johnson', 'alice.johnson@email.com', '555-0101', 'New York'),
('Bob Smith', 'bob.smith@email.com', '555-0102', 'Los Angeles'),
('Carol Williams', 'carol.williams@email.com', '555-0103', 'Chicago'),
('David Brown', 'david.brown@email.com', '555-0104', 'Houston'),
('Emma Davis', 'emma.davis@email.com', '555-0105', 'Phoenix'),
('Frank Miller', 'frank.miller@email.com', '555-0106', 'Philadelphia'),
('Grace Wilson', 'grace.wilson@email.com', '555-0107', 'San Antonio'),
('Henry Moore', 'henry.moore@email.com', '555-0108', 'San Diego'),
('Iris Taylor', 'iris.taylor@email.com', '555-0109', 'Dallas'),
('Jack Anderson', 'jack.anderson@email.com', '555-0110', 'San Jose');

-- Insert 10 products
INSERT INTO products (product_name, description, price, stock_quantity, category) VALUES
('Laptop Pro 15', 'High-performance laptop with 15-inch display', 1299.99, 50, 'Electronics'),
('Wireless Mouse', 'Ergonomic wireless mouse with USB receiver', 29.99, 200, 'Accessories'),
('Mechanical Keyboard', 'RGB mechanical keyboard with blue switches', 89.99, 100, 'Accessories'),
('USB-C Hub', '7-in-1 USB-C hub with HDMI and card reader', 49.99, 150, 'Accessories'),
('Monitor 27"', '4K UHD 27-inch monitor with HDR', 399.99, 75, 'Electronics'),
('Webcam HD', '1080p HD webcam with built-in microphone', 79.99, 120, 'Electronics'),
('Desk Lamp', 'LED desk lamp with adjustable brightness', 34.99, 180, 'Office'),
('Laptop Stand', 'Adjustable aluminum laptop stand', 39.99, 95, 'Accessories'),
('External SSD 1TB', 'Portable SSD with 1TB storage capacity', 129.99, 80, 'Storage'),
('Headphones', 'Noise-cancelling wireless headphones', 199.99, 60, 'Electronics');

-- Insert 5 sales with multiple items each

-- Sale 1: Alice Johnson buys 3 items
INSERT INTO sales (customer_id, total_amount) VALUES (1, 0);
SET @sale1_id = LAST_INSERT_ID();
INSERT INTO sale_items (sale_id, product_id, quantity, unit_price) VALUES
(@sale1_id, 1, 1, 1299.99),
(@sale1_id, 2, 2, 29.99),
(@sale1_id, 3, 1, 89.99);
UPDATE sales SET total_amount = (SELECT SUM(quantity * unit_price) FROM sale_items WHERE sale_id = @sale1_id) WHERE sale_id = @sale1_id;

-- Sale 2: David Brown buys 4 items
INSERT INTO sales (customer_id, total_amount) VALUES (4, 0);
SET @sale2_id = LAST_INSERT_ID();
INSERT INTO sale_items (sale_id, product_id, quantity, unit_price) VALUES
(@sale2_id, 5, 1, 399.99),
(@sale2_id, 4, 1, 49.99),
(@sale2_id, 6, 1, 79.99),
(@sale2_id, 8, 1, 39.99);
UPDATE sales SET total_amount = (SELECT SUM(quantity * unit_price) FROM sale_items WHERE sale_id = @sale2_id) WHERE sale_id = @sale2_id;

-- Sale 3: Emma Davis buys 2 items
INSERT INTO sales (customer_id, total_amount) VALUES (5, 0);
SET @sale3_id = LAST_INSERT_ID();
INSERT INTO sale_items (sale_id, product_id, quantity, unit_price) VALUES
(@sale3_id, 10, 1, 199.99),
(@sale3_id, 9, 1, 129.99);
UPDATE sales SET total_amount = (SELECT SUM(quantity * unit_price) FROM sale_items WHERE sale_id = @sale3_id) WHERE sale_id = @sale3_id;

-- Sale 4: Grace Wilson buys 5 items
INSERT INTO sales (customer_id, total_amount) VALUES (7, 0);
SET @sale4_id = LAST_INSERT_ID();
INSERT INTO sale_items (sale_id, product_id, quantity, unit_price) VALUES
(@sale4_id, 1, 1, 1299.99),
(@sale4_id, 2, 1, 29.99),
(@sale4_id, 3, 1, 89.99),
(@sale4_id, 4, 1, 49.99),
(@sale4_id, 8, 1, 39.99);
UPDATE sales SET total_amount = (SELECT SUM(quantity * unit_price) FROM sale_items WHERE sale_id = @sale4_id) WHERE sale_id = @sale4_id;

-- Sale 5: Jack Anderson buys 3 items
INSERT INTO sales (customer_id, total_amount) VALUES (10, 0);
SET @sale5_id = LAST_INSERT_ID();
INSERT INTO sale_items (sale_id, product_id, quantity, unit_price) VALUES
(@sale5_id, 5, 1, 399.99),
(@sale5_id, 7, 2, 34.99),
(@sale5_id, 9, 1, 129.99);
UPDATE sales SET total_amount = (SELECT SUM(quantity * unit_price) FROM sale_items WHERE sale_id = @sale5_id) WHERE sale_id = @sale5_id;
EOF

# Execute SQL file
echo ""
echo -e "${YELLOW}Inserting mock data... (this may take a few moments)${NC}"
echo ""

SUCCESS=false
if [ "$TUNNEL_ACTIVE" = "true" ]; then
    # Use SSH tunnel with secure password method
    if MYSQL_PWD="$DB_PASSWORD" mysql -h 127.0.0.1 -P $LOCAL_PORT -u "$DB_USERNAME" "$DB_NAME" < "$TEMP_SQL" 2>/dev/null; then
        SUCCESS=true
    fi
else
    # Use Azure CLI method
    if az mysql flexible-server execute \
        --name "$SERVER_NAME" \
        --admin-user "$DB_USERNAME" \
        --admin-password "$DB_PASSWORD" \
        --database-name "$DB_NAME" \
        --file-path "$TEMP_SQL" 2>&1 | grep -v "WARNING" > /dev/null; then
        SUCCESS=true
    fi
fi

if [ "$SUCCESS" = "true" ]; then
    
    echo -e "${GREEN}=========================================="
    echo "✓ Mock data inserted successfully!"
    echo -e "==========================================${NC}"
    echo ""
    if [ "$TUNNEL_ACTIVE" = "true" ]; then
        echo "Connection: SSH Tunnel (localhost:$LOCAL_PORT)"
    else
        echo "Server: $SERVER_NAME"
        echo "Resource Group: $RG_NAME"
    fi
    echo "Database: $DB_NAME"
    echo ""
    echo "Tables created:"
    echo "  - customers (10 records)"
    echo "  - products (10 records)"
    echo "  - sales (5 records)"
    echo "  - sale_items (relationship table)"
    echo ""
else
    echo -e "${RED}✗ Failed to insert mock data${NC}"
    rm -f "$TEMP_SQL"
    exit 1
fi

# Cleanup
rm -f "$TEMP_SQL"

echo ""
echo -e "${GREEN}Data insertion complete!${NC}"
echo ""

# Display summary by querying the database
echo -e "${BLUE}Fetching data summary...${NC}"
echo ""

# Count records in each table
echo -e "${CYAN}Table Record Counts:${NC}"
COUNT_QUERY="SELECT 'Customers' as Table_Name, COUNT(*) as Total FROM customers UNION ALL SELECT 'Products', COUNT(*) FROM products UNION ALL SELECT 'Sales', COUNT(*) FROM sales UNION ALL SELECT 'Sale Items', COUNT(*) FROM sale_items;"

if [ "$TUNNEL_ACTIVE" = "true" ]; then
    MYSQL_PWD="$DB_PASSWORD" mysql -h 127.0.0.1 -P $LOCAL_PORT -u "$DB_USERNAME" "$DB_NAME" -e "$COUNT_QUERY"
else
    az mysql flexible-server execute \
        --name "$SERVER_NAME" \
        --admin-user "$DB_USERNAME" \
        --admin-password "$DB_PASSWORD" \
        --database-name "$DB_NAME" \
        --querytext "$COUNT_QUERY" 2>&1 | grep -v "WARNING"
fi

echo ""
echo -e "${CYAN}Sales Summary:${NC}"
SALES_QUERY="SELECT c.customer_name AS Customer, c.city AS City, CONCAT('\$', FORMAT(s.total_amount, 2)) AS Total FROM sales s JOIN customers c ON s.customer_id = c.customer_id ORDER BY s.sale_id;"

if [ "$TUNNEL_ACTIVE" = "true" ]; then
    MYSQL_PWD="$DB_PASSWORD" mysql -h 127.0.0.1 -P $LOCAL_PORT -u "$DB_USERNAME" "$DB_NAME" -e "$SALES_QUERY"
else
    az mysql flexible-server execute \
        --name "$SERVER_NAME" \
        --admin-user "$DB_USERNAME" \
        --admin-password "$DB_PASSWORD" \
        --database-name "$DB_NAME" \
        --querytext "$SALES_QUERY" 2>&1 | grep -v "WARNING"
fi

echo ""
echo -e "${GREEN}All operations completed successfully!${NC}"
