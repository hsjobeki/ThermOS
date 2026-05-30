# /contracts/packages
#
# Merge strategy: concatenation. Deduplication happens in buildEnv.
{ types, ... }:
{
  name = "packages";

  options = {
    package = {
      type = types.derivation;
    };
  };

  contract = {
    merge = publishers: builtins.concatLists (builtins.attrValues publishers);
  };

  impl = { options, ... }: options;
}
