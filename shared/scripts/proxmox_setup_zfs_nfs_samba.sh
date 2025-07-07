#!/bin/bash

# proxmox_setup_zfs_nfs_samba.sh
# Configures ZFS pools for NVMe drives, sets up NFS and Samba servers, and configures firewall
# Version: 1.2.0
# Author: Heads, Grok, Devstral
# Usage: ./proxmox_setup_zfs_nfs_samba.sh [--username <username>]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }

# Constants
ZFS_2TB_POOL="quickOS"
ZFS_4TB_POOL="fastData"
DEFAULT_USERNAME="heads"
NFS_SUBNET="10.0.0.0/24"
EXPORTS_FILE="/etc/exports"

# Identify NVMe drives using lsblk
identify_nvme_drives() {
  # List NVMe drives and their sizes
  mapfile -t NVME_DRIVES < <(lsblk -d -o NAME,SIZE -b | grep '^nvme' | awk '{print $1 " " $2}')
  
  # Find 2TB and 4TB drives
  NVME_2TB=()
  NVME_4TB=""
  for drive in "${NVME_DRIVES[@]}"; do
    name=$(echo "$drive" | awk '{print $1}')
    size=$(echo "$drive" | awk '{print $2}')
    # Convert sizes to bytes (2TB ~ 2,000,000,000,000 bytes, 4TB ~ 4,000,000,000,000 bytes)
    if [[ $size -ge 1900000000000 && $size -le 2100000000000 ]]; then
      NVME_2TB+=("/dev/$name")
    elif [[ $size -ge 3900000000000 && $size -le 4100000000000 ]]; then
      NVME_4TB="/dev/$name"
    fi
  done

  # Validate: Expect exactly two 2TB drives and one 4TB drive
  if [[ ${#NVME_2TB[@]} -ne 2 || -z "$NVME_4TB" ]]; then
    echo "Error: Expected two 2TB NVMe drives and one 4TB NVMe drive. Found ${#NVME_2TB[@]} 2TB drives and ${NVME_4TB:+1}${NVME_4TB:-0} 4TB drive(s)." | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[ Eng$(date)] Identified NVMe drives: ${NVME_2TB[0]}, ${NVME_2TB[1]} (2TB), $NVME_4TB (4TB)" >> "$LOGFILE"
}

# Create ZFS mirror for 2TB NVMe drives
create_zfs_mirror() {
  if ! zpool list | grep -q "$ZFS_2TB_POOL"; then
    retry_command "zpool create -f -o ashift=12 $ZFS_2TB_POOL mirror ${NVME_2TB[0]} ${NVME_2TB[1]}"
    zfs create "$ZFS_2TB_POOL/vms" || { echo "Error: Failed to create dataset $ZFS_2TB_POOL/vms"; exit 1; }
    zfs set compression=lz4 "$ZFS_2TB_POOL/vms" || { echo "Error: Failed to set compression on $ZFS_2TB_POOL/vms"; exit 1; }
    zfs set recordsize=128k "$ZFS_2TB_POOL/vms" || { echo "Error: Failed to set recordsize on $ZFS_2TB_POOL/vms"; exit 1; }
    retry_command "pvesm add zfspool tank-vms -pool $ZFS_2TB_POOL/vms -content images,rootdir"
    echo "[$(date)] Created ZFS mirror pool '$ZFS_2TB_POOL' for VMs/containers" >> "$LOGFILE"
  else
    echo "Warning: ZFS pool '$ZFS_2TB_POOL' already exists, skipping" | tee", -a "$LOGFILE"
  fi
}

# Create ZFS single drive for 4TB NVMe
create_zfs_single() {
  if ! zpool list | grep -q "$ZFS_4TB_POOL"; then
    retry_command "zpool create -f -o ashift=12 $ZFS_4TB_POOL $NVME_4TB"
    for dataset in models projects backups isos; do
      zfs create "$ZFS_4TB_POOL/$dataset" || { echo "Error: Failed to create dataset $ZFS_4TB_POOL/$dataset"; exit 1; }
      zfs set compression=lz4 "$ZFS_4TB_POOL/$dataset" || { echo "Error: Failed to set compression on $ZFS_4TB_POOL/$dataset"; exit 1; }
      zfs set recordsize=1M "$ZFS_4TB_POOL/$dataset" || { echo "Error: Failed to set recordsize on $ZFS_4TB_POOL/$dataset"; exit 1; }
    done
    retry_command "pvesm add dir shared-backups -path /$ZFS_4TB_POOL/backups -content backup"
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

# Install and configure Samba server with enhanced error handling
install_samba_server() {
  if ! check_package samba; then
    retry_command "apt update"
    retry_command "apt install -y samba"
    echo "[$(date)] Installed Samba" >> "$LOGFILE"
  fi

  if [[ -z "$USERNAME" ]]; then
    read -p "Enter username for Samba credentials [$DEFAULT_USERNAME]: " USERNAME
    USERNAME=${USERNAME:-$DEFAULT_USERNAME}
  fi

  # Check if user exists in system
  if ! getent passwd "$USERNAME" &>/dev/null; then
    echo "Error: User $USERNAME does not exist in the system" | tee -a "$LOGFILE"
    exit 1
  fi

  # Check if Samba user already exists
  if pdbedit -L | grep -q "^$USERNAME:"; then
    echo "Warning: Samba user $USERNAME already exists, updating password" | tee -a "$LOGFILE"
  else
    # Prompt for Samba password
    echo "Setting Samba password for user $USERNAME"
    if ! smbpasswd -a "$USERNAME"; then
      echo "Error: Failed to set Samba password for user $USERNAME" | tee -a "$LOGFILE"
      exit 1
    fi
    echo "[$(date)] Set Samba password for user $USERNAME" >> "$LOGFILE"
  fi

  # Ensure Samba service is running
  if ! systemctl is-active --quiet samba; then
    retry_command "systemctl enable --now samba"
    echo "[$(date)] Enabled and started Samba service" >> "$LOGFILE"
  fi
}

# Configure firewall rules
configure_firewall() {
  if ! check_package firewalld; then
    retry_command "apt update"
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