Phoenix Server Proxmox VE Setup Scripts
This repository contains scripts to configure a Proxmox VE server (hostname: phoenix.example.com) for virtualization, storage, and GPU passthrough. The scripts are designed for a high-performance home-lab server with AMD CPU, NVIDIA 5060 TI GPUs, and NVMe storage, supporting AI/ML workloads, containers, and VMs.
Purpose
The scripts automate the setup of a Proxmox VE environment, including repository configuration, admin user creation, ZFS storage pools, NFS/Samba sharing, NVIDIA GPU virtualization, and LXC/VM user setup. They are modular, robust, and include error handling, logging, system updates, and command-line argument support for automation.
Prerequisites
Before running the scripts, ensure the following requirements are met:

Operating System: Proxmox VE 8.x (based on Debian 12 Bookworm) installed on 2x 240GB Crucial BX500 SSDs (ZFS mirror, 180GB allocated per SSD).
Hardware:
AMD CPU (e.g., AMD 7600).
2x NVIDIA 5060 TI GPUs (PCIe 5.0 x8).
2x 2TB Samsung 990 EVO Plus NVMe (for ZFS mirror, quickOS).
1x 4TB Samsung 990 EVO Plus NVMe (for shared storage, fastData).
96GB DDR5 RAM.
10GbE Ethernet interface.


Network:
Static IP: 10.0.0.13.
Gateway: 10.0.0.1.
DNS: 8.8.8.8.
Subnet: 10.0.0.0/24.


Software:
Internet access for package downloads (e.g., NVIDIA drivers, CUDA).
wget installed (included by default in Proxmox VE).


Permissions: All commands are executed as the root user via SSH or console.
Storage: NVMe drives must be visible via lsblk (2x 2TB for mirror, 1x 4TB for standalone).

Pre-Configuration Steps
Follow these steps to prepare the server before running the setup scripts. All commands are executed as the root user.

Log in as root:

Access the server via SSH (ssh root@10.0.0.13 -p 2222) or console.


Download and Extract Scripts:

Download the script tarball using wget and extract it.wget https://example.com/proxmox-scripts.tar.gz -O /tmp/proxmox-scripts.tar.gz
tar -xzf /tmp/proxmox-scripts.tar.gz -C /tmp


The tarball extracts to a directory like thinkheads-ai-ragdocs-IT-<version>/shared/scripts/, where <version> is a version number (e.g., 1.0.0).


Copy Scripts to /usr/local/bin:

Create the target directory and copy the scripts from the extracted directory.mkdir -p /usr/local/bin
cp /tmp/thinkheads-ai-ragdocs-IT-*/shared/scripts/*.sh /usr/local/bin/




Set Script Permissions:

Make the scripts executable.chmod +x /usr/local/bin/*.sh




Configure Log Rotation:

The scripts log to /var/log/proxmox_setup.log. Set up log rotation to manage log size.
Create the log rotation configuration file:nano /etc/logrotate.d/proxmox_setup


Add the following content:/var/log/proxmox_setup.log {
    weekly
    rotate 4
    compress
    missingok
}


Save and exit (Ctrl+O, Enter, Ctrl+X).
Test the log rotation configuration:logrotate -f /etc/logrotate.d/proxmox_setup




Verify Log File Access:

Ensure the log file directory and file are accessible.mkdir -p /var/log
touch /var/log/proxmox_setup.log
chmod 664 /var/log/proxmox_setup.log


Verify the log file is writable:echo "Test log entry" >> /var/log/proxmox_setup.log
cat /var/log/proxmox_setup.log


If the test entry is visible, the log file is correctly configured.


Verify NVMe Drives:

Confirm the presence of 2x 2TB NVMe drives and 1x 4TB NVMe drive using lsblk.lsblk -d -o NAME,SIZE


Expected output should show three NVMe drives (e.g., nvme0n1, nvme2n1 ~2TB each, nvme1n1 ~4TB).


Ensure Internet Connectivity:

Verify internet access for package downloads.ping -c 4 8.8.8.8


Ensure the DNS server (8.8.8.8) and gateway (10.0.0.1) are reachable.



Running the Scripts
After completing the pre-configuration steps, run the scripts in the following order as the root user, then switch to the admin user after creating it.

Configure Repositories:
Run proxmox_configure_repos.sh to set up the Proxm


