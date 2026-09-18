{
  config,
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    #yubikey-manager-qt # launch using ykman-gui - out of date and insecure
    # yubikey-agent removed: it grabs the PIV slot over PC/SC and contended
    # with pcscd / FIDO2, causing flaky WebAuthn prompts. Re-add only if PIV
    # SSH is actually needed.
    yubikey-manager
    yubioath-flutter
  ];
  services.udev.packages = [
    pkgs.yubikey-personalization
  ];

  # pcscd is needed for PIV / PKCS#11 smartcard use (e.g. client certificates).
  # Firefox WebAuthn/FIDO2 itself talks to the token directly via HIDRAW.
  services.pcscd.enable = true;

  # Keep the YubiKey out of USB autosuspend. The host-wide rule in
  # hosts/abyss/hardware.nix sets autosuspend=2s for all USB devices while on
  # battery, which causes pcscd to lose the reader and makes FIDO2 prompts
  # intermittently fail. Pin the Yubico vendor ID (1050) to "always on".
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{power/autosuspend}="-1", ATTR{power/control}="on"
  '';
}
