# Unit under test: /core/base impl (modules/core/base.nix). Asserts the FHS
# substrate the rest of the system relies on at runtime.
{ tree, ... }:
let
  inherit (builtins) any match;
  base = tree.modules.core.modules.base { };
in
{
  # /var/run -> /run (FHS). zbus defaults the system bus to
  # /var/run/dbus/system_bus_socket, so without this symlink the desktop bars
  # fail with "no system bus". Caught at eval so a base-tmpfiles refactor that
  # drops it fails here, not at desktop boot.
  testVarRunSymlink = {
    expr = any (r: match "L /var/run .*/run" r.rule != null) base.tmpfiles;
    expected = true;
  };
}
