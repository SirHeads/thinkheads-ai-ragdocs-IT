#!/bin/bash

# proxmox_setup_nvidia_gpu_virt.sh
# Prepares Proxmox system for virtualization of NVIDIA GPUs on a ZFS mirror with an AMD CPU

set -e
LOGFILE="/var/log/proxmox_setup.log"
echo "[$(date)] Starting proxmox_setup_nvidia_gpu_virt.sh" >> $LOGFILE

# Function to check if script is run as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run with sudo" | tee -a $LOGFILE
    exit 1
  fi
}

# Update and upgrade system packages
update_system() {
  apt-get update && apt-get upgrade -y || { echo "Error: Failed to update or upgrade system"; exit 1; }
  echo "[$(date)] System updated and upgraded" >> $LOGFILE
}

# Ensure kernel headers are installed for the current kernel version
install_kernel_headers() {
  CURRENT_KERNEL=$(uname -r)
  KERNEL_HEADERS="linux-headers-$CURRENT_KERNEL"

  if ! dpkg -l | grep -q "$KERNEL_HEADERS"; then
    apt-get install -y $KERNEL_HEADERS || { echo "Error: Failed to install kernel headers"; exit 1; }
    echo "[$(date)] Installed kernel headers for current kernel version" >> $LOGFILE
  else
    echo "Kernel headers already installed, skipping" | tee -a $LOGFILE
  fi
}

# Add NVIDIA repository for the latest drivers and tools
add_nvidia_repository() {
  if ! grep -q 'nvidia' /etc/apt/sources.list.d/nvidia-sources.list; then
    curl -s -L https://developer.download.nvidia.com/compute/cuda/repos/debian10/x86_64/cuda-debian10.pin | tee /etc/apt/preferences.d/cuda-repository-pin-600 || { echo "Error: Failed to add NVIDIA repository pin"; exit 1; }
    apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub || { echo "Error: Failed to fetch NVIDIA GPG key"; exit 1; }
    add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/debian10/x86_64/" > /dev/null || { echo "Error: Failed to add NVIDIA repository"; exit 1; }
    echo "[$(date)] Added NVIDIA repository" >> $LOGFILE
  else
    echo "NVIDIA repository already added, skipping" | tee -a $LOGFILE
  fi

  apt-get update || { echo "Error: Failed to update package list"; exit 1; }
}

# Install NVIDIA drivers and CUDA toolkit
install_nvidia_drivers() {
  if ! dpkg -l | grep -q nvidia-driver; then
    apt-get install -y nvidia-driver || { echo "Error: Failed to install NVIDIA driver"; exit 1; }
    echo "[$(date)] Installed NVIDIA driver" >> $LOGFILE
  else
    echo "NVIDIA driver already installed, skipping" | tee -a $LOGFILE
  fi

  if ! dpkg -l | grep -q cuda; then
    apt-get install -y cuda || { echo "Error: Failed to install CUDA toolkit"; exit 1; }
    echo "[$(date)] Installed CUDA toolkit" >> $LOGFILE
  else
    echo "CUDA toolkit already installed, skipping" | tee -a $LOGFILE
  fi

  if ! dpkg -l | grep -q nvtop; then
    apt-get install -y nvtop || { echo "Error: Failed to install NVTop"; exit 1; }
    echo "[$(date)] Installed NVTop" >> $LOGFILE
  else
    echo "NVTop already installed, skipping" | tee -a $LOGFILE
  fi
}

# Blacklist the Nouveau driver and set modeset=0
blacklist_nouveau() {
  if ! grep -q '^blacklist nouveau' /etc/modprobe.d/blacklist.conf; then
    echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf || { echo "Error: Failed to blacklist Nouveau driver"; exit 1; }
    echo "options nouveau modeset=0" >> /etc/modprobe.d/blacklist.conf || { echo "Error: Failed to set modeset=0 for Nouveau"; exit 1; }
    echo "[$(date)] Blacklisted Nouveau driver and set modeset=0" >> $LOGFILE
  else
    echo "Nouveau driver already blacklisted, skipping" | tee -a $LOGFILE
  fi
}

# Add necessary modules to /etc/modules for VFIO pass-through
add_vfio_modules() {
  if ! grep -q '^vfio' /etc/modules; then
    echo "vfio" >> /etc/modules || { echo "Error: Failed to add vfio module"; exit 1; }
    echo "vfio_iommu_type1" >> /etc/modules || { echo "Error: Failed to add vfio_iommu_type1 module"; exit 1; }
    echo "vfio_pci" >> /etc/modules || { echo "Error: Failed to add vfio_pci module"; exit 1; }
    echo "vfio_virqfd" >> /etc/modules || { echo "Error: Failed to add vfio_virqfd module"; exit 1; }
    echo "[$(date)] Added VFIO modules to /etc/modules" >> $LOGFILE
  else
    echo "VFIO modules already added, skipping" | tee -a $LOGFILE
  fi
}

# Update kernel command line for VM IOMMU GPU passthrough and AMD CPU
update_kernel_command_line() {
  if ! grep -q "amd_iommu=on" /etc/default/grub; then
    sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT=".*\)"/\1 iommu=pt amd_iommu=on video=vesafb:/' /etc/default/grub || { echo "Error: Failed to update kernel command line"; exit 1; }
    update-grub || { echo "Error: Failed to update GRUB configuration"; exit 1; }
    echo "[$(date)] Updated kernel command line for IOMMU and AMD CPU" >> $LOGFILE
  else
    echo "IOMMU parameter already set, skipping" | tee -a $LOGFILE
  fi
}

# Final system updates and reboots
final_system_updates() {
  apt-get update && apt-get upgrade -y || { echo "Error: Failed to perform final system updates"; exit 1; }

  # Refresh Proxmox boot tools
  proxmox-boot-tool refresh || { echo "Error: Failed to refresh Proxmox boot tool"; exit 1; }

  # Update initramfs
  update-initramfs -u || { echo "Error: Failed to update initramfs"; exit 1; }

  echo "[$(date)] Final system updates and reboots completed" >> $LOGFILE
}

# Main script execution
check_root
update_system
install_kernel_headers
add_nvidia_repository
install_nvidia_drivers
blacklist_nouveau
add_vfio_modules
update_kernel_command_line

echo "Setup complete. Reboot the system to apply changes."
final_system_updates

read -p "Reboot now? (y/n) [Timeout in 60 seconds]: " REBOOT_CONFIRMATION
if [[ -z "$REBOOT_CONFIRMATION" ]]; then
  echo "No response received. Rebooting the system."
  sleep 1
  reboot
else
  if [[ "$REBOOT_CONFIRMATION" == "y" || "$REBOOT_CONFIRMATION" == "Y" ]]; then
    reboot
  else
    echo "Please reboot the system manually to apply changes."
  fi
fi

echo "[$(date)] Completed proxmox_setup_nvidia_gpu_virt.sh" >> $LOGFILE