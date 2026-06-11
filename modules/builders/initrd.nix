# systemd-as-PID-1 initrd for QEMU/metal boot.
#
# systemd under initrd.target: udev autoloads storage by modalias,
# systemd-fstab-generator turns root= into the /sysroot mount, initrd-switch-root
#
# Root is found by UUID/PARTUUID via udev
#
# /contracts/kernel-modules (stage=initrd) routing:
#   force     -> /etc/modules-load.d (systemd-modules-load, early)
#   available -> /lib/modules closure (udev modalias autoload)
# Loads here persist across switch_root.
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
    # Minimum to reach a virtio root and keep the NIC across switch_root. Metal
    # storage breadth comes from /core/initrd-storage at (initrd, available).
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
      systemd = pkgs.systemd;
      kernel = pkgs.linuxPackages.kernel;

      # Modules declared at stage=initrd on /contracts/kernel-modules.
      mods = subscriptions."kernel-modules";
      initrdMods = builtins.filter (m: m.stage == "initrd") mods;
      forceNames = lib.unique (map (m: m.name) (builtins.filter (m: m.mode == "force") initrdMods));
      availNames = lib.unique (map (m: m.name) (builtins.filter (m: m.mode == "available") initrdMods));

      # force names also go to modules-load.d; available names rely on udev
      # modalias autoload. allowMissing = false rejects typo names.
      closureModules = lib.unique (options.kernelModules ++ forceNames ++ availNames);

      emptyFirmware = pkgs.runCommand "empty-firmware" { } "mkdir -p $out";
      modulesClosure = pkgs.makeModulesClosure {
        rootModules = closureModules;
        kernel = kernel.modules;
        firmware = emptyFirmware;
        allowMissing = false;
      };

      initrdRelease = pkgs.writeText "initrd-release" ''
        NAME="ThermOS"
        ID=thermos
        VERSION_ID=initrd
        PRETTY_NAME="ThermOS (Initrd)"
      '';

      # Give services a PATH; systemd compiled default omits /bin and /sbin.
      systemConf = pkgs.writeText "system.conf" ''
        [Manager]
        DefaultEnvironment=PATH=/bin:/sbin
      '';

      # Root account locked: the emergency shell exists but is not a login path.
      shadow = pkgs.writeText "shadow" ''
        root:*:::::::
      '';

      modulesLoad = pkgs.writeText "initrd-modules-load.conf" (
        lib.concatStringsSep "\n" forceNames + "\n"
      );

      binEnv = pkgs.buildEnv {
        name = "thermos-initrd-bin";
        paths = [
          pkgs.coreutils
          pkgs.kmod
          pkgs.util-linux
          pkgs.e2fsprogs
          pkgs.bashInteractive
          systemd
        ];
        pathsToLink = [
          "/bin"
          "/sbin"
        ];
      };

      unitBase = "${systemd}/example/systemd/system";

      # Explicit allowlist of stock systemd units shipped in the initrd.
      # Vendored from nixos initrd closure
      # Decouples us from systemd - but might require updates with systemd bumps
      # Passing throuh all systemd stock units unfiltered seems overly-permissive
      # So this is an explicit whitlelist
      upstreamUnits = lib.unique (
        [
          "basic.target"
          "breakpoint-pre-udev.service"
          "breakpoint-pre-basic.service"
          "breakpoint-pre-mount.service"
          "breakpoint-pre-switch-root.service"
          "ctrl-alt-del.target"
          "debug-shell.service"
          "emergency.service"
          "emergency.target"
          "final.target"
          "halt.target"
          "initrd-cleanup.service"
          "initrd-fs.target"
          "initrd-parse-etc.service"
          "initrd-root-device.target"
          "initrd-root-fs.target"
          "initrd-switch-root.service"
          "initrd-switch-root.target"
          "initrd.target"
          "kexec.target"
          "kmod-static-nodes.service"
          "local-fs-pre.target"
          "local-fs.target"
          "modprobe@.service"
          "multi-user.target"
          "paths.target"
          "poweroff.target"
          "reboot.target"
          "rescue.service"
          "rescue.target"
          "rpcbind.target"
          "shutdown.target"
          "sigpwr.target"
          "slices.target"
          "sockets.target"
          "swap.target"
          "sysinit.target"
          "sys-kernel-config.mount"
          "syslog.socket"
          "systemd-ask-password-console.path"
          "systemd-ask-password-console.service"
          "systemd-factory-reset-complete.service"
          "factory-reset-now.target"
          "systemd-fsck@.service"
          "systemd-halt.service"
          "systemd-hibernate-resume.service"
          "systemd-journald-audit.socket"
          "systemd-journald-dev-log.socket"
          "systemd-journald.service"
          "systemd-journald.socket"
          "systemd-kexec.service"
          "systemd-modules-load.service"
          "systemd-poweroff.service"
          "systemd-reboot.service"
          "systemd-sysctl.service"
          "timers.target"
          "umount.target"
          "systemd-bsod.service"
        ]
        ++ sysinitWants
        ++ socketsWants
      );

      sysinitWants = [
        "kmod-static-nodes.service"
        "systemd-modules-load.service"
        "systemd-udevd.service"
        "systemd-udev-trigger.service"
        "systemd-sysctl.service"
        "systemd-journald.service"
        "systemd-tmpfiles-setup-dev-early.service"
        "systemd-tmpfiles-setup-dev.service"
      ];

      socketsWants = [
        "systemd-udevd-control.socket"
        "systemd-udevd-kernel.socket"
        "systemd-journald.socket"
        "systemd-journald-dev-log.socket"
      ];

      # fails on missing stock units
      unitDir = pkgs.runCommand "thermos-initrd-units" { } ''
        mkdir -p $out
        for u in ${lib.concatStringsSep " " upstreamUnits}; do
          src=${unitBase}/$u
          if [ ! -e "$src" ]; then echo "initrd: upstream unit missing: $u" >&2; exit 1; fi
          ln -s "$src" "$out/$u"
        done
        ln -sf initrd.target $out/default.target
        mkdir -p $out/sysinit.target.wants
        for u in ${lib.concatStringsSep " " sysinitWants}; do
          ln -s ${unitBase}/$u $out/sysinit.target.wants/$u
        done
        mkdir -p $out/sockets.target.wants
        for u in ${lib.concatStringsSep " " socketsWants}; do
          ln -s ${unitBase}/$u $out/sockets.target.wants/$u
        done
      '';

      contents = [
        {
          source = "${systemd}/lib/systemd/systemd";
          target = "/init";
          # systemd dlopens libmount by soname (.note.dlopen). make-initrd-ng only
          # bundles dlopen libs when given this config; it propagates to deps.
          # Without libmount, PID 1 fails at mount_setup.
          dlopen = {
            usePriority = "recommended";
            features = [ ];
          };
        }
        {
          source = initrdRelease;
          target = "/etc/initrd-release";
        }
        {
          source = initrdRelease;
          target = "/etc/os-release";
        }
        {
          source = systemConf;
          target = "/etc/systemd/system.conf";
        }
        {
          source = shadow;
          target = "/etc/shadow";
        }
        {
          source = modulesLoad;
          target = "/etc/modules-load.d/thermos.conf";
        }
        {
          source = unitDir;
          target = "/etc/systemd/system";
        }
        {
          source = "${modulesClosure}/lib/modules";
          target = "/lib/modules";
        }
        {
          source = "${binEnv}/bin";
          target = "/bin";
        }
        {
          source = "${binEnv}/sbin";
          target = "/sbin";
        }
        # Runtime-exec, not ELF-linked, so make-initrd-ng won't trace them: place
        # lib/systemd (systemd-executor, generators) and lib/udev at their store
        # paths. Missing systemd-executor -> "Failed to allocate manager object".
        { source = "${systemd}/lib/systemd"; }
        { source = "${systemd}/lib/udev"; }
        # systemd hardcodes these util-linux paths for ExecMount and sulogin
        # (compile-time mount-path/sulogin-path), not a PATH lookup, so the exact
        # store paths must be present.
        { source = "${lib.getOutput "mount" pkgs.util-linuxMinimal}"; }
        { source = "${lib.getOutput "login" pkgs.util-linuxMinimal}"; }
      ];
    in
    {
      inherit kernel;

      derivation = pkgs.makeInitrdNG {
        name = "thermos-initrd";
        inherit contents;
      };
    };
}
