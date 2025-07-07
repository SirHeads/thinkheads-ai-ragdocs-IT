# Phoenix Server Proxmox VE Setup Scripts

This repository contains scripts to configure a Proxmox VE server (hostname: `phoenix.example.com`) for virtualization, storage, and GPU passthrough. The scripts are designed for a high-performance home-lab server with AMD CPU, NVIDIA 5060 TI GPUs, and NVMe storage, supporting AI/ML workloads, containers, and VMs.

## Purpose

The scripts automate the setup of a Proxmox VE environment, including repository configuration, admin user creation, ZFS storage pools, NFS/Samba sharing, NVIDIA GPU virtualization, and LXC/VM user setup. They are modular, robust, and include error handling, logging, and command-line argument support for automation.

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
  - Static IP: `<server-ip>` (e.g., 192.168.1.100).
  - Gateway: `<gateway-ip>` (e.g., 192.168.1.1).
  - DNS: `<dns-server>` (e.g., 8.8.8.8).
  - Subnet: `<subnet>` (e.g., 192.168.1.0/24).
- **Software**:
  - Internet access for package downloads (e.g., NVIDIA drivers, CUDA).
  - Git installed (`apt install git`).
- **Permissions**: Initial login as `root` user via SSH or console.
- **Storage**: NVMe drives must be visible via `lsblk` (2x 2TB for mirror, 1x 4TB for standalone).

## Pre-Configuration Steps

Follow these steps in order to prepare the server before running the setup scripts. All commands are executed as the `root` user unless otherwise specified.

1. **Log in as root**:
   - Access the server via SSH (`ssh root@<server-ip>`) or console間で

2. **Install Git**:
   - Ensure `git` is installed for cloning the repository.
     ```bash
     apt update
     apt install -y git
     ```

3. **Clone the Repository**:
女人

4. **Copy Scripts to `/usr/local/bin`**:
   - Create the target directory and copy the scripts.
     ```bash
     sudo mkdir -p /usr/local/bin
     sudo cp common.sh proxmox_configure_repos.sh proxmox_create_admin_user.sh proxmox_setup_zfs_nfs_samba.sh proxmox_setup_nvidia_gpu_virt.sh proxmox_create_lxc_user.sh /usr/local/bin/
     ```

5. **Set Script Permissions**:
   - Make the scripts executable.
     ```bash
     sudo chmod +x /usr/local/bin/*.sh
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

After completing the pre-configuration steps, run the scripts in the following order. Start as the `root` user, then switch to the admin user after creating it.

1. **Configure Repositories**:
   - Run `proxmox_configure_repos.sh` to set up the Proxmox VE no-subscription repository.
     ```bash
     sudo /usr/local/bin/proxmox_configure_repos.sh
     ```

2. **Create Admin User**:
   - Run `proxmox_create_admin_user.sh` to create a non-root admin user with sudo and Proxmox privileges.
     ```bash
     sudo /usr/local/bin/proxmox_create_admin_user.sh --username <admin-user> --ssh-port <ssh-port>
     ```
     Replace `<admin-user>` with your chosen username (e.g., `adminuser`) and `<ssh-port>` with your preferred SSH port (e.g., `2222`).
   - After successful execution, log out and log in as the new user:
     ```bash
     ssh <admin-user>@<server-ip> -p <ssh-port>
     ```

3. **Switch to Admin User**:
   - Log in as the new admin user via SSH.
     ```bash
     ssh <admin-user>@<server-ip> -p <ssh-port>
     ```

4. **Configure ZFS, NFS, and Samba**:
   - As the `<admin-user>` user, run `proxmox_setup_zfs_nfs_samba.sh` to set up ZFS pools (`quickOS` for 2x 2TB NVMe mirror, `fastData` for 4TB NVMe) and shared storage.
     ```bash
     sudo /usr/local/bin/proxmox_setup_zfs_nfs_samba.sh --username <admin-user>
     ```

5. **Configure NVIDIA GPU Virtualization**:
   - Run `proxmox_setup_nvidia_gpu_virt.sh` to configure GPU passthrough (NVIDIA driver 575.57.08, CUDA 12.9).
     ```bash
     sudo /usr/local/bin/proxmox_setup_nvidia_gpu_virt.sh --no-reboot
     ```
   - Reboot the server unless `--no-reboot` is used:
     ```bash
     sudo reboot
     ```

6. **Create LXC/VM User**:
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

## Script Details

1. **`common.sh`**:
   - Contains shared functions for error handling, logging to `/var/log/proxmox_setup.log`, and package checks.
   - Sourced by all other scripts for consistency.
   - Logs all actions with timestamps for debugging.

2. **`proxmox_configure_repos.sh`**:
   - Disables Proxmox VE production and Ceph repositories.
   - Enables the no-subscription repository in `/etc/apt/sources.list`.
   - Updates APT package lists.
   - Requires internet access.

3. **`proxmox_create_admin_user.sh`**:
   - Creates a non-root Linux user with sudo and Proxmox admin privileges.
   - Installs `sudo` and `samba` packages.
   - Configures SSH with a customizable port (default 22).
   - Supports `--username`, `--password`, `--ssh-key`, and `--ssh-port` arguments.
   - Interactive mode prompts for missing inputs.

4. **`proxmox_setup_zfs_nfs_samba.sh`**:
   - Creates ZFS pool `quickOS` (2x 2TB NVMe mirror) for VMs/containers.
   - Creates ZFS pool `fastData` (4TB NVMe) with datasets: `models`, `projects`, `backups`, `isos`.
   - Configures NFS exports for `<subnet>` (e.g., `192.168.1.0/24`).
   - Sets up Samba with user checks and error handling.
   - Opens firewall ports (NFS: 2049, 111; Samba: 137–139, 445).
   - Uses `lsblk` to validate two 2TB and one 4TB NVMe drives.
   - Sets ZFS ARC cache to ~1/3 of RAM (32GB of 96GB).
   - Supports `--username` argument.

5. **`proxmox_setup_nvidia_gpu_virt.sh`**:
   - Installs NVIDIA driver 575.57.08 and CUDA 12.9.
   - Configures VFIO for GPU passthrough on AMD CPU.
   - Verifies GPUs via `lspci`.
   - Supports `--no-reboot` to skip reboot prompt.
   - Requires internet access.

6. **`proxmox_create_lxc_user.sh`**:
   - Creates Linux users for LXC containers/VMs with Samba and NFS access.
   - Supports `--username` argument.
   - Requires Samba service from `proxmox_setup_zfs_nfs_samba.sh`.

## Execution Order

1. `proxmox_configure_repos.sh`
2. `proxmox_create_admin_user.sh`
3. `proxmox_setup_zfs_nfs_samba.sh`
4. `proxmox_setup_nvidia_gpu_virt.sh`
5. Create LXC containers/VMs via Proxmox web interface (`https://<server-ip>:8006`).
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
- **Reboot**: Required after `proxmox_setup_nvidia_gpu_virt.sh` unless `--no-reboot` is used.
- **Dependencies**: Internet access required for `apt` and NVIDIA downloads.
- **Hardware**: Assumes 2x 2TB NVMe, 1x 4TB NVMe, and NVIDIA 5060 TI GPUs. NVMe identification uses `lsblk`.
- **Automation**: Use command-line arguments for scripted deployments (e.g., CI/CD pipelines).

## Additional Resources

- For hardware specifications, see [notes_server_hardware.markdown](notes_server_hardware.markdown).
- For Proxmox VE installation settings, see [notes_proxmox_install_settings.markdown](notes_proxmox_install_settings.markdown).
- For storage configuration details, see [notes_proxmox_storage_config.markdown](notes_proxmox_storage_config.markdown).

## Contact

For issues or enhancements, contact the project maintainer at `<maintainer-email>` (e.g., `admin@example.com`).