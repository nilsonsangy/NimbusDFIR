#!/usr/bin/env python3
"""
Azure MySQL Manager Script - Python Version
Author: NimbusDFIR
Description: Manage MySQL databases (list, create, delete) via Azure tunnel or direct
"""
import subprocess
import getpass
import sys

def get_mysql_credentials():
    user = input("Enter MySQL admin username (default: mysqladmin): ").strip() or "mysqladmin"
    passwd = getpass.getpass("Enter MySQL admin password: ")
    return user, passwd

def list_databases():
    user, passwd = get_mysql_credentials()
    env = {**dict(**os.environ), 'MYSQL_PWD': passwd}
    try:
        result = subprocess.run([
            'mysql', '-h', '127.0.0.1', '-P', '3307', '-u', user, '-e', 'SHOW DATABASES;'
        ], capture_output=True, text=True, env=env, check=True)
        lines = [l.strip() for l in result.stdout.splitlines() if l.strip()]
        system = {"Database", "information_schema", "performance_schema", "mysql", "sys"}
        print("Available Databases:")
        for i, db in enumerate([d for d in lines if d not in system], 1):
            print(f"  {i}. {db}")
    except subprocess.CalledProcessError:
        print("Error: Could not connect to MySQL")

def create_database(name):
    if not name:
        name = input("Enter new database name: ").strip()
        if not name:
            print("Database name required")
            return
    user, passwd = get_mysql_credentials()
    env = {**dict(**os.environ), 'MYSQL_PWD': passwd}
    try:
        subprocess.run([
            'mysql', '-h', '127.0.0.1', '-P', '3307', '-u', user, '-e', f'CREATE DATABASE IF NOT EXISTS `{name}`;'
        ], env=env, check=True)
        print(f"✓ Database '{name}' created or already exists.")
    except subprocess.CalledProcessError:
        print(f"✗ Failed to create database '{name}'")

def delete_database(name):
    if not name:
        name = input("Enter database name to delete: ").strip()
        if not name:
            print("Database name required")
            return
    user, passwd = get_mysql_credentials()
    env = {**dict(**os.environ), 'MYSQL_PWD': passwd}
    confirm = input(f"Are you sure you want to delete database '{name}'? (y/N): ").strip().lower()
    if confirm != 'y':
        print("Deletion cancelled")
        return
    try:
        subprocess.run([
            'mysql', '-h', '127.0.0.1', '-P', '3307', '-u', user, '-e', f'DROP DATABASE IF EXISTS `{name}`;'
        ], env=env, check=True)
        print(f"✓ Database '{name}' deleted (if it existed).")
    except subprocess.CalledProcessError:
        print(f"✗ Failed to delete database '{name}'")

def show_usage():
    print("==========================================")
    print("Azure MySQL Manager - NimbusDFIR")
    print("==========================================")
    print()
    print("Usage: python mysql_manager.py [COMMAND] [DATABASE_NAME]")
    print()
    print("Commands:")
    print("  list                List all databases")
    print("  create [NAME]        Create a new database")
    print("  delete [NAME]        Delete a database")
    print("  help                 Show this help message")
    print()
    print("Examples:")
    print("  python mysql_manager.py list")
    print("  python mysql_manager.py create testdb")
    print("  python mysql_manager.py delete testdb")
    print()

def main():
    import os
    args = sys.argv[1:]
    if not args or args[0] == 'help':
        show_usage()
        return
    cmd = args[0]
    name = args[1] if len(args) > 1 else None
    if cmd == 'list':
        list_databases()
    elif cmd == 'create':
        create_database(name)
    elif cmd == 'delete':
        delete_database(name)
    else:
        show_usage()

if __name__ == "__main__":
    main()
