{ types, ... }:
{
  name = "getty";

  options = {
    ttys = {
      type = types.listOf types.str;
      default = [ "tty1" ];
    };
    serialTtys = {
      type = types.listOf types.str;
      default = [ ];
    };
    autologinUser = {
      type = types.str;
      default = "";
    };
    baudRate = {
      type = types.str;
      default = "115200";
    };
  };

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
  };

  publish = [
    "/contracts/units"
  ];

  impl =
    { options, inputs, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;

      agetty = "${pkgs.util-linux}/bin/agetty";

      autologinArgs = if options.autologinUser != "" then "--autologin ${options.autologinUser} " else "";

      ttyUnit = tty: {
        unitName = "getty@${tty}.service";
        unitConfig = {
          Unit = {
            Description = "Getty on ${tty}";
            After = [
              "systemd-user-sessions.service"
              "plymouth-quit-wait.service"
            ];
            ConditionPathExists = "/dev/${tty}";
          };
          Service = {
            ExecStart = "${agetty} ${autologinArgs}--noclear ${tty} linux";
            Type = "idle";
            Restart = "always";
            RestartSec = "0";
            UtmpIdentifier = tty;
            TTYPath = "/dev/${tty}";
            TTYReset = "yes";
            TTYVHangup = "yes";
            TTYVTDisallocate = "yes";
            StandardInput = "tty";
            StandardOutput = "tty";
          };
          Install = {
            WantedBy = [ "multi-user.target" ];
          };
        };
      };

      serialUnit = tty: {
        unitName = "serial-getty@${tty}.service";
        unitConfig = {
          Unit = {
            Description = "Serial Getty on ${tty}";
            After = [ "systemd-user-sessions.service" ];
            BindsTo = [ "dev-${tty}.device" ];
          };
          Service = {
            ExecStart = "${agetty} ${autologinArgs}--keep-baud ${tty} ${options.baudRate} vt100";
            Type = "idle";
            Restart = "always";
            RestartSec = "0";
            UtmpIdentifier = tty;
            TTYPath = "/dev/${tty}";
            TTYReset = "yes";
            TTYVHangup = "yes";
            StandardInput = "tty";
            StandardOutput = "tty";
          };
          Install = {
            WantedBy = [ "multi-user.target" ];
          };
        };
      };
    in
    {
      units = (map ttyUnit options.ttys) ++ (map serialUnit options.serialTtys);
    };
}
