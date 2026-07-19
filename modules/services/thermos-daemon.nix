{ types, ... }:
{
  name = "thermos-daemon";

  options = {
    enable = {
      type = types.bool;
      default = false;
    };
  };

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
  ];

  impl =
    { options, inputs, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      daemon = (import ../../desktop { inherit pkgs; }).daemon;

      # The daemon owns org.thermos.Daemon1 on the system bus; dbus-daemon reads
      # /etc/dbus-1/system.d. Methods are Polkit-gated, so any client may send.
      dbusPolicy = ''
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE busconfig PUBLIC
         "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
         "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
        <busconfig>
          <policy user="thermos-daemon">
            <allow own="org.thermos.Daemon1"/>
          </policy>
          <policy context="default">
            <allow send_destination="org.thermos.Daemon1"/>
          </policy>
        </busconfig>
      '';

      thermosRules = ''
        polkit.addRule(function(action, subject) {
            if (action.id == "org.thermos.daemon.start-update" ||
                action.id == "org.thermos.daemon.apply-update") {
                if (subject.user == "root" || subject.active) {
                    return polkit.Result.YES;
                }
            }
        });
      '';
    in
    if !options.enable then
      {
        units = [ ];
        users = [ ];
        groups = [ ];
        packages = [ ];
        etc = [ ];
      }
    else
      {
        packages = [ { package = daemon; } ];

        users = [
          {
            name = "thermos-daemon";
            uid = 299;
            gid = 299;
            home = "/var/empty";
            shell = "/bin/nologin";
            gecos = "ThermOS system daemon";
          }
        ];

        groups = [
          {
            name = "thermos-daemon";
            gid = 299;
          }
        ];

        units = [
          {
            unitName = "thermos-daemon.service";
            unitConfig = {
              Unit = {
                Description = "ThermOS system update authority";
                After = [
                  "dbus.service"
                  "polkit.service"
                ];
                Requires = [ "dbus.service" ];
                Wants = [ "polkit.service" ];
              };
              Service = {
                Type = "dbus";
                BusName = "org.thermos.Daemon1";
                ExecStart = "${daemon}/bin/thermos-daemon";
                User = "thermos-daemon";
                Group = "thermos-daemon";
                Restart = "on-failure";
                RestartSec = "5s";
              };
              Install = {
                WantedBy = [ "multi-user.target" ];
              };
            };
          }
        ];

        etc = [
          {
            name = "dbus-1/system.d/org.thermos.Daemon1.conf";
            text = dbusPolicy;
          }
          {
            name = "polkit-1/rules.d/10-thermos.rules";
            text = thermosRules;
          }
        ];
      };
}
