# Builds a Unified Kernel Image:
# kernel + initrd + cmdline + os-release bundled
# into one EFI PE binary via systemd-stub + ukify.
#
# Currently direct UEFI boot
#
# uses ukify to build an currently unsigned UKI
{ types, ... }:
{
  name = "uki";

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
    initrdBuilder = {
      path = "/builders/initrd";
    };
    etcBuilder = {
      path = "/builders/etc";
    };
  };

  options = {
    # Kernel command line baked into the UKI (.cmdline section). There is no
    # bootloader -append on metal, so this is the only cmdline. The composing
    # system config overrides it with root=PARTUUID=... console=tty0 rw rootwait.
    cmdline = {
      type = types.str;
      default = "console=tty0 rw rootwait";
    };
  };

  impl =
    {
      inputs,
      options,
      results,
      ...
    }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      kernel = results.initrdBuilder.kernel;
      initrd = results.initrdBuilder.derivation;
      etc = results.etcBuilder.derivation;
      efiArch = pkgs.stdenv.hostPlatform.efiArch;

      ukifyConf = pkgs.writeText "ukify.conf" ''
        [UKI]
        Linux=${kernel}/bzImage
        Initrd=${initrd}/initrd
        Cmdline=${options.cmdline}
        Stub=${pkgs.systemd}/lib/systemd/boot/efi/linux${efiArch}.efi.stub
        Uname=${kernel.modDirVersion}
        OSRelease=@${etc}/etc/os-release
        EFIArch=${efiArch}
      '';
    in
    {
      derivation = pkgs.runCommand "thermos-uki" { } ''
        mkdir -p $out
        ${pkgs.systemdUkify}/lib/systemd/ukify build \
          --config=${ukifyConf} \
          --output=$out/thermos.efi
      '';
    };
}
