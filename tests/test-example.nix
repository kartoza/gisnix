{
  inputs,
  outputs,
  projectConfig,
  hostConfig,
  lib,
  ...
}:
{
  name = "Test example host";

  # runNixOSTest pins `nixpkgs.*` read-only inside the node, so the repo
  # overlays that profiles/common.nix depends on have to be supplied as a
  # prebuilt pkgs here instead.
  node.pkgs = lib.mkForce (
    import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = false;
      overlays = import ./../overlays { inherit inputs; };
    }
  );

  nodes = {
    server =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      {
        _module.args = {
          inherit
            inputs
            outputs
            projectConfig
            hostConfig
            ;
          hostname = "example";
        };

        imports = [
          inputs.agenix.nixosModules.default

          ./../profiles/common.nix
          ./../users/example.nix
        ];
      };
  };

  testScript =
    { nodes, ... }:
    ''
      start_all()

      with subtest("example account exists and is usable"):
          server.succeed("id example")
          server.succeed("test -d /home/example")

      with subtest("example is in the wheel group"):
          groups = server.succeed("su - example -c 'groups'").strip()
          assert "wheel" in groups, f"example not in wheel group: {groups}"
    '';
}
