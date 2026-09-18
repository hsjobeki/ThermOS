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
      extraModules.tests.modules.kmPublisher = kmPublisher;
      options."/tests/kmPublisher".data = data;
    };

  # Tree with the initrd-network hardware module dropped in
  initrdNetworkTree = entrypoint.configure {
    modules = [ "/hardware/initrd-network" ];
  };
in
{
  # hardware/initrd-network impl: selected publishes af_packet at (initrd, force)
  testInitrdNetworkPublishesAfPacket = {
    expr = (initrdNetworkTree.modules.hardware.modules."initrd-network" { })."kernel-modules";
    expected = [
      {
        name = "af_packet";
        stage = "initrd";
        mode = "force";
      }
    ];
  };

  # builders/initrd: a published (initrd, force) module (initrd-network af_packet)
  # flows through the contract into the initrd closure.
  testInitrdForceModuleBuilds = {
    expr = isDerivation (initrdNetworkTree.modules.builders.modules.initrd { }).derivation;
    expected = true;
  };

  # builders/initrd: publish (initrd, available)
  testInitrdAvailableModuleBuilds = {
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
      isDerivation (t.modules.builders.modules.initrd { }).derivation;
    expected = true;
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
