/**
  Builds a GPT disk image with systemd-repart.

  Output is a directory:
    thermos.raw (see below)
    repart-output.json

  Layout of thermos.raw:

  +============================================+
  | p1  ESP   FAT32   ~260 MiB                 |
  +============================================+
      type      C12A7328-F81F-11D2-BA4B-00A0C93EC93B  (EFI System)
      PARTUUID  seed-derived, not asserted
      contents  EFI/BOOT/BOOTX64.EFI when espUki is set (else empty)

  +============================================+
  | p2  root  ext4    rest of disk (~492 MiB)  |
  +============================================+
      type      4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709  (Linux root x86-64)
      PARTUUID  44444444-4444-4444-8888-888888888888  (boot target)
      Label     root
      contents  rootfs overlay + its /nix/store closure

  Boot: kernel cmdline `root=PARTUUID=44444444-4444-4444-8888-888888888888`.
        systemd initrd resolves it via udev (/dev/disk/by-partuuid),
        mounts it as /sysroot, then switch-root into it.
*/
{ types, ... }:
{
  name = "image";

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
    rootfsBuilder = {
      path = "/builders/rootfs";
    };
  };

  options = {
    # Path to a single EFI binary placed at the firmware removable-media fallback
    # i.e. EFI/BOOT/BOOTX64.EFI on the ESP (Empty leaves the ESP empty)
    espUki = {
      type = types.str;
      default = "";
    };
  };

  impl =
    {
      inputs,
      results,
      options,
      ...
    }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      lib = inputs.nixpkgs.lib;
      rootfs = results.rootfsBuilder.derivation;
      closureInfo = pkgs.closureInfo { rootPaths = [ rootfs ]; };

      # Boot by root=PARTUUID=, not fs UUID: repart derives the ext4 fs UUID from
      # this and it is not settable (repart.d(5)). Doubles as the --seed that
      # derives every other partition/disk UUID.
      rootPartUUID = "44444444-4444-4444-8888-888888888888";

      # FAT32 needs >= 65525 clusters, a ~260M floor at repart's 4K cluster size
      # that overrides a smaller SizeMaxBytes (repart.d(5)); SizeMinBytes states the
      # floor. espUki is a store path (eval-time known), so its CopyFiles line goes
      # in the conf directly; repart creates the EFI/BOOT parents.
      espConf = pkgs.writeText "10-esp.conf" (
        ''
          [Partition]
          Type=esp
          Format=vfat
          SizeMinBytes=256M
        ''
        + lib.optionalString (options.espUki != "") "CopyFiles=${options.espUki}:/EFI/BOOT/BOOTX64.EFI\n"
      );
      rootConf = pkgs.writeText "20-root.conf" ''
        [Partition]
        Type=root
        Format=ext4
        Label=root
        UUID=${rootPartUUID}
        Minimize=guess
      '';
    in
    {
      inherit rootPartUUID;
      derivation =
        pkgs.runCommand "thermos-image"
          {
            nativeBuildInputs = [
              pkgs.systemd
              pkgs.fakeroot
              pkgs.util-linux
              pkgs.dosfstools
              pkgs.e2fsprogs
              pkgs.mtools
            ];
          }
          ''
            export SOURCE_DATE_EPOCH=1

            mkdir -p ./rootImage/nix/store
            while IFS= read -r path; do
              cp -a "$path" ./rootImage/nix/store/
            done < ${closureInfo}/store-paths

            # Overlay rootfs over the staged closure (it has an empty /nix/store).
            cp -a ${rootfs}/* ./rootImage/
            chmod -R u+w ./rootImage

            defs=$PWD/repart.d
            mkdir -p "$defs"
            cp ${espConf} "$defs/10-esp.conf"
            cp ${rootConf} "$defs/20-root.conf"
            chmod u+w "$defs/20-root.conf"
            # CopyFiles needs the absolute staging path, known only at build time.
            echo "CopyFiles=$PWD/rootImage:/" >> "$defs/20-root.conf"

            mkdir -p $out
            # unshare --map-root-user: the build user cannot set repart user.*
            # xattrs. fakeroot: files recorded uid/gid 0, else sshd StrictModes
            # rejects baked authorized_keys. Mirrors nixpkgs repart-image.nix.
            unshare --map-root-user --fork -- fakeroot \
              systemd-repart \
                --architecture=x86-64 \
                --offline=yes \
                --empty=create \
                --size=auto \
                --seed=${rootPartUUID} \
                --definitions="$defs" \
                --dry-run=no \
                --json=pretty \
                $out/thermos.raw > $out/repart-output.json
          '';
    };
}
