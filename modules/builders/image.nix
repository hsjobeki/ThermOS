# Builds a raw ext4 disk image containing the rootfs and its nix store closure.
# Uses mkfs.ext4 -d (no root/mount/loop required, runs in nix sandbox).
{ types, ... }:
{
  name = "image-builder";

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
    rootfsBuilder = {
      path = "/builders/rootfs";
    };
  };

  impl =
    { inputs, results, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      rootfs = results.rootfsBuilder.derivation;
      closureInfo = pkgs.closureInfo { rootPaths = [ rootfs ]; };
    in
    {
      derivation =
        pkgs.runCommand "thermos-image"
          {
            nativeBuildInputs = [ pkgs.e2fsprogs ];
          }
          ''
            mkdir -p ./rootImage/nix/store

            # Copy store closure first (into writable dir)
            while IFS= read -r path; do
              cp -a "$path" ./rootImage/nix/store/
            done < ${closureInfo}/store-paths

            # Overlay rootfs layout (may contain nix/store mount point)
            cp -a ${rootfs}/* ./rootImage/
            chmod -R u+w ./rootImage

            # Size estimate: 20% headroom + 64MB buffer
            numBlocks=$(du -s -B 4096 --apparent-size ./rootImage | awk '{print int($1 * 1.20) + 16384}')
            bytes=$((numBlocks * 4096))

            # Round up to nearest MiB
            mib=$((1024 * 1024))
            if (( bytes % mib )); then
              bytes=$(( (bytes / mib + 1) * mib ))
            fi

            truncate -s "$bytes" $out
            mkfs.ext4 -L thermos -d ./rootImage $out
            resize2fs -M $out
            new_size=$(dumpe2fs -h $out 2>/dev/null | awk -F: \
              '/Block count/{count=$2} /Block size/{size=$2} END{print (count*size+16*2^20)/size}')
            resize2fs $out "$new_size"
          '';
    };
}
