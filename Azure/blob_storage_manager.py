#!/usr/bin/env python3
import subprocess
import sys
import os
import tempfile
import shutil
import zipfile
from datetime import datetime

# Colors
class Colors:
    GREEN = '\033[32m'
    YELLOW = '\033[33m'
    RED = '\033[31m'
    BLUE = '\033[34m'
    NC = '\033[0m'

def banner():
    print(f"{Colors.BLUE}=============================================={Colors.NC}")
    print(f"{Colors.GREEN}          Azure Blob Storage Manager          {Colors.NC}")
    print(f"{Colors.BLUE}=============================================={Colors.NC}")

def run_az(args):
    result = subprocess.run(["az"] + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return result.stdout.strip(), result.stderr.strip(), result.returncode

def get_all_blob_containers():
    out, _, _ = run_az(["storage", "account", "list", "--query", "[].name", "-o", "tsv"])
    accounts = out.splitlines()
    containers = []
    for account in accounts:
        c_out, _, _ = run_az(["storage", "container", "list", "--account-name", account, "--auth-mode", "login", "--query", "[].name", "-o", "tsv"])
        for c in c_out.splitlines():
            if c:
                containers.append((c, account))
    return containers

def list_all_blob_containers():
    containers = get_all_blob_containers()
    if not containers:
        print(f"{Colors.RED}No Blob Containers found in any Storage Account.{Colors.NC}")
        return
    print(f"{'#':<3} {'Container':<30} {'Account':<30}")
    for idx, (c, a) in enumerate(containers, 1):
        print(f"{idx:<3} {c:<30} {a:<30}")

def upload_to_blob_container(files, container):
    containers = get_all_blob_containers()
    account = None
    for c, a in containers:
        if c == container:
            account = a
            break
    if not account:
        print(f"{Colors.RED}Blob Container '{container}' not found.{Colors.NC}")
        return
    for file in files:
        if not os.path.isfile(file):
            print(f"{Colors.RED}File not found: {file}{Colors.NC}")
            continue
        blob_name = os.path.basename(file)
        print(f"Uploading {file} as blob '{blob_name}' to container '{container}' in account '{account}'...")
        _, err, code = run_az(["storage", "blob", "upload", "--account-name", account, "--container-name", container, "--file", file, "--name", blob_name, "--auth-mode", "login"])
        if code == 0:
            print(f"{Colors.GREEN}Upload complete: {blob_name}{Colors.NC}")
        else:
            print(f"{Colors.RED}Upload failed for {file}: {err}{Colors.NC}")

def download_from_blob_container(container, blob=None):
    containers = get_all_blob_containers()
    account = None
    for c, a in containers:
        if c == container:
            account = a
            break
    if not account:
        print(f"{Colors.RED}Blob Container '{container}' not found.{Colors.NC}")
        return
    out, _, _ = run_az(["storage", "blob", "list", "--account-name", account, "--container-name", container, "--query", "[].name", "-o", "tsv", "--auth-mode", "login"])
    blobs = out.splitlines()
    if not blobs:
        print(f"{Colors.RED}No blobs found.{Colors.NC}")
        return
    if not blob:
        print("Available blobs:")
        for idx, b in enumerate(blobs, 1):
            print(f"  {idx}) {b}")
        sel = input("Choose blob (ENTER = all): ")
        if not sel:
            for b in blobs:
                default_path = os.path.expanduser(f"~/Downloads/{b}")
                save_path = input(f"Download '{b}' to {default_path}? (ENTER to confirm, or type path): ") or default_path
                _, err, code = run_az(["storage", "blob", "download", "--account-name", account, "--container-name", container, "--name", b, "--file", save_path, "--auth-mode", "login"])
                if code == 0:
                    print(f"{Colors.GREEN}Download complete: {save_path}{Colors.NC}")
                else:
                    print(f"{Colors.RED}Download failed for {b}: {err}{Colors.NC}")
            return
        try:
            idx = int(sel) - 1
            blob = blobs[idx]
        except:
            print(f"{Colors.RED}Invalid selection.{Colors.NC}")
            return
    default_path = os.path.expanduser(f"~/Downloads/{blob}")
    save_path = input(f"Download '{blob}' to {default_path}? (ENTER to confirm, or type path): ") or default_path
    _, err, code = run_az(["storage", "blob", "download", "--account-name", account, "--container-name", container, "--name", blob, "--file", save_path, "--auth-mode", "login"])
    if code == 0:
        print(f"{Colors.GREEN}Download complete: {save_path}{Colors.NC}")
    else:
        print(f"{Colors.RED}Download failed for {blob}: {err}{Colors.NC}")

def dump_blob_container(container):
    containers = get_all_blob_containers()
    account = None
    for c, a in containers:
        if c == container:
            account = a
            break
    if not account:
        print(f"{Colors.RED}Blob Container '{container}' not found.{Colors.NC}")
        return
    temp_dir = tempfile.mkdtemp()
    print(f"Downloading all blobs from '{container}'...")
    _, err, code = run_az(["storage", "blob", "download-batch", "--account-name", account, "--destination", temp_dir, "--source", container, "--auth-mode", "login"])
    if code != 0:
        print(f"{Colors.RED}Error downloading blobs: {err}{Colors.NC}")
        shutil.rmtree(temp_dir)
        return
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    zip_name = f"{container}_{timestamp}.zip"
    default_zip = os.path.expanduser(f"~/Downloads/{zip_name}")
    zip_path = input(f"Save zip to {default_zip}? (ENTER to confirm, or type path): ") or default_zip
    print(f"Zipping files to {zip_path}...")
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, _, files in os.walk(temp_dir):
            for file in files:
                abs_path = os.path.join(root, file)
                rel_path = os.path.relpath(abs_path, temp_dir)
                zipf.write(abs_path, rel_path)
    print(f"{Colors.GREEN}Dump complete: {zip_path}{Colors.NC}")
    shutil.rmtree(temp_dir)

def info_blob_container(container):
    containers = get_all_blob_containers()
    account = None
    for c, a in containers:
        if c == container:
            account = a
            break
    if not account:
        print(f"{Colors.RED}Blob Container '{container}' not found.{Colors.NC}")
        return
    out, err, code = run_az(["storage", "container", "show", "--account-name", account, "--name", container, "--auth-mode", "login"])
    if code == 0:
        print(out)
    else:
        print(f"{Colors.RED}Error: {err}{Colors.NC}")

def main():
    if len(sys.argv) < 2:
        banner()
        print("Usage: blob_storage_manager.py [COMMAND] [ARGS]")
        print("Commands: list, upload, download, dump, info")
        return
    cmd = sys.argv[1]
    if cmd == "list":
        banner()
        list_all_blob_containers()
    elif cmd == "upload":
        banner()
        if len(sys.argv) < 4:
            print("Usage: upload <file1> [file2 ...] <container>")
            return
        files = sys.argv[2:-1]
        container = sys.argv[-1]
        upload_to_blob_container(files, container)
    elif cmd == "download":
        banner()
        if len(sys.argv) < 3:
            print("Usage: download <container> [blob]")
            return
        container = sys.argv[2]
        blob = sys.argv[3] if len(sys.argv) > 3 else None
        download_from_blob_container(container, blob)
    elif cmd == "dump":
        banner()
        if len(sys.argv) < 3:
            print("Usage: dump <container>")
            return
        container = sys.argv[2]
        dump_blob_container(container)
    elif cmd == "info":
        banner()
        if len(sys.argv) < 3:
            print("Usage: info <container>")
            return
        container = sys.argv[2]
        info_blob_container(container)
    else:
        print("Unknown command.")

if __name__ == "__main__":
    main()
