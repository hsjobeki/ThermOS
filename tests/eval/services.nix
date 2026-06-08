{ tree, ... }:
let
  inherit (builtins) attrNames head match;
in
{
  testGettyPublishesUnit = {
    expr =
      let
        impl = tree.modules.services.modules.getty { };
      in
      map (u: u.unitName) impl.units;
    expected = [ "getty@tty1.service" ];
  };

  testGettyUnitHasSections = {
    expr =
      let
        impl = tree.modules.services.modules.getty { };
        unit = head impl.units;
      in
      attrNames unit.unitConfig;
    expected = [
      "Install"
      "Service"
      "Unit"
    ];
  };

  testGettyExecStartContainsAgetty = {
    expr =
      let
        impl = tree.modules.services.modules.getty { };
        unit = head impl.units;
      in
      match ".*agetty.*" unit.unitConfig.Service.ExecStart != null;
    expected = true;
  };

  testGettyDefaultNoAutologin = {
    expr =
      let
        impl = tree.modules.services.modules.getty { };
        unit = head impl.units;
      in
      match ".*--autologin.*" unit.unitConfig.Service.ExecStart != null;
    expected = false;
  };

  testGettyWantedByMultiUser = {
    expr =
      let
        impl = tree.modules.services.modules.getty { };
        unit = head impl.units;
      in
      unit.unitConfig.Install.WantedBy;
    expected = [ "multi-user.target" ];
  };
}
