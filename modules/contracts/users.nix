# Merge strategy: conflict detection on name and uid.
# Two modules declaring the same username or uid is an error.
{ types, ... }:
{
  name = "users";

  options = {
    name = {
      type = types.str;
    };
    uid = {
      type = types.int;
    };
    gid = {
      type = types.int;
    };
    home = {
      type = types.str;
      default = "/var/empty";
    };
    shell = {
      type = types.str;
      default = "/sbin/nologin";
    };
    gecos = {
      type = types.str;
      default = "";
    };
  };

  contract = {
    merge =
      publishers:
      let
        all = builtins.concatLists (builtins.attrValues publishers);
        byName = builtins.groupBy (u: u.name) all;
        byUid = builtins.groupBy (u: toString u.uid) all;
        dupeNames = builtins.filter (n: builtins.length byName.${n} > 1) (builtins.attrNames byName);
        dupeUids = builtins.filter (u: builtins.length byUid.${u} > 1) (builtins.attrNames byUid);
      in
      if dupeNames != [ ] then
        throw "Conflicting user names: ${builtins.concatStringsSep ", " dupeNames}"
      else if dupeUids != [ ] then
        throw "Conflicting user UIDs: ${builtins.concatStringsSep ", " dupeUids}"
      else
        all;
  };

  impl = { options, ... }: options;
}
