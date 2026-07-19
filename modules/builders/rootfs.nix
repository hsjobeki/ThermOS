{ types, ... }:
{
  name = "rootfs";

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
    toplevelBuilder = {
      path = "/builders/toplevel";
    };
  };

  impl =
    { inputs, results, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;

      etcDrv = results.toplevelBuilder.builders.etc;
      packagesDrv = results.toplevelBuilder.builders.packages;
      unitsDrv = results.toplevelBuilder.builders.units;
      tmpfilesDrv = results.toplevelBuilder.builders.tmpfiles;
      usersDrv = results.toplevelBuilder.builders.users;
      kernelModulesDrv = results.toplevelBuilder.builders.kernelModules;

      systemdBin = "${pkgs.systemd}/lib/systemd/systemd";
    in
    {
      derivation = pkgs.runCommand "thermos-rootfs" { } ''
        mkdir -p $out

        mkdir -p $out/sbin
        ln -s ${systemdBin} $out/sbin/init

        mkdir -p $out/etc
        cp -rs ${etcDrv}/etc/* $out/etc/
        # cp -rs copies source directory permissions (read-only from the store).
        # The builder adds files into $out/etc and its subdirectories below,
        # so every directory in the tree needs write access.
        find $out/etc -type d -exec chmod u+w {} +

        # Empty machine-id. Must be exactly 0 bytes or nspawn rejects it.
        truncate -s 0 $out/etc/machine-id

        mkdir -p $out/etc/systemd/system
        if [ -d ${unitsDrv}/etc/systemd/system ]; then
          for f in ${unitsDrv}/etc/systemd/system/*; do
            cp -rs "$f" $out/etc/systemd/system/
          done
          # .wants dirs from the units builder may receive more symlinks below
          # (e.g. networkd enablement), so they need write access.
          find $out/etc/systemd/system -name '*.wants' -type d -exec chmod u+w {} +
        fi

        # User-scoped units (e.g. the desktop bars) go to the per-user instance
        # path. Present only when a module publishes at scope = user.
        if [ -d ${unitsDrv}/etc/systemd/user ]; then
          mkdir -p $out/etc/systemd/user
          for f in ${unitsDrv}/etc/systemd/user/*; do
            cp -rs "$f" $out/etc/systemd/user/
          done
          find $out/etc/systemd/user -name '*.wants' -type d -exec chmod u+w {} +
        fi

        # stock default is graphical.target
        ln -s multi-user.target $out/etc/systemd/system/default.target

        # Enable stock systemd-networkd when .network config files are present.
        # The stock unit at /usr/lib/systemd/system/ has proper sandboxing,
        # capabilities, and socket activation that a custom unit would lack.
        if [ -d $out/etc/systemd/network ]; then
          mkdir -p $out/etc/systemd/system/multi-user.target.wants
          ln -s /usr/lib/systemd/system/systemd-networkd.service \
            $out/etc/systemd/system/multi-user.target.wants/systemd-networkd.service
        fi

        if [ -d ${tmpfilesDrv}/etc/tmpfiles.d ]; then
          ln -s ${tmpfilesDrv}/etc/tmpfiles.d $out/etc/tmpfiles.d
        fi

        cp ${usersDrv}/etc/passwd $out/etc/passwd
        cp ${usersDrv}/etc/group $out/etc/group
        cp ${usersDrv}/etc/shadow $out/etc/shadow
        mkdir -p $out/usr
        ln -s ${packagesDrv}/bin $out/usr/bin
        ln -s ${packagesDrv}/bin $out/bin

        # os-release must be a real file (nspawn checks before bind-mounting /nix/store).
        # /usr/lib/systemd/ must be a real directory to merge:
        #   systemd runtime libs from lib/systemd/*
        #   stock units from example/systemd/system/ (NixOS splits them there)
        mkdir -p $out/usr/lib
        for f in ${pkgs.systemd}/lib/*; do
          name=$(basename "$f")
          if [ "$name" = "systemd" ]; then
            mkdir -p $out/usr/lib/systemd
            for sf in ${pkgs.systemd}/lib/systemd/*; do
              ln -s "$sf" $out/usr/lib/systemd/$(basename "$sf")
            done
            ln -s ${pkgs.systemd}/example/systemd/system $out/usr/lib/systemd/system
            # Per-user instance units. The user manager (user@UID.service) reads
            # /usr/lib/systemd/user for the stock targets (graphical-session,
            # sockets, basic, default); our user units (dbus.socket, the bars)
            # come from /etc/systemd/user via the units builder. Without this the
            # user session has no targets and the bars never start.
            ln -s ${pkgs.systemd}/example/systemd/user $out/usr/lib/systemd/user
          else
            ln -s "$f" $out/usr/lib/$name
          fi
        done
        cp --dereference ${etcDrv}/etc/os-release $out/usr/lib/os-release

        # systemd ships its D-Bus policies (login1, systemd1, hostname1, ...) and
        # service-activation files under share/dbus-1/{system.d,system-services};
        # packages published by services ship theirs the same way (e.g. polkit's
        # org.freedesktop.PolicyKit1.conf). We merge all of them, plus the
        # aggregated packages env, into /usr/share/dbus-1/*. The dbus module adds an
        # absolute <includedir>/usr/share/dbus-1/system.d</includedir> to system.conf
        # so they load; without it a daemon (PID1, polkitd, ...) cannot own its bus
        # name and logind sessions plus every Type=dbus service break.
        mkdir -p $out/usr/share/dbus-1
        for pkg in ${pkgs.dbus} ${pkgs.systemd} ${packagesDrv}; do
          if [ -d $pkg/share/dbus-1 ]; then
            for d in $pkg/share/dbus-1/*; do
              name=$(basename "$d")
              if [ -d "$d" ]; then
                mkdir -p $out/usr/share/dbus-1/$name
                for f in "$d"/*; do
                  ln -sf "$f" $out/usr/share/dbus-1/$name/$(basename "$f")
                done
              else
                ln -sf "$d" $out/usr/share/dbus-1/$name
              fi
            done
          fi
        done

        # Per-package share subdirs that a daemon reads from /usr/share by an
        # absolute, compiled-in path: polkitd reads /usr/share/polkit-1/{actions,
        # rules.d} (built with datadir /usr/share); cosmic-comp reads
        # /usr/share/cosmic via cosmic-config (XDG_DATA_DIRS). Each is symlinked
        # straight from the packages env, which merges share/<sub> from every
        # package that ships it. Absent when no module publishes that data, so each
        # is additive. dbus-1 is handled above (merged across dbus + systemd +
        # packages), not here.
        for sub in polkit-1 cosmic; do
          if [ -d ${packagesDrv}/share/$sub ]; then
            mkdir -p $out/usr/share
            ln -s ${packagesDrv}/share/$sub $out/usr/share/$sub
          fi
        done

        # Module tree for the running system, at /lib/modules where the loader
        # (modprobe, udev) looks. Empty until a service publishes (system, *)
        # modules; built by /builders/kernel-modules.
        mkdir -p $out/lib
        ln -s ${kernelModulesDrv}/lib/modules $out/lib/modules

        # nspawn needs these dirs to exist
        mkdir -p $out/{proc,sys,dev,run,tmp,var}

        # nspawn bind-mounts host store here
        mkdir -p $out/nix/store
      '';
    };
}
