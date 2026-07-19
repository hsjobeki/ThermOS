{ types, ... }:
{
  name = "polkit";

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
      lib = inputs.nixpkgs.lib;

      # ThermOS has no /run/current-system, so polkit's default datadir
      # (/run/current-system/sw/share) would make polkitd read its action files
      # from a path that does not exist. Override the compiled datadir to the FHS
      # /usr/share that the rootfs assembles (the same structural fix as the kmod
      # /run/... fallback and the pam_unix wrapper un-patch: satisfy the path
      # instead of patching it out). Actions then live at /usr/share/polkit-1/
      # actions, which the rootfs links from the packages env; rules stay at the
      # /etc sysconfdir, which is already correct.
      polkit = pkgs.polkit.overrideAttrs (old: {
        mesonFlags = map (
          f: if lib.hasPrefix "--datadir=" f then "--datadir=/usr/share" else f
        ) old.mesonFlags;
        postInstall = builtins.replaceStrings [ "/run/current-system/sw" ] [ "/usr" ] old.postInstall;
      });

      # polkitd and share/polkit-1 live in polkit's `out` output; its DEFAULT
      # output is `bin` (small man pages), so reference `out` explicitly for both
      # the unit and the packages env (which would otherwise install bin and miss
      # share/polkit-1).
      polkitOut = polkit.out;

      # polkitd owns org.freedesktop.PolicyKit1 on the system bus. dbus-daemon
      # reads /etc/dbus-1/system.d, so ship the policy there (inlined to avoid
      # building polkit at eval time).
      dbusPolicy = ''
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE busconfig PUBLIC
         "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
         "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
        <busconfig>
          <policy user="polkituser">
            <allow own="org.freedesktop.PolicyKit1"/>
          </policy>
          <policy context="default">
            <allow send_destination="org.freedesktop.PolicyKit1"/>
          </policy>
          <policy user="polkituser">
            <allow send_interface="org.freedesktop.PolicyKit1.AuthenticationAgent"/>
          </policy>
        </busconfig>
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
        packages = [ { package = polkitOut; } ];

        users = [
          {
            name = "polkituser";
            uid = 27;
            gid = 27;
            home = "/var/empty";
            shell = "/bin/nologin";
            gecos = "PolicyKit daemon";
          }
        ];

        groups = [
          {
            name = "polkituser";
            gid = 27;
          }
        ];

        units = [
          {
            unitName = "polkit.service";
            unitConfig = {
              Unit = {
                Description = "Authorization Manager";
                Documentation = [ "man:polkit(8)" ];
                After = [ "dbus.service" ];
                Requires = [ "dbus.service" ];
              };
              Service = {
                Type = "dbus";
                BusName = "org.freedesktop.PolicyKit1";
                ExecStart = "${polkitOut}/lib/polkit-1/polkitd --no-debug --log-level=notice";
                User = "polkituser";
                # polkitd starts already as polkituser (built -Dpolkitd_user=
                # polkituser; v127 skips the setgroups privilege drop when already
                # the target uid), so it holds and needs no capabilities. Empty is
                # the real least-privilege ceiling: a non-empty set here would be
                # inert (a process that starts unprivileged gets no caps without
                # AmbientCapabilities) and would falsely imply polkitd uses them.
                CapabilityBoundingSet = "";
                NoNewPrivileges = "yes";
                RestrictAddressFamilies = "AF_UNIX";
                Restart = "on-failure";
              };
              Install = {
                WantedBy = [ "multi-user.target" ];
              };
            };
          }
        ];

        etc = [
          {
            name = "dbus-1/system.d/org.freedesktop.PolicyKit1.conf";
            text = dbusPolicy;
          }
        ];
      };
}
