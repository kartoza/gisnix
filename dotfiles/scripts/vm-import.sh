#!/usr/bin/env bash
# vm-import: Import VM disk images from /home/VMs/images/ into libvirt
# Creates domain definitions and saves them to /home/VMs/config/

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo vm-import)"
    exit 1
fi

IMAGES_DIR="/home/VMs/images"
CONFIG_DIR="/home/VMs/config"
ISO_DIR="/home/VMs/iso"

mkdir -p "$CONFIG_DIR"

# Collect available disk images (skip UEFI vars files)
IMAGES=()
for img in "$IMAGES_DIR"/*.qcow2; do
    [ -f "$img" ] || continue
    IMAGES+=("$(basename "$img")")
done

if [ ${#IMAGES[@]} -eq 0 ]; then
    echo "No .qcow2 images found in $IMAGES_DIR"
    exit 1
fi

echo "Found ${#IMAGES[@]} disk image(s) in $IMAGES_DIR:"
printf "  %s\n" "${IMAGES[@]}"
echo ""

for IMG_FILE in "${IMAGES[@]}"; do
    IMG_PATH="$IMAGES_DIR/$IMG_FILE"
    VM_NAME="${IMG_FILE%.qcow2}"

    # Skip if already defined
    if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
        echo "[$VM_NAME] Already defined, skipping."
        continue
    fi

    echo "--- Importing: $VM_NAME ---"

    # Detect OS variant
    case "$VM_NAME" in
        *win11*|*windows11*)
            OS_VARIANT="win11"
            RAM=8192
            CPUS=4
            FIRMWARE="uefi"
            ;;
        *ubuntu*)
            OS_VARIANT="ubuntu24.04"
            RAM=4096
            CPUS=4
            FIRMWARE="bios"
            ;;
        *debian*)
            OS_VARIANT="debian12"
            RAM=4096
            CPUS=2
            FIRMWARE="bios"
            ;;
        *nixos*)
            OS_VARIANT="nixos-unstable"
            RAM=4096
            CPUS=2
            FIRMWARE="bios"
            ;;
        *)
            OS_VARIANT="generic"
            RAM=4096
            CPUS=2
            FIRMWARE="bios"
            ;;
    esac

    echo "  OS variant: $OS_VARIANT"
    echo "  RAM: ${RAM}MB, CPUs: $CPUS, Firmware: $FIRMWARE"

    # Build virt-install command
    VIRT_ARGS=(
        --name "$VM_NAME"
        --ram "$RAM"
        --vcpus "$CPUS"
        --import
        --disk "path=$IMG_PATH,format=qcow2"
        --os-variant "$OS_VARIANT"
        --noautoconsole
        --network network=default
    )

    # Windows 11 needs UEFI + TPM
    if [ "$FIRMWARE" = "uefi" ]; then
        VIRT_ARGS+=(--boot uefi)
        VIRT_ARGS+=(--tpm backend.type=emulated,backend.version=2.0,model=tis)
        # Attach VARS file if it exists
        VARS_FILE="$IMAGES_DIR/${VM_NAME}_VARS.fd"
        if [ -f "$VARS_FILE" ]; then
            echo "  Found UEFI VARS: $VARS_FILE"
        fi
    fi

    if virt-install "${VIRT_ARGS[@]}" 2>&1; then
        echo "  Imported successfully."
        # Stop it immediately (import starts the VM)
        virsh destroy "$VM_NAME" 2>/dev/null || true
        # Save the domain XML
        virsh dumpxml "$VM_NAME" > "$CONFIG_DIR/$VM_NAME.xml"
        echo "  Config saved to $CONFIG_DIR/$VM_NAME.xml"
    else
        echo "  WARNING: Failed to import $VM_NAME"
    fi
    echo ""
done

echo "=== Import complete ==="
virsh list --all
