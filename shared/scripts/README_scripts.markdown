This repository contains scripts to configure a Proxmox VE server (hostname: `phoenix.example.com`) for virtualization, storage, and GPU passthrough. The scripts are designed for a high-performance home-lab server with AMD CPU, NVIDIA 5060 TI GPUs, and NVMe storage, supporting AI/ML workloads, containers, and VMs.

## Purpose

The scripts automate the setup of a Proxmox VE environment, including repository configuration, admin user creation, ZFS storage pools, NFS/Samba sharing, NVIDIA GPU virtualization, and LXC/VM user setup. They are modular, robust, and include error handling, logging, system updates, and command-line argument support for automation.

## Prerequisites

Before running the scripts, ensure the following requirements are met:

- **Operating System**: Proxmox VE 8.x (based on Debian 12 Bookworm) installed on 2x 240GB Crucial BX500 SSDs (ZFS mirror, 180GB allocated per SSD).
- **Hardware**:
  - AMD CPU (e.g., AMD 7600).
  - 2x NVIDIA 5060 TI GPUs (PCIe 5.0 x8).
  - 2x 2TB Samsung 990 EVO Plus NVMe (for ZFS mirror, `quickOS`).
  - 1x 4TB Samsung 990 EVO Plus NVMe (for shared storage, `fastData`).
  - 96GB DDR5 RAM.
  - 10GbE Ethernet interface.
- **Network**:
  - Static IP: `10.0.0.13`.
  - Gateway: `10.0.0.1`.
  - DNS: `8.8.8.8`.
  - Subnet: `10.0.0.0/24`.
- **Software**:
  - Internet access for package downloads (e.g., NVIDIA drivers, CUDA).
  - `wget` installed (included by default in Proxmox VE).
- **Permissions**: Initial login as `root` user via SSH or console.
- **Storage**: NVMe drives must be visible via `lsblk` (2x 2TB for mirror, 1x 4TB for standalone).

## Pre-Configuration Steps

Follow these steps in order to prepare the server before running the setup scripts. All commands are executed as the `root` user unless otherwise specified.

1. **Log in as root**:
   - Access the server via SSH (`ssh root@10.0.0.13`) or console.

2. **Download and Extract Scripts**:
   - Download the script tarball using `wget` and extract it.  Check and change repo version as needed.
     ```bash
     wget https://github.com/SirHeads/thinkheads-ai-ragdocs-IT/archive/refs/tags/v0.1.07.tar.gz -O /tmp/proxmox-scripts.tar.gz
     tar -xzf /tmp/proxmox-scripts.tar.gz -C /tmp
     ```

3. **Copy Scripts to `/usr/local/bin`**:
   - Create the target directory and copy the scripts. Check version number in file path.
     ```bash
     mkdir -p /usr/local/bin
     cp /tmp/thinkheads-ai-ragdocs-IT-0.1.07/shared/scripts/common.sh /tmp/thinkheads-ai-ragdocs-IT-0.1.07/shared/scripts/proxmox_configure_repos.sh /tmp/thinkheads-ai-ragdocs-IT-0.1.07/shared/scripts/proxmox_create_admin_user.sh /tmp/thinkheads-ai-ragdocs-IT-0.1.07/shared/scripts/proxmox_setup_zfs_nfs_samba.sh /tmp/thinkheads-ai-ragdocs-IT-0.1.07/shared/scripts/proxmox_setup_nvidia_gpu_virt.sh /tmp/thinkheads-ai-ragdocs-IT-0.1.07/shared/scripts/proxmox_create_lxc_user.sh /usr/local/bin/
     ```

4. **Set Script Permissions**:
   - Make the scripts executable.
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
   - Ensure the log file directory and file are accessible, and varify the log file is writable:
     ```bash
     mkdir -p /var/log
     touch /var/log/proxmox_setup.log
     chmod 664 /var/log/proxmox_setup.log
     echo "Test log entry" >> /var/log/proxmox_setup.log
     cat /var/log/proxmox_setup.log
     ```
   - If the test entry is visible, the log file is correctly configured.

7. **Verify NVMe Drives**:
   - Confirm the presence of 2x 2TB NVMe drives and 1x 4TB NVMe drive using `lsblk`.
     ```bash
     lsblk -d -o NAME,SIZE
     ```
   - Expected output should show three NVMe drives (e.g., `nvme0n1`, `nvme1n1` ~2TB each, `nvme2n1` ~4TB).

8. **Ensure Internet Connectivity**:
   - Verify internet access for package downloads.
     ```bash
     ping -c 4 8.8.8.8
     ```
   - Ensure the DNS server (`8.8.8.8`) and gateway (`10.0.0.1`) are reachable.

## Running the Scripts

After completing the pre-configuration steps, run the scripts in the following order. Start as the `root` user, then switch to the admin user after creating it.

1. **Configure Repositories**:
   - Run `proxmox_configure_repos.sh` to set up the Proxmox VE no-subscription repository and update the system.
     ```bash
     /usr/local/bin/proxmox_configure_repos.sh
     ```
   - Reboot unless `--no-reboot` is used:
     ```bash
     reboot
     ```

2. **Create Admin User**:
   - Run `proxmox_create_admin_user.sh` to create a non-root admin user with sudo and Proxmox privileges.
     ```bash
     /usr/local/bin/proxmox_create_admin_user.sh --username <admin-user> --ssh-port <ssh-port> [--no-reboot]
     ```
     Replace `<admin-user>` with your chosen username (e.g., `adminuser`) and `<ssh-port>` with your preferred SSH port (e.g., `2222`).
   - Reboot unless `--no-reboot` is used:
     ```bash
     reboot
     ```
   - After successful execution, log out and log in as the new user:
     ```bash
     ssh <admin-user>@10.0.0.13 -p <ssh-port>
     ```

3. **Switch to Admin User**:
   - Log in as the new admin user via SSH.
     ```bash
     ssh <admin-user>@10.0.0.13 -p <ssh-port>
     ```

4. **Configure ZFS, NFS, and Samba**:
   - As the `<admin-user>` user, run `proxmox_setup_zfs_nfs_samba.sh` to set up ZFS pools (`quickOS` for 2x 2TB NVMe mirror, `fastData` for 4TB NVMe) and shared storage.
     ```bash
     /usr/local/bin/proxmox_setup_zfs_nfs_samba.sh --username <admin-user> [--no-reboot]
     ```
   - Reboot unless `--no-reboot` is used:
     ```bash
     reboot
     ```

5. **Configure NVIDIA GPU Virtualization**:
   - Run `proxmox_setup_nvidia_gpu_virt.sh` to configure GPU passthrough (NVIDIA driver 575.57.08, CUDA 12.9).
     ```bash
     /usr/local/bin/proxmox_setup_nvidia_gpu_virt.sh --no-reboot
     ```
   - Reboot unless `--no-reboot` is used:
     ```bash
     reboot
     ```

6. **Create LXC/VM User**:
   - Run `proxmox_create_lxc_user.sh` for each LXC container or VM user.
     ```bash
     /usr/local/bin/proxmox_create_lxc_user.sh --username <lxc-user>
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
  mount -t nfs 10.0.0.13:/fastData/models /mnt/models
  ```

- **Test Samba Access**:
  ```bash
  smbclient -L //10.0.0.13 -U <admin-user>
  ```

- **Verify GPU**:
  ```bash
  nvidia-smi
  ```

- **Access Proxmox Web Interface**:
  - Open `https://10.0.0.13:8006` in a browser and log in with the admin user credentials.

- **Check Logs**:
  ```bash
  tail -f /var/log/proxmox_setup.log
  ```

## Script Details

1. **`common.sh`** (Version: 1.1.0):
   - Contains shared functions for error handling, logging to `/var/log/proxmox_setup.log`, and package checks.
   - Sourced by all other scripts for consistency.
   - Logs all actions with timestamps for debugging.

2. **`proxmox_configure_repos.sh`** (Version: 1.1.0):
   - Disables Proxmox VE production and Ceph repositories.
   - Enables the no-subscription repository in `/etc/apt/sources.list`.
   - Updates and upgrades the system (`apt-get update`, `apt-get upgrade -y`, `proxmox-boot-tool refresh`, `update-initramfs -u`).
   - Supports `--no-reboot` to skip reboot prompt.
   - Requires internet access.

3. **`proxmox_create_admin_user.sh`** (Version: 1.4.0):
   - Creates a non-root Linux user with sudo and Proxmox admin privileges.
   - Installs `sudo` package.
   - Configures SSH with a customizable port (default 22).
   - Updates and upgrades the system (`apt-get update`, `apt-get upgrade -y`, `proxmox-boot-tool refresh`, `update-initramfs -u`).
   - Supports `--username`, `--password`, `--ssh-key`, `--ssh-port`, and `--no-reboot` arguments.
   - Interactive mode prompts for missing inputs.

4. **`proxmox_setup_zfs_nfs_samba.sh`** (Version: 1.5.0):
   - Prompts the user to select two NVMe drives for the `quickOS` ZFS mirror pool (VMs/containers) and one for the `fastData` ZFS pool (datasets: `models`, `projects`, `backups`, `isos`).
   - Configures ZFS ARC cache size (prompts for size in MB, default ~9000MB).
   - Sets up NFS exports for `10.0.0.0/24`.
   - Configures Samba with user checks and shares for `fastData` datasets.
   - Opens firewall ports (NFS: 2049, 111; Samba: 137–139, 445).
   - Updates and upgrades the system (`apt-get update`, `apt-get upgrade -y`, `proxmox-boot-tool refresh`, `update-initramfs -u`).
   - Uses `lsblk` to list NVMe drives for selection.
   - Supports `--username` and `--no-reboot` arguments.

5. **`proxmox_setup_nvidia_gpu_virt.sh`** (Version: 1.1.0):
   - Installs NVIDIA driver 575.57.08 and CUDA 12.9.
   - Configures VFIO for GPU passthrough on AMD CPU.
   - Verifies GPUs via `lspci`.
   - Supports `--no-reboot` to skip reboot prompt.
   - Requires internet access.

6. **`proxmox_create_lxc_user.sh`** (Version: 1.0.0):
   - Creates Linux users for LXC containers/VMs with Samba and NFS access.
   - Supports `--username` argument.
   - Requires Samba service from `proxmox_setup_zfs_nfs_samba.sh`.

## Execution Order

1. `proxmox_configure_repos.sh`
2. `proxmox_create_admin_user.sh`
3. `proxmox_setup_zfs_nfs_samba.sh`
4. `proxmox_setup_nvidia_gpu_virt.sh`
5. Create LXC containers/VMs via Proxmox web interface (`https://10.0.0.13:8006`).
6. `proxmox_create_lxc_user.sh` (for each container/VM user).

## Post-Setup Tasks

- **Configure Containers/VMs**:
  - Mount `/fastData/models` in Ollama containers/VMs (set `OLLAMA_MODELS=/fastData/models`).
  - Use `/fastData/projects` for datasets, `/fastData/backups` for backups, and `/fastData/isos` for ISO images.
- **Security**:
  - Consider `root_squash` in `/etc/exports` for NFS to restrict root access.
  - Restrict SSH to specific IPs:
    ```bash
    firewall-cmd --add-rich-rule='rule family="ipv4" source address="<your-ip>" port port="<ssh-port>" protocol="tcp" accept' --permanent
    ```
- **Monitoring**:
  - Check logs: `tail -f /var/log/proxmox_setup.log`
  - Monitor ZFS: `zpool status; arc_summary`

## Notes

- **Logging**: All scripts log to `/var/log/proxmox_setup.log`. Review for errors or warnings.
- **Reboot**: Required after each script unless `--no-reboot` is used.
- **Dependencies**: Internet access required for `apt` and NVIDIA downloads.
- **Hardware**: Assumes 2x 2TB NVMe, 1x 4TB NVMe, and NVIDIA 5060 TI GPUs. NVMe selection is interactive via `lsblk`.
- **Automation**: Use command-line arguments for scripted deployments (e.g., CI/CD pipelines).

## Additional Resources

- For hardware specifications, see [notes_server_hardware.markdown](notes_server_hardware.markdown).
- For Proxmox VE installation settings, see [notes_proxmox_install_settings.markdown](notes_proxmox_install_settings.markdown).
- For storage configuration details, see [notes_proxmox_storage_config.markdown](notes_proxmox_storage_config.markdown).

## Contact

For issues or enhancements, contact the project maintainer at `<maintainer-email>` (e.g., `admin@example.com`).