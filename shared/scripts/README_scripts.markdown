# Proxmox VE Setup Scripts

This repository contains a set of bash scripts designed to automate the setup and configuration of a Proxmox VE server. The scripts handle tasks such as configuring repositories, installing the NVIDIA driver, creating an admin user, and setting up ZFS pools with NFS and Samba sharing. These scripts streamline the initial setup process and ensure a consistent configuration.

## Introduction

The scripts in this repository automate the following tasks:
- **Repository Configuration**: Disables the production and Ceph repositories, enables the no-subscription repository, and updates the system.
- **NVIDIA Driver Installation**: Installs and verifies the NVIDIA driver for systems with NVIDIA GPUs.
- **Admin User Creation**: Creates a non-root admin user with sudo and Proxmox admin privileges, sets up SSH key-based authentication, and configures the SSH port.
- **ZFS, NFS, and Samba Setup**: Configures ZFS pools for NVMe drives, sets up NFS and Samba servers for sharing datasets, and configures the firewall to allow necessary traffic.

These scripts are designed to be run in a specific order and are idempotent, meaning they can be run multiple times without causing issues, as they check for existing configurations and skip steps that have already been completed.

## Prerequisites

Before running the scripts, ensure that you have the following:
- A fresh installation of Proxmox VE.
- At least three NVMe drives for ZFS pools.
- An NVIDIA GPU (for driver installation).
- Internet access for downloading packages.
- Basic knowledge of the Linux command line.
- `wget` and `tar` installed (`apt install wget tar`).

## Setup Steps

1. **Download and Extract the Repository**:
   - Download the repository tarball to `/tmp`:
     ```bash
     wget https://github.com/your-repo/proxmox-setup-scripts/archive/refs/tags/v0.1.10.tar.gz -O /tmp/thinkheads-ai-ragdocs-IT-0.1.10.tar.gz
     ```
   - Replace `https://github.com/your-repo/proxmox-setup-scripts/archive/refs/tags/v0.1.10.tar.gz` with the actual URL of your repository tarball.
   - Extract the tarball to `/tmp/thinkheads-ai-ragdocs-IT-0.1.10`:
     ```bash
     tar -xzf /tmp/thinkheads-ai-ragdocs-IT-0.1.10.tar.gz -C /tmp
     mv /tmp/proxmox-setup-scripts-0.1.10 /tmp/thinkheads-ai-ragdocs-IT-0.1.10
     ```

2. **Navigate to the Scripts Directory**:
   - Change to the directory containing the scripts:
     ```bash
     cd /tmp/thinkheads-ai-ragdocs-IT-0.1.10/shared/scripts
     ```

3. **Copy Scripts to `/usr/local/bin`**:
   - Create the target directory and copy the scripts. Check version number in file path (0.1.10):
     ```bash
     mkdir -p /usr/local/bin
     cp /tmp/thinkheads-ai-ragdocs-IT-0.1.10/shared/scripts/common.sh \
        /tmp/thinkheads-ai-ragdocs-IT-0.1.10/shared/scripts/proxmox_configure_repos.sh \
        /tmp/thinkheads-ai-ragdocs-IT-0.1.10/shared/scripts/proxmox_create_admin_user.sh \
        /tmp/thinkheads-ai-ragdocs-IT-0.1.10/shared/scripts/proxmox_setup_zfs_nfs_samba.sh \
        /usr/local/bin/
     ```
   - **Note**: Verify the version number (`0.1.10`) matches your extracted directory path. Adjust if necessary (e.g., `0.1.11`).

4. **Set Script Permissions**:
   - Make the scripts executable:
     ```bash
     chmod +x /usr/local/bin/*.sh
     ```

5. **Configure Log Rotation**:
   - The scripts log to `/var/log/proxmox_setup.log`. Set up log rotation to manage log size.
   - Create the log rotation configuration file:
     ```bash
     nano /etc/logrotate.d/proxmox_setup
     ```
   - Add the following content:
     ```bash
     /var/log/proxmox_setup.log 
     {
         weekly
         rotate 4
         compress
         missingok
     }
     ```
   - Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X`).
   - Test the log rotation configuration:
     ```bash
     logrotate -f /etc/logrotate.d/proxmox_setup
     ```

6. **Verify Log File Access**:
   - Ensure the log file directory and file are accessible, and verify the log file is writable:
     ```bash
     mkdir -p /var/log
     touch /var/log/proxmox_setup.log
     chmod 664 /var/log/proxmox_setup.log
     echo "Test log entry" >> /var/log/proxmox_setup.log
     cat /var/log/proxmox_setup.log
     ```
   - If the test entry is visible, the log file is correctly configured.

7. **Run the Scripts in Order**:
   - Configure repositories:
     ```bash
     sudo /usr/local/bin/proxmox_configure_repos.sh [--no-reboot]
     ```
   - Install NVIDIA driver:
     ```bash
     sudo /usr/local/bin/proxmox_install_nvidia_driver.sh [--no-reboot]
     ```
   - Create admin user:
     ```bash
     sudo /usr/local/bin/proxmox_create_admin_user.sh [--username <username>] [--password <password>] [--ssh-key <key>] [--ssh-port <port>] [--no-reboot]
     ```
   - Setup ZFS, NFS, and Samba:
     ```bash
     sudo /usr/local/bin/proxmox_setup_zfs_nfs_samba.sh [--username <username>] [--no-reboot]
     ```

8. **Reboot the System**:
   - After running all scripts, reboot the system to apply changes:
     ```bash
     sudo reboot
     ```
   - If you used the `--no-reboot` flag, reboot manually.

## Script Details

- **`proxmox_configure_repos.sh`**:
  - Disables the production and Ceph repositories.
  - Enables the no-subscription repository.
  - Updates and upgrades the system.
  - **Options**:
    - `--no-reboot`: Skip automatic reboot.

- **`proxmox_install_nvidia_driver.sh`**:
  - Blacklists the Nouveau driver.
  - Installs kernel headers and the NVIDIA driver.
  - Verifies the driver installation.
  - **Options**:
    - `--no-reboot`: Skip automatic reboot.

- **`proxmox_create_admin_user.sh`**:
  - Creates a non-root admin user with sudo and Proxmox admin privileges.
  - Sets up SSH key-based authentication and configures the SSH port (default: 2222).
  - **Options**:
    - `--username <username>`: Specify the admin username (default: `heads`).
    - `--password <password>`: Specify the admin password (must be 8+ characters with 1 special character).
    - `--ssh-key <key>`: Specify the SSH public key.
    - `--ssh-port <port>`: Specify the SSH port (default: 2222).
    - `--no-reboot`: Skip automatic reboot.

- **`proxmox_setup_zfs_nfs_samba.sh`**:
  - Configures ZFS pools (`quickOS` mirror and `fastData` single) for NVMe drives.
  - Sets up NFS and Samba servers for sharing ZFS datasets.
  - Configures the firewall to allow NFS and Samba traffic.
  - **Options**:
    - `--username <username>`: Specify the username for Samba credentials (default: `heads`).
    - `--no-reboot`: Skip automatic reboot.

- **`common.sh`**:
  - Contains shared functions used by the other scripts (e.g., checking root privileges, retrying commands, checking package installations).
  - This script is sourced by the other scripts and must be in `/usr/local/bin`.

## Troubleshooting

- **Script Fails to Run**: Ensure you are running the scripts as root (`sudo`) and that they are executable (`ls -l /usr/local/bin/ | grep .sh`).
- **Download or Extraction Fails**: Verify the tarball URL and ensure `wget` and `tar` are installed (`apt install wget tar`). Check available disk space in `/tmp` (`df -h /tmp`).
- **Copy Command Fails**: Verify the version number (0.1.10) in the source path matches your extracted directory. Check that all listed scripts exist (`ls /tmp/thinkheads-ai-ragdocs-IT-0.1.10/shared/scripts/`).
- **Package Installation Issues**: Confirm internet connectivity and repository configurations (`cat /etc/apt/sources.list`).
- **ZFS Pool Creation Fails**: Ensure NVMe drives are not in use and are properly connected (`lsblk -d | grep nvme`).
- **NFS or Samba Access Issues**: Check firewall rules (`iptables -L` or `firewall-cmd --list-all`) and service status (`systemctl status nfs-kernel-server smbd`).
- **SSH Issues**: Verify the SSH port and key configuration (`cat /etc/ssh/sshd_config`); check logs in `/var/log/proxmox_setup.log`.
- **Log Rotation Issues**: Ensure `logrotate` is installed (`apt install logrotate`) and check syntax (`logrotate -d /etc/logrotate.d/proxmox_setup`).

## Notes

- All scripts log actions to `/var/log/proxmox_setup.log`. Check this file for detailed setup information.
- The scripts are idempotent and can be run multiple times safely.
- Ensure the version number in the script paths (0.1.10) matches your setup to avoid errors.

## Conclusion

By following these steps, you should have a fully configured Proxmox VE server with ZFS storage, NFS and Samba sharing, and an admin user set up. For further customization or issues, refer to the [Proxmox VE documentation](https://pve.proxmox.com/pve-docs/) or seek help from the community.