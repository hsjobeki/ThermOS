{ tree, ... }:
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
      "units"
      "users"
    ];
  };

  testCoreChildren = {
    expr = attrNames tree.modules.core.modules;
    expected = [
      "base"
      "initrd-network"
      "initrd-storage"
    ];
  };

  testServiceChildren = {
    expr = attrNames tree.modules.services.modules;
    expected = [
      "dbus"
      "getty"
      "networkd"
      "openssh"
    ];
  };

  testMiddlewareChildren = {
    expr = attrNames tree.modules.middleware.modules;
    expected = [ "pam" ];
  };
}
