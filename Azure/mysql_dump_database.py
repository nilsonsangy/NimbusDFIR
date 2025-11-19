#!/usr/bin/env python3

"""
Azure MySQL Dump Database Script - Python Version
Author: NimbusDFIR
Description: Dump database from Azure MySQL Flexible Server
"""

import subprocess
import sys
import json
import os
import getpass
import psutil
import socket
from pathlib import Path
from datetime import datetime

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

def check_mysql_client():
    """Check if MySQL client is installed"""
    try:
        subprocess.run(['mysqldump', '--version'], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print_colored("Error: MySQL client (mysqldump) is not installed", Colors.RED)
        print("Please install MySQL client first")
        print("macOS: brew install mysql-client")
        print("Ubuntu/Debian: sudo apt-get install mysql-client")
        print("Windows: Download from https://dev.mysql.com/downloads/mysql/")
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
    print_colored("Checking for active SSH tunnel...", Colors.BLUE)
    
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
                            print_colored(f"✓ Active SSH tunnel detected on port {local_port}", Colors.GREEN)
                            break
                    except:
                        pass
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    
    if not tunnel_active:
        print_colored("✗ No active SSH tunnel found", Colors.YELLOW)
        print_colored("Please run mysql_connect.py first to establish tunnel, then run this script", Colors.YELLOW)
        print_colored("Or use this script independently (will prompt for server selection)", Colors.CYAN)
        print()
    else:
        print_colored("Using existing SSH tunnel for database operations", Colors.GREEN)
        print()
    
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

def get_azure_server_name():
    """Get Azure MySQL server name automatically"""
    try:
        result = subprocess.run(['az', 'mysql', 'flexible-server', 'list', '--query', '[].name', '-o', 'tsv'], 
                              capture_output=True, text=True, check=True)
        
        if result.stdout.strip():
            servers = [s.strip() for s in result.stdout.strip().split('\n') if s.strip()]
            if servers:
                return servers[0]  # Return the first server
    except:
        pass
    
    return "azure-mysql-server"

def list_databases_via_tunnel(username, password, local_port):
    """List databases via SSH tunnel"""
    print_colored("Listing databases via SSH tunnel...", Colors.BLUE)
    
    env = os.environ.copy()
    env['MYSQL_PWD'] = password
    
    try:
        result = subprocess.run(['mysql', '-h', '127.0.0.1', '-P', str(local_port), 
                               '-u', username, '-e', 'SHOW DATABASES;'], 
                              env=env, capture_output=True, text=True, check=True)
        
        # Parse the result to get database names (skip header, borders and system databases)
        databases = []
        system_dbs = {'Database', 'information_schema', 'performance_schema', 'mysql', 'sys'}
        
        for line in result.stdout.split('\n'):
            line = line.strip()
            # Skip empty lines, headers, borders, and system databases
            if (line and 
                not line.startswith('+') and 
                not line.startswith('-') and 
                not line.startswith('|') and
                line not in system_dbs):
                
                # Clean up pipe characters if present
                clean_line = line.replace('|', '').strip()
                
                if clean_line and clean_line not in system_dbs:
                    databases.append(clean_line)
        
        return databases
    except subprocess.CalledProcessError as e:
        print_colored("Error: Failed to connect to MySQL via tunnel", Colors.RED)
        return None

def list_databases_via_cli(server_name, resource_group):
    """List databases via Azure CLI"""
    print_colored("Listing databases via Azure CLI...", Colors.BLUE)
    
    try:
        result = subprocess.run(['az', 'mysql', 'flexible-server', 'db', 'list',
                               '--resource-group', resource_group,
                               '--server-name', server_name,
                               '--query', '[].name', '-o', 'tsv'], 
                              capture_output=True, text=True, check=True)
        
        databases = [db.strip() for db in result.stdout.split('\n') if db.strip()]
        return databases
    except subprocess.CalledProcessError as e:
        print_colored(f"Error retrieving databases: {e}", Colors.RED)
        return None

def dump_via_tunnel(username, password, database_name, local_port, output_file, server_name):
    """Perform database dump via SSH tunnel"""
    print_colored("Creating database dump via SSH tunnel...", Colors.GREEN)
    
    env = os.environ.copy()
    env['MYSQL_PWD'] = password
    
    try:
        # Execute mysqldump and capture output
        result = subprocess.run(['mysqldump', '-h', '127.0.0.1', '-P', str(local_port),
                               '-u', username, '--single-transaction', '--routines', 
                               '--triggers', database_name], 
                              env=env, capture_output=True, text=True, check=True)
        
        # Modify the dump header to show Azure server name
        dump_content = result.stdout
        dump_content = dump_content.replace(
            '-- Host: 127.0.0.1',
            f'-- Host: {server_name} (via SSH tunnel from 127.0.0.1)'
        )
        
        # Write modified dump to file
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(dump_content)
        
        return True
    except subprocess.CalledProcessError as e:
        print_colored("Error: mysqldump failed", Colors.RED)
        return False

def show_usage():
    """Display usage information"""
    print_colored("==========================================", Colors.BLUE)
    print_colored("Azure MySQL Dump Database - NimbusDFIR", Colors.BLUE)
    print_colored("==========================================", Colors.BLUE)
    print()
    print("Usage: python mysql_dump_database.py [SERVER_NAME] [DATABASE_NAME] [OUTPUT_PATH]")
    print()
    print("Examples:")
    print("  python mysql_dump_database.py                              # Interactive mode")
    print("  python mysql_dump_database.py my-server testdb             # Direct mode")
    print("  python mysql_dump_database.py my-server testdb ~/backups   # With custom path")
    print()
    print("Features:")
    print("  - Auto-detects existing SSH tunnels")
    print("  - Lists available databases for selection")
    print("  - Saves to Downloads folder by default")
    print("  - Generates timestamped dump files")
    print()

def main():
    """Main function"""
    if len(sys.argv) > 1 and sys.argv[1] in ['help', '--help', '-h']:
        show_usage()
        sys.exit(0)
    
    # Check prerequisites
    check_azure_cli()
    check_mysql_client()
    check_azure_login()
    
    print_colored("==========================================", Colors.BLUE)
    print_colored("Azure MySQL Dump Database", Colors.BLUE)
    print_colored("==========================================", Colors.BLUE)
    print()
    
    # Check for active SSH tunnel
    tunnel_active, local_port = check_ssh_tunnel()
    
    # Get credentials first
    print_colored("Enter MySQL credentials:", Colors.BLUE)
    db_username = input("Enter MySQL admin username (default: mysqladmin): ").strip()
    if not db_username:
        db_username = "mysqladmin"
    
    print()
    db_password = getpass.getpass("Enter MySQL admin password: ")
    
    if not db_password:
        print_colored("Error: Password is required", Colors.RED)
        sys.exit(1)
    
    # Get server and database information
    server_info = None
    server_name = None
    databases = None
    
    if tunnel_active:
        # Get Azure server name
        azure_server_name = get_azure_server_name()
        
        # List databases via tunnel
        databases = list_databases_via_tunnel(db_username, db_password, local_port)
    else:
        # Get server name if not provided
        server_name = sys.argv[1] if len(sys.argv) > 1 else None
        if not server_name:
            servers = get_mysql_servers()
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
        
        # Get server information
        print()
        print_colored("Finding server details...", Colors.BLUE)
        server_info = get_server_info(server_name)
        
        # List databases via Azure CLI
        databases = list_databases_via_cli(server_name, server_info['resourceGroup'])
    
    if not databases:
        print_colored("Error: No databases available for dump", Colors.RED)
        sys.exit(1)
    
    # Show databases and get selection
    print()
    print_colored("Available Databases:", Colors.CYAN)
    for i, db in enumerate(databases, 1):
        print(f"{i}. {db}")
    print()
    
    database_name = sys.argv[2] if len(sys.argv) > 2 else None
    if not database_name:
        db_input = input("Select database number or enter name: ").strip()
        
        if not db_input:
            print_colored("Error: Database selection is required", Colors.RED)
            sys.exit(1)
        
        # Check if input is a number
        if db_input.isdigit():
            db_index = int(db_input) - 1
            if 0 <= db_index < len(databases):
                database_name = databases[db_index]
            else:
                print_colored("Error: Invalid selection", Colors.RED)
                sys.exit(1)
        else:
            database_name = db_input
    
    # Get output path
    output_path = sys.argv[3] if len(sys.argv) > 3 else None
    if not output_path:
        default_path = str(Path.home() / "Downloads")
        print()
        output_path = input(f"Enter output directory (default: {default_path}): ").strip()
        if not output_path:
            output_path = default_path
    
    # Create output directory if it doesn't exist
    Path(output_path).mkdir(parents=True, exist_ok=True)
    
    # Generate output filename with timestamp
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = Path(output_path) / f"{database_name}_dump_{timestamp}.sql"
    
    print()
    print_colored("Database dump configuration:", Colors.BLUE)
    if tunnel_active:
        print(f"Connection: SSH Tunnel (localhost:{local_port})")
        print(f"Azure Server: {azure_server_name}")
    else:
        print(f"Server: {server_name}")
        print(f"Resource Group: {server_info['resourceGroup']}")
    print(f"Database: {database_name}")
    print(f"Output File: {output_file}")
    print()
    
    confirm = input("Proceed with dump? (Y/n): ").strip()
    if confirm.lower() == 'n':
        print_colored("Dump cancelled", Colors.YELLOW)
        sys.exit(0)
    
    # Perform the dump
    print()
    print_colored("Starting database dump...", Colors.YELLOW)
    
    success = False
    if tunnel_active:
        success = dump_via_tunnel(db_username, db_password, database_name, local_port, str(output_file), azure_server_name)
    else:
        print_colored("Note: Direct Azure CLI dump not supported", Colors.YELLOW)
        print_colored("Please use SSH tunnel method for full dump functionality", Colors.YELLOW)
        sys.exit(1)
    
    if success:
        file_size = output_file.stat().st_size
        file_size_mb = round(file_size / (1024 * 1024), 2)
        
        print()
        print_colored("==========================================", Colors.GREEN)
        print_colored("✓ Database dump completed successfully!", Colors.GREEN)
        print_colored("==========================================", Colors.GREEN)
        print()
        print(f"Database: {database_name}")
        print(f"Output File: {output_file}")
        print(f"File Size: {file_size_mb} MB")
        print(f"Created: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print()
        print_colored("Dump completed!", Colors.GREEN)
    else:
        print()
        print_colored("✗ Database dump failed", Colors.RED)
        if output_file.exists():
            output_file.unlink()
        sys.exit(1)

if __name__ == "__main__":
    main()