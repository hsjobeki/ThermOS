# Merge strategy: conflict detection on name and gid.
# Two modules declaring the same group name or gid is an error.
{ types, ... }:
{
  name = "groups";

  options = {
    name = {
      type = types.str;
    };
    gid = {
      type = types.int;
    };
    members = {
      type = types.listOf types.str;
      default = [ ];
    };
  };

  contract = {
    merge =
      publishers:
      let
        all = builtins.concatLists (builtins.attrValues publishers);
        byName = builtins.groupBy (g: g.name) all;
        byGid = builtins.groupBy (g: toString g.gid) all;
        dupeNames = builtins.filter (n: builtins.length byName.${n} > 1) (builtins.attrNames byName);
        dupeGids = builtins.filter (g: builtins.length byGid.${g} > 1) (builtins.attrNames byGid);
      in
      if dupeNames != [ ] then
        throw "Conflicting group names: ${builtins.concatStringsSep ", " dupeNames}"
      else if dupeGids != [ ] then
        throw "Conflicting group GIDs: ${builtins.concatStringsSep ", " dupeGids}"
      else
        all;
  };

  impl = { options, ... }: options;
}
