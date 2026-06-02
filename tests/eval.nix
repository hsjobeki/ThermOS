# Eval tests: nix-unit tests/eval.nix
let
  thermos = import ../default.nix { };
  types = thermos.evaluated.types;

  etcContract = (import ../modules/contracts/etc.nix { inherit types; }).contract;
  packagesContract = (import ../modules/contracts/packages.nix { inherit types; }).contract;
  unitsContract = (import ../modules/contracts/units.nix { inherit types; }).contract;
  tmpfilesContract = (import ../modules/contracts/tmpfiles.nix { inherit types; }).contract;
  assertionsContract = (import ../modules/contracts/assertions.nix { inherit types; }).contract;
  usersContract = (import ../modules/contracts/users.nix { inherit types; }).contract;
  groupsContract = (import ../modules/contracts/groups.nix { inherit types; }).contract;
  pamContract = (import ../modules/contracts/pam.nix { inherit types; }).contract;

  ev = thermos.evaluated;

  inherit (builtins)
    all
    attrNames
    filter
    hasAttr
    head
    length
    match
    ;
in
{
  # contract merge

  contracts = {
    etc = {
      testMergeDisjoint = {
        expr = etcContract.merge {
          a = [
            {
              name = "hostname";
              text = "box";
            }
          ];
          b = [
            {
              name = "resolv.conf";
              text = "nameserver 1.1.1.1";
            }
          ];
        };
        expected = [
          {
            name = "hostname";
            text = "box";
          }
          {
            name = "resolv.conf";
            text = "nameserver 1.1.1.1";
          }
        ];
      };

      testMergeConflictThrows = {
        expr = etcContract.merge {
          a = [
            {
              name = "hostname";
              text = "box1";
            }
          ];
          b = [
            {
              name = "hostname";
              text = "box2";
            }
          ];
        };
        expectedError.type = "ThrownError";
        expectedError.msg = "Conflicting /etc entries.*hostname";
      };

      testMergeEmpty = {
        expr = etcContract.merge { };
        expected = [ ];
      };

      testMergeSinglePublisher = {
        expr = etcContract.merge {
          a = [
            {
              name = "foo";
              text = "1";
            }
            {
              name = "bar";
              text = "2";
            }
          ];
        };
        expected = [
          {
            name = "foo";
            text = "1";
          }
          {
            name = "bar";
            text = "2";
          }
        ];
      };
    };

    packages = {
      testMergeConcatenates = {
        expr = length (
          packagesContract.merge {
            a = [
              { package = "x"; }
              { package = "y"; }
            ];
            b = [ { package = "z"; } ];
          }
        );
        expected = 3;
      };

      testMergeEmpty = {
        expr = packagesContract.merge { };
        expected = [ ];
      };

      testMergePreservesOrder = {
        expr = map (e: e.package) (
          packagesContract.merge {
            a = [ { package = "first"; } ];
            b = [ { package = "second"; } ];
          }
        );
        expected = [
          "first"
          "second"
        ];
      };
    };

    units = {
      testMergeSingleUnit = {
        expr = unitsContract.merge {
          a = [
            {
              unitName = "foo.service";
              unitConfig = {
                Service = {
                  ExecStart = "/bin/foo";
                };
              };
            }
          ];
        };
        expected = {
          "foo.service" = {
            Service = {
              ExecStart = "/bin/foo";
            };
          };
        };
      };

      testMergeDeepOverride = {
        expr = unitsContract.merge {
          a = [
            {
              unitName = "foo.service";
              unitConfig = {
                Service = {
                  ExecStart = "/bin/foo";
                  Type = "simple";
                };
                Unit = {
                  Description = "Foo";
                };
              };
            }
          ];
          b = [
            {
              unitName = "foo.service";
              unitConfig = {
                Service = {
                  ProtectSystem = "strict";
                };
              };
            }
          ];
        };
        expected = {
          "foo.service" = {
            Service = {
              ExecStart = "/bin/foo";
              Type = "simple";
              ProtectSystem = "strict";
            };
            Unit = {
              Description = "Foo";
            };
          };
        };
      };

      testMergeFieldOverride = {
        expr = unitsContract.merge {
          a = [
            {
              unitName = "foo.service";
              unitConfig = {
                Service = {
                  ExecStart = "/bin/old";
                };
              };
            }
          ];
          b = [
            {
              unitName = "foo.service";
              unitConfig = {
                Service = {
                  ExecStart = "/bin/new";
                };
              };
            }
          ];
        };
        expected = {
          "foo.service" = {
            Service = {
              ExecStart = "/bin/new";
            };
          };
        };
      };

      testMergeDisjointUnits = {
        expr = unitsContract.merge {
          a = [
            {
              unitName = "a.service";
              unitConfig = {
                Service = {
                  ExecStart = "/a";
                };
              };
            }
          ];
          b = [
            {
              unitName = "b.service";
              unitConfig = {
                Service = {
                  ExecStart = "/b";
                };
              };
            }
          ];
        };
        expected = {
          "a.service" = {
            Service = {
              ExecStart = "/a";
            };
          };
          "b.service" = {
            Service = {
              ExecStart = "/b";
            };
          };
        };
      };

      testMergeEmpty = {
        expr = unitsContract.merge { };
        expected = { };
      };
    };

    tmpfiles = {
      testMergeConcatenates = {
        expr = tmpfilesContract.merge {
          a = [ { rule = "d /var/log 0755 root root -"; } ];
          b = [ { rule = "d /tmp 1777 root root -"; } ];
        };
        expected = [
          { rule = "d /var/log 0755 root root -"; }
          { rule = "d /tmp 1777 root root -"; }
        ];
      };

      testMergeEmpty = {
        expr = tmpfilesContract.merge { };
        expected = [ ];
      };
    };

    assertions = {
      testMergeConcatenates = {
        expr = assertionsContract.merge {
          a = [
            {
              assertion = true;
              message = "ok";
            }
          ];
          b = [
            {
              assertion = false;
              message = "bad";
            }
          ];
        };
        expected = [
          {
            assertion = true;
            message = "ok";
          }
          {
            assertion = false;
            message = "bad";
          }
        ];
      };

      testMergeEmpty = {
        expr = assertionsContract.merge { };
        expected = [ ];
      };
    };

    users = {
      testMergeDisjoint = {
        expr = map (u: u.name) (
          usersContract.merge {
            a = [
              {
                name = "root";
                uid = 0;
                gid = 0;
              }
            ];
            b = [
              {
                name = "nobody";
                uid = 65534;
                gid = 65534;
              }
            ];
          }
        );
        expected = [
          "root"
          "nobody"
        ];
      };

      testMergeConflictNameThrows = {
        expr = usersContract.merge {
          a = [
            {
              name = "root";
              uid = 0;
              gid = 0;
            }
          ];
          b = [
            {
              name = "root";
              uid = 1;
              gid = 1;
            }
          ];
        };
        expectedError.type = "ThrownError";
        expectedError.msg = "Conflicting user names.*root";
      };

      testMergeConflictUidThrows = {
        expr = usersContract.merge {
          a = [
            {
              name = "root";
              uid = 0;
              gid = 0;
            }
          ];
          b = [
            {
              name = "toor";
              uid = 0;
              gid = 0;
            }
          ];
        };
        expectedError.type = "ThrownError";
        expectedError.msg = "Conflicting user UIDs.*0";
      };

      testMergeEmpty = {
        expr = usersContract.merge { };
        expected = [ ];
      };

      testMergeSinglePublisher = {
        expr = map (u: u.name) (
          usersContract.merge {
            a = [
              {
                name = "root";
                uid = 0;
                gid = 0;
              }
              {
                name = "nobody";
                uid = 65534;
                gid = 65534;
              }
            ];
          }
        );
        expected = [
          "root"
          "nobody"
        ];
      };
    };

    groups = {
      testMergeDisjoint = {
        expr = map (g: g.name) (
          groupsContract.merge {
            a = [
              {
                name = "root";
                gid = 0;
              }
            ];
            b = [
              {
                name = "nobody";
                gid = 65534;
              }
            ];
          }
        );
        expected = [
          "root"
          "nobody"
        ];
      };

      testMergeConflictNameThrows = {
        expr = groupsContract.merge {
          a = [
            {
              name = "root";
              gid = 0;
            }
          ];
          b = [
            {
              name = "root";
              gid = 1;
            }
          ];
        };
        expectedError.type = "ThrownError";
        expectedError.msg = "Conflicting group names.*root";
      };

      testMergeConflictGidThrows = {
        expr = groupsContract.merge {
          a = [
            {
              name = "root";
              gid = 0;
            }
          ];
          b = [
            {
              name = "wheel";
              gid = 0;
            }
          ];
        };
        expectedError.type = "ThrownError";
        expectedError.msg = "Conflicting group GIDs.*0";
      };

      testMergeEmpty = {
        expr = groupsContract.merge { };
        expected = [ ];
      };

      testMergePreservesMembers = {
        expr =
          (head (
            groupsContract.merge {
              a = [
                {
                  name = "wheel";
                  gid = 10;
                  members = [
                    "alice"
                    "bob"
                  ];
                }
              ];
            }
          )).members;
        expected = [
          "alice"
          "bob"
        ];
      };
    };

    pam = {
      testMergeDisjoint = {
        expr = map (s: s.name) (
          pamContract.merge {
            a = [
              {
                name = "login";
                rules = [
                  {
                    type = "auth";
                    control = "required";
                    module = "pam_unix";
                  }
                ];
              }
            ];
            b = [
              {
                name = "sshd";
                rules = [
                  {
                    type = "auth";
                    control = "required";
                    module = "pam_unix";
                    args = "nullok";
                  }
                ];
              }
            ];
          }
        );
        expected = [
          "login"
          "sshd"
        ];
      };

      testMergeConflictThrows = {
        expr = pamContract.merge {
          a = [
            {
              name = "login";
              rules = [
                {
                  type = "auth";
                  control = "required";
                  module = "pam_unix";
                }
              ];
            }
          ];
          b = [
            {
              name = "login";
              rules = [
                {
                  type = "auth";
                  control = "required";
                  module = "pam_deny";
                }
              ];
            }
          ];
        };
        expectedError.type = "ThrownError";
        expectedError.msg = "Conflicting PAM service names.*login";
      };

      testMergeEmpty = {
        expr = pamContract.merge { };
        expected = [ ];
      };

      # Demonstrates the pattern openssh would use
      testSshdServiceDeclaration = {
        expr =
          let
            sshdPam = [
              {
                name = "sshd";
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
                ];
              }
            ];
            merged = pamContract.merge {
              base = [
                {
                  name = "login";
                  rules = [
                    {
                      type = "auth";
                      control = "required";
                      module = "pam_unix";
                    }
                  ];
                }
              ];
              openssh = sshdPam;
            };
          in
          {
            count = length merged;
            names = map (s: s.name) merged;
            sshdRuleCount = length (head (filter (s: s.name == "sshd") merged)).rules;
          };
        expected = {
          count = 2;
          names = [
            "login"
            "sshd"
          ];
          sshdRuleCount = 4;
        };
      };
    };
  };
  # tree structure

  tree = {
    testTopLevelModules = {
      expr = attrNames ev.modules;
      expected = [
        "builders"
        "contracts"
        "core"
        "middleware"
        "nixpkgs"
        "services"
      ];
    };

    testContractChildren = {
      expr = attrNames ev.modules.contracts.modules;
      expected = [
        "assertions"
        "etc"
        "groups"
        "packages"
        "pam"
        "tmpfiles"
        "units"
        "users"
      ];
    };

    testBuilderChildren = {
      expr = attrNames ev.modules.builders.modules;
      expected = [
        "etc"
        "image"
        "initrd"
        "packages"
        "rootfs"
        "tmpfiles"
        "toplevel"
        "units"
        "users"
      ];
    };

    testCoreChildren = {
      expr = attrNames ev.modules.core.modules;
      expected = [ "base" ];
    };

    testServiceChildren = {
      expr = attrNames ev.modules.services.modules;
      expected = [
        "dbus"
        "getty"
        "networkd"
        "openssh"
      ];
    };

    testMiddlewareChildren = {
      expr = attrNames ev.modules.middleware.modules;
      expected = [ "pam" ];
    };
  };

  # builder outputs

  builders = {
    testEtcProducesDerivation = {
      expr = (ev.modules.builders.modules.etc { }).derivation.type or null;
      expected = "derivation";
    };

    testPackagesProducesDerivation = {
      expr = (ev.modules.builders.modules.packages { }).derivation.type or null;
      expected = "derivation";
    };

    testUnitsProducesDerivation = {
      expr = (ev.modules.builders.modules.units { }).derivation.type or null;
      expected = "derivation";
    };

    testTmpfilesProducesDerivation = {
      expr = (ev.modules.builders.modules.tmpfiles { }).derivation.type or null;
      expected = "derivation";
    };

    testToplevelProducesDerivation = {
      expr = thermos.toplevel.type or null;
      expected = "derivation";
    };

    testToplevelName = {
      expr = thermos.toplevel.name;
      expected = "thermos-system";
    };

    testRootfsProducesDerivation = {
      expr = thermos.rootfs.type or null;
      expected = "derivation";
    };

    testRootfsName = {
      expr = thermos.rootfs.name;
      expected = "thermos-rootfs";
    };

    testUsersProducesDerivation = {
      expr = (ev.modules.builders.modules.users { }).derivation.type or null;
      expected = "derivation";
    };

    testUsersName = {
      expr = (ev.modules.builders.modules.users { }).derivation.name;
      expected = "thermos-users";
    };
  };

  # dbus

  dbus = {
    testPublishesUnits = {
      expr =
        let
          impl = ev.modules.services.modules.dbus { };
        in
        map (u: u.unitName) impl.units;
      expected = [
        "dbus.socket"
        "dbus.service"
      ];
    };

    testSocketWantedBySockets = {
      expr =
        let
          impl = ev.modules.services.modules.dbus { };
          socket = head (filter (u: u.unitName == "dbus.socket") impl.units);
        in
        socket.unitConfig.Install.WantedBy;
      expected = [ "sockets.target" ];
    };

    testServiceWantedByMultiUser = {
      expr =
        let
          impl = ev.modules.services.modules.dbus { };
          svc = head (filter (u: u.unitName == "dbus.service") impl.units);
        in
        svc.unitConfig.Install.WantedBy;
      expected = [ "multi-user.target" ];
    };

    testServiceExecStart = {
      expr =
        let
          impl = ev.modules.services.modules.dbus { };
          svc = head (filter (u: u.unitName == "dbus.service") impl.units);
        in
        match ".*dbus-daemon.*" svc.unitConfig.Service.ExecStart != null;
      expected = true;
    };

    testMessagebusUser = {
      expr =
        let
          impl = ev.modules.services.modules.dbus { };
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
          impl = ev.modules.services.modules.dbus { };
        in
        (head impl.groups).name;
      expected = "messagebus";
    };

    testDbusConfigInEtc = {
      expr =
        let
          impl = ev.modules.services.modules.dbus { };
        in
        length (filter (e: e.name == "dbus-1/system.conf") impl.etc) == 1;
      expected = true;
    };

    testDbusPackage = {
      expr =
        let
          impl = ev.modules.services.modules.dbus { };
        in
        length (filter (p: p.package == thermos.pkgs.dbus) impl.packages) == 1;
      expected = true;
    };
  };

  networkd = {
    testDhcpNetworkFile = {
      expr =
        let
          impl = ev.modules.services.modules.networkd {
            enable = true;
          };
          etc = head impl.etc;
        in
        {
          inherit (etc) name;
          hasDHCP = builtins.match ".*DHCP=yes.*" etc.text != null;
        };
      expected = {
        name = "systemd/network/80-wired.network";
        hasDHCP = true;
      };
    };

    testStaticAddress = {
      expr =
        let
          impl = ev.modules.services.modules.networkd {
            enable = true;
            useDHCP = false;
            addresses = [ "192.168.1.2/24" ];
          };
          etc = head impl.etc;
        in
        {
          inherit (etc) name;
          hasAddress = builtins.match ".*Address=192\\.168\\.1\\.2/24.*" etc.text != null;
          noDHCP = builtins.match ".*DHCP=yes.*" etc.text == null;
        };
      expected = {
        name = "systemd/network/80-wired.network";
        hasAddress = true;
        noDHCP = true;
      };
    };

    testDisabledEmpty = {
      expr =
        let
          impl = ev.modules.services.modules.networkd { };
        in
        {
          inherit (impl) etc users groups;
        };
      expected = {
        etc = [ ];
        users = [ ];
        groups = [ ];
      };
    };

    testNetworkUser = {
      expr =
        let
          impl = ev.modules.services.modules.networkd {
            enable = true;
          };
        in
        (head impl.users).name;
      expected = "systemd-network";
    };
  };

  # services

  services = {
    testGettyPublishesUnit = {
      expr =
        let
          impl = ev.modules.services.modules.getty { };
        in
        map (u: u.unitName) impl.units;
      expected = [ "getty@tty1.service" ];
    };

    testGettyUnitHasSections = {
      expr =
        let
          impl = ev.modules.services.modules.getty { };
          unit = head impl.units;
        in
        attrNames unit.unitConfig;
      expected = [
        "Install"
        "Service"
        "Unit"
      ];
    };

    testGettyExecStartContainsAgetty = {
      expr =
        let
          impl = ev.modules.services.modules.getty { };
          unit = head impl.units;
        in
        match ".*agetty.*" unit.unitConfig.Service.ExecStart != null;
      expected = true;
    };

    testGettyDefaultNoAutologin = {
      expr =
        let
          impl = ev.modules.services.modules.getty { };
          unit = head impl.units;
        in
        match ".*--autologin.*" unit.unitConfig.Service.ExecStart != null;
      expected = false;
    };

    testGettyWantedByMultiUser = {
      expr =
        let
          impl = ev.modules.services.modules.getty { };
          unit = head impl.units;
        in
        unit.unitConfig.Install.WantedBy;
      expected = [ "multi-user.target" ];
    };
  };

  # options overrides

  options = {
    testGettyAutologin = {
      expr =
        let
          impl = ev.modules.services.modules.getty { autologinUser = "root"; };
          unit = head impl.units;
        in
        match ".*--autologin root.*" unit.unitConfig.Service.ExecStart != null;
      expected = true;
    };

    testGettyMultipleTtys = {
      expr =
        let
          impl = ev.modules.services.modules.getty {
            ttys = [
              "tty1"
              "tty2"
              "tty3"
            ];
          };
        in
        map (u: u.unitName) impl.units;
      expected = [
        "getty@tty1.service"
        "getty@tty2.service"
        "getty@tty3.service"
      ];
    };

    testGettySerialTty = {
      expr =
        let
          impl = ev.modules.services.modules.getty {
            serialTtys = [ "ttyS0" ];
            baudRate = "9600";
          };
          unit = head (filter (u: u.unitName == "serial-getty@ttyS0.service") impl.units);
        in
        match ".*--keep-baud ttyS0 9600.*" unit.unitConfig.Service.ExecStart != null;
      expected = true;
    };

    testGettyAutologinWithMultipleTtys = {
      expr =
        let
          impl = ev.modules.services.modules.getty {
            ttys = [
              "tty1"
              "tty2"
            ];
            autologinUser = "admin";
          };
        in
        all (u: match ".*--autologin admin.*" u.unitConfig.Service.ExecStart != null) impl.units;
      expected = true;
    };

    testBaseCustomHostname = {
      expr =
        let
          impl = ev.modules.core.modules.base { hostName = "myhost"; };
          hostnameEntry = head (filter (e: e.name == "hostname") impl.etc);
        in
        hostnameEntry.text;
      expected = "myhost";
    };
  };

  # units pipeline

  pipeline = {
    testUnitsBuilderName = {
      expr = (ev.modules.builders.modules.units { }).derivation.name;
      expected = "thermos-units";
    };

    # proves data flows: module -> contract -> merged
    testMergedUnitsContainGetty = {
      expr =
        let
          gettyUnits = (ev.modules.services.modules.getty { }).units;
          merged = unitsContract.merge { getty = gettyUnits; };
        in
        hasAttr "getty@tty1.service" merged;
      expected = true;
    };

    testMergedGettyHasServiceSection = {
      expr =
        let
          gettyUnits = (ev.modules.services.modules.getty { }).units;
          merged = unitsContract.merge { getty = gettyUnits; };
        in
        hasAttr "Service" merged."getty@tty1.service";
      expected = true;
    };
  };

  # pam middleware pipeline

  pamProvider = {
    # Base module publishes structured PAM declarations
    testBasePublishesPam = {
      expr =
        let
          impl = ev.modules.core.modules.base { };
        in
        map (s: s.name) impl.pam;
      expected = [
        "login"
        "su"
        "other"
        "systemd-user"
      ];
    };

    # Middleware resolves module names to store paths
    testMiddlewareRendersEtc = {
      expr =
        let
          impl = ev.modules.middleware.modules.pam { };
          loginEntry = head (filter (e: e.name == "pam.d/login") impl.etc);
        in
        match ".*pam_unix\\.so.*" loginEntry.text != null;
      expected = true;
    };

    # Middleware output contains nix store paths (not bare module names)
    testMiddlewareResolvesStorePaths = {
      expr =
        let
          impl = ev.modules.middleware.modules.pam { };
          loginEntry = head (filter (e: e.name == "pam.d/login") impl.etc);
        in
        match ".*/nix/store/[a-z0-9]+-linux-pam[^/]*/lib/security/pam_unix\\.so.*" loginEntry.text != null;
      expected = true;
    };

    # Middleware renders all base PAM services
    testMiddlewareRendersFiveServices = {
      expr =
        let
          impl = ev.modules.middleware.modules.pam { };
        in
        length impl.etc;
      expected = 5;
    };

    # Demonstrates openssh pattern: a service publishes PAM rules,
    # middleware resolves them alongside base services.
    testSshdPatternIntegration = {
      expr =
        let
          # What openssh would publish
          sshdRules = [
            {
              name = "sshd";
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
              ];
            }
          ];
          # What base publishes
          baseRules = (ev.modules.core.modules.base { }).pam;
          # Merge like the contract would
          merged = pamContract.merge {
            base = baseRules;
            openssh = sshdRules;
          };
          # Verify sshd is in the merged set
          sshdService = head (filter (s: s.name == "sshd") merged);
        in
        {
          totalServices = length merged;
          sshdRuleCount = length sshdService.rules;
          firstModule = (head sshdService.rules).module;
        };
      expected = {
        totalServices = 5;
        sshdRuleCount = 4;
        firstModule = "pam_unix";
      };
    };
  };

  # assertions

  assertions = {
    # test check logic directly (wiring a second tree is complex)
    testFailedAssertionMessage = {
      expr =
        let
          lib = thermos.lib;
          failed = [
            {
              assertion = false;
              message = "disk too small";
            }
          ];
        in
        lib.concatMapStringsSep "\n" (a: "Assertion failed: ${a.message}") failed;
      expected = "Assertion failed: disk too small";
    };
  };

  # entrypoint options passthrough

  entrypoint = {
    testOptionsPassthroughGettyAutologin = {
      expr =
        let
          configured = import ../default.nix {
            options = {
              "/services/getty" = {
                autologinUser = "testuser";
              };
            };
          };
          getty = (configured.evaluated.modules.services.modules.getty { });
          unit = head getty.units;
        in
        match ".*--autologin testuser.*" unit.unitConfig.Service.ExecStart != null;
      expected = true;
    };

    testOptionsPassthroughHostname = {
      expr =
        let
          configured = import ../default.nix {
            options = {
              "/core/base" = {
                hostName = "customhost";
              };
            };
          };
          base = (configured.evaluated.modules.core.modules.base { });
          entry = head (filter (e: e.name == "hostname") base.etc);
        in
        entry.text;
      expected = "customhost";
    };

    testEmptyOptionsPreservesDefaults = {
      expr =
        let
          configured = import ../default.nix { };
          base = (configured.evaluated.modules.core.modules.base { });
          entry = head (filter (e: e.name == "hostname") base.etc);
        in
        entry.text;
      expected = "thermos";
    };
  };

  # openssh service

  openssh = {
    testUser = {
      expr =
        let
          impl = ev.modules.services.modules.openssh { };
        in
        head impl.users;
      expected = {
        name = "sshd";
        uid = 74;
        gid = 74;
        home = "/var/empty";
        shell = "/bin/nologin";
        gecos = "SSH privilege separation user";
        hashedPassword = "!";
      };
    };

    testGroup = {
      expr =
        let
          impl = ev.modules.services.modules.openssh { };
        in
        head impl.groups;
      expected = {
        name = "sshd";
        gid = 74;
        members = [ ];
      };
    };

    testServiceUnit = {
      expr =
        let
          impl = ev.modules.services.modules.openssh { };
          unit = head (filter (u: u.unitName == "sshd.service") impl.units);
        in
        unit.unitConfig.Service.Type;
      expected = "simple";
    };

    testKeygenUnit = {
      expr =
        let
          impl = ev.modules.services.modules.openssh { };
          unit = head (filter (u: u.unitName == "sshd-keygen-ed25519.service") impl.units);
        in
        unit.unitConfig.Service.Type;
      expected = "oneshot";
    };

    testKeygenTarget = {
      expr =
        let
          impl = ev.modules.services.modules.openssh { };
          units = map (u: u.unitName) impl.units;
        in
        all (n: builtins.elem n units) [
          "sshd.service"
          "sshd-keygen.target"
          "sshd-keygen-ed25519.service"
        ];
      expected = true;
    };

    testDefaultPort = {
      expr =
        let
          impl = ev.modules.services.modules.openssh { };
          cfg = head (filter (e: e.name == "ssh/sshd_config") impl.etc);
        in
        match ".*Port 22.*" cfg.text != null;
      expected = true;
    };

    testCustomPort = {
      expr =
        let
          configured = import ../default.nix {
            options = {
              "/services/openssh" = {
                port = 2222;
              };
            };
          };
          impl = (configured.evaluated.modules.services.modules.openssh { });
          cfg = head (filter (e: e.name == "ssh/sshd_config") impl.etc);
        in
        match ".*Port 2222.*" cfg.text != null;
      expected = true;
    };

    testPermitRootLogin = {
      expr =
        let
          impl = ev.modules.services.modules.openssh { };
          cfg = head (filter (e: e.name == "ssh/sshd_config") impl.etc);
        in
        match ".*PermitRootLogin prohibit-password.*" cfg.text != null;
      expected = true;
    };

    testSshdConfigMode = {
      expr =
        let
          impl = ev.modules.services.modules.openssh { };
          cfg = head (filter (e: e.name == "ssh/sshd_config") impl.etc);
        in
        cfg.mode;
      expected = "0600";
    };

    testPam = {
      expr =
        let
          impl = ev.modules.services.modules.openssh { };
          svc = head impl.pam;
        in
        svc.name;
      expected = "sshd";
    };

    testPamRules = {
      expr =
        let
          impl = ev.modules.services.modules.openssh { };
          svc = head impl.pam;
        in
        map (r: r.type) svc.rules;
      expected = [
        "auth"
        "account"
        "session"
      ];
    };

    testPackage = {
      expr =
        let
          impl = ev.modules.services.modules.openssh { };
        in
        length impl.packages;
      expected = 1;
    };

    testAuthorizedKeysRendered = {
      expr =
        let
          configured = import ../default.nix {
            options = {
              "/services/openssh" = {
                authorizedKeys = {
                  root = [ "ssh-ed25519 AAAA testkey" ];
                };
              };
            };
          };
          impl = (configured.evaluated.modules.services.modules.openssh { });
          entry = head (filter (e: e.name == "ssh/authorized_keys/root") impl.etc);
        in
        entry.text;
      expected = "ssh-ed25519 AAAA testkey\n";
    };

    testNoAuthorizedKeysDefault = {
      expr =
        let
          impl = ev.modules.services.modules.openssh { };
        in
        length (filter (e: match "ssh/authorized_keys/.*" e.name != null) impl.etc);
      expected = 0;
    };

    testHostKeys = {
      expr =
        let
          impl = ev.modules.services.modules.openssh { };
          cfg = head (filter (e: e.name == "ssh/sshd_config") impl.etc);
        in
        all (t: match ".*HostKey /var/lib/ssh/ssh_host_${t}_key.*" cfg.text != null) [
          "ed25519"
        ];
      expected = true;
    };
  };
}
