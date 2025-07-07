# ThinkHeads.ai Proxmox VE Server Setup

Welcome to the **ThinkHeads.ai Proxmox VE Server Setup** repository! This project showcases a robust, scripted deployment of a Proxmox Virtual Environment (VE) server named **Phoenix**, designed to host **AI, machine learning, and multiple development environments** with high performance and flexibility. Built on powerful hardware and leveraging ZFS storage, NVIDIA GPU virtualization, and cross-platform NFS/Samba sharing, this setup supports local server operations with future cloud integration potential.

This repository contains configuration files, scripts, and documentation to automate the setup of the Phoenix server, demonstrating expertise in system administration, virtualization, and infrastructure automation. The project is tailored for **AI/ML workloads** (e.g., Ollama model hosting), **development environments** (LXC containers and VMs), and **data management** (shared storage for datasets, backups, and ISOs).

## Project Goals

The primary goal is to create a **high-performance, local Proxmox VE server** to:
- **Host AI/ML Workloads**: Run Ollama containers/VMs with shared model storage, leveraging dual NVIDIA 5060 TI GPUs for accelerated computation.
- **Support Development Environments**: Provide isolated LXC containers and VMs for multiple programming and testing environments.
- **Enable Scalable Storage**: Use ZFS for redundant (2x 2TB NVMe mirror) and shared (4TB NVMe) storage, accessible via NFS/Samba across Windows, Linux, and macOS.
- **Automate Setup**: Deliver a repeatable, scripted process for environment creation, ensuring consistency and ease of deployment.
- **Prepare for Growth**: Design a flexible infrastructure with upgrade paths for CPU, GPU, and storage, supporting future cloud integration.

This project reflects a professional approach to infrastructure design, with robust error handling, logging, and documentation, making it an excellent showcase for system administration and DevOps skills.

## Hardware Overview

The Phoenix server is built with high-end components optimized for virtualization and AI/ML workloads:

- **Server Name**: Phoenix (Hostname: `Phoenix.ThinkHeads.ai`, IP: `10.0.0.13`)
- **CPU**: AMD 7600 (overclockable to ~7600X performance)
- **RAM**: 96GB DDR5 G.SKILL Flare X5 (5200 MHz)
- **Storage**:
  - 2x 240GB Crucial BX500 SSD (ZFS mirror, Proxmox VE installation)
  - 2x 2TB Samsung 990 EVO Plus NVMe (ZFS mirror, container/VM OS)
  - 1x 4TB Samsung 990 EVO Plus NVMe (ZFS single, shared storage)
- **GPUs**: 2x NVIDIA 5060 TI 16GB (PCIe 5.0 x8, virtualized for AI/ML)
- **Network**: 10GbE Ethernet for high-speed access
- **Motherboard**: Gigabyte B850 AI TOPP (PCIe 5.0, NVMe support)
- **Power Supply**: ASUS TUF Gaming 1200W 80 Plus Gold

This hardware supports demanding workloads with room for upgrades (e.g., AMD 10950X3D CPU, larger NVMe drives, or higher-end GPUs). See `docs/server_hardware_markdown` for details.

## Repository Structure

The repository is organized for clarity and ease of use:

- **`docs/`**: Configuration and hardware documentation
  - `notes_proxmox_install_settings.markdown`: Proxmox VE installation details (ZFS mirror, network config)
  - `notes_proxmox_storage_config.markdown`: ZFS storage setup for container/VM and shared storage
  - `notes_server_hardware_markdown`: Hardware specifications and upgrade paths
- **`scripts/`**: Automation scripts for Proxmox VE setup
  - `common.sh`: Shared functions for error handling and logging
  - `proxmox_create_admin_user.sh`: Creates a non-root admin user with SSH and Proxmox privileges
  - `proxmox_setup_zfs_nfs_samba.sh`: Configures ZFS pools, NFS/Samba, and firewall
  - `proxmox_setup_nvidia_gpu_virt.sh`: Sets up NVIDIA GPU virtualization (driver 575.57.08, CUDA 12.9)
  - `proxmox_create_lxc_user.sh`: Creates users for LXC containers/VMs with NFS/Samba access
  - `README.md`: Detailed instructions for script usage
- **`README.TXT`**: This file, providing a high-level overview


## Setup Process

The `scripts/` directory contains a set of Bash scripts to automate the Proxmox VE environment setup. These scripts are modular, include robust error handling, and support command-line arguments for automation. For detailed instructions, see `scripts/README.md`. A high-level overview:

1. **Prepare Scripts**:
   - Copy scripts to `/usr/local/bin` and make executable:
     ```bash
     sudo cp scripts/*.sh /usr/local/bin/
     sudo chmod +x /usr/local/bin/*.sh
     ```
   - Configure log rotation for `/var/log/proxmox_setup.log` (see `scripts/README.md`).

2. **Execution Order**:
   - **Step 1**: `proxmox_create_admin_user.sh` - Creates an admin user (e.g., `heads`) with SSH (custom port) and Proxmox access.
   - **Step 2**: `proxmox_setup_zfs_nfs_samba.sh` - Sets up ZFS pools (`tank` for VMs, `shared` for models/projects/backups/isos), NFS/Samba, and firewall.
   - **Step 3**: `proxmox_setup_nvidia_gpu_virt.sh` - Configures NVIDIA GPUs for virtualization.
   - **Step 4**: Create LXC containers/VMs via Proxmox web interface (`https://10.0.0.13:8006`).
   - **Step 5**: `proxmox_create_lxc_user.sh` - Creates users for containers/VMs with NFS/Samba access.

3. **Key Features**:
   - **ZFS Storage**: Redundant 2TB mirror (`tank`) for VM/container OS, 4TB single pool (`shared`) for shared storage.
   - **NFS/Samba**: Cross-platform access to `/shared/models`, `/shared/projects`, `/shared/backups`, `/shared/isos`.
   - **GPU Virtualization**: NVIDIA driver 575.57.08 and CUDA 12.9 for AI/ML workloads.
   - **Automation**: Scripts support non-interactive execution (e.g., `./proxmox_create_admin_user.sh --username heads --ssh-port 2222`).

## Why This Project?

This setup demonstrates expertise in:
- **System Administration**: Configuring Proxmox VE, ZFS, NFS, Samba, and firewalld.
- **Virtualization**: Setting up LXC containers, VMs, and GPU passthrough for AI/ML.
- **Automation**: Writing robust, modular Bash scripts with error handling and logging.
- **Performance Optimization**: Leveraging NVMe, 10GbE, and ZFS for high-speed, reliable storage.
- **Scalability**: Designing for future upgrades and cloud integration.

The scripted approach ensures repeatability, making it ideal for production environments or rapid redeployment. The documentation and logging provide transparency, while the hardware supports cutting-edge AI/ML and development tasks.

## Getting Started

1. **Clone the Repository**:
   ```bash
   git clone <repository-url>
   cd <repository-name>
   ```

2. **Review Documentation**:
   - Read `docs/proxmox_install_settings.markdown` and `docs/proxmox_storage_config.markdown` for server setup details.
   - Check `docs/server_hardware_markdown` for hardware context.

3. **Follow Script Instructions**:
   - See `scripts/README.md` for detailed setup steps, including file placement, execution order, and verification commands.

4. **Post-Setup**:
   - Access Proxmox: `https://10.0.0.13:8006`
   - Mount shared storage: `mount -t nfs 10.0.0.13:/shared/models /mnt/models`
   - Verify GPUs: `nvidia-smi`
   - Monitor logs: `tail -f /var/log/proxmox_setup.log`

## Security and Maintenance

- **Security**:
  - Restrict NFS to `10.0.0.0/24` subnet.
  - Use non-standard SSH ports and firewall rules (e.g., `firewall-cmd --add-port=2222/tcp`).
  - Consider `root_squash` for NFS to enhance security.
- **Maintenance**:
  - Monitor ZFS health: `zpool status tank; zpool status shared`
  - Schedule ZFS snapshots: `zfs snapshot shared/models@daily-$(date +%Y%m%d)`
  - Update Proxmox and NVIDIA drivers regularly.

## Future Enhancements

- Add orchestration script to run all scripts in sequence.
- Implement automated backups to offsite storage (e.g., Backblaze B2).
- Integrate with cloud services for hybrid AI/ML workloads.
- Expand monitoring with tools like Prometheus and Grafana.

## Contact

For questions or contributions, contact [Your Name] at [Your Email]. This project is a testament to my passion for building scalable, automated infrastructure for AI and development. I welcome feedback and opportunities to collaborate!