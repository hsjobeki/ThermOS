# /contracts/units
#
# Publishers provide { "unit-name.service" = { Unit = {...}; Service = {...}; }; }
# Merge strategy: deep merge. Later publishers override specific fields,
# like systemd drop-ins. This lets a service module define a unit and a
# hardening module overlay ProtectSystem=strict without knowing about each other.
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
        # Deep-merge units by name: later entries override earlier fields
        merged = builtins.foldl' (
          acc: entry:
          acc
          // {
            ${entry.unitName} =
              let
                prev = acc.${entry.unitName} or { };
                sections = builtins.attrNames entry.unitConfig;
              in
              builtins.foldl' (
                a: section:
                a
                // {
                  ${section} = (a.${section} or { }) // entry.unitConfig.${section};
                }
              ) prev sections;
          }
        ) { } all;
      in
      merged;
  };

  impl = { options, ... }: options;
}
