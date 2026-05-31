# Minimal initrd for QEMU direct kernel boot.
# Loads virtio + ext4 modules, mounts root, switch_root to real rootfs.
{ types, ... }:
{
  name = "initrd-builder";

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
  };

  options = {
    kernelModules = {
      type = types.any;
      default = [
        "virtio_blk"
        "virtio_pci"
        "ext4"
      ];
    };
  };

  impl =
    { inputs, options, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      kernel = pkgs.linuxPackages.kernel;

      emptyFirmware = pkgs.runCommand "empty-firmware" { } "mkdir -p $out";

      modulesClosure = pkgs.makeModulesClosure {
        rootModules = options.kernelModules;
        kernel = kernel.modules;
        firmware = emptyFirmware;
        allowMissing = false;
      };

      modprobeLines = builtins.concatStringsSep "\n" (map (m: "modprobe ${m}") options.kernelModules);

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
