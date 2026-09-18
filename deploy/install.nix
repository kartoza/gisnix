{
  pkgs,
  lib,
  nixos-anywhere-pkg,
  projectConfig,
  serverConfig,
  postInstallScript,
  hostname,
  ...
}:

lib.throwIf (projectConfig.environmentName == "dev")
  ''
    Can't deploy with insecure development configuration enabled !
    Set the environment name to another value than `dev` using

    ```
    echo <ENVIRONMENT-NAME> > environment.txt
    ```
  ''
  pkgs.writeShellScriptBin
  "install"
  ''
    set -euo pipefail

    function usage {
      echo -e "\nUSAGE:  nix run .#<hostname>-deploy"
    }

    echo -e "\nThis script will launch and install a new NixOS machine."
    echo
    echo "NixOS configuration:    ${hostname}"
    echo "Deployment environment: ${projectConfig.environmentName}"
    echo
    echo "[CTRL-C to abort, ENTER to continue]"
    read

    # Machine creation
    echo -e "\nDEPLOY: Creating server machine ..."
    targetHost=$( \
      ${lib.getExe pkgs.hcloud} server create \
        --context ${projectConfig.hetznerContext} \
        --name ${hostname}-${projectConfig.environmentName} \
        --label hostname=${hostname} \
        --label environment=${projectConfig.environmentName} \
        --image ${projectConfig.hetznerImage} \
        --ssh-key ${projectConfig.hetznerSSHKey} \
        --output json \
        ${lib.concatStringsSep " " serverConfig} \
        ${
          lib.optionalString (
            projectConfig.environmentName == "prod"
          ) "--enable-backup --enable-protection delete,rebuild"
        } \
      | ${lib.getExe pkgs.jq} --raw-output '.server.public_net.ipv4.ip' \
    )

    # Installation
     echo -e "\nDEPLOY: Installing NixOS ..."
    ${nixos-anywhere-pkg}/bin/nixos-anywhere \
      --flake .#${hostname} \
      --target-host root@$targetHost

    # Done
    echo -e "\nDEPLOY: Installation has finished. Launch post-install script:"
    echo "${pkgs.lib.getExe postInstallScript} $targetHost"
  ''
