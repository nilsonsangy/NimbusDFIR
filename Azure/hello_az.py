#!/usr/bin/env python3

"""
Azure Connection Test Script
Author: NimbusDFIR
Description: Tests Azure connection and displays account information
"""

import subprocess
import sys
import json
from typing import Optional

# ANSI color codes
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color

def run_az_command(command: list, capture_output: bool = True) -> Optional[str]:
    """Run an Azure CLI command and return output."""
    try:
        if capture_output:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout.strip()
        else:
            subprocess.run(command, check=True)
            return None
    except subprocess.CalledProcessError:
        return None
    except FileNotFoundError:
        return None

def check_az_installed() -> bool:
    """Check if Azure CLI is installed."""
    result = run_az_command(['az', '--version'])
    return result is not None

def check_logged_in() -> bool:
    """Check if user is logged in to Azure."""
    result = run_az_command(['az', 'account', 'show'])
    return result is not None

def get_account_info() -> dict:
    """Get Azure account information."""
    result = run_az_command(['az', 'account', 'show', '--output', 'json'])
    if result:
        return json.loads(result)
    return {}

def get_subscriptions() -> list:
    """Get all Azure subscriptions."""
    result = run_az_command(['az', 'account', 'list', '--output', 'json'])
    if result:
        return json.loads(result)
    return []

def get_locations() -> list:
    """Get Azure locations."""
    result = run_az_command(['az', 'account', 'list-locations', '--output', 'json'])
    if result:
        return json.loads(result)
    return []

def get_az_version() -> str:
    """Get Azure CLI version."""
    result = run_az_command(['az', 'version', '--output', 'json'])
    if result:
        version_info = json.loads(result)
        return version_info.get('azure-cli', 'unknown')
    return 'unknown'

def main():
    """Main function."""
    print(f"{Colors.BLUE}==========================================")
    print("Azure Connection Test - NimbusDFIR")
    print(f"=========================================={Colors.NC}")
    print()

    # Check if Azure CLI is installed
    if not check_az_installed():
        print(f"{Colors.RED}[ERROR]{Colors.NC} Azure CLI is not installed")
        print()
        print("To install Azure CLI:")
        print(f"  macOS: {Colors.GREEN}brew install azure-cli{Colors.NC}")
        print(f"  Windows: {Colors.GREEN}winget install Microsoft.AzureCLI{Colors.NC}")
        print(f"  Linux: {Colors.GREEN}curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash{Colors.NC}")
        sys.exit(1)

    # Check if logged in
    print(f"{Colors.BLUE}[INFO]{Colors.NC} Checking Azure authentication...")
    if not check_logged_in():
        print(f"{Colors.RED}[ERROR]{Colors.NC} Not logged in to Azure")
        print()
        print("Please log in first:")
        print(f"  {Colors.GREEN}az login{Colors.NC}")
        sys.exit(1)

    print(f"{Colors.GREEN}[SUCCESS]{Colors.NC} Azure connection successful!")
    print()

    # Get account information
    account_info = get_account_info()
    if account_info:
        print(f"{Colors.CYAN}Account Information:{Colors.NC}")
        print("====================")
        print(f"  Account Name: {Colors.GREEN}{account_info.get('name', 'N/A')}{Colors.NC}")
        print(f"  Subscription ID: {Colors.GREEN}{account_info.get('id', 'N/A')}{Colors.NC}")
        print(f"  Tenant ID: {Colors.GREEN}{account_info.get('tenantId', 'N/A')}{Colors.NC}")
        print(f"  User: {Colors.GREEN}{account_info.get('user', {}).get('name', 'N/A')}{Colors.NC}")
        print(f"  Type: {Colors.GREEN}{account_info.get('user', {}).get('type', 'N/A')}{Colors.NC}")
        print()

    # List subscriptions
    subscriptions = get_subscriptions()
    if subscriptions:
        print(f"{Colors.CYAN}Available Subscriptions:{Colors.NC}")
        print("====================")
        for sub in subscriptions:
            is_default = "✓" if sub.get('isDefault', False) else " "
            print(f"  [{is_default}] {sub.get('name', 'N/A')} ({sub.get('state', 'N/A')})")
            print(f"      ID: {sub.get('id', 'N/A')}")
        print()

    # List locations
    locations = get_locations()
    if locations:
        print(f"{Colors.CYAN}Available Locations (Regions):{Colors.NC}")
        print("====================")
        for i, loc in enumerate(locations[:20], 1):
            print(f"  {i:2}. {loc.get('displayName', 'N/A'):30} ({loc.get('name', 'N/A')})")
        if len(locations) > 20:
            print(f"... (showing first 20 of {len(locations)} regions)")
        print()

    # Get Azure CLI version
    az_version = get_az_version()
    print(f"{Colors.BLUE}[INFO]{Colors.NC} Azure CLI Version: {Colors.GREEN}{az_version}{Colors.NC}")
    print()

    print(f"{Colors.GREEN}[SUCCESS]{Colors.NC} All checks completed successfully!")

if __name__ == '__main__':
    main()
