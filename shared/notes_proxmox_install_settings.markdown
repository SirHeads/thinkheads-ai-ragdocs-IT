# Proxmox VE Installation Settings for Phoenix Server

## Server Details
- **Server Name**: Phoenix
- **Hostname (FQDN)**: Phoenix.ThinkHeads.ai
- **Location**: United States, EST (New York City)
- **Keyboard Layout**: US English

## Storage Configuration
- **Target Drives**: 
  - 2x 240 GB Crucial BX500 SSD (SATA 1 and SATA 2) - sda & sdb
- **Filesystem**: ZFS (Mirror)
  - **Allocated Space**: 180 GB per SSD
  - **Reserved Space**: 60 GB per SSD (unallocated for emergency use)
  - **Ashift: 12
  - **compress: on
  - **copies: 1
  - **arc MAX size: 9566

## Network Configuration
- **Management Interface**: 10GbE Ethernet
- **IP Address**: 10.0.0.13
- **Gateway**: 10.0.0.1
- **DNS Server**: 1.1.1.1
- **Local Login**: [Proxmox VE Web Interface](https://10.0.0.13:8006)

## Notes
- The ZFS mirror configuration ensures redundancy for the Proxmox VE installation.
- The 10GbE Ethernet interface is used for high-speed management access.
- Reserved space on SSDs allows for future recovery or emergency use.
- The local login link provides access to the Proxmox VE web interface for management.
- These settings are tailored for the ThinkHeads.ai infrastructure, supporting local server operations and future integration with cloud services.
