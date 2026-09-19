# openrazer 3.12.3 predates the hid_report_raw_event bufsize-hardening
# parameter (the signature is now: data, bufsize, size, interrupt). That change
# landed in mainline and was backported into the 6.12 LTS series, so the patch
# is needed by every kernel series we ship. Upstream tracks the same class of
# breakage in https://github.com/openrazer/openrazer/issues/2821 — drop this
# once nixpkgs ships a release with a fixed guard.
#
# Extracted from overlays/default.nix so it can also be applied to a kernel
# package set from a different nixpkgs (a host may source its kernel from
# nixpkgs-master in its own hardware.nix). openrazer is not cosmetic
# here: a kanata-keyboard.nix that depends on the openrazer group and
# openrazer-daemon.service for keyboard remapping means an unpatched
# openrazer fails the build rather than merely losing RGB.
kernelPackages:
kernelPackages.extend (
  _kfinal: kprev: {
    openrazer = kprev.openrazer.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace driver/razerkbd_driver.c \
          --replace-fail "hid_report_raw_event(hdev, HID_INPUT_REPORT, xdata, sizeof(xdata), 0);" \
                         "hid_report_raw_event(hdev, HID_INPUT_REPORT, xdata, sizeof(xdata), sizeof(xdata), 0);"
      '';
    });
  }
)
