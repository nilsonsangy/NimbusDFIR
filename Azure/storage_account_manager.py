#!/usr/bin/env python3
import subprocess
import sys

# Colors for terminal output
class Colors:
    GREEN = '\033[32m'
    YELLOW = '\033[33m'
    RED = '\033[31m'
    BLUE = '\033[34m'
    NC = '\033[0m'

def banner():
    print(f"{Colors.BLUE}=============================================={Colors.NC}")
    print(f"{Colors.GREEN}        Azure Storage Account Manager         {Colors.NC}")
    print(f"{Colors.BLUE}=============================================={Colors.NC}")

def pause():
    input("Press ENTER to continue...")

def select_from_list(options, default):
    for idx, val in enumerate(options, 1):
        if val == default:
            print(f"  {Colors.BLUE}{idx}) {val} (default){Colors.NC}")
        else:
            print(f"  {Colors.BLUE}{idx}) {val}{Colors.NC}")
    choice = input(f"Choose an option (ENTER for default: {default}): ")
    if not choice:
        return default
    if choice.isdigit() and 1 <= int(choice) <= len(options):
        return options[int(choice)-1]
    for val in options:
        if val == choice:
            return val
    return default

def run_az(args):
    result = subprocess.run(["az"] + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return result.stdout.strip(), result.stderr.strip(), result.returncode

def list_storage_accounts():
    print(f"{Colors.YELLOW}Fetching Storage Accounts from all Resource Groups...{Colors.NC}")
    out, err, code = run_az(["storage", "account", "list", "--query", "[].{name:name, rg:resourceGroup}", "-o", "tsv"])
    if not out:
        print(f"{Colors.RED}No Storage Accounts found.{Colors.NC}")
        return
    print(f"{Colors.GREEN}Storage Accounts found:{Colors.NC}")
    print("ID    Storage Account                          Resource Group")
    print("---------------------------------------------------------------")
    lines = out.splitlines()
    for idx, line in enumerate(lines, 1):
        parts = line.split('\t')
        if len(parts) == 2:
            print(f"{idx}    {parts[0]:<36} {parts[1]}")
    print()

def create_storage_account():
    print(f"{Colors.GREEN}Create new Storage Account{Colors.NC}")
    print(f"{Colors.YELLOW}Fetching Resource Groups...{Colors.NC}")
    out, _, _ = run_az(["group", "list", "--query", "[].name", "-o", "tsv"])
    rgs = out.splitlines()
    for idx, rg in enumerate(rgs, 1):
        print(f"  {idx}) {rg}")
    print("  0) Create NEW Resource Group")
    rg_choice = input("Choose a Resource Group option: ")
    if rg_choice == "0":
        RG = input("Enter new Resource Group name: ")
        RG_LOCATION = input("Location for new Resource Group (ENTER for eastus): ") or "eastus"
        print(f"{Colors.YELLOW}Creating Resource Group...{Colors.NC}")
        run_az(["group", "create", "--name", RG, "--location", RG_LOCATION])
    else:
        idx = int(rg_choice) - 1
        RG = rgs[idx] if 0 <= idx < len(rgs) else None
        if not RG:
            print(f"{Colors.RED}Invalid Resource Group selection.{Colors.NC}")
            return
    SA_NAME = input("Storage Account name (lowercase, 3-24 chars): ")
    if not SA_NAME:
        print(f"{Colors.RED}Name is required.{Colors.NC}")
        return
    LOCATIONS = ["eastus", "centralus", "westus", "eastus2", "southcentralus"]
    SKUS = ["Standard_LRS", "Standard_GRS", "Standard_RAGRS", "Standard_ZRS", "Premium_LRS"]
    KINDS = ["StorageV2", "Storage", "BlobStorage", "FileStorage", "BlockBlobStorage"]
    LOCATION = select_from_list(LOCATIONS, "eastus")
    SKU = select_from_list(SKUS, "Standard_LRS")
    KIND = select_from_list(KINDS, "StorageV2")
    print(f"{Colors.YELLOW}Creating Storage Account with Azure AD authentication enabled...{Colors.NC}")
    _, err, code = run_az([
        "storage", "account", "create",
        "--name", SA_NAME,
        "--resource-group", RG,
        "--location", LOCATION,
        "--sku", SKU,
        "--kind", KIND,
        "--allow-shared-key-access", "false",
        "--min-tls-version", "TLS1_2"
    ])
    if code != 0:
        print(f"{Colors.RED}Failed to create Storage Account: {err}{Colors.NC}")
        return
    print(f"{Colors.GREEN}Storage Account created successfully!{Colors.NC}")
    print(f"{Colors.YELLOW}Assigning 'Storage Blob Data Owner' role to the signed-in user...{Colors.NC}")
    user_id, _, _ = run_az(["ad", "signed-in-user", "show", "--query", "id", "-o", "tsv"])
    sub_id, _, _ = run_az(["account", "show", "--query", "id", "-o", "tsv"])
    _, _, _ = run_az([
        "role", "assignment", "create",
        "--assignee", user_id,
        "--role", "Storage Blob Data Owner",
        "--scope", f"/subscriptions/{sub_id}/resourceGroups/{RG}/providers/Microsoft.Storage/storageAccounts/{SA_NAME}"
    ])
    print(f"{Colors.GREEN}Role assignment completed! You now have permission to upload using --auth-mode login.{Colors.NC}")

def delete_storage_account(name=None):
    if not name:
        list_storage_accounts()
        choice = input("Enter the ID of the Storage Account to delete: ")
        out, _, _ = run_az(["storage", "account", "list", "--query", "[].{name:name, rg:resourceGroup}", "-o", "tsv"])
        lines = out.splitlines()
        idx = int(choice) - 1
        if idx < 0 or idx >= len(lines):
            print(f"{Colors.RED}Invalid selection.{Colors.NC}")
            return
        parts = lines[idx].split('\t')
        SA_NAME, RG = parts[0], parts[1]
    else:
        SA_NAME = name
        out, _, _ = run_az(["storage", "account", "show", "--name", SA_NAME, "--query", "resourceGroup", "-o", "tsv"])
        RG = out.strip()
    print(f"{Colors.RED}Are you sure you want to delete:{Colors.NC}")
    print(f"  Storage Account: {Colors.YELLOW}{SA_NAME}{Colors.NC}")
    print(f"  Resource Group:  {Colors.YELLOW}{RG}{Colors.NC}")
    confirm = input("Confirm deletion? (y/N): ")
    if confirm.lower() != "y":
        print(f"{Colors.YELLOW}Operation cancelled.{Colors.NC}")
        return
    print(f"{Colors.YELLOW}Deleting Storage Account...{Colors.NC}")
    _, _, code = run_az(["storage", "account", "delete", "--name", SA_NAME, "--resource-group", RG, "--yes"])
    if code == 0:
        print(f"{Colors.GREEN}Storage Account deleted successfully!{Colors.NC}")
    else:
        print(f"{Colors.RED}Error deleting Storage Account.{Colors.NC}")

def print_help():
    print("Usage: storage_account_manager.py [COMMAND] [OPTIONS]\n")
    print("Commands:")
    print("  list              List all Storage Accounts")
    print("  create            Create a new Storage Account")
    print("  delete [NAME]     Delete a Storage Account (select if NAME omitted)")
    print("  help              Show this help message\n")
    print("Examples:")
    print("  python storage_account_manager.py list")
    print("  python storage_account_manager.py create")
    print("  python storage_account_manager.py delete my-storage-account")

def main():
    if len(sys.argv) < 2:
        print_help()
        return
    cmd = sys.argv[1]
    if cmd == "list":
        banner()
        list_storage_accounts()
    elif cmd == "create":
        banner()
        create_storage_account()
    elif cmd == "delete":
        banner()
        name = sys.argv[2] if len(sys.argv) > 2 else None
        delete_storage_account(name)
    else:
        print_help()

if __name__ == "__main__":
    main()
