# Publishers provide [{ unitName, unitConfig }] records.
# Merge strategy: deep merge by unit name. The merge output is an attrset
# keyed by unit name, not a list. This is intentional: subscribers look up
# and overlay units by name, like systemd drop-ins.
{ types, ... }:
{
  name = "units";

  options = {
    unitName = {
      type = types.str;
    };
    unitConfig = {
      type = types.attrs;
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
