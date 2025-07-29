#!/bin/bash

set -e

AUTO_YES=false

# Check for -y flag
for arg in "$@"; do
  if [[ "$arg" == "-y" ]]; then
    AUTO_YES=true
  fi
done

confirm_or_skip() {
  local msg=$1
  if [ "$AUTO_YES" = true ]; then
    return 0
  fi

  read -rp "$msg [Y/n] " choice
  [[ "$choice" =~ ^[Yy]?$ ]]
}

install_aws_cli() {
  echo -e "\n--- AWS CLI Installation ---"
  if ! confirm_or_skip "Do you want to install AWS CLI?"; then return; fi

  tmp_dir=$(mktemp -d)
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$tmp_dir/awscliv2.zip"
  unzip -q "$tmp_dir/awscliv2.zip" -d "$tmp_dir"
  sudo "$tmp_dir/aws/install" --update
  rm -rf "$tmp_dir"
  echo "AWS CLI installed."
}

install_azure_cli() {
  echo -e "\n--- Azure CLI Installation ---"
  if ! confirm_or_skip "Do you want to install Azure CLI?"; then return; fi

  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  echo "Azure CLI installed."
}

install_gcloud_cli() {
  echo -e "\n--- Google Cloud CLI Installation ---"
  if ! confirm_or_skip "Do you want to install Google Cloud CLI?"; then return; fi

  tmp_dir=$(mktemp -d)
  curl -s https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-456.0.0-linux-x86_64.tar.gz -o "$tmp_dir/gcloud.tar.gz"
  tar -xzf "$tmp_dir/gcloud.tar.gz" -C "$tmp_dir"
  sudo "$tmp_dir/google-cloud-sdk/install.sh" --quiet
  rm -rf "$tmp_dir"
  echo "Google Cloud CLI installed."
}

echo "Cloud CLI Installer Script (Linux/macOS)"
echo "This script may prompt for sudo privileges."

install_aws_cli
install_azure_cli
install_gcloud_cli

# Update PATH in current session
export PATH=$PATH:$HOME/.local/bin:/usr/local/bin:/usr/bin

echo -e "\nAll selected CLI tools have been processed."

# Optional: Show versions
which aws &>/dev/null && aws --version
which az &>/dev/null && az version | grep azure-cli
which gcloud &>/dev/null && gcloud version | head -n 1
