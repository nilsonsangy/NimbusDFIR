# Azure DFIR Tools - Usage Examples

This directory contains forensic and incident response tools for Azure environments. Below are usage examples for each tool.

---

## Table of Contents
- [Installation Azure CLI](#installation-azure-cli)
- [Connection Testing](#connection-testing)

---

## Installation Azure CLI

### install_azure_cli_macos.sh
Install Azure CLI on macOS using Homebrew.

```bash
# Install Azure CLI
./install_azure_cli_macos.sh

# Verify installation
az --version
```

**Note:** The script will automatically install Homebrew if it's not already present on your system. It supports both Intel and Apple Silicon Macs.

---

## Connection Testing

### hello_az.sh
Test Azure credentials and connection.

```bash
# Test Azure connection (.sh / .ps1 / .py available)
./hello_az.sh

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