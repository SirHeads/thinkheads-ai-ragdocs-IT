#!/bin/bash

# setup_zfs_proxmox.sh
# Configures ZFS pools (quickOS, fastData), datasets, and Proxmox storage for VMs, LXC, databases, and shared data.
# Prompts for NVMe drives, SMB user/password, and network subnet. Sets ARC to 24GB, handles NFS/Samba dependencies, and configures firewall.

# Exit on any error
set -e

# Constants
LOGFILE="/var/log/setup_zfs_proxmox.log"
ARC_MAX=$((24 * 1024 * 1024 * 1024)) # 24GB ARC cache for 96GB RAM system
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
    exec 1> >(tee -a "$LOGFILE")
    exec 2>&1
    echo "Starting ZFS and Proxmox setup at $(date)" | tee -a "$LOGFILE"
}

# Check ZFS version for autotrim support
check_zfs_version() {
    echo "Checking ZFS version..." | tee -a "$LOGFILE"
    ZFS_VERSION=$(zfs version | head -n1 | cut -d'-' -f2)
    if [[ "$ZFS_VERSION" < "2.0" ]]; then
        echo "Warning: ZFS version $ZFS_VERSION does not support autotrim. Will rely on periodic fstrim." | tee -a "$LOGFILE"
        AUTOTRIM_SUPPORTED=false
    else
        echo "ZFS version $ZFS_VERSION supports autotrim." | tee -a "$LOGFILE"
        AUTOTRIM_SUPPORTED=true
    fi
}

# Prompt for NVMe drives
prompt_for_drives() {
    echo "Available NVMe drives:" | tee -a "$LOGFILE"
    lsblk -d -o NAME,SIZE,MODEL | grep nvme
    echo "Select two NVMe drives for quickOS (mirrored, 2TB each, e.g., /dev/nvme0n1 /dev/nvme2n1):"
    read -r -p "Enter two drive paths (space-separated): " quickos_drive1 quickos_drive2
    if [[ ! -b "$quickos_drive1" || ! -b "$quickos_drive2" ]]; then
        echo "Error: Invalid or non-existent drives: $quickos_drive1, $quickos_drive2" | tee -a "$LOGFILE"
        exit 1
    fi
    QUICKOS_2TB_DRIVES=("$quickos_drive1" "$quickos_drive2")

    echo "Select one NVMe drive for fastData (4TB, e.g., /dev/nvme1n1):"
    read -r -p "Enter drive path: " fastdata_drive
    if [[ ! -b "$fastdata_drive" ]]; then
        echo "Error: Invalid or non-existent drive: $fastdata_drive" | tee -a "$LOGFILE"
        exit 1
    fi
    FASTDATA_4TB_DRIVE="$fastdata_drive"
}

# Check if drives are in use
check_drives_free() {
    echo "Checking if drives are free..." | tee -a "$LOGFILE"
    for drive in "${QUICKOS_2TB_DRIVES[@]}" "$FASTDATA_4TB_DRIVE"; do
        if zpool status | grep -q "$drive"; then
            echo "Error: Drive $drive is part of an existing ZFS pool. Destroy the pool first." | tee -a "$LOGFILE"
            exit 1
        fi
        if mount | grep -q "$drive"; then
            echo "Error: Drive $drive is mounted. Unmount it first." | tee -a "$LOGFILE"
            exit 1
        fi
        if pvdisplay | grep -q "$drive"; then
            echo "Error: Drive $drive is part of an LVM physical volume. Remove it first." | tee -a "$LOGFILE"
            exit 1
        fi
        if lsof "$drive" > /dev/null 2>&1; then
            echo "Error: Drive $drive is in use by a process. Stop processes first." | tee -a "$LOGFILE"
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
    echo "Configuring firewall for SSH (port 2222), NFS, Samba, and Proxmox web UI..." | tee -a "$LOGFILE"
    ufw allow from "$NFS_SUBNET" to any port 2222 proto tcp # SSH
    ufw allow from "$NFS_SUBNET" to any port 111 proto tcp # RPC
    ufw allow from "$NFS_SUBNET" to any port 2049 proto tcp # NFS
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
    if ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        echo "Warning: No internet connectivity detected. Package installation may fail." | tee -a "$LOGFILE"
    fi
    if ! ip addr show | grep -q "inet.*$NFS_SUBNET"; then
        echo "Warning: Network subnet $NFS_SUBNET not detected. NFS/Samba may not work as expected." | tee -a "$LOGFILE"
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

# Confirm drive wiping
confirm_wipe_drives() {
    echo "WARNING: This script will wipe the following drives:" | tee -a "$LOGFILE"
    echo "quickOS (mirror): ${QUICKOS_2TB_DRIVES[*]}" | tee -a "$LOGFILE"
    echo "fastData (single): $FASTDATA_4TB_DRIVE" | tee -a "$LOGFILE"
    read -p "Proceed with wiping drives? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted by user." | tee -a "$LOGFILE"
        exit 1
    fi
}

# Wipe drives
wipe_drives() {
    echo "Wiping drives..." | tee -a "$LOGFILE"
    for drive in "${QUICKOS_2TB_DRIVES[@]}" "$FASTDATA_4TB_DRIVE"; do
        if [[ -b "$drive" ]]; then
            wipefs -a "$drive" || { echo "Failed to wipe $drive" | tee -a "$LOGFILE"; exit 1; }
        else
            echo "Error: Drive $drive not found." | tee -a "$LOGFILE"
            exit 1
        fi
    done
}

# Create ZFS pools
create_zfs_pools() {
    echo "Creating ZFS pool quickOS (mirror)..." | tee -a "$LOGFILE"
    if [[ "$AUTOTRIM_SUPPORTED" == "true" ]]; then
        zpool create -f -o ashift=12 -o autotrim=on quickOS mirror "${QUICKOS_2TB_DRIVES[@]}" || {
            echo "Failed to create quickOS pool" | tee -a "$LOGFILE"
            exit 1
        }
    else
        zpool create -f -o ashift=12 quickOS mirror "${QUICKOS_2TB_DRIVES[@]}" || {
            echo "Failed to create quickOS pool" | tee -a "$LOGFILE"
            exit 1
        }
        echo "Setting up periodic fstrim due to lack of autotrim support..." | tee -a "$LOGFILE"
        echo "15 3 * * * root fstrim /quickOS" > /etc/cron.d/fstrim_quickOS
    fi
    zfs set compression=lz4 atime=off quickOS || {
        echo "Failed to set properties on quickOS pool" | tee -a "$LOGFILE"
        exit 1
    }

    echo "Creating ZFS pool fastData (single)..." | tee -a "$LOGFILE"
    if [[ "$AUTOTRIM_SUPPORTED" == "true" ]]; then
        zpool create -f -o ashift=12 -o autotrim=on fastData "$FASTDATA_4TB_DRIVE" || {
            echo "Failed to create fastData pool" | tee -a "$LOGFILE"
            exit 1
        }
    else
        zpool create -f -o ashift=12 fastData "$FASTDATA_4TB_DRIVE" || {
            echo "Failed to create fastData pool" | tee -a "$LOGFILE"
            exit 1
        }
        echo "Setting up periodic fstrim for fastData..." | tee -a "$LOGFILE"
        echo "15 3 * * * root fstrim /fastData" > /etc/cron.d/fstrim_fastData
    fi
    zfs set compression=lz4 atime=off fastData || {
        echo "Failed to set properties on fastData pool" | tee -a "$LOGFILE"
        exit 1
    }
}

# Tune ARC cache
tune_arc() {
    echo "Tuning ARC cache to 24GB..." | tee -a "$LOGFILE"
    echo "$ARC_MAX" > /sys/module/zfs/parameters/zfs_arc_max
    echo "options zfs zfs_arc_max=$ARC_MAX" > /etc/modprobe.d/zfs.conf
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
    echo "0 0 * * * root zfs snapshot quickOS/disks-vm@snap-daily-\$(date +%Y%m%d)" > /etc/cron.d/zfs-snapshot-disks-vm
    echo "0 0 * * * root zfs snapshot quickOS/disks-lxc@snap-daily-\$(date +%Y%m%d)" > /etc/cron.d/zfs-snapshot-disks-lxc
    echo "0 0 * * * root zfs snapshot quickOS/shared-prod-data@snap-daily-\$(date +%Y%m%d)" > /etc/cron.d/zfs-snapshot-prod-data
    echo "0 0 * * 0 root zfs snapshot fastData/shared-test-data@snap-weekly-\$(date +%Y%m%d)" > /etc/cron.d/zfs-snapshot-test-data
}

# Verify dataset mountpoints
verify_mountpoints() {
    echo "Verifying dataset mountpoints..." | tee -a "$LOGFILE"
    for dataset in quickOS/disks-vm quickOS/disks-lxc quickOS/shared-prod-data quickOS/shared-prod-data-sync \
                   fastData/shared-test-data fastData/shared-backups fastData/shared-iso fastData/shared-bulk-data; do
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
    pvesm add nfs shared-prod-data -server localhost -path /quickOS/shared-prod-data -export /quickOS/shared-prod-data -content vztmpl,backup,iso,snippets -options noatime,async || {
        echo "Failed to add shared-prod-data storage" | tee -a "$LOGFILE"
        exit 1
    }
    pvesm add nfs shared-prod-data-sync -server localhost -path /quickOS/shared-prod-data-sync -export /quickOS/shared-prod-data-sync -content vztmpl,backup,iso,snippets -options noatime,sync || {
        echo "Failed to add shared-prod-data-sync storage" | tee -a "$LOGFILE"
        exit 1
    }
    pvesm add nfs shared-test-data -server localhost -path /fastData/shared-test-data -export /fastData/shared-test-data -content vztmpl,backup,iso,snippets -options noatime,async || {
        echo "Failed to add shared-test-data storage" | tee -a "$LOGFILE"
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
    pvesm add nfs shared-bulk-data -server localhost -path /fastData/shared-bulk-data -export /fastData/shared-bulk-data -content vztmpl,backup,iso,snippets -options noatime,async || {
        echo "Failed to add shared-bulk-data storage" | tee -a "$LOGFILE"
        exit 1
    }
}

# Main execution
main() {
    check_root
    setup_logging
    check_zfs_version
    prompt_for_drives
    prompt_for_smb_credentials
    prompt_for_subnet
    check_network
    install_prerequisites
    configure_firewall
    configure_samba_user
    check_drives_free
    confirm_wipe_drives
    wipe_drives
    create_zfs_pools
    tune_arc
    create_quickos_datasets
    create_fastdata_datasets
    configure_snapshots
    verify_mountpoints
    configure_nfs
    configure_samba
    configure_proxmox_storage
    echo "ZFS and Proxmox setup completed successfully at $(date)" | tee -a "$LOGFILE"
}

main