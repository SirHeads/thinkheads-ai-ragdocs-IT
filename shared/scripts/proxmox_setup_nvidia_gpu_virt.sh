#!/bin/bash

# proxmox_setup_nvidia_gpu_virt.sh
# Configures NVIDIA GPU virtualization on Proxmox VE with AMD CPU, using NVIDIA driver and CUDA 12.9
# Version: 1.2.4
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
  echo "[$(date)] Updating and upgrading the system" | tee -a "$LOGFILE"
  retry_command "apt-get update" || {
    echo "Error: apt-get update failed. Check /var/log/proxmox_setup.log for details" | tee -a "$LOGFILE"
    cat /var/log/apt/term.log >> "$LOGFILE" 2>/dev/null
    exit 1
  }
  retry_command "apt-get upgrade -y"
  echo "[$(date)] System updated and upgraded" | tee -a "$LOGFILE"
}

# Install kernel headers
install_kernel_headers() {
  echo "[$(date)] Installing kernel headers" | tee -a "$LOGFILE"
  local current_kernel=$(uname -r)
  local kernel_headers="linux-headers-$current_kernel"
  if ! check_package "$kernel_headers"; then
    retry_command "apt-get install -y $kernel_headers"
    echo "[$(date)] Installed kernel headers for $current_kernel" | tee -a "$LOGFILE"
  else
    echo "[$(date)] Kernel headers for $current_kernel already installed" | tee -a "$LOGFILE"
  fi
}

# Verify NVIDIA GPUs
verify_nvidia_gpus() {
  echo "[$(date)] Verifying NVIDIA GPUs" | tee -a "$LOGFILE"
  if ! lspci | grep -i nvidia | grep -q "5060"; then
    echo "Warning: NVIDIA 5060 TI GPUs not detected. Check 'lspci' output" | tee -a "$LOGFILE"
  else
    echo "[$(date)] Detected NVIDIA 5060 TI GPUs" | tee -a "$LOGFILE"
  fi
}

# Install NVIDIA repository dependencies
install_nvidia_repo_deps() {
  echo "[$(date)] Installing NVIDIA repository dependencies" | tee -a "$LOGFILE"
  local deps="wget gnupg"
  for dep in $deps; do
    if ! check_package "$dep"; then
      retry_command "apt-get install -y $dep" || {
        echo "Error: Failed to install $dep" | tee -a "$LOGFILE"
        exit 1
      }
      echo "[$(date)] Installed $dep" | tee -a "$LOGFILE"
    else
      echo "[$(date)] Package $dep already installed" | tee -a "$LOGFILE"
    fi
  done
}

# Add NVIDIA repository (Debian 12 Bookworm)
add_nvidia_repository() {
  echo "[$(date)] Adding NVIDIA CUDA repository" | tee -a "$LOGFILE"
  # Clean up existing NVIDIA/CUDA repository and pin files
  if [[ -f /etc/apt/sources.list.d/nvidia-cuda.list || -f /etc/apt/sources.list.d/cuda.list || -f /etc/apt/preferences.d/cuda-repository-pin-600 ]]; then
    echo "Warning: Existing NVIDIA/CUDA repository or pin files detected, removing to avoid conflicts" | tee -a "$LOGFILE"
    rm -f /etc/apt/sources.list.d/nvidia-cuda.list /etc/apt/sources.list.d/cuda.list /etc/apt/preferences.d/cuda-repository-pin-600
  fi
  # Check if CUDA repository is already configured
  if ! grep -q 'developer.download.nvidia.com/compute/cuda' /etc/apt/sources.list $(find /etc/apt/sources.list.d/ -type f -name '*.list' 2>/dev/null) 2>/dev/null; then
    retry_command "wget https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb -O /tmp/cuda-keyring.deb" || {
      echo "Error: Failed to download cuda-keyring package" | tee -a "$LOGFILE"
      exit 1
    }
    retry_command "dpkg -i /tmp/cuda-keyring.deb" || {
      echo "Error: Failed to install cuda-keyring package" | tee -a "$LOGFILE"
      exit 1
    }
    rm -f /tmp/cuda-keyring.deb
    if [[ ! -f /etc/apt/sources.list.d/cuda-debian12-x86_64.list ]]; then
      echo "Error: CUDA repository file not created by cuda-keyring package" | tee -a "$LOGFILE"
      exit 1
    }
    retry_command "apt-get update" || {
      echo "Error: apt-get update failed after adding NVIDIA repository" | tee -a "$LOGFILE"
      cat /var/log/apt/term.log >> "$LOGFILE" 2>/dev/null
      exit 1
    }
    echo "[$(date)] Added NVIDIA CUDA repository for Debian 12 with cuda-keyring" | tee -a "$LOGFILE"
  else
    echo "[$(date)] NVIDIA CUDA repository already configured, skipping" | tee -a "$LOGFILE"
  fi
}

# Install NVIDIA driver, CUDA 12.9, and NVTop
install_nvidia_drivers() {
  echo "[$(date)] Installing NVIDIA driver, CUDA Toolkit 12.9, and NVTop" | tee -a "$LOGFILE"
  if ! check_package nvidia-driver; then
    retry_command "apt-get install -y nvidia-driver nvidia-utils" || {
      echo "Error: Failed to install NVIDIA driver and utils" | tee -a "$LOGFILE"
      exit 1
    }
    echo "[$(date)] Installed NVIDIA driver and utilities (includes nvidia-smi)" | tee -a "$LOGFILE"
  else
    echo "[$(date)] NVIDIA driver already installed" | tee -a "$LOGFILE"
  fi
  if ! check_package cuda-toolkit-12-9; then
    retry_command "apt-get install -y cuda-toolkit-12-9" || {
      echo "Error: Failed to install CUDA Toolkit 12.9" | tee -a "$LOGFILE"
      exit 1
    }
    echo "[$(date)] Installed CUDA Toolkit 12.9" | tee -a "$LOGFILE"
  else
    echo "[$(date)] CUDA Toolkit 12.9 already installed" | tee -a "$LOGFILE"
  fi
  if ! check_package nvtop; then
    retry_command "apt-get install -y nvtop" || {
      echo "Error: Failed to install NVTop" | tee -a "$LOGFILE"
      exit 1
    }
    echo "[$(date)] Installed NVTop" | tee -a "$LOGFILE"
  else
    echo "[$(date)] NVTop already installed" | tee -a "$LOGFILE"
  fi
}

# Install NVIDIA Container Toolkit
install_nvidia_container_toolkit() {
  echo "[$(date)] Installing NVIDIA Container Toolkit" | tee -a "$LOGFILE"
  if ! check_package nvidia-container-toolkit; then
    retry_command "curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
    retry_command "curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list"
    retry_command "apt-get update"
    retry_command "apt-get install -y nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1" || {
      echo "Error: Failed to install NVIDIA Container Toolkit" | tee -a "$LOGFILE"
      exit 1
    }
    if ! command -v docker &>/dev/null; then
      retry_command "apt-get install -y docker.io" || {
        echo "Error: Failed to install Docker" | tee -a "$LOGFILE"
        exit 1
      }
      retry_command "systemctl enable --now docker"
      echo "[$(date)] Installed and enabled Docker" | tee -a "$LOGFILE"
    else
      echo "[$(date)] Docker already installed" | tee -a "$LOGFILE"
    fi
    retry_command "nvidia-ctk runtime configure --runtime=docker"
    retry_command "systemctl restart docker"
    echo "[$(date)] Installed and configured NVIDIA Container Toolkit" | tee -a "$LOGFILE"
  else
    echo "[$(date)] NVIDIA Container Toolkit already installed, skipping" | tee -a "$LOGFILE"
  fi
}

# Verify NVIDIA installation
verify_nvidia_installation() {
  echo "[$(date)] Verifying NVIDIA installation" | tee -a "$LOGFILE"
  if command -v nvidia-smi &>/dev/null; then
    if nvidia-smi &>>"$LOGFILE"; then
      echo "[$(date)] NVIDIA driver verified with nvidia-smi" | tee -a "$LOGFILE"
    else
      echo "Error: nvidia-smi failed to execute. Check GPU driver installation" | tee -a "$LOGFILE"
      exit 1
    fi
  else
    echo "Error: nvidia-smi not found. NVIDIA driver installation incomplete" | tee -a "$LOGFILE"
    exit 1
  fi
  if command -v nvtop &>/dev/null; then
    echo "[$(date)] NVTop installed successfully" | tee -a "$LOGFILE"
  else
    echo "Error: nvtop not found. NVTop installation incomplete" | tee -a "$LOGFILE"
    exit 1
  fi
  if command -v nvcc &>/dev/null; then
    nvcc --version &>>"$LOGFILE"
    echo "[$(date)] CUDA Toolkit 12.9 verified with nvcc" | tee -a "$LOGFILE"
  else
    echo "Error: nvcc not found. CUDA Toolkit installation incomplete" | tee -a "$LOGFILE"
    exit 1
  fi
  if command -v nvidia-ctk &>/dev/null; then
    echo "[$(date)] NVIDIA Container Toolkit verified with nvidia-ctk" | tee -a "$LOGFILE"
  else
    echo "Error: nvidia-ctk not found. NVIDIA Container Toolkit installation incomplete" | tee -a "$LOGFILE"
    exit 1
  fi
}

# Blacklist Nouveau driver
blacklist_nouveau() {
  echo "[$(date)] Blacklisting Nouveau driver" | tee -a "$LOGFILE"
  if ! grep -q '^blacklist nouveau' /etc/modprobe.d/blacklist.conf 2>/dev/null; then
    echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf || { echo "Error: Failed to blacklist Nouveau driver" | tee -a "$LOGFILE"; exit 1; }
    echo "options nouveau modeset=0" >> /etc/modprobe.d/blacklist.conf || { echo "Error: Failed to set modeset=0 for Nouveau" | tee -a "$LOGFILE"; exit 1; }
    echo "[$(date)] Blacklisted Nouveau driver" | tee -a "$LOGFILE"
  else
    echo "[$(date)] Nouveau driver already blacklisted, skipping" | tee -a "$LOGFILE"
  fi
}

# Add VFIO modules for GPU passthrough
add_vfio_modules() {
  echo "[$(date)] Adding VFIO modules" | tee -a "$LOGFILE"
  if ! grep -q '^vfio' /etc/modules; then
    for module in vfio vfio_iommu_type1 vfio_pci vfio_virqfd; do
      echo "$module" >> /etc/modules || { echo "Error: Failed to add $module to /etc/modules" | tee -a "$LOGFILE"; exit 1; }
    done
    echo "[$(date)] Added VFIO modules to /etc/modules" | tee -a "$LOGFILE"
  else
    echo "[$(date)] VFIO modules already added, skipping" | tee -a "$LOGFILE"
  fi
}

# Update kernel command line
update_kernel_command_line() {
  echo "[$(date)] Updating kernel command line" | tee -a "$LOGFILE"
  if ! grep -q "amd_iommu=on" /etc/default/grub; then
    retry_command "sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT=\".*\)\"/\1 iommu=pt amd_iommu=on video=vesafb:/' /etc/default/grub"
    retry_command "update-grub"
    echo "[$(date)] Updated kernel command line for IOMMU and AMD CPU" | tee -a "$LOGFILE"
  else
    echo "[$(date)] IOMMU parameters already set, skipping" | tee -a "$LOGFILE"
  fi
}

# Final system updates
final_system_updates() {
  echo "[$(date)] Performing final system updates" | tee -a "$LOGFILE"
  retry_command "proxmox-boot-tool refresh"
  retry_command "update-initramfs -u"
  echo "[$(date)] Completed final system updates" | tee -a "$LOGFILE"
}

# Main execution
check_root
update_system
install_kernel_headers
verify_nvidia_gpus
install_nvidia_repo_deps
add_nvidia_repository
install_nvidia_drivers
install_nvidia_container_toolkit
verify_nvidia_installation
blacklist_nouveau
add_vfio_modules
update_kernel_command_line
final_system_updates

echo "NVIDIA GPU virtualization setup complete (Driver: latest, CUDA: 12.9, Container Toolkit installed)." | tee -a "$LOGFILE"
echo "- Tools installed: nvidia-smi, nvtop, nvcc, nvidia-ctk" | tee -a "$LOGFILE"
echo "- Reboot required to apply changes." | tee -a "$LOGFILE"
echo "- Proxmox VE web interface: https://10.0.0.13:8006" | tee -a "$LOGFILE"
echo "- Verify GPU access in containers: docker run --rm --gpus all nvidia/cuda:12.9.0-base-ubuntu22.04 nvidia-smi" | tee -a "$LOGFILE"
if [[ $NO_REBOOT -eq 0 ]]; then
  read -t 60 -p "Reboot now? (y/n) [Timeout in 60s]: " REBOOT_CONFIRMATION
  if [[ -z "$REBOOT_CONFIRMATION" || "$REBOOT_CONFIRMATION" == "y" || "$REBOOT_CONFIRMATION" == "Y" ]]; then
    echo "Rebooting system..." | tee -a "$LOGFILE"
    reboot
  else
    echo "Please reboot manually to apply changes." | tee -a "$LOGFILE"
  fi
else
  echo "Reboot skipped due to --no-reboot flag. Please reboot manually." | tee -a "$LOGFILE"
fi
echo "[$(date)] Completed proxmox_setup_nvidia_gpu_virt.sh" >> "$LOGFILE"