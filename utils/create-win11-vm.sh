#!/usr/bin/env bash

# Windows 11 VM Creation Helper Script
# This script provides instructions and commands to create a Windows 11 VM with proper TPM support

set -e

# Get current user's home directory
USER_HOME="$HOME"
VM_DIR="$USER_HOME/VMs"
VM_IMAGES_DIR="$VM_DIR/images"
VM_ISO_DIR="$VM_DIR/iso"

echo "🖥️ Windows 11 VM Setup Guide"
echo "============================="
echo "VM Storage Location: $VM_DIR"
echo ""

# Ensure VM directories exist
if [ ! -d "$VM_DIR" ]; then
  echo "📁 Creating VM directories..."
  mkdir -p "$VM_IMAGES_DIR" "$VM_ISO_DIR"
  echo "✅ Created: $VM_DIR"
  echo "✅ Created: $VM_IMAGES_DIR"
  echo "✅ Created: $VM_ISO_DIR"
else
  echo "✅ VM directories already exist"
fi
echo ""

# Check if virt-manager is running
if ! pgrep -x "libvirtd" >/dev/null; then
  echo "❌ libvirtd is not running. Starting it..."
  sudo systemctl start libvirtd
  echo "✅ libvirtd started"
else
  echo "✅ libvirtd is running"
fi

# Check if default network is active
if ! sudo virsh net-list --all | grep -q "default.*active"; then
  echo "❌ Default network is not active. Starting it..."
  sudo virsh net-start default
  sudo virsh net-autostart default
  echo "✅ Default network started and set to autostart"
else
  echo "✅ Default network is active"
fi

echo ""
echo "📋 Windows 11 VM Creation Steps:"
echo "1. Launch virt-manager:"
echo "   $ virt-manager"
echo ""
echo "2. Create new VM with these settings:"
echo "   📱 Name: Windows11"
echo "   💿 ISO: Windows 11 installation media"
echo "   💾 Storage: 128GB+ VirtIO disk"
echo "      └─ Path: $VM_IMAGES_DIR/windows11.qcow2"
echo "   🧠 Memory: 16GB+ RAM"
echo "   ⚙️  CPU: 8+ cores"
echo "   🔧 Chipset: Q35"
echo "   🔒 Firmware: UEFI x86_64 (OVMF_CODE.secboot.fd)"
echo "   🛡️  Enable: Secure Boot"
echo "   🔐 Add: TPM v2.0 device (Emulated, Model: TIS)"
echo ""
echo "3. Download and store ISOs:"
echo "   🌐 Windows 11: Store in $VM_ISO_DIR/"
echo "   🌐 VirtIO drivers: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/"
echo "      └─ Store virtio-win.iso in $VM_ISO_DIR/"
echo "   📀 Attach both ISOs during VM creation"
echo ""
echo "4. During Windows 11 installation:"
echo "   See this video to create a local only account"
echo "   https://www.youtube.com/shorts/ieUaZvZJ_s4"
echo "   🔍 Load VirtIO drivers when disk is not detected"
echo "   📂 Browse to virtio-win CD → vioscsi → w11 → amd64"
echo ""
echo "🎉 Your system is configured with:"
echo "   ✅ OVMF UEFI firmware with Secure Boot"
echo "   ✅ Software TPM (swtpm) for TPM 2.0 emulation"
echo "   ✅ VirtIO drivers support"
echo "   ✅ SPICE guest tools"
echo "   ✅ USB redirection"
echo ""
echo "💾 All VM data will be stored in: $VM_DIR"
echo "   └─ Disk images: $VM_IMAGES_DIR"
echo "   └─ ISO files: $VM_ISO_DIR"
echo "   └─ This ensures ZFS backup coverage!"
echo ""
echo "Need help? Check the configuration in:"
echo "📁 software/system/virt.nix"
