{ config, pkgs, ... }:

# If the network adapter does not want to start do
# sudo virsh net-start default
# Or make it default to start every time by running
# virsh net-autostart default
#
# Verify the interface is up like this
#sudo virsh net-list
# Name      State    Autostart   Persistent
#--------------------------------------------
# default   active   yes         yes
#
#
# libvirt's default network runs its own dnsmasq on the virtual NIC, which
# can collide with a DNS resolver bound to the same interface. blocky, which
# this fleet runs, listens on 127.0.0.1 only and does not collide — a host
# running libvirt and blocky together may still need to force that
# explicitly in its own networking.nix if libvirt claims :53 first.
#
# If a collision does appear, the virtual network is what to stop:
#
#   sudo virsh net-destroy default    # release it
#   sudo virsh net-start default      # bring it back
#
# Windows 11 VM Setup:
# 1. Create VM in virt-manager with:
#    - Firmware: UEFI x86_64 (OVMF_CODE.secboot.fd)
#    - Enable TPM v2.0 device (Emulated, Model: TIS)
#    - Enable Secure Boot
#    - At least 4GB RAM, 2 CPU cores
#    - Chipset: Q35
#    - Disk: VirtIO, at least 64GB
# 2. Download Windows 11 ISO and virtio drivers from:
#    https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/
# 3. Attach virtio-win ISO as second CD-ROM during installation
#
{
  config = {
    environment.systemPackages = with pkgs; [
      (writeScriptBin "vm-import" (builtins.readFile ../../../dotfiles/scripts/vm-import.sh))
      OVMF
      libosinfo
      libvirt-glib
      spice
      spice-gtk
      spice-protocol
      virt-manager
      virt-viewer
      win-spice
      virtio-win
      # Additional tools for Windows 11 VMs
      swtpm
      qemu_full
      virtiofsd
      bridge-utils
      iptables
    ];

    programs.dconf.enable = true;

    # Manage the virtualisation services
    virtualisation = {
      libvirtd = {
        enable = true;
        qemu = {
          swtpm.enable = true;
          vhostUserPackages = with pkgs; [ virtiofsd ];
          # Additional settings for Windows 11 support
          runAsRoot = false;
        };
        allowedBridges = [ "virbr0" ];
      };
      spiceUSBRedirection.enable = true;
    };

    # Create shared VM directories in /home for ZFS backup coverage
    systemd.tmpfiles.rules = [
      "d /home/VMs 0775 root users -"
      "d /home/VMs/images 0775 qemu-libvirtd qemu-libvirtd -"
      "d /home/VMs/iso 0775 root users -"
      "d /home/VMs/config 0775 root users -"
      "d /home/VMs/smb-share 0775 root users -"
    ];

    # Enable additional features for Windows 11 VMs
    boot.kernelModules = [ "vfio-pci" ];
    services.spice-vdagentd.enable = true;

    # Configure libvirt default pool to use /home/VMs
    systemd.services.libvirtd-home-pools = {
      description = "Configure libvirt storage pools in /home/VMs";
      after = [ "libvirtd.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.libvirt
        pkgs.gnused
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Wait for libvirtd to be ready
        sleep 5

        # Ensure default network is started and set to autostart
        virsh net-start default || true
        virsh net-autostart default || true

        # Check if default pool points to the wrong path
        CURRENT_PATH=$(virsh pool-dumpxml default 2>/dev/null | grep '<path>' | sed 's|.*<path>\(.*\)</path>.*|\1|' || echo "")
        if [ "$CURRENT_PATH" != "/home/VMs/images" ]; then
          # Stop and remove the old pool definition
          virsh pool-stop default 2>/dev/null || true
          virsh pool-destroy default 2>/dev/null || true
          virsh pool-undefine default 2>/dev/null || true
          # Define with correct path
          virsh pool-define-as default dir - - - - /home/VMs/images
          virsh pool-build default 2>/dev/null || true
          virsh pool-start default
          virsh pool-autostart default
        else
          virsh pool-start default 2>/dev/null || true
          virsh pool-autostart default 2>/dev/null || true
        fi
        virsh pool-refresh default || true

        # Set up ISO pool at /home/VMs/iso
        ISO_PATH=$(virsh pool-dumpxml iso 2>/dev/null | grep '<path>' | sed 's|.*<path>\(.*\)</path>.*|\1|' || echo "")
        if [ "$ISO_PATH" != "/home/VMs/iso" ]; then
          virsh pool-stop iso 2>/dev/null || true
          virsh pool-destroy iso 2>/dev/null || true
          virsh pool-undefine iso 2>/dev/null || true
          virsh pool-define-as iso dir - - - - /home/VMs/iso
          virsh pool-build iso 2>/dev/null || true
          virsh pool-start iso
          virsh pool-autostart iso
        else
          virsh pool-start iso 2>/dev/null || true
          virsh pool-autostart iso 2>/dev/null || true
        fi

        # Import VM domain definitions from /home/VMs/config/
        for xml in /home/VMs/config/*.xml; do
          [ -f "$xml" ] || continue
          VM_NAME=$(sed -n 's|.*<name>\(.*\)</name>.*|\1|p' "$xml" | head -1)
          if [ -n "$VM_NAME" ] && ! virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
            virsh define "$xml" || true
          fi
        done

        # Export any domain definitions not yet saved to /home/VMs/config/
        for VM_NAME in $(virsh list --all --name 2>/dev/null); do
          [ -n "$VM_NAME" ] || continue
          if [ ! -f "/home/VMs/config/$VM_NAME.xml" ]; then
            virsh dumpxml "$VM_NAME" > "/home/VMs/config/$VM_NAME.xml" 2>/dev/null || true
          fi
        done
      '';
    };
  };
}
