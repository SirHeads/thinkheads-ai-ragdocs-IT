#!/bin/bash

# proxmox_setup_zfs_nfs_samba.sh
# Configures ZFS mirror for 2x 2TB NVMe, creates a single drive pool for 4TB NVMe with datasets,
# installs and configures NFS/Samba server, and sets up firewall rules.

set -e
LOGFILE="/var/log/proxmox_setup.log"
echo "[$(date)] Starting proxmox_setup_zfs_nfs_samba.sh" >> $LOGFILE

# Function to check if script is run as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run with sudo" | tee -a $LOGFILE
    exit 1
  fi
}

# Identify NVMe drives
identify_nvme_drives() {
  NVME0=$(nvme list | grep -m1 "Samsung 990 EVO Plus 2TB" | awk '{print $1}')
  NVME1=$(nvme list | grep -m2 "Samsung 990 EVO Plus 2TB" | tail -n1 | awk '{print $1}')
  NVME4TB=$(nvme list | grep "Samsung 990 EVO Plus 4TB" | awk '{print $1}')

  if [[ -z "$NVME0" || -z "$NVME1" || -z "$NVME4TB" ]]; then
    echo "Error: Could not identify NVMe drives" | tee -a $LOGFILE
    exit 1
  fi

  echo "[$(date)] Identified NVMe drives: $NVME0, $NVME1 (2TB), $NVME4TB (4TB)" >> $LOGFILE
}

# Create ZFS single drive for 4TB NVMe (shared)
create_zfs_pool() {
  if ! zpool list | grep -q "shared"; then
    zpool create -f -o ashift=12 shared "$NVME4TB"
    zfs create shared/models
    zfs create shared/projects
    zfs create shared/backups
    zfs create shared/isos
    zfs set compression=lz4 shared/models shared/projects shared/backups shared/isos
    zfs set recordsize=1M shared/models shared/projects shared/backups shared/isos
    pvesm add dir shared-backups -path /shared/backups -content backup
    pvesm add dir shared-isos -path /shared/isos -content iso
    echo "[$(date)] Created ZFS pool 'shared' with datasets" >> $LOGFILE
  else
    echo "Warning: ZFS pool 'shared' already exists, skipping" | tee -a $LOGFILE
  fi
}

# Configure ZFS ARC cache (limit to ~32GB of 96GB RAM)
configure_zfs_arc_cache() {
  if ! grep -q "zfs_arc_max" /etc/modprobe.d/zfs.conf 2>/dev/null; then
    echo "options zfs zfs_arc_max=34359738368" >> /etc/modprobe.d/zfs.conf
    update-initramfs -u
    echo "[$(date)] Configured ZFS ARC cache to ~32GB" >> $LOGFILE
  else
    echo "Warning: ZFS ARC cache already configured, skipping" | tee -a $LOGFILE
  fi
}

# Install and configure NFS server
install_nfs_server() {
  if ! dpkg -l | grep -q nfs-kernel-server; then
    apt update
    apt install -y nfs-kernel-server
    echo "[$(date)] Installed nfs-kernel-server" >> $LOGFILE
  else
    echo "Warning: nfs-kernel-server already installed, skipping" | tee -a $LOGFILE
  fi

  EXPORTS_FILE="/etc/exports"
  if grep -q "/shared/.*10.0.0.0/24" "$EXPORTS_FILE"; then
    exportfs -ra
    if [[ $? -eq 0 ]]; then
      echo "[$(date)] Refreshed NFS exports for shared datasets" >> $LOGFILE
    else
      echo "Error: Failed to refresh NFS exports" | tee -a $LOGFILE
      exit 1
    fi
  else
    echo "/shared/models 10.0.0.0/24(rw,sync,no_subtree_check)" >> /etc/exports
    echo "/shared/projects 10.0.0.0/24(rw,sync,no_subtree_check)" >> /etc/exports
    echo "/shared/backups 10.0.0.0/24(rw,sync,no_subtree_check)" >> /etc/exports
    echo "/shared/isos 10.0.0.0/24(rw,sync,no_subtree_check)" >> /etc/exports
    exportfs -ra
    if [[ $? -eq 0 ]]; then
      echo "[$(date)] Added NFS exports for shared datasets" >> $LOGFILE
    else
      echo "Error: Failed to add NFS exports" | tee -a $LOGFILE
      exit 1
    fi
  fi
}

# Install and configure Samba server (optional)
install_samba_server() {
  if ! dpkg -l | grep -q samba; then
    apt install -y samba
    echo "[$(date)] Installed Samba" >> $LOGFILE
  else
    echo "Warning: Samba already installed, skipping" | tee -a $LOGFILE
  fi

  # Prompt for the username to add Samba credentials (optional)
  read -p "Enter username for Samba credentials [default: heads]: " USERNAME
  USERNAME=${USERNAME:-heads}
  if ! smbpasswd -a "$USERNAME" &>/dev/null; then
    echo "Error: Failed to set Samba password for user $USERNAME" | tee -a $LOGFILE
    exit 1
  else
    echo "[$(date)] Set Samba password for user $USERNAME" >> $LOGFILE
  fi
}

# Configure firewalld rules for NFS and Samba (optional)
configure_firewall() {
  if ! firewall-cmd --permanent --query-service=nfs; then
    firewall-cmd --permanent --add-service=nfs
    firewall-cmd --permanent --add-service=samba
    firewall-cmd --reload
    echo "[$(date)] Configured firewalld rules for NFS and Samba" >> $LOGFILE
  fi
}

# Main script execution
check_root
identify_nvme_drives
create_zfs_pool
configure_zfs_arc_cache
install_nfs_server
install_samba_server
configure_firewall

echo "[$(date)] Completed proxmox_setup_zfs_nfs_samba.sh" >> $LOGFILE