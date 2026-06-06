# Minimal initrd for QEMU direct kernel boot.
# Loads virtio + ext4 plus any (initrd, force) modules, mounts root, then
# switch_root to the real rootfs.
{ types, ... }:
{
  name = "initrd";

  subscribe = [ "/contracts/kernel-modules" ];

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
  };

  options = {
    # Builder-intrinsic modules to reach the real root: virtio transport and
    # ext4. Modules declared at (initrd, force) on /contracts/kernel-modules
    # are merged on top of these.
    kernelModules = {
      type = types.any;
      default = [
        "virtio_blk"
        "virtio_pci"
        "virtio_net"
        "ext4"
      ];
    };
  };

  impl =
    {
      inputs,
      options,
      subscriptions,
      ...
    }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      lib = inputs.nixpkgs.lib;
      kernel = pkgs.linuxPackages.kernel;

      # Modules declared at stage=initrd on /contracts/kernel-modules.
      mods = subscriptions."kernel-modules";
      initrdMods = builtins.filter (m: m.stage == "initrd") mods;
      initrdForce = map (m: m.name) (builtins.filter (m: m.mode == "force") initrdMods);
      initrdAvail = builtins.filter (m: m.mode == "available") initrdMods;

      # (initrd, available) means "present for udev to autoload", but the
      # busybox initrd has no udev, so it would be a silent no-op. Reject it.
      allModules =
        if initrdAvail != [ ] then
          throw "kernel-modules: (initrd, available) needs udev in the initrd, which ThermOS does not have yet (systemd-in-initrd roadmap). Use stage=system for udev autoload, or stage=initrd mode=force to force-load."
        else
          lib.unique (options.kernelModules ++ initrdForce);

      emptyFirmware = pkgs.runCommand "empty-firmware" { } "mkdir -p $out";

      modulesClosure = pkgs.makeModulesClosure {
        rootModules = allModules;
        kernel = kernel.modules;
        firmware = emptyFirmware;
        allowMissing = false;
      };

      modprobeLines = builtins.concatStringsSep "\n" (map (m: "modprobe ${m}") allModules);

      init = pkgs.writeScript "init" ''
        #!/bin/busybox sh
        /bin/busybox --install -s /bin
        mkdir -p /dev /proc /sys /sysroot
        mount -t devtmpfs devtmpfs /dev
        mount -t proc proc /proc
        mount -t sysfs sysfs /sys
        ${modprobeLines}
        mount -t ext4 /dev/vda /sysroot
        exec switch_root /sysroot /sbin/init
      '';
    in
    {
      inherit kernel;

      derivation = pkgs.makeInitrdNG {
        name = "thermos-initrd";
        contents = [
          {
            source = "${pkgs.busybox}/bin/busybox";
            target = "/bin/busybox";
          }
          {
            source = init;
            target = "/init";
          }
          {
            source = "${modulesClosure}/lib/modules";
            target = "/lib/modules";
          }
        ];
      };
    };
}
