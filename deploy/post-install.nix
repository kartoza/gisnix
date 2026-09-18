{ pkgs, projectConfig, ... }:

pkgs.writeShellScriptBin "post-install" ''
  function usage {
    echo -e "\nUSAGE:  post-install <target-host>"
  }

  function remoteCp {
    local file=$1
    local host=$2
    # Using accept-new to accept new host keys while still rejecting changed keys
    # This is more secure than 'no' which would accept any key including MITM attacks
    ${pkgs.openssh}/bin/scp \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile=/dev/null \
    $file $host
  }

  function remoteCmd {
    local file=$1
    local host=$2
    # Using accept-new to accept new host keys while still rejecting changed keys
    # This is more secure than 'no' which would accept any key including MITM attacks
    ${pkgs.openssh}/bin/ssh \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile=/dev/null \
    $file $host
  }

  [ -z "$1" ] && echo -e "\nTarget host is missing !" && usage && exit 1

  set -euo pipefail

  targetHost=$1

  echo -e "\nPost-install script will be executed on host $targetHost."
  echo
  echo "[CTRL-C to abort, ENTER to continue]"
  read

  echo -e "\nPrivate SSH key used for secrets decryption."
  read -p "Enter path to a file (leave empty to skip): " secretSSHKey

  echo -e "\nHeadscale VPN server."
  read -p "Enter server address (leave empty to skip): " vpnServerHost

  # Secrets decryption
  echo -e "\nPOST-INSTALL: Installing secrets private key ..."
  if [ ! -z "$secretSSHKey" ]; then
    remoteCp $secretSSHKey ${projectConfig.adminUser}@$targetHost:/tmp/agenix.key

    remoteCmd ${projectConfig.adminUser}@$targetHost \
      "sudo mkdir -pv /root/.agenix && sudo chmod 0700 /root/.agenix"

    remoteCmd ${projectConfig.adminUser}@$targetHost \
      "sudo mv -fv /tmp/agenix.key /root/.agenix/"
  else
    echo "... skipped"
  fi

  # VPN network
  echo -e "\nPOST-INSTALL: Connecting host to VPN network ..."
  if [ ! -z "$vpnServerHost" ]; then
    hostname=$(remoteCmd ${projectConfig.adminUser}@$targetHost "hostname")

    remoteCmd ${projectConfig.adminUser}@$vpnServerHost \
      "sudo headscale users create $hostname"

    vpnAuthKey=$( \
      remoteCmd ${projectConfig.adminUser}@$vpnServerHost \
        "sudo headscale preauthkeys -u $hostname create" \
    )

    vpnUpCmd="sudo tailscale up --login-server 'https://$vpnServerHost' --auth-key $vpnAuthKey"
    echo "Up command: $vpnUpCmd"
    remoteCmd ${projectConfig.adminUser}@$targetHost "$vpnUpCmd"
  else
    echo "... skipped"
  fi

  # Done
  echo -e "\nPOST-INSTALL: Post-installation has finished."
  echo "Machine will reboot now ..."
  remoteCmd ${projectConfig.adminUser}@$targetHost \
    "sleep 3 && sudo reboot"
''
