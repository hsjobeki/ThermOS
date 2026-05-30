# /contracts/etc
#
# Merge strategy: conflict detection. Two modules writing the same
# /etc path is an error caught at eval time.
{ types, ... }:
{
  name = "etc";

  options = {
    name = {
      type = types.str;
    };
    text = {
      type = types.str;
    };
    mode = {
      type = types.str;
      default = "0444";
    };
    uid = {
      type = types.int;
      default = 0;
    };
    gid = {
      type = types.int;
      default = 0;
    };
  };

  contract = {
    merge =
      publishers:
      let
        all = builtins.concatLists (builtins.attrValues publishers);
        byName = builtins.groupBy (f: f.name) all;
        dupes = builtins.filter (n: builtins.length byName.${n} > 1) (builtins.attrNames byName);
      in
      if dupes != [ ] then
        throw "Conflicting /etc entries: ${builtins.concatStringsSep ", " dupes}"
      else
        all;
  };

  impl = { options, ... }: options;
}
