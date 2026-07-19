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
      "uki"
      "units"
      "users"
    ];
  };

  testCoreChildren = {
    expr = attrNames tree.modules.core.modules;
    expected = [
      "base"
      "graphics"
      "initrd-network"
      "initrd-storage"
      "system-input"
    ];
  };

  testServiceChildren = {
    expr = attrNames tree.modules.services.modules;
    expected = [
      "dbus"
      "desktop"
      "getty"
      "networkd"
      "openssh"
      "polkit"
      "thermos-daemon"
    ];
  };

  testMiddlewareChildren = {
    expr = attrNames tree.modules.middleware.modules;
    expected = [ "pam" ];
  };
}
