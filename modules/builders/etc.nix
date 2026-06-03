{ types, ... }:
{
  name = "etc";

  subscribe = [ "/contracts/etc" ];

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
  };

  impl =
    { subscriptions, inputs, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      lib = inputs.nixpkgs.lib;
      etcFiles = subscriptions.etc;

      emitEntry =
        f:
        let
          file = pkgs.writeText "etc-${lib.replaceStrings [ "/" ] [ "-" ] f.name}" f.text;
        in
        ''
          mkdir -p $out/etc/$(dirname "${f.name}")
          cp ${file} $out/etc/${f.name}
        '';
    in
    {
      derivation = pkgs.runCommand "thermos-etc" { } (lib.concatMapStringsSep "\n" emitEntry etcFiles);
    };
}
