{ types, ... }:
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

      # Two surgical edits to the stock system.conf, which we publish as
      # /etc/dbus-1/system.conf (dbus-daemon --system reads that path):
      #   1. Strip the self-include of /etc/dbus-1/system.conf, else the file
      #      includes itself and dbus-daemon fails with "Circular inclusion".
      #   2. Add an absolute include for /usr/share/dbus-1/system.d. The stock
      #      relative <includedir>system.d</includedir> resolves against the
      #      config's location, i.e. /etc/dbus-1/system.d, never /usr/share.
      #      systemd ships its bus policies (login1, systemd1, hostname1, ...)
      #      under /usr/share/dbus-1/system.d (the rootfs places them there).
      #      Without this include, root has no <allow
      #      own="org.freedesktop.systemd1"/>, PID1 cannot own the name, dbus
      #      treats it as activatable (runs /bin/false, times out), and logind
      #      user-sessions plus every Type=dbus service break.
      dbusSystemConf =
        builtins.replaceStrings
          [
            ''<include ignore_missing="yes">/etc/dbus-1/system.conf</include>''
            "<includedir>/etc/dbus-1/system.d</includedir>"
          ]
          [
            ""
            "<includedir>/etc/dbus-1/system.d</includedir>\n  <includedir>/usr/share/dbus-1/system.d</includedir>"
          ]
          (builtins.readFile "${dbus}/share/dbus-1/system.conf");

      # The per-user session bus (dbus-daemon --session) reads /etc/dbus-1/
      # session.conf. Same self-include problem as system.conf; strip it. No
      # /usr/share include needed: the session bus carries no systemd own-name
      # policy (those are system-bus only).
      dbusSessionConf =
        builtins.replaceStrings
          [ ''<include ignore_missing="yes">/etc/dbus-1/session.conf</include>'' ]
          [ "" ]
          (builtins.readFile "${dbus}/share/dbus-1/session.conf");
    in
    if
      lib.hasInfix ''<include ignore_missing="yes">/etc/dbus-1/system.conf</include>'' dbusSystemConf
    then
      throw "dbus: replaceStrings failed to strip self-include from system.conf"
    else if !lib.hasInfix "<includedir>/usr/share/dbus-1/system.d</includedir>" dbusSystemConf then
      throw "dbus: failed to add /usr/share/dbus-1/system.d includedir; systemd D-Bus policies would not load and PID1 could not own org.freedesktop.systemd1"
    else if
      lib.hasInfix ''<include ignore_missing="yes">/etc/dbus-1/session.conf</include>'' dbusSessionConf
    then
      throw "dbus: replaceStrings failed to strip self-include from session.conf"
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
          # Per-user session bus. systemd user managers (user@UID.service) look
          # for a unit literally named dbus.socket to provide $XDG_RUNTIME_DIR/bus;
          # this is the same name as the system socket above, at a different
          # scope, hence the contract keys by (scope, name). Without it
          # `systemctl --user` and graphical-session.target (the desktop bars)
          # have no bus to talk to.
          {
            unitName = "dbus.socket";
            scope = "user";
            unitConfig = {
              Unit = {
                Description = "D-Bus User Message Bus Socket";
              };
              Socket = {
                ListenStream = "%t/bus";
              };
              Install = {
                WantedBy = [ "sockets.target" ];
              };
            };
          }
          {
            unitName = "dbus.service";
            scope = "user";
            unitConfig = {
              Unit = {
                Description = "D-Bus User Message Bus";
                Documentation = [ "man:dbus-daemon(1)" ];
                Requires = [ "dbus.socket" ];
              };
              Service = {
                Type = "notify";
                NotifyAccess = "main";
                ExecStart = "${dbus}/bin/dbus-daemon --session --address=systemd: --nofork --nopidfile --systemd-activation --syslog-only";
                ExecReload = "${dbus}/bin/dbus-send --print-reply --session --type=method_call --dest=org.freedesktop.DBus / org.freedesktop.DBus.ReloadConfig";
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
          {
            name = "dbus-1/session.conf";
            text = dbusSessionConf;
          }
        ];

        tmpfiles = [
          { rule = "d /run/dbus 0755 messagebus messagebus -"; }
          { rule = "d /var/lib/dbus 0755 root root -"; }
          { rule = "L /var/lib/dbus/machine-id - - - - /etc/machine-id"; }
        ];
      };
}
