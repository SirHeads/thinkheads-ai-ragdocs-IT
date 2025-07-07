#!/bin/bash

# proxmox_create_admin_user.sh
# Creates a non-root Linux user with sudo and Proxmox admin privileges, sets up SSH key-based authentication
# Version: 1.1.0
# Author: [Your Name]
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

  # Create user with sudo privileges
  retry_command "useradd -m -s /bin/bash $USERNAME"
  echo "$USERNAME:$PASSWORD" | retry_command "chpasswd"
  retry_command "usermod -aG sudo $USERNAME"
  echo "[$(date)] Created Linux admin user $USERNAME with sudo privileges" >> "$LOGFILE"
}

# Configure SSH port
configure_ssh_port() {
  if [[ -z "$SSH_PORT" ]]; then
    read -p "Enter SSH port [$DEFAULT_SSH_PORT]: " SSH_PORT
    SSH_PORT=${SSH_PORT:-$DEFAULT_SSH_PORT}
  fi
  if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [[ "$SSH_PORT" -lt 1 || "$SSH_PORT" -gt 65535 ]]; then
    echo "Error: Invalid SSH port $SSH_PORT" | tee -a "$LOGFILE"
    exit 1
  fi

  if ! grep -q "^Port $SSH_PORT" /etc/ssh/sshd_config; then
    retry_command "sed -i 's/^#*Port .*/Port $SSH_PORT/' /etc/ssh/sshd_config"
    retry_command "systemctl restart sshd"
    echo "[$(date)] Configured SSH to use port $SSH_PORT" >> "$LOGFILE"
  else
    echo "SSH port $SSH_PORT already configured, skipping" | tee -a "$LOGFILE"
  fi
}

# Setup SSH key-based authentication
setup_ssh() {
  if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    mkdir -p "/home/$USERNAME/.ssh" || { echo "Error: Failed to create SSH directory"; exit 1; }
    echo "$SSH_PUBLIC_KEY" >> "/home/$USERNAME/.ssh/authorized_keys"
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
    chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
    echo "[$(date)] Added SSH public key for user $USERNAME" >> "$LOGFILE"
  else
    read -p "Add SSH public key for $USERNAME? [y/N]: " ADD_SSH_KEY
    if [[ "$ADD_SSH_KEY" == "y" || "$ADD_SSH_KEY" == "Y" ]]; then
      read -p "Enter SSH public key: " SSH_PUBLIC_KEY
      mkdir -p "/home/$USERNAME/.ssh" || { echo "Error: Failed to create SSH directory"; exit 1; }
      echo "$SSH_PUBLIC_KEY" >> "/home/$USERNAME/.ssh/authorized_keys"
      chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
      chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
      echo "[$(date)] Added SSH public key for user $USERNAME" >> "$LOGFILE"
    fi
  fi
}

# Main execution
check_root
prompt_for_username
create_user
configure_ssh_port
setup_ssh

echo "Setup complete for admin user '$USERNAME'."
echo "- SSH access: ssh $USERNAME@10.0.0.13 -p $SSH_PORT"
echo "- Proxmox VE web interface: https://10.0.0.13:8006"
echo "[$(date)] Completed proxmox_create_admin_user.sh" >> "$LOGFILE"