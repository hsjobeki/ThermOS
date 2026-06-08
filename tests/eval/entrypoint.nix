{ tree, ... }:
let
  inherit (builtins) filter head match;
in
{
  testOptionsPassthroughGettyAutologin = {
    expr =
      let
        reconfigured = tree.override {
          options = {
            "/services/getty" = {
              autologinUser = "testuser";
            };
          };
        };
        getty = (reconfigured.modules.services.modules.getty { });
        unit = head getty.units;
      in
      match ".*--autologin testuser.*" unit.unitConfig.Service.ExecStart != null;
    expected = true;
  };

  testOptionsPassthroughHostname = {
    expr =
      let
        reconfigured = tree.override {
          options = {
            "/core/base" = {
              hostName = "customhost";
            };
          };
        };
        base = (reconfigured.modules.core.modules.base { });
        entry = head (filter (e: e.name == "hostname") base.etc);
      in
      entry.text;
    expected = "customhost";
  };

  testEmptyOptionsPreservesDefaults = {
    expr =
      let
        base = (tree.modules.core.modules.base { });
        entry = head (filter (e: e.name == "hostname") base.etc);
      in
      entry.text;
    expected = "thermos";
  };
}
