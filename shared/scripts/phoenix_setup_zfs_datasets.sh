#!/bin/bash

# phoenix_setup_zfs_datasets.sh
# Configures ZFS datasets, snapshots, NFS/Samba shares, firewall, and Proxmox storage.
# Version: 1.0.4
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_zfs_datasets.sh
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup
# Run after phoenix_setup_zfs_pools.sh

# Exit on any error
set -e

# Source common functions
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }

# Constants
DEFAULT_SUBNET="10.0.0.0/24" # Default network subnet
PROXMOX_NFS_SERVER="10.0.0.13" # Host IP for NFS server

# Ensure script runs as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root." | tee -a "$LOGFILE"
        exit 1
    fi
}

# Initialize logging
setup_logging() {
    exec 1> >(tee -a "$LOGFILE")
    exec 2>&1
    echo "Starting ZFS dataset and service setup at $(date)" | tee -a "$LOGFILE"
}

# Check if pools exist
check_pools() {
    echo "Checking for required ZFS pools..." | tee -a "$LOGFILE"
    for pool in quickOS fastData; do
        if ! zpool status "$pool" >/dev/null 2>&1; then
            echo "Error: ZFS pool $pool does not exist. Run phoenix_setup_zfs_pools.sh first." | tee -a "$LOGFILE"
            exit 1
        fi
    done
}

# Prompt for SMB user and password
prompt_for_smb_credentials() {
    echo "Enter Samba username (e.g., proxmox):" | tee -a "$LOGFILE"
    read -r SMB_USER
    if [[ -z "$SMB_USER" ]]; then
        echo "Error: Samba username cannot be empty" | tee -a "$LOGFILE"
        exit 1
    fi
    echo "Enter Samba password (input hidden):" | tee -a "$LOGFILE"
    read -r -s SMB_PASSWORD
    if [[ -z "$SMB_PASSWORD" ]]; then
        echo "Error: Samba password cannot be empty" | tee -a "$LOGFILE"
        exit 1
    fi
}

# Prompt for network subnet
prompt_for_subnet() {
    echo "Enter network subnet for NFS/Samba (default: $DEFAULT_SUBNET):" | tee -a "$LOGFILE"
    read -r NFS_SUBNET
    NFS_SUBNET=${NFS_SUBNET:-$DEFAULT_SUBNET}
    if ! [[ "$NFS_SUBNET" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "Error: Invalid subnet format: $NFS_SUBNET" | tee -a "$LOGFILE"
        exit 1
    fi
}

# Install required packages
install_prerequisites() {
    echo "Installing prerequisites..." | tee -a "$LOGFILE"
    apt-get update
    apt-get install -y zfsutils-linux nfs-kernel-server nfs-common samba smbclient ufw zfs-auto-snapshot || {
        echo "Failed to install prerequisites" | tee -a "$LOGFILE"
        exit 1
    }
}

# Configure firewall for SSH, NFS, Samba, and Proxmox web UI
configure_firewall() {
    echo "Configuring firewall for SSH, NFS, Samba, and Proxmox web UI..." | tee -a "$LOGFILE"
    ufw allow from "$NFS_SUBNET" to any port 22 proto tcp # SSH
    ufw allow from "$NFS_SUBNET" to any port 111 proto tcp # RPC
    ufw allow from "$NFS_SUBNET" to any port 2049 proto tcp # NFS
    ufw allow from 127.0.0.1 to any port 2049 proto tcp # NFS localhost
    ufw allow from "$NFS_SUBNET" to any port 137 proto udp # Samba NetBIOS
    ufw allow from "$NFS_SUBNET" to any port 138 proto udp # Samba NetBIOS
    ufw allow from "$NFS_SUBNET" to any port 139 proto tcp # Samba SMB
    ufw allow from "$NFS_SUBNET" to any port 445 proto tcp # Samba SMB
    ufw allow from "$NFS_SUBNET" to any port 8006 proto tcp # Proxmox web UI
    ufw enable || { echo "Failed to enable firewall" | tee -a "$LOGFILE"; exit 1; }
    echo "Firewall configured" | tee -a "$LOGFILE"
}

# Check network connectivity
check_network() {
    echo "Checking network connectivity..." | tee -a "$LOGFILE"
    # Check localhost resolution
    if ! ping -c 1 localhost >/dev/null 2>&1; then
        echo "Warning: Hostname 'localhost' does not resolve to 127.0.0.1. Check /etc/hosts." | tee -a "$LOGFILE"
    fi
    # Check if PROXMOX_NFS_SERVER is reachable
    if ! ping -c 1 "$PROXMOX_NFS_SERVER" >/dev/null 2>&1; then
        echo "Error: NFS server IP $PROXMOX_NFS_SERVER is not reachable." | tee -a "$LOGFILE"
        exit 1
    fi
    # Check if an interface has an IP in NFS_SUBNET
    if ! ip addr show | grep -q "inet.*$NFS_SUBNET"; then
        echo "Warning: Network subnet $NFS_SUBNET not detected on any interface. NFS/Samba may not work as expected." | tee -a "$LOGFILE"
    else
        echo "Network subnet $NFS_SUBNET detected on interface." | tee -a "$LOGFILE"
    fi
    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo "Warning: No internet connectivity detected. Package installation may fail." | tee -a "$LOGFILE"
    fi
}

# Configure Samba user and password
configure_samba_user() {
    echo "Configuring Samba user $SMB_USER..." | tee -a "$LOGFILE"
    if ! id "$SMB_USER" > /dev/null 2>&1; then
        useradd -M -s /sbin/nologin "$SMB_USER" || {
            echo "Failed to create Samba user $SMB_USER" | tee -a "$LOGFILE"
            exit 1
        }
    fi
    echo -e "$SMB_PASSWORD\n$SMB_PASSWORD" | smbpasswd -a "$SMB_USER" || {
        echo "Failed to set Samba password for $SMB_USER" | tee -a "$LOGFILE"
        exit 1
    }
    smbpasswd -e "$SMB_USER" || {
        echo "Failed to enable Samba user $SMB_USER" | tee -a "$LOGFILE"
        exit 1
    }
}

# Create ZFS datasets on quickOS
create_quickos_datasets() {
    echo "Creating quickOS datasets..." | tee -a "$LOGFILE"
    zfs create -o recordsize=128K -o compression=lz4 -o sync=standard -o quota=800G quickOS/disks-vm || {
        echo "Failed to create disks-vm dataset" | tee -a "$LOGFILE"
        exit 1
    }
    zfs create -o recordsize=16K -o compression=lz4 -o sync=standard -o quota=600G quickOS/disks-lxc || {
        echo "Failed to create disks-lxc dataset" | tee -a "$LOGFILE"
        exit 1
    }
    zfs create -o recordsize=128K -o compression=lz4 -o sync=standard -o quota=400G quickOS/shared-prod-data || {
        echo "Failed to create shared-prod-data dataset" | tee -a "$LOGFILE"
        exit 1
    }
    zfs create -o recordsize=16K -o compression=lz4 -o sync=always -o quota=100G quickOS/shared-prod-data-sync || {
        echo "Failed to create shared-prod-data-sync dataset" | tee -a "$LOGFILE"
        exit 1
    }
}

# Create ZFS datasets on fastData
create_fastdata_datasets() {
    echo "Creating fastData datasets..." | tee -a "$LOGFILE"
    zfs create -o recordsize=128K -o compression=lz4 -o sync=standard -o quota=500G fastData/shared-test-data || {
        echo "Failed to create shared-test-data dataset" | tee -a "$LOGFILE"
        exit 1
    }
    zfs create -o recordsize=16K -o compression=lz4 -o sync=always -o quota=100G fastData/shared-test-data-sync || {
        echo "Failed to create shared-test-data-sync dataset" | tee -a "$LOGFILE"
        exit 1
    }
    zfs create -o recordsize=1M -o compression=zstd -o sync=standard -o quota=2T fastData/shared-backups || {
        echo "Failed to create shared-backups dataset" | tee -a "$LOGFILE"
        exit 1
    }
    zfs create -o recordsize=1M -o compression=lz4 -o sync=standard -o quota=100G fastData/shared-iso || {
        echo "Failed to create shared-iso dataset" | tee -a "$LOGFILE"
        exit 1
    }
    zfs create -o recordsize=1M -o compression=lz4 -o sync=standard -o quota=1.4T fastData/shared-bulk-data || {
        echo "Failed to create shared-bulk-data dataset" | tee -a "$LOGFILE"
        exit 1
    }
}

# Configure ZFS snapshots
configure_snapshots() {
    echo "Configuring ZFS snapshot schedules..." | tee -a "$LOGFILE"
    echo "0 * * * * root zfs snapshot quickOS/shared-prod-data-sync@snap-hourly-\$(date +%Y%m%d%H%M)" > /etc/cron.d/zfs-snapshot-prod-data-sync
    echo "0 * * * * root zfs snapshot fastData/shared-test-data-sync@snap-hourly-\$(date +%Y%m%d%H%M)" > /etc/cron.d/zfs-snapshot-test-data-sync
    echo "0 0 * * * root zfs snapshot quickOS/disks-vm@snap-daily-\$(date +%Y%m%d)" > /etc/cron.d/zfs-snapshot-disks-vm
    echo "0 0 * * * root zfs snapshot quickOS/disks-lxc@snap-daily-\$(date +%Y%m%d)" > /etc/cron.d/zfs-snapshot-disks-lxc
    echo "0 0 * * * root zfs snapshot quickOS/shared-prod-data@snap-daily-\$(date +%Y%m%d)" > /etc/cron.d/zfs-snapshot-prod-data
    echo "0 0 * * 0 root zfs snapshot fastData/shared-test-data@snap-weekly-\$(date +%Y%m%d)" > /etc/cron.d/zfs-snapshot-test-data
}


# Verify dataset mountpoints
verify_mountpoints() {
    echo "Verifying dataset mountpoints..." | tee -a "$LOGFILE"
    for dataset in quickOS/disks-vm quickOS/disks-lxc quickOS/shared-prod-data quickOS/shared-prod-data-sync \
                   fastData/shared-test-data fastData/shared-test-data-sync fastData/shared-backups fastData/shared-iso fastData/shared-bulk-data; do
        mountpoint=$(zfs get -H -o value mountpoint "$dataset")
        if [[ ! -d "$mountpoint" ]]; then
            echo "Error: Mountpoint $mountpoint for dataset $dataset does not exist" | tee -a "$LOGFILE"
            exit 1
        fi
    done
}

# Configure NFS exports
configure_nfs() {
    echo "Configuring NFS exports..." | tee -a "$LOGFILE"
    cat << EOF > /etc/exports
/quickOS/shared-prod-data $NFS_SUBNET(rw,async,no_subtree_check,no_root_squash)
/quickOS/shared-prod-data-sync $NFS_SUBNET(rw,sync,no_subtree_check,no_root_squash)
/fastData/shared-test-data $NFS_SUBNET(rw,async,no_subtree_check,no_root_squash)
/fastData/shared-test-data-sync $NFS_SUBNET(rw,sync,no_subtree_check,no_root_squash)
/fastData/shared-bulk-data $NFS_SUBNET(rw,async,no_subtree_check,no_root_squash)
/fastData/shared-iso $NFS_SUBNET(ro,async,no_subtree_check,no_root_squash)
EOF
    exportfs -ra || { echo "Failed to export NFS shares" | tee -a "$LOGFILE"; exit 1; }
    systemctl enable --now nfs-kernel-server || { echo "Failed to enable NFS server" | tee -a "$LOGFILE"; exit 1; }
}

# Configure Samba shares
configure_samba() {
    echo "Configuring Samba shares..." | tee -a "$LOGFILE"
    cat << EOF > /etc/samba/smb.conf
[global]
   workgroup = WORKGROUP
   server signing = mandatory
   security = user
   map to guest = never

[shared-prod-data]
   path = /quickOS/shared-prod-data
   writable = yes
   browsable = yes
   valid users = $SMB_USER
   create mask = 0644
   directory mask = 0755

[shared-prod-data-sync]
   path = /quickOS/shared-prod-data-sync
   writable = yes
   browsable = yes
   valid users = $SMB_USER
   create mask = 0644
   directory mask = 0755

[shared-test-data]
   path = /fastData/shared-test-data
   writable = yes
   browsable = yes
   valid users = $SMB_USER
   create mask = 0644
   directory mask = 0755

[shared-test-data-sync]
   path = /fastData/shared-test-data-sync
   writable = yes
   browsable = yes
   valid users = $SMB_USER
   create mask = 0644
   directory mask = 0755

[shared-bulk-data]
   path = /fastData/shared-bulk-data
   writable = yes
   browsable = yes
   valid users = $SMB_USER
   create mask = 0644
   directory mask = 0755

[shared-iso]
   path = /fastData/shared-iso
   writable = no
   browsable = yes
   valid users = $SMB_USER
   create mask = 0644
   directory mask = 0755
EOF
    systemctl enable --now smbd nmbd || { echo "Failed to enable Samba services" | tee -a "$LOGFILE"; exit 1; }
}

# Configure Proxmox storage
configure_proxmox_storage() {
    echo "Configuring Proxmox storage..." | tee -a "$LOGFILE"
    pvesm add zfspool disks-vm -pool quickOS/disks-vm -content images || {
        echo "Failed to add disks-vm storage" | tee -a "$LOGFILE"
        exit 1
    }
    pvesm add zfspool disks-lxc -pool quickOS/disks-lxc -content rootdir || {
        echo "Failed to add disks-lxc storage" | tee -a "$LOGFILE"
        exit 1
    }
    pvesm add nfs shared-prod-data -server "$PROXMOX_NFS_SERVER" -path /quickOS/shared-prod-data -export /quickOS/shared-prod-data -content vztmpl,backup,iso,snippets -options vers=4 || {
        echo "Failed to add shared-prod-data storage" | tee -a "$LOGFILE"
        exit 1
    }
    pvesm add nfs shared-prod-data-sync -server "$PROXMOX_NFS_SERVER" -path /quickOS/shared-prod-data-sync -export /quickOS/shared-prod-data-sync -content vztmpl,backup,iso,snippets -options vers=4 || {
        echo "Failed to add shared-prod-data-sync storage" | tee -a "$LOGFILE"
        exit 1
    }
    pvesm add nfs shared-test-data -server "$PROXMOX_NFS_SERVER" -path /fastData/shared-test-data -export /fastData/shared-test-data -content vztmpl,backup,iso,snippets -options vers=4 || {
        echo "Failed to add shared-test-data storage" | tee -a "$LOGFILE"
        exit 1
    }
    pvesm add nfs shared-test-data-sync -server "$PROXMOX_NFS_SERVER" -path /fastData/shared-test-data-sync -export /fastData/shared-test-data-sync -content vztmpl,backup,iso,snippets -options vers=4 || {
        echo "Failed to add shared-test-data-sync storage" | tee -a "$LOGFILE"
        exit 1
    }
    pvesm add dir shared-backups -path /fastData/shared-backups -content backup || {
        echo "Failed to add shared-backups storage" | tee -a "$LOGFILE"
        exit 1
    }
    pvesm add dir shared-iso -path /fastData/shared-iso -content iso || {
        echo "Failed to add shared-iso storage" | tee -a "$LOGFILE"
        exit 1
    }
    pvesm add nfs shared-bulk-data -server "$PROXMOX_NFS_SERVER" -path /fastData/shared-bulk-data -export /fastData/shared-bulk-data -content vztmpl,backup,iso,snippets -options vers=4 || {
        echo "Failed to add shared-bulk-data storage" | tee -a "$LOGFILE"
        exit 1
    }
}

# Main execution
main() {
    check_root
    setup_logging
    check_pools
    prompt_for_smb_credentials
    prompt_for_subnet
    check_network
    install_prerequisites
    configure_firewall
    configure_samba_user
    create_quickos_datasets
    create_fastdata_datasets
    zfs mount -a || { echo "Failed to mount ZFS datasets" | tee -a "$LOGFILE"; exit 1; }
    configure_snapshots
    verify_mountpoints
    configure_nfs
    configure_samba
    configure_proxmox_storage
    echo "ZFS dataset and service setup completed successfully at $(date)" | tee -a "$LOGFILE"
}

main