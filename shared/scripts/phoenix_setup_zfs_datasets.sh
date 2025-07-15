#!/bin/bash

# phoenix_setup_zfs_datasets.sh
# Configures ZFS datasets, NFS/Samba shares for each dataset, and Proxmox storage
# Version: 1.0.4
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_zfs_datasets.sh
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup
# Run after phoenix_setup_nfs.sh and phoenix_setup_samba.sh

# Exit on any error
set -e

# Source common functions
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }

# Constants
PROXMOX_NFS_SERVER="10.0.0.13" # Host IP for NFS server
DEFAULT_SUBNET="10.0.0.0/24" # Default network subnet

# Ensure script runs as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root." | tee -a "$LOGFILE"
        exit 1
    fi
}

# Initialize logging
setup_logging() {
    # Rely on LOGFILE from common.sh
    echo "Starting ZFS dataset setup at $(date)" | tee -a "$LOGFILE"
}

# Prompt for network subnet
prompt_for_subnet() {
    echo "Enter network subnet for NFS/Samba (default: $DEFAULT_SUBNET):"
    read -r NFS_SUBNET
    NFS_SUBNET=${NFS_SUBNET:-$DEFAULT_SUBNET}
    if ! [[ "$NFS_SUBNET" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "Error: Invalid subnet format: $NFS_SUBNET" | tee -a "$LOGFILE"
        exit 1
    fi
}

# Install required ZFS packages
install_prerequisites() {
    echo "Installing ZFS prerequisites..." | tee -a "$LOGFILE"
    retry_command "apt-get update"
    retry_command "apt-get install -y zfsutils-linux" || {
        echo "Failed to install ZFS prerequisites" | tee -a "$LOGFILE"
        exit 1
    }
}

# Configure firewall for Proxmox
configure_firewall_proxmox() {
    echo "Configuring firewall for SSH and Proxmox web UI..." | tee -a "$LOGFILE"
    retry_command "ufw allow from $NFS_SUBNET to any port 22 proto tcp" || { echo "Failed to set firewall rule for SSH" | tee -a "$LOGFILE"; exit 1; }
    retry_command "ufw allow from $NFS_SUBNET to any port 8006 proto tcp" || { echo "Failed to set firewall rule for Proxmox web UI" | tee -a "$LOGFILE"; exit 1; }
    ufw status | grep -E "22|8006" || { echo "Failed to verify Proxmox firewall rules" | tee -a "$LOGFILE"; exit 1; }
}

# Check if pools exist and are healthy
check_pools() {
    echo "Checking for required ZFS pools..." | tee -a "$LOGFILE"
    for pool in quickOS fastData; do
        if ! zpool status "$pool" >/dev/null 2>&1; then
            echo "Error: ZFS pool $pool does not exist. Run phoenix_setup_zfs_pools.sh first." | tee -a "$LOGFILE"
            exit 1
        fi
        zpool status "$pool" | grep -q "state: ONLINE" || {
            echo "Error: Pool $pool is not healthy" | tee -a "$LOGFILE"
            exit 1
        }
    done
}

# Check NFS services
check_nfs_services() {
    echo "Checking NFS services..." | tee -a "$LOGFILE"
    for service in rpcbind nfs-kernel-server; do
        if ! systemctl is-active --quiet "$service"; then
            echo "Error: $service is not running" | tee -a "$LOGFILE"
            retry_command "systemctl restart $service" || { echo "Failed to restart $service" | tee -a "$LOGFILE"; exit 1; }
        fi
        echo "$service is running" | tee -a "$LOGFILE"
    done
}

# Create ZFS datasets on quickOS and configure NFS/Samba shares
create_quickos_datasets() {
    echo "Creating quickOS datasets and configuring shares..." | tee -a "$LOGFILE"
    # disks-vm
    retry_command "zfs create -o mountpoint=/quickOS/disks-vm -o recordsize=128K -o compression=lz4 -o sync=standard -o quota=800G -o canmount=on quickOS/disks-vm" || {
        echo "Failed to create disks-vm dataset" | tee -a "$LOGFILE"
        exit 1
    }
    chown "$SMB_USER":"$SMB_USER" /quickOS/disks-vm
    chmod 755 /quickOS/disks-vm
    # disks-lxc
    retry_command "zfs create -o mountpoint=/quickOS/disks-lxc -o recordsize=16K -o compression=lz4 -o sync=standard -o quota=600G -o canmount=on quickOS/disks-lxc" || {
        echo "Failed to create disks-lxc dataset" | tee -a "$LOGFILE"
        exit 1
    }
    chown "$SMB_USER":"$SMB_USER" /quickOS/disks-lxc
    chmod 755 /quickOS/disks-lxc
    # shared-prod-data
    retry_command "zfs create -o mountpoint=/quickOS/shared-prod-data -o recordsize=128K -o compression=lz4 -o sync=standard -o quota=400G -o canmount=on quickOS/shared-prod-data" || {
        echo "Failed to create shared-prod-data dataset" | tee -a "$LOGFILE"
        exit 1
    }
    chown "$SMB_USER":"$SMB_USER" /quickOS/shared-prod-data
    chmod 755 /quickOS/shared-prod-data
    echo "/quickOS/shared-prod-data $NFS_SUBNET(rw,async,no_subtree_check,no_root_squash)" >> /etc/exports
    cat << EOF >> /etc/samba/smb.conf
[shared-prod-data]
   path = /quickOS/shared-prod-data
   writable = yes
   browsable = yes
   valid users = $SMB_USER
   create mask = 0644
   directory mask = 0755
EOF
    # shared-prod-data-sync
    retry_command "zfs create -o mountpoint=/quickOS/shared-prod-data-sync -o recordsize=16K -o compression=lz4 -o sync=always -o quota=100G -o canmount=on quickOS/shared-prod-data-sync" || {
        echo "Failed to create shared-prod-data-sync dataset" | tee -a "$LOGFILE"
        exit 1
    }
    chown "$SMB_USER":"$SMB_USER" /quickOS/shared-prod-data-sync
    chmod 755 /quickOS/shared-prod-data-sync
    echo "/quickOS/shared-prod-data-sync $NFS_SUBNET(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
    cat << EOF >> /etc/samba/smb.conf
[shared-prod-data-sync]
   path = /quickOS/shared-prod-data-sync
   writable = yes
   browsable = yes
   valid users = $SMB_USER
   create mask = 0644
   directory mask = 0755
EOF
    # Validate Samba configuration
    retry_command "testparm -s" || { echo "Error: Invalid Samba configuration after quickOS shares" | tee -a "$LOGFILE"; exit 1; }
}

# Create ZFS datasets on fastData and configure NFS/Samba shares
create_fastdata_datasets() {
    echo "Creating fastData datasets and configuring shares..." | tee -a "$LOGFILE"
    # shared-test-data
    retry_command "zfs create -o mountpoint=/fastData/shared-test-data -o recordsize=128K -o compression=lz4 -o sync=standard -o quota=500G -o canmount=on fastData/shared-test-data" || {
        echo "Failed to create shared-test-data dataset" | tee -a "$LOGFILE"
        exit 1
    }
    chown "$SMB_USER":"$SMB_USER" /fastData/shared-test-data
    chmod 755 /fastData/shared-test-data
    echo "/fastData/shared-test-data $NFS_SUBNET(rw,async,no_subtree_check,no_root_squash)" >> /etc/exports
    cat << EOF >> /etc/samba/smb.conf
[shared-test-data]
   path = /fastData/shared-test-data
   writable = yes
   browsable = yes
   valid users = $SMB_USER
   create mask = 0644
   directory mask = 0755
EOF
    # shared-test-data-sync
    retry_command "zfs create -o mountpoint=/fastData/shared-test-data-sync -o recordsize=16K -o compression=lz4 -o sync=always -o quota=100G -o canmount=on fastData/shared-test-data-sync" || {
        echo "Failed to create shared-test-data-sync dataset" | tee -a "$LOGFILE"
        exit 1
    }
    chown "$SMB_USER":"$SMB_USER" /fastData/shared-test-data-sync
    chmod 755 /fastData/shared-test-data-sync
    echo "/fastData/shared-test-data-sync $NFS_SUBNET(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
    cat << EOF >> /etc/samba/smb.conf
[shared-test-data-sync]
   path = /fastData/shared-test-data-sync
   writable = yes
   browsable = yes
   valid users = $SMB_USER
   create mask = 0644
   directory mask = 0755
EOF
    # shared-backups
    retry_command "zfs create -o mountpoint=/fastData/shared-backups -o recordsize=1M -o compression=zstd -o sync=standard -o quota=2T -o canmount=on fastData/shared-backups" || {
        echo "Failed to create shared-backups dataset" | tee -a "$LOGFILE"
        exit 1
    }
    chown "$SMB_USER":"$SMB_USER" /fastData/shared-backups
    chmod 755 /fastData/shared-backups
    cat << EOF >> /etc/samba/smb.conf
[shared-backups]
   path = /fastData/shared-backups
   writable = yes
   browsable = yes
   valid users = $SMB_USER
   create mask = 0644
   directory mask = 0755
EOF
    # shared-iso
    retry_command "zfs create -o mountpoint=/fastData/shared-iso -o recordsize=1M -o compression=lz4 -o sync=standard -o quota=100G -o canmount=on fastData/shared-iso" || {
        echo "Failed to create shared-iso dataset" | tee -a "$LOGFILE"
        exit 1
    }
    chown "$SMB_USER":"$SMB_USER" /fastData/shared-iso
    chmod 755 /fastData/shared-iso
    echo "/fastData/shared-iso $NFS_SUBNET(ro,async,no_subtree_check,no_root_squash)" >> /etc/exports
    cat << EOF >> /etc/samba/smb.conf
[shared-iso]
   path = /fastData/shared-iso
   writable = no
   browsable = yes
   valid users = $SMB_USER
   create mask = 0644
   directory mask = 0755
EOF
    # shared-bulk-data
    retry_command "zfs create -o mountpoint=/fastData/shared-bulk-data -o recordsize=1M -o compression=lz4 -o sync=standard -o quota=1.4T -o canmount=on fastData/shared-bulk-data" || {
        echo "Failed to create shared-bulk-data dataset" | tee -a "$LOGFILE"
        exit 1
    }
    chown "$SMB_USER":"$SMB_USER" /fastData/shared-bulk-data
    chmod 755 /fastData/shared-bulk-data
    echo "/fastData/shared-bulk-data $NFS_SUBNET(rw,async,no_subtree_check,no_root_squash)" >> /etc/exports
    cat << EOF >> /etc/samba/smb.conf
[shared-bulk-data]
   path = /fastData/shared-bulk-data
   writable = yes
   browsable = yes
   valid users = $SMB_USER
   create mask = 0644
   directory mask = 0755
EOF
    # Validate Samba configuration
    retry_command "testparm -s" || { echo "Error: Invalid Samba configuration after fastData shares" | tee -a "$LOGFILE"; exit 1; }
    # Apply NFS exports
    retry_command "exportfs -ra" || { echo "Failed to export NFS shares" | tee -a "$LOGFILE"; exit 1; }
    exportfs -v | grep -E "/quickOS|/fastData" || { echo "Failed to verify NFS exports" | tee -a "$LOGFILE"; exit 1; }
    # Restart Samba to apply new shares
    retry_command "systemctl restart smbd nmbd" || { echo "Failed to restart Samba services" | tee -a "$LOGFILE"; exit 1; }
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
        if [[ $(zfs get -H -o value mounted "$dataset") != "yes" ]]; then
            echo "Error: Dataset $dataset is not mounted" | tee -a "$LOGFILE"
            retry_command "zfs mount $dataset" || { echo "Failed to mount $dataset" | tee -a "$LOGFILE"; exit 1; }
        fi
        if [[ $(zfs get -H -o value canmount "$dataset") != "on" ]]; then
            echo "Warning: Dataset $dataset has canmount=off, setting to on" | tee -a "$LOGFILE"
            retry_command "zfs set canmount=on $dataset" || { echo "Failed to set canmount for $dataset" | tee -a "$LOGFILE"; exit 1; }
        fi
        echo "Mountpoint $mountpoint for $dataset verified" | tee -a "$LOGFILE"
    done
}

# Verify dataset responsiveness
verify_datasets() {
    echo "Verifying dataset responsiveness..." | tee -a "$LOGFILE"
    echo "Enter Samba password for user $SMB_USER (input hidden):"
    read -r -s TEST_SMB_PASSWORD
    if [[ -z "$TEST_SMB_PASSWORD" ]]; then
        echo "Error: Samba password cannot be empty" | tee -a "$LOGFILE"
        exit 1
    fi
    echo "Confirm Samba password (input hidden):"
    read -r -s TEST_SMB_PASSWORD_CONFIRM
    if [[ "$TEST_SMB_PASSWORD" != "$TEST_SMB_PASSWORD_CONFIRM" ]]; then
        echo "Error: Passwords do not match" | tee -a "$LOGFILE"
        exit 1
    fi
    for dataset in quickOS/disks-vm quickOS/disks-lxc quickOS/shared-prod-data quickOS/shared-prod-data-sync \
                   fastData/shared-test-data fastData/shared-test-data-sync fastData/shared-backups fastData/shared-iso fastData/shared-bulk-data; do
        mountpoint=$(zfs get -H -o value mountpoint "$dataset")
        # Test local write access
        echo "test" > "$mountpoint/testfile" || {
            echo "Error: Failed to write to $mountpoint" | tee -a "$LOGFILE"
            exit 1
        }
        rm -f "$mountpoint/testfile"
        echo "Local write to $mountpoint successful" | tee -a "$LOGFILE"
        # Test NFS access (skip disks-vm and disks-lxc, as they are not exported)
        if [[ "$dataset" != "quickOS/disks-vm" && "$dataset" != "quickOS/disks-lxc" ]]; then
            mkdir -p "/mnt/nfs-test-$dataset"
            retry_command "mount -t nfs $PROXMOX_NFS_SERVER:$mountpoint /mnt/nfs-test-$dataset" || {
                echo "Error: Failed to mount NFS share $mountpoint" | tee -a "$LOGFILE"
                rm -rf "/mnt/nfs-test-$dataset"
                exit 1
            }
            echo "test" > "/mnt/nfs-test-$dataset/testfile" || {
                echo "Error: Failed to write to NFS share $mountpoint" | tee -a "$LOGFILE"
                umount "/mnt/nfs-test-$dataset"
                rm -rf "/mnt/nfs-test-$dataset"
                exit 1
            }
            rm -f "/mnt/nfs-test-$dataset/testfile"
            retry_command "umount /mnt/nfs-test-$dataset" || {
                echo "Error: Failed to unmount NFS share $mountpoint" | tee -a "$LOGFILE"
                exit 1
            }
            rm -rf "/mnt/nfs-test-$dataset"
            echo "NFS access to $mountpoint successful" | tee -a "$LOGFILE"
        fi
        # Test Samba access (skip disks-vm and disks-lxc, as they are not Samba shares)
        if [[ "$dataset" != "quickOS/disks-vm" && "$dataset" != "quickOS/disks-lxc" ]]; then
            share_name=$(basename "$mountpoint")
            echo "test" > /tmp/samba-test-file
            chown "$SMB_USER":"$SMB_USER" /tmp/samba-test-file
            chmod 644 /tmp/samba-test-file
            error_output=$(smbclient "//localhost/$share_name" "$TEST_SMB_PASSWORD" -U "$SMB_USER" -c "put /tmp/samba-test-file testfile" 2>&1)
            if [[ $? -ne 0 ]]; then
                echo "Error: Failed to upload test file to Samba share $share_name" | tee -a "$LOGFILE"
                echo "Error output: $error_output" | tee -a "$LOGFILE"
                rm -f /tmp/samba-test-file "$mountpoint/testfile"
                exit 1
            fi
            rm -f /tmp/samba-test-file "$mountpoint/testfile"
            echo "Samba access to $share_name successful" | tee -a "$LOGFILE"
        fi
    done
}

# Configure Proxmox storage
configure_proxmox_storage() {
    echo "Configuring Proxmox storage..." | tee -a "$LOGFILE"
    # Remove existing NFS storages to avoid stale configurations
    for storage in shared-prod-data shared-prod-data-sync shared-test-data shared-test-data-sync shared-bulk-data; do
        pvesm remove "$storage" 2>/dev/null || true
    done
    retry_command "pvesm add zfspool disks-vm -pool quickOS/disks-vm -content images" || {
        echo "Failed to add disks-vm storage" | tee -a "$LOGFILE"
        exit 1
    }
    retry_command "pvesm add zfspool disks-lxc -pool quickOS/disks-lxc -content rootdir" || {
        echo "Failed to add disks-lxc storage" | tee -a "$LOGFILE"
        exit 1
    }
    retry_command "pvesm add nfs shared-prod-data -server $PROXMOX_NFS_SERVER -path /quickOS/shared-prod-data -export /quickOS/shared-prod-data -content vztmpl,backup,iso,snippets -options vers=4" || {
        echo "Failed to add shared-prod-data storage" | tee -a "$LOGFILE"
        exit 1
    }
    retry_command "pvesm add nfs shared-prod-data-sync -server $PROXMOX_NFS_SERVER -path /quickOS/shared-prod-data-sync -export /quickOS/shared-prod-data-sync -content vztmpl,backup,iso,snippets -options vers=4" || {
        echo "Failed to add shared-prod-data-sync storage" | tee -a "$LOGFILE"
        exit 1
    }
    retry_command "pvesm add nfs shared-test-data -server $PROXMOX_NFS_SERVER -path /fastData/shared-test-data -export /fastData/shared-test-data -content vztmpl,backup,iso,snippets -options vers=4" || {
        echo "Failed to add shared-test-data storage" | tee -a "$LOGFILE"
        exit 1
    }
    retry_command "pvesm add nfs shared-test-data-sync -server $PROXMOX_NFS_SERVER -path /fastData/shared-test-data-sync -export /fastData/shared-test-data-sync -content vztmpl,backup,iso,snippets -options vers=4" || {
        echo "Failed to add shared-test-data-sync storage" | tee -a "$LOGFILE"
        exit 1
    }
    retry_command "pvesm add dir shared-backups -path /fastData/shared-backups -content backup" || {
        echo "Failed to add shared-backups storage" | tee -a "$LOGFILE"
        exit 1
    }
    retry_command "pvesm add dir shared-iso -path /fastData/shared-iso -content iso" || {
        echo "Failed to add shared-iso storage" | tee -a "$LOGFILE"
        exit 1
    }
    retry_command "pvesm add nfs shared-bulk-data -server $PROXMOX_NFS_SERVER -path /fastData/shared-bulk-data -export /fastData/shared-bulk-data -content vztmpl,backup,iso,snippets -options vers=4" || {
        echo "Failed to add shared-bulk-data storage" | tee -a "$LOGFILE"
        exit 1
    }
    pvesm status | grep -E "shared-prod-data|shared-test-data|shared-bulk-data|shared-iso|shared-backups" | grep -v inactive || {
        echo "Failed to verify Proxmox storage" | tee -a "$LOGFILE"
        exit 1
    }
}

# Main execution
main() {
    check_root
    setup_logging
    prompt_for_subnet
    configure_firewall_proxmox
    # Get Samba user from smb.conf or prompt if not set
    SMB_USER=$(grep "valid users" /etc/samba/smb.conf | awk '{print $NF}' | head -1 || true)
    if [[ -z "$SMB_USER" ]]; then
        echo "Enter Samba username (e.g., heads):"
        read -r SMB_USER
        if [[ -z "$SMB_USER" ]]; then
            echo "Error: Samba username cannot be empty" | tee -a "$LOGFILE"
            exit 1
        fi
        echo "Enter Samba password (input hidden):"
        read -r -s SMB_PASSWORD
        if [[ -z "$SMB_PASSWORD" ]]; then
            echo "Error: Samba password cannot be empty" | tee -a "$LOGFILE"
            exit 1
        fi
        echo "Confirm Samba password (input hidden):"
        read -r -s SMB_PASSWORD_CONFIRM
        if [[ "$SMB_PASSWORD" != "$SMB_PASSWORD_CONFIRM" ]]; then
            echo "Error: Passwords do not match" | tee -a "$LOGFILE"
            exit 1
        fi
        configure_samba_user
    fi
    check_pools
    check_nfs_services
    install_prerequisites
    create_quickos_datasets
    create_fastdata_datasets
    retry_command "zfs mount -a" || { echo "Failed to mount ZFS datasets" | tee -a "$LOGFILE"; exit 1; }
    verify_mountpoints
    verify_datasets
    configure_proxmox_storage
    echo "ZFS dataset, NFS/Samba shares, and Proxmox storage setup completed successfully at $(date)" | tee -a "$LOGFILE"
}

# Configure Samba user (called only if user is prompted)
configure_samba_user() {
    echo "Configuring Samba user $SMB_USER..." | tee -a "$LOGFILE"
    if ! id "$SMB_USER" > /dev/null 2>&1; then
        retry_command "useradd -M -s /sbin/nologin $SMB_USER" || {
            echo "Failed to create Samba user $SMB_USER" | tee -a "$LOGFILE"
            exit 1
        }
    fi
    echo -e "$SMB_PASSWORD\n$SMB_PASSWORD" | smbpasswd -s -a "$SMB_USER" || {
        echo "Failed to set Samba password for $SMB_USER" | tee -a "$LOGFILE"
        exit 1
    }
    retry_command "smbpasswd -e $SMB_USER" || {
        echo "Failed to enable Samba user $SMB_USER" | tee -a "$LOGFILE"
        exit 1
    }
}

main