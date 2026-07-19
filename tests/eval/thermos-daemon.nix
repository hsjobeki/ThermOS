# Unit under test: /services/thermos-daemon impl (modules/services/thermos-daemon.nix).
# Asserts the update authority is published as a Type=dbus system service that owns
# org.thermos.Daemon1, with the bus policy that lets it own the name, and is inert
# when disabled.
{ tree, nixpkgs-lib, ... }:
let
  inherit (builtins) filter head;
  inherit (nixpkgs-lib) hasInfix;
  on = tree.modules.services.modules."thermos-daemon" { enable = true; };
  unit = head (filter (u: u.unitName == "thermos-daemon.service") on.units);
  policy = head (filter (e: e.name == "dbus-1/system.d/org.thermos.Daemon1.conf") on.etc);
  rules = head (filter (e: e.name == "polkit-1/rules.d/10-thermos.rules") on.etc);
in
{
  testDisabledEmpty = {
    expr =
      let
        off = tree.modules.services.modules."thermos-daemon" { };
      in
      {
        inherit (off) units packages users;
      };
    expected = {
      units = [ ];
      packages = [ ];
      users = [ ];
    };
  };

  # Type=dbus + BusName: systemd marks the service active when the name appears on
  # the bus. The daemon claims it via zbus, which needs the /var/run -> /run
  # symlink the base test guards.
  testServiceIsDbusActivated = {
    expr = {
      type = unit.unitConfig.Service.Type;
      busName = unit.unitConfig.Service.BusName;
      user = unit.unitConfig.Service.User;
    };
    expected = {
      type = "dbus";
      busName = "org.thermos.Daemon1";
      user = "thermos-daemon";
    };
  };

  # The bus policy must let the daemon's user own the well-known name, else dbus
  # refuses the request and the Type=dbus unit never activates.
  testPolicyAllowsOwn = {
    expr = hasInfix ''<allow own="org.thermos.Daemon1"/>'' policy.text;
    expected = true;
  };

  # The polkit rule grants StartUpdate/ApplyUpdate to root and active sessions
  # without an interactive agent; without it the actions fall to the auth_admin
  # default and fail headless. Guards the authorization path (Phase 1 L466).
  testRulesGrantUpdate = {
    expr =
      hasInfix "org.thermos.daemon.start-update" rules.text
      && hasInfix "org.thermos.daemon.apply-update" rules.text
      && hasInfix "polkit.Result.YES" rules.text;
    expected = true;
  };
}
