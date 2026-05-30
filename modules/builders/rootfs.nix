{ types, ... }:
{
  name = "rootfs-builder";

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

      systemdBin = "${pkgs.systemd}/lib/systemd/systemd";
    in
    {
      derivation = pkgs.runCommand "thermos-rootfs" { } ''
        mkdir -p $out

        mkdir -p $out/sbin
        ln -s ${systemdBin} $out/sbin/init

        mkdir -p $out/etc
        for f in ${etcDrv}/etc/*; do
          ln -s "$f" $out/etc/$(basename "$f")
        done

        # Empty machine-id. Must be exactly 0 bytes or nspawn rejects it.
        truncate -s 0 $out/etc/machine-id

        mkdir -p $out/etc/systemd/system
        if [ -d ${unitsDrv}/etc/systemd/system ]; then
          for f in ${unitsDrv}/etc/systemd/system/*; do
            ln -s "$f" $out/etc/systemd/system/$(basename "$f")
          done
        fi
        # stock default is graphical.target
        ln -s multi-user.target $out/etc/systemd/system/default.target

        if [ -d ${tmpfilesDrv}/etc/tmpfiles.d ]; then
          ln -s ${tmpfilesDrv}/etc/tmpfiles.d $out/etc/tmpfiles.d
        fi

        for f in passwd group shadow; do
          if [ -f ${usersDrv}/etc/$f ]; then
            ln -s ${usersDrv}/etc/$f $out/etc/$f
          fi
        done
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
          else
            ln -s "$f" $out/usr/lib/$name
          fi
        done
        cp --dereference ${etcDrv}/etc/os-release $out/usr/lib/os-release

        # nspawn needs these dirs to exist
        mkdir -p $out/{proc,sys,dev,run,tmp,var}

        # nspawn bind-mounts host store here
        mkdir -p $out/nix/store
      '';
    };
}
