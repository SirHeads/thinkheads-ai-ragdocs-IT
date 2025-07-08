#!/bin/bash

# common.sh
# Shared functions for Proxmox VE setup scripts
# Version: 1.1.2
# Author: Heads, Grok, Devstral

# Log file
LOGFILE="/var/log/proxmox_setup.log"

# Retry command with delay
retry_command() {
  local cmd="$*"
  local retries=3
  local delay=5
  local count=0

  until [ $count -ge $retries ]; do
    eval "$cmd" && return 0
    count=$((count + 1))
    echo "[$(date)] Command failed: $cmd (attempt $count/$retries)" >> "$LOGFILE"
    sleep $delay
  done
  echo "[$(date)] Command failed after $retries attempts: $cmd" >> "$LOGFILE"
  return 1
}

# Check if package is installed and verify critical binaries
check_package() {
  local package="$1"
  local binaries=()
  case $package in
    samba)
      binaries=("smbd" "pdbedit" "smbpasswd")
      ;;
    nfs-kernel-server)
      binaries=("rpc.nfsd" "exportfs")
      ;;
    firewalld)
      binaries=("firewall-cmd")
      ;;
    sudo)
      binaries=("sudo")
      ;;
    iptables)
      binaries=("iptables")
      ;;
    *)
      binaries=("$package")
      ;;
  esac

  # Check if package is installed
  if dpkg -l "$package" &>/dev/null; then
    # Verify all required binaries are present
    for bin in "${binaries[@]}"; do
      if ! command -v "$bin" &>/dev/null; then
        echo "[$(date)] Package $package is installed but binary $bin is missing" >> "$LOGFILE"
        return 1
      fi
    done
    echo "[$(date)] Package $package and required binaries are installed" >> "$LOGFILE"
    return 0
  fi
  echo "[$(date)] Package $package is not installed" >> "$LOGFILE"
  return 1
}

# Check if running as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" | tee -a "$LOGFILE"
    exit 1
  fi
}

# Check if service is active
systemctl_is_active() {
  local service="$1"
  systemctl is-active --quiet "$service" && return 0
  return 1
}