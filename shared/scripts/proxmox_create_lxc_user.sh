#!/bin/bash

# proxmox_create_lxc_user.sh
# Creates a Linux user with Samba credentials and NFS access for Proxmox LXC containers/VMs
# Version: 1.1.0
# Author: Heads, Grok, Devstral
# Usage: ./proxmox_create_lxc_user.sh [--username <username>]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }

# Constants
SERVER_IP="10.0.0.13"
ZFS_4TB_POOL="fastData"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --username)
      USERNAME="$2"
      shift 2
      ;;
    *)
      echo "Error: Unknown option $1" | tee -a "$LOGFILE"
      exit 1
      ;;
  esac
done

# Prompt for username if not provided
prompt_for_username() {
  if [[ -z "$USERNAME" ]]; then
    read -p "Enter new username for container/VM: " USERNAME
  fi
  if [[ -z "$USERNAME" ]]; then
    echo "Error: Username cannot be empty" | tee -a "$LOGFILE"
    exit 1
  fi
}

# Create Linux user
create_user() {
  if getent passwd "$USERNAME" &>/dev/null; then
    echo "Warning: User $USERNAME already exists, skipping user creation" | tee -a "$LOGFILE"
    return 0
  fi
  retry_command "useradd -M -s /bin/false $USERNAME"
  echo "[$(date)] Created Linux user $USERNAME" >> "$LOGFILE"
}

# Get UID for NFS compatibility
get_uid() {
  UID=$(id -u "$USERNAME")
  if [[ -z "$UID" ]]; then
    echo "Error: Failed to get UID for $USERNAME" | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date)] User $USERNAME has UID $UID" >> "$LOGFILE"
}

# Verify Samba service
verify_samba_service() {
  if ! check_package samba; then
    echo "Error: Samba is not installed. Run proxmox_setup_zfs_nfs_samba.sh first" | tee -a "$LOGFILE"
    exit 1
  fi
  if ! systemctl is-active --quiet smbd; then
    retry_command "systemctl start smbd"
    echo "[$(date)] Started Samba service" >> "$LOGFILE"
  else
    echo "[$(date)] Samba service is already running" >> "$LOGFILE"
  fi
}

# Setup Samba password
setup_samba_password() {
  echo "Setting Samba password for user '$USERNAME'."
  retry_command "smbpasswd -a $USERNAME"
  echo "[$(date)] Set Samba password for user $USERNAME" >> "$LOGFILE"
}

# Main execution
check_root
prompt_for_username
create_user
get_uid
verify_samba_service
setup_samba_password

echo "Setup complete for user '$USERNAME'."
echo "- Samba access: \\\\$SERVER_IP\\<dataset> (use '$USERNAME' and Samba password)"
echo "- NFS access: mount -t nfs $SERVER_IP:/$ZFS_4TB_POOL/<dataset> /mnt/<dataset>"
echo "- UID: $UID (use for container/VM config)"
echo "Store the Samba password securely."
echo "[$(date)] Completed proxmox_create_lxc_user.sh" >> "$LOGFILE"