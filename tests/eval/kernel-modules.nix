{
  entrypoint,
  tree,
  nixpkgs-lib,
  ...
}:
let
  inherit (nixpkgs-lib) isDerivation;

  # A synthetic "kernel-modules" publisher
  kmPublisher = import ../fixtures/kernel-modules-publisher.nix { inherit (entrypoint) types; };

  treeWith =
    data:
    entrypoint.configure {
      modules.tests.modules.kmPublisher = kmPublisher;
      options."/tests/kmPublisher".data = data;
    };
in
{
  # core/initrd-network impl: enabled publishes af_packet at (initrd, force)
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

  # core/initrd-network: disabled publishes nothing
  testInitrdNetworkDisabled = {
    expr = (tree.modules.core.modules."initrd-network" { })."kernel-modules";
    expected = [ ];
  };

  # builders/initrd: a published (initrd, force) module (initrd-network af_packet)
  # flows through the contract into the initrd closure.
  testInitrdForceModuleBuilds = {
    expr =
      let
        reconfigured = tree.override {
          options = {
            "/core/initrd-network" = {
              enable = true;
            };
          };
        };
      in
      isDerivation (reconfigured.modules.builders.modules.initrd { }).derivation;
    expected = true;
  };

  # builders/initrd: (initrd, available) is rejected
  # no udev in the busybox initrd
  testInitrdAvailableThrows = {
    expr =
      let
        t = treeWith [
          {
            name = "e1000e";
            stage = "initrd";
            mode = "available";
          }
        ];
      in
      (t.modules.builders.modules.initrd { }).derivation.drvPath;
    expectedError.type = "ThrownError";
    expectedError.msg = ".*initrd, available.*udev.*";
  };

  # builders/initrd: stage=system modules are excluded
  testInitrdIgnoresSystemModules = {
    expr =
      let
        t = treeWith [
          {
            name = "loop";
            stage = "system";
            mode = "force";
          }
        ];
      in
      isDerivation (t.modules.builders.modules.initrd { }).derivation;
    expected = true;
  };

  # builders/kernel-modules: no (system, *)
  # publisher means empty etc + packages
  testBuilderDormantByDefault = {
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
