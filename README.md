

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
4. [Contributing](#contributing)
5. [License](#license)
6. [Disclaimer](#disclaimer)

---

## Project Structure

| Folder   | Description |
|----------|-------------|
| `AWS/`   | AWS forensic tools, scripts, and templates |
| `Azure/` | Azure forensic tools and scripts (in development) |
| `GCP/`   | GCP forensic tools and scripts (in development) |

---

## Summary of Scripts

| Cloud | Script | Description |
|-------|--------|-------------|
| AWS | aws_ebs_snapshot_collector | Collects EBS disk snapshots and generates SHA256 hashes |
| AWS | aws_ebs_snapshot_hash | Generates SHA256 hashes for EBS snapshots |
| AWS | ec2_manager | Manage EC2 instances (list, create, start, stop, terminate) |
| AWS | hello_aws | Tests AWS connection and prints account ID and regions |
| AWS | install_aws_cli_macos | Installs AWS CLI v2 on macOS |
| AWS | s3_manager | Manage S3 buckets (list, create, remove, upload, download, dump) |
| Azure | hello_azure | Tests Azure connection and prints account info and subscriptions |
| GCP | hello_gcp | Tests GCP connection and prints account email and regions |

**Note:** Scripts are available in multiple formats:
- `.sh` - Bash (macOS/Linux)
- `.ps1` - PowerShell (Windows/Cross-platform)
- `.py` - Python with boto3 (Cross-platform)

---

## Setup & Installation

1. **Clone the repository:**
   ```sh
   git clone https://github.com/nilsonsangy/nimbus.git
   cd nimbus
   ```
2. **Configure environment variables:**
   
   Copy `.env.example` to `.env` and fill in your AWS/Azure secrets.
   
3. **Install dependencies:**
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
