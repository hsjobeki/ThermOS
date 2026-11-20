{ entrypoint, tree, ... }:
let
  inherit (builtins) attrNames;
in
{
  testTopLevelModules = {
    expr = attrNames tree.modules;
    expected = [
      "builders"
      "contracts"
      "core"
      "hardware"
      "middleware"
      "nixpkgs"
      "services"
    ];
  };

  testContractChildren = {
    expr = attrNames tree.modules.contracts.modules;
    expected = [
      "assertions"
      "etc"
      "groups"
      "kernel-modules"
      "packages"
      "pam"
      "tmpfiles"
      "units"
      "users"
    ];
  };

  testBuilderChildren = {
    expr = attrNames tree.modules.builders.modules;
    expected = [
      "etc"
      "image"
      "initrd"
      "kernel-modules"
      "packages"
      "rootfs"
      "tmpfiles"
      "toplevel"
      "uki"
      "units"
      "users"
    ];
  };

  testCoreChildren = {
    expr = attrNames tree.modules.core.modules;
    expected = [ "base" ];
  };

  testMiddlewareChildren = {
    expr = attrNames tree.modules.middleware.modules;
    expected = [ "pam" ];
  };

  # entrypoint.configure: membership is the selection. A selected module is in
  # the tree; an unselected one does not exist.
  testSelectedServiceChildren = {
    expr = attrNames tree.modules.services.modules;
    expected = [
      "dbus"
      "getty"
      "networkd"
      "openssh"
    ];
  };

  testUnselectedGroupIsEmpty = {
    expr = attrNames tree.modules.hardware.modules;
    expected = [ ];
  };

  testHardwareSelection = {
    expr =
      let
        t = entrypoint.configure {
          modules = [
            "/hardware/initrd-storage"
            "/hardware/system-input"
          ];
        };
      in
      {
        hardware = attrNames t.modules.hardware.modules;
        services = attrNames t.modules.services.modules;
      };
    expected = {
      hardware = [
        "initrd-storage"
        "system-input"
      ];
      services = [ ];
    };
  };

  testUnknownModuleThrows = {
    expr = entrypoint.configure { modules = [ "/services/nope" ]; };
    expectedError.type = "ThrownError";
    expectedError.msg = "thermos: unknown module '/services/nope'";
  };

  testCatalogPaths = {
    expr = entrypoint.catalogPaths;
    expected = [
      "/hardware/initrd-network"
      "/hardware/initrd-storage"
      "/hardware/system-input"
      "/services/dbus"
      "/services/getty"
      "/services/networkd"
      "/services/openssh"
    ];
  };
}
