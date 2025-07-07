# Phoenix Server Proxmox VE Setup

This repository contains scripts to configure a Proxmox VE server tailored for a high-performance home-lab server with AMD CPU, NVIDIA 5060 TI GPUs, and NVMe storage, supporting AI/ML workloads, containers, and VMs.

## Purpose

The scripts automate the configuration of Proxmox VE, including repository setup, admin user creation, ZFS storage pools, NFS/Samba sharing, NVIDIA GPU virtualization, and LXC/VM user setup. They are modular, robust, and include error handling and logging.

## Prerequisites

Before running the scripts, ensure the following requirements are met:

- **Operating System**: Proxmox VE 8.x (based on Debian 12 Bookworm) installed on 2x 240GB Crucial BX500 SSDs (ZFS mirror, 180GB allocated per SSD).
- **Hardware**:
  - AMD CPU (e.g., AMD 7600).
  - 2x NVIDIA 5060 TI GPUs (PCIe 5.0 x8).
  - 2x 2TB Samsung 990 EVO Plus NVMe (for ZFS mirror).
  - 1x 4TB Samsung 990 EVO Plus NVMe (for shared storage).
  - 96GB DDR5 RAM.
  - 10GbE Ethernet interface.
- **Network**:
  - Static IP: `<server-ip>` (e.g., 192.168.1.100).
  - Gateway: `<gateway-ip>` (e.g., 192.168.1.1).
  - DNS: `<dns-server>` (e.g., 8.8.8.8).
  - Subnet: `<subnet>` (e.g., 192.168.1.0/24).
- **Software**:
  - Internet access for package downloads (e.g., NVIDIA drivers, CUDA).
  - `wget` installed (typically pre-installed on Proxmox VE).
- **Permissions**: Initial login as `root` user via SSH or console.
- **Storage**: NVMe drives must be visible via `lsblk` (2x 2TB for mirror, 1x 4TB for standalone).

## Pre-Configuration Steps

Follow these steps in order to prepare the server before running the setup scripts. All commands are executed as the `root` user unless otherwise specified.

1. **Log in as root**:
   - Access the server via SSH (`ssh root@<server-ip>`) or console.

2. **Download Scripts with wget**:
   - Use `wget` to download all scripts from their raw URLs to `/root`.
     ```bash
     wget https://github.com/SirHeads/thinkheads-ai-ragdocs-IT/blob/main/shared/scripts/common.sh
     ```
     ```bash
     wget https://github.com/SirHeads/thinkheads-ai-ragdocs-IT/blob/main/shared/scripts/proxmox_configure_repos.sh
     ```
     ```bash
     wget https://github.com/SirHeads/thinkheads-ai-ragdocs-IT/blob/main/shared/scripts/proxmox_create_admin_user.sh
     ```
     ```bash
     wget https://github.com/SirHeads/thinkheads-ai-ragdocs-IT/blob/main/shared/scripts/proxmox_setup_zfs_nfs_samba.sh
     ```
     ```bash
     wget https://github.com/SirHeads/thinkheads-ai-ragdocs-IT/blob/main/shared/scripts/proxmox_setup_nvidia_gpu_virt.sh
     ```
     ```bash
     wget https://github.com/SirHeads/thinkheads-ai-ragdocs-IT/blob/main/shared/scripts/proxmox_create_lxc_user.sh
     ```
     For private repositories, include an authorization token:
     ```bash
     wget --header="Authorization: token <your-token>" <url-to-common.sh> -O /root/common.sh
     ```

3. **Copy Scripts to `/usr/local/bin`**:
   - Copy all downloaded scripts to `/usr/local/bin`.
     ```bash
     sudo mkdir -p /usr/local/bin
     sudo cp /root/common.sh /root/proxmox_configure_repos.sh /root/proxmox_create_admin_user.sh /root/proxmox_setup_zfs_nfs_samba.sh /root/proxmox_setup_nvidia_gpu_virt.sh /root/proxmox_create_lxc_user.sh /usr/local/bin/
     ```

4. **Set Script Permissions**:
   - Make the scripts executable.
     ```bash
     sudo chmod +x /usr/local/bin/*.sh
     ```

5. **Configure Repositories**:
   - Run `proxmox_configure_repos.sh` to enable the Proxmox VE no-subscription repository.
     ```bash
     sudo /usr/local/bin/proxmox_configure_repos.sh
     ```

6. **Configure Log Rotation**:
   - The scripts log to `/var/log/proxmox_setup.log`. Set up log rotation to manage log size.
   - Create the log rotation configuration file:
     ```bash
     sudo nano /etc/logrotate.d/proxmox_setup
     ```
   - Add the following content:
     ```bash
     /var/log/proxmox_setup.log {
         weekly
         rotate 4
         compress
         missingok
     }
     ```
   - Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X`).
   - Test the log rotation configuration:
     ```bash
     sudo logrotate -f /etc/logrotate.d/proxmox_setup
     ```

7. **Verify Log File Access**:
   - Ensure the log file directory and file are accessible.
     ```bash
     sudo mkdir -p /var/log
     sudo touch /var/log/proxmox_setup.log
     sudo chmod 664 /var/log/proxmox_setup.log
     ```
   - Verify the log file is writable:
     ```bash
     echo "Test log entry" >> /var/log/proxmox_setup.log
     cat /var/log/proxmox_setup.log
     ```
   - If the test entry is visible, the log file is correctly configured.

8. **Verify NVMe Drives**:
   - Confirm the presence of 2x 2TB NVMe drives and 1x 4TB NVMe drive using `lsblk`.
     ```bash
     lsblk -d -o NAME,SIZE
     ```
   - Expected output should show three NVMe drives (e.g., `nvme0n1`, `nvme1n1` ~2TB each, `nvme2n1` ~4TB).

9. **Ensure Internet Connectivity**:
   - Verify internet access for package downloads.
     ```bash
     ping -c 4 <dns-server>
     ```
   - Ensure the DNS server (e.g., `8.8.8.8`) and gateway (e.g., `192.168.1.1`) are reachable.

## Running the Scripts

After completing the pre-configuration steps, run the scripts in the following order as the `root` user. After the admin user is created, switch to the new user for subsequent steps.

1. **Create Admin User**:
   - Run `proxmox_create_admin_user.sh` to create a non-root admin user with sudo and Proxmox privileges.
     ```bash
     sudo /usr/local/bin/proxmox_create_admin_user.sh --username <admin-user> --ssh-port <ssh-port>
     ```
     Replace `<admin-user>` with your chosen username (e.g., `adminuser`) and `<ssh-port>` with your preferred SSH port (e.g., `2222`).
   - After successful execution, log out and log in as the new user:
     ```bash
     ssh <admin-user>@<server-ip> -p <ssh-port>
     ```

2. **Switch to Admin User**:
   - Log in as the new admin user via SSH.
     ```bash
     ssh <admin-user>@<server-ip> -p <ssh-port>
     ```

3. **Configure ZFS, NFS, and Samba**:
   - As the `<admin-user>` user, run `proxmox_setup_zfs_nfs_samba.sh` to set up ZFS pools and shared storage.
     ```bash
     sudo /usr/local/bin/proxmox_setup_zfs_nfs_samba.sh --username <admin-user>
     ```

4. **Configure NVIDIA GPU Virtualization**:
   - Run `proxmox_setup_nvidia_gpu_virt.sh` to configure GPU passthrough.
     ```bash
     sudo /usr/local/bin/proxmox_setup_nvidia_gpu_virt.sh --no-reboot
     ```
   - Reboot the server unless `--no-reboot` is used:
     ```bash
     sudo reboot
     ```

5. **Create LXC/VM User**:
   - Run `proxmox_create_lxc_user.sh` for each LXC container or VM user.
     ```bash
     sudo /usr/local/bin/proxmox_create_lxc_user.sh --username <lxc-user>
     ```
     Replace `<lxc-user>` with the desired username (e.g., `lxcuser`).

## Post-Setup Verification

- **Check ZFS Pools**:
  ```bash
  zpool status quickOS
  zpool status fastData
  ```

- **Test NFS Mounts**:
  ```bash
  mount -t nfs <server-ip>:/fastData/models /mnt/models
  ```

- **Test Samba Access**:
  ```bash
  smbclient -L //<server-ip> -U <admin-user>
  ```

- **Verify GPU**:
  ```bash
  nvidia-smi
  ```

- **Access Proxmox Web Interface**:
  - Open `https://<server-ip>:8006` in a browser and log in with the admin user credentials.

- **Check Logs**:
  ```bash
  tail -f /var/log/proxmox_setup.log
  ```

## Additional Resources

- For detailed script descriptions and advanced configurations, see [scripts/README-scripts.markdown](scripts/README-scripts.markdown).
- For hardware specifications, see [notes_server_hardware.markdown](notes_server_hardware.markdown).
- For Proxmox VE installation settings, see [notes_proxmox_install_settings.markdown](notes_proxmox_install_settings.markdown).
- For storage configuration details, see [notes_proxmox_storage_config.markdown](notes_proxmox_storage_config.markdown).

## Contact

For issues or enhancements, contact me at @ Heads@ThinkHeads.ai (eventually, I'll get there).