#!/usr/bin/env bash
set -euo pipefail

# AWS CLI v2 installer for Linux
# Prints the exact commands before executing them
# Usage: ./install_aws_cli_linux.sh [--uninstall]

print_cmd() {
  echo "[Command] $*"
}

uninstall_aws_cli() {
  echo "Uninstalling AWS CLI v2..." | sed 's/^/\x1b[33m/;s/$/\x1b[0m/'
  
  if [[ -f /usr/local/bin/aws ]]; then
    print_cmd sudo rm -f /usr/local/bin/aws
    sudo rm -f /usr/local/bin/aws
  fi
  
  if [[ -f /usr/local/bin/aws_completer ]]; then
    print_cmd sudo rm -f /usr/local/bin/aws_completer
    sudo rm -f /usr/local/bin/aws_completer
  fi
  
  if [[ -d /usr/local/aws-cli ]]; then
    print_cmd sudo rm -rf /usr/local/aws-cli
    sudo rm -rf /usr/local/aws-cli
  fi
  
  echo "AWS CLI uninstalled successfully." | sed 's/^/\x1b[32m/;s/$/\x1b[0m/'
  exit 0
}

require_root() {
  if [[ $(id -u) -ne 0 ]]; then
    echo "This script uses sudo for package installs and awscli installation."
    if ! command -v sudo >/dev/null 2>&1; then
      echo "sudo is required. Please install sudo or run as root." >&2
      exit 1
    fi
  fi
}

install_prereqs() {
  # Detect package manager and install curl and unzip
  if command -v apt-get >/dev/null 2>&1; then
    print_cmd sudo apt-get update
    sudo apt-get update
    print_cmd sudo apt-get install -y curl unzip
    sudo apt-get install -y curl unzip
  elif command -v dnf >/dev/null 2>&1; then
    print_cmd sudo dnf install -y curl unzip
    sudo dnf install -y curl unzip
  elif command -v yum >/dev/null 2>&1; then
    print_cmd sudo yum install -y curl unzip
    sudo yum install -y curl unzip
  elif command -v zypper >/dev/null 2>&1; then
    print_cmd sudo zypper install -y curl unzip
    sudo zypper install -y curl unzip
  else
    echo "Unsupported package manager. Please install curl and unzip manually." >&2
  fi
}

install_aws_cli() {
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  
  # Detect CPU architecture
  arch=$(uname -m)
  case "$arch" in
    x86_64)
      url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
      ;;
    aarch64|arm64)
      url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
      ;;
    *)
      echo "Unsupported architecture: $arch. Only x86_64 and aarch64 are supported." >&2
      exit 1
      ;;
  esac
  
  echo "Detected architecture: $arch"
  print_cmd curl -fsSL "$url" -o "$tmpdir/awscliv2.zip"
  curl -fsSL "$url" -o "$tmpdir/awscliv2.zip"

  print_cmd unzip -q "$tmpdir/awscliv2.zip" -d "$tmpdir"
  unzip -q "$tmpdir/awscliv2.zip" -d "$tmpdir"

  print_cmd sudo "$tmpdir/aws/install" --update
  sudo "$tmpdir/aws/install" --update
}

check_install() {
  if command -v aws >/dev/null 2>&1; then
    print_cmd aws --version
    aws --version
  else
    echo "AWS CLI not found on PATH after installation." >&2
    exit 1
  fi
}

main() {
  # Check for uninstall flag
  if [[ "${1:-}" == "--uninstall" ]] || [[ "${1:-}" == "-u" ]]; then
    require_root
    uninstall_aws_cli
  fi
  
  echo "AWS CLI v2 Installer (Linux)" | sed 's/^/\x1b[36m/;s/$/\x1b[0m/'
  require_root
  install_prereqs
  install_aws_cli
  check_install
  echo "Installation complete." | sed 's/^/\x1b[32m/;s/$/\x1b[0m/'
}

main "$@"
