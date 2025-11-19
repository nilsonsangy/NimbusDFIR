#!/usr/bin/env python3

"""
Azure MySQL Insert Mock Data Script - Python Version
Author: NimbusDFIR
Description: Insert mock data into an Azure MySQL Flexible Server
"""

import subprocess
import sys
import json
import os
import tempfile
import getpass
import psutil
import socket
from pathlib import Path

# Colors for output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color

def print_colored(message, color):
    """Print message with color"""
    print(f"{color}{message}{Colors.NC}")

def check_azure_cli():
    """Check if Azure CLI is installed"""
    try:
        subprocess.run(['az', '--version'], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print_colored("Error: Azure CLI is not installed", Colors.RED)
        print("Please install Azure CLI first")
        sys.exit(1)

def check_azure_login():
    """Check if logged in to Azure"""
    try:
        subprocess.run(['az', 'account', 'show'], capture_output=True, check=True)
    except subprocess.CalledProcessError:
        print_colored("Error: Not logged in to Azure", Colors.RED)
        print("Please run: az login")
        sys.exit(1)

def check_ssh_tunnel():
    """Check for active SSH tunnel"""
    tunnel_active = False
    local_port = 3307
    
    # Check if there's an SSH process running with MySQL tunnel
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        try:
            if proc.info['name'] == 'ssh' and proc.info['cmdline']:
                cmdline = ' '.join(proc.info['cmdline'])
                if '3307' in cmdline and '3306' in cmdline:
                    # Check if port 3307 is listening
                    try:
                        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                        sock.settimeout(1)
                        result = sock.connect_ex(('127.0.0.1', local_port))
                        sock.close()
                        if result == 0:
                            tunnel_active = True
                            break
                    except:
                        pass
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    
    return tunnel_active, local_port

def get_mysql_servers():
    """Get list of MySQL servers"""
    try:
        result = subprocess.run(['az', 'mysql', 'flexible-server', 'list', '--output', 'json'], 
                              capture_output=True, text=True, check=True)
        servers = json.loads(result.stdout)
        
        if not servers:
            print_colored("No MySQL flexible servers found", Colors.YELLOW)
            sys.exit(0)
        
        print_colored("Available MySQL Servers:", Colors.CYAN)
        print()
        
        for i, server in enumerate(servers, 1):
            print(f"{i}. {server['name']} ({server['resourceGroup']} - {server['state']})")
        
        print()
        return servers
    except subprocess.CalledProcessError as e:
        print_colored(f"Error retrieving MySQL servers: {e}", Colors.RED)
        sys.exit(1)

def get_server_info(server_name):
    """Get server information"""
    try:
        result = subprocess.run(['az', 'mysql', 'flexible-server', 'list', 
                               '--query', f"[?name=='{server_name}']", '-o', 'json'], 
                              capture_output=True, text=True, check=True)
        server_info = json.loads(result.stdout)
        
        if not server_info:
            print_colored(f"Error: MySQL server '{server_name}' not found", Colors.RED)
            sys.exit(1)
        
        server = server_info[0]
        print_colored(f"✓ Server found in resource group: {server['resourceGroup']}", Colors.GREEN)
        
        return {
            'name': server['name'],
            'resourceGroup': server['resourceGroup'],
            'status': server['state']
        }
    except subprocess.CalledProcessError as e:
        print_colored(f"Error getting server information: {e}", Colors.RED)
        sys.exit(1)

def get_mock_data_sql():
    """Get mock data SQL content"""
    return """
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
"""

def execute_mysql_via_tunnel(db_username, db_password, db_name, local_port, query=None, sql_file=None):
    """Execute MySQL command via SSH tunnel"""
    env = os.environ.copy()
    env['MYSQL_PWD'] = db_password
    
    cmd = ['mysql', '-h', '127.0.0.1', '-P', str(local_port), '-u', db_username]
    
    if db_name:
        cmd.append(db_name)
    
    if query:
        cmd.extend(['-e', query])
    
    try:
        if sql_file:
            with open(sql_file, 'r') as f:
                result = subprocess.run(cmd, input=f.read(), text=True, env=env, 
                                      capture_output=True, check=True)
        else:
            result = subprocess.run(cmd, env=env, capture_output=True, text=True, check=True)
        
        return True, result.stdout
    except subprocess.CalledProcessError as e:
        return False, e.stderr

def execute_mysql_via_azure_cli(server_name, db_username, db_password, db_name, query=None, sql_file=None):
    """Execute MySQL command via Azure CLI"""
    try:
        if sql_file:
            cmd = ['az', 'mysql', 'flexible-server', 'execute',
                   '--name', server_name,
                   '--admin-user', db_username,
                   '--admin-password', db_password,
                   '--database-name', db_name,
                   '--file-path', sql_file]
        else:
            cmd = ['az', 'mysql', 'flexible-server', 'execute',
                   '--name', server_name,
                   '--admin-user', db_username,
                   '--admin-password', db_password,
                   '--database-name', db_name,
                   '--querytext', query]
        
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return True, result.stdout
    except subprocess.CalledProcessError as e:
        return False, e.stderr

def show_usage():
    """Display usage information"""
    print_colored("==========================================", Colors.BLUE)
    print_colored("Azure MySQL Insert Mock Data - NimbusDFIR", Colors.BLUE)
    print_colored("==========================================", Colors.BLUE)
    print()
    print("Usage: python mysql_insert_mock_data.py [SERVER_NAME] [DATABASE_NAME]")
    print()
    print("Examples:")
    print("  python mysql_insert_mock_data.py                      # Interactive mode")
    print("  python mysql_insert_mock_data.py my-server testdb     # Direct mode")
    print()
    print("Mock data includes:")
    print("  - 10 customers")
    print("  - 10 products")
    print("  - 5 sales")
    print("  - Purchase details linking customers, sales, and products")
    print()

def main():
    """Main function"""
    if len(sys.argv) > 1 and sys.argv[1] in ['help', '--help', '-h']:
        show_usage()
        sys.exit(0)
    
    # Check prerequisites
    check_azure_cli()
    check_azure_login()
    
    print_colored("==========================================", Colors.BLUE)
    print_colored("Azure MySQL Insert Mock Data", Colors.BLUE)
    print_colored("==========================================", Colors.BLUE)
    print()
    
    # Check for active SSH tunnel first
    print_colored("Checking for active SSH tunnel...", Colors.BLUE)
    tunnel_active, local_port = check_ssh_tunnel()
    
    server_info = None
    server_name = None
    
    if not tunnel_active:
        print_colored("✗ No active SSH tunnel found", Colors.YELLOW)
        print_colored("Please run mysql_connect.py first to establish tunnel, then run this script", Colors.YELLOW)
        print_colored("Or use this script independently (will prompt for server selection)", Colors.CYAN)
        print()
        
        # Fallback to server selection mode
        server_name = sys.argv[1] if len(sys.argv) > 1 else None
        if not server_name:
            servers = get_mysql_servers()
            print()
            server_input = input("Select server number or enter name: ").strip()
            
            if not server_input:
                print_colored("Error: Server selection is required", Colors.RED)
                sys.exit(1)
            
            # Check if input is a number
            if server_input.isdigit():
                server_index = int(server_input) - 1
                if 0 <= server_index < len(servers):
                    server_name = servers[server_index]['name']
                else:
                    print_colored("Error: Invalid selection", Colors.RED)
                    sys.exit(1)
            else:
                server_name = server_input
    else:
        print_colored(f"✓ Active SSH tunnel detected on port {local_port}", Colors.GREEN)
        print_colored("Using existing SSH tunnel for data insertion", Colors.GREEN)
        print()
    
    # Get server information only if not using tunnel
    if not tunnel_active and server_name:
        print()
        print_colored("Finding server details...", Colors.BLUE)
        server_info = get_server_info(server_name)
    
    # Get database name
    db_name = sys.argv[2] if len(sys.argv) > 2 else None
    if not db_name:
        print()
        db_name = input("Enter database name to create (default: testdb): ").strip()
        if not db_name:
            db_name = "testdb"
    
    # Get admin credentials
    print()
    db_username = input("Enter MySQL admin username (default: mysqladmin): ").strip()
    if not db_username:
        db_username = "mysqladmin"
    
    print()
    db_password = getpass.getpass("Enter MySQL admin password: ")
    
    if not db_password:
        print_colored("Error: Password is required", Colors.RED)
        sys.exit(1)
    
    # Create database
    print()
    print_colored(f"Creating database '{db_name}'...", Colors.BLUE)
    
    if tunnel_active:
        print_colored("Using SSH tunnel connection...", Colors.GREEN)
        success, output = execute_mysql_via_tunnel(
            db_username, db_password, None, local_port, 
            query=f"CREATE DATABASE IF NOT EXISTS `{db_name}`;"
        )
    else:
        # Create database via Azure CLI
        try:
            subprocess.run(['az', 'mysql', 'flexible-server', 'db', 'create',
                           '--resource-group', server_info['resourceGroup'],
                           '--server-name', server_name,
                           '--database-name', db_name], 
                          capture_output=True, check=True)
            success = True
        except subprocess.CalledProcessError:
            success = True  # Database might already exist
    
    if success:
        print_colored("✓ Database ready", Colors.GREEN)
    
    # Create temporary SQL file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sql', delete=False) as temp_sql:
        temp_sql.write(get_mock_data_sql())
        temp_sql_path = temp_sql.name
    
    try:
        print()
        print_colored("Inserting mock data... (this may take a few moments)", Colors.YELLOW)
        print()
        
        # Execute SQL file
        if tunnel_active:
            success, output = execute_mysql_via_tunnel(
                db_username, db_password, db_name, local_port, sql_file=temp_sql_path
            )
        else:
            success, output = execute_mysql_via_azure_cli(
                server_name, db_username, db_password, db_name, sql_file=temp_sql_path
            )
        
        if success:
            print_colored("==========================================", Colors.GREEN)
            print_colored("✓ Mock data inserted successfully!", Colors.GREEN)
            print_colored("==========================================", Colors.GREEN)
            print()
            
            if tunnel_active:
                print(f"Connection: SSH Tunnel (localhost:{local_port})")
            else:
                print(f"Server: {server_name}")
                print(f"Resource Group: {server_info['resourceGroup']}")
            
            print(f"Database: {db_name}")
            print()
            print("Tables created:")
            print("  - customers (10 records)")
            print("  - products (10 records)")
            print("  - sales (5 records)")
            print("  - sale_items (relationship table)")
            print()
            
            # Display summary
            print_colored("Fetching data summary...", Colors.BLUE)
            print()
            
            # Count records in each table
            print_colored("Table Record Counts:", Colors.CYAN)
            count_query = ("SELECT 'Customers' as Table_Name, COUNT(*) as Total FROM customers "
                          "UNION ALL SELECT 'Products', COUNT(*) FROM products "
                          "UNION ALL SELECT 'Sales', COUNT(*) FROM sales "
                          "UNION ALL SELECT 'Sale Items', COUNT(*) FROM sale_items;")
            
            if tunnel_active:
                success, output = execute_mysql_via_tunnel(
                    db_username, db_password, db_name, local_port, query=count_query
                )
            else:
                success, output = execute_mysql_via_azure_cli(
                    server_name, db_username, db_password, db_name, query=count_query
                )
            
            if success:
                print(output)
            
            print()
            print_colored("Sales Summary:", Colors.CYAN)
            sales_query = ("SELECT c.customer_name AS Customer, c.city AS City, "
                          "CONCAT('$', FORMAT(s.total_amount, 2)) AS Total "
                          "FROM sales s JOIN customers c ON s.customer_id = c.customer_id "
                          "ORDER BY s.sale_id;")
            
            if tunnel_active:
                success, output = execute_mysql_via_tunnel(
                    db_username, db_password, db_name, local_port, query=sales_query
                )
            else:
                success, output = execute_mysql_via_azure_cli(
                    server_name, db_username, db_password, db_name, query=sales_query
                )
            
            if success:
                print(output)
            
            print()
            print_colored("All operations completed successfully!", Colors.GREEN)
        else:
            print_colored("✗ Failed to insert mock data", Colors.RED)
            print_colored(f"Error: {output}", Colors.RED)
            sys.exit(1)
            
    finally:
        # Cleanup temporary file
        try:
            os.unlink(temp_sql_path)
        except:
            pass

if __name__ == "__main__":
    main()