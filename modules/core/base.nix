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
