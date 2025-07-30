

<div align="center">
  <img src="https://img.shields.io/badge/Nimbus%20DFIR-Cloud%20Forensics%20%26%20Incident%20Response-blue?style=for-the-badge" alt="Nimbus DFIR Badge" />
</div>



# NimbusDFIR

Resources and tools for Digital Forensics and Incident Response (DFIR) in cloud environments (AWS, Azure, GCP). This project helps investigators and cloud engineers collect, analyze, and manage forensic evidence in multi-cloud scenarios.

---

## Table of Contents
1. [Project Structure](#project-structure)
2. [Summary of Scripts](#summary-of-scripts)
3. [Setup & Installation](#setup--installation)
4. [Usage Examples](#usage-examples)
5. [Contributing](#contributing)
6. [License](#license)
7. [Disclaimer](#disclaimer)

---

## Project Structure

| Folder   | Description |
|----------|-------------|
| `AWS/`   | AWS forensic tools, scripts, and templates |
| `Azure/` | Azure forensic tools and scripts (in development) |
| `GCP/`   | GCP forensic tools and scripts (in development) |

---

## Summary of Scripts

| Script/File                       | Description                                                      | Usage Example |
|-----------------------------------|------------------------------------------------------------------|--------------|
| `AWS/cloudformation-webapp.yaml`  | CloudFormation template for web app infrastructure                | AWS Console or CLI |
| `AWS/aws_ebs_snapshot_collector.py` | Collects EBS disk snapshots and generates SHA256 hashes           | `python AWS/aws_ebs_snapshot_collector.py <instance_id>` |
| `AWS/hello_aws.py`                | Tests AWS connection and prints account ID and regions            | `python AWS/hello_aws.py` |
| `Azure/hello_azure.py`            | Tests Azure connection and prints account info and subscriptions  | `python Azure/hello_azure.py` |
| `GCP/hello_gcp.py`                | Tests GCP connection and prints account email and regions         | `python GCP/hello_gcp.py` |
| `setup.ps1`                       | PowerShell script to set up Python environment and dependencies   | `pwsh ./setup.ps1` |
| `requirements.txt`                | Python dependencies for all scripts                              | `pip install -r requirements.txt` |
| `.env.example`                    | Example environment variables for AWS and Azure credentials       | Copy to `.env` and fill in secrets |

---

## Setup & Installation

1. **Clone the repository:**
   ```sh
   git clone https://github.com/nilsonsangy/nimbus.git
   cd nimbus
   ```
2. **Set up Python environment (Windows/PowerShell):**
   ```pwsh
   ./setup.ps1
   ```
3. **Configure environment variables:**
   - Copy `.env.example` to `.env` and fill in your AWS/Azure secrets.
   - Never commit `.env` to git.
4. **Install dependencies:**
   ```sh
   pip install -r requirements.txt
   ```

---

## Usage Examples


### AWS Hello Script
```sh
python AWS/hello_aws.py
```

### Azure Hello Script
```sh
python Azure/hello_azure.py
```

### GCP Hello Script
```sh
python GCP/hello_gcp.py
```

### AWS EBS Snapshot Collector
```sh
python AWS/aws_ebs_snapshot_collector.py <instance_id>
```

### PowerShell Environment Setup
```pwsh
./setup.ps1
```

### CloudFormation Template
Deploy using AWS Console or:
```sh
aws cloudformation deploy --template-file AWS/cloudformation-webapp.yaml --stack-name <your-stack>
```

---

## Contributing
Contributions are welcome! Please open issues or submit pull requests for new forensic tools, templates, or documentation for any cloud provider.

---


## License
This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

| ☕ Support this project (EN) | ☕ Apoie este projeto (PT-BR) |
|-----------------------------|------------------------------|
| If this project helps you or you think it's cool, consider supporting:<br>💳 [PayPal](https://www.paypal.com/donate/?business=7CC3CMJVYYHAC&no_recurring=0&currency_code=BRL)<br>![PayPal QR code](https://api.qrserver.com/v1/create-qr-code/?size=120x120&data=https://www.paypal.com/donate/?business=7CC3CMJVYYHAC&no_recurring=0&currency_code=BRL) | Se este projeto te ajuda ou você acha legal, considere apoiar:<br>🇧🇷 Pix: `df92ab3c-11e2-4437-a66b-39308f794173`<br>![Pix QR code](https://api.qrserver.com/v1/create-qr-code/?size=120x120&data=df92ab3c-11e2-4437-a66b-39308f794173) |

## Disclaimer
This project is for educational and research purposes only. Use responsibly and ensure compliance with your organization's policies and cloud provider terms of service. Never commit sensitive credentials or secrets to version control.
