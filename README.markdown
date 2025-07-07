# Proxmox Setup Scripts

This repository contains a set of Bash scripts designed to automate the setup and configuration of Proxmox environments, including user management, storage configuration, and network sharing.

## Contents

1. [create_admin_user.sh](#create_admin_usersh)
2. [setup_zfs_nfs_samba.sh](#setup_zfs_nfs_sambash)
3. [create_container_user.sh](#create_container_usersh)

## Prerequisites

- Proxmox VE installed on your server.
- Bash shell access to the server (preferably as root).
- Basic knowledge of Linux command line operations.

## Usage Instructions

### Common Steps
1. Save each script to a directory on your Proxmox server, e.g., `/root/setup_scripts/`.
2. Make each script executable:
   ```bash
   chmod +x <script_name>.sh
   ```
3. Run the scripts as `root` using `sudo` or directly in the root shell.

### create_admin_user.sh

**Purpose**: Creates a non-root Linux user with sudo and Proxmox admin privileges, sets up SSH key-based authentication for secure access.

#### Usage:
1. Save the script to `/root/setup_scripts/create_admin_user.sh`.
2. Make executable: `chmod +x create_admin_user.sh`
3. Run as root: `bash create_admin_user.sh`
4. Follow prompts to enter a username and password, then paste your SSH public key when prompted.

### setup_zfs_nfs_samba.sh

**Purpose**: Configures ZFS mirror for 2x 2TB NVMe drives, creates a single drive pool for 4TB NVMe with datasets, installs and configures NFS/Samba server, and sets up firewall rules.

#### Usage:
1. Save the script to `/root/setup_scripts/setup_zfs_nfs_samba.sh`.
2. Make executable: `chmod +x setup_zfs_nfs_samba.sh`
3. Run as root: `bash setup_zfs_nfs_samba.sh`
4. Follow any prompts for specific configurations, such as entering usernames.

### create_container_user.sh

**Purpose**: Creates a Linux user with Samba credentials and NFS access for containers/VMs on Proxmox.

#### Usage:
1. Save the script to `/root/setup_scripts/create_container_user.sh`.
2. Make executable: `chmod +x create_container_user.sh`
3. Run as root: `bash create_container_user.sh`
4. Follow prompts to enter a new username for the container/VM and set up Samba credentials.

## Additional Information

- **create_admin_user.sh**: This script sets up an admin user with SSH key-based authentication, ensuring secure access to your Proxmox server.
- **setup_zfs_nfs_samba.sh**: This script configures ZFS storage, NFS shares, and Samba for easy file sharing across different systems within the same network.
- **create_container_user.sh**: This script creates a user specifically for container/VM use, configuring access to shared datasets via NFS and Samba.

## Contributing

Private for now
