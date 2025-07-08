#!/bin/bash

# proxmox_setup_zfs_nfs_samba.sh
# Configures ZFS pools for NVMe drives, sets up NFS and Samba servers, and configures firewall
# Version: 1.5.2
# Author: Heads, Grok, Devstral
# Usage: ./proxmox_setup_zfs_nfs_samba.sh [--username <username>] [--no-reboot]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }

# Constants
ZFS_2TB_POOL="quickOS"
ZFS_4TB_POOL="fastData"
DEFAULT_USERNAME="heads"
NFS_SUBNET="10.0.0.0/24"
EXPORTS_FILE="/etc/exports"
NO_REBOOT=0
DEFAULT_ARC_SIZE_MB=9000  # Default ARC size in MB (~9GB)

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --username)
      USERNAME="$2"
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

# Interactively select NVMe drives
select_nvme_drives() {
  # List NVMe drives and their sizes
  mapfile -t NVME_DRIVES < <(lsblk -d -o NAME,SIZE,MODEL -b | grep '^nvme' | awk '{print $1 " " $2 " " $3}')
  
  if [[ ${#NVME_DRIVES[@]} -lt 3 ]]; then
    echo "Error: At least three NVMe drives are required. Found ${#NVME_DRIVES[@]}." | tee -a "$LOGFILE"
    exit 1
  fi

  echo "Available NVMe drives:"
  for i in "${!NVME_DRIVES[@]}"; do
    name=$(echo "${NVME_DRIVES[$i]}" | awk '{print $1}')
    size=$(echo "${NVME_DRIVES[$i]}" | awk '{print $2}')
    model=$(echo "${NVME_DRIVES[$i]}" | awk '{print $3}')
    size_gb=$((size / 1024 / 1024 / 1024))
    echo "[$i] /dev/$name ($size_gb GB, $model)"
  done

  # Select two drives for mirror (quickOS)
  NVME_2TB=()
  echo "Select two drives for mirrored ZFS pool '$ZFS_2TB_POOL' (enter two numbers, space-separated):"
  read -r drive1 drive2
  if [[ -z "$drive1" || -z "$drive2" || "$drive1" == "$drive2" || $drive1 -ge ${#NVME_DRIVES[@]} || $drive2 -ge ${#NVME_DRIVES[@]} ]]; then
    echo "Error: Invalid selection for mirrored drives" | tee -a "$LOGFILE"
    exit 1
  fi
  NVME_2TB+=("/dev/$(echo "${NVME_DRIVES[$drive1]}" | awk '{print $1}')")
  NVME_2TB+=("/dev/$(echo "${NVME_DRIVES[$drive2]}" | awk '{print $1}')")

  # Select one drive for single pool (fastData)
  echo "Select one drive for single ZFS pool '$ZFS_4TB_POOL' (enter one number):"
  read -r drive3
  if [[ -z "$drive3" || $drive3 -ge ${#NVME_DRIVES[@]} || $drive3 == "$drive1" || $drive3 == "$drive2" ]]; then
    echo "Error: Invalid selection for single drive" | tee -a "$LOGFILE"
    exit 1
  fi
  NVME_4TB="/dev/$(echo "${NVME_DRIVES[$drive3]}" | awk '{print $1}')"

  echo "[$(date)] Selected NVMe drives: ${NVME_2TB[0]}, ${NVME_2TB[1]} for $ZFS_2TB_POOL; $NVME_4TB for $ZFS_4TB_POOL" >> "$LOGFILE"
}

# Create ZFS mirror for selected NVMe drives
create_zfs_mirror() {
  if ! zpool list | grep -q "$ZFS_2TB_POOL"; then
    retry_command "zpool create -f -o ashift=12 $ZFS_2TB_POOL mirror ${NVME_2TB[0]} ${NVME_2TB[1]}"
    zfs create "$ZFS_2TB_POOL/vms" || { echo "Error: Failed to create dataset $ZFS_2TB_POOL/vms"; exit 1; }
    zfs set compression=lz4 "$ZFS_2TB_POOL/vms" || { echo "Error: Failed to set compression on $ZFS_2TB_POOL/vms"; exit 1; }
    zfs set recordsize=128k "$ZFS_2TB_POOL/vms" || { echo "Error: Failed to set recordsize on $ZFS_2TB_POOL/vms"; exit 1; }
    retry_command "pvesm add zfspool tank-vms -pool $ZFS_2TB_POOL/vms -content images,rootdir"
    echo "[$(date)] Created ZFS mirror pool '$ZFS_2TB_POOL' for VMs/containers" >> "$LOGFILE"
  else
    echo "Warning: ZFS pool '$ZFS_2TB_POOL' already exists, skipping" | tee -a "$LOGFILE"
  fi
}

# Create ZFS single drive for selected NVMe
create_zfs_single() {
  if ! zpool list | grep -q "$ZFS_4TB_POOL"; then
    retry_command "zpool create -f -o ashift=12 $ZFS_4TB_POOL $NVME_4TB"
    for dataset in models projects backups isos; do
      zfs create "$ZFS_4TB_POOL/$dataset" || { echo