# Publishers provide [{ assertion, message }] records.
#
# { assertion :: bool, message :: str }
#
# The toplevel builder checks all assertions before producing the
# system derivation. Merge: concatenation.
{ types, ... }:
{
  name = "assertions";

  options = {
    assertion = {
      type = types.bool;
    };
    message = {
      type = types.str;
    };
  };

  contract = {
    merge = publishers: builtins.concatLists (builtins.attrValues publishers);
  };

  impl = { options, ... }: options;
}
