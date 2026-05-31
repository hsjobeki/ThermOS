{ types, ... }:
{
  name = "openssh";

  options = {
    port = {
      type = types.int;
      default = 22;
    };
    permitRootLogin = {
      type = types.str;
      default = "prohibit-password";
    };
    authorizedKeys = {
      type = types.attrsOf (types.listOf types.str);
      default = { };
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
    "/contracts/pam"
    "/contracts/etc"
  ];

  impl =
    { options, inputs, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      openssh = pkgs.openssh;

      hostKeyTypes = [ "ed25519" ];

      sshdConfig = ''
        Port ${toString options.port}
        PermitRootLogin ${options.permitRootLogin}
        UsePAM yes
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        X11Forwarding no
        MaxAuthTries 3
        AuthorizedKeysFile /etc/ssh/authorized_keys/%u
        ${builtins.concatStringsSep "\n" (map (t: "HostKey /var/lib/ssh/ssh_host_${t}_key") hostKeyTypes)}
      '';

      authorizedKeyEntries = builtins.attrValues (
        builtins.mapAttrs (user: keys: {
          name = "ssh/authorized_keys/${user}";
          text = builtins.concatStringsSep "\n" keys + "\n";
          mode = "0444";
        }) options.authorizedKeys
      );
    in
    {
      users = [
        {
          name = "sshd";
          uid = 74;
          gid = 74;
          home = "/var/empty";
          shell = "/bin/nologin";
          gecos = "SSH privilege separation user";
        }
      ];

      groups = [
        {
          name = "sshd";
          gid = 74;
        }
      ];

      packages = [ { package = openssh; } ];

      units = [
        {
          unitName = "sshd.service";
          unitConfig = {
            Unit = {
              Description = "OpenSSH Daemon";
              After = [
                "network.target"
                "sshd-keygen.target"
              ];
              Requires = [ "sshd-keygen.target" ];
            };
            Service = {
              ExecStart = "${openssh}/bin/sshd -D -f /etc/ssh/sshd_config";
              Type = "simple";
              Restart = "on-failure";
              RestartSec = "5s";
            };
            Install = {
              WantedBy = [ "multi-user.target" ];
            };
          };
        }
        {
          unitName = "sshd-keygen.target";
          unitConfig = {
            Unit = {
              Description = "OpenSSH Host Key Generation";
            };
          };
        }
      ]
      # TODO: replace with secrets provisioning. First-boot generation is a
      # placeholder. Host keys should be injected at deployment time.
      ++ map (keyType: {
        unitName = "sshd-keygen-${keyType}.service";
        unitConfig = {
          Unit = {
            Description = "OpenSSH ${keyType} Host Key Generation";
            ConditionPathExists = "!/var/lib/ssh/ssh_host_${keyType}_key";
          };
          Service = {
            Type = "oneshot";
            StateDirectory = "ssh";
            StateDirectoryMode = "0700";
            ExecStart = "${openssh}/bin/ssh-keygen -t ${keyType} -f /var/lib/ssh/ssh_host_${keyType}_key -N \"\"";
          };
          Install = {
            WantedBy = [ "sshd-keygen.target" ];
          };
        };
      }) hostKeyTypes;

      pam = [
        {
          name = "sshd";
          rules = [
            {
              type = "auth";
              control = "required";
              module = "pam_unix";
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
      ];

      etc = [
        {
          name = "ssh/sshd_config";
          text = sshdConfig;
          mode = "0600";
        }
      ]
      ++ authorizedKeyEntries;
    };
}
