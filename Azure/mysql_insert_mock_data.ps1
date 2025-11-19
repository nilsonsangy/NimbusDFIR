# Azure MySQL Insert Mock Data Script - PowerShell Version
# Author: NimbusDFIR
# Description: Insert mock data into an Azure MySQL Flexible Server

param(
    [Parameter(Position=0)]
    [string]$ServerName,
    
    [Parameter(Position=1)]
    [string]$DatabaseName,
    
    [Parameter()]
    [switch]$Help
)

# Check if Azure CLI is installed
function Test-AzureCLI {
    $azCmd = Get-Command az -ErrorAction SilentlyContinue
    if (-not $azCmd) {
        Write-Host "Error: Azure CLI is not installed" -ForegroundColor Red
        Write-Host "Please install Azure CLI first"
        exit 1
    }
}

# Check if logged in to Azure
function Test-AzureLogin {
    try {
        $null = az account show 2>$null
    }
    catch {
        Write-Host "Error: Not logged in to Azure" -ForegroundColor Red
        Write-Host "Please run: az login"
        exit 1
    }
}

# Display usage information
function Show-Usage {
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "Azure MySQL Insert Mock Data - NimbusDFIR"
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Usage: .\mysql_insert_mock_data.ps1 [SERVER_NAME] [DATABASE_NAME]"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\mysql_insert_mock_data.ps1                      # Interactive mode"
    Write-Host "  .\mysql_insert_mock_data.ps1 my-server testdb     # Direct mode"
    Write-Host ""
    Write-Host "Mock data includes:"
    Write-Host "  - 10 customers"
    Write-Host "  - 10 products"
    Write-Host "  - 5 sales"
    Write-Host "  - Purchase details linking customers, sales, and products"
    Write-Host ""
}

# List available MySQL servers
function Get-MySQLServers {
    Write-Host "Available MySQL Servers:" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        $servers = az mysql flexible-server list --output json | ConvertFrom-Json
        
        if ($servers.Count -eq 0) {
            Write-Host "No MySQL flexible servers found" -ForegroundColor Yellow
            exit 0
        }
        
        for ($i = 0; $i -lt $servers.Count; $i++) {
            $server = $servers[$i]
            Write-Host "$($i + 1). $($server.name) ($($server.resourceGroup) - $($server.state))"
        }
        Write-Host ""
        
        return $servers
    }
    catch {
        Write-Host "Error retrieving MySQL servers: $_" -ForegroundColor Red
        exit 1
    }
}

# Get server information
function Get-ServerInfo {
    param([string]$ServerName)
    
    try {
        $serverInfo = az mysql flexible-server list --query "[?name=='$ServerName']" -o json | ConvertFrom-Json
        
        if ($serverInfo.Count -eq 0) {
            Write-Host "Error: MySQL server '$ServerName' not found" -ForegroundColor Red
            exit 1
        }
        
        $server = $serverInfo[0]
        Write-Host "✓ Server found in resource group: $($server.resourceGroup)" -ForegroundColor Green
        
        return @{
            Name = $server.name
            ResourceGroup = $server.resourceGroup
            Status = $server.state
        }
    }
    catch {
        Write-Host "Error getting server information: $_" -ForegroundColor Red
        exit 1
    }
}

# Create mock data SQL content
function Get-MockDataSQL {
    return @"
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
"@
}

# Main script execution
try {
    if ($Help) {
        Show-Usage
        exit 0
    }
    
    # Check prerequisites
    Test-AzureCLI
    Test-AzureLogin
    
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "Azure MySQL Insert Mock Data"
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host ""
    
    # Check for active SSH tunnel first
    Write-Host "Checking for active SSH tunnel..." -ForegroundColor Blue
    
    # Check if there's an SSH process running with MySQL tunnel
    $sshProcesses = Get-Process -Name "ssh" -ErrorAction SilentlyContinue | Where-Object { 
        $_.ProcessName -eq "ssh" 
    }
    
    $tunnelActive = $false
    $localPort = 3307  # Default tunnel port
    
    if ($sshProcesses) {
        # Check if port 3307 is listening (typical MySQL tunnel port)
        try {
            $tcpConnection = Get-NetTCPConnection -LocalPort $localPort -State Listen -ErrorAction SilentlyContinue
            if ($tcpConnection) {
                $tunnelActive = $true
                Write-Host "✓ Active SSH tunnel detected on port $localPort" -ForegroundColor Green
            }
        }
        catch {
            # Port check failed, no tunnel
        }
    }
    
    if (-not $tunnelActive) {
        Write-Host "✗ No active SSH tunnel found" -ForegroundColor Yellow
        Write-Host "Please run mysql_connect.ps1 first to establish tunnel, then run this script" -ForegroundColor Yellow
        Write-Host "Or use this script independently (will prompt for server selection)" -ForegroundColor Cyan
        Write-Host ""
        
        # Fallback to server selection mode
        if (-not $ServerName) {
            $servers = Get-MySQLServers
            Write-Host ""
            $serverInput = Read-Host "Select server number or enter name"
            
            if (-not $serverInput) {
                Write-Host "Error: Server selection is required" -ForegroundColor Red
                exit 1
            }
            
            # Check if input is a number
            if ($serverInput -match '^\d+$') {
                $serverIndex = [int]$serverInput - 1
                if ($serverIndex -ge 0 -and $serverIndex -lt $servers.Count) {
                    $ServerName = $servers[$serverIndex].name
                } else {
                    Write-Host "Error: Invalid selection" -ForegroundColor Red
                    exit 1
                }
            } else {
                $ServerName = $serverInput
            }
        }
    } else {
        Write-Host "Using existing SSH tunnel for data insertion" -ForegroundColor Green
        Write-Host ""
    }
    
    # Get database name
    if (-not $DatabaseName) {
        Write-Host ""
        $DatabaseName = Read-Host "Enter database name to create (default: testdb)"
        if (-not $DatabaseName) {
            $DatabaseName = "testdb"
        }
    }
    
    # Get admin credentials
    Write-Host ""
    $dbUsername = Read-Host "Enter MySQL admin username (default: mysqladmin)"
    if (-not $dbUsername) {
        $dbUsername = "mysqladmin"
    }
    
    Write-Host ""
    $dbPassword = Read-Host "Enter MySQL admin password" -AsSecureString
    $dbPasswordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($dbPassword))
    
    if (-not $dbPasswordPlain) {
        Write-Host "Error: Password is required" -ForegroundColor Red
        exit 1
    }
    
    # Get server information only if not using tunnel
    if (-not $tunnelActive -and $ServerName) {
        Write-Host ""
        Write-Host "Finding server details..." -ForegroundColor Blue
        $serverInfo = Get-ServerInfo -ServerName $ServerName
    }
    
    # Create temporary SQL file
    $tempSqlFile = [System.IO.Path]::GetTempFileName() + ".sql"
    $mockDataSQL = Get-MockDataSQL
    $mockDataSQL | Out-File -FilePath $tempSqlFile -Encoding utf8
    
    try {
        Write-Host ""
        Write-Host "Inserting mock data... (this may take a few moments)" -ForegroundColor Yellow
        Write-Host ""
        
        if ($tunnelActive) {
            # Use SSH tunnel - connect directly to localhost:3307
            Write-Host "Using SSH tunnel connection..." -ForegroundColor Green
            
            # Create database first
            Write-Host "Creating database '$DatabaseName'..." -ForegroundColor Blue
            $createDbCmd = "CREATE DATABASE IF NOT EXISTS ``$DatabaseName``;"
            
            # Use environment variable for password (more secure)
            $env:MYSQL_PWD = $dbPasswordPlain
            try {
                & mysql -h 127.0.0.1 -P $localPort -u $dbUsername -e $createDbCmd 2>$null
                Write-Host "✓ Database ready" -ForegroundColor Green
                
                # Execute SQL file using mysql client through tunnel
                Get-Content $tempSqlFile | & mysql -h 127.0.0.1 -P $localPort -u $dbUsername $DatabaseName
            }
            finally {
                # Clear the password from environment immediately
                Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
            }
            $success = $LASTEXITCODE -eq 0
            
        } else {
            # Use Azure CLI method
            # Create database if not exists
            Write-Host "Creating database '$DatabaseName'..." -ForegroundColor Blue
            try {
                az mysql flexible-server db create `
                    --resource-group $serverInfo.ResourceGroup `
                    --server-name $ServerName `
                    --database-name $DatabaseName `
                    --output none 2>$null
                Write-Host "✓ Database ready" -ForegroundColor Green
            }
            catch {
                # Database might already exist, continue
                Write-Host "✓ Database ready (may already exist)" -ForegroundColor Green
            }
            
            # Execute SQL file using Azure CLI
            $result = az mysql flexible-server execute `
                --name $ServerName `
                --admin-user $dbUsername `
                --admin-password $dbPasswordPlain `
                --database-name $DatabaseName `
                --file-path $tempSqlFile 2>&1
            
            $success = $LASTEXITCODE -eq 0
        }
        
        # Check if successful
        if ($success) {
            Write-Host "==========================================" -ForegroundColor Green
            Write-Host "✓ Mock data inserted successfully!"
            Write-Host "==========================================" -ForegroundColor Green
            Write-Host ""
            if ($tunnelActive) {
                Write-Host "Connection: SSH Tunnel (localhost:$localPort)"
            } else {
                Write-Host "Server: $ServerName"
                Write-Host "Resource Group: $($serverInfo.ResourceGroup)"
            }
            Write-Host "Database: $DatabaseName"
            Write-Host ""
            Write-Host "Tables created:"
            Write-Host "  - customers (10 records)"
            Write-Host "  - products (10 records)"
            Write-Host "  - sales (5 records)"
            Write-Host "  - sale_items (relationship table)"
            Write-Host ""
            
            # Display summary by querying the database
            Write-Host "Fetching data summary..." -ForegroundColor Blue
            Write-Host ""
            
            # Count records in each table
            Write-Host "Table Record Counts:" -ForegroundColor Cyan
            $countQuery = "SELECT 'Customers' as Table_Name, COUNT(*) as Total FROM customers UNION ALL SELECT 'Products', COUNT(*) FROM products UNION ALL SELECT 'Sales', COUNT(*) FROM sales UNION ALL SELECT 'Sale Items', COUNT(*) FROM sale_items;"
            
            if ($tunnelActive) {
                # Use environment variable for secure password handling
                $env:MYSQL_PWD = $dbPasswordPlain
                try {
                    & mysql -h 127.0.0.1 -P $localPort -u $dbUsername $DatabaseName -e $countQuery
                }
                finally {
                    Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
                }
            } else {
                az mysql flexible-server execute `
                    --name $ServerName `
                    --admin-user $dbUsername `
                    --admin-password $dbPasswordPlain `
                    --database-name $DatabaseName `
                    --querytext $countQuery 2>$null
            }
            
            Write-Host ""
            Write-Host "Sales Summary:" -ForegroundColor Cyan
            $salesQuery = "SELECT c.customer_name AS Customer, c.city AS City, CONCAT('$', FORMAT(s.total_amount, 2)) AS Total FROM sales s JOIN customers c ON s.customer_id = c.customer_id ORDER BY s.sale_id;"
            
            if ($tunnelActive) {
                # Use environment variable for secure password handling
                $env:MYSQL_PWD = $dbPasswordPlain
                try {
                    & mysql -h 127.0.0.1 -P $localPort -u $dbUsername $DatabaseName -e $salesQuery
                }
                finally {
                    Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
                }
            } else {
                az mysql flexible-server execute `
                    --name $ServerName `
                    --admin-user $dbUsername `
                    --admin-password $dbPasswordPlain `
                    --database-name $DatabaseName `
                    --querytext $salesQuery 2>$null
            }
            
            Write-Host ""
            Write-Host "All operations completed successfully!" -ForegroundColor Green
        } else {
            Write-Host "✗ Failed to insert mock data" -ForegroundColor Red
            Write-Host "Error output: $result" -ForegroundColor Red
            exit 1
        }
    }
    finally {
        # Cleanup temporary files and ensure password is cleared
        if (Test-Path $tempSqlFile) {
            Remove-Item $tempSqlFile -Force -ErrorAction SilentlyContinue
        }
        # Ensure password environment variable is cleared
        Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
    }
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}