#!/bin/bash

# proxmox_create_lxc_user.sh
# Creates a Linux user with Samba credentials and NFS access for a container/VM

set -e
LOGFILE="/var/log/proxmox_setup.log"
echo "[$(date)] Starting proxmox_create_lxc_user.sh" >> $LOGFILE

# Function to check if script is run as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run with sudo" | tee -a $LOGFILE
    exit 1
  fi
}

# Prompt for username
prompt_for_username() {
  read -p "Enter new username for container/VM: " USERNAME
  if [[ -z "$USERNAME" ]]; then
    echo "Error: Username cannot be empty" | tee -a $LOGFILE
    exit 1
  fi

  # Check if user already exists using getent for security reasons
  if getent passwd "$USERNAME" &>/dev/null; then
    echo "Warning: User $USERNAME already exists, skipping user creation" | tee -a $LOGFILE
  else
    create_user
  fi
}

# Create Linux user without home directory or login shell
create_user() {
  useradd -M -s /bin/false "$USERNAME"
  echo "[$(date)] Created Linux user $USERNAME" >> $LOGFILE
}

# Get UID for NFS compatibility
get_uid() {
  UID=$(id -u "$USERNAME")
  if [[ -z "$UID" ]]; then
    echo "Error: Failed to get UID for $USERNAME" | tee -a $LOGFILE
    exit 1
  fi
  echo "[$(date)] User $USERNAME has UID $UID" >> $LOGFILE
}

# Prompt for Samba password
setup_samba_password() {
  echo "Setting up Samba password for user '$USERNAME'. Enter a password for Samba access."
  smbpasswd -a "$USERNAME"
  if [[ $? -eq 0 ]]; then
    echo "[$(date)] Set Samba password for user $USERNAME" >> $LOGFILE
  else
    echo "Error: Failed to set Samba password for $USERNAME" | tee -a $LOGFILE
    exit 1
  fi
}

# Main script execution
check_root
prompt_for_username
get_uid
setup_samba_password

echo "Setup complete for user '$USERNAME'."
echo "- Samba access: \\\\10.0.0.13\\<dataset> (use '$USERNAME' and Samba password)"
echo "- NFS access (in container/VM): mount -t nfs 10.0.0.13:/shared/<dataset> /mnt/<dataset>"
echo "- UID: $UID (use for container/VM config)"
echo "Store the Samba password securely."
echo "[$(date)] Completed proxmox_create_lxc_user.sh" >> $LOGFILE