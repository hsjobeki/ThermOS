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
        key: unit:
        let
          # Contract keys units by "scope/name"; scope drives the dir, name the file.
          name = lib.last (lib.splitString "/" key);
          sections = unit.sections;
          dir = "etc/systemd/${unit.scope}";
          file = pkgs.writeText name (unitToINI name sections);
          wantedBy = (sections.Install or { }).WantedBy or [ ];
          wantedByLinks = lib.concatMapStrings (target: ''
            mkdir -p $out/${dir}/${target}.wants
            ln -s ../${name} $out/${dir}/${target}.wants/${name}
          '') (if builtins.isList wantedBy then wantedBy else [ wantedBy ]);
        in
        ''
          mkdir -p $out/${dir}
          cp ${file} $out/${dir}/${name}
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
