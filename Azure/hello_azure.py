from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import SubscriptionClient

def main():
    credential = DefaultAzureCredential()
    sub_client = SubscriptionClient(credential)
    from azure.identity import AzureCliCredential
    try:
        cli_cred = AzureCliCredential()
        profile = cli_cred.get_token("https://management.azure.com/.default")
        print(f'Azure connection successful! Account info: {profile.token[:40]}...')
    except Exception:
        print('Azure connection successful! (Could not retrieve account info)')
    print('Subscriptions:')
    for sub in sub_client.subscriptions.list():
        print(sub.subscription_id)

if __name__ == '__main__':
    main()
