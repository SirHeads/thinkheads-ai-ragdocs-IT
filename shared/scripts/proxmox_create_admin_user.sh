#!/bin/bash

# proxmox_create_admin_user.sh
# Creates a non-root Linux user with sudo and Proxmox admin privileges, sets up SSH key-based authentication
# Version: 1.4.2
# Author: Heads, Grok, Devstral
# Usage: ./proxmox_create_admin_user.sh [--username <username>] [--password <password>] [--ssh-key <key>] [--ssh-port <port>] [--no-reboot]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }

# Default values
DEFAULT_USERNAME="heads"
DEFAULT_SSH_PORT=2222
NO_REBOOT=0

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
    --no-reboot)
      NO_REBOOT=1
      shift
      ;;
    *)
      echo "Error: Unknown option $1" | tee -a "$LOGFILE"
      exit 1
      ;;
  esac
done

# Ensure sudo package and sudoers group exist
setup_sudo() {
  if ! check_package sudo; then
    retry_command "apt update"
    retry_command "apt install -y sudo"
    echo "[$(date)] Installed sudo package" >> "$LOGFILE"
  fi
  if ! getent group sudo &>/dev/null; then
    groupadd sudo || { echo "Error: Failed to create sudo group"; exit 1; }
    echo "[$(date)] Created sudo group" >> "$LOGFILE"
  fi
}

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
  usermod -aG sudo "$USERNAME" || { echo "Error: Failed to add user $USERNAME to sudo group"; exit 1; }

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
  local sshd_config="/etc/ssh/sshd_config"
  SSH_PORT=${SSH_PORT:-$DEFAULT_SSH_PORT}

  # Validate SSH port
  if [[ ! "$SSH_PORT" =~ ^[0-9]+$ || "$SSH_PORT" -lt 1 || "$SSH_PORT" -gt 65535 ]]; then
    echo "Error: SSH port must be a number between 1 and 65535" | tee -a "$LOGFILE"
    exit 1
  fi

  # Check if sshd_config exists
  if [[ ! -f "$sshd_config" ]]; then
    echo "Error: SSH configuration file $sshd_config not found" | tee -a "$LOGFILE"
    exit 1
  fi

  # Backup sshd_config
  cp "$sshd_config" "${sshd_config}.bak" || { echo "Error: Failed to backup $sshd_config"; exit 1; }
  echo "[$(date)] Backed up $sshd_config to ${sshd_config}.bak" >> "$LOGFILE"

  # Check for empty or invalid Port directive
  if ! grep -q "^Port [0-9]\+" "$sshd_config" && ! grep -q "^#Port [0-9]\+" "$sshd_config"; then
    echo "[$(date)] No valid Port directive found in $sshd_config, adding Port $SSH_PORT" >> "$LOGFILE"
    echo "Port $SSH_PORT" >> "$sshd_config" || { echo "Error: Failed to add Port $SSH_PORT to $sshd_config"; exit 1; }
  elif grep -q "^Port[[:space:]]*$" "$sshd_config" || grep -q "^Port[[:space:]]*[^0-9]" "$sshd_config"; then
    echo "[$(date)] Invalid or empty Port directive found in $sshd_config, setting to Port $SSH_PORT" >> "$LOGFILE"
    sed -i "s/^Port[[:space:]]*.*/Port $SSH_PORT/" "$sshd_config" || { echo "Error: Failed to fix invalid Port in $sshd_config"; exit 1; }
  elif grep -q "^Port " "$sshd_config"; then
    sed -i "s/^Port .*/Port $SSH_PORT/" "$sshd_config" || { echo "Error: Failed to set SSH port in $sshd_config"; exit 1; }
  elif grep -q "^#Port " "$sshd_config"; then
    sed -i "s/^#Port .*/Port $SSH_PORT/" "$sshd_config" || { echo "Error: Failed to set SSH port in $sshd_config"; exit 1; }
  fi
  echo "[$(date)] Configured SSH to listen on port $SSH_PORT" >> "$LOGFILE"

  # Test SSH configuration
  if ! /usr/sbin/sshd -t &>/tmp/sshd_test_output; then
    echo "Error: Invalid SSH configuration in $sshd_config" | tee -a "$LOGFILE"
    cat /tmp/sshd_test_output >> "$LOGFILE"
    echo "Restoring backup configuration" | tee -a "$LOGFILE"
    mv "${sshd_config}.bak" "$sshd_config" || { echo "Error: Failed to restore $sshd_config backup"; exit 1; }
    exit 1
  fi
  rm -f /tmp/sshd_test_output
  echo "[$(date)] SSH configuration test passed" >> "$LOGFILE"

  # Check if port is in use
  if command -v ss >/dev/null 2>&1; then
    if ss -tuln | grep -q ":$SSH_PORT "; then
      echo "Warning: Port $SSH_PORT is already in use by another process" | tee -a "$LOGFILE"
      echo "Please choose a different port or stop the conflicting service" | tee -a "$LOGFILE"
      exit 1
    fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -tuln | grep -q ":$SSH_PORT "; then
      echo "Warning: Port $SSH_PORT is already in use by another process" | tee -a "$LOGFILE"
      echo "Please choose a different port or stop the conflicting service" | tee -a "$LOGFILE"
      exit 1
    fi
  else
    echo "Error: Neither ss nor netstat is installed. Please install one to check port usage." | tee -a "$LOGFILE"
    exit 1
  fi

  # Restart SSH service
  retry_command "systemctl restart ssh" || { echo "Error: Failed to restart SSH service"; exit 1; }
  echo "[$(date)] Restarted SSH service" >> "$LOGFILE"
}

# Update and upgrade system
update_system() {
  retry_command "apt-get update"
  retry_command "apt-get upgrade -y"
  retry_command "proxmox-boot-tool refresh"
  retry_command "update-initramfs -u"
  echo "[$(date)] System updated, upgraded, and initramfs refreshed" >> "$LOGFILE"
}

# Main execution
check_root
setup_sudo
prompt_for_username
create_user
configure_ssh_port
update_system

echo "Setup complete for admin user '$USERNAME'."
echo "- SSH access: ssh $USERNAME@10.0.0.13 -p $SSH_PORT"
echo "- Proxmox VE web interface: https://10.0.0.13:8006"
if [[ $NO_REBOOT -eq 0 ]]; then
  read -t 60 -p "Reboot now? (y/n) [Timeout in 60s]: " REBOOT_CONFIRMATION
  if [[ -z "$REBOOT_CONFIRMATION" || "$REBOOT_CONFIRMATION" == "y" || "$REBOOT_CONFIRMATION" == "Y" ]]; then
    echo "Rebooting system..."
    reboot
  else
    echo "Please reboot manually to apply changes."
  fi
else
  echo "Reboot skipped due to --no-reboot flag. Please reboot manually."
fi
echo "[$(date)] Completed proxmox_create_admin_user.sh" >> "$LOGFILE"