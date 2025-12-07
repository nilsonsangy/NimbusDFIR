#!/usr/bin/env python3
import argparse
import subprocess
import json


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
    parser = argparse.ArgumentParser(description="AWS RDS Connect (Python)")
    parser.add_argument("--instance-id")
    parser.add_argument("--engine", choices=["mysql", "postgres"], help="DB engine")
    parser.add_argument("--user")
    parser.add_argument("--password")
    parser.add_argument("--database")
    parser.add_argument("--port", type=int)
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
    port = port or int(input("Port (e.g., 3306/5432): "))
    user = args.user or input("Username: ")
    password = args.password or input("Password: ")
    database = args.database or input("Database name: ")

    if engine == "mysql":
        print(f"[Command] mysql -h {endpoint} -P {port} -u {user} -p****** {database}")
        env = {**dict(**dict()), "MYSQL_PWD": password}
        subprocess.run(["mysql", "-h", endpoint, "-P", str(port), "-u", user, database], env=env)
    elif engine == "postgres":
        print(f"[Command] psql postgresql://{user}:******@{endpoint}:{port}/{database}")
        env = {**dict(**dict()), "PGPASSWORD": password}
        subprocess.run(["psql", f"postgresql://{user}:{password}@{endpoint}:{port}/{database}"], env=env)
    else:
        raise SystemExit(f"Unsupported engine: {engine}")


if __name__ == "__main__":
    main()
