#!/usr/bin/env python3
import argparse
import json
import subprocess


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
    parser = argparse.ArgumentParser(description="AWS RDS Insert Mock Data (Python)")
    parser.add_argument("--instance-id")
    parser.add_argument("--engine", choices=["mysql", "postgres"], help="DB engine")
    parser.add_argument("--user")
    parser.add_argument("--password")
    parser.add_argument("--database")
    parser.add_argument("--table-name", default="mock_data")
    parser.add_argument("--row-count", type=int, default=10)
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

    if engine == "mysql":
        print(f"[Command] mysql -h {endpoint} -P {port or 3306} -u {user} -p****** {database}")
        env = {**dict(**dict()), "MYSQL_PWD": password}
        sql_create = f"""
CREATE TABLE IF NOT EXISTS {args.table_name} (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
"""
        subprocess.run(["mysql", "-h", endpoint, "-P", str(port or 3306), "-u", user, database, "-e", sql_create], env=env)
        for i in range(1, args.row_count + 1):
            name = f"Name_{i}"
            subprocess.run(["mysql", "-h", endpoint, "-P", str(port or 3306), "-u", user, database, "-e", f"INSERT INTO {args.table_name} (name) VALUES ('{name}');"], env=env)
        print(f"Inserted {args.row_count} rows into {args.table_name}")
    elif engine == "postgres":
        print(f"[Command] psql postgresql://{user}:******@{endpoint}:{port or 5432}/{database}")
        env = {**dict(**dict()), "PGPASSWORD": password}
        sql_create = f"""
CREATE TABLE IF NOT EXISTS {args.table_name} (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
"""
        subprocess.run(["psql", f"postgresql://{user}:{password}@{endpoint}:{port or 5432}/{database}", "-c", sql_create], env=env)
        for i in range(1, args.row_count + 1):
            name = f"Name_{i}"
            subprocess.run(["psql", f"postgresql://{user}:{password}@{endpoint}:{port or 5432}/{database}", "-c", f"INSERT INTO {args.table_name} (name) VALUES ('{name}');"], env=env)
        print(f"Inserted {args.row_count} rows into {args.table_name}")
    else:
        raise SystemExit(f"Unsupported engine: {engine}")


if __name__ == "__main__":
    main()
