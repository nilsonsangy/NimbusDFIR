#!/bin/bash

# Script to install Azure CLI on macOS
# Author: NimbusDFIR
# Description: Installs the latest Azure CLI for macOS using Homebrew

set -e

echo "=========================================="
echo "Azure CLI Installation Script for macOS"
echo "=========================================="
echo ""

# Check if Azure CLI is already installed
if command -v az &> /dev/null; then
    CURRENT_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    echo "Azure CLI is already installed (version: $CURRENT_VERSION)"
    read -p "Do you want to reinstall/update? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
fi

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "Homebrew is not installed. Installing Homebrew first..."
    echo "This will require your password."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install Homebrew"
        exit 1
    fi
    
    # Add Homebrew to PATH for Apple Silicon Macs
    if [[ $(uname -m) == 'arm64' ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi

echo "Updating Homebrew..."
brew update

echo ""
echo "Installing Azure CLI..."
if command -v az &> /dev/null; then
    # If Azure CLI exists, upgrade it
    brew upgrade azure-cli
else
    # Fresh install
    brew install azure-cli
fi

if [ $? -ne 0 ]; then
    echo "Error: Failed to install Azure CLI"
    exit 1
fi

# Verify installation
echo ""
echo "Verifying installation..."
if command -v az &> /dev/null; then
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null)
    echo "✓ Azure CLI installed successfully!"
    echo "Version: $AZ_VERSION"
    echo ""
    echo "To log in to Azure, run:"
    echo "  az login"
    echo ""
    echo "To configure default subscription, run:"
    echo "  az account set --subscription <subscription-id>"
else
    echo "✗ Installation verification failed"
    exit 1
fi

echo ""
echo "Installation complete!"
