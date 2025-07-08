#!/bin/bash

# proxmox_setup_zfs_nfs_samba.sh
# Configures ZFS pools for NVMe drives, sets up NFS and Samba servers, and configures firewall
# Version: 1.5.0
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
  local ram_total_mb=$((ram_total / 1024 / 1024))
  local arc_size_mb

  # Prompt for ARC size
  echo "Total system RAM: $ram_total_mb MB"
  read -p "Enter ZFS ARC cache size in MB [$DEFAULT_ARC_SIZE_MB]: " arc_size_mb
  arc_size_mb=${arc_size_mb:-$DEFAULT_ARC_SIZE_MB}

  # Validate ARC size
  if [[ ! $arc_size_mb =~ ^[0-9]+$ || $arc_size_mb -le 0 || $arc_size_mb -gt $ram_total_mb ]]; then
    echo "Error: ARC size must be a positive number not exceeding total RAM ($ram_total_mb MB)" | tee -a "$LOGFILE"
    exit 1
  fi

  local arc_size_bytes=$((arc_size_mb * 1024 * 1024))
  echo "options zfs zfs_arc_max=$arc_size_bytes" > /etc/modprobe.d/zfs.conf || { echo "Error: Failed to configure ZFS ARC cache"; exit 1; }
  retry_command "update-initramfs -u"
  echo "[$(date)] Configured ZFS ARC cache to $arc_size_mb MB (~$((arc_size_mb / 1024))GB)" >> "$LOGFILE"
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

  # Configure Samba shares for ZFS datasets
  local smb_conf="/etc/samba/smb.conf"
  for dataset in models projects backups isos; do
    if ! grep -q "path = /$ZFS_4TB_POOL/$dataset" "$smb_conf" 2>/dev/null; then
      cat << EOF >> "$smb_conf"
[$dataset]
   path = /$ZFS_4TB_POOL/$dataset
   writable = yes
   browsable = yes
   valid users = $USERNAME
   create mask = 0644
   directory mask = 0755
EOF
      echo "[$(date)] Added Samba share for $dataset" >> "$LOGFILE"
    else
      echo "Warning: Samba share for $dataset already configured, skipping" | tee -a "$LOGFILE"
    fi
  done

  # Ensure Samba service is running
  if ! systemctl_is_active --quiet samba; then
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
      echo "Warning: Firewall rule for $service already exists, skipping" | tee -a "$LOGFILE"
    fi
  done
  retry_command "firewall-cmd --reload"
  echo "[$(date)] Applied firewall rules" >> "$LOGFILE"
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
select_nvme_drives
create_zfs_mirror
create_zfs_single
configure_zfs_arc_cache
install_nfs_server
install_samba_server
configure_firewall
update_system

echo "Setup complete for ZFS, NFS, and Samba."
echo "- NFS access: mount -t nfs 10.0.0.13:/$ZFS_4TB_POOL/<dataset> /mnt/<dataset>"
echo "- Samba access: \\\\10.0.0.13\\<dataset> (use '$USERNAME' and Samba password)"
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
echo "[$(date)] Completed proxmox_setup_zfs_nfs_samba.sh" >> "$LOGFILE"