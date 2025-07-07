# Proxmox Storage Configuration for Phoenix Server

## Server Overview
- **Server Name**: Phoenix
- **Hostname (FQDN)**: Phoenix.ThinkHeads.ai
- **Hardware Context**:
  - 2x 2 TB Samsung 990 EVO Plus NVMe (PCIe 4.0 x4, CPU-attached) for container/VM OS and primary drives
  - 1x 4 TB Samsung 990 EVO Plus NVMe (PCIe 4.0 x4, chipset-attached) for shared storage
- **Goal**: Configure ZFS mirror for 2 TB NVMes for container/VM OS and primary drives, and ZFS single drive for 4 TB NVMe with dedicated folders for shared Ollama models, VM data projects, backups, and ISOs, accessible across Windows, Linux, and macOS.

## Storage Configuration

### 2 TB NVMe Drives (Container and VM OS & Primary Drives)
- **Configuration**: ZFS Mirror (RAID1 equivalent)
- **Name: quickOS
- **Purpose**: Host Proxmox container (LXC) and VM root filesystems and primary storage
- **Setup Steps**:
  1. Identify NVMe drives: Run `lsblk` or `nvme list` to confirm drive names (e.g., `/dev/nvme0n1`, `/dev/nvme1n1`).
  2. Create ZFS pool: `zpool create -f -o ashift=12 tank mirror /dev/nvme0n1 /dev/nvme1n1`
     - `ashift=12` optimizes for 4K sector size.
  3. Create dataset for Proxmox: `zfs create tank/vms`
  4. Add to Proxmox storage: `pvesm add zfspool tank-vms -pool tank/vms -content images,rootdir`
  5. Configure properties:
     - `zfs set compression=lz4 tank/vms` (enables compression for efficiency)
     - `zfs set recordsize=128k tank/vms` (optimizes for VM/container workloads)
- **Notes**:
  - ZFS mirror provides 2 TB usable capacity with redundancy.
  - High performance due to CPU-attached PCIe 4.0 x4 lanes.
  - Suitable for LXC containers and VM disk images.

### 4 TB NVMe Drive (Shared Storage)
- **Configuration**: ZFS Single Drive with NFS Exports
- **Name: fastData
- **Purpose**: Shared storage for:
  - **Ollama Models**: Shared folder for AI models used by Ollama instances in containers/VMs
  - **Data Projects**: Storage for VM data project files (e.g., datasets, scripts)
  - **Backups**: Proxmox backups (vzdump)
  - **ISOs**: ISO images for VM installations
- **Rationale**:
  - ZFS chosen for snapshots, compression, data integrity, and cross-platform NFS sharing.
  - NFS ensures high-speed access for local containers/VMs and external Windows/Linux/macOS clients.
  - Dedicated datasets improve organization and allow per-folder snapshot policies.
- **Setup Steps**:
  1. Identify 4 TB NVMe: Run `nvme list` (e.g., `/dev/nvme2n1`).
  2. Create ZFS pool: `zpool create -f -o ashift=12 shared /dev/nvme2n1`
  3. Create datasets for specific purposes:
     - `zfs create shared/models` (Ollama models)
     - `zfs create shared/projects` (VM data projects)
     - `zfs create shared/backups` (Proxmox backups)
     - `zfs create shared/isos` (ISO images)
  4. Enable compression: `zfs set compression=lz4 shared/models shared/projects shared/backups shared/isos`
  5. Set recordsize for large files: `zfs set recordsize=1M shared/models shared/projects shared/backups shared/isos`
     - Optimizes for large files (models, datasets, backups, ISOs).
  6. Configure NFS sharing:
     - Install NFS server: `apt install nfs-kernel-server`
     - Add to `/etc/exports`:
       ```
       /shared/models 10.0.0.0/24(rw,sync,no_subtree_check,no_root_squash)
       /shared/projects 10.0.0.0/24(rw,sync,no_subtree_check,no_root_squash)
       /shared/backups 10.0.0.0/24(rw,sync,no_subtree_check,no_root_squash)
       /shared/isos 10.0.0.0/24(rw,sync,no_subtree_check,no_root_squash)
       ```
     - Apply exports: `exportfs -ra`
  7. Add to Proxmox storage:
     - Backups: `pvesm add dir shared-backups -path /shared/backups -content backup`
     - ISOs: `pvesm add dir shared-isos -path /shared/isos -content iso`
  8. Tune ZFS ARC cache: `echo "options zfs zfs_arc_max=34359738368" >> /etc/modprobe.d/zfs.conf` (limits ARC to ~32 GB of 96 GB RAM)
     - Update initramfs: `update-initramfs -u`
     - Reboot to apply.
- **Access Instructions**:
  - **Proxmox Local Access (Containers/VMs)**:
    - Mount datasets directly: `/shared/models`, `/shared/projects`, `/shared/backups`, `/shared/isos`
    - Or via NFS: `mount -t nfs 10.0.0.13:/shared/<dataset> /mnt/<dataset>`
  - **Windows**:
    - Use NFS client (Windows 10/11 Pro): `mount \\10.0.0.13\shared\<dataset> X:`
    - Optional: Configure Samba for easier access (`apt install samba`, add `[models] path=/shared/models` to `/etc/samba/smb.conf`).
  - **Linux**:
    - Mount via NFS: `mount -t nfs 10.0.0.13:/shared/<dataset> /mnt/<dataset>`
  - **macOS**:
    - Finder: Connect to Server (`nfs://10.0.0.13/shared/<dataset>`)
    - CLI: `mount -t nfs 10.0.0.13:/shared/<dataset> /Volumes/<dataset>`
- **Ollama Models Setup**:
  - Configure Ollama containers/VMs to use `/shared/models` as the model storage path (e.g., set `OLLAMA_MODELS=/shared/models` in environment variables).
  - Models are accessible across all containers/VMs, reducing duplication.
- **Data Projects Setup**:
  - VMs can mount `/shared/projects` for datasets, scripts, and other project files.
  - Supports large datasets for AI/ML workloads with high-speed access via 10GbE and NVMe.
- **Backups Setup**:
  - Configure Proxmox backup jobs to use `shared-backups` storage.
  - Use ZFS snapshots for versioning: `zfs snapshot shared/backups@backup-YYYYMMDD`.
- **Notes**:
  - 4 TB usable capacity; no redundancy (single drive).
  - NFS over 10GbE ensures low-latency access.
  - Snapshots can be scheduled per dataset (e.g., `zfs snapshot shared/models@daily-YYYYMMDD`).

## Additional Considerations
- **Performance**:
  - 10GbE Ethernet and NVMe ensure high-speed access for local and remote clients.
  - ZFS compression (lz4) optimizes storage for models and datasets; ARC cache leverages 96 GB RAM.
- **Backup Strategy**:
  - Use `/shared/backups` for Proxmox `vzdump` backups.
  - Follow 3-2-1 rule: Add offsite backups (e.g., external HDD via Samba or cloud like Backblaze B2).
- **Security**:
  - NFS restricted to `10.0.0.0/24` subnet.
  - For Samba (optional), add user authentication in `/etc/samba/smb.conf`.
- **Monitoring**:
  - Check ZFS health: `zpool status shared` and `zpool status tank`.
  - Monitor ARC cache: `arc_summary`.
