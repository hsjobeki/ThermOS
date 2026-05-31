# Publishers provide [{ unitName, unitConfig }] records.
#
# unitConfig :: { sectionName :: { fieldName :: str | int | [str] } }
#
# Mirrors systemd unit file structure. Sections and fields are not
# hardcoded: new ones work automatically.
# Merge: deep merge by unit name, like systemd drop-ins.
{ types, ... }:
let
  unitValue = types.union [
    types.str
    types.int
    (types.listOf types.str)
  ];
  unitSection = types.attrsOf unitValue;
in
{
  name = "units";

  options = {
    unitName = {
      type = types.str;
    };
    unitConfig = {
      type = types.attrsOf unitSection;
    };
  };

  contract = {
    merge =
      publishers:
      let
        all = builtins.concatLists (builtins.attrValues publishers);
        asAttrs = map (e: { ${e.unitName} = e.unitConfig; }) all;
      in
      builtins.zipAttrsWith (_: builtins.zipAttrsWith (_: builtins.foldl' (a: b: a // b) { })) asAttrs;
  };

  impl = { options, ... }: options;
}
