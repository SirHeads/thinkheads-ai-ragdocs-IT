#!/bin/bash

# proxmox_setup_nvidia_gpu_virt.sh
# Configures NVIDIA GPU virtualization on Proxmox VE with AMD CPU, using NVIDIA driver and CUDA 12.9
# Version: 1.1.1
# Author: Heads, Grok, Devstral
# Usage: ./proxmox_setup_nvidia_gpu_virt.sh [--no-reboot]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions
if [[ ! -f /usr/local/bin/common.sh ]]; then
  echo "Error: /usr/local/bin/common.sh does not exist" | tee -a "$LOGFILE"
  exit 1
fi
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }

# Parse command-line arguments
NO_REBOOT=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-reboot)
      NO_REBOOT=1
      shift
      ;;
    *)
      echo "Error: Unknown option $1" | tee -a "$LOGFILE"
      exit 1
      ;;
  esac
done

# Update and upgrade system
update_system() {
  retry_command "apt-get update" || {
    echo "Error: apt-get update failed. Check /var/log/proxmox_setup.log for details" | tee -a "$LOGFILE"
    cat /var/log/apt/term.log >> "$LOGFILE" 2>/dev/null
    exit 1
  }
  retry_command "apt-get upgrade -y"
  echo "[$(date)] System updated and upgraded" >> "$LOGFILE"
}

# Install kernel headers
install_kernel_headers() {
  local current_kernel=$(uname -r)
  local kernel_headers="linux-headers-$current_kernel"
  if ! check_package "$kernel_headers"; then
    retry_command "apt-get install -y $kernel_headers"
    echo "[$(date)] Installed kernel headers for $current_kernel" >> "$LOGFILE"
  fi
}

# Verify NVIDIA GPUs
verify_nvidia_gpus() {
  if ! lspci | grep -i nvidia | grep -q "5060"; then
    echo "Warning: NVIDIA 5060 TI GPUs not detected. Check 'lspci' output" | tee -a "$LOGFILE"
  else
    echo "[$(date)] Detected NVIDIA 5060 TI GPUs" >> "$LOGFILE"
  fi
}

# Add NVIDIA repository (Debian 12 Bookworm)
add_nvidia_repository() {
  if ! grep -q 'nvidia' /etc/apt/sources.list.d/nvidia-c CUDA.list 2>/dev/null; then
    retry_command "curl -s -L https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-debian12.pin -o /etc/apt/preferences.d/cuda-repository-pin-600"
    retry_command "curl -s -L https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/3bf863cc.pub -o /usr/share/keyrings/nvidia-cuda-keyring.gpg"
    echo "deb [signed-by=/usr/share/keyrings/nvidia-cuda-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/ /" | \
      retry_command "tee /etc/apt/sources.list.d/nvidia-cuda.list"
    retry_command "apt-get update" || {
      echo "Error: apt-get update failed. Check /var/log/proxmox_setup.log for details" | tee -a "$LOGFILE"
      cat /var/log/apt/term.log >> "$LOGFILE" 2>/dev/null
      exit 1
    }
    echo "[$(date)] Added NVIDIA repository for Debian 12" >> "$LOGFILE"
  else
    echo "NVIDIA repository already added, skipping" | tee -a "$LOGFILE"
  fi
}

# Install NVIDIA driver and CUDA 12.9
install_nvidia_drivers() {
  if ! check_package nvidia-driver; then
    retry_command "apt-get install -y nvidia-driver"
    echo "[$(date)] Installed NVIDIA driver" >> "$LOGFILE"
  fi
  if ! check_package cuda-12-9; then
    retry_command "apt-get install -y cuda-12-9"
    echo "[$(date)] Installed CUDA 12.9" >> "$LOGFILE"
  fi
  if ! check_package nvtop; then
    retry_command "apt-get install -y nvtop"
    echo "[$(date)] Installed NVTop" >> "$LOGFILE"
  fi
}

# Blacklist Nouveau driver
blacklist_nouveau() {
  if ! grep -q '^blacklist nouveau' /etc/modprobe.d/blacklist.conf 2>/dev/null; then
    echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf || { echo "Error: Failed to blacklist Nouveau driver"; exit 1; }
    echo "options nouveau modeset=0" >> /etc/modprobe.d/blacklist.conf || { echo "Error: Failed to set modeset=0 for Nouveau"; exit 1; }
    echo "[$(date)] Blacklisted Nouveau driver" >> "$LOGFILE"
  else
    echo "Nouveau driver already blacklisted, skipping" | tee -a "$LOGFILE"
  fi
}

# Add VFIO modules for GPU passthrough
add_vfio_modules() {
  if ! grep -q '^vfio' /etc/modules; then
    for module in vfio vfio_iommu_type1 vfio_pci vfio_virqfd; do
      echo "$module" >> /etc/modules || { echo "Error: Failed to add $module to /etc/modules"; exit 1; }
    done
    echo "[$(date)] Added VFIO modules to /etc/modules" >> "$LOGFILE"
  else
    echo "VFIO modules already added, skipping" | tee -a "$LOGFILE"
  fi
}

# Update kernel command line
update_kernel_command_line() {
  if ! grep -q "amd_iommu=on" /etc/default/grub; then
    retry_command "sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT=\".*\)\"/\1 iommu=pt amd_iommu=on video=vesafb:/' /etc/default/grub"
    retry_command "update-grub"
    echo "[$(date)] Updated kernel command line for IOMMU and AMD CPU" >> "$LOGFILE"
  else
    echo "IOMMU parameters already set, skipping" | tee -a "$LOGFILE"
  fi
}

# Final system updates
final_system_updates() {
  retry_command "proxmox-boot-tool refresh"
  retry_command "update-initramfs -u"
  echo "[$(date)] Completed final system updates" >> "$LOGFILE"
}

# Main execution
check_root
update_system
install_kernel_headers
verify_nvidia_gpus
add_nvidia_repository
install_nvidia_drivers
blacklist_nouveau
add_vfio_modules
update_kernel_command_line
final_system_updates

echo "NVIDIA GPU virtualization setup complete (Driver: latest, CUDA: 12.9)."
echo "- Reboot required to apply changes."
echo "- Proxmox VE web interface: https://10.0.0.13:8006"
if [[ $NO_REBOOT -eq 0 ]]; then
  read -t 60 -p "Reboot now? (y/n) [Timeout in 60s]: " REBOOT_CONFIRMATION
  if [[ -z "$REBOOT_CONFIRMATION" || "$REBOOT_CONFIRMATION" == "y" || "$REBOOT_CONFIRMATION" == "Y" ]]; then
    echo "Rebooting system..."
    reboot
  else
    echo "Please reboot manually to apply changes."
  fi
else
  echo "Reboot skipped due to --no-reboot flag. Please reboot manually."
fi
echo "[$(date)] Completed proxmox_setup_nvidia_gpu_virt.sh" >> "$LOGFILE"