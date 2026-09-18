#!/usr/bin/env bash

# Hardware configuration generator for NixOS flake
# This script uses nixos-generate-config to generate hardware configuration
# and then adds flake-specific customizations

set -euo pipefail

# Default output file
OUTPUT_FILE="hardware.nix"
HOSTNAME=""
TEMP_DIR=""

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -o, --output FILE     Output file (default: hardware.nix)"
    echo "  -h, --hostname NAME   Hostname for comments (default: current hostname)"
    echo "  --help               Show this help message"
    echo ""
    echo "This utility uses nixos-generate-config to scan hardware and generates"
    echo "a hardware.nix file compatible with this NixOS flake configuration."
}

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

log() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

# Set up cleanup trap
trap cleanup EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--hostname)
            HOSTNAME="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Get hostname if not provided
if [[ -z "$HOSTNAME" ]]; then
    HOSTNAME=$(hostname)
fi

log "Generating hardware configuration for $HOSTNAME"
log "Output file: $OUTPUT_FILE"

# Check if nixos-generate-config is available
if ! command -v nixos-generate-config >/dev/null 2>&1; then
    error "nixos-generate-config not found. Please ensure you're running on NixOS"
    exit 1
fi

# Check if we're running as root or have sudo access for hardware detection
if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    error "This script requires root privileges to scan hardware properly"
    error "Please run with sudo or as root"
    exit 1
fi

# Function to detect if bluetooth hardware is present
detect_bluetooth() {
    if lsusb 2>/dev/null | grep -qi "bluetooth\|btusb" || lspci 2>/dev/null | grep -qi "bluetooth"; then
        return 0
    fi
    return 1
}

# Function to detect if QMK keyboard hardware is present
detect_qmk() {
    if lsusb 2>/dev/null | grep -qi "via\|qmk\|zsa" || lsusb 2>/dev/null | grep -E "04d9:|feed:" >/dev/null; then
        return 0
    fi
    return 1
}

# Function to detect Framework laptop
detect_framework() {
    if command -v dmidecode >/dev/null 2>&1; then
        if dmidecode -s system-manufacturer 2>/dev/null | grep -qi "framework" ||
           dmidecode -s system-product-name 2>/dev/null | grep -qi "framework"; then
            return 0
        fi
    fi
    return 1
}

# Generate the hardware configuration using nixos-generate-config
generate_config() {
    log "Creating temporary directory for nixos-generate-config..."
    TEMP_DIR=$(mktemp -d)
    
    log "Running nixos-generate-config to detect hardware..."
    if [[ $EUID -eq 0 ]]; then
        nixos-generate-config --dir "$TEMP_DIR"
    else
        sudo nixos-generate-config --dir "$TEMP_DIR"
    fi
    
    local base_hardware_file="$TEMP_DIR/hardware-configuration.nix"
    
    if [[ ! -f "$base_hardware_file" ]]; then
        error "Failed to generate hardware configuration"
        exit 1
    fi
    
    log "Customizing hardware configuration for this flake..."
    
    # Start with the generated hardware configuration
    cp "$base_hardware_file" "$OUTPUT_FILE"
    
    # Add hostname-specific comment if it's a notable system
    if detect_framework; then
        sed -i '1a\\n  # Framework laptop specific hardware configuration' "$OUTPUT_FILE"
    elif [[ "$HOSTNAME" != "nixos" ]]; then
        sed -i "1a\\n  # $HOSTNAME specific hardware configuration" "$OUTPUT_FILE"
    fi
    
    # Add custom enhancements
    local temp_additions
    temp_additions=$(mktemp)
    
    # Bluetooth support
    if detect_bluetooth; then
        cat >> "$temp_additions" << 'EOF'

  # Bluetooth support
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
EOF
    fi
    
    # QMK keyboard support
    if detect_qmk; then
        cat >> "$temp_additions" << 'EOF'

  # QMK Keyboard support
  hardware.keyboard.qmk.enable = true;
  environment.systemPackages = with pkgs; [
    qmk
  ];
EOF
    fi
    
    # Framework-specific settings
    if detect_framework; then
        cat >> "$temp_additions" << 'EOF'

  # Framework laptop specific packages
  environment.systemPackages = with pkgs; [
    framework-tool
  ];
EOF
        
        # Detect GPU vendor for Framework-specific tweaks
        local gpu_vendor=""
        if lspci 2>/dev/null | grep -qi "amd.*vga\|amd.*display"; then
            gpu_vendor="amd"
        fi
        
        # Add Framework-specific kernel parameters
        echo "  # Framework-specific kernel parameters" >> "$temp_additions"
        echo "  boot.kernelParams = [" >> "$temp_additions"
        
        # Detect display resolution for Framework
        local resolution=""
        if command -v xrandr >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
            resolution=$(xrandr 2>/dev/null | grep -E '^\s*[0-9]+x[0-9]+.*\*' | head -1 | awk '{print $1}' || echo "")
        fi
        
        if [[ -n "$resolution" ]]; then
            echo "    \"video=$resolution\"" >> "$temp_additions"
        else
            echo "    # \"video=2560x1600\"  # Uncomment and adjust for your display" >> "$temp_additions"
        fi
        
        if [[ "$gpu_vendor" == "amd" ]]; then
            cat >> "$temp_additions" << 'EOF'
    # AMD GPU workarounds for Framework
    "amdgpu.dcdebugmask=0x10"
EOF
        fi
        
        echo "  ];" >> "$temp_additions"
        
        # Add AMD CPU power management if detected
        if grep -q "vendor_id.*: AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
            cat >> "$temp_additions" << 'EOF'

  # AMD CPU power management
  services.power-profiles-daemon.enable = lib.mkDefault true;
EOF
        fi
    fi
    
    # Insert additions before the final closing brace
    if [[ -s "$temp_additions" ]]; then
        # Remove the last closing brace, add our additions, then add the closing brace back
        sed -i '$d' "$OUTPUT_FILE"
        cat "$temp_additions" >> "$OUTPUT_FILE"
        echo "}" >> "$OUTPUT_FILE"
    fi
    
    rm -f "$temp_additions"
}

# Main execution
generate_config

success "Hardware configuration generated: $OUTPUT_FILE"
log "Generated using nixos-generate-config with custom flake enhancements"

if detect_framework; then
    log "Framework laptop detected - added Framework-specific optimizations"
fi

if detect_bluetooth; then
    log "Bluetooth hardware detected - added bluetooth configuration"
fi

if detect_qmk; then
    log "QMK keyboard detected - added QMK and Via support"
fi

log "Review the generated file and adjust as needed for your specific hardware"