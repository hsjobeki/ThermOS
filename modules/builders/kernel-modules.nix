# Stage-2 kernel module substrate.
#
# Subscribes /contracts/kernel-modules and owns everything the running system
# needs to load (system, *) modules:
#   - derivation: a self-contained /lib/modules/<version> closure (modprobe- and
#     udev-resolvable) that the rootfs symlinks in. Contains both force and
#     available modules plus their dependencies.
#   - etc: /etc/modules-load.d/thermos.conf listing the (system, force) names.
#     systemd-modules-load.service reads it (stock systemd enables it via
#     sysinit.target). It needs CAP_SYS_MODULE, so it force-loads on QEMU/metal
#     but no-ops under nspawn, which drops that capability.
#   - packages: kmod (modprobe/lsmod/rmmod) for admin tooling, shipped only when
#     there are system modules to act on.
#
# (initrd, *) modules are handled by the initrd builder, not here. With no
# (system, *) publisher the closure is an empty directory and nothing is added
# to /etc or the system path: the substrate ships dormant.
{ types, ... }:
{
  name = "kernel-modules";

  subscribe = [ "/contracts/kernel-modules" ];
  publish = [
    "/contracts/etc"
    "/contracts/packages"
  ];

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
  };

  impl =
    { inputs, subscriptions, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      lib = inputs.nixpkgs.lib;
      kernel = pkgs.linuxPackages.kernel;

      mods = subscriptions."kernel-modules";
      systemMods = builtins.filter (m: m.stage == "system") mods;
      systemForce = lib.unique (map (m: m.name) (builtins.filter (m: m.mode == "force") systemMods));
      systemAvail = lib.unique (map (m: m.name) (builtins.filter (m: m.mode == "available") systemMods));
      # Both force and available modules must live in the tree: force for
      # systemd-modules-load, available for udev modalias autoload.
      systemAll = lib.unique (systemForce ++ systemAvail);

      emptyFirmware = pkgs.runCommand "empty-firmware" { } "mkdir -p $out";
      closure =
        if systemAll == [ ] then
          pkgs.runCommand "thermos-modules-empty" { } "mkdir -p $out/lib/modules"
        else
          pkgs.makeModulesClosure {
            rootModules = systemAll;
            kernel = kernel.modules;
            firmware = emptyFirmware;
            allowMissing = false;
          };

      confText = lib.concatStringsSep "\n" systemForce + "\n";
    in
    {
      derivation = closure;
      etc = lib.optional (systemForce != [ ]) {
        name = "modules-load.d/thermos.conf";
        text = confText;
      };
      packages = lib.optional (systemAll != [ ]) { package = pkgs.kmod; };
    };
}
