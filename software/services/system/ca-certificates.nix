# Trust extra CA certificates system-wide. security.pki.certificateFiles is
# what actually adds them to the trust store: Chromium, Brave, Chrome,
# Ungoogled Chromium, curl, wget. Merely placing a PEM under /etc trusts
# nothing.
#
# Off by default — no certificate is bundled here. A deployment that needs to
# trust a private/enterprise CA (e.g. an internal MITM proxy, a self-hosted
# service with a private root) points extraCA.certificateFiles at its own
# chain, kept alongside its own host/user config rather than in this shared
# module.
{
  config,
  lib,
  ...
}:
let
  cfg = config.extraCA;
in
{
  options.extraCA = {
    certificateFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Extra CA certificate chain files to trust system-wide, in addition to
        the standard public CA bundle.
      '';
    };
  };

  config = lib.mkIf (cfg.certificateFiles != [ ]) {
    security.pki.certificateFiles = cfg.certificateFiles;

    # Firefox needs explicit policy configuration to trust additional CAs.
    programs.firefox = {
      enable = true;
      policies.Certificates.ImportEnterpriseRoots = true;
      preferences."security.enterprise_roots.enabled" = true;
    };
  };
}
