{ types, ... }:
{
  name = "base";

  options = {
    hostName = {
      type = types.str;
      default = "thermos";
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
  ];

  impl =
    { options, inputs, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      # NixOS patches pam_unix to hardcode /run/wrappers/bin/unix_chkpwd,
      # a setuid wrapper that doesn't exist outside NixOS. Remove the patch
      # so pam_unix uses the default ${sbin}/unix_chkpwd from its own store path.
      pam = pkgs.pam.overrideAttrs { postPatch = ""; };

      pamLogin = ''
        auth       required     ${pam}/lib/security/pam_unix.so nullok
        account    required     ${pam}/lib/security/pam_unix.so
        session    required     ${pam}/lib/security/pam_unix.so
      '';
      pamOther = ''
        auth       required     ${pam}/lib/security/pam_deny.so
        account    required     ${pam}/lib/security/pam_deny.so
        session    required     ${pam}/lib/security/pam_deny.so
      '';
      pamSystemdUser = ''
        account    required     ${pam}/lib/security/pam_unix.so no_pass_expiry
        session    required     ${pam}/lib/security/pam_loginuid.so
        session    optional     ${pam}/lib/security/pam_keyinit.so force revoke
        session    optional     ${pam}/lib/security/pam_umask.so silent
      '';
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
        # PAM config. Absolute store paths so no /lib/security symlink needed.
        {
          name = "pam.d/login";
          text = pamLogin;
        }
        {
          name = "pam.d/su";
          text = pamLogin;
        }
        {
          name = "pam.d/other";
          text = pamOther;
        }
        {
          name = "pam.d/systemd-user";
          text = pamSystemdUser;
        }
        # pam_unix and glibc NSS need this for passwd/group resolution.
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

      packages = map (p: { package = p; }) [
        pkgs.coreutils
        pkgs.bash
        pkgs.util-linux
        pkgs.systemd
      ];

      tmpfiles = [
        { rule = "d /var/log 0755 root root -"; }
        { rule = "d /var/tmp 1777 root root 30d"; }
        { rule = "d /tmp 1777 root root -"; }
        { rule = "d /run 0755 root root -"; }
      ];

      users = [
        {
          name = "root";
          uid = 0;
          gid = 0;
          home = "/root";
          shell = "/bin/sh";
          gecos = "System administrator";
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
