# Publishers provide [{ unitName, unitConfig, scope? }] records.
#
# unitConfig :: { sectionName :: { fieldName :: str | int | [str] } }
# scope      :: enum "system" | "user"  (default "system")
#                system -> /etc/systemd/system (the system instance)
#                user   -> /etc/systemd/user   (the per-user instance)
#
# Mirrors systemd unit file structure. Sections and fields are not
# hardcoded: new ones work automatically.
# Merge: deep merge by (scope, name), like systemd drop-ins. The same name at
# different scopes (e.g. the system bus and per-user bus both ship a
# dbus.socket) is a distinct unit; they coexist instead of conflicting.
{ types, ... }:
let
  unitValue = types.union [
    types.str
    types.int
    (types.listOf types.str)
  ];
  unitSection = types.attrsOf unitValue;
in
{
  name = "units";

  options = {
    unitName = {
      type = types.str;
    };
    unitConfig = {
      type = types.attrsOf unitSection;
    };
    scope = {
      type = types.enum "scope" [
        "system"
        "user"
      ];
      default = "system";
    };
  };

  contract = {
    merge =
      publishers:
      let
        all = builtins.concatLists (builtins.attrValues publishers);
        # Units are identified by (scope, name): /etc/systemd/system/dbus.socket
        # and /etc/systemd/user/dbus.socket are distinct files for distinct
        # managers. Group by both so a shared name at different scopes coexists,
        # while drop-ins for one (scope, name) still deep-merge. unitName carries
        # no '/', scope is an enum, so the composite key splits unambiguously.
        byKey = builtins.groupBy (e: "${e.scope or "system"}/${e.unitName}") all;
        # Deep-merge drop-ins for one unit: per section, later publishers'
        # fields override earlier ones (systemd drop-in semantics).
        mergeSections = configs: builtins.zipAttrsWith (_: builtins.foldl' (a: b: a // b) { }) configs;
      in
      builtins.mapAttrs (_: entries: {
        scope = (builtins.head entries).scope or "system";
        sections = mergeSections (map (e: e.unitConfig) entries);
      }) byKey;
  };

  impl = { options, ... }: options;
}
