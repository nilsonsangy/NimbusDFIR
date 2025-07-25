from google.cloud import compute_v1
import google.auth

def main():
    credentials, project = google.auth.default()
    account_email = getattr(credentials, 'service_account_email', None) or getattr(credentials, 'client_email', None)
    print(f'GCP connection successful! Account: {account_email}')
    client = compute_v1.RegionsClient()
    regions = client.list(project=project)
    print('Available regions:')
    for region in regions:
        print(region.name)

if __name__ == '__main__':
    main()
