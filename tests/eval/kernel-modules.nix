{
  entrypoint,
  tree,
  lib,
  ...
}:
let
  inherit (lib) isDerivation;
  types = tree.types;
  initrdImpl = (import ../../modules/builders/initrd.nix { inherit types; }).impl;
in
{
  testInitrdNetworkEnabled = {
    expr = (tree.modules.core.modules."initrd-network" { enable = true; })."kernel-modules";
    expected = [
      {
        name = "af_packet";
        stage = "initrd";
        mode = "force";
      }
    ];
  };

  testInitrdNetworkDisabled = {
    expr = (tree.modules.core.modules."initrd-network" { })."kernel-modules";
    expected = [ ];
  };

  testInitrdForceModuleBuilds = {
    expr =
      isDerivation
        (initrdImpl {
          inputs.nixpkgs = { inherit (entrypoint) pkgs lib; };
          options.kernelModules = [ "ext4" ];
          subscriptions."kernel-modules" = [
            {
              name = "af_packet";
              stage = "initrd";
              mode = "force";
            }
          ];
        }).derivation;
    expected = true;
  };

  testInitrdAvailableThrows = {
    expr =
      (initrdImpl {
        inputs.nixpkgs = { inherit (entrypoint) pkgs lib; };
        options.kernelModules = [ "ext4" ];
        subscriptions."kernel-modules" = [
          {
            name = "e1000e";
            stage = "initrd";
            mode = "available";
          }
        ];
      }).derivation.drvPath;
    expectedError.type = "ThrownError";
    expectedError.msg = ".*initrd, available.*udev.*";
  };

  testInitrdIgnoresSystemModules = {
    # stage=system modules must not enter the initrd; builder still succeeds.
    expr =
      isDerivation
        (initrdImpl {
          inputs.nixpkgs = { inherit (entrypoint) pkgs lib; };
          options.kernelModules = [ "ext4" ];
          subscriptions."kernel-modules" = [
            {
              name = "loop";
              stage = "system";
              mode = "force";
            }
          ];
        }).derivation;
    expected = true;
  };

  testBuilderDormantByDefault = {
    # No (system, *) publisher in the default tree: empty etc + packages.
    expr = {
      etc = (tree.modules.builders.modules."kernel-modules" { }).etc;
      packages = (tree.modules.builders.modules."kernel-modules" { }).packages;
    };
    expected = {
      etc = [ ];
      packages = [ ];
    };
  };
}
