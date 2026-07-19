{
  entrypoint,
  tree,
  nixpkgs-lib,
  ...
}:
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
      map (u: "${u.scope or "system"}/${u.unitName}") impl.units;
    expected = [
      "system/dbus.socket"
      "system/dbus.service"
      "user/dbus.socket"
      "user/dbus.service"
    ];
  };

  testSocketWantedBySockets = {
    expr =
      let
        impl = tree.modules.services.modules.dbus { };
        socket = head (
          filter (u: u.unitName == "dbus.socket" && (u.scope or "system") == "system") impl.units
        );
      in
      socket.unitConfig.Install.WantedBy;
    expected = [ "sockets.target" ];
  };

  testServiceWantedByMultiUser = {
    expr =
      let
        impl = tree.modules.services.modules.dbus { };
        svc = head (
          filter (u: u.unitName == "dbus.service" && (u.scope or "system") == "system") impl.units
        );
      in
      svc.unitConfig.Install.WantedBy;
    expected = [ "multi-user.target" ];
  };

  testServiceExecStart = {
    expr =
      let
        impl = tree.modules.services.modules.dbus { };
        svc = head (
          filter (u: u.unitName == "dbus.service" && (u.scope or "system") == "system") impl.units
        );
      in
      match ".*dbus-daemon.*" svc.unitConfig.Service.ExecStart != null;
    expected = true;
  };

  # Per-user session bus: the user-scope dbus.socket listens on the runtime
  # dir bus (%t/bus = /run/user/UID/bus) and dbus.service runs --session.
  testUserBusSocketListen = {
    expr =
      let
        impl = tree.modules.services.modules.dbus { };
        socket = head (
          filter (u: u.unitName == "dbus.socket" && (u.scope or "system") == "user") impl.units
        );
      in
      socket.unitConfig.Socket.ListenStream;
    expected = "%t/bus";
  };

  testUserBusServiceSession = {
    expr =
      let
        impl = tree.modules.services.modules.dbus { };
        svc = head (filter (u: u.unitName == "dbus.service" && (u.scope or "system") == "user") impl.units);
      in
      match ".*--session.*" svc.unitConfig.Service.ExecStart != null;
    expected = true;
  };

  testSessionConfInEtc = {
    expr =
      let
        impl = tree.modules.services.modules.dbus { };
      in
      length (filter (e: e.name == "dbus-1/session.conf") impl.etc) == 1;
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

  # Unit under test: the dbus module's published /etc/dbus-1/system.conf must put
  # /usr/share/dbus-1/system.d on dbus-daemon's policy search path. systemd ships
  # org.freedesktop.systemd1.conf (the <allow own="org.freedesktop.systemd1"/>
  # policy) there; without this include dbus never loads it, PID1 cannot own the
  # name, and logind user-sessions plus every Type=dbus service silently break.
  testSystemConfScansUsrShareSystemD = {
    expr =
      let
        impl = tree.modules.services.modules.dbus { };
        conf = head (filter (e: e.name == "dbus-1/system.conf") impl.etc);
      in
      nixpkgs-lib.hasInfix "<includedir>/usr/share/dbus-1/system.d</includedir>" conf.text;
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
