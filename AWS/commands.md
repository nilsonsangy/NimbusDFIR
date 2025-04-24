# AWS CLI Commands for EC2 Management

This document contains useful AWS CLI commands to manage the infrastructure created with CloudFormation.

## EC2 Commands

### Capture EC2 Instance Metadata
```bash
aws ec2 describe-instances --filters "Name=ip-address,Values=X.X.X.X"
```

### Protect EC2 Instance from Accidental Termination
```bash
aws ec2 modify-instance-attribute --instance-id i-abc1234 --attribute disableApiTermination --value true
```

### Isolate EC2 Instance
```bash
aws ec2 modify-instance-attribute --instance-id i-abc1234 --groups sg-alb2c3d4
```

### Detach EC2 Instance from Auto Scaling Group
```bash
aws autoscaling detach-instances --instance-ids i-abc1234 --auto-scaling-group-name web-asg
```

### Deregister EC2 Instance from ELB Services
```bash
aws elb deregister-instances-from-load-balancer --load-balancer-name web-load-balancer --instances i-abc1234
```

### Snapshot EBS Data Volumes
```bash
aws ec2 create-snapshot --volume vol-12xxxx78 --description "ResponderName-Date-REFERENCE-ID"
```

### Tag EC2 Instance
```bash
aws ec2 create-tags --resources i-abc1234 --tags Key=Environment,Value=Quarantine:REFERENCE-ID
```

## IAM Access Key Actions

### Search for IAM Access Key Actions in CloudTrail Logs
```bash
aws logs filter-log-events --region us-east-1 --start-time 1551402000000 --log-group-name CloudTrail/DefaultLogGroup --filter-pattern <Access Key ID> --output json --query 'events[*].message' | jq -r '.[] | fromjson | .userIdentity, .sourceIPAddress, .responseElements'
```