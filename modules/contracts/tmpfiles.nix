# /contracts/tmpfiles
#
# Merge strategy: concatenation. Rules are additive.
# Conflicts (two rules for the same path) are handled by tmpfiles itself.
{ types, ... }:
{
  name = "tmpfiles";

  options = {
    rule = {
      type = types.str;
    };
  };

  contract = {
    merge = publishers: builtins.concatLists (builtins.attrValues publishers);
  };

  impl = { options, ... }: options;
}
