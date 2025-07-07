#!/bin/bash

# proxmox_setup_zfs_nfs_samba.sh
# Configures ZFS pools for NVMe drives, sets up NFS and Samba servers, and configures firewall
# Version: 1.1.0
# Author: [Your Name]
# Usage: ./proxmox_setup_zfs_nfs_samba.sh [--username <username>]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }

# Constants
ZFS_2TB_POOL="tank"
ZFS_4TB_POOL="shared"
DEFAULT_USERNAME="heads"
NFS_SUBNET="10.0.0.0/24"
EXPORTS_FILE="/etc/exports"

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

# Identify NVMe drives
identify_nvme_drives() {
  NVME0=$(nvme list | grep -m1 "Samsung 990 EVO Plus 2TB" | awk '{print $1}')
  NVME1=$(nvme list | grep -m2 "Samsung 990 EVO Plus 2TB" | tail -n1 | awk '{print $1}')
  NVME4TB=$(nvme list | grep "Samsung 990 EVO Plus 4TB" | awk '{print $1}')

  if [[ -z "$NVME0" || -z "$NVME1" || -z "$NVME4TB" ]]; then
    echo "Error: Could not identify NVMe drives. Ensure drives are connected and visible via 'nvme list'" | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date)] Identified NVMe drives: $NVME0, $NVME1 (2TB), $NVME4TB (4TB)" >> "$LOGFILE"
}

# Create ZFS mirror for 2TB NVMe drives
create_zfs_mirror() {
  if ! zpool list | grep -q "$ZFS_2TB_POOL"; then
    retry_command "zpool create -f -o ashift=12 $ZFS_2TB_POOL mirror $NVME0 $NVME1"
    zfs create "$ZFS_2TB_POOL/vms" || { echo "Error: Failed to create dataset $ZFS_2TB_POOL/vms"; exit 1; }
    zfs set compression=lz4 "$ZFS_2TB_POOL/vms" || { echo "Error: Failed to set compression on $ZFS_2TB_POOL/vms"; exit 1; }
    zfs set recordsize=128k "$ZFS_2TB_POOL/vms" || { echo "Error: Failed to set recordsize on $ZFS_2TB_POOL/vms"; exit 1; }
    retry_command "pvesm add zfspool tank-vms -pool $ZFS_2TB_POOL/vms -content images,rootdir"
    echo "[$(date)] Created ZFS mirror pool '$ZFS_2TB_POOL' for VMs/containers" >> "$LOGFILE"
  else
    echo "Warning: ZFS pool '$ZFS_2TB_POOL' already exists, skipping" | tee -a "$LOGFILE"
  fi
}

# Create ZFS single drive for 4TB NVMe
create_zfs_single() {
  if ! zpool list | grep -q "$ZFS_4TB_POOL"; then
    retry_command "zpool create -f -o ashift=12 $ZFS_4TB_POOL $NVME4TB"
    for dataset in models projects backups isos; do
      zfs create "$ZFS_4TB_POOL/$dataset" || { echo "Error: Failed to create dataset $ZFS_4TB_POOL/$dataset"; exit 1; }
      zfs set compression=lz4 "$ZFS_4TB_POOL/$dataset" || { echo "Error: Failed to set compression on $ZFS_4TB_POOL/$dataset"; exit 1; }
      zfs set recordsize=1M "$ZFS_4TB_POOL/$dataset" || { echo "Error: Failed to set recordsize on $ZFS_4TB_POOL/$dataset"; exit 1; }
    done
    retry_command "pvesm add dir shared-backups -path /$ZFS_4TB_POOL lados -content backup"
    retry_command "pvesm add dir shared-isos -path /$ZFS_4TB_POOL/isos -content iso"
    echo "[$(date)] Created ZFS pool '$ZFS_4TB_POOL' with datasets" >> "$LOGFILE"
  else
    echo "Warning: ZFS pool '$ZFS_4TB_POOL' already exists, skipping" | tee -a "$LOGFILE"
  fi
}

# Configure ZFS ARC cache
configure_zfs_arc_cache() {
  local ram_total=$(free -b | awk '/Mem:/ {print $2}')
  local arc_max=$((ram_total / 3))  # Limit to ~1/3 of total RAM
  if ! grep -q "zfs_arc_max" /etc/modprobe.d/zfs.conf 2>/dev/null; then
    echo "options zfs zfs_arc_max=$arc_max" >> /etc/modprobe.d/zfs.conf || { echo "Error: Failed to configure ZFS ARC cache"; exit 1; }
    retry_command "update-initramfs -u"
    echo "[$(date)] Configured ZFS ARC cache to ~$(($arc_max / 1024 / 1024 / 1024))GB" >> "$LOGFILE"
  else
    echo "Warning: ZFS ARC cache already configured, skipping" | tee -a "$LOGFILE"
  fi
}

# Install and configure NFS server
install_nfs_server() {
  if ! check_package nfs-kernel-server; then
    retry_command "apt update"
    retry_command "apt install -y nfs-kernel-server"
    echo "[$(date)] Installed nfs-kernel-server" >> "$LOGFILE"
  fi

  if ! grep -q "/$ZFS_4TB_POOL/.*$NFS_SUBNET" "$EXPORTS_FILE"; then
    for dataset in models projects backups isos; do
      echo "/$ZFS_4TB_POOL/$dataset $NFS_SUBNET(rw,sync,no_subtree_check,no_root_squash)" >> "$EXPORTS_FILE" || { echo "Error: Failed to update $EXPORTS_FILE for $dataset"; exit 1; }
    done
    retry_command "exportfs -ra"
    echo "[$(date)] Added NFS exports for $ZFS_4TB_POOL datasets" >> "$LOGFILE"
  else
    retry_command "exportfs -ra"
    echo "[$(date)] Refreshed NFS exports for $ZFS_4TB_POOL datasets" >> "$LOGFILE"
  fi
}

# Install and configure Samba server
install_samba_server() {
  if ! check_package samba; then
    retry_command "apt install -y samba"
    echo "[$(date)] Installed Samba" >> "$LOGFILE"
  fi

  if [[ -z "$USERNAME" ]]; then
    read -p "Enter username for Samba credentials [$DEFAULT_USERNAME]: " USERNAME
    USERNAME=${USERNAME:-$DEFAULT_USERNAME}
  fi
  if ! smbpasswd -a "$USERNAME" &>/dev/null; then
    echo "Error: Failed to set Samba password for user $USERNAME" | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date)] Set Samba password for user $USERNAME" >> "$LOGFILE"
}

# Configure firewall rules
configure_firewall() {
  if ! check_package firewalld; then
    retry_command "apt install -y firewalld"
    echo "[$(date)] Installed firewalld" >> "$LOGFILE"
  fi
  if ! systemctl is-active --quiet firewalld; then
    retry_command "systemctl enable --now firewalld"
    echo "[$(date)] Enabled and started firewalld" >> "$LOGFILE"
  fi
  for service in nfs samba; do
    if ! firewall-cmd --permanent --query-service="$service" &>/dev/null; then
      retry_command "firewall-cmd --permanent --add-service=$service"
      echo "[$(date)] Added firewall rule for $service (ports: nfs=2049,111; samba=137-139,445)" >> "$LOGFILE"
    else
      echo "Firewall rule for $service already exists, skipping" | tee -a "$LOGFILE"
    fi
  done
  retry_command "firewall-cmd --reload"
  echo "[$(date)] Applied firewall rules" >> "$LOGFILE"
}

# Main execution
check_root
identify_nvme_drives
create_zfs_mirror
create_zfs_single
configure_zfs_arc_cache
install_nfs_server
install_samba_server
configure_firewall

echo "Setup complete for ZFS, NFS, and Samba."
echo "- NFS access: mount -t nfs 10.0.0.13:/$ZFS_4TB_POOL/<dataset> /mnt/<dataset>"
echo "- Samba access: \\\\10.0.0.13\\<dataset> (use '$USERNAME' and Samba password)"
echo "- Proxmox VE web interface: https://10.0.0.13:8006"
echo "[$(date)] Completed proxmox_setup_zfs_nfs_samba.sh" >> "$LOGFILE"