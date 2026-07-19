{ types, ... }:
{
  name = "base";

  options = {
    hostName = {
      type = types.str;
      default = "thermos";
    };
    rootHashedPassword = {
      type = types.str;
      default = "!";
    };
  };

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
  };

  publish = [
    "/contracts/etc"
    "/contracts/packages"
    "/contracts/tmpfiles"
    "/contracts/users"
    "/contracts/groups"
    "/contracts/pam"
  ];

  impl =
    { options, inputs, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;
    in
    {
      etc = [
        {
          name = "hostname";
          text = options.hostName;
        }
        {
          name = "os-release";
          text = ''
            NAME=ThermOS
            ID=thermos
            PRETTY_NAME="ThermOS"
          '';
        }
        {
          name = "nsswitch.conf";
          text = ''
            passwd: files
            group:  files
            shadow: files
          '';
        }
        {
          name = "profile";
          text = ''
            export PATH=/bin:/usr/bin
            if [ -d /etc/profile.d ]; then
              for f in /etc/profile.d/*.sh; do
                [ -r "$f" ] && . "$f"
              done
              unset f
            fi
          '';
        }
      ];

      pam = [
        {
          name = "login";
          rules = [
            {
              type = "auth";
              control = "required";
              module = "pam_unix";
              args = "nullok";
            }
            {
              type = "account";
              control = "required";
              module = "pam_unix";
            }
            {
              type = "session";
              control = "required";
              module = "pam_unix";
            }
            {
              type = "session";
              control = "optional";
              module = "pam_loginuid";
            }
            {
              type = "session";
              control = "optional";
              module = "pam_systemd";
            }
          ];
        }
        {
          name = "su";
          rules = [
            {
              type = "auth";
              control = "required";
              module = "pam_unix";
              args = "nullok";
            }
            {
              type = "account";
              control = "required";
              module = "pam_unix";
            }
            {
              type = "session";
              control = "required";
              module = "pam_unix";
            }
          ];
        }
        {
          name = "other";
          rules = [
            {
              type = "auth";
              control = "required";
              module = "pam_deny";
            }
            {
              type = "account";
              control = "required";
              module = "pam_deny";
            }
            {
              type = "session";
              control = "required";
              module = "pam_deny";
            }
          ];
        }
        {
          name = "systemd-user";
          rules = [
            {
              type = "account";
              control = "required";
              module = "pam_unix";
              args = "no_pass_expiry";
            }
            {
              type = "session";
              control = "required";
              module = "pam_loginuid";
            }
            {
              type = "session";
              control = "optional";
              module = "pam_keyinit";
              args = "force revoke";
            }
            {
              type = "session";
              control = "optional";
              module = "pam_umask";
              args = "silent";
            }
            {
              # pam_systemd here is special-cased by systemd to set
              # XDG_RUNTIME_DIR for the per-user manager (user@UID.service runs
              # PAMName=systemd-user). Without it `systemd --user` exits "Trying
              # to run as user instance, but $XDG_RUNTIME_DIR is not set", so the
              # user bus never starts and graphical-session.target (the desktop
              # bars) cannot come up.
              type = "session";
              control = "optional";
              module = "pam_systemd";
            }
          ];
        }
      ];

      packages = map (p: { package = p; }) [
        pkgs.coreutils
        pkgs.bash
        pkgs.util-linux
        pkgs.systemd
      ];

      tmpfiles = [
        { rule = "d /root 0700 root root -"; }
        { rule = "d /var/log 0755 root root -"; }
        { rule = "d /var/empty 0555 root root -"; }
        { rule = "d /var/tmp 1777 root root 30d"; }
        { rule = "d /tmp 1777 root root -"; }
        { rule = "d /run 0755 root root -"; }
        # FHS /var/run -> /run. systemd's stock var.conf creates this, but ThermOS
        # processes only its own tmpfiles. Clients using the legacy /var/run path
        # need it: zbus defaults the system bus to /var/run/dbus/system_bus_socket,
        # so without it the desktop bars cannot reach the bus at /run/dbus.
        { rule = "L /var/run - - - - ../run"; }
        # nixpkgs systemd is built with SYSTEMD_BINARY_PATH and default-user-shell
        # under /run/current-system (a NixOS layout). Without it, `systemctl
        # daemon-reexec` fails ("Failed to execute our own binary") and PID1 cannot
        # re-establish itself. Point it at the systemd package so reexec works.
        { rule = "d /run/current-system 0755 root root -"; }
        { rule = "L+ /run/current-system/systemd - - - - ${pkgs.systemd}"; }
        # nix store normalizes all files to 0444; fix at boot
        { rule = "z /etc/shadow 0640 root root -"; }
      ];

      users = [
        {
          name = "root";
          uid = 0;
          gid = 0;
          home = "/root";
          shell = "/bin/sh";
          gecos = "System administrator";
          hashedPassword = options.rootHashedPassword;
        }
        {
          name = "nobody";
          uid = 65534;
          gid = 65534;
          home = "/var/empty";
          shell = "/bin/nologin";
          gecos = "Nobody";
        }
      ];

      groups = [
        {
          name = "root";
          gid = 0;
        }
        {
          name = "nobody";
          gid = 65534;
        }
      ];
    };
}
