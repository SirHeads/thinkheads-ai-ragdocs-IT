# ZFS Storage Requirements Document

## Overview
This document outlines the requirements for configuring two ZFS pools (`quickOS` on 2TB mirrored NVMe and `fastData` on 4TB single NVMe) to support a Proxmox-based virtualization environment with VMs and LXC containers. The setup prioritizes high performance, minimal data on VM/LXC disks, ZFS snapshots, database reliability with synchronous writes (no SLOG), and NVMe lifespan optimization, leveraging 96GB RAM for ARC caching. Separating `quickOS/vm-disks` and `quickOS/lxc-disks` ensures tailored optimization for VM and LXC workloads.

- **Hardware**:
  - **quickOS**: 2TB mirrored NVMe (2 drives, high IOPS, high reliability).
  - **fastData**: 4TB single NVMe (high capacity, lower reliability).
  - System RAM: 96GB, available for ZFS ARC caching.
- **Software**: Proxmox VE, ZFS filesystem, Linux-based OS.
- **Workloads**: VMs and LXC containers with minimal local storage, shared storage for databases (sync writes), LLM models, test data, backups, ISOs, and bulk data.
- **Goals**:
  - Maximize performance for `quickOS` (VMs, LXC, databases, LLM models).
  - Use `fastData` for less critical, high-capacity storage.
  - Support frequent snapshots for recovery and cloning.
  - Minimize NVMe wear, especially on `quickOS` (mirrored).
  - Isolate database sync writes and optimize VM vs. LXC I/O patterns.
  - Leverage ARC caching for read performance.

## ZFS Pool Requirements

### 1. quickOS (2TB Mirrored NVMe)
- **Purpose**: Host VM root disks, LXC root disks, and production shared storage (databases, LLM models, application data).
- **Configuration**:
  - Create a mirrored ZFS pool using two 2TB NVMe drives for redundancy.
  - Enable `autotrim=on` to optimize NVMe performance and lifespan by proactively marking freed blocks.
  - Set `compression=lz4` for all datasets to reduce I/O and write amplification.
  - Set `atime=off` to minimize unnecessary writes.
- **ARC Caching**:
  - Limit ARC to ~48GB (`zfs_arc_max=51539607552`) to balance with VM/LXC RAM needs (96GB total).
  - Prioritize read caching for VM/LXC disks and shared storage.

### 2. fastData (4TB Single NVMe)
- **Purpose**: Host test data, backups, ISO images, and bulk storage.
- **Configuration**:
  - Create a single-device ZFS pool using one 4TB NVMe drive.
  - Enable `autotrim=on` for NVMe performance and lifespan.
  - Set `compression=lz4` for most datasets, `zstd` for backups to maximize space savings.
  - Set `atime=off` to reduce writes.
- **ARC Caching**: Use ARC (shared with `quickOS`) for read-heavy workloads like test data and ISOs.

## ZFS Dataset Requirements

### On quickOS
1. **Dataset: `quickOS/vm-disks`**
   - **Purpose**: Block storage for VM root disks (OS and binaries only, minimal data).
   - **Configuration**:
     - `recordsize=128K` to match typical VM I/O patterns (larger, block-based I/O).
     - `compression=lz4` to reduce I/O and NVMe wear.
     - `sync=standard` (async writes) for performance, as VM OS disks don’t require strict consistency.
     - `quota=800G` (thin-provisioned) to reserve space for snapshots and balance with other datasets.
     - Create sub-datasets per VM (e.g., `quickOS/vm-disks/vm1`) for snapshot granularity.
   - **Snapshots**: Daily snapshots for recovery.
   - **Backups**: Proxmox backups to `fastData/shared-backups`.
   - **Mounting**: Used as block storage in Proxmox (ZFS backend).
   - **Content**: VM OS, application binaries, minimal configuration. Application data stored in `shared-prod-data` or `shared-prod-data-sync`.

2. **Dataset: `quickOS/lxc-disks`**
   - **Purpose**: Block storage for LXC root disks (OS and binaries only, minimal data).
   - **Configuration**:
     - `recordsize=16K` to match LXC’s smaller, random I/O patterns (e.g., container filesystems).
     - `compression=lz4` to reduce I/O and NVMe wear.
     - `sync=standard` (async writes) for performance, as LXC OS disks don’t require strict consistency.
     - `quota=600G` (thin-provisioned) to reserve space for snapshots and balance with other datasets.
     - Create sub-datasets per LXC (e.g., `quickOS/lxc-disks/lxc1`) for snapshot granularity.
   - **Snapshots**: Daily snapshots for recovery.
   - **Backups**: Proxmox backups to `fastData/shared-backups`.
   - **Mounting**: Used as block storage in Proxmox (ZFS backend).
   - **Content**: LXC OS, application binaries, minimal configuration. Application data stored in `shared-prod-data` or `shared-prod-data-sync`.

3. **Dataset: `quickOS/shared-prod-data`**
   - **Purpose**: Shared storage for LLM models, application data, and non-database files.
   - **Configuration**:
     - `recordsize=128K` for mixed workloads (sequential reads/writes for LLM models).
     - `compression=lz4` for performance and NVMe lifespan.
     - `sync=standard` (async writes) for high throughput.
     - `quota=400G` (thin-provisioned) to balance with other datasets.
   - **Snapshots**: Daily snapshots for recovery and cloning to `fastData/shared-test-data`.
   - **Backups**: Snapshots backed up to `fastData/shared-backups` via `zfs send/receive`.
   - **Mounting**: NFS (`noatime`, `async`) for VMs, bind-mounted (`discard`, `noatime`) for LXC.
   - **Content**: LLM model files, application data, non-critical files. No database data.

4. **Dataset: `quickOS/shared-prod-data-sync`**
   - **Purpose**: Shared storage for databases requiring synchronous writes (e.g., PostgreSQL, MySQL, Redis AOF).
   - **Configuration**:
     - `recordsize=16K` for small, random I/O (database transaction logs, indexes).
     - `compression=lz4` to reduce I/O and write amplification.
     - `sync=always` to ensure data consistency (no SLOG, writes hit main NVMe drives).
     - `quota=100G` (thin-provisioned) to limit database growth.
     - Optional sub-datasets (e.g., `shared-prod-data-sync/postgres`) for specific databases.
   - **Snapshots**: Hourly snapshots for point-in-time recovery.
   - **Backups**: Snapshots backed up to `fastData/shared-backups` via `zfs send/receive`.
   - **Mounting**: NFS (`sync`, `noatime`) for VMs, bind-mounted (`discard`, `noatime`) for LXC.
   - **Content**: Database data directories (e.g., `/var/lib/postgresql`), transaction logs, Redis AOF files.

### On fastData
1. **Dataset: `fastData/shared-test-data`**
   - **Purpose**: Test environment storage, cloned from `quickOS/shared-prod-data` or `quickOS/shared-prod-data-sync`.
   - **Configuration**:
     - `recordsize=128K` (default, matches `shared-prod-data`) or `16K` (if cloned from `shared-prod-data-sync`).
     - `compression=lz4` for performance.
     - `sync=standard` (async writes, test data is non-critical).
     - `quota=500G` (thin-provisioned) to match production data size.
   - **Snapshots**: Optional, infrequent (e.g., weekly) for test environment recovery.
   - **Backups**: Not typically needed (ephemeral test data).
   - **Mounting**: NFS (`noatime`, `async`) for VMs, bind-mounted (`discard`, `noatime`) for LXC.
   - **Content**: Test copies of production data (databases, LLM models).

2. **Dataset: `fastData/shared-backups`**
   - **Purpose**: Storage for Proxmox backups of VMs/LXC and snapshots of production data.
   - **Configuration**:
     - `recordsize=1M` for large, sequential writes (backup archives).
     - `compression=zstd` for maximum space savings.
     - `sync=standard` (async writes, backups don’t require strict consistency).
     - `quota=2T` (thin-provisioned) for multiple backup sets.
   - **Snapshots**: Not needed (Proxmox manages retention).
   - **Backups**: Primary backup target.
   - **Mounting**: Proxmox backup storage (directory or ZFS backend).
   - **Content**: Proxmox `.vma` files, ZFS snapshot backups.

3. **Dataset: `fastData/shared-iso`**
   - **Purpose**: Storage for ISO images used in VM/LXC creation.
   - **Configuration**:
     - `recordsize=1M` for large, static files.
     - `compression=lz4` for space savings.
     - `sync=standard` (async writes, ISOs are static).
     - `quota=100G` (thin-provisioned) for typical ISO sizes.
   - **Snapshots**: Rarely needed (static data).
   - **Backups**: Not needed.
   - **Mounting**: Proxmox ISO storage (directory or NFS).
   - **Content**: ISO images.

4. **Dataset: `fastData/shared-bulk-data`**
   - **Purpose**: General-purpose storage for large files/folders (e.g., media, logs).
   - **Configuration**:
     - `recordsize=1M` for large, sequential I/O.
     - `compression=lz4` for performance and space savings.
     - `sync=standard` (async writes, non-critical data).
     - `quota=1.4T` (thin-provisioned) for remaining space.
   - **Snapshots**: Infrequent (e.g., weekly) due to large data size.
   - **Backups**: Optional backups to `shared-backups`.
   - **Mounting**: NFS (`noatime`, `async`) for VMs, bind-mounted (`discard`, `noatime`) for LXC.
   - **Content**: Media, logs, non-critical files.

## Additional Requirements

### NVMe Optimization
- **TRIM**: Enable `autotrim=on` on both pools to maintain NVMe performance and extend lifespan, critical for snapshots and database writes.
- **Write Amplification**:
  - Use `lz4`/`zstd` compression to reduce writes.
  - Isolate sync writes to `shared-prod-data-sync` to minimize wear on `quickOS` NVMe drives (mirrored, doubles writes).
  - Monitor NVMe wear with `smartctl` (e.g., wear level, write counts).
- **Firmware**: Ensure NVMe firmware is up-to-date for optimal TRIM and I/O handling.

### Snapshots and Backups
- **Snapshot Schedules**:
  - `vm-disks`, `lxc-disks`: Daily snapshots for recovery.
  - `shared-prod-data-sync`: Hourly snapshots for database recovery.
  - `shared-prod-data`: Daily snapshots for LLM models and application data.
  - `shared-test-data`: Weekly snapshots (optional).
  - `shared-backups`, `shared-iso`, `shared-bulk-data`: Snapshots rarely needed.
- **Cloning**: Clone snapshots from `shared-prod-data` or `shared-prod-data-sync` to `fastData/shared-test-data` for test environments.
- **Backups**:
  - Proxmox backups of VMs/LXC to `fastData/shared-backups`.
  - ZFS snapshot backups (`zfs send/receive`) from `quickOS` to `fastData/shared-backups`.

### Proxmox Integration
- **Storage Backends**:
  - Add `quickOS/vm-disks` and `quickOS/lxc-disks` as separate ZFS storage backends for VM and LXC disks.
  - Add `quickOS/shared-prod-data` and `shared-prod-data-sync` as NFS or directory storage for shared mounts.
  - Add `fastData/shared-backups` as backup storage.
  - Add `fastData/shared-iso` as ISO storage.
  - Add `fastData/shared-test-data` and `shared-bulk-data` as NFS or directory storage.
- **Mount Options**:
  - NFS: Use `noatime`, `async` for `shared-prod-data`, `shared-test-data`, `shared-bulk-data`; `sync`, `noatime` for `shared-prod-data-sync`.
  - Bind mounts (LXC): Use `discard`, `noatime` for all datasets.
- **Database Configuration**:
  - Store database data directories (e.g., `/var/lib/postgresql`, MySQL data, Redis AOF) on `shared-prod-data-sync`.
  - Tune databases for `sync=always` (e.g., PostgreSQL `synchronous_commit=on`, MySQL `innodb_flush_log_at_trx_commit=1`).

### Performance and Monitoring
- **ARC Tuning**: Set `zfs_arc_max=48G` to balance caching with VM/LXC RAM needs.
- **I/O Monitoring**: Use `zpool iostat` and `zfs list -o space` to monitor performance and space usage.
- **NVMe Health**: Track wear with `smartctl` to ensure longevity, especially on `quickOS` (mirrored, higher write load due to sync writes).

## Trade-Offs
- **Dataset Separation (`vm-disks`, `lxc-disks`, `shared-prod-data-sync`)**:
  - **Pros**: Optimizes VM (`recordsize=128K`) and LXC (`recordsize=16K`) I/O, isolates database sync writes (`recordsize=16K`, `sync=always`), maintains async performance for LLM models (`recordsize=128K`, `sync=standard`), supports tailored snapshots.
  - **Cons**: Increases management complexity (more datasets, mounts), consumes `quickOS` space (~800GB VM, ~600GB LXC, ~100GB database, ~400GB LLM/other).
- **No SLOG**:
  - **Pros**: Avoids hardware cost.
  - **Cons**: `sync=always` on `shared-prod-data-sync` increases latency and NVMe wear on `quickOS`. Mitigated by compression and TRIM.
- **ARC Usage**:
  - **Pros**: 48GB ARC improves read performance for VMs, LXC, and shared storage.
  - **Cons**: Leaves ~48GB for VMs/LXC, requiring monitoring to avoid memory contention.
- **Snapshots**:
  - **Pros**: Enable recovery and cloning for databases, VMs, and LXC.
  - **Cons**: Frequent snapshots on `shared-prod-data-sync` consume space and I/O; mitigated by quotas and thin provisioning.