{ pkgs, ... }:
{
  # Dygma keyboards (e.g. the Defy — shows up as "Sonsei-BLE - 1" when paired
  # over Bluetooth, USB vendor 35ef) are configured with Bazecor, which talks
  # to the board over a USB serial / hidraw connection using the Focus
  # protocol. Install the udev rules Bazecor ships (60-dygma.rules) so the
  # logged-in user gets uaccess to that node — without them Bazecor cannot
  # open the device and reports "no keyboard detected".
  #
  # IMPORTANT: Bazecor only communicates over USB (the USB-C cable) or the
  # Dygma RF/Neuron dongle — NOT over Bluetooth. Bluetooth exposes only the
  # HID typing endpoints, so connect the cable to configure the keyboard.
  #
  # The bazecor package itself is installed per-user in users/tim.nix.
  services.udev.packages = [ pkgs.bazecor ];
}
