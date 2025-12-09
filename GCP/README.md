# GCP - Google Cloud Platform Scripts

This directory contains scripts for managing and investigating resources in Google Cloud Platform (GCP), focusing on Digital Forensics and Incident Response (DFIR) operations.

---

## 📋 Available Scripts

### VM Management
- **`compute_engine_manager.ps1`** - Manage GCP Compute Engine VM instances
  - List all VM instances with details (zone, machine type, status, IP)
  - Create new VM instances (interactive setup with cost-optimized options)
  - Start stopped VM instances
  - Stop running VM instances
  - Delete VM instances
  - Supports preemptible (spot) instances for cost savings
  - Auto-detects zones and validates permissions

### Connection Testing
- **`hello_gcp.ps1`** - Test GCP connectivity and authentication
  - Verifies gcloud CLI installation
  - Checks authentication status
  - Validates project configuration
  - Tests API connectivity
  - Displays project details and default settings

- **`hello_gcp.py`** - Python version of GCP connection test
  - Tests GCP connection
  - Prints account email and available regions

### Installation
- **`install_gcloud_cli_windows.ps1`** - Install Google Cloud CLI on Windows
  - User-level installation (no admin rights required)
  - Silent installation with automatic PATH configuration
  - Uninstall support with `-Uninstall` parameter
  - Downloads official installer from Google

---

## 🚀 Quick Start

### Prerequisites
1. **Install gcloud CLI:**
   ```powershell
   .\install_gcloud_cli_windows.ps1
   ```

2. **Authenticate:**
   ```powershell
   gcloud auth login
   ```

3. **Set your project:**
   ```powershell
   gcloud config set project YOUR_PROJECT_ID
   ```

4. **Enable Compute Engine API:**
   ```powershell
   gcloud services enable compute.googleapis.com
   ```

### Test Connection
```powershell
.\hello_gcp.ps1
```

### Manage VMs
```powershell
# List all VM instances
.\compute_engine_manager.ps1 list

# Create a new VM (interactive)
.\compute_engine_manager.ps1 create

# Start a VM
.\compute_engine_manager.ps1 start vm-name

# Stop a VM
.\compute_engine_manager.ps1 stop vm-name

# Delete a VM
.\compute_engine_manager.ps1 delete vm-name
```

---

## 💡 Features

### Compute Engine Manager
- **Cost-optimized defaults:**
  - e2-micro machine type (lowest cost)
  - us-central1-a zone (Iowa - lowest cost region)
  - Ubuntu 22.04 LTS as default image
  - 10 GB boot disk

- **Flexible options:**
  - 5 machine types (e2-micro to e2-standard-2)
  - 5 zones across different regions
  - 5 OS images (Ubuntu, Debian, CentOS)
  - Preemptible (spot) instances for up to 80% cost savings
  - Custom disk sizes

- **Smart features:**
  - Auto-generated unique VM names (gcp-vm-XXXX)
  - Zone auto-detection for existing VMs
  - Interactive selection for start/stop/delete operations
  - Prints all gcloud commands before execution (educational)

### Installation Script
- **User-friendly:**
  - No administrator privileges required
  - Installs to `%LOCALAPPDATA%\Google\Cloud SDK`
  - Automatic PATH configuration
  - Clean uninstallation support

---

## 📚 Common Operations

### Create a Cost-Effective VM
```powershell
.\compute_engine_manager.ps1 create
# Press Enter for defaults:
# - Name: gcp-vm-XXXX (auto-generated)
# - Zone: us-central1-a (Iowa)
# - Machine: e2-micro (2 vCPU, 1 GB RAM)
# - Image: Ubuntu 22.04 LTS
# - Disk: 10 GB
# Answer 'y' for preemptible to save up to 80% cost
```

### List Running VMs
```powershell
.\compute_engine_manager.ps1 list
```

### Stop All Running VMs (Interactive)
```powershell
.\compute_engine_manager.ps1 stop
# Select from numbered list
```

---

## 🔧 Configuration

### Set Default Region and Zone
```powershell
gcloud config set compute/region us-central1
gcloud config set compute/zone us-central1-a
```

### View Current Configuration
```powershell
gcloud config list
```

### Switch Projects
```powershell
gcloud config set project ANOTHER_PROJECT_ID
```

---

## 🌍 Available Zones (by cost)

| Zone | Location | Cost Tier |
|------|----------|-----------|
| us-central1-a | Iowa | Lowest |
| us-west1-a | Oregon | Low |
| us-east1-b | South Carolina | Low |
| us-south1-a | Dallas | Low |
| europe-west4-a | Netherlands | Medium |

---

## 💻 Machine Types

| Type | vCPU | RAM | Use Case |
|------|------|-----|----------|
| e2-micro | 2 | 1 GB | Testing, low-traffic apps |
| e2-small | 2 | 2 GB | Light workloads |
| e2-medium | 2 | 4 GB | Development environments |
| e2-standard-2 | 2 | 8 GB | Small production apps |
| n1-standard-1 | 1 | 3.75 GB | Legacy workloads |

---

## 🔐 Security Best Practices

1. **Use preemptible instances for non-critical workloads** - Up to 80% cost savings
2. **Enable automatic updates** for OS security patches
3. **Use service accounts** with minimal required permissions
4. **Enable VPC firewall rules** to restrict access
5. **Use SSH keys** instead of passwords
6. **Enable audit logging** for compliance

---

## 🆘 Troubleshooting

### API Not Enabled
If you see: `API [compute.googleapis.com] not enabled`
```powershell
gcloud services enable compute.googleapis.com
```
Wait a few minutes for the API to activate.

### Authentication Issues
```powershell
gcloud auth login
gcloud auth list
```

### Project Not Set
```powershell
gcloud projects list
gcloud config set project PROJECT_ID
```

### Permission Denied
Ensure your account has the `Compute Admin` role:
```powershell
gcloud projects get-iam-policy PROJECT_ID --flatten="bindings[].members" --filter="bindings.members:user:YOUR_EMAIL"
```

---

## 📖 Additional Resources

- [GCP Compute Engine Documentation](https://cloud.google.com/compute/docs)
- [GCP Pricing Calculator](https://cloud.google.com/products/calculator)
- [gcloud CLI Reference](https://cloud.google.com/sdk/gcloud/reference)
- [GCP Free Tier](https://cloud.google.com/free)

---

## 🤝 Contributing

Contributions are welcome! Please submit issues or pull requests for:
- New GCP management scripts
- Bug fixes
- Documentation improvements
- Additional cloud forensics tools

---

## ⚠️ Disclaimer

These scripts are for educational and research purposes. Always:
- Test in development environments first
- Follow your organization's cloud policies
- Review costs before creating resources
- Enable billing alerts to avoid unexpected charges
- Clean up resources when no longer needed

---

**Note:** All scripts print the actual gcloud commands being executed for transparency and educational purposes.
