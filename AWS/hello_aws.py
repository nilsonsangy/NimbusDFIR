import boto3

def main():
    ec2 = boto3.client('ec2')
    sts = boto3.client('sts')
    account_id = sts.get_caller_identity()['Account']
    print(f'AWS connection successful! Account ID: {account_id}')
    regions = ec2.describe_regions()['Regions']
    print('Available regions:')
    for region in regions:
        print(region['RegionName'])

if __name__ == '__main__':
    main()
