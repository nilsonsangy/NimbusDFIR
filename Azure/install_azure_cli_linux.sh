#!/bin/bash

# Script to install Azure CLI on Linux
# Author: NimbusDFIR
# Description: Installs the latest Azure CLI for Linux distributions

set -e

echo "=========================================="
echo "Azure CLI Installation Script for Linux"
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

# Detect Linux distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    VERSION_ID=$VERSION_ID
else
    echo "Error: Cannot detect Linux distribution"
    exit 1
fi

echo "Detected distribution: $DISTRO"
echo ""

# Install based on distribution
case $DISTRO in
    ubuntu|debian)
        echo "Installing Azure CLI for Debian/Ubuntu..."
        echo ""
        
        # Install prerequisites
        echo "Installing prerequisites..."
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg
        
        # Create keyring directory if it doesn't exist
        sudo mkdir -p /etc/apt/keyrings
        
        # Download and install Microsoft signing key
        echo "Adding Microsoft signing key..."
        curl -sLS https://packages.microsoft.com/keys/microsoft.asc | \
            gpg --dearmor | \
            sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
        sudo chmod go+r /etc/apt/keyrings/microsoft.gpg
        
        # Add Azure CLI repository
        echo "Adding Azure CLI repository..."
        AZ_REPO=$(lsb_release -cs)
        echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
            sudo tee /etc/apt/sources.list.d/azure-cli.list
        
        # Install Azure CLI
        echo "Installing Azure CLI..."
        sudo apt-get update
        sudo apt-get install -y azure-cli
        ;;
        
    rhel|centos|fedora)
        echo "Installing Azure CLI for RHEL/CentOS/Fedora..."
        echo ""
        
        # Import Microsoft repository key
        echo "Importing Microsoft repository key..."
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        
        # Add Azure CLI repository
        echo "Adding Azure CLI repository..."
        if [[ "$DISTRO" == "fedora" ]]; then
            sudo sh -c 'echo -e "[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/azure-cli.repo'
        else
            sudo sh -c 'echo -e "[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/azure-cli.repo'
        fi
        
        # Install Azure CLI
        echo "Installing Azure CLI..."
        if [[ "$DISTRO" == "fedora" ]]; then
            sudo dnf install -y azure-cli
        else
            sudo yum install -y azure-cli
        fi
        ;;
        
    opensuse*|sles)
        echo "Installing Azure CLI for openSUSE/SLES..."
        echo ""
        
        # Install prerequisites
        sudo zypper install -y curl
        
        # Import Microsoft repository key
        echo "Importing Microsoft repository key..."
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        
        # Add Azure CLI repository
        echo "Adding Azure CLI repository..."
        sudo zypper addrepo --name 'Azure CLI' --check https://packages.microsoft.com/yumrepos/azure-cli azure-cli
        
        # Install Azure CLI
        echo "Installing Azure CLI..."
        sudo zypper install -y --from azure-cli azure-cli
        ;;
        
    arch|manjaro)
        echo "Installing Azure CLI for Arch Linux..."
        echo ""
        
        # Install from AUR or official repo
        if command -v yay &> /dev/null; then
            echo "Installing via yay..."
            yay -S --noconfirm azure-cli
        elif command -v paru &> /dev/null; then
            echo "Installing via paru..."
            paru -S --noconfirm azure-cli
        else
            echo "Installing via pacman (official repo)..."
            sudo pacman -Sy --noconfirm azure-cli
        fi
        ;;
        
    *)
        echo "Unsupported distribution: $DISTRO"
        echo ""
        echo "For manual installation, please visit:"
        echo "https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux"
        exit 1
        ;;
esac

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
