#!/usr/bin/env bash
set -e

echo "=== Testing NixOS Installation with Disko ==="
echo "This will:"
echo "1. Wipe and recreate the NVMe disk images"
echo "2. Start a VM with NixOS installer environment"
echo "3. Run disko to partition the drives"
echo "4. Install NixOS with your configuration"
echo "5. Boot the installed system"
echo ""

# Recreate disk images to ensure clean state
echo "Recreating NVMe disk images..."
rm -f nvme0.qcow2 nvme1.qcow2
rm -f abyss-laptop.qcow2
qemu-img create -f qcow2 nvme0.qcow2 10G
qemu-img create -f qcow2 nvme1.qcow2 10G
kz abyss-laptop-vm

echo "Commands to run in the VM:"
echo "1. cd /nix-config"

echo "2. sudo disko --mode disko ./hosts/abyss-laptop/disks.nix"
echo " This does not work yet......"
echo "3. sudo nixos-install --root /mnt --flake /nix-config#abyss-laptop"
echo "4. sudo reboot"
echo ""
echo "=== Step 2: Test the installed system ==="
echo "After reboot, the system should boot from ZFS with encryption"
echo "The nix-config folder will be available at /mnt/nix-config"
echo ""

# Start the installer VM
echo "Starting installer VM..."
kz abyss-laptop-vm

echo "Installation test complete!"
