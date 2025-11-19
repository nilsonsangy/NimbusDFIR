#!/usr/bin/env python3
"""
Azure MySQL Connect Script - Python Version
Author: NimbusDFIR
Description: Connect to Azure MySQL Flexible Server - handles both public and private instances
"""

import sys
import os
import json
import subprocess
import time
import argparse
import getpass
import tempfile
import signal
import atexit
from typing import Dict, List, Optional


class Colors:
    """ANSI color codes for terminal output"""
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color


class AzureMySQLConnector:
    def __init__(self):
        self.jumpserver_info_file = os.path.join(tempfile.gettempdir(), 'azure_mysql_jumpserver_info.txt')
        atexit.register(self.cleanup_jumpserver)
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
    
    def _signal_handler(self, signum, frame):
        """Handle cleanup on signal"""
        print(f"\n{Colors.YELLOW}Received signal, cleaning up...{Colors.NC}")
        self.cleanup_jumpserver()
        sys.exit(1)
    
    def run_command(self, cmd: List[str], capture_output: bool = True, check: bool = True) -> subprocess.CompletedProcess:
        """Run a command and return the result"""
        try:
            return subprocess.run(cmd, capture_output=capture_output, text=True, check=check)
        except subprocess.CalledProcessError as e:
            if capture_output:
                print(f"{Colors.RED}Command failed: {' '.join(cmd)}{Colors.NC}")
                if e.stderr:
                    print(f"{Colors.RED}Error: {e.stderr.strip()}{Colors.NC}")
            raise
    
    def check_prerequisites(self):
        """Check if required tools are installed"""
        # Check Azure CLI
        try:
            self.run_command(['az', '--version'], capture_output=True)
        except (subprocess.CalledProcessError, FileNotFoundError):
            print(f"{Colors.RED}Error: Azure CLI is not installed{Colors.NC}")
            print("Please install Azure CLI first")
            sys.exit(1)
        
        # Check MySQL client
        try:
            self.run_command(['mysql', '--version'], capture_output=True)
        except (subprocess.CalledProcessError, FileNotFoundError):
            print(f"{Colors.RED}Error: MySQL client is not installed{Colors.NC}")
            print("Please install MySQL client first")
            print("macOS: brew install mysql-client")
            print("Ubuntu/Debian: sudo apt-get install mysql-client")
            print("Windows: Download from https://dev.mysql.com/downloads/mysql/")
            sys.exit(1)
        
        # Check Azure login
        try:
            self.run_command(['az', 'account', 'show'], capture_output=True)
        except subprocess.CalledProcessError:
            print(f"{Colors.RED}Error: Not logged in to Azure{Colors.NC}")
            print("Please run: az login")
            sys.exit(1)
    
    def show_usage(self):
        """Display usage information"""
        print(f"{Colors.BLUE}==========================================")
        print("Azure MySQL Connect - NimbusDFIR")
        print(f"=========================================={Colors.NC}")
        print()
        print("Usage: python mysql_connect.py [SERVER_NAME]")
        print()
        print("Description:")
        print("  Connects to an Azure MySQL Flexible Server")
        print("  - For public servers: connects directly")
        print("  - For private servers: creates Azure VM jump server with SSH tunnel")
        print()
        print("Examples:")
        print("  python mysql_connect.py my-mysql-server")
        print("  python mysql_connect.py")
        print()
    
    def list_servers(self) -> List[Dict]:
        """List available MySQL servers"""
        print(f"{Colors.BLUE}Available Azure MySQL Flexible Servers:{Colors.NC}")
        print()
        
        try:
            result = self.run_command(['az', 'mysql', 'flexible-server', 'list', '--output', 'json'])
            servers = json.loads(result.stdout)
            
            if not servers:
                print(f"{Colors.YELLOW}No MySQL flexible servers found{Colors.NC}")
                sys.exit(1)
            
            for i, server in enumerate(servers, 1):
                public_access = server.get('network', {}).get('publicNetworkAccess', 'Unknown')
                print(f"{i}. {server['name']} ({server['resourceGroup']} - {server['state']} - Public: {public_access})")
            print()
            
            return servers
        except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
            print(f"{Colors.RED}Error retrieving MySQL servers: {e}{Colors.NC}")
            sys.exit(1)
    
    def get_server_info(self, server_name: str) -> Dict:
        """Get server information"""
        try:
            result = self.run_command([
                'az', 'mysql', 'flexible-server', 'list',
                '--query', f"[?name=='{server_name}']",
                '-o', 'json'
            ])
            servers = json.loads(result.stdout)
            
            if not servers:
                print(f"{Colors.RED}Error: MySQL server '{server_name}' not found{Colors.NC}")
                sys.exit(1)
            
            server = servers[0]
            
            if server['state'] != 'Ready':
                print(f"{Colors.RED}Error: Server is not ready (Status: {server['state']}){Colors.NC}")
                sys.exit(1)
            
            # Check firewall rules for public servers
            public_access = server.get('network', {}).get('publicNetworkAccess', 'Disabled')
            
            if public_access == 'Enabled':
                try:
                    fw_result = self.run_command([
                        'az', 'mysql', 'flexible-server', 'firewall-rule', 'list',
                        '--resource-group', server['resourceGroup'],
                        '--name', server_name,
                        '--query', 'length(@)',
                        '-o', 'tsv'
                    ])
                    if int(fw_result.stdout.strip()) == 0:
                        print(f"{Colors.YELLOW}Warning: Server has public access enabled but no firewall rules{Colors.NC}")
                        print(f"{Colors.YELLOW}Treating as private server - will use jump server{Colors.NC}")
                        public_access = 'Disabled'
                except subprocess.CalledProcessError:
                    public_access = 'Disabled'
            
            return {
                'name': server['name'],
                'fqdn': server['fullyQualifiedDomainName'],
                'version': server['version'],
                'location': server['location'],
                'resource_group': server['resourceGroup'],
                'public_access': public_access,
                'status': server['state']
            }
        except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
            print(f"{Colors.RED}Error getting server information: {e}{Colors.NC}")
            sys.exit(1)
    
    def connect_public_mysql(self, server_info: Dict):
        """Connect to public MySQL server"""
        print(f"{Colors.GREEN}Server has public access enabled{Colors.NC}")
        print("Connecting directly to MySQL server...")
        print()
        print("Connection details:")
        print(f"  Host: {server_info['fqdn']}")
        print("  Port: 3306")
        print()
        
        mysql_user = input("Enter MySQL username: ")
        if not mysql_user:
            print(f"{Colors.RED}Error: Username is required{Colors.NC}")
            sys.exit(1)
        
        mysql_password = getpass.getpass(f"Enter password for user '{mysql_user}': ")
        if not mysql_password:
            print(f"{Colors.RED}Error: Password is required{Colors.NC}")
            sys.exit(1)
        
        db_name = input("Enter database name (press Enter for no database): ")
        print()
        
        print("Connecting to MySQL...")
        
        # Build MySQL command
        mysql_cmd = ['mysql', '-h', server_info['fqdn'], '-u', mysql_user, f'-p{mysql_password}']
        if db_name:
            mysql_cmd.append(db_name)
        
        try:
            self.run_command(mysql_cmd, capture_output=False, check=True)
        except subprocess.CalledProcessError:
            print(f"{Colors.RED}MySQL connection failed{Colors.NC}")
            sys.exit(1)
    
    def create_jumpserver_vm(self, server_info: Dict) -> Dict:
        """Create or use existing jump server VM"""
        print(f"{Colors.YELLOW}Server is private - checking for existing jump server...{Colors.NC}")
        print()
        
        jumpserver_rg = server_info['resource_group']
        jumpserver_location = server_info['location']

        # Check for existing jump server VMs
        try:
            result = self.run_command([
                'az', 'vm', 'list',
                '--resource-group', jumpserver_rg,
                '--query', "[?starts_with(name, 'mysql-jumpserver')].{name:name, state:powerState, ip:publicIps}",
                '-o', 'json'
            ])
            existing_jumpservers = json.loads(result.stdout)
            
            if existing_jumpservers:
                print(f"{Colors.GREEN}Found {len(existing_jumpservers)} existing jump server VM(s){Colors.NC}")
                for i, jumpserver in enumerate(existing_jumpservers, 1):
                    print(f"{i}. {jumpserver['name']} - {jumpserver['state']} - {jumpserver.get('ip', 'No IP')}")
                print()
                
                use_existing = input("Use existing jump server? (Y/n): ").lower()
                if use_existing != 'n':
                    jumpserver = existing_jumpservers[0]
                    jumpserver_name = jumpserver['name']
                    
                    # Get public IP
                    ip_result = self.run_command([
                        'az', 'vm', 'show',
                        '--resource-group', jumpserver_rg,
                        '--name', jumpserver_name,
                        '--show-details',
                        '--query', 'publicIps',
                        '-o', 'tsv'
                    ])
                    jumpserver_public_ip = ip_result.stdout.strip()
                    
                    # Start VM if stopped
                    if 'stopped' in jumpserver['state'].lower() or 'deallocated' in jumpserver['state'].lower():
                        print(f"{Colors.YELLOW}Starting existing jump server VM: {jumpserver_name}{Colors.NC}")
                        self.run_command([
                            'az', 'vm', 'start',
                            '--resource-group', jumpserver_rg,
                            '--name', jumpserver_name,
                            '--no-wait'
                        ])
                        time.sleep(10)
                        
                        # Get IP after starting
                        ip_result = self.run_command([
                            'az', 'vm', 'show',
                            '--resource-group', jumpserver_rg,
                            '--name', jumpserver_name,
                            '--show-details',
                            '--query', 'publicIps',
                            '-o', 'tsv'
                        ])
                        jumpserver_public_ip = ip_result.stdout.strip()
                    
                    print(f"{Colors.GREEN}✓ Using existing jump server VM: {jumpserver_name}{Colors.NC}")
                    print(f"Public IP: {jumpserver_public_ip}")
                    print()
                    
                    # Save jump server info
                    with open(self.jumpserver_info_file, 'w') as f:
                        f.write(f"{jumpserver_name}|{jumpserver_rg}|{jumpserver_public_ip}")
                    
                    return {
                        'name': jumpserver_name,
                        'resource_group': jumpserver_rg,
                        'public_ip': jumpserver_public_ip
                    }
        except subprocess.CalledProcessError:
            pass  # No existing bastions found
        
        # Create new jump server VM
        print(f"{Colors.YELLOW}Creating new Azure VM jump server instance...{Colors.NC}")
        print()
        
        jumpserver_name = f"mysql-jumpserver-{int(time.time())}"
        
        print(f"Creating jump server VM: {jumpserver_name}")
        print(f"Location: {jumpserver_location}")
        print(f"Resource Group: {jumpserver_rg}")
        print()
        print("Launching VM (this may take 2-3 minutes)...")
        
        try:
            result = self.run_command([
                'az', 'vm', 'create',
                '--resource-group', jumpserver_rg,
                '--name', jumpserver_name,
                '--location', jumpserver_location,
                '--image', 'Ubuntu2204',
                '--size', 'Standard_B1s',
                '--admin-username', 'azureuser',
                '--generate-ssh-keys',
                '--public-ip-sku', 'Standard',
                '--public-ip-address', f'{jumpserver_name}-ip',
                '--nsg', f'{jumpserver_name}-nsg',
                '--nsg-rule', 'SSH',
                '--output', 'json'
            ])
            
            vm_info = json.loads(result.stdout)
            jumpserver_public_ip = vm_info['publicIpAddress']
            
            if not jumpserver_public_ip:
                raise Exception("Failed to get jump server VM public IP")
            
            print(f"{Colors.GREEN}✓ Jump server VM created successfully{Colors.NC}")
            print(f"Public IP: {jumpserver_public_ip}")
            print()
            
            # Save jump server info for cleanup
            with open(self.jumpserver_info_file, 'w') as f:
                f.write(f"{jumpserver_name}|{jumpserver_rg}|{jumpserver_public_ip}")
            
            return {
                'name': jumpserver_name,
                'resource_group': jumpserver_rg,
                'public_ip': jumpserver_public_ip
            }
        except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
            print(f"{Colors.RED}Error: Failed to create jump server VM{Colors.NC}")
            print(f"Error details: {e}")
            sys.exit(1)
    
    def connect_via_jumpserver(self, server_info: Dict, jumpserver_info: Dict):
        """Connect to MySQL via SSH tunnel through jump server VM"""
        print()
        print(f"{Colors.BLUE}Setting up SSH tunnel to MySQL through jump server VM...{Colors.NC}")
        print()
        print("Waiting for VM to be fully ready (this may take 30-60 seconds)...")
        
        # Wait for SSH to be ready
        ssh_ready = False
        for i in range(60):
            try:
                self.run_command([
                    'ssh', '-i', os.path.expanduser('~/.ssh/id_rsa'),
                    '-o', 'StrictHostKeyChecking=no',
                    '-o', 'ConnectTimeout=5',
                    '-o', 'ConnectionAttempts=1',
                    f'azureuser@{jumpserver_info["public_ip"]}',
                    'echo SSH ready'
                ], capture_output=True)
                print(f"{Colors.GREEN}✓ SSH connection established{Colors.NC}")
                ssh_ready = True
                break
            except subprocess.CalledProcessError:
                if (i + 1) % 10 == 0:
                    print(f"Still waiting... ({i + 1}/60 seconds)")
                time.sleep(1)
        
        if not ssh_ready:
            print(f"{Colors.RED}Error: SSH connection timeout{Colors.NC}")
            sys.exit(1)
        
        print()
        
        # Add firewall rule for jump server VM
        print(f"{Colors.YELLOW}Adding firewall rule for jump server VM...{Colors.NC}")
        rule_name = f"jumpserver-access-{int(time.time())}"
        
        self.run_command([
            'az', 'mysql', 'flexible-server', 'firewall-rule', 'create',
            '--resource-group', server_info['resource_group'],
            '--name', server_info['name'],
            '--rule-name', rule_name,
            '--start-ip-address', jumpserver_info['public_ip'],
            '--end-ip-address', jumpserver_info['public_ip'],
            '--output', 'none'
        ])
        
        print(f"{Colors.GREEN}✓ Firewall rule created{Colors.NC}")
        print()
        
        # Get MySQL credentials
        mysql_user = input("Enter MySQL username: ")
        if not mysql_user:
            print(f"{Colors.RED}Error: Username is required{Colors.NC}")
            sys.exit(1)
        
        mysql_password = getpass.getpass(f"Enter password for user '{mysql_user}': ")
        if not mysql_password:
            print(f"{Colors.RED}Error: Password is required{Colors.NC}")
            sys.exit(1)
        
        db_name = input("Enter database name (press Enter for no database): ")
        print()
        
        local_port = 3307
        
        print(f"{Colors.GREEN}==========================================")
        print("✓ SSH Tunnel Configuration")
        print(f"=========================================={Colors.NC}")
        print(f"Local Port: {local_port}")
        print(f"Remote MySQL: {server_info['fqdn']}:3306")
        print(f"Jump Server: {jumpserver_info['public_ip']}")
        print()
        print(f"{Colors.YELLOW}Starting SSH tunnel in background...{Colors.NC}")
        
        # Start SSH tunnel
        tunnel_process = subprocess.Popen([
            'ssh', '-i', os.path.expanduser('~/.ssh/id_rsa'),
            '-f', '-N',
            '-L', f'{local_port}:{server_info["fqdn"]}:3306',
            '-o', 'StrictHostKeyChecking=no',
            f'azureuser@{jumpserver_info["public_ip"]}'
        ])
        
        time.sleep(2)
        
        print(f"{Colors.GREEN}✓ SSH tunnel established{Colors.NC}")
        print()
        print("Connecting to MySQL through tunnel...")
        print()
        
        # Connect to MySQL through tunnel
        mysql_cmd = ['mysql', '-h', '127.0.0.1', '-P', str(local_port), '-u', mysql_user, f'-p{mysql_password}']
        if db_name:
            mysql_cmd.append(db_name)
        
        try:
            self.run_command(mysql_cmd, capture_output=False)
        except subprocess.CalledProcessError:
            print(f"{Colors.RED}MySQL connection failed{Colors.NC}")
        finally:
            # Cleanup
            print()
            print("Cleaning up...")
            
            # Remove firewall rule
            print("Removing firewall rule...")
            try:
                self.run_command([
                    'az', 'mysql', 'flexible-server', 'firewall-rule', 'delete',
                    '--resource-group', server_info['resource_group'],
                    '--name', server_info['name'],
                    '--rule-name', rule_name,
                    '--yes',
                    '--output', 'none'
                ], capture_output=True)
            except subprocess.CalledProcessError:
                pass
            
            # Kill SSH tunnel
            print("Closing SSH tunnel...")
            try:
                subprocess.run(['pkill', '-f', f'ssh.*{local_port}:{server_info["fqdn"]}:3306'], 
                             capture_output=True)
            except subprocess.CalledProcessError:
                pass
    
    def cleanup_jumpserver(self):
        """Cleanup jump server resources"""
        if os.path.exists(self.jumpserver_info_file):
            print()
            print(f"{Colors.YELLOW}Cleaning up jump server resources...{Colors.NC}")
            
            try:
                with open(self.jumpserver_info_file, 'r') as f:
                    jumpserver_data = f.read().strip()
                
                jumpserver_name, jumpserver_rg, jumpserver_ip = jumpserver_data.split('|')
                
                if jumpserver_name and jumpserver_rg:
                    print(f"Deleting jump server VM and all associated resources: {jumpserver_name}")
                    
                    # Delete VM and associated resources
                    resources_to_delete = [
                        ('VM', ['az', 'vm', 'delete', '--resource-group', jumpserver_rg, 
                               '--name', jumpserver_name, '--yes', '--force-deletion', 'yes']),
                        ('Network Interface', ['az', 'network', 'nic', 'delete', 
                                             '--resource-group', jumpserver_rg, '--name', f'{jumpserver_name}VMNic']),
                        ('Public IP', ['az', 'network', 'public-ip', 'delete', 
                                     '--resource-group', jumpserver_rg, '--name', f'{jumpserver_name}-ip']),
                        ('Network Security Group', ['az', 'network', 'nsg', 'delete', 
                                                   '--resource-group', jumpserver_rg, '--name', f'{jumpserver_name}-nsg']),
                        ('Disk', ['az', 'disk', 'delete', '--resource-group', jumpserver_rg, 
                                 '--name', f'{jumpserver_name}_disk1_*', '--yes'])
                    ]
                    
                    for resource_type, cmd in resources_to_delete:
                        try:
                            print(f"  - Deleting {resource_type.lower()}...")
                            subprocess.run(cmd + ['--output', 'none'], 
                                         capture_output=True, timeout=120)
                        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                            pass  # Continue with other resources
                        time.sleep(2)  # Brief delay between deletions
                    
                    print(f"{Colors.GREEN}✓ All jump server resources deleted{Colors.NC}")
                
                os.remove(self.jumpserver_info_file)
            except Exception as e:
                print(f"{Colors.RED}Error during cleanup: {e}{Colors.NC}")
    
    def main(self):
        """Main execution function"""
        parser = argparse.ArgumentParser(description='Connect to Azure MySQL Flexible Server')
        parser.add_argument('server_name', nargs='?', help='MySQL server name')
        parser.add_argument('--help-detailed', action='store_true', 
                          help='Show detailed help information')
        
        args = parser.parse_args()
        
        if args.help_detailed:
            self.show_usage()
            return
        
        # Check prerequisites
        self.check_prerequisites()
        
        server_name = args.server_name
        
        if not server_name:
            servers = self.list_servers()
            print()
            server_input = input("Select server number or enter name: ").strip()
            
            if not server_input:
                print(f"{Colors.RED}Error: Server selection is required{Colors.NC}")
                sys.exit(1)
            
            # Check if input is a number
            if server_input.isdigit():
                server_index = int(server_input) - 1
                if 0 <= server_index < len(servers):
                    server_name = servers[server_index]['name']
                else:
                    print(f"{Colors.RED}Error: Invalid selection{Colors.NC}")
                    sys.exit(1)
            else:
                server_name = server_input
        
        # Get server information
        print(f"{Colors.BLUE}Gathering MySQL server information...{Colors.NC}")
        server_info = self.get_server_info(server_name)
        
        print(f"{Colors.BLUE}==========================================")
        print("MySQL Server Information")
        print(f"=========================================={Colors.NC}")
        print(f"Name: {server_info['name']}")
        print(f"FQDN: {server_info['fqdn']}")
        print(f"Version: {server_info['version']}")
        print(f"Location: {server_info['location']}")
        print(f"Resource Group: {server_info['resource_group']}")
        print(f"Public Access: {server_info['public_access']}")
        print(f"Status: {server_info['status']}")
        print()
        
        # Connect based on public access
        if server_info['public_access'] == 'Enabled':
            self.connect_public_mysql(server_info)
        else:
            jumpserver_info = self.create_jumpserver_vm(server_info)
            self.connect_via_jumpserver(server_info, jumpserver_info)
        
        print()
        print(f"{Colors.GREEN}MySQL connection closed{Colors.NC}")


if __name__ == '__main__':
    connector = AzureMySQLConnector()
    try:
        connector.main()
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Operation cancelled by user{Colors.NC}")
        sys.exit(1)
    except Exception as e:
        print(f"{Colors.RED}Unexpected error: {e}{Colors.NC}")
        sys.exit(1)