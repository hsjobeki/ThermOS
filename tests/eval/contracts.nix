{ tree, ... }:
let
  types = tree.types;
  etcContract = (import ../../modules/contracts/etc.nix { inherit types; }).contract;
  packagesContract = (import ../../modules/contracts/packages.nix { inherit types; }).contract;
  unitsContract = (import ../../modules/contracts/units.nix { inherit types; }).contract;
  tmpfilesContract = (import ../../modules/contracts/tmpfiles.nix { inherit types; }).contract;
  assertionsContract = (import ../../modules/contracts/assertions.nix { inherit types; }).contract;
  usersContract = (import ../../modules/contracts/users.nix { inherit types; }).contract;
  groupsContract = (import ../../modules/contracts/groups.nix { inherit types; }).contract;
  pamContract = (import ../../modules/contracts/pam.nix { inherit types; }).contract;
  kernelModulesContract =
    (import ../../modules/contracts/kernel-modules.nix { inherit types; }).contract;
  kernelModulesOptions = tree.modules.contracts.modules."kernel-modules".options;
  inherit (builtins)
    head
    length
    map
    ;
in
{
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
  };

  "kernel-modules" = {
    testMergeDedupesTuples = {
      expr = kernelModulesContract.merge {
        a = [
          {
            name = "af_packet";
            stage = "initrd";
            mode = "force";
          }
        ];
        b = [
          {
            name = "af_packet";
            stage = "initrd";
            mode = "force";
          }
          {
            name = "loop";
            stage = "system";
            mode = "available";
          }
        ];
      };
      expected = [
        {
          name = "af_packet";
          stage = "initrd";
          mode = "force";
        }
        {
          name = "loop";
          stage = "system";
          mode = "available";
        }
      ];
    };

    testMergeKeepsSameNameAcrossCells = {
      expr = length (
        kernelModulesContract.merge {
          a = [
            {
              name = "e1000e";
              stage = "initrd";
              mode = "available";
            }
          ];
          b = [
            {
              name = "e1000e";
              stage = "system";
              mode = "force";
            }
          ];
        }
      );
      expected = 2;
    };

    testMergeAcceptsInitrdAvailable = {
      expr = length (
        kernelModulesContract.merge {
          a = [
            {
              name = "e1000e";
              stage = "initrd";
              mode = "available";
            }
          ];
        }
      );
      expected = 1;
    };

    testStageEnumRejects = {
      # unit: contracts/kernel-modules stage type: rejects a non-member
      expr = kernelModulesOptions.stage.type.verify "stage1" != null;
      expected = true;
    };

    testStageEnumAccepts = {
      # unit: contracts/kernel-modules stage type: accepts a member
      expr = kernelModulesOptions.stage.type.verify "initrd";
      expected = null;
    };

    testModeEnumRejects = {
      # unit: contracts/kernel-modules mode type: rejects a non-member
      expr = kernelModulesOptions.mode.type.verify "maybe" != null;
      expected = true;
    };

    testMergeEmpty = {
      expr = kernelModulesContract.merge { };
      expected = [ ];
    };
  };
}
