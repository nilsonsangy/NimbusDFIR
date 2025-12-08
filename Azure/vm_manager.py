#!/usr/bin/env python3

"""
Azure VM Manager Script - Python
Author: NimbusDFIR
Description: Manage Azure VMs - list, create, start, stop, and delete VMs
"""

import sys
import subprocess
import json
import argparse
from datetime import datetime
import getpass

# Colors for terminal output
class Colors:
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    WHITE = '\033[97m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

def print_colored(message, color=Colors.WHITE):
    """Print colored message to terminal"""
    print(f"{color}{message}{Colors.RESET}")

def run_az_command(command, capture_output=True, check=True):
    """Run Azure CLI command and return result"""
    try:
        if isinstance(command, str):
            # Print command before execution
            print_colored(f"[Azure CLI] {command}", Colors.CYAN)
            command = command.split()
        else:
            # Command is already a list - mask password if present
            display_cmd = command.copy()
            for i, arg in enumerate(display_cmd):
                if arg in ['--admin-password', '--password', '-p'] and i + 1 < len(display_cmd):
                    display_cmd[i + 1] = '********'
            print_colored(f"[Azure CLI] {' '.join(display_cmd)}", Colors.CYAN)
        
        result = subprocess.run(
            command,
            capture_output=capture_output,
            text=True,
            check=check
        )
        
        if capture_output:
            return result.stdout.strip(), result.stderr.strip(), result.returncode
        else:
            return None, None, result.returncode
            
    except subprocess.CalledProcessError as e:
        if capture_output:
            return e.stdout, e.stderr, e.returncode
        else:
            return None, None, e.returncode
    except FileNotFoundError:
        print_colored("ERROR: Azure CLI is not installed", Colors.RED)
        print_colored("Please install Azure CLI first", Colors.YELLOW)
        print_colored("Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli", Colors.GREEN)
        sys.exit(1)

def check_prerequisites():
    """Check if Azure CLI is installed and user is logged in"""
    # Check Azure CLI installation
    stdout, stderr, returncode = run_az_command("az --version")
    if returncode != 0:
        print_colored("ERROR: Azure CLI is not installed", Colors.RED)
        sys.exit(1)
    
    # Check if logged in
    stdout, stderr, returncode = run_az_command("az account show")
    if returncode != 0:
        print_colored("ERROR: Not logged in to Azure", Colors.RED)
        print_colored("Please run: az login", Colors.YELLOW)
        sys.exit(1)

def show_usage():
    """Display usage information"""
    print_colored("==========================================", Colors.BLUE)
    print_colored("Azure VM Manager - NimbusDFIR", Colors.BLUE)
    print_colored("==========================================", Colors.BLUE)
    print()
    print("Usage: python vm_manager.py [COMMAND] [OPTIONS]")
    print()
    print("Commands:")
    print("  list              List all VMs in current subscription")
    print("  create            Create a new VM")
    print("  delete            Delete a VM")
    print("  start             Start a stopped VM")
    print("  stop              Stop a running VM (deallocate)")
    print("  help              Show this help message")
    print()
    print("Examples:")
    print("  python vm_manager.py list")
    print("  python vm_manager.py create")
    print("  python vm_manager.py delete myVM")
    print("  python vm_manager.py start myVM")
    print("  python vm_manager.py stop myVM")
    print()

def list_vms():
    """List all VMs in the current subscription"""
    print_colored("Listing Azure VMs...", Colors.BLUE)
    print()
    
    stdout, stderr, returncode = run_az_command("az vm list --output json")
    if returncode != 0:
        print_colored(f"Error listing VMs: {stderr}", Colors.RED)
        return
    
    try:
        vms = json.loads(stdout) if stdout else []
    except json.JSONDecodeError:
        print_colored("Error parsing VM list", Colors.RED)
        return
    
    if not vms:
        print_colored("No VMs found in current subscription", Colors.YELLOW)
        return
    
    print_colored("VM Name\t\t\tResource Group\t\tLocation\tSize\t\tState", Colors.CYAN)
    print("----------------------------------------------------------------------------------------")
    
    for vm in vms:
        # Get power state
        power_cmd = f"az vm get-instance-view --name {vm['name']} --resource-group {vm['resourceGroup']} --query \"instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus\" -o tsv"
        power_stdout, _, power_returncode = run_az_command(power_cmd)
        power_state = power_stdout if power_returncode == 0 else "Unknown"
        
        # Choose color based on state
        color = Colors.WHITE
        if "running" in power_state.lower():
            color = Colors.GREEN
        elif "stopped" in power_state.lower() or "deallocated" in power_state.lower():
            color = Colors.YELLOW
        
        vm_info = f"{vm['name']}\t\t{vm['resourceGroup']}\t\t{vm['location']}\t{vm['hardwareProfile']['vmSize']}\t{power_state}"
        print_colored(vm_info, color)

def create_vm():
    """Create a new Azure VM"""
    print_colored("Create New Azure VM", Colors.BLUE)
    print()
    
    # Get VM name
    default_name = f"azure-vm-{datetime.now().strftime('%Y%m%d%H%M%S')}"
    vm_name = input(f"Enter VM name (default: {default_name}): ").strip()
    if not vm_name:
        vm_name = default_name
    
    # Get or create resource group
    print()
    print_colored("Available Resource Groups:", Colors.CYAN)
    stdout, stderr, returncode = run_az_command('az group list --query "[].{Name:name, Location:location}" -o json')
    
    resource_groups = []
    if returncode == 0 and stdout:
        try:
            resource_groups = json.loads(stdout)
            for i, rg in enumerate(resource_groups, 1):
                print(f"  {i}. {rg['Name']} ({rg['Location']})")
        except json.JSONDecodeError:
            pass
    
    if not resource_groups:
        print("  No resource groups found")
    
    print()
    rg_input = input("Enter resource group name or number (default: rg-forensics): ").strip()
    if not rg_input:
        rg_name = "rg-forensics"
    elif rg_input.isdigit() and resource_groups:
        rg_index = int(rg_input) - 1
        if 0 <= rg_index < len(resource_groups):
            rg_name = resource_groups[rg_index]['Name']
        else:
            print_colored("Invalid resource group number. Using default: rg-forensics", Colors.YELLOW)
            rg_name = "rg-forensics"
    else:
        rg_name = rg_input
    
    # Check if resource group exists
    stdout, stderr, returncode = run_az_command(f"az group show --name {rg_name}")
    if returncode != 0:
        print_colored("Resource group does not exist. Creating...", Colors.YELLOW)
        location = input("Enter location (default: northcentralus): ").strip()
        if not location:
            location = "northcentralus"
        
        _, _, returncode = run_az_command(f"az group create --name {rg_name} --location {location} --output table", capture_output=False)
        if returncode == 0:
            print_colored("✓ Resource group created", Colors.GREEN)
        else:
            print_colored("✗ Failed to create resource group", Colors.RED)
            return
    else:
        # Get location from existing resource group
        location_stdout, _, _ = run_az_command(f"az group show --name {rg_name} --query location -o tsv")
        location = location_stdout if location_stdout else "northcentralus"
    
    # Get VM size
    print()
    print_colored("Select VM Size:", Colors.CYAN)
    print("  1. Standard_B1s   - 1 vCPU, 1 GB RAM  (Lowest cost)")
    print("  2. Standard_B1ms  - 1 vCPU, 2 GB RAM")
    print("  3. Standard_B2s   - 2 vCPU, 4 GB RAM")
    print("  4. Standard_D2s_v3 - 2 vCPU, 8 GB RAM")
    print()
    
    vm_size_choice = input("Choose VM size [1-4] (default: 1): ").strip()
    if not vm_size_choice:
        vm_size_choice = "1"
    
    vm_sizes = {
        "1": "Standard_B1s",
        "2": "Standard_B1ms",
        "3": "Standard_B2s",
        "4": "Standard_D2s_v3"
    }
    vm_size = vm_sizes.get(vm_size_choice, "Standard_B1s")
    
    # Get image
    print()
    print_colored("Select Image:", Colors.CYAN)
    print("  1. Ubuntu2204     - Ubuntu 22.04 LTS")
    print("  2. Ubuntu2404     - Ubuntu 24.04 LTS")
    print("  3. Debian11       - Debian 11")
    print("  4. Win2022Datacenter - Windows Server 2022")
    print("  5. Win2019Datacenter - Windows Server 2019")
    print()
    
    image_choice = input("Choose image [1-5] (default: 1): ").strip()
    if not image_choice:
        image_choice = "1"
    
    images = {
        "1": "Ubuntu2204",
        "2": "Ubuntu2404",
        "3": "Debian11",
        "4": "Win2022Datacenter",
        "5": "Win2019Datacenter"
    }
    image = images.get(image_choice, "Ubuntu2204")
    
    # Get authentication
    print()
    admin_user = input("Enter admin username (default: azureuser): ").strip()
    if not admin_user:
        admin_user = "azureuser"
    
    print()
    print_colored("Authentication Method:", Colors.CYAN)
    print("  1. SSH key (Linux VMs)")
    print("  2. Password")
    print()
    
    auth_method = input("Choose authentication method [1-2] (default: 1): ").strip()
    if not auth_method:
        auth_method = "1"
    
    # Build command
    cmd = [
        "az", "vm", "create",
        "--name", vm_name,
        "--resource-group", rg_name,
        "--location", location,
        "--size", vm_size,
        "--image", image,
        "--admin-username", admin_user
    ]
    
    if auth_method == "1":
        cmd.extend(["--generate-ssh-keys"])
    else:
        admin_password = getpass.getpass("Enter admin password: ")
        cmd.extend(["--admin-password", admin_password])
    
    # Ask about public IP
    print()
    public_ip = input("Assign public IP? (y/N): ").strip().lower()
    if public_ip not in ["y", "yes"]:
        cmd.extend(["--public-ip-address", ""])
    
    print()
    print_colored("Creating VM... (this may take a few minutes)", Colors.YELLOW)
    print_colored(f"[INFO] VM: {vm_name} | Size: {vm_size} | Image: {image} | Location: {location}", Colors.BLUE)
    print()
    
    # Execute command
    _, _, returncode = run_az_command(cmd, capture_output=False)
    
    if returncode == 0:
        print()
        print_colored("✓ VM created successfully!", Colors.GREEN)
        print()
        
        # Get VM details
        print_colored("VM Details:", Colors.CYAN)
        details_cmd = f"az vm show --name {vm_name} --resource-group {rg_name} --show-details --query \"{{Name:name, ResourceGroup:resourceGroup, Location:location, Size:hardwareProfile.vmSize, PublicIP:publicIps, PrivateIP:privateIps}}\" -o table"
        run_az_command(details_cmd, capture_output=False)
    else:
        print_colored("✗ Failed to create VM", Colors.RED)
        sys.exit(1)

def delete_vm(vm_name):
    """Delete a VM and optionally its associated resources"""
    if not vm_name:
        # List VMs and let user choose
        print_colored("Available VMs to delete:", Colors.CYAN)
        print()
        
        stdout, stderr, returncode = run_az_command("az vm list --output json")
        if returncode != 0:
            print_colored(f"Error listing VMs: {stderr}", Colors.RED)
            return
        
        try:
            vms = json.loads(stdout) if stdout else []
        except json.JSONDecodeError:
            print_colored("Error parsing VM list", Colors.RED)
            return
        
        if not vms:
            print_colored("No VMs found in current subscription", Colors.YELLOW)
            sys.exit(0)
        
        # Display numbered list of all VMs with their status
        for i, vm in enumerate(vms, 1):
            power_cmd = f"az vm get-instance-view --name {vm['name']} --resource-group {vm['resourceGroup']} --query \"instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus\" -o tsv"
            power_stdout, _, power_returncode = run_az_command(power_cmd)
            power_state = power_stdout if power_returncode == 0 else "Unknown"
            
            # Choose color based on state
            color = Colors.WHITE
            if "running" in power_state.lower():
                color = Colors.GREEN
            elif "stopped" in power_state.lower() or "deallocated" in power_state.lower():
                color = Colors.YELLOW
            
            vm_info_text = f"  {i}. {vm['name']} ({vm['resourceGroup']}) - {vm['location']} [{power_state}]"
            print_colored(vm_info_text, color)
        
        print()
        selection = input(f"Select VM to delete [1-{len(vms)}] or 0 to cancel: ").strip()
        
        if selection == "0" or not selection:
            print_colored("Operation cancelled", Colors.YELLOW)
            sys.exit(0)
        
        try:
            selected_index = int(selection) - 1
            if selected_index < 0 or selected_index >= len(vms):
                print_colored("Invalid selection", Colors.RED)
                sys.exit(1)
            
            vm_name = vms[selected_index]['name']
            rg_name = vms[selected_index]['resourceGroup']
        except ValueError:
            print_colored("Invalid selection", Colors.RED)
            sys.exit(1)
    else:
        # Find VM and get resource group
        print_colored(f"Finding VM: {vm_name}", Colors.BLUE)
        stdout, stderr, returncode = run_az_command(f"az vm list --query \"[?name=='{vm_name}']\" -o json")
        
        if returncode != 0:
            print_colored(f"Error finding VM: {stderr}", Colors.RED)
            sys.exit(1)
        
        try:
            vm_info = json.loads(stdout) if stdout else []
        except json.JSONDecodeError:
            print_colored("Error parsing VM information", Colors.RED)
            sys.exit(1)
        
        if not vm_info:
            print_colored(f"Error: VM '{vm_name}' not found", Colors.RED)
            sys.exit(1)
        
        rg_name = vm_info[0]['resourceGroup']
    
    print_colored(f"VM found in resource group: {rg_name}", Colors.YELLOW)
    print()
    confirm = input(f"Are you sure you want to delete VM '{vm_name}'? (y/N): ").strip().lower()
    if confirm != "y":
        print("Deletion cancelled")
        sys.exit(0)
    
    print()
    print_colored("Deleting VM and associated resources...", Colors.YELLOW)
    
    # Delete VM
    _, _, returncode = run_az_command(f"az vm delete --name {vm_name} --resource-group {rg_name} --yes", capture_output=False)
    
    if returncode == 0:
        print_colored("✓ VM deleted successfully", Colors.GREEN)
        
        # Ask to delete associated resources
        delete_resources = input("Delete associated NICs and disks? (y/n): ").strip().lower()
        if delete_resources == "y":
            print_colored("Cleaning up all associated resources...", Colors.YELLOW)
            print()
            
            # Delete NICs
            print_colored("[INFO] Deleting Network Interfaces...", Colors.BLUE)
            nic_stdout, _, _ = run_az_command(f"az network nic list --resource-group {rg_name} --query \"[?contains(name, '{vm_name}')].[name]\" -o tsv")
            if nic_stdout:
                for nic in nic_stdout.split('\n'):
                    if nic.strip():
                        print_colored(f"  Deleting NIC: {nic}", Colors.YELLOW)
                        _, _, returncode = run_az_command(f"az network nic delete --resource-group {rg_name} --name {nic}", capture_output=False)
                        if returncode == 0:
                            print_colored(f"    ✓ NIC deleted: {nic}", Colors.GREEN)
                        else:
                            print_colored(f"    ✗ Failed to delete NIC: {nic}", Colors.RED)
            
            # Delete Public IPs
            print_colored("[INFO] Deleting Public IP addresses...", Colors.BLUE)
            pip_stdout, _, _ = run_az_command(f"az network public-ip list --resource-group {rg_name} --query \"[?contains(name, '{vm_name}')].[name]\" -o tsv")
            if pip_stdout:
                for public_ip in pip_stdout.split('\n'):
                    if public_ip.strip():
                        print_colored(f"  Deleting Public IP: {public_ip}", Colors.YELLOW)
                        _, _, returncode = run_az_command(f"az network public-ip delete --resource-group {rg_name} --name {public_ip}", capture_output=False)
                        if returncode == 0:
                            print_colored(f"    ✓ Public IP deleted: {public_ip}", Colors.GREEN)
                        else:
                            print_colored(f"    ✗ Failed to delete Public IP: {public_ip}", Colors.RED)
            
            # Delete Network Security Groups
            print_colored("[INFO] Deleting Network Security Groups...", Colors.BLUE)
            nsg_stdout, _, _ = run_az_command(f"az network nsg list --resource-group {rg_name} --query \"[?contains(name, '{vm_name}')].[name]\" -o tsv")
            if nsg_stdout:
                for nsg in nsg_stdout.split('\n'):
                    if nsg.strip():
                        print_colored(f"  Deleting NSG: {nsg}", Colors.YELLOW)
                        _, _, returncode = run_az_command(f"az network nsg delete --resource-group {rg_name} --name {nsg}", capture_output=False)
                        if returncode == 0:
                            print_colored(f"    ✓ NSG deleted: {nsg}", Colors.GREEN)
                        else:
                            print_colored(f"    ✗ Failed to delete NSG: {nsg}", Colors.RED)
            
            # Delete Disks
            print_colored("[INFO] Deleting Disks...", Colors.BLUE)
            disk_stdout, _, _ = run_az_command(f"az disk list --resource-group {rg_name} --query \"[?contains(name, '{vm_name}')].[name]\" -o tsv")
            if disk_stdout:
                for disk in disk_stdout.split('\n'):
                    if disk.strip():
                        print_colored(f"  Deleting disk: {disk}", Colors.YELLOW)
                        _, _, returncode = run_az_command(f"az disk delete --resource-group {rg_name} --name {disk} --yes", capture_output=False)
                        if returncode == 0:
                            print_colored(f"    ✓ Disk deleted: {disk}", Colors.GREEN)
                        else:
                            print_colored(f"    ✗ Failed to delete disk: {disk}", Colors.RED)
            
            # Delete Virtual Networks (only if they are VM-specific)
            print_colored("[INFO] Checking Virtual Networks...", Colors.BLUE)
            vnet_stdout, _, _ = run_az_command(f"az network vnet list --resource-group {rg_name} --query \"[?contains(name, '{vm_name}')].[name]\" -o tsv")
            if vnet_stdout:
                for vnet in vnet_stdout.split('\n'):
                    if vnet.strip():
                        print_colored(f"  Deleting VNET: {vnet}", Colors.YELLOW)
                        _, _, returncode = run_az_command(f"az network vnet delete --resource-group {rg_name} --name {vnet}", capture_output=False)
                        if returncode == 0:
                            print_colored(f"    ✓ VNET deleted: {vnet}", Colors.GREEN)
                        else:
                            print_colored(f"    ✗ Failed to delete VNET: {vnet}", Colors.RED)
            
            print()
            print_colored("✓ All resources cleanup completed", Colors.GREEN)
    else:
        print_colored("✗ Failed to delete VM", Colors.RED)
        sys.exit(1)

def start_vm(vm_name):
    """Start a stopped VM"""
    if not vm_name:
        # List VMs and let user choose
        print_colored("Available VMs to start:", Colors.CYAN)
        print()
        
        stdout, stderr, returncode = run_az_command("az vm list --output json")
        if returncode != 0:
            print_colored(f"Error listing VMs: {stderr}", Colors.RED)
            return
        
        try:
            vms = json.loads(stdout) if stdout else []
        except json.JSONDecodeError:
            print_colored("Error parsing VM list", Colors.RED)
            return
        
        if not vms:
            print_colored("No VMs found in current subscription", Colors.YELLOW)
            sys.exit(0)
        
        # Filter only stopped VMs
        stopped_vms = []
        for vm in vms:
            power_cmd = f"az vm get-instance-view --name {vm['name']} --resource-group {vm['resourceGroup']} --query \"instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus\" -o tsv"
            power_stdout, _, power_returncode = run_az_command(power_cmd)
            power_state = power_stdout if power_returncode == 0 else "Unknown"
            
            if "stopped" in power_state.lower() or "deallocated" in power_state.lower():
                stopped_vms.append(vm)
        
        if not stopped_vms:
            print_colored("No stopped VMs found to start", Colors.YELLOW)
            sys.exit(0)
        
        # Display numbered list of stopped VMs
        for i, vm in enumerate(stopped_vms, 1):
            print(f"  {i}. {vm['name']} ({vm['resourceGroup']}) - {vm['location']}")
        
        print()
        selection = input(f"Select VM to start [1-{len(stopped_vms)}] or 0 to cancel: ").strip()
        
        if selection == "0" or not selection:
            print_colored("Operation cancelled", Colors.YELLOW)
            sys.exit(0)
        
        try:
            selected_index = int(selection) - 1
            if selected_index < 0 or selected_index >= len(stopped_vms):
                print_colored("Invalid selection", Colors.RED)
                sys.exit(1)
            
            vm_name = stopped_vms[selected_index]['name']
            rg_name = stopped_vms[selected_index]['resourceGroup']
        except ValueError:
            print_colored("Invalid selection", Colors.RED)
            sys.exit(1)
    else:
        # Find VM and get resource group
        stdout, stderr, returncode = run_az_command(f"az vm list --query \"[?name=='{vm_name}']\" -o json")
        
        if returncode != 0:
            print_colored(f"Error finding VM: {stderr}", Colors.RED)
            sys.exit(1)
        
        try:
            vm_info = json.loads(stdout) if stdout else []
        except json.JSONDecodeError:
            print_colored("Error parsing VM information", Colors.RED)
            sys.exit(1)
        
        if not vm_info:
            print_colored(f"Error: VM '{vm_name}' not found", Colors.RED)
            sys.exit(1)
        
        rg_name = vm_info[0]['resourceGroup']
    
    print_colored(f"Starting VM: {vm_name}", Colors.YELLOW)
    _, _, returncode = run_az_command(f"az vm start --name {vm_name} --resource-group {rg_name}", capture_output=False)
    
    if returncode == 0:
        print_colored("✓ VM started successfully", Colors.GREEN)
    else:
        print_colored("✗ Failed to start VM", Colors.RED)
        sys.exit(1)

def stop_vm(vm_name):
    """Stop and deallocate a VM"""
    if not vm_name:
        # List VMs and let user choose
        print_colored("Available VMs to stop:", Colors.CYAN)
        print()
        
        stdout, stderr, returncode = run_az_command("az vm list --output json")
        if returncode != 0:
            print_colored(f"Error listing VMs: {stderr}", Colors.RED)
            return
        
        try:
            vms = json.loads(stdout) if stdout else []
        except json.JSONDecodeError:
            print_colored("Error parsing VM list", Colors.RED)
            return
        
        if not vms:
            print_colored("No VMs found in current subscription", Colors.YELLOW)
            sys.exit(0)
        
        # Filter only running VMs
        running_vms = []
        for vm in vms:
            power_cmd = f"az vm get-instance-view --name {vm['name']} --resource-group {vm['resourceGroup']} --query \"instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus\" -o tsv"
            power_stdout, _, power_returncode = run_az_command(power_cmd)
            power_state = power_stdout if power_returncode == 0 else "Unknown"
            
            if "running" in power_state.lower():
                running_vms.append(vm)
        
        if not running_vms:
            print_colored("No running VMs found to stop", Colors.YELLOW)
            sys.exit(0)
        
        # Display numbered list of running VMs
        for i, vm in enumerate(running_vms, 1):
            print(f"  {i}. {vm['name']} ({vm['resourceGroup']}) - {vm['location']}")
        
        print()
        selection = input(f"Select VM to stop [1-{len(running_vms)}] or 0 to cancel: ").strip()
        
        if selection == "0" or not selection:
            print_colored("Operation cancelled", Colors.YELLOW)
            sys.exit(0)
        
        try:
            selected_index = int(selection) - 1
            if selected_index < 0 or selected_index >= len(running_vms):
                print_colored("Invalid selection", Colors.RED)
                sys.exit(1)
            
            vm_name = running_vms[selected_index]['name']
            rg_name = running_vms[selected_index]['resourceGroup']
        except ValueError:
            print_colored("Invalid selection", Colors.RED)
            sys.exit(1)
    else:
        # Find VM and get resource group
        stdout, stderr, returncode = run_az_command(f"az vm list --query \"[?name=='{vm_name}']\" -o json")
        
        if returncode != 0:
            print_colored(f"Error finding VM: {stderr}", Colors.RED)
            sys.exit(1)
        
        try:
            vm_info = json.loads(stdout) if stdout else []
        except json.JSONDecodeError:
            print_colored("Error parsing VM information", Colors.RED)
            sys.exit(1)
        
        if not vm_info:
            print_colored(f"Error: VM '{vm_name}' not found", Colors.RED)
            sys.exit(1)
        
        rg_name = vm_info[0]['resourceGroup']
    
    print_colored(f"Stopping and deallocating VM: {vm_name}", Colors.YELLOW)
    _, _, returncode = run_az_command(f"az vm deallocate --name {vm_name} --resource-group {rg_name}", capture_output=False)
    
    if returncode == 0:
        print_colored("✓ VM stopped and deallocated successfully", Colors.GREEN)
    else:
        print_colored("✗ Failed to stop VM", Colors.RED)
        sys.exit(1)

def main():
    """Main function"""
    parser = argparse.ArgumentParser(
        description="Azure VM Manager - NimbusDFIR",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python vm_manager.py list
  python vm_manager.py create
  python vm_manager.py delete myVM
  python vm_manager.py start myVM
  python vm_manager.py stop myVM
        """
    )
    
    parser.add_argument(
        'command',
        choices=['list', 'create', 'delete', 'start', 'stop', 'help'],
        help='Command to execute'
    )
    
    parser.add_argument(
        'vm_name',
        nargs='?',
        help='VM name (required for delete, start, stop commands)'
    )
    
    if len(sys.argv) == 1:
        show_usage()
        sys.exit(1)
    
    args = parser.parse_args()
    
    if args.command == 'help':
        show_usage()
        return
    
    # Check prerequisites
    check_prerequisites()
    
    # Execute command
    if args.command == 'list':
        list_vms()
    elif args.command == 'create':
        create_vm()
    elif args.command == 'delete':
        delete_vm(args.vm_name)
    elif args.command == 'start':
        start_vm(args.vm_name)
    elif args.command == 'stop':
        stop_vm(args.vm_name)

if __name__ == "__main__":
    main()