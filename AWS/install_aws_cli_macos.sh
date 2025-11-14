#!/bin/bash

# Script to install AWS CLI on macOS
# Author: NimbusDFIR
# Description: Downloads and installs the latest AWS CLI v2 for macOS

set -e

echo "=========================================="
echo "AWS CLI Installation Script for macOS"
echo "=========================================="
echo ""

# Check if AWS CLI is already installed
if command -v aws &> /dev/null; then
    CURRENT_VERSION=$(aws --version 2>&1 | cut -d ' ' -f1 | cut -d '/' -f2)
    echo "AWS CLI is already installed (version: $CURRENT_VERSION)"
    read -p "Do you want to reinstall/update? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo "Downloading AWS CLI v2 for macOS..."
curl -sS "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"

if [ $? -ne 0 ]; then
    echo "Error: Failed to download AWS CLI installer"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "Installing AWS CLI..."
sudo installer -pkg AWSCLIV2.pkg -target /

if [ $? -ne 0 ]; then
    echo "Error: Failed to install AWS CLI"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Clean up
echo "Cleaning up temporary files..."
cd - > /dev/null
rm -rf "$TEMP_DIR"

# Verify installation
echo ""
echo "Verifying installation..."
if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version 2>&1)
    echo "✓ AWS CLI installed successfully!"
    echo "Version: $AWS_VERSION"
    echo ""
    echo "To configure AWS CLI, run:"
    echo "  aws configure"
else
    echo "✗ Installation verification failed"
    exit 1
fi

echo ""
echo "Installation complete!"
