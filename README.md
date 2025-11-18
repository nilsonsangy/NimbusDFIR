

<div align="center">
  <img src="https://img.shields.io/badge/Nimbus%20DFIR-Cloud%20Forensics%20%26%20Incident%20Response-blue?style=for-the-badge" alt="Nimbus DFIR Badge" />
</div>



# ☁️ NimbusDFIR

Resources and tools for Digital Forensics and Incident Response (DFIR) in cloud environments (AWS, Azure, GCP). This project helps investigators and cloud engineers collect, analyze, and manage forensic evidence in multi-cloud scenarios.

---

## Table of Contents
1. [Summary of Scripts](#summary-of-scripts)
2. [Setup & Installation](#setup--installation)
3. [Contributing](#contributing)
4. [License](#license)
5. [Disclaimer](#disclaimer)

---

## Summary of Scripts

| Cloud | Script | Description |
|-------|--------|-------------|
| AWS | aws_ebs_snapshot_collector | Collects EBS disk snapshots and generates SHA256 hashes |
| | aws_ebs_snapshot_hash | Generates SHA256 hashes for EBS snapshots |
| | ec2_manager | Manage EC2 instances (list, create, start, stop, terminate) |
| | ec2_evidence_preservation | Digital forensics and incident response for EC2 (isolate, snapshot evidence) |
| | hello_aws | Tests AWS connection and prints account ID and regions |
| | install_aws_cli_macos | Installs AWS CLI v2 on macOS |
| | rds_connect | Connect to RDS instances (public or private via bastion host) |
| | rds_dump_database | Dump RDS databases with interactive or direct mode |
| | rds_insert_mock_data | Insert mock e-commerce data into RDS databases |
| | s3_manager | Manage S3 buckets (list, create, delete, upload, download, dump) |
| Azure | hello_az | Tests Azure connection and prints account info and subscriptions |
| | install_azure_cli_macos | Installs Azure CLI on macOS |
| GCP | hello_gcp | Tests GCP connection and prints account email and regions |

**Note:** Scripts are available in multiple formats:
- `.sh` - Bash (macOS/Linux)
- `.ps1` - PowerShell (Windows/Cross-platform)
- `.py` - Python with boto3 (Cross-platform)

---

## Setup & Installation

1. **Clone the repository:**
   ```sh
   git clone https://github.com/nilsonsangy/NimbusDFIR.git
   cd NimbusDFIR
   ```
2. **Install dependencies if you intend to use the Python scripts included in this project:**
   ```sh
   pip install -r requirements.txt
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
This project is for educational and research purposes only. Use responsibly and ensure compliance with your organization's policies and cloud provider terms of service.
