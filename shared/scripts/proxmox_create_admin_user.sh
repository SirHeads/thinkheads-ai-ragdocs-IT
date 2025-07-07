#!/bin/bash

# proxmox_create_admin_user.sh
# Creates a non-root Linux user with sudo and Proxmox admin privileges, sets up SSH key-based authentication
# Version: 1.2.0
# Author: Heads, Grok, Devstral
# Usage: ./proxmox_create_admin_user.sh [--username <username>] [--password <password>] [--ssh-key <key>] [--ssh-port <port>]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }

# Default values
DEFAULT_USERNAME="heads"
DEFAULT_SSH_PORT=22

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --username)
      USERNAME="$2"
      shift 2
      ;;
    --password)
      PASSWORD="$2"
      shift 2
      ;;
    --ssh-key)
      SSH_PUBLIC_KEY="$2"
      shift 2
      ;;
    --ssh-port)
      SSH_PORT="$2"
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
    read -p "Enter new admin username [$DEFAULT_USERNAME]: " USERNAME
    USERNAME=${USERNAME:-$DEFAULT_USERNAME}
  fi
  if [[ -z "$USERNAME" ]]; then
    echo "Error: Username cannot be empty" | tee -a "$LOGFILE"
    exit 1
  fi
}

# Validate and create user
create_user() {
  if getent passwd "$USERNAME" &>/dev/null; then
    echo "Warning: User $USERNAME already exists, skipping user creation" | tee -a "$LOGFILE"
    return 0
  fi

  # Prompt for password if not provided
  if [[ -z "$PASSWORD" ]]; then
    read -s -p "Enter password for $USERNAME (min 8 chars, 1 special char): " PASSWORD
    echo
  fi
  if [[ ${#PASSWORD} -lt 8 || ! $PASSWORD =~ [^a-zA-Z0-9] ]]; then
    echo "Error: Password must be at least 8 characters long and contain at least one special character" | tee -a "$LOGFILE"
    exit 1
  fi

  # Create user with home directory and set password
  useradd -m -s /bin/bash "$USERNAME" || { echo "Error: Failed to create user $USERNAME"; exit 1; }
  echo "$USERNAME:$PASSWORD" | chpasswd || { echo "Error: Failed to set password for user $USERNAME"; exit 1; }

  # Add user to sudo group
  if ! grep -q " $USERNAME" /etc/sudoers; then
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers || { echo "Error: Failed to add user $USERNAME to sudo group"; exit 1; }
  fi

  # Set up SSH key (if provided)
  if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    mkdir -p "/home/$USERNAME/.ssh"
    echo "$SSH_PUBLIC_KEY" > "/home/$USERNAME/.ssh/authorized_keys" || { echo "Error: Failed to add SSH key for user $USERNAME"; exit 1; }
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh" || { echo "Error: Failed to set ownership of .ssh directory for user $USERNAME"; exit 1; }
    chmod 700 "/home/$USERNAME/.ssh"
    chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
  fi

  # Create Proxmox admin user
  if ! pveum user add "$USERNAME@pam" &>/dev/null; then
    echo "Error: Failed to create Proxmox user $USERNAME@pam" | tee -a "$LOGFILE"
    exit 1
  fi

  # Grant Proxmox admin privileges
  if ! pveum acl modify / -user "$USERNAME@pam" -role Administrator &>/dev/null; then
    echo "Error: Failed to grant Proxmox admin role to user $USERNAME@pam" | tee -a "$LOGFILE"
    exit 1
  fi

  echo "[$(date)] Created and configured Proxmox admin user '$USERNAME'" >> "$LOGFILE"
}

# Configure SSH port if different from default
configure_ssh_port() {
  if [[ "$SSH_PORT" -ne $DEFAULT_SSH_PORT ]]; then
    sed -i "s/^Port $DEFAULT_SSH_PORT/Port $SSH_PORT/" /etc/ssh/sshd_config || { echo "Error: Failed to set SSH port"; exit 1; }
    systemctl restart sshd || { echo "Error: Failed to restart SSH service"; exit 1; }
    echo "[$(date)] Configured SSH to listen on port $SSH_PORT" >> "$LOGFILE"
  fi
}

# Main execution
check_root
prompt_for_username
create_user
configure_ssh_port

echo "Setup complete for admin user '$USERNAME'."
echo "- SSH access: ssh $USERNAME@10.0.0.13 -p $SSH_PORT"
echo "- Proxmox VE web interface: https://10.0.0.13:8006"
echo "[$(date)] Completed proxmox_create_admin_user.sh" >> "$LOGFILE"