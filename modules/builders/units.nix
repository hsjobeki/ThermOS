# /builders/units
{ types, ... }:
{
  name = "units-builder";

  subscribe = [ "/contracts/units" ];

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
      units = subscriptions.units;

      sectionToINI =
        name: kvs:
        "[${name}]\n"
        + lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            k: v:
            if builtins.isList v then
              lib.concatMapStringsSep "\n" (item: "${k}=${item}") v
            else
              "${k}=${toString v}"
          ) kvs
        );

      unitToINI =
        name: sections: lib.concatStringsSep "\n\n" (lib.mapAttrsToList sectionToINI sections) + "\n";

      mkUnit =
        name: sections:
        let
          file = pkgs.writeText name (unitToINI name sections);
        in
        ''
          cp ${file} $out/etc/systemd/system/${name}
        '';
    in
    {
      derivation = pkgs.runCommand "thermos-units" { } (
        ''
          mkdir -p $out/etc/systemd/system
        ''
        + lib.concatStringsSep "\n" (lib.mapAttrsToList mkUnit units)
      );
    };
}
