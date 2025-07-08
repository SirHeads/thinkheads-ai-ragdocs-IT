#!/bin/bash

# proxmox_configure_repos.sh
# Configures Proxmox VE repositories: disables production and Ceph repos, enables no-subscription repo
# Version: 1.1.0
# Author: Heads, Grok, Devstral
# Usage: ./proxmox_configure_repos.sh [--no-reboot]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }

# Parse command-line arguments
NO_REBOOT=0
while [[ $# -gt 0 ]]; do
  case $1 in
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

# Disable Proxmox VE production repository
disable_pve_production_repo() {
  local pve_repo_file="/etc/apt/sources.list.d/pve-enterprise.list"
  if [[ -f "$pve_repo_file" ]]; then
    sed -i 's/^deb/#deb/' "$pve_repo_file" || { echo "Error: Failed to disable Proxmox VE production repository"; exit 1; }
    echo "[$(date)] Disabled Proxmox VE production repository" >> "$LOGFILE"
  else
    echo "Warning: Proxmox VE production repository file not found, skipping" | tee -a "$LOGFILE"
  fi
}

# Disable Ceph repository
disable_ceph_repo() {
  local ceph_repo_file="/etc/apt/sources.list.d/ceph.list"
  if [[ -f "$ceph_repo_file" ]]; then
    sed -i 's/^deb/#deb/' "$ceph_repo_file" || { echo "Error: Failed to disable Ceph repository"; exit 1; }
    echo "[$(date)] Disabled Ceph repository" >> "$LOGFILE"
  else
    echo "Warning: Ceph repository file not found, skipping" | tee -a "$LOGFILE"
  fi
}

# Enable Proxmox VE no-subscription repository
enable_pve_no_subscription_repo() {
  local sources_list="/etc/apt/sources.list"
  local no_sub_repo="deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription"
  if ! grep -q "$no_sub_repo" "$sources_list"; then
    echo "$no_sub_repo" >> "$sources_list" || { echo "Error: Failed to add Proxmox VE no-subscription repository"; exit 1; }
    echo "[$(date)] Added Proxmox VE no-subscription repository" >> "$LOGFILE"
  else
    echo "Warning: Proxmox VE no-subscription repository already enabled, skipping" | tee -a "$LOGFILE"
  fi
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
disable_pve_production_repo
disable_ceph_repo
enable_pve_no_subscription_repo
update_system

echo "Proxmox VE repository configuration complete."
echo "- Disabled production and Ceph repositories."
echo "- Enabled no-subscription repository."
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
echo "[$(date)] Completed proxmox_configure_repos.sh" >> "$LOGFILE"