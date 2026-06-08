{ entrypoint, tree, ... }:
let
  inherit (builtins)
    filter
    head
    length
    match
    ;
in
{
  testPublishesUnits = {
    expr =
      let
        impl = tree.modules.services.modules.dbus { };
      in
      map (u: u.unitName) impl.units;
    expected = [
      "dbus.socket"
      "dbus.service"
    ];
  };

  testSocketWantedBySockets = {
    expr =
      let
        impl = tree.modules.services.modules.dbus { };
        socket = head (filter (u: u.unitName == "dbus.socket") impl.units);
      in
      socket.unitConfig.Install.WantedBy;
    expected = [ "sockets.target" ];
  };

  testServiceWantedByMultiUser = {
    expr =
      let
        impl = tree.modules.services.modules.dbus { };
        svc = head (filter (u: u.unitName == "dbus.service") impl.units);
      in
      svc.unitConfig.Install.WantedBy;
    expected = [ "multi-user.target" ];
  };

  testServiceExecStart = {
    expr =
      let
        impl = tree.modules.services.modules.dbus { };
        svc = head (filter (u: u.unitName == "dbus.service") impl.units);
      in
      match ".*dbus-daemon.*" svc.unitConfig.Service.ExecStart != null;
    expected = true;
  };

  testMessagebusUser = {
    expr =
      let
        impl = tree.modules.services.modules.dbus { };
        user = head impl.users;
      in
      {
        inherit (user) name uid gid;
      };
    expected = {
      name = "messagebus";
      uid = 81;
      gid = 81;
    };
  };

  testMessagebusGroup = {
    expr =
      let
        impl = tree.modules.services.modules.dbus { };
      in
      (head impl.groups).name;
    expected = "messagebus";
  };

  testDbusConfigInEtc = {
    expr =
      let
        impl = tree.modules.services.modules.dbus { };
      in
      length (filter (e: e.name == "dbus-1/system.conf") impl.etc) == 1;
    expected = true;
  };

  testDbusPackage = {
    expr =
      let
        impl = tree.modules.services.modules.dbus { };
      in
      length (filter (p: p.package == entrypoint.pkgs.dbus) impl.packages) == 1;
    expected = true;
  };
}
