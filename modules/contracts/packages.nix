# Publishers provide [{ package }] records.
#
# { package :: derivation }
#
# Merge: concatenation. Deduplication happens in buildEnv.
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
