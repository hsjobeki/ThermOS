{
  name = "dbus";

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
  };

  publish = [
    "/contracts/units"
    "/contracts/users"
    "/contracts/groups"
    "/contracts/packages"
    "/contracts/etc"
    "/contracts/tmpfiles"
  ];

  impl =
    { inputs, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      lib = inputs.nixpkgs.lib;
      dbus = pkgs.dbus;

      # Remove the /etc/dbus-1/system.conf include from the stock config.
      # We publish this file as /etc/dbus-1/system.conf, so it would
      # include itself and dbus-daemon fails with "Circular inclusion".
      dbusSystemConf =
        builtins.replaceStrings
          [ ''<include ignore_missing="yes">/etc/dbus-1/system.conf</include>'' ]
          [ "" ]
          (builtins.readFile "${dbus}/share/dbus-1/system.conf");
    in
    if
      lib.hasInfix ''<include ignore_missing="yes">/etc/dbus-1/system.conf</include>'' dbusSystemConf
    then
      throw "dbus: replaceStrings failed to strip self-include from system.conf"
    else
      {
        units = [
          {
            unitName = "dbus.socket";
            unitConfig = {
              Unit = {
                Description = "D-Bus System Message Bus Socket";
              };
              Socket = {
                ListenStream = "/run/dbus/system_bus_socket";
              };
              Install = {
                WantedBy = [ "sockets.target" ];
              };
            };
          }
          {
            unitName = "dbus.service";
            unitConfig = {
              Unit = {
                Description = "D-Bus System Message Bus";
                Documentation = [ "man:dbus-daemon(1)" ];
                Requires = [ "dbus.socket" ];
              };
              Service = {
                Type = "notify";
                NotifyAccess = "main";
                ExecStart = "${dbus}/bin/dbus-daemon --system --address=systemd: --nofork --nopidfile --systemd-activation --syslog-only";
                ExecReload = "${dbus}/bin/dbus-send --print-reply --system --type=method_call --dest=org.freedesktop.DBus / org.freedesktop.DBus.ReloadConfig";
                User = "messagebus";
                Group = "messagebus";
                OOMScoreAdjust = "-900";
                AmbientCapabilities = "CAP_AUDIT_WRITE";
              };
              Install = {
                WantedBy = [ "multi-user.target" ];
              };
            };
          }
        ];

        users = [
          {
            name = "messagebus";
            uid = 81;
            gid = 81;
            home = "/run/dbus";
            shell = "/bin/nologin";
            gecos = "D-Bus system daemon";
          }
        ];

        groups = [
          {
            name = "messagebus";
            gid = 81;
          }
        ];

        packages = [ { package = dbus; } ];

        etc = [
          {
            name = "dbus-1/system.conf";
            text = dbusSystemConf;
          }
        ];

        tmpfiles = [
          { rule = "d /run/dbus 0755 messagebus messagebus -"; }
          { rule = "d /var/lib/dbus 0755 root root -"; }
          { rule = "L /var/lib/dbus/machine-id - - - - /etc/machine-id"; }
        ];
      };
}
