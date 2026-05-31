{ types, ... }:
{
  name = "units";

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

      emitUnit =
        name: sections:
        let
          file = pkgs.writeText name (unitToINI name sections);
          wantedBy = (sections.Install or { }).WantedBy or [ ];
          wantedByLinks = lib.concatMapStrings (target: ''
            mkdir -p $out/etc/systemd/system/${target}.wants
            ln -s ../${name} $out/etc/systemd/system/${target}.wants/${name}
          '') (if builtins.isList wantedBy then wantedBy else [ wantedBy ]);
        in
        ''
          cp ${file} $out/etc/systemd/system/${name}
          ${wantedByLinks}
        '';
    in
    {
      derivation = pkgs.runCommand "thermos-units" { } (
        ''
          mkdir -p $out/etc/systemd/system
        ''
        + lib.concatStringsSep "\n" (lib.mapAttrsToList emitUnit units)
      );
    };
}
