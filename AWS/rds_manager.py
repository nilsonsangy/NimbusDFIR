#!/usr/bin/env python3
import argparse
import json
import subprocess

try:
    import boto3
except ImportError:
    boto3 = None


def aws_cli(*args):
    print("[AWS CLI] aws", " ".join(args))
    return subprocess.run(["aws", *args], capture_output=True, text=True)


def list_instances():
    res = aws_cli("rds", "describe-db-instances", "--query",
                  "DBInstances[].{Id:DBInstanceIdentifier,Engine:Engine,Status:DBInstanceStatus,Endpoint:Endpoint.Address}",
                  "--output", "table")
    print(res.stdout)


def describe_instance(instance_id: str):
    if not instance_id:
        raise SystemExit("InstanceId is required for describe.")
    res = aws_cli("rds", "describe-db-instances", "--db-instance-identifier", instance_id, "--output", "json")
    print(res.stdout)


def start_instance(instance_id: str):
    if not instance_id:
        raise SystemExit("InstanceId is required for start.")
    res = aws_cli("rds", "start-db-instance", "--db-instance-identifier", instance_id)
    print(res.stdout)


def stop_instance(instance_id: str):
    if not instance_id:
        raise SystemExit("InstanceId is required for stop.")
    res = aws_cli("rds", "stop-db-instance", "--db-instance-identifier", instance_id)
    print(res.stdout)


def main():
    parser = argparse.ArgumentParser(description="AWS RDS Manager (Python)")
    parser.add_argument("command", choices=["list", "describe", "start", "stop", "help"], help="Command to run")
    parser.add_argument("--instance-id", dest="instance_id")
    args = parser.parse_args()

    if args.command == "help":
        parser.print_help()
        return
    if args.command == "list":
        list_instances()
    elif args.command == "describe":
        describe_instance(args.instance_id)
    elif args.command == "start":
        start_instance(args.instance_id)
    elif args.command == "stop":
        stop_instance(args.instance_id)


if __name__ == "__main__":
    main()
