{ tree, ... }:
let
  inherit (builtins)
    all
    filter
    head
    match
    ;
in
{
  testGettyAutologin = {
    expr =
      let
        impl = tree.modules.services.modules.getty { autologinUser = "root"; };
        unit = head impl.units;
      in
      match ".*--autologin root.*" unit.unitConfig.Service.ExecStart != null;
    expected = true;
  };

  testGettyMultipleTtys = {
    expr =
      let
        impl = tree.modules.services.modules.getty {
          ttys = [
            "tty1"
            "tty2"
            "tty3"
          ];
        };
      in
      map (u: u.unitName) impl.units;
    expected = [
      "getty@tty1.service"
      "getty@tty2.service"
      "getty@tty3.service"
    ];
  };

  testGettySerialTty = {
    expr =
      let
        impl = tree.modules.services.modules.getty {
          serialTtys = [ "ttyS0" ];
          baudRate = "9600";
        };
        unit = head (filter (u: u.unitName == "serial-getty@ttyS0.service") impl.units);
      in
      match ".*--keep-baud ttyS0 9600.*" unit.unitConfig.Service.ExecStart != null;
    expected = true;
  };

  testGettyAutologinWithMultipleTtys = {
    expr =
      let
        impl = tree.modules.services.modules.getty {
          ttys = [
            "tty1"
            "tty2"
          ];
          autologinUser = "admin";
        };
      in
      all (u: match ".*--autologin admin.*" u.unitConfig.Service.ExecStart != null) impl.units;
    expected = true;
  };

  testBaseCustomHostname = {
    expr =
      let
        impl = tree.modules.core.modules.base { hostName = "myhost"; };
        hostnameEntry = head (filter (e: e.name == "hostname") impl.etc);
      in
      hostnameEntry.text;
    expected = "myhost";
  };
}
