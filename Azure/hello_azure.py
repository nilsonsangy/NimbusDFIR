import os
from dotenv import load_dotenv
from azure.identity import EnvironmentCredential
from azure.mgmt.resource import SubscriptionClient

def main():
    # Load environment variables from .env in the project root
    env_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), '.env')
    load_dotenv(env_path)
    credential = EnvironmentCredential()
    sub_client = SubscriptionClient(credential)
    try:
        token = credential.get_token("https://management.azure.com/.default")
        print(f'Azure connection successful! Token: {token.token[:40]}...')
    except Exception as e:
        print(f'Azure connection failed: {e}')
    print('Subscriptions:')
    try:
        for sub in sub_client.subscriptions.list():
            print(sub.subscription_id)
            # Enumerate resource groups in this subscription
            try:
                from azure.mgmt.resource import ResourceManagementClient
                res_client = ResourceManagementClient(credential, sub.subscription_id)
                print('  Resource Groups:')
                for rg in res_client.resource_groups.list():
                    print(f'    - {rg.name}')
            except Exception as e:
                print(f'  Could not list resource groups: {e}')

            # Enumerate available locations for this subscription
            try:
                print('  Locations:')
                for loc in sub_client.subscriptions.list_locations(sub.subscription_id):
                    print(f'    - {loc.display_name} ({loc.name})')
            except Exception as e:
                print(f'  Could not list locations: {e}')
    except Exception as e:
        print(f'Could not list subscriptions: {e}')

if __name__ == '__main__':
    main()
