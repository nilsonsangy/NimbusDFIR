#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
from datetime import datetime


def aws_cli(*args):
    print("[AWS CLI] aws", " ".join(args))
    return subprocess.run(["aws", *args], capture_output=True, text=True)


def get_instance_info(instance_id: str):
    if not instance_id:
        return None
    res = aws_cli("rds", "describe-db-instances", "--db-instance-identifier", instance_id, "--output", "json")
    data = json.loads(res.stdout or "{}")
    db = (data.get("DBInstances") or [None])[0]
    if not db:
        raise SystemExit(f"Instance not found: {instance_id}")
    return db


def main():
    parser = argparse.ArgumentParser(description="AWS RDS Dump (Python)")
    parser.add_argument("--instance-id")
    parser.add_argument("--engine", choices=["mysql", "postgres"], help="DB engine")
    parser.add_argument("--user")
    parser.add_argument("--password")
    parser.add_argument("--database")
    parser.add_argument("--output-path")
    args = parser.parse_args()

    endpoint = None
    port = None
    if args.instance_id:
        db = get_instance_info(args.instance_id)
        endpoint = db["Endpoint"]["Address"]
        port = db["Endpoint"]["Port"]
        args.engine = args.engine or db["Engine"]

    engine = args.engine or input("Engine (mysql/postgres): ")
    endpoint = endpoint or input("Endpoint address: ")
    user = args.user or input("Username: ")
    password = args.password or input("Password: ")
    database = args.database or input("Database name: ")

    output_path = args.output_path
    if not output_path:
        downloads = os.path.join(os.path.expanduser("~"), "Downloads")
        fname = f"{database}_dump_{datetime.now().strftime('%Y%m%d_%H%M%S')}.sql"
        output_path = os.path.join(downloads, fname)
        print(f"No output path specified. Using: {output_path}")

    if engine == "mysql":
        print(f"[Command] mysqldump -h {endpoint} -P {port or 3306} -u {user} -p****** {database} > {output_path}")
        env = {**dict(**dict()), "MYSQL_PWD": password}
        with open(output_path, "w", encoding="utf-8") as f:
            subprocess.run(["mysqldump", "-h", endpoint, "-P", str(port or 3306), "-u", user, database], env=env, stdout=f)
        print(f"Dump saved to {output_path}")
    elif engine == "postgres":
        print(f"[Command] pg_dump -h {endpoint} -p {port or 5432} -U {user} -d {database} -f {output_path}")
        env = {**dict(**dict()), "PGPASSWORD": password}
        subprocess.run(["pg_dump", "-h", endpoint, "-p", str(port or 5432), "-U", user, "-d", database, "-f", output_path], env=env)
        print(f"Dump saved to {output_path}")
    else:
        raise SystemExit(f"Unsupported engine: {engine}")


if __name__ == "__main__":
    main()
