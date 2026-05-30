# Any module can publish assertions. The toplevel builder checks them all
# before producing the system derivation.
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
