#!/bin/bash

# RDS Insert Mock Data Script
# Author: NimbusDFIR
# Description: Insert mock data into an RDS database through an existing SSH tunnel
# Note: Requires rds_connect.sh to be running first

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo -e "${BLUE}=========================================="
    echo "RDS Insert Mock Data - NimbusDFIR"
    echo -e "==========================================${NC}"
    echo ""
    echo -e "${YELLOW}⚠ This script requires an active RDS connection${NC}"
    echo ""
    echo "Steps to use:"
    echo "  1. First, connect to your RDS using:"
    echo "     ${GREEN}./rds_connect.sh your-db-identifier${NC}"
    echo ""
    echo "  2. Once connected to MySQL, open a new terminal"
    echo ""
    echo "  3. Run this script in the new terminal:"
    echo "     ${GREEN}./rds_insert_mock_data.sh${NC}"
    echo ""
    echo "The script will detect the active SSH tunnel and insert mock data."
    echo ""
    echo "Mock data includes:"
    echo "  - 10 customers"
    echo "  - 10 products"
    echo "  - 5 sales"
    echo "  - Purchase details linking customers, sales, and products"
    echo ""
}

# Check if there's an active SSH tunnel for RDS
check_tunnel() {
    # Look for SSH tunnels on common ports (3307-3320)
    for port in {3307..3320}; do
        if lsof -Pi :$port -sTCP:LISTEN | grep -q ssh 2>/dev/null; then
            TUNNEL_PORT=$port
            return 0
        fi
    done
    return 1
}

# Main script
if [ "$1" == "help" ] || [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    usage
    exit 0
fi

echo -e "${BLUE}=========================================="
echo "RDS Insert Mock Data"
echo -e "==========================================${NC}"
echo ""

# Check for active SSH tunnel
echo "Checking for active SSH tunnel..."
if ! check_tunnel; then
    echo -e "${RED}✗ No active SSH tunnel found${NC}"
    echo ""
    echo -e "${YELLOW}Please run './rds_connect.sh' first to establish a connection.${NC}"
    echo ""
    echo "For more information, run: ./rds_insert_mock_data.sh help"
    exit 1
fi

echo -e "${GREEN}✓ Found active SSH tunnel on port $TUNNEL_PORT${NC}"
echo ""

# Get database credentials
read -p "Enter database name (default: testdb): " DB_NAME
DB_NAME=${DB_NAME:-testdb}

read -p "Enter MySQL username (default: admin): " DB_USERNAME
DB_USERNAME=${DB_USERNAME:-admin}

echo -e "${YELLOW}Enter MySQL password:${NC}"
read -s DB_PASSWORD
echo ""

if [ -z "$DB_PASSWORD" ]; then
    echo -e "${RED}Error: Password is required${NC}"
    exit 1
fi

# Test connection
echo "Testing connection..."
if ! mysql -h 127.0.0.1 -P "$TUNNEL_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1;" &> /dev/null; then
    echo -e "${RED}✗ Failed to connect to database${NC}"
    echo "Please verify your credentials and try again."
    exit 1
fi

echo -e "${GREEN}✓ Connected successfully${NC}"
echo ""

# Create database if not exists
echo "Creating database '$DB_NAME' if not exists..."
mysql -h 127.0.0.1 -P "$TUNNEL_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;" 2>&1

echo "Inserting mock data..."
echo ""

# Execute SQL commands
mysql -h 127.0.0.1 -P "$TUNNEL_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_NAME" <<'EOF'

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
(@sale1_id, 1, 1, 1299.99),  -- Laptop
(@sale1_id, 2, 2, 29.99),     -- Mouse x2
(@sale1_id, 3, 1, 89.99);     -- Keyboard
UPDATE sales SET total_amount = (SELECT SUM(quantity * unit_price) FROM sale_items WHERE sale_id = @sale1_id) WHERE sale_id = @sale1_id;

-- Sale 2: David Brown buys 4 items
INSERT INTO sales (customer_id, total_amount) VALUES (4, 0);
SET @sale2_id = LAST_INSERT_ID();
INSERT INTO sale_items (sale_id, product_id, quantity, unit_price) VALUES
(@sale2_id, 5, 1, 399.99),    -- Monitor
(@sale2_id, 4, 1, 49.99),     -- USB-C Hub
(@sale2_id, 6, 1, 79.99),     -- Webcam
(@sale2_id, 8, 1, 39.99);     -- Laptop Stand
UPDATE sales SET total_amount = (SELECT SUM(quantity * unit_price) FROM sale_items WHERE sale_id = @sale2_id) WHERE sale_id = @sale2_id;

-- Sale 3: Emma Davis buys 2 items
INSERT INTO sales (customer_id, total_amount) VALUES (5, 0);
SET @sale3_id = LAST_INSERT_ID();
INSERT INTO sale_items (sale_id, product_id, quantity, unit_price) VALUES
(@sale3_id, 10, 1, 199.99),   -- Headphones
(@sale3_id, 9, 1, 129.99);    -- External SSD
UPDATE sales SET total_amount = (SELECT SUM(quantity * unit_price) FROM sale_items WHERE sale_id = @sale3_id) WHERE sale_id = @sale3_id;

-- Sale 4: Grace Wilson buys 5 items
INSERT INTO sales (customer_id, total_amount) VALUES (7, 0);
SET @sale4_id = LAST_INSERT_ID();
INSERT INTO sale_items (sale_id, product_id, quantity, unit_price) VALUES
(@sale4_id, 1, 1, 1299.99),   -- Laptop
(@sale4_id, 2, 1, 29.99),     -- Mouse
(@sale4_id, 3, 1, 89.99),     -- Keyboard
(@sale4_id, 4, 1, 49.99),     -- USB-C Hub
(@sale4_id, 8, 1, 39.99);     -- Laptop Stand
UPDATE sales SET total_amount = (SELECT SUM(quantity * unit_price) FROM sale_items WHERE sale_id = @sale4_id) WHERE sale_id = @sale4_id;

-- Sale 5: Jack Anderson buys 3 items
INSERT INTO sales (customer_id, total_amount) VALUES (10, 0);
SET @sale5_id = LAST_INSERT_ID();
INSERT INTO sale_items (sale_id, product_id, quantity, unit_price) VALUES
(@sale5_id, 5, 1, 399.99),    -- Monitor
(@sale5_id, 7, 2, 34.99),     -- Desk Lamp x2
(@sale5_id, 9, 1, 129.99);    -- External SSD
UPDATE sales SET total_amount = (SELECT SUM(quantity * unit_price) FROM sale_items WHERE sale_id = @sale5_id) WHERE sale_id = @sale5_id;

-- Display summary
SELECT '' AS '';
SELECT '======================================' AS '';
SELECT '   DATA INSERTION SUMMARY' AS '';
SELECT '======================================' AS '';
SELECT CONCAT('Customers: ', COUNT(*)) AS 'Total Records' FROM customers;
SELECT CONCAT('Products: ', COUNT(*)) AS 'Total Records' FROM products;
SELECT CONCAT('Sales: ', COUNT(*)) AS 'Total Records' FROM sales;
SELECT CONCAT('Sale Items: ', COUNT(*)) AS 'Total Records' FROM sale_items;

SELECT '' AS '';
SELECT '======================================' AS '';
SELECT '   SALES DETAILS' AS '';
SELECT '======================================' AS '';
SELECT 
    s.sale_id AS 'Sale ID',
    c.customer_name AS 'Customer',
    c.city AS 'City',
    DATE_FORMAT(s.sale_date, '%Y-%m-%d %H:%i') AS 'Date',
    CONCAT('$', FORMAT(s.total_amount, 2)) AS 'Total',
    COUNT(si.product_id) AS 'Items'
FROM sales s
JOIN customers c ON s.customer_id = c.customer_id
JOIN sale_items si ON s.sale_id = si.sale_id
GROUP BY s.sale_id, c.customer_name, c.city, s.sale_date, s.total_amount
ORDER BY s.sale_id;

SELECT '' AS '';
SELECT '======================================' AS '';

EOF

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}=========================================="
    echo "✓ Mock data inserted successfully!"
    echo -e "==========================================${NC}"
    echo ""
    echo "Database: $DB_NAME"
    echo ""
    echo "Tables created:"
    echo "  - customers (10 records)"
    echo "  - products (10 records)"
    echo "  - sales (5 records)"
    echo "  - sale_items (relationship table)"
    echo ""
    echo "Connection: 127.0.0.1:$TUNNEL_PORT"
    echo ""
    echo -e "${BLUE}You can now query the data in your active MySQL session!${NC}"
    echo ""
else
    echo -e "${RED}✗ Failed to insert mock data${NC}"
    exit 1
fi
