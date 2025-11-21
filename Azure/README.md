# Azure DFIR Tools - Usage Examples

This directory contains forensic and incident response tools for Azure environments. Below are usage examples for each tool.

---

## Table of Contents
- [Installation Azure CLI](#installation-azure-cli)
- [Connection Testing](#connection-testing)
- [Blob Storage Management](#blob-storage-management)
- [Storage Account Management](#storage-account-management)
- [VM Management](#vm-management)
- [MySQL Management](#mysql-management)

---

## Script Inventory

| Script | Description |
|--------|-------------|
| blob_storage_manager.sh / .ps1 / .py | Manage Azure Blob Storage containers and blobs |
| hello_az.sh / .ps1 / .py | Tests Azure connection and prints account info and subscriptions |
| install_azure_cli_linux.sh | Installs Azure CLI on Linux |
| install_azure_cli_macos.sh | Installs Azure CLI on macOS |
| install_azure_cli_windows.ps1 | Installs Azure CLI on Windows with automatic configuration |
| install_mysql_windows.ps1 | Installs MySQL Community Server on Windows with PATH configuration |
| mysql_connect.sh / .ps1 / .py | Connect to Azure MySQL Flexible Server (public or private via jump server) |
| mysql_dump_database.sh / .ps1 / .py | Dump Azure MySQL databases |
| mysql_insert_mock_data.sh / .ps1 / .py | Insert mock data into Azure MySQL |
| storage_account_manager.sh / .ps1 / .py | Manage Azure Storage Accounts (AAD, TLS, role assignment) |
| vm_manager.sh / .ps1 / .py | Manage Azure VMs (list, create, start, stop, delete) |

---

## Installation Azure CLI

### install_azure_cli_macos.sh / install_azure_cli_linux.sh / install_azure_cli_windows.ps1
Install Azure CLI on macOS, Linux, or Windows.

```bash
# Install Azure CLI (macOS)
./install_azure_cli_macos.sh
# Install Azure CLI (Linux)
./install_azure_cli_linux.sh
# Install Azure CLI (Windows)
./install_azure_cli_windows.ps1

# Verify installation
az --version
```

**Note:** The macOS script will automatically install Homebrew if it's not already present. It supports both Intel and Apple Silicon Macs.

---

## Connection Testing

### hello_az.sh / hello_az.ps1 / hello_az.py
Test Azure credentials and connection.

```bash
# Test Azure connection (.sh / .ps1 / .py available)
./hello_az.sh
./hello_az.ps1
python3 hello_az.py

# Output shows:
# - Account name
# - Subscription ID
# - Tenant ID
# - User information
# - Available subscriptions
# - Azure regions (first 20)
# - Azure CLI version
```

**Note:** All connection test scripts require you to be logged in to Azure. If not logged in, they will prompt you to run `az login`.

---

## Blob Storage Management

### blob_storage_manager.sh / .ps1 / .py
Manage Azure Blob Storage containers and blobs.

```bash
# List all blob containers
./blob_storage_manager.sh list

# Upload files to a container
./blob_storage_manager.sh upload file1.txt file2.txt mycontainer

# Download blobs from a container
./blob_storage_manager.sh download mycontainer

# Dump all blobs in a container as a zip
./blob_storage_manager.sh dump mycontainer

# Show container info
./blob_storage_manager.sh info mycontainer
```

---

## Storage Account Management

### storage_account_manager.sh / .ps1 / .py
Manage Azure Storage Accounts (AAD, TLS, role assignment).

```bash
# List all storage accounts
./storage_account_manager.sh list

# Create a new storage account (with AAD, TLS, and role assignment)
./storage_account_manager.sh create

# Delete a storage account
./storage_account_manager.sh delete mystorageaccount
```

---

## VM Management

### vm_manager.sh / .ps1 / .py
Manage Azure VMs (list, create, start, stop, delete).

```bash
# List all VMs
./vm_manager.sh list

# Create a new VM
./vm_manager.sh create

# Start a VM
./vm_manager.sh start myvm

# Stop a VM
./vm_manager.sh stop myvm

# Delete a VM
./vm_manager.sh delete myvm
```

---

## MySQL Management

### mysql_connect.sh / .ps1 / .py
Connect to Azure MySQL Flexible Server (public or private via jump server).

```bash
# Connect to MySQL
./mysql_connect.sh
```

### mysql_dump_database.sh / .ps1 / .py
Dump Azure MySQL databases.

```bash
# Dump database
./mysql_dump_database.sh
```

### mysql_insert_mock_data.sh / .ps1 / .py
Insert mock data into Azure MySQL.

```bash
# Insert mock data
./mysql_insert_mock_data.sh
```