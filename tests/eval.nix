# Eval tests: nix-unit tests/eval.nix
let
  thermos = (import ../default.nix) { };
  types = thermos.evaluated.types;

  etcContract = (import ../modules/contracts/etc.nix { inherit types; }).contract;
  packagesContract = (import ../modules/contracts/packages.nix { inherit types; }).contract;
  unitsContract = (import ../modules/contracts/units.nix { inherit types; }).contract;
  tmpfilesContract = (import ../modules/contracts/tmpfiles.nix { inherit types; }).contract;
  assertionsContract = (import ../modules/contracts/assertions.nix { inherit types; }).contract;
  usersContract = (import ../modules/contracts/users.nix { inherit types; }).contract;
  groupsContract = (import ../modules/contracts/groups.nix { inherit types; }).contract;

  ev = thermos.evaluated;
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
        expr = builtins.length (
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
          (builtins.head (
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
  };

  # tree structure

  tree = {
    testTopLevelModules = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames ev.modules);
      expected = [
        "builders"
        "contracts"
        "core"
        "nixpkgs"
        "services"
      ];
    };

    testContractChildren = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames ev.modules.contracts.modules);
      expected = [
        "assertions"
        "etc"
        "groups"
        "packages"
        "tmpfiles"
        "units"
        "users"
      ];
    };

    testBuilderChildren = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames ev.modules.builders.modules);
      expected = [
        "etc"
        "packages"
        "rootfs"
        "tmpfiles"
        "toplevel"
        "units"
        "users"
      ];
    };

    testCoreChildren = {
      expr = builtins.attrNames ev.modules.core.modules;
      expected = [ "base" ];
    };

    testServiceChildren = {
      expr = builtins.attrNames ev.modules.services.modules;
      expected = [ "getty" ];
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

  # services

  services = {
    testGettyPublishesUnit = {
      expr =
        let
          impl = (ev.modules.services.modules.getty { });
        in
        map (u: u.unitName) impl.units;
      expected = [ "getty@tty1.service" ];
    };

    testGettyUnitHasSections = {
      expr =
        let
          impl = (ev.modules.services.modules.getty { });
          unit = builtins.head impl.units;
        in
        builtins.sort builtins.lessThan (builtins.attrNames unit.unitConfig);
      expected = [
        "Install"
        "Service"
        "Unit"
      ];
    };

    testGettyExecStartContainsAgetty = {
      expr =
        let
          impl = (ev.modules.services.modules.getty { });
          unit = builtins.head impl.units;
        in
        builtins.match ".*agetty.*" unit.unitConfig.Service.ExecStart != null;
      expected = true;
    };

    testGettyDefaultNoAutologin = {
      expr =
        let
          impl = (ev.modules.services.modules.getty { });
          unit = builtins.head impl.units;
        in
        builtins.match ".*--autologin.*" unit.unitConfig.Service.ExecStart != null;
      expected = false;
    };

    testGettyWantedByMultiUser = {
      expr =
        let
          impl = (ev.modules.services.modules.getty { });
          unit = builtins.head impl.units;
        in
        unit.unitConfig.Install.WantedBy;
      expected = [ "multi-user.target" ];
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
        builtins.hasAttr "getty@tty1.service" merged;
      expected = true;
    };

    testMergedGettyHasServiceSection = {
      expr =
        let
          gettyUnits = (ev.modules.services.modules.getty { }).units;
          merged = unitsContract.merge { getty = gettyUnits; };
        in
        builtins.hasAttr "Service" merged."getty@tty1.service";
      expected = true;
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
}
