# Proxmox VE Setup Scripts for Phoenix Server

This repository contains scripts to configure a Proxmox VE server named Phoenix (hostname: `Phoenix.ThinkHeads.ai`, IP: `10.0.0.13`) for virtualization, storage, and GPU passthrough. The scripts are designed for a high-performance server with AMD CPU, NVIDIA 5060 TI GPUs, and NVMe storage, supporting AI/ML workloads, containers, and VMs.

## Overview

The scripts automate the setup of a Proxmox VE environment, including repository configuration, admin user creation, ZFS storage setup, NFS/Samba sharing, NVIDIA GPU virtualization, and LXC/VM user setup. They are modular, robust, and include error handling, logging, and command-line argument support for automation.

### Scripts and Their Purposes

1. `common.sh`: Shared functions for error handling, logging, and package checks. Sourced by all other scripts.
2. `proxmox_configure_repos.sh`: Disables Proxmox VE production and Ceph repositories, enables the no-subscription repository, and updates package lists.
3. `proxmox_create_admin_user.sh`: Creates a non-root Linux user with sudo and Proxmox admin privileges, configures SSH with a customizable port, and ensures `sudo` and `samba` packages are installed.
4. `proxmox_setup_zfs_nfs_samba.sh`: Sets up ZFS pools (`quickOS` for 2x 2TB NVMe mirror, `fastData` for 4TB NVMe), configures NFS and Samba for shared storage, and opens firewall ports. Uses `lsblk` for reliable NVMe drive identification.
5. `proxmox_setup_nvidia_gpu_virt.sh`: Configures NVIDIA GPU virtualization (driver 575.57.08, CUDA 12.9) for passthrough to VMs, tailored for AMD CPU.
6. `proxmox_create_lxc_user.sh`: Creates a Linux user for LXC containers/VMs with Samba credentials and NFS access.

## Prerequisites

- **Operating System**: Proxmox VE 8.x (based on Debian 12 Bookworm).
- **Hardware**:
  - AMD CPU (e.g., AMD 7600).
  - 2x NVIDIA 5060 TI GPUs (PCIe 5.0 x8).
  - 2x 2TB Samsung 990 EVO Plus NVMe (for ZFS mirror, `quickOS`).
  - 1x 4TB Samsung 990 EVO Plus NVMe (for shared storage, `fastData`).
  - 2x 240GB Crucial BX500 SSD (for Proxmox VE installation, ZFS mirror).
  - 96GB DDR5 RAM.
  - 10GbE Ethernet interface.
- **Network**:
  - Static IP: `10.0.0.13`.
  - Gateway: `10.0.0.1`.
  - DNS: `1.1.1.1`.
  - Subnet: `10.0.0.0/24`.
- **Software**:
  - Proxmox VE installed on the 2x 240GB SSDs (ZFS mirror, 180GB allocated per SSD).
  - Internet access for package downloads (NVIDIA drivers, CUDA, etc.).
- **Permissions**: Scripts must be run as root (use `sudo`).

## Installation and Setup

### 1. Place the Scripts

- **Directory**: Copy all scripts to `/usr/local/bin` on the Proxmox VE server.

  ```bash
  sudo mkdir -p /usr/local/bin
  sudo cp common.sh proxmox_configure_repos.sh proxmox_create_admin_user.sh proxmox_setup_zfs_nfs_samba.sh proxmox_setup_nvidia_gpu_virt.sh proxmox_create_lxc_user.sh /usr/local/bin/
  ```

- **Permissions**: Make the scripts executable.

  ```bash
  sudo chmod +x /usr/local/bin/*.sh
  ```

### 2. Configure Log Rotation

- The scripts log to `/var/log/proxmox_setup.log`. Configure log rotation to manage log size.

- Create `/etc/logrotate.d/proxmox_setup`:

  ```bash
  sudo nano /etc/logrotate.d/proxmox_setup
  ```

  Add:

  ```
  /var/log/proxmox_setup.log {
      weekly
      rotate 4
      compress
      missingok
  }
  ```

- Verify:

  ```bash
  sudo logrotate -f /etc/logrotate.d/proxmox_setup
  ```

### 3. Run the Scripts

Execute the scripts in the following order. Each script supports command-line arguments for automation (e.g., `--username`, `--ssh-port`). Run interactively for prompts or provide arguments for non-interactive execution.

#### Step 1: Configure Repositories

- **Script**: `proxmox_configure_repos.sh`

- **Purpose**: Disables Proxmox VE production and Ceph repositories, enables the no-subscription repository, and updates APT package lists.

- **When to Run**: After Proxmox VE installation, before other configurations.

- **Example**:

  ```bash
  sudo /usr/local/bin/proxmox_configure_repos.sh
  ```

- **Output**: Updated APT sources with no-subscription repository enabled.

- **Notes**: Requires internet access for `apt update`.

#### Step 2: Create Admin User

- **Script**: `proxmox_create_admin_user.sh`

- **Purpose**: Sets up a non-root admin user with sudo privileges, SSH access (default port 22, customizable), and Proxmox admin privileges. Installs `sudo` and `samba` packages.

- **When to Run**: After repository configuration, before other configurations.

- **Example**:

  ```bash
  sudo /usr/local/bin/proxmox_create_admin_user.sh --username heads --ssh-port 2222
  ```

  - Interactive: Prompts for username, password, SSH key, and port.
  - Non-interactive: Provide `--username`, `--password`, `--ssh-key`, and `--ssh-port`.

- **Output**: SSH access (`ssh heads@10.0.0.13 -p 2222`) and Proxmox web interface (`https://10.0.0.13:8006`).

- **Notes**: Ensure the SSH port is open in the firewall (e.g., `sudo firewall-cmd --add-port=2222/tcp --permanent; sudo firewall-cmd --reload`).

#### Step 3: Configure ZFS, NFS, and Samba

- **Script**: `proxmox_setup_zfs_nfs_samba.sh`

- **Purpose**: Configures ZFS pools (`quickOS` for 2x 2TB NVMe mirror, `fastData` for 4TB NVMe), sets up NFS and Samba for shared storage (`/fastData/models`, `/fastData/projects`, `/fastData/backups`, `/fastData/isos`), and opens firewall ports (NFS: 2049, 111; Samba: 137–139, 445). Uses `lsblk` to identify NVMe drives by size (2x 2TB for mirror, 1x 4TB for standalone).

- **When to Run**: After admin user setup, before GPU configuration.

- **Example**:

  ```bash
  sudo /usr/local/bin/proxmox_setup_zfs_nfs_samba.sh --username heads
  ```

  - Interactive: Prompts for Samba username and password.
  - Non-interactive: Provide `--username`.

- **Output**: NFS mounts (`mount -t nfs 10.0.0.13:/fastData/<dataset> /mnt/<dataset>`) and Samba shares (`\\10.0.0.13\<dataset>`).

- **Notes**: Validates exactly two 2TB NVMe drives and one 4TB NVMe drive. Uses \~1/3 of RAM (32GB of 96GB) for ZFS ARC cache. Enhanced Samba setup checks for existing users and handles errors.

#### Step 4: Configure NVIDIA GPU Virtualization

- **Script**: `proxmox_setup_nvidia_gpu_virt.sh`

- **Purpose**: Installs NVIDIA driver 575.57.08 and CUDA 12.9, configures GPU passthrough for VMs, and sets up VFIO modules for AMD CPU.

- **When to Run**: After ZFS/NFS/Samba setup, before creating containers/VMs.

- **Example**:

  ```bash
  sudo /usr/local/bin/proxmox_setup_nvidia_gpu_virt.sh --no-reboot
  ```

  - Interactive: Prompts for reboot (60s timeout).
  - Non-interactive: Use `--no-reboot` to skip reboot prompt.

- **Output**: GPU virtualization ready; reboot required unless `--no-reboot` is used.

- **Notes**: Verifies NVIDIA 5060 TI GPUs via `lspci`. Requires internet for NVIDIA repository.

#### Step 5: Create LXC/VM User

- **Script**: `proxmox_create_lxc_user.sh`

- **Purpose**: Creates a Linux user for LXC containers/VMs with Samba credentials and NFS access.

- **When to Run**: After creating LXC containers or VMs, post-ZFS/NFS/Samba setup.

- **Example**:

  ```bash
  sudo /usr/local/bin/proxmox_create_lxc_user.sh --username lxcuser
  ```

  - Interactive: Prompts for username and Samba password.
  - Non-interactive: Provide `--username`.

- **Output**: User with UID, Samba access (`\\10.0.0.13\<dataset>`), and NFS access (`mount -t nfs 10.0.0.13:/fastData/<dataset> /mnt/<dataset>`).

- **Notes**: Run once per container/VM user. Requires Samba service (from `proxmox_setup_zfs_nfs_samba.sh`).

### Execution Order

1. `proxmox_configure_repos.sh`
2. `proxmox_create_admin_user.sh`
3. `proxmox_setup_zfs_nfs_samba.sh`
4. `proxmox_setup_nvidia_gpu_virt.sh`
5. Create LXC containers/VMs via Proxmox web interface (`https://10.0.0.13:8006`).
6. `proxmox_create_lxc_user.sh` (for each container/VM user).

### Post-Setup Tasks

- **Verify Setup**:
  - Check ZFS pools: `zpool status quickOS; zpool status fastData`
  - Test NFS mounts: `mount -t nfs 10.0.0.13:/fastData/models /mnt/models`
  - Test Samba: `smbclient -L //10.0.0.13 -U heads`
  - Verify GPU: `nvidia-smi; nvtop`
  - Access Proxmox: `https://10.0.0.13:8006`
- **Configure Containers/VMs**:
  - Mount `/fastData/models` in Ollama containers/VMs (set `OLLAMA_MODELS=/fastData/models`).
  - Use `/fastData/projects` for datasets, `/fastData/backups` for Proxmox backups, and `/fastData/isos` for ISO images.
- **Security**:
  - Consider `root_squash` in `/etc/exports` for NFS to restrict root access.
  - Restrict SSH to specific IPs: `firewall-cmd --add-rich-rule='rule family="ipv4" source address="YOUR_IP" port port="2222" protocol="tcp" accept' --permanent`
- **Monitoring**:
  - Check logs: `tail -f /var/log/proxmox_setup.log`
  - Monitor ZFS: `zpool status; arc_summary`

## Notes

- **Logging**: All scripts log to `/var/log/proxmox_setup.log`. Review for errors or warnings.
- **Reboot**: Required after `proxmox_setup_nvidia_gpu_virt.sh` to apply GPU and kernel changes.
- **Dependencies**: Ensure internet access for `apt` and NVIDIA repository downloads.
- **Hardware**: Scripts assume specific NVMe drives (2x 2TB, 1x 4TB) and NVIDIA 5060 TI GPUs. NVMe identification uses `lsblk` for reliability.
- **Automation**: Use command-line arguments for scripted deployments (e.g., in CI/CD pipelines).

## Contact

For issues or enhancements, contact Heads at SirHeads@ThinkHeads.ai (pending).