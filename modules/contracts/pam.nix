# Publishers provide [{ name, rules }] records.
#
# rule: { type :: str, control :: str, module :: str,
#         package? :: derivation, args? :: str }
#
# Module names are resolved to store paths by the PAM middleware.
# Common modules (pam_unix, pam_deny, ...) resolve automatically.
# Custom modules require a package field to locate the .so file.
# Merge: conflict detection on name.
{ types, ... }:
let
  pamRule = types.struct "pamRule" {
    type = types.str;
    control = types.str;
    module = types.str;
    package = types.optionalAttr types.derivation;
    args = types.optionalAttr types.str;
  };
in
{
  name = "pam";

  options = {
    name = {
      type = types.str;
    };
    rules = {
      type = types.listOf pamRule;
    };
  };

  contract = {
    merge =
      publishers:
      let
        all = builtins.concatLists (builtins.attrValues publishers);
        byName = builtins.groupBy (s: s.name) all;
        dupes = builtins.filter (n: builtins.length byName.${n} > 1) (builtins.attrNames byName);
      in
      if dupes != [ ] then
        throw "Conflicting PAM service names: ${builtins.concatStringsSep ", " dupes}"
      else
        all;
  };

  impl = { options, ... }: options;
}
