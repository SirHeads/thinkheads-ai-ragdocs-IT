#!/bin/bash

# proxmox_create_admin_user.sh
# Creates a non-root Linux user with sudo and Proxmox admin privileges, sets up SSH key-based authentication

set -e
LOGFILE="/var/log/proxmox_setup.log"
echo "[$(date)] Starting proxmox_create_admin_user.sh" >> $LOGFILE

# Function to check if script is run as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run with sudo" | tee -a $LOGFILE
    exit 1
  fi
}

# Prompt for username (default: heads)
read -p "Enter new admin username [heads]: " USERNAME
USERNAME=${USERNAME:-heads}
if [[ -z "$USERNAME" ]]; then
  echo "Error: Username cannot be empty" | tee -a $LOGFILE
  exit 1
fi

# Check if user already exists using getent for security reasons
if getent passwd "$USERNAME" &>/dev/null; then
  echo "Warning: User $USERNAME already exists, skipping user creation" | tee -a $LOGFILE
else
  # Prompt for password with validation (minimum length and special character)
  read -s -p "Enter password for $USERNAME (minimum 8 characters with at least one special character): " PASSWORD
  echo
  if [[ ${#PASSWORD} -lt 8 || ! $PASSWORD =~ [^a-zA-Z0-9] ]]; then
    echo "Error: Password must be at least 8 characters long and contain at least one special character" | tee -a $LOGFILE
    exit 1
  fi

  # Create user with sudo privileges (assuming sudo is installed)
  useradd -m -s /bin/bash "$USERNAME"
  echo "$USERNAME:$PASSWORD" | chpasswd
  usermod -aG sudo "$USERNAME"

  echo "[$(date)] Created Linux admin user $USERNAME with sudo privileges" >> $LOGFILE

  # Setup SSH key-based authentication (optional)
  read -p "Would you like to add an SSH public key for user '$USERNAME'? [y/N]: " ADD_SSH_KEY
  if [[ "$ADD_SSH_KEY" == "y" || "$ADD_SSH_KEY" == "Y" ]]; then
    read -p "Enter the SSH public key: " SSH_PUBLIC_KEY
    mkdir -p /home/$USERNAME/.ssh
    echo "$SSH_PUBLIC_KEY" >> /home/$USERNAME/.ssh/authorized_keys
    chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
    chmod 600 /home/$USERNAME/.ssh/authorized_keys

    echo "[$(date)] Added SSH public key for user $USERNAME" >> $LOGFILE
  fi
fi

echo "Setup complete for admin user '$USERNAME'."
echo "- To log in via SSH, use the following command: ssh $USERNAME@<hostname>"
echo "[$(date)] Completed proxmox_create_admin_user.sh" >> $LOGFILE